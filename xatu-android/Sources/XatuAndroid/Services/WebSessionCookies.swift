import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// CookieManager queries are path-specific. A root URL cannot see /authserver or /eams cookies.
enum WebSessionCookies {
    struct Scope {
        let url: URL
        let fallbackPath: String
    }
    static let scopes: [Scope] = [
        ("https://authserver.xatu.edu.cn/", "/"),
        ("https://authserver.xatu.edu.cn/authserver/login", "/authserver"),
        ("http://jwgl2018.xatu.edu.cn/", "/"),
        ("http://jwgl2018.xatu.edu.cn/eams/homeExt.action", "/eams"),
        ("http://jwgl2018.xatu.edu.cn/eams/courseTableForStd.action", "/eams"),
        ("https://jfpay.xatu.edu.cn/", "/"),
        ("https://jfpay.xatu.edu.cn/casLogin/", "/casLogin"),
        ("https://jfpay.xatu.edu.cn/api/", "/api"),
        ("https://ehall.xatu.edu.cn/", "/"),
        ("https://self.xatu.edu.cn/", "/"),
        ("https://ywtb.xatu.edu.cn/", "/")
    ].map { Scope(url: URL(string: $0.0)!, fallbackPath: $0.1) }

    static func isCampusHost(_ host: String) -> Bool {
        host == "xatu.edu.cn" || host.hasSuffix(".xatu.edu.cn")
    }

    /// CookieManagerCompat preserves Path, Domain, Secure, HttpOnly and expiry.
    static func parse(records: [String], for url: URL) -> [HTTPCookie] {
        guard let host = url.host, isCampusHost(host) else { return [] }
        return records.flatMap { HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": $0], for: url) }
            .filter { isCampusHost($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
    }

    /// Older WebViews expose only a Cookie request header. Keep it within the queried app path.
    static func parseLegacy(header: String, scope: Scope) -> [HTTPCookie] {
        guard let host = scope.url.host, isCampusHost(host) else { return [] }
        return header.split(separator: ";").compactMap { component in
            guard let equals = component.firstIndex(of: "=") else { return nil }
            let name = component[..<equals].trimmingCharacters(in: .whitespaces)
            let value = component[component.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return HTTPCookie(properties: [.name: name, .value: value, .domain: host, .path: scope.fallbackPath])
        }
    }

    static func install(_ cookies: [HTTPCookie], in storage: HTTPCookieStorage = .shared) {
        // Remove stale scopes created by older versions without disturbing other school sessions.
        func identity(_ cookie: HTTPCookie) -> String {
            cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "|" + cookie.name
        }
        let imported = Set(cookies.map(identity))
        for old in storage.cookies ?? [] where imported.contains(identity(old)) {
            storage.deleteCookie(old)
        }
        for cookie in cookies { storage.setCookie(cookie) }
    }
}
