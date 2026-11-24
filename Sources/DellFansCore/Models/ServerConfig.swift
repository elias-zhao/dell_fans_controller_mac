import Foundation

public struct ServerConfig: Equatable, Sendable, Codable {
    public var host: String
    public var username: String
    public var refreshIntervalSeconds: Int
    public var ipmitoolPath: String

    public init(
        host: String = "",
        username: String = "root",
        refreshIntervalSeconds: Int = 10,
        ipmitoolPath: String = ""
    ) {
        self.host = host
        self.username = username
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.ipmitoolPath = ipmitoolPath
    }

    public var trimmedHost: String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("https://") {
            value.removeFirst("https://".count)
        } else if value.lowercased().hasPrefix("http://") {
            value.removeFirst("http://".count)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    public var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isConfigured: Bool {
        !trimmedHost.isEmpty && !trimmedUsername.isEmpty
    }

    public var webConsoleURL: URL? {
        let host = trimmedHost
        guard !host.isEmpty else { return nil }
        return URL(string: "https://\(host)")
    }
}
