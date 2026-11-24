import CryptoKit
import Foundation

public enum LocalPasswordStoreError: LocalizedError, Sendable {
    case invalidDirectory
    case encryptionFailed
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            return "无法确定本地凭据存储目录"
        case .encryptionFailed:
            return "加密本地凭据失败"
        case .decryptionFailed:
            return "解密本地凭据失败"
        }
    }
}

public struct LocalPasswordStore: PasswordStoreProtocol, Sendable {
    private let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            self.directoryURL = appSupport.appendingPathComponent("DellFansController", isDirectory: true)
        }
    }

    public var fileURL: URL {
        directoryURL.appendingPathComponent("credentials.bin", isDirectory: false)
    }

    public func savePassword(_ password: String, account: String) throws {
        if password.isEmpty {
            try deletePassword(account: account)
            return
        }

        var map = (try? loadAll()) ?? [:]
        map[account] = password
        try persistAll(map)
    }

    public func loadPassword(account: String) throws -> String? {
        let map = try loadAll()
        return map[account]
    }

    public func deletePassword(account: String) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        var map = (try? loadAll()) ?? [:]
        map.removeValue(forKey: account)
        if map.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            try persistAll(map)
        }
    }

    // MARK: - Private

    private func loadAll() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let encrypted = try Data(contentsOf: fileURL)
        guard !encrypted.isEmpty else {
            return [:]
        }
        let box = try AES.GCM.SealedBox(combined: encrypted)
        let decrypted = try AES.GCM.open(box, using: derivedKey())
        return try JSONDecoder().decode([String: String].self, from: decrypted)
    }

    private func persistAll(_ map: [String: String]) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directoryURL.path) {
            try fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        }

        let plaintext = try JSONEncoder().encode(map)
        let sealed = try AES.GCM.seal(plaintext, using: derivedKey())
        guard let combined = sealed.combined else {
            throw LocalPasswordStoreError.encryptionFailed
        }

        try combined.write(to: fileURL, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func derivedKey() -> SymmetricKey {
        let seed = "com.dellfanscontroller.mac.localstore.v1:\(NSUserName()):\(NSHomeDirectory())"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: digest)
    }
}
