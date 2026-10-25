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
    private static let balanceKey = "xatu.electricityBalance"
    private static let checkedKey = "xatu.electricityCheckedAt"

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

    private static let loginTimesKey = "xatu.loginTimes"

    /// 最近自动登录的时间点，用来防止连续登录把账号搞冻结
    static var loginTimes: [Date] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: loginTimesKey) as? [Double] else { return [] }
            return raw.map { Date(timeIntervalSince1970: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.suffix(10).map { $0.timeIntervalSince1970 }, forKey: loginTimesKey)
        }
    }

    /// 上次查到的电费余额，存下来才能判断"今天已经查过了"
    static var electricityBalance: String? {
        get { UserDefaults.standard.string(forKey: balanceKey) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: balanceKey) }
            else { UserDefaults.standard.removeObject(forKey: balanceKey) }
        }
    }

    static var electricityCheckedAt: Date? {
        get {
            let stamp = UserDefaults.standard.double(forKey: checkedKey)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: checkedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: checkedKey)
            }
        }
    }
}
