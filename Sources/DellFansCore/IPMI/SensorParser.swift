import Foundation

public enum SensorParser {
    public static func parse(_ output: String) -> [SensorReading] {
        struct ParsedRow {
            let index: Int
            let name: String
            let rawValue: String
            let numericValue: Double?
            let unit: String
            let rawUnit: String
            let status: SensorStatus
            let rawStatus: String
            let category: SensorCategory
            let upperNonCritical: Double?
            let upperCritical: Double?
        }

        var rows: [ParsedRow] = []
        var nameCounts: [String: Int] = [:]

        let lines = output.components(separatedBy: .newlines)
        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 4 else { continue }

            let name = columns[0]
            guard !name.isEmpty else { continue }

            let rawValue = columns[1]
            let rawUnit = columns[2]
            let rawStatus = columns[3]

            guard let (category, displayUnit) = categorize(name: name, rawUnit: rawUnit) else {
                continue
            }

            let numericValue = Double(rawValue)
            let status = parseStatus(rawStatus)
            let upperNonCritical = columns.count > 7 ? Double(columns[7]) : nil
            let upperCritical = columns.count > 8 ? Double(columns[8]) : nil

            rows.append(
                ParsedRow(
                    index: lineIndex,
                    name: name,
                    rawValue: rawValue,
                    numericValue: numericValue,
                    unit: displayUnit,
                    rawUnit: rawUnit,
                    status: status,
                    rawStatus: rawStatus,
                    category: category,
                    upperNonCritical: upperNonCritical,
                    upperCritical: upperCritical
                )
            )
            nameCounts[name, default: 0] += 1
        }

        var seenCounts: [String: Int] = [:]
        return rows.map { row in
            let count = nameCounts[row.name, default: 1]
            let displayName: String
            if count > 1 {
                let occurrence = seenCounts[row.name, default: 0] + 1
                seenCounts[row.name] = occurrence
                displayName = "\(row.name) #\(occurrence)"
            } else {
                displayName = row.name
            }

            return SensorReading(
                id: "\(row.index)-\(row.name)",
                name: row.name,
                displayName: displayName,
                numericValue: row.numericValue,
                rawValue: row.rawValue,
                unit: row.unit,
                rawUnit: row.rawUnit,
                status: row.status,
                rawStatus: row.rawStatus,
                category: row.category,
                upperNonCritical: row.upperNonCritical,
                upperCritical: row.upperCritical
            )
        }
    }

    public static func summarize(_ readings: [SensorReading]) -> SensorSummary {
        var cpuTemperatures: [LabeledMetric] = []
        var genericTempCount = 0
        var inletTemperature: Double?
        var exhaustTemperature: Double?
        var highestTemperature: Double?
        var fanRPMs: [LabeledMetric] = []
        var positiveRPMs: [Double] = []
        var powerWatts: Double?

        for reading in readings {
            let lowerName = reading.name.lowercased()

            switch reading.category {
            case .temperature:
                guard let value = reading.numericValue else { continue }

                if highestTemperature == nil || value > highestTemperature! {
                    highestTemperature = value
                }

                if lowerName.contains("inlet"), inletTemperature == nil {
                    inletTemperature = value
                }
                if lowerName.contains("exhaust"), exhaustTemperature == nil {
                    exhaustTemperature = value
                }

                if lowerName == "temp" {
                    genericTempCount += 1
                    cpuTemperatures.append(
                        LabeledMetric(
                            id: reading.id,
                            label: "CPU\(genericTempCount)",
                            value: value
                        )
                    )
                } else if lowerName.contains("cpu") {
                    cpuTemperatures.append(
                        LabeledMetric(
                            id: reading.id,
                            label: reading.displayName,
                            value: value
                        )
                    )
                }

            case .fan:
                guard let value = reading.numericValue else { continue }
                fanRPMs.append(
                    LabeledMetric(
                        id: reading.id,
                        label: reading.displayName,
                        value: value
                    )
                )
                if value > 0 {
                    positiveRPMs.append(value)
                }

            case .power:
                if powerWatts == nil, let value = reading.numericValue {
                    powerWatts = value
                }

            case .voltage, .current, .other:
                break
            }
        }

        let averageFanRPM: Int?
        if positiveRPMs.isEmpty {
            averageFanRPM = nil
        } else {
            let avg = positiveRPMs.reduce(0, +) / Double(positiveRPMs.count)
            averageFanRPM = Int(avg.rounded())
        }

        let menuBarValue = cpuTemperatures.map(\.value).max() ?? highestTemperature
        let menuBarTemperatureText: String
        if let menuBarValue {
            menuBarTemperatureText = "\(Int(menuBarValue.rounded()))°C"
        } else {
            menuBarTemperatureText = "--°C"
        }

        return SensorSummary(
            cpuTemperatures: cpuTemperatures,
            inletTemperature: inletTemperature,
            exhaustTemperature: exhaustTemperature,
            highestTemperature: highestTemperature,
            fanRPMs: fanRPMs,
            averageFanRPM: averageFanRPM,
            powerWatts: powerWatts,
            menuBarTemperatureText: menuBarTemperatureText
        )
    }

    private static func categorize(name: String, rawUnit: String) -> (SensorCategory, String)? {
        let lowerName = name.lowercased()
        let lowerUnit = rawUnit.lowercased()

        // Match by unit first so sensors with explicit units are never misclassified.
        if lowerUnit.contains("degrees c") || lowerUnit.contains("°c") || (lowerUnit == "c" && lowerName.contains("temp")) {
            return (.temperature, "°C")
        }
        if lowerUnit.contains("rpm") {
            return (.fan, "RPM")
        }
        if lowerUnit.contains("volt") || lowerUnit == "v" {
            return (.voltage, "V")
        }
        if lowerUnit.contains("amp") || lowerUnit == "a" {
            return (.current, "A")
        }
        if lowerUnit.contains("watt") || lowerUnit == "w" {
            return (.power, "W")
        }

        // Fall back to sensor name (handles unspecified/empty units while excluding unrelated discrete sensors).
        if lowerName.contains("temp") {
            return (.temperature, "°C")
        }
        if lowerName.contains("fan") {
            return (.fan, "RPM")
        }
        if lowerName.contains("voltage") || lowerName.contains("vcore") || lowerName.contains("vbat") {
            return (.voltage, "V")
        }
        if lowerName.contains("current") {
            return (.current, "A")
        }
        if lowerName.contains("pwr") || lowerName.contains("power") {
            return (.power, "W")
        }

        return nil
    }

    private static func parseStatus(_ rawStatus: String) -> SensorStatus {
        switch rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ok":
            return .ok
        case "nc", "lnc", "unc":
            return .nonCritical
        case "cr", "lcr", "ucr":
            return .critical
        case "nr", "lnr", "unr":
            return .nonRecoverable
        case "na", "ns":
            return .notAvailable
        default:
            return .unknown
        }
    }
}
