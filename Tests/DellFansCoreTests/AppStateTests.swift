import Foundation
import XCTest
@testable import DellFansCore

final class InMemoryPasswordStore: PasswordStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func savePassword(_ password: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if password.isEmpty {
            storage.removeValue(forKey: account)
        } else {
            storage[account] = password
        }
    }

    func loadPassword(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[account]
    }

    func deletePassword(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: account)
    }
}

final class MockIPMIClient: IPMIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()

    var detectedPath: String? = "/opt/homebrew/bin/ipmitool"
    var testConnectionResult: Result<FirmwareInfo, Error> = .success(
        FirmwareInfo(
            firmwareRevision: "2.86.86.86",
            rawFirmwareRevision: "2.86",
            serverModel: "PowerEdge R730",
            supportStatus: .supported(reason: "iDRAC8 支持手动调速")
        )
    )
    var fetchSensorsResult: Result<[SensorReading], Error> = .success([])
    var fetchFirmwareResult: Result<FirmwareInfo, Error> = .success(
        FirmwareInfo(
            firmwareRevision: "2.86.86.86",
            rawFirmwareRevision: "2.86",
            serverModel: "PowerEdge R730",
            supportStatus: .supported(reason: "iDRAC8 支持手动调速")
        )
    )
    var setManualFanSpeedError: Error?
    var restoreAutoFanControlError: Error?

    private(set) var lastManualPercent: Int?
    private(set) var restoreAutoCallCount = 0

    func resolveIPMIToolPath(customPath: String) -> String? {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? detectedPath : trimmed
    }

    func testConnection(config: ServerConfig, password: String) async throws -> FirmwareInfo {
        try testConnectionResult.get()
    }

    func fetchSensors(config: ServerConfig, password: String) async throws -> [SensorReading] {
        try fetchSensorsResult.get()
    }

    func fetchFirmwareInfo(config: ServerConfig, password: String) async throws -> FirmwareInfo {
        try fetchFirmwareResult.get()
    }

    func setManualFanSpeed(percent: Int, config: ServerConfig, password: String) async throws {
        if let error = setManualFanSpeedError {
            throw error
        }
        lock.withLock {
            lastManualPercent = percent
        }
    }

    func restoreAutoFanControl(config: ServerConfig, password: String) async throws {
        if let error = restoreAutoFanControlError {
            throw error
        }
        lock.withLock {
            restoreAutoCallCount += 1
        }
    }
}

