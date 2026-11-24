import Foundation

public protocol IPMIClientProtocol: Sendable {
    func resolveIPMIToolPath(customPath: String) -> String?
    func testConnection(config: ServerConfig, password: String) async throws -> FirmwareInfo
    func fetchSensors(config: ServerConfig, password: String) async throws -> [SensorReading]
    func fetchFirmwareInfo(config: ServerConfig, password: String) async throws -> FirmwareInfo
    func setManualFanSpeed(percent: Int, config: ServerConfig, password: String) async throws
    func restoreAutoFanControl(config: ServerConfig, password: String) async throws
}

public protocol PasswordStoreProtocol: Sendable {
    func savePassword(_ password: String, account: String) throws
    func loadPassword(account: String) throws -> String?
    func deletePassword(account: String) throws
}
