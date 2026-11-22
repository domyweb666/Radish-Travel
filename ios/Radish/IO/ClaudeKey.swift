// 使用者自己填的 Claude API 金鑰，存在這支手機的鑰匙圈（Keychain）。
// 不放進存檔的 JSON，所以「複製備份」不會帶走它；設成只在這支手機、開機解鎖過後讀得到，不跟著 iCloud 走。
import Foundation
import Security

enum ClaudeKeyStore {
    private static let service: String = "org.domyweb.radish.claude-api-key"
    private static let account: String = "default"

    private static var base: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 讀出來；沒有就是空字串
    static func load() -> String {
        var query: [String: Any] = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 存起來（蓋掉舊的）。存成功回 true
    @discardableResult
    static func save(_ key: String) -> Bool {
        clear()
        var item: [String: Any] = base
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(base as CFDictionary)
    }
}

/// 畫面上顯示金鑰時只露頭尾，例：sk-ant-…a1b2
func maskedClaudeKey(_ key: String) -> String {
    guard key.count > 12 else { return "已填" }
    return "\(key.prefix(7))…\(key.suffix(4))"
}