final class AppStateTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var passwordStore: InMemoryPasswordStore!
    private var mockClient: MockIPMIClient!

    override func setUp() {
        super.setUp()
        suiteName = "AppStateTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        passwordStore = InMemoryPasswordStore()
        mockClient = MockIPMIClient()
    }

    override func tearDown() {
        if let suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        userDefaults = nil
        passwordStore = nil
        mockClient = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    private func makeAppState() -> AppState {
        AppState(
            client: mockClient,
            passwordStore: passwordStore,
            userDefaults: userDefaults,
            startAutoRefreshImmediately: false
        )
    }

    @MainActor
    func testSaveAndReloadConnectionSettings() throws {
        let state = makeAppState()
        XCTAssertEqual(state.connectionStatus, .unconfigured)
        XCTAssertFalse(state.config.isConfigured)

        state.saveConnectionSettings(
            host: "192.168.10.50",
            username: "admin",
            password: "secret-password",
            refreshInterval: 15,
            ipmitoolPath: "/usr/local/bin/ipmitool"
        )

        XCTAssertEqual(state.connectionStatus, .idle)
        XCTAssertTrue(state.config.isConfigured)
        XCTAssertEqual(state.config.trimmedHost, "192.168.10.50")
        XCTAssertEqual(state.config.trimmedUsername, "admin")
        XCTAssertEqual(state.config.refreshIntervalSeconds, 15)
        XCTAssertEqual(state.password, "secret-password")
        XCTAssertEqual(try passwordStore.loadPassword(account: "default"), "secret-password")

        let reloaded = makeAppState()
        XCTAssertEqual(reloaded.connectionStatus, .idle)
        XCTAssertEqual(reloaded.config.host, "192.168.10.50")
        XCTAssertEqual(reloaded.config.username, "admin")
        XCTAssertEqual(reloaded.config.refreshIntervalSeconds, 15)
        XCTAssertEqual(reloaded.config.ipmitoolPath, "/usr/local/bin/ipmitool")
        XCTAssertEqual(reloaded.password, "secret-password")
    }

    @MainActor
    func testTestConnectionSuccessAndUnsupportedFirmware() async {
        let state = makeAppState()
        state.saveConnectionSettings(
            host: "10.0.0.12",
            username: "root",
            password: "calvin",
            refreshInterval: 10,
            ipmitoolPath: ""
        )

        let unsupportedFirmware = FirmwareInfo(
            firmwareRevision: "7.00.00.00",
            rawFirmwareRevision: "7.00",
            serverModel: "PowerEdge R750",
            supportStatus: .unsupported(reason: "iDRAC9 ≥ 3.34.34.34 已封禁手动调速")
        )
        mockClient.testConnectionResult = .success(unsupportedFirmware)

        await state.testConnection()

        XCTAssertTrue(state.connectionStatus.isOnline)
        XCTAssertEqual(state.firmwareInfo, unsupportedFirmware)
        XCTAssertTrue(state.isFirmwareUnsupported)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(state.serverDisplayTitle, "PowerEdge R750 · 10.0.0.12")
    }

    @MainActor
    func testTestConnectionFailure() async {
        let state = makeAppState()
        state.saveConnectionSettings(
            host: "10.0.0.12",
            username: "root",
            password: "wrong",
            refreshInterval: 10,
            ipmitoolPath: ""
        )

        mockClient.testConnectionResult = .failure(IPMIError.authenticationFailed(detail: "Invalid user"))

        await state.testConnection()

        XCTAssertFalse(state.connectionStatus.isOnline)
        if case .offline(let reason) = state.connectionStatus {
            XCTAssertTrue(reason.contains("认证失败"))
        } else {
            XCTFail("Expected offline status, got \(state.connectionStatus)")
        }
        XCTAssertNotNil(state.lastError)

        state.clearError()
        XCTAssertNil(state.lastError)
    }

    @MainActor
    func testRefreshSensorsUpdatesSummaryAndStatus() async {
        let state = makeAppState()
        state.saveConnectionSettings(
            host: "192.168.1.100",
            username: "root",
            password: "calvin",
            refreshInterval: 10,
            ipmitoolPath: ""
        )

        let sampleReadings: [SensorReading] = [
            SensorReading(
                id: "Inlet Temp",
                name: "Inlet Temp",
                displayName: "进风口温度",
                numericValue: 24,
                rawValue: "24",
                unit: "°C",
                rawUnit: "degrees C",
                status: .ok,
                rawStatus: "ok",
                category: .temperature
            ),
            SensorReading(
                id: "CPU1 Temp",
                name: "CPU1 Temp",
                displayName: "CPU 1 温度",
                numericValue: 52,
                rawValue: "52",
                unit: "°C",
                rawUnit: "degrees C",
                status: .ok,
                rawStatus: "ok",
                category: .temperature
            ),
            SensorReading(
                id: "Fan1",
                name: "Fan1",
                displayName: "风扇 1",
                numericValue: 3600,
                rawValue: "3600",
                unit: "RPM",
                rawUnit: "RPM",
                status: .ok,
                rawStatus: "ok",
                category: .fan
            ),
            SensorReading(
                id: "Pwr Consumption",
                name: "Pwr Consumption",
                displayName: "整机功耗",
                numericValue: 140,
                rawValue: "140",
                unit: "W",
                rawUnit: "Watts",
                status: .ok,
                rawStatus: "ok",
                category: .power
            )
        ]
        mockClient.fetchSensorsResult = .success(sampleReadings)

        await state.refreshSensors()

        XCTAssertTrue(state.connectionStatus.isOnline)
        XCTAssertEqual(state.sensors.count, 4)
        XCTAssertNotNil(state.lastUpdated)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(state.sensorSummary.inletTemperature, 24)
        XCTAssertEqual(state.sensorSummary.averageFanRPM, 3600)
        XCTAssertEqual(state.sensorSummary.powerWatts, 140)
        XCTAssertNotEqual(state.menuBarLabelText, "iDRAC")
    }

    @MainActor
    func testApplyFanSpeedAndRestoreAutoFanControl() async {
        let state = makeAppState()
        state.saveConnectionSettings(
            host: "192.168.1.100",
            username: "root",
            password: "calvin",
            refreshInterval: 10,
            ipmitoolPath: ""
        )

        state.fanSpeedPercent = 45
        await state.applyFanSpeed()

        XCTAssertEqual(state.fanControlMode, .manual(percent: 45))
        XCTAssertEqual(mockClient.lastManualPercent, 45)
        XCTAssertNil(state.lastError)

        mockClient.restoreAutoFanControlError = IPMIError.connectionTimeout(host: "192.168.1.100")
        await state.restoreAutoFanControl()

        XCTAssertEqual(state.fanControlMode, .manual(percent: 45))
        XCTAssertNotNil(state.lastError)

        mockClient.restoreAutoFanControlError = nil
        await state.restoreAutoFanControl()

        XCTAssertEqual(state.fanControlMode, .automatic)
        XCTAssertEqual(mockClient.restoreAutoCallCount, 1)
        XCTAssertNil(state.lastError)
    }

    @MainActor
    func testServerDisplayTitleAndIntervalClamping() {
        let state = makeAppState()
        XCTAssertEqual(state.serverDisplayTitle, "未配置服务器")
        XCTAssertEqual(state.menuBarLabelText, "iDRAC")

        state.saveConnectionSettings(
            host: "https://idrac.example.local/",
            username: "root",
            password: "pw",
            refreshInterval: 1,
            ipmitoolPath: ""
        )

        XCTAssertEqual(state.config.refreshIntervalSeconds, 3)
        XCTAssertEqual(state.serverDisplayTitle, "idrac.example.local")

        state.updateRefreshInterval(9999)
        XCTAssertEqual(state.config.refreshIntervalSeconds, 3600)

        state.firmwareInfo = FirmwareInfo(
            firmwareRevision: "2.86.86.86",
            rawFirmwareRevision: "2.86",
            serverModel: "PowerEdge R730xd",
            supportStatus: .supported(reason: "OK")
        )
        XCTAssertEqual(state.serverDisplayTitle, "PowerEdge R730xd · idrac.example.local")
    }

    @MainActor
    func testFanControlStatePersistenceAndResetOnHostChange() async {
        let state = makeAppState()
        state.saveConnectionSettings(
            host: "192.168.1.250",
            username: "root",
            password: "calvin",
            refreshInterval: 10,
            ipmitoolPath: ""
        )

        state.fanSpeedPercent = 20
        await state.applyFanSpeed()
        XCTAssertEqual(state.fanControlMode, .manual(percent: 20))

        let reloaded = makeAppState()
        XCTAssertEqual(reloaded.fanControlMode, .manual(percent: 20))
        XCTAssertEqual(reloaded.fanSpeedPercent, 20)

        await reloaded.restoreAutoFanControl()
        XCTAssertEqual(reloaded.fanControlMode, .automatic)

        let reloadedAuto = makeAppState()
        XCTAssertEqual(reloadedAuto.fanControlMode, .automatic)
        XCTAssertEqual(reloadedAuto.fanSpeedPercent, 20)

        reloadedAuto.saveConnectionSettings(
            host: "192.168.1.251",
            username: "root",
            password: "calvin",
            refreshInterval: 10,
            ipmitoolPath: ""
        )
        XCTAssertEqual(reloadedAuto.fanControlMode, .unknown)
    }
}
