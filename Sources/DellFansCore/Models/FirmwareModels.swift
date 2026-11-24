import Foundation

public enum FirmwareSupportStatus: Equatable, Sendable {
    case supported(reason: String)
    case unsupported(reason: String)
    case warning(reason: String)
    case unknown(reason: String)

    public var isUnsupported: Bool {
        if case .unsupported = self {
            return true
        }
        return false
    }

    public var isSupported: Bool {
        if case .supported = self {
            return true
        }
        return false
    }

    public var message: String {
        switch self {
        case .supported(let reason),
             .unsupported(let reason),
             .warning(let reason),
             .unknown(let reason):
            return reason
        }
    }
}

public struct FirmwareInfo: Equatable, Sendable {
    public let firmwareRevision: String
    public let rawFirmwareRevision: String
    public let auxFirmwareRevision: String?
    public let manufacturerID: Int?
    public let manufacturerName: String?
    public let productID: Int?
    public let serverModel: String?
    public let supportStatus: FirmwareSupportStatus

    public init(
        firmwareRevision: String,
        rawFirmwareRevision: String,
        auxFirmwareRevision: String? = nil,
        manufacturerID: Int? = nil,
        manufacturerName: String? = nil,
        productID: Int? = nil,
        serverModel: String? = nil,
        supportStatus: FirmwareSupportStatus
    ) {
        self.firmwareRevision = firmwareRevision
        self.rawFirmwareRevision = rawFirmwareRevision
        self.auxFirmwareRevision = auxFirmwareRevision
        self.manufacturerID = manufacturerID
        self.manufacturerName = manufacturerName
        self.productID = productID
        self.serverModel = serverModel
        self.supportStatus = supportStatus
    }
}
