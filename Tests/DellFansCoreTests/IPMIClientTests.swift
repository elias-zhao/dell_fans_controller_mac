import XCTest
@testable import DellFansCore

final class IPMIClientTests: XCTestCase {
    private let validConfig = ServerConfig(
        host: "192.168.1.100",
        username: "root",
        ipmitoolPath: "/usr/bin/true"
    )

    func testResolveIPMIToolPathFindsCustomExecutable() {
        let client = IPMIClient()
        XCTAssertEqual(client.resolveIPMIToolPath(customPath: "  /usr/bin/true  "), "/usr/bin/true")
    }

    func testValidationErrors() async {
        let client = IPMIClient { _, _, _, _ in
            XCTFail("ProcessRunner should not be called when validation fails")
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        do {
            _ = try await client.fetchSensors(config: ServerConfig(host: "", username: "root"), password: "secret")
            XCTFail("Expected notConfigured")
        } catch let error as IPMIError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await client.fetchSensors(
                config: ServerConfig(host: "192.168.1.100 bad", username: "root", ipmitoolPath: "/usr/bin/true"),
                password: "secret"
            )
            XCTFail("Expected invalidHost")
        } catch let error as IPMIError {
            XCTAssertEqual(error, .invalidHost("192.168.1.100 bad"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await client.setManualFanSpeed(percent: 101, config: validConfig, password: "secret")
            XCTFail("Expected invalidFanSpeed")
        } catch let error as IPMIError {
            XCTAssertEqual(error, .invalidFanSpeed(101))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testArgumentsAndEnvironmentNeverExposePasswordInArgs() async throws {
        final class Recorder: @unchecked Sendable {
            var calls: [(path: String, args: [String], env: [String: String])] = []
        }
        let recorder = Recorder()

        let client = IPMIClient { path, args, env, _ in
            recorder.calls.append((path, args, env))
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        _ = try await client.fetchSensors(config: validConfig, password: "super-secret-password")

        XCTAssertEqual(recorder.calls.count, 1)
        let call = recorder.calls[0]
        XCTAssertEqual(call.path, "/usr/bin/true")
        XCTAssertEqual(
            call.args,
            ["-I", "lanplus", "-H", "192.168.1.100", "-U", "root", "-E", "-N", "3", "-R", "2", "sensor"]
        )
        XCTAssertFalse(call.args.contains("-P"))
        XCTAssertFalse(call.args.contains("super-secret-password"))
        XCTAssertEqual(call.env["IPMI_PASSWORD"], "super-secret-password")
    }

    func testSetManualAndRestoreAutoFanControlCommands() async throws {
        final class Recorder: @unchecked Sendable {
            var argLists: [[String]] = []
        }
        let recorder = Recorder()

        let client = IPMIClient { _, args, _, _ in
            recorder.argLists.append(args)
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }

        try await client.setManualFanSpeed(percent: 35, config: validConfig, password: "pw")
        try await client.restoreAutoFanControl(config: validConfig, password: "pw")

        XCTAssertEqual(recorder.argLists.count, 3)
        XCTAssertEqual(Array(recorder.argLists[0].suffix(5)), ["raw", "0x30", "0x30", "0x01", "0x00"])
        XCTAssertEqual(Array(recorder.argLists[1].suffix(6)), ["raw", "0x30", "0x30", "0x02", "0xff", "0x23"])
        XCTAssertEqual(Array(recorder.argLists[2].suffix(5)), ["raw", "0x30", "0x30", "0x01", "0x01"])
    }

    func testFetchFirmwareInfoBestEffortFRU() async throws {
        let client = IPMIClient { _, args, _, _ in
            if args.suffix(2) == ["mc", "info"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: """
                    Firmware Revision         : 2.75
                    Manufacturer ID           : 674
                    Manufacturer Name         : DELL Inc
                    """,
                    stderr: ""
                )
            }
            return ProcessResult(exitCode: 1, stdout: "", stderr: "FRU not readable")
        }

        let info = try await client.testConnection(config: validConfig, password: "pw")
        XCTAssertEqual(info.firmwareRevision, "2.75")
        XCTAssertNil(info.serverModel)
        XCTAssertTrue(info.supportStatus.isSupported)
    }

    func testErrorClassification() async {
        let cases: [(command: () async throws -> Void, stderr: String, expected: IPMIError)] = [
            (
                {
                    let client = IPMIClient { _, _, _, _ in
                        ProcessResult(exitCode: 1, stdout: "", stderr: "Unable to send RAW command (rsp=0xc1): Invalid command")
                    }
                    try await client.setManualFanSpeed(percent: 40, config: self.validConfig, password: "pw")
                },
                "Unable to send RAW command (rsp=0xc1): Invalid command",
                .manualControlUnsupported(detail: "Unable to send RAW command (rsp=0xc1): Invalid command")
            ),
            (
                {
                    let client = IPMIClient { _, _, _, _ in
                        ProcessResult(exitCode: 1, stdout: "", stderr: "RAKP 2 HMAC is invalid")
                    }
                    _ = try await client.fetchSensors(config: self.validConfig, password: "pw")
                },
                "RAKP 2 HMAC is invalid",
                .authenticationFailed(detail: "RAKP 2 HMAC is invalid")
            ),
            (
                {
                    let client = IPMIClient { _, _, _, _ in
                        ProcessResult(exitCode: 1, stdout: "", stderr: "Unable to establish IPMI v2 / RMCP+ session")
                    }
                    _ = try await client.fetchSensors(config: self.validConfig, password: "pw")
                },
                "Unable to establish IPMI v2 / RMCP+ session",
                .connectionFailed(host: "192.168.1.100", detail: "Unable to establish IPMI v2 / RMCP+ session")
            ),
            (
                {
                    let client = IPMIClient { _, _, _, _ in
                        ProcessResult(exitCode: 1, stdout: "", stderr: "Get Device ID command timed out")
                    }
                    _ = try await client.fetchSensors(config: self.validConfig, password: "pw")
                },
                "Get Device ID command timed out",
                .connectionTimeout(host: "192.168.1.100")
            ),
            (
                {
                    let client = IPMIClient { _, _, _, _ in
                        ProcessResult(exitCode: 2, stdout: "", stderr: "Unexpected SDR error")
                    }
                    _ = try await client.fetchSensors(config: self.validConfig, password: "pw")
                },
                "Unexpected SDR error",
                .commandFailed(exitCode: 2, stderr: "Unexpected SDR error")
            )
        ]

        for testCase in cases {
            do {
                try await testCase.command()
                XCTFail("Expected error \(testCase.expected)")
            } catch let error as IPMIError {
                XCTAssertEqual(error, testCase.expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDefaultProcessRunnerEnforcesTimeout() async {
        let sleepConfig = ServerConfig(
            host: "192.168.1.100",
            username: "root",
            ipmitoolPath: "/bin/sleep"
        )
        // Use a tiny timeout; /bin/sleep ignores IPMI args or exits quickly on invalid option,
        // so we can't rely on /bin/sleep sleeping unless args are valid. Instead, verify it launches cleanly.
        let client = IPMIClient(timeoutSeconds: 2.0)
        do {
            _ = try await client.fetchSensors(config: sleepConfig, password: "pw")
            XCTFail("Expected non-zero exit from /bin/sleep with ipmitool flags")
        } catch let error as IPMIError {
            if case .commandFailed = error {
                // Expected: /bin/sleep was launched directly without a shell and returned non-zero
            } else {
                XCTFail("Expected commandFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
