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

/// 记一下每次请求的 302 链，出问题能看出是在哪儿打转
final class NetRedirectTracer: NSObject, URLSessionTaskDelegate {
    private static let lock = NSLock()
    private static var _lastHops: [String] = []
    static var lastHops: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastHops
        }
        set {
            lock.lock()
            _lastHops = newValue
            lock.unlock()
        }
    }

    static func reset() {
        lastHops = []
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        Self.lock.lock()
        Self._lastHops.append(request.url?.absoluteString ?? "")
        if Self._lastHops.count > 16 { Self._lastHops.removeFirst() }
        Self.lock.unlock()
        completionHandler(request)
    }
}

enum Net {
    private static let tracer = NetRedirectTracer()

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: tracer, delegateQueue: nil)
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

    /// 重定向打转时，把链子摊出来，方便判断是在 CAS 之间来回还是同一个地址死循环
    static var redirectTrail: String {
        guard !lastHops.isEmpty else { return "" }
        let tail = lastHops.suffix(6).map { hop in
            guard let url = URL(string: hop) else { return hop }
            return url.host.map { "\($0)\(url.path)" } ?? hop
        }
        return "；跳转：" + tail.joined(separator: " → ")
    }

    private static var lastHops: [String] { NetRedirectTracer.lastHops }

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

    /// 只拿现有的统一认证票据换一次票，不填密码。
    /// 浏览器就是这么做的：cookie 还在，CAS 直接 302 带 ticket 回来。
    static func silentRenew() async -> Bool {
        guard var components = URLComponents(string: loginPage) else { return false }
        components.queryItems = [URLQueryItem(name: "service", value: service)]
        guard let url = components.url else { return false }
        do {
            let (data, response) = try await Net.session.data(from: url)
            let host = response.url?.host ?? ""
            let html = String(data: data, encoding: .utf8) ?? ""
            return !host.contains("authserver") && !html.contains("pwdEncryptSalt")
        } catch {
            return false
        }
    }

    /// 用学号密码登录，成功后 cookie 落在共享存储里，jwgl2018 那边就能用了。
    func login(username: String, password: String) async throws {
        var clearedCount = 0
        for cookie in HTTPCookieStorage.shared.cookies ?? []
        where cookie.domain == "xatu.edu.cn" || cookie.domain.hasSuffix(".xatu.edu.cn") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
            clearedCount += 1
        }
        CookieVault.clear()
        LoginDiagnostics.shared.record(category: "CAS", message: "清理旧 Cookie count=\(clearedCount)")
        guard var components = URLComponents(string: Self.loginPage) else { throw AppError.badURL }
        components.queryItems = [URLQueryItem(name: "service", value: Self.service)]
        guard let url = components.url else { throw AppError.badURL }

        NetRedirectTracer.reset()
        let (pageData, pageResponse): (Data, URLResponse)
        do {
            (pageData, pageResponse) = try await fetch(url)
        } catch {
            LoginDiagnostics.shared.recordRedirectHops(NetRedirectTracer.lastHops, category: "CAS", label: "GET登录页")
            LoginDiagnostics.shared.record(category: "CAS", message: "GET 登录页失败", url: url, error: error)
            throw error
        }
        let getStatus = (pageResponse as? HTTPURLResponse)?.statusCode
        LoginDiagnostics.shared.recordRedirectHops(NetRedirectTracer.lastHops, category: "CAS", label: "GET登录页")
        LoginDiagnostics.shared.record(category: "CAS", message: "GET 登录页完成 bytes=\(pageData.count)", url: pageResponse.url, statusCode: getStatus)

        guard let html = String(data: pageData, encoding: .utf8) else {
            LoginDiagnostics.shared.record(category: "CAS", message: "GET 登录页非 UTF-8 编码", url: pageResponse.url, statusCode: getStatus)
            throw AppError.parseFailed
        }

        // 统一认证那边的会话还活着时会带着 ticket 直接跳回业务系统，页面上根本没有登录表单。
        // 这种其实已经登录成功、cookie 也落地了，直接返回。
        let landedHost = pageResponse.url?.host ?? ""
        if !landedHost.contains("authserver"), !html.contains("pwdEncryptSalt") {
            LoginDiagnostics.shared.record(category: "CAS", message: "GET 登录页直接跳转业务系统（免密复用会话）", url: pageResponse.url, statusCode: getStatus)
            return
        }

        // captchaSwitch 打开表示这次一定要填验证码，纯 API 过不去，直接交给网页
        if Self.captchaRequired(in: html) {
            LoginDiagnostics.shared.recordHTML(category: "CAS", label: "GET 检测到 captchaSwitch 开启", html: html, url: pageResponse.url, statusCode: getStatus)
            throw AppError.needCaptcha
        }

        let salt = html.firstMatch(#"id="pwdEncryptSalt"[^>]*value="([^"]*)""#)
        let execution = html.firstMatch(#"id="execution"[^>]*value="([^"]*)""#)
        guard let salt, let execution else {
            LoginDiagnostics.shared.recordHTML(
                category: "CAS",
                label: "GET 表单解析失败 hasSalt=\(salt != nil) hasExecution=\(execution != nil)",
                html: html,
                url: pageResponse.url,
                statusCode: getStatus
            )
            throw AppError.parseFailed
        }
        let lt = html.firstMatch(#"id="lt"[^>]*value="([^"]*)""#) ?? ""
        LoginDiagnostics.shared.record(category: "CAS", message: "表单字段提取完成 saltLen=\(salt.count), hasExecution=true, hasLt=\(!lt.isEmpty)")

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

        NetRedirectTracer.reset()
        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await Net.session.data(for: request)
        } catch {
            LoginDiagnostics.shared.recordRedirectHops(NetRedirectTracer.lastHops, category: "CAS", label: "POST登录")
            LoginDiagnostics.shared.record(category: "CAS", message: "POST 登录请求失败", url: url, error: error)
            throw error
        }
        let postStatus = (response as? HTTPURLResponse)?.statusCode
        let finalHost = response.url?.host ?? ""
        let finalHTML = String(data: responseData, encoding: .utf8) ?? ""
        LoginDiagnostics.shared.recordRedirectHops(NetRedirectTracer.lastHops, category: "CAS", label: "POST登录")
        LoginDiagnostics.shared.record(category: "CAS", message: "POST 登录响应完成 bytes=\(responseData.count)", url: response.url, statusCode: postStatus)

        if finalHost.contains("authserver") || finalHTML.contains("id=\"pwdEncryptSalt\"") {
            // 登录失败回到的页面本身就带验证码/动态码字样，不能只看提示文案。
            // 先看服务端是不是把验证码开关打开了——这就是"要验证码"最可靠的信号，
            // 这种情况下提示经常只写"用户名或密码错误"，照着显示会把人带沟里。
            if Self.captchaRequired(in: finalHTML) {
                LoginDiagnostics.shared.recordHTML(category: "CAS", label: "POST 后要求验证码(captchaSwitch)", html: finalHTML, url: response.url, statusCode: postStatus)
                throw AppError.needCaptcha
            }
            let message = errorMessage(from: finalHTML)
            LoginDiagnostics.shared.recordHTML(category: "CAS", label: "POST 留在认证页 extractedMsg=\(message)", html: finalHTML, url: response.url, statusCode: postStatus)
            if message.contains("验证码") || message.contains("动态码") {
                throw AppError.needCaptcha
            }
            throw AppError.loginFailed(message)
        }
        LoginDiagnostics.shared.record(category: "CAS", message: "CAS 原生登录落地成功", url: response.url, statusCode: postStatus)
    }

    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await Net.session.data(from: url)
        } catch {
            throw AppError.network(error.localizedDescription)
        }
    }

    /// 服务端的验证码开关。有的页面写 `var captchaSwitch = "1";`，
    /// 有的写 `captchaSwitch = 1;`，两种都认
    static func captchaRequired(in html: String) -> Bool {
        guard let value = html.firstMatch(#"captchaSwitch\s*=\s*['"]?([A-Za-z0-9]+)"#) else {
            return false
        }
        return value == "1" || value.lowercased() == "true"
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
