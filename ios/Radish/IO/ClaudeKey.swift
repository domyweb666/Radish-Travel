// 使用者自己填的 Claude API 金鑰、連電腦 Claude CLI 的網址，存在這支手機的鑰匙圈（Keychain）。
// 不放進存檔的 JSON，所以「複製備份」不會帶走它們；設成只在這支手機、開機解鎖過後讀得到，不跟著 iCloud 走。
import Foundation
import Security

/// 鑰匙圈裡的一格
enum SecretSlot: String {
    /// Claude API 金鑰
    case claudeKey = "org.domyweb.radish.claude-api-key"
    /// 連電腦 Claude CLI 的網址（含密碼）
    case bridge = "org.domyweb.radish.claude-bridge"
}

enum SecretStore {
    private static func base(_ slot: SecretSlot) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.rawValue,
            kSecAttrAccount as String: "default",
        ]
    }

    /// 讀出來；沒有就是空字串
    static func load(_ slot: SecretSlot) -> String {
        var query: [String: Any] = base(slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 存起來（蓋掉舊的）。存成功回 true。先改舊的那一格，沒有舊的才新增；失敗時舊的還在
    @discardableResult
    static func save(_ slot: SecretSlot, _ value: String) -> Bool {
        let fields: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated: OSStatus = SecItemUpdate(base(slot) as CFDictionary, fields as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var item: [String: Any] = base(slot)
        for (key, field) in fields {
            item[key] = field
        }
        let added: OSStatus = SecItemAdd(item as CFDictionary, nil)
        return added == errSecSuccess
    }

    static func clear(_ slot: SecretSlot) {
        SecItemDelete(base(slot) as CFDictionary)
    }
}

/// 畫面上顯示金鑰時只露頭尾，例：sk-ant-…a1b2
func maskedClaudeKey(_ key: String) -> String {
    guard key.count > 12 else { return "已填" }
    return "\(key.prefix(7))…\(key.suffix(4))"
}

/// 畫面上顯示轉接網址時只露位址，不露密碼，例：192.168.1.23:8787
func maskedBridge(_ url: String) -> String {
    guard let u = URLComponents(string: url), let host = u.host else { return "已連" }
    if let port = u.port { return "\(host):\(port)" }
    return host
}
