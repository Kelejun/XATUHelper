import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main struct SessionProbe {
    static func main() async throws {
        let fixtureValid = Crypto.aesCBCEncrypt("xatu-password", key: "0123456789abcdef", iv: "fedcba9876543210") == "PNK7KHZdk4qpd+KsL0UtUw=="
        print("Android AES fixture valid: \(fixtureValid)")
        let args = Array(CommandLine.arguments.dropFirst())
        if let base = args.first(where: { $0.hasPrefix("http://") }) {
            for path in ["/authserver/login", "/authserver/check", "/eams/home", "/eams/check"] {
                var request = URLRequest(url: URL(string: base + path)!)
                if path == "/authserver/check" {
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = Data(Net.formBody([("username", "fixture"), ("password", "synthetic-fixture")]).utf8)
                }
                let (data, response) = try await Net.session.data(for: request)
                print("\(path): status=\((response as? HTTPURLResponse)?.statusCode ?? 0) body=\(String(decoding: data, as: UTF8.self))")
            }
        } else {
            let (data, response) = try await Net.session.data(from: CASService.loginURL())
            let html = String(decoding: data, as: UTF8.self)
            print("CAS GET: status=\((response as? HTTPURLResponse)?.statusCode ?? 0) saltLength=\(html.firstMatch(#"id="pwdEncryptSalt"[^>]*value="([^"]*)""#)?.utf8.count ?? 0)")
        }
        // Names and scopes only. Never print cookie values or credentials.
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            print("cookie name=\(cookie.name) domain=\(cookie.domain) path=\(cookie.path) secure=\(cookie.isSecure)")
        }
    }
}
