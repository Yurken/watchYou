import Foundation

/// A stored credential entry with a non-sensitive fingerprint.
public struct CredentialEntry: Equatable, Sendable {
    public let fingerprint: String
    public let secret: String

    public init(fingerprint: String, secret: String) {
        self.fingerprint = fingerprint
        self.secret = secret
    }
}

public protocol CredentialStore: Sendable {
    func save(profileID: String, recipient: String, fingerprint: String, secret: String) throws
    func read(profileID: String, recipient: String) throws -> CredentialEntry?
    func delete(profileID: String, recipient: String) throws
}

/// Build a recipient string from normalized endpoint and authentication type.
public func credentialRecipient(normalizedEndpoint: String, authType: String) -> String {
    "\(normalizedEndpoint)|\(authType)"
}

/// Last four characters of a secret; used as a non-sensitive identifier.
public func credentialFingerprint(secret: String) -> String {
    String(secret.suffix(4))
}

#if canImport(Security)
import Security

/// Keychain-backed credential store.
public struct KeychainCredentialStore: CredentialStore {
    public static let service = "app.watchyou.ios"

    public init() {}

    private func account(for profileID: String, recipient: String) -> String {
        "\(profileID)|\(recipient)"
    }

    private func baseQuery(profileID: String, recipient: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainCredentialStore.service,
            kSecAttrAccount as String: account(for: profileID, recipient: recipient),
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    public func save(profileID: String, recipient: String, fingerprint: String, secret: String) throws {
        guard let data = secret.data(using: .utf8) else { return }

        var query = baseQuery(profileID: profileID, recipient: recipient)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemUpdate(query as CFDictionary, [
            kSecValueData as String: data
        ] as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain("保存凭据失败: \(addStatus)")
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain("更新凭据失败: \(status)")
        }
    }

    public func read(profileID: String, recipient: String) throws -> CredentialEntry? {
        var query = baseQuery(profileID: profileID, recipient: recipient)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw CredentialStoreError.keychain("读取凭据失败: \(status)")
        }
        guard let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else { return nil }
        return CredentialEntry(fingerprint: credentialFingerprint(secret: secret), secret: secret)
    }

    public func delete(profileID: String, recipient: String) throws {
        let status = SecItemDelete(baseQuery(profileID: profileID, recipient: recipient) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain("删除凭据失败: \(status)")
        }
    }
}
#endif

/// In-memory credential store for tests and prototypes.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var storage: [String: CredentialEntry] = [:]
    private let lock = NSLock()

    public init() {}

    private func key(profileID: String, recipient: String) -> String {
        "\(profileID)|\(recipient)"
    }

    public func save(profileID: String, recipient: String, fingerprint: String, secret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key(profileID: profileID, recipient: recipient)] = CredentialEntry(
            fingerprint: fingerprint,
            secret: secret
        )
    }

    public func read(profileID: String, recipient: String) throws -> CredentialEntry? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key(profileID: profileID, recipient: recipient)]
    }

    public func delete(profileID: String, recipient: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key(profileID: profileID, recipient: recipient))
    }
}

public enum CredentialStoreError: Error, Equatable {
    case keychain(String)
}
