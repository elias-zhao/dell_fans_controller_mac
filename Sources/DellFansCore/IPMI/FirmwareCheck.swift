import Foundation

public enum FirmwareCheck {
    public static func parseMCInfo(_ output: String, serverModel: String? = nil) -> FirmwareInfo {
        var rawFirmwareRevision = ""
        var manufacturerID: Int?
        var manufacturerName: String?
        var productID: Int?
        var auxHexTokens: [String] = []
        var collectingAux = false

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                collectingAux = false
                continue
            }

            if collectingAux {
                if !trimmed.contains(":"), let _ = parseHexByte(trimmed), auxHexTokens.count < 4 {
                    auxHexTokens.append(trimmed)
                    if auxHexTokens.count == 4 {
                        collectingAux = false
                    }
                    continue
                } else {
                    collectingAux = false
                }
            }

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "firmware revision":
                rawFirmwareRevision = value
            case "manufacturer id":
                manufacturerID = parseLeadingInt(value)
            case "manufacturer name":
                manufacturerName = value.isEmpty ? nil : value
            case "product id":
                productID = parseLeadingInt(value)
            case "aux firmware rev info":
                collectingAux = true
            default:
                break
            }
        }

        let auxRevision = auxHexTokens.isEmpty ? nil : auxHexTokens.joined(separator: " ")
        let effectiveRevision = combineFirmwareRevision(
            rawRevision: rawFirmwareRevision,
            auxHexTokens: auxHexTokens
        )

        let supportStatus = evaluateSupport(
            firmwareRevision: effectiveRevision,
            auxRevision: auxRevision,
            manufacturerID: manufacturerID,
            manufacturerName: manufacturerName
        )

        return FirmwareInfo(
            firmwareRevision: effectiveRevision,
            rawFirmwareRevision: rawFirmwareRevision,
            auxFirmwareRevision: auxRevision,
            manufacturerID: manufacturerID,
            manufacturerName: manufacturerName,
            productID: productID,
            serverModel: serverModel,
            supportStatus: supportStatus
        )
    }

    public static func parseServerModel(fromFRU output: String) -> String? {
        var productName: String?
        var boardProduct: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }

            let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let lowerValue = value.lowercased()
            if lowerValue == "unspecified" || lowerValue == "n/a" || lowerValue == "to be filled by o.e.m." {
                continue
            }

            if key == "product name", productName == nil {
                productName = cleanModelName(value)
            } else if key == "board product", boardProduct == nil {
                boardProduct = cleanModelName(value)
            }
        }

        return productName ?? boardProduct
    }

    public static func evaluateSupport(
        firmwareRevision: String,
        auxRevision: String?,
        manufacturerID: Int?,
        manufacturerName: String?
    ) -> FirmwareSupportStatus {
        let isDellByName = manufacturerName?.lowercased().contains("dell") ?? false
        if let manufacturerID, manufacturerID != 674, !isDellByName {
            let vendor = manufacturerName ?? "ID \(manufacturerID)"
            return .warning(reason: "未检测到 Dell iDRAC（制造商：\(vendor)），手动调速命令可能无效")
        }

        let parts = firmwareRevision
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .map(String.init)

        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return .unknown(reason: "无法识别固件版本格式：\(firmwareRevision)")
        }

        if major < 3 {
            return .supported(reason: "iDRAC 固件 \(firmwareRevision) 支持 IPMI 手动风扇调速")
        }
        if major == 3 && minor <= 30 {
            return .supported(reason: "iDRAC9 固件 \(firmwareRevision) 支持 IPMI 手动风扇调速")
        }
        if major == 3 && minor > 30 && minor < 34 {
            return .warning(reason: "iDRAC9 固件 \(firmwareRevision) 处于临界版本，部分型号可能已限制手动调速")
        }
        return .unsupported(reason: "iDRAC 固件 \(firmwareRevision) 已封禁 IPMI raw 0x30 0x30 手动调速")
    }

    private static func combineFirmwareRevision(rawRevision: String, auxHexTokens: [String]) -> String {
        let trimmed = rawRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let parts = trimmed.split(separator: ".").map(String.init)
        guard parts.count == 2, let major = Int(parts[0]), major >= 3 else {
            return trimmed
        }

        var auxBytes = auxHexTokens.compactMap(parseHexByte)
        while auxBytes.last == 0 {
            auxBytes.removeLast()
        }
        guard !auxBytes.isEmpty else {
            return trimmed
        }

        let suffix = auxBytes.map(String.init).joined(separator: ".")
        return "\(trimmed).\(suffix)"
    }

    private static func parseHexByte(_ token: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("0x") {
            return Int(trimmed.dropFirst(2), radix: 16)
        }
        return Int(trimmed, radix: 16)
    }

    private static func parseLeadingInt(_ value: String) -> Int? {
        let token = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
        return token.flatMap(Int.init)
    }

    private static func cleanModelName(_ raw: String) -> String? {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Dell Inc. ", "Dell ", "PowerEdge "] {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result.removeFirst(prefix.count)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result.isEmpty ? nil : result
    }
}
