import Foundation
import Security

public enum KeychainError: LocalizedError, Equatable, Sendable {
    case unhandledStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "钥匙串操作失败：\(message) (\(status))"
            }
            return "钥匙串操作失败（状态码 \(status)）"
        case .invalidData:
            return "钥匙串中的数据无法解码为 UTF-8 字符串"
        }
    }
}

public struct KeychainHelper: PasswordStoreProtocol, Sendable {
    private let service: String

    public init(service: String = "com.dellfanscontroller.mac") {
        self.service = service
    }

    public func savePassword(_ password: String, account: String) throws {
        if password.isEmpty {
            try deletePassword(account: account)
            return
        }

        let data = Data(password.utf8)
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            return
        }

        if status == errSecDuplicateItem {
            let query = baseQuery(account: account)
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(updateStatus)
            }
            return
        }

        throw KeychainError.unhandledStatus(status)
    }

    public func loadPassword(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return password
    }

    public func deletePassword(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
