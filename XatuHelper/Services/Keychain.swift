import Foundation
import Security

enum Keychain {
    private static let service = "com.cell.XatuHelper.credential"

    static func savePassword(_ password: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum Preferences {
    private static let studentKey = "xatu.studentID"
    private static let dormKey = "xatu.dorm"

    static var studentID: String? {
        get { UserDefaults.standard.string(forKey: studentKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: studentKey) }
            else { UserDefaults.standard.removeObject(forKey: studentKey) }
        }
    }

    /// 选好的宿舍：校区 + 楼栋 + 房间，存成 JSON 落 UserDefaults
    static var dorm: DormSelection? {
        get {
            guard let data = UserDefaults.standard.data(forKey: dormKey) else { return nil }
            return try? JSONDecoder().decode(DormSelection.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: dormKey)
            } else {
                UserDefaults.standard.removeObject(forKey: dormKey)
            }
        }
    }
}
