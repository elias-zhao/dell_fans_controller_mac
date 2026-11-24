import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public typealias ProcessRunner = @Sendable (
    _ executablePath: String,
    _ arguments: [String],
    _ environment: [String: String],
    _ timeoutSeconds: TimeInterval
) async throws -> ProcessResult

public final class IPMIClient: IPMIClientProtocol, Sendable {
    private let processRunner: ProcessRunner
    private let timeoutSeconds: TimeInterval

    public init(processRunner: ProcessRunner? = nil, timeoutSeconds: TimeInterval = 15) {
        self.processRunner = processRunner ?? IPMIClient.defaultProcessRunner
        self.timeoutSeconds = timeoutSeconds
    }

    public func resolveIPMIToolPath(customPath: String) -> String? {
        for candidate in candidateIPMIToolPaths(customPath: customPath) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public func testConnection(config: ServerConfig, password: String) async throws -> FirmwareInfo {
        try await fetchFirmwareInfo(config: config, password: password)
    }

    public func fetchSensors(config: ServerConfig, password: String) async throws -> [SensorReading] {
        let result = try await runIPMICommand(["sensor"], config: config, password: password)
        return SensorParser.parse(result.stdout)
    }

    public func fetchFirmwareInfo(config: ServerConfig, password: String) async throws -> FirmwareInfo {
        let mcResult = try await runIPMICommand(["mc", "info"], config: config, password: password)
        let fruResult = try? await runIPMICommand(["fru", "print", "0"], config: config, password: password)
        let serverModel = fruResult.flatMap { FirmwareCheck.parseServerModel(fromFRU: $0.stdout) }
        return FirmwareCheck.parseMCInfo(mcResult.stdout, serverModel: serverModel)
    }

    public func setManualFanSpeed(percent: Int, config: ServerConfig, password: String) async throws {
        guard (0...100).contains(percent) else {
            throw IPMIError.invalidFanSpeed(percent)
        }
        _ = try await runIPMICommand(["raw", "0x30", "0x30", "0x01", "0x00"], config: config, password: password)
        let hexByte = String(format: "0x%02x", percent)
        _ = try await runIPMICommand(["raw", "0x30", "0x30", "0x02", "0xff", hexByte], config: config, password: password)
    }

    public func restoreAutoFanControl(config: ServerConfig, password: String) async throws {
        _ = try await runIPMICommand(["raw", "0x30", "0x30", "0x01", "0x01"], config: config, password: password)
    }

    // MARK: - Private Helpers

    private func candidateIPMIToolPaths(customPath: String) -> [String] {
        var candidates: [String] = []
        let trimmedCustom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            candidates.append(trimmedCustom)
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/ipmitool",
            "/usr/local/bin/ipmitool",
            "/usr/bin/ipmitool"
        ])

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let pathDir = String(dir).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !pathDir.isEmpty else { continue }
                let fullPath = (pathDir as NSString).appendingPathComponent("ipmitool")
                candidates.append(fullPath)
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private func runIPMICommand(
        _ commandArgs: [String],
        config: ServerConfig,
        password: String
    ) async throws -> ProcessResult {
        let host = config.trimmedHost
        let username = config.trimmedUsername

        guard !host.isEmpty, !username.isEmpty, !password.isEmpty else {
            throw IPMIError.notConfigured
        }

        if host.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            throw IPMIError.invalidHost(host)
        }

        let searchedPaths = candidateIPMIToolPaths(customPath: config.ipmitoolPath)
        guard let ipmitoolPath = resolveIPMIToolPath(customPath: config.ipmitoolPath) else {
            throw IPMIError.ipmitoolNotFound(searchedPaths: searchedPaths)
        }

        let arguments = [
            "-I", "lanplus",
            "-H", host,
            "-U", username,
            "-E",
            "-N", "3",
            "-R", "2"
        ] + commandArgs

        let environment = ["IPMI_PASSWORD": password]
        let result: ProcessResult
        do {
            result = try await processRunner(ipmitoolPath, arguments, environment, timeoutSeconds)
        } catch let error as IPMIError {
            throw error
        } catch is ProcessTimeoutError {
            throw IPMIError.connectionTimeout(host: host)
        } catch {
            throw IPMIError.processLaunchFailed(detail: error.localizedDescription)
        }

        if result.exitCode != 0 {
            throw classifyError(result: result, commandArgs: commandArgs, host: host)
        }

        return result
    }

    private func classifyError(result: ProcessResult, commandArgs: [String], host: String) -> IPMIError {
        let rawDetail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = rawDetail.isEmpty ? "退出码 \(result.exitCode)" : rawDetail
        let lower = (result.stderr + "\n" + result.stdout).lowercased()

        let isRawFanCommand = commandArgs.count >= 3
            && commandArgs[0] == "raw"
            && commandArgs[1] == "0x30"
            && commandArgs[2] == "0x30"

        if isRawFanCommand {
            let unsupportedIndicators = [
                "0xc1",
                "invalid command",
                "rsp=0xc1",
                "rsp=0xd5",
                "rsp=0xc9",
                "not supported",
                "disabled"
            ]
            if unsupportedIndicators.contains(where: { lower.contains($0) }) {
                return .manualControlUnsupported(detail: detail)
            }
        }

        let authIndicators = [
            "invalid user",
            "unauthorized",
            "password",
            "authentication",
            "rakp 2 hmac",
            "insufficient privilege"
        ]
        if authIndicators.contains(where: { lower.contains($0) }) {
            return .authenticationFailed(detail: detail)
        }

        if lower.contains("timed out") || lower.contains("timeout") {
            return .connectionTimeout(host: host)
        }

        let connectionIndicators = [
            "unable to establish ipmi",
            "no response",
            "connection refused",
            "network is unreachable",
            "no route to host",
            "could not open",
            "getaddrinfo"
        ]
        if connectionIndicators.contains(where: { lower.contains($0) }) {
            return .connectionFailed(host: host, detail: detail)
        }

        return .commandFailed(exitCode: result.exitCode, stderr: detail)
    }

    private static let defaultProcessRunner: ProcessRunner = { executablePath, arguments, environment, timeoutSeconds in
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            var mergedEnv = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                mergedEnv[key] = value
            }
            process.environment = mergedEnv

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            final class State: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                var stdoutData = Data()
                var stderrData = Data()

                func tryResume() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if resumed { return false }
                    resumed = true
                    return true
                }
            }

            let state = State()
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                if state.tryResume() {
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(throwing: ProcessTimeoutError())
                }
            }
            timer.resume()

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    timer.cancel()
                    if state.tryResume() {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                let ioGroup = DispatchGroup()

                ioGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    state.stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    ioGroup.leave()
                }

                ioGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    state.stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    ioGroup.leave()
                }

                ioGroup.wait()
                process.waitUntilExit()
                timer.cancel()

                if state.tryResume() {
                    let stdout = String(data: state.stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: state.stderrData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }
        }
    }
}

private struct ProcessTimeoutError: Error {}
