import Foundation

public enum SensorCategory: String, CaseIterable, Identifiable, Sendable {
    case temperature = "温度"
    case fan = "风扇"
    case voltage = "电压"
    case current = "电流"
    case power = "功耗"
    case other = "其他"

    public var id: String { rawValue }
}

public enum SensorStatus: String, Sendable, Equatable {
    case ok
    case nonCritical
    case critical
    case nonRecoverable
    case notAvailable
    case unknown

    public var displayText: String {
        switch self {
        case .ok:
            return "正常"
        case .nonCritical:
            return "警告"
        case .critical:
            return "严重"
        case .nonRecoverable:
            return "危急"
        case .notAvailable:
            return "不可用"
        case .unknown:
            return "未知"
        }
    }

    public var isAbnormal: Bool {
        switch self {
        case .nonCritical, .critical, .nonRecoverable:
            return true
        case .ok, .notAvailable, .unknown:
            return false
        }
    }
}

public struct SensorReading: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let numericValue: Double?
    public let rawValue: String
    public let unit: String
    public let rawUnit: String
    public let status: SensorStatus
    public let rawStatus: String
    public let category: SensorCategory
    public let upperNonCritical: Double?
    public let upperCritical: Double?

    public init(
        id: String,
        name: String,
        displayName: String,
        numericValue: Double?,
        rawValue: String,
        unit: String,
        rawUnit: String,
        status: SensorStatus,
        rawStatus: String,
        category: SensorCategory,
        upperNonCritical: Double? = nil,
        upperCritical: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.numericValue = numericValue
        self.rawValue = rawValue
        self.unit = unit
        self.rawUnit = rawUnit
        self.status = status
        self.rawStatus = rawStatus
        self.category = category
        self.upperNonCritical = upperNonCritical
        self.upperCritical = upperCritical
    }

    public var formattedValue: String {
        guard let numericValue else {
            return rawValue.isEmpty ? "--" : rawValue
        }
        if numericValue.rounded() == numericValue {
            return String(format: "%.0f", numericValue)
        }
        return String(format: "%.2f", numericValue)
    }
}

public struct LabeledMetric: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: Double

    public init(id: String, label: String, value: Double) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct SensorSummary: Equatable, Sendable {
    public let cpuTemperatures: [LabeledMetric]
    public let inletTemperature: Double?
    public let exhaustTemperature: Double?
    public let highestTemperature: Double?
    public let fanRPMs: [LabeledMetric]
    public let averageFanRPM: Int?
    public let powerWatts: Double?
    public let menuBarTemperatureText: String

    public init(
        cpuTemperatures: [LabeledMetric],
        inletTemperature: Double?,
        exhaustTemperature: Double?,
        highestTemperature: Double?,
        fanRPMs: [LabeledMetric],
        averageFanRPM: Int?,
        powerWatts: Double?,
        menuBarTemperatureText: String
    ) {
        self.cpuTemperatures = cpuTemperatures
        self.inletTemperature = inletTemperature
        self.exhaustTemperature = exhaustTemperature
        self.highestTemperature = highestTemperature
        self.fanRPMs = fanRPMs
        self.averageFanRPM = averageFanRPM
        self.powerWatts = powerWatts
        self.menuBarTemperatureText = menuBarTemperatureText
    }

    public static let empty = SensorSummary(
        cpuTemperatures: [],
        inletTemperature: nil,
        exhaustTemperature: nil,
        highestTemperature: nil,
        fanRPMs: [],
        averageFanRPM: nil,
        powerWatts: nil,
        menuBarTemperatureText: "--°C"
    )
}
