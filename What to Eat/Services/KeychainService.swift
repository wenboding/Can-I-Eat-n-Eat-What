import Foundation
import Security

enum KeychainServiceError: LocalizedError {
    case invalidData
    case emptyKey
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return AppLanguage.current == .simplifiedChinese ? "无法读取安全密钥数据。" : "Unable to read secure key data."
        case .emptyKey:
            return AppLanguage.current == .simplifiedChinese ? "API Key 不能为空。" : "API key cannot be empty."
        case .unexpectedStatus(let status):
            return AppLanguage.current == .simplifiedChinese
                ? "钥匙串操作失败（状态码：\(status)）。"
                : "Keychain operation failed (status: \(status))."
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()

    private let service = Bundle.main.bundleIdentifier ?? "MealCoachDemo"
    private let openAIAccount = "openai_api_key"
    private let qwenBeijingAccount = "qwen_api_key_beijing"
    private let qwenSingaporeLegacyAccount = "qwen_api_key_singapore"

    private init() {}

    func saveAPIKey(_ key: String, for provider: LLMProvider, region: QwenRegion? = nil) throws {
        let sanitized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            throw KeychainServiceError.emptyKey
        }
        guard let data = sanitized.data(using: .utf8) else {
            throw KeychainServiceError.invalidData
        }

        let targetAccount = account(for: provider, region: region)
        let baseQuery = baseQuery(forAccount: targetAccount)
        var addQuery = baseQuery
        addQuery.merge([
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            try deleteAllKeys(except: targetAccount)
        case errSecDuplicateItem:
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainServiceError.unexpectedStatus(updateStatus)
            }
            try deleteAllKeys(except: targetAccount)
        default:
            throw KeychainServiceError.unexpectedStatus(addStatus)
        }
    }

    func loadAPIKey(for provider: LLMProvider, region: QwenRegion? = nil) -> String? {
        var query = baseQuery(forAccount: account(for: provider, region: region))
        query.merge([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]) { _, new in new }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return nil
        }

        guard
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    func deleteAPIKey(for provider: LLMProvider, region: QwenRegion? = nil) throws {
        let status = SecItemDelete(baseQuery(forAccount: account(for: provider, region: region)) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func maskedAPIKey(for provider: LLMProvider, region: QwenRegion? = nil) -> String? {
        guard let key = loadAPIKey(for: provider, region: region), key.count >= 4 else { return nil }
        let suffix = key.suffix(4)
        return "••••••••\(suffix)"
    }

    private func deleteAllKeys(except keptAccount: String) throws {
        for account in [openAIAccount, qwenBeijingAccount, qwenSingaporeLegacyAccount] where account != keptAccount {
            let status = SecItemDelete(baseQuery(forAccount: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainServiceError.unexpectedStatus(status)
            }
        }
    }

    private func baseQuery(forAccount account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func account(for provider: LLMProvider, region _: QwenRegion?) -> String {
        switch provider {
        case .openAI:
            return openAIAccount
        case .qwen:
            return qwenBeijingAccount
        }
    }
}
