import Foundation
import Security

/// 把校园域名的 cookie 存在本地，下次启动原样塞回去。
///
/// iOS 默认不会持久化「会话 cookie」（没有 Expires 的那些），杀掉 app 就没了。
/// 所以这里做两件事：
/// 1. `pin()`：把没有过期时间的会话 cookie 重新设一遍，补一个将来的 Expires，
///    这样系统自己就会把它写进磁盘；
/// 2. `save()`/`restore()`：再拿 Keychain 存一份兜底，冷启动时塞回 HTTPCookieStorage。
///
/// 真正失效（服务端那边过期了）还是会被踢回登录页，交给 withRelogin 重登。
enum CookieVault {
    private static let service = "com.cell.XatuHelper.cookies"
    private static let account = "xatu"
    private static let domainKeyword = "xatu.edu.cn"
    /// 给会话 cookie 补的过期时间，够长就行，服务端该失效还是会失效
    private static let pinLifetime: TimeInterval = 30 * 24 * 3600

    private struct StoredCookie: Codable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expires: Date?
        var isSecure: Bool
        var isHTTPOnly: Bool
    }

    // MARK: - 对外

    /// 登录成功后调一次：补过期时间 + 落盘
    static func pinAndSave() {
        pin()
        save()
    }

    /// 冷启动时调一次，把上次存的 cookie 塞回去
    static func restore() {
        guard let data = load(), let cookies = try? JSONDecoder().decode([StoredCookie].self, from: data) else {
            return
        }
        let now = Date()
        for stored in cookies {
            // 自己记的过期时间都过了就别塞了，省得每次都拿死 cookie 去撞墙
            if let expires = stored.expires, expires <= now { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: stored.name,
                .value: stored.value,
                .domain: stored.domain,
                .path: stored.path,
                .secure: stored.isSecure ? "TRUE" : "FALSE",
            ]
            if stored.isHTTPOnly {
                properties[.init("HttpOnly")] = "TRUE"
            }
            properties[.expires] = stored.expires ?? now.addingTimeInterval(pinLifetime)
            if let cookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    static func save() {
        let cookies = liveCookies()
        guard !cookies.isEmpty else { return }
        let stored = cookies.map { cookie in
            StoredCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expires: cookie.expiresDate ?? Date().addingTimeInterval(pinLifetime),
                isSecure: cookie.isSecure,
                isHTTPOnly: cookie.isHTTPOnly
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        write(data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - 内部

    /// 把没有过期时间的会话 cookie 重设成有 Expires 的，系统才会持久化
    private static func pin() {
        let expiry = Date().addingTimeInterval(pinLifetime)
        for cookie in liveCookies() where cookie.expiresDate == nil {
            var properties = cookie.properties ?? [:]
            properties[.expires] = expiry
            if let pinned = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(pinned)
            }
        }
    }

    private static func liveCookies() -> [HTTPCookie] {
        (HTTPCookieStorage.shared.cookies ?? [])
            .filter { $0.domain.contains(domainKeyword) }
    }

    private static func write(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
