import Foundation

enum AppError: LocalizedError {
    case badURL
    case parseFailed
    case needCaptcha
    case sessionExpired
    case loginFailed(String)
    case reloginFailed(String)
    case emptyTimetable
    case noClassTable
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "地址拼装失败"
        case .parseFailed:
            return "页面结构和预期不一样，可能学校又改版了"
        case .needCaptcha:
            return "这次登录要验证码或者手机动态码，跟着弹出来的网页登一次就好"
        case .sessionExpired:
            return "登录已过期，请重新登录"
        case .loginFailed(let message):
            return message
        case .reloginFailed(let message):
            return message
        case .emptyTimetable:
            return "没解析到课程，可能是学期还没开学"
        case .noClassTable:
            return "这个账号没有班级课表"
        case .network(let message):
            return "网络错误：\(message)"
        }
    }
}

enum Net {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 把 ATS / 超时这类系统错误连带着失败的域名一起吐出来，不然只看到一句笼统的提示
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let failing = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        let host = failing?.host ?? (failing?.absoluteString ?? "")
        return host.isEmpty ? ns.localizedDescription : "\(ns.localizedDescription)（\(host)）"
    }

    static func isTransportProblem(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return ns.code == NSURLErrorAppTransportSecurityRequiresSecureConnection
            || ns.code == NSURLErrorCannotFindHost
            || ns.code == NSURLErrorCannotConnectToHost
            || ns.code == NSURLErrorTimedOut
            || ns.code == NSURLErrorNetworkConnectionLost
    }

    static func formBody(_ pairs: [(String, String)]) -> String {
        pairs.map { pair in
            let value = pair.1.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            return "\(pair.0)=\(value)"
        }.joined(separator: "&")
    }
}

/// 金智 CAS 统一身份认证
struct CASService {
    private static let loginPage = "https://authserver.xatu.edu.cn/authserver/login"
    private static let service = "http://jwgl2018.xatu.edu.cn/eams/homeExt.action"

    /// 网页兜底登录用的地址，和 API 登录走同一个 service
    static func loginURL() -> URL {
        var components = URLComponents(string: loginPage)
        components?.queryItems = [URLQueryItem(name: "service", value: service)]
        return components?.url ?? URL(string: loginPage)!
    }

    /// 用学号密码登录，成功后 cookie 落在共享存储里，jwgl2018 那边就能用了。
    func login(username: String, password: String) async throws {
        guard var components = URLComponents(string: Self.loginPage) else { throw AppError.badURL }
        components.queryItems = [URLQueryItem(name: "service", value: Self.service)]
        guard let url = components.url else { throw AppError.badURL }

        let (pageData, pageResponse) = try await fetch(url)
        guard let html = String(data: pageData, encoding: .utf8) else { throw AppError.parseFailed }

        // 统一认证那边的会话还活着时会带着 ticket 直接跳回业务系统，页面上根本没有登录表单。
        // 这种其实已经登录成功、cookie 也落地了，直接返回。
        let landedHost = pageResponse.url?.host ?? ""
        if !landedHost.contains("authserver"), !html.contains("pwdEncryptSalt") {
            return
        }

        // captchaSwitch = "1" 表示这次一定要填验证码，纯 API 过不去，直接交给网页
        if html.firstMatch(#"var\s+captchaSwitch\s*=\s*"([^"]*)""#) == "1" {
            throw AppError.needCaptcha
        }

        guard let salt = html.firstMatch(#"id="pwdEncryptSalt"[^>]*value="([^"]*)""#),
              let execution = html.firstMatch(#"id="execution"[^>]*value="([^"]*)""#) else {
            throw AppError.parseFailed
        }
        let lt = html.firstMatch(#"id="lt"[^>]*value="([^"]*)""#) ?? ""

        let body = Net.formBody([
            ("username", username),
            ("password", Crypto.encryptPassword(password, salt: salt)),
            ("passwordText", ""),
            ("captcha", ""),
            ("_eventId", "submit"),
            ("cllt", "userNameLogin"),
            ("dllt", "generalLogin"),
            ("lt", lt),
            ("execution", execution),
            ("rmShown", "1")
        ])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let (responseData, response) = try await Net.session.data(for: request)
        let finalHost = response.url?.host ?? ""
        let finalHTML = String(data: responseData, encoding: .utf8) ?? ""

        if finalHost.contains("authserver") || finalHTML.contains("id=\"pwdEncryptSalt\"") {
            // 登录失败回到的页面本身就带验证码/动态码字样，只能看错误提示里说了什么
            let message = errorMessage(from: finalHTML)
            if message.contains("验证码") || message.contains("动态码") {
                throw AppError.needCaptcha
            }
            throw AppError.loginFailed(message)
        }
    }

    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await Net.session.data(from: url)
        } catch {
            throw AppError.network(error.localizedDescription)
        }
    }

    private func errorMessage(from html: String) -> String {
        let patterns = [
            #"id="msg"[^>]*>(.*?)</"#,
            #"class="auth_error"[^>]*>(.*?)</"#,
            #"id="errorMsg"[^>]*>(.*?)</"#
        ]
        for pattern in patterns {
            if let text = html.firstMatch(pattern)?.strippingTags, !text.isEmpty {
                return text
            }
        }
        return "登录失败，账号或密码不对"
    }
}
