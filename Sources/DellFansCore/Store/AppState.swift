import Combine
import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum ConnectionStatus: Equatable, Sendable {
    case unconfigured
    case idle
    case connecting
    case online
    case offline(String)

    public var displayText: String {
        switch self {
        case .unconfigured:
            return "未配置"
        case .idle:
            return "待连接"
        case .connecting:
            return "连接中..."
        case .online:
            return "在线"
        case .offline(let reason):
            return reason.isEmpty ? "离线" : "离线：\(reason)"
        }
    }

    public var isOnline: Bool {
        if case .online = self {
            return true
        }
        return false
    }
}

public enum FanControlMode: Equatable, Sendable {
    case unknown
    case automatic
    case manual(percent: Int)

    public var displayText: String {
        switch self {
        case .unknown:
            return "未记录"
        case .automatic:
            return "自动 (iDRAC)"
        case .manual(let percent):
            return "手动 \(percent)%"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var config: ServerConfig
    @Published public var password: String
    @Published public var connectionStatus: ConnectionStatus
    @Published public var firmwareInfo: FirmwareInfo?
    @Published public var sensors: [SensorReading]
    @Published public var sensorSummary: SensorSummary
    @Published public var fanSpeedPercent: Double
    @Published public var fanControlMode: FanControlMode
    @Published public var isRefreshing: Bool
    @Published public var isApplyingFanSpeed: Bool
    @Published public var isTestingConnection: Bool
    @Published public var lastUpdated: Date?
    @Published public var lastError: String?
    @Published public var statusMessage: String?
    @Published public var autoRefreshEnabled: Bool {
        didSet {
            guard !isInitializing else { return }
            userDefaults.set(autoRefreshEnabled, forKey: DefaultsKey.autoRefreshEnabled)
            if autoRefreshEnabled && config.isConfigured {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }

    private let client: IPMIClientProtocol
    private let passwordStore: PasswordStoreProtocol
    private let userDefaults: UserDefaults
    private var autoRefreshTask: Task<Void, Never>?
    private var postApplyRefreshTask: Task<Void, Never>?
    private var isInitializing = true

    private enum DefaultsKey {
        static let host = "dellfans.server.host"
        static let username = "dellfans.server.username"
        static let refreshIntervalSeconds = "dellfans.server.refreshIntervalSeconds"
        static let ipmitoolPath = "dellfans.server.ipmitoolPath"
        static let autoRefreshEnabled = "dellfans.server.autoRefreshEnabled"
        static let fanSpeedPercent = "dellfans.fan.speedPercent"
        static let fanControlModeType = "dellfans.fan.controlModeType"
        static let fanControlManualPercent = "dellfans.fan.controlManualPercent"
    }

    private static let keychainAccount = "default"
    private static let minRefreshInterval = 3
    private static let maxRefreshInterval = 3600

    public init(
        client: IPMIClientProtocol = IPMIClient(),
        passwordStore: PasswordStoreProtocol = KeychainHelper(),
        userDefaults: UserDefaults = .standard,
        startAutoRefreshImmediately: Bool = true
    ) {
        self.client = client
        self.passwordStore = passwordStore
        self.userDefaults = userDefaults

        let host = userDefaults.string(forKey: DefaultsKey.host) ?? ""
        let username = userDefaults.string(forKey: DefaultsKey.username) ?? "root"
        let rawInterval: Int
        if userDefaults.object(forKey: DefaultsKey.refreshIntervalSeconds) != nil {
            rawInterval = userDefaults.integer(forKey: DefaultsKey.refreshIntervalSeconds)
        } else {
            rawInterval = 10
        }
        let interval = Self.clampedInterval(rawInterval)
        let ipmitoolPath = userDefaults.string(forKey: DefaultsKey.ipmitoolPath) ?? ""

        let loadedConfig = ServerConfig(
            host: host,
            username: username,
            refreshIntervalSeconds: interval,
            ipmitoolPath: ipmitoolPath
        )

        let loadedAutoRefresh: Bool
        if userDefaults.object(forKey: DefaultsKey.autoRefreshEnabled) != nil {
            loadedAutoRefresh = userDefaults.bool(forKey: DefaultsKey.autoRefreshEnabled)
        } else {
            loadedAutoRefresh = true
        }

        let loadedPassword: String
        do {
            loadedPassword = try passwordStore.loadPassword(account: Self.keychainAccount) ?? ""
        } catch {
            loadedPassword = ""
        }

        let loadedMode: FanControlMode
        switch userDefaults.string(forKey: DefaultsKey.fanControlModeType) {
        case "automatic":
            loadedMode = .automatic
        case "manual":
            let savedPercent = userDefaults.object(forKey: DefaultsKey.fanControlManualPercent) != nil
                ? userDefaults.integer(forKey: DefaultsKey.fanControlManualPercent)
                : 30
            loadedMode = .manual(percent: min(max(savedPercent, 5), 100))
        default:
            loadedMode = .unknown
        }

        let loadedFanSpeedPercent: Double
        if userDefaults.object(forKey: DefaultsKey.fanSpeedPercent) != nil {
            let stored = userDefaults.double(forKey: DefaultsKey.fanSpeedPercent)
            loadedFanSpeedPercent = min(max(stored.rounded(), 5), 100)
        } else if case .manual(let percent) = loadedMode {
            loadedFanSpeedPercent = Double(percent)
        } else {
            loadedFanSpeedPercent = 30
        }

        self.config = loadedConfig
        self.password = loadedPassword
        self.connectionStatus = loadedConfig.isConfigured ? .idle : .unconfigured
        self.firmwareInfo = nil
        self.sensors = []
        self.sensorSummary = .empty
        self.fanSpeedPercent = loadedFanSpeedPercent
        self.fanControlMode = loadedConfig.isConfigured ? loadedMode : .unknown
        self.isRefreshing = false
        self.isApplyingFanSpeed = false
        self.isTestingConnection = false
        self.lastUpdated = nil
        self.lastError = nil
        self.statusMessage = nil
        self.autoRefreshEnabled = loadedAutoRefresh
        self.isInitializing = false

        if startAutoRefreshImmediately && loadedConfig.isConfigured && loadedAutoRefresh {
            startAutoRefresh()
        }
    }

    deinit {
        autoRefreshTask?.cancel()
        postApplyRefreshTask?.cancel()
    }

    // MARK: - Computed Properties

    public var serverDisplayTitle: String {
        let host = config.trimmedHost
        if let model = firmwareInfo?.serverModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            return host.isEmpty ? model : "\(model) · \(host)"
        }
        return host.isEmpty ? "未配置服务器" : host
    }

    public var menuBarLabelText: String {
        config.isConfigured ? sensorSummary.menuBarTemperatureText : "iDRAC"
    }

    public var isFirmwareUnsupported: Bool {
        firmwareInfo?.supportStatus.isUnsupported ?? false
    }

    public var detectedIPMIToolPath: String? {
        client.resolveIPMIToolPath(customPath: config.ipmitoolPath)
    }

    // MARK: - Auto Refresh

    public func startAutoRefresh() {
        stopAutoRefresh()
        guard config.isConfigured, autoRefreshEnabled else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshSensors()
                let interval = Self.clampedInterval(self.config.refreshIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    public func setAutoRefresh(enabled: Bool) {
        if autoRefreshEnabled != enabled {
            autoRefreshEnabled = enabled
        } else {
            userDefaults.set(enabled, forKey: DefaultsKey.autoRefreshEnabled)
            if enabled && config.isConfigured {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }

    public func updateRefreshInterval(_ seconds: Int) {
        let clamped = Self.clampedInterval(seconds)
        config.refreshIntervalSeconds = clamped
        userDefaults.set(clamped, forKey: DefaultsKey.refreshIntervalSeconds)
        if autoRefreshEnabled && config.isConfigured {
            startAutoRefresh()
        }
    }

    // MARK: - Actions

    public func saveConnectionSettings(
        host: String,
        username: String,
        password: String,
        refreshInterval: Int,
        ipmitoolPath: String
    ) {
        let previousHost = config.trimmedHost
        let clampedInterval = Self.clampedInterval(refreshInterval)

        config = ServerConfig(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            refreshIntervalSeconds: clampedInterval,
            ipmitoolPath: ipmitoolPath.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        self.password = password

        userDefaults.set(config.host, forKey: DefaultsKey.host)
        userDefaults.set(config.username, forKey: DefaultsKey.username)
        userDefaults.set(config.refreshIntervalSeconds, forKey: DefaultsKey.refreshIntervalSeconds)
        userDefaults.set(config.ipmitoolPath, forKey: DefaultsKey.ipmitoolPath)

        do {
            try passwordStore.savePassword(password, account: Self.keychainAccount)
        } catch {
            lastError = error.localizedDescription
        }

        if !config.isConfigured {
            connectionStatus = .unconfigured
            firmwareInfo = nil
            fanControlMode = .unknown
            persistFanState()
            stopAutoRefresh()
        } else {
            let hostChanged = previousHost != config.trimmedHost
            if hostChanged || connectionStatus == .unconfigured {
                connectionStatus = .idle
                if hostChanged {
                    firmwareInfo = nil
                    fanControlMode = .unknown
                    persistFanState()
                }
            }
            if autoRefreshEnabled {
                startAutoRefresh()
            }
        }

        statusMessage = "已保存连接设置"
    }

    public func testConnection() async {
        guard config.isConfigured else {
            connectionStatus = .unconfigured
            lastError = IPMIError.notConfigured.localizedDescription
            return
        }
        guard !isTestingConnection else { return }

        isTestingConnection = true
        connectionStatus = .connecting
        lastError = nil
        statusMessage = nil
        defer { isTestingConnection = false }

        do {
            let info = try await client.testConnection(config: config, password: password)
            firmwareInfo = info
            connectionStatus = .online
            if info.supportStatus.isUnsupported {
                statusMessage = "连接成功，但固件不支持手动调速：\(info.supportStatus.message)"
            } else {
                let targetName = info.serverModel ?? config.trimmedHost
                statusMessage = "连接成功：\(targetName) (iDRAC \(info.firmwareRevision))"
            }
        } catch {
            let message = error.localizedDescription
            connectionStatus = .offline(message)
            lastError = message
        }
    }

    public func refreshSensors() async {
        guard config.isConfigured else {
            connectionStatus = .unconfigured
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        if connectionStatus == .idle || connectionStatus == .unconfigured {
            connectionStatus = .connecting
        }
        defer { isRefreshing = false }

        do {
            let readings = try await client.fetchSensors(config: config, password: password)
            sensors = readings
            sensorSummary = SensorParser.summarize(readings)
            lastUpdated = Date()
            connectionStatus = .online
            lastError = nil

            if firmwareInfo == nil {
                if let info = try? await client.fetchFirmwareInfo(config: config, password: password) {
                    firmwareInfo = info
                }
            }
        } catch {
            let message = error.localizedDescription
            connectionStatus = .offline(message)
            lastError = message
        }
    }

    public func applyFanSpeed() async {
        guard config.isConfigured else {
            lastError = IPMIError.notConfigured.localizedDescription
            return
        }
        guard !isApplyingFanSpeed else { return }

        let targetPercent = Int(fanSpeedPercent.rounded())
        isApplyingFanSpeed = true
        lastError = nil
        statusMessage = nil
        defer { isApplyingFanSpeed = false }

        do {
            try await client.setManualFanSpeed(
                percent: targetPercent,
                config: config,
                password: password
            )
            fanSpeedPercent = Double(targetPercent)
            fanControlMode = .manual(percent: targetPercent)
            persistFanState()
            statusMessage = "已设置手动风扇转速为 \(targetPercent)%"
            schedulePostApplySensorRefresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func restoreAutoFanControl() async {
        guard config.isConfigured else {
            lastError = IPMIError.notConfigured.localizedDescription
            return
        }
        guard !isApplyingFanSpeed else { return }

        isApplyingFanSpeed = true
        lastError = nil
        statusMessage = nil
        defer { isApplyingFanSpeed = false }

        do {
            try await client.restoreAutoFanControl(config: config, password: password)
            fanControlMode = .automatic
            persistFanState()
            statusMessage = "已恢复 iDRAC 自动风扇控制"
            schedulePostApplySensorRefresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func openWebConsole() {
        guard let url = config.webConsoleURL else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    public func clearError() {
        lastError = nil
    }

    private func persistFanState() {
        userDefaults.set(fanSpeedPercent.rounded(), forKey: DefaultsKey.fanSpeedPercent)
        switch fanControlMode {
        case .unknown:
            userDefaults.set("unknown", forKey: DefaultsKey.fanControlModeType)
            userDefaults.removeObject(forKey: DefaultsKey.fanControlManualPercent)
        case .automatic:
            userDefaults.set("automatic", forKey: DefaultsKey.fanControlModeType)
            userDefaults.removeObject(forKey: DefaultsKey.fanControlManualPercent)
        case .manual(let percent):
            userDefaults.set("manual", forKey: DefaultsKey.fanControlModeType)
            userDefaults.set(percent, forKey: DefaultsKey.fanControlManualPercent)
        }
    }

    private func schedulePostApplySensorRefresh() {
        guard autoRefreshEnabled || connectionStatus.isOnline else { return }
        postApplyRefreshTask?.cancel()
        postApplyRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refreshSensors()
        }
    }

    private static func clampedInterval(_ seconds: Int) -> Int {
        min(max(seconds, minRefreshInterval), maxRefreshInterval)
    }
}
