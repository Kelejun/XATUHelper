import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 把 CAS 到 jfpay 之间的每一次 302 都记下来
private final class RedirectTracer: NSObject, URLSessionTaskDelegate {
    private(set) var hops: [String] = []

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        record(response: response, request: request)
        completionHandler(request)
    }
    func record(response: HTTPURLResponse, request: URLRequest) {
        let target = request.url?.absoluteString ?? "?"
        hops.append("\(response.statusCode) → \(target)")
    }

}

/// 缴费平台（jfpay）的只读接口。
/// 只做查询，不碰下单，所以不用管金额和支付渠道。
struct PayService {
    static let apiBase = "https://jfpay.xatu.edu.cn/api/"
    /// 缴费平台的 CAS service，和登录页上的"统一身份认证登录"走同一个入口
    static let casService = "https://jfpay.xatu.edu.cn/casLogin/"

    /// 出错时留一份原始响应，方便设置页复制
    static var lastError: String?
    /// 最近一次请求的原始返回，诊断用
    static var lastRaw: String?
    /// CAS 回来带的 idserial，后面有的接口可能要用
    static var idserial: String?
    /// 登录这一跳的现场，出问题时打出来
    static var lastLogin: String?

    // MARK: - 会话

    /// 借统一认证那边的登录态换一份 jfpay 的 token。
    /// CAS 回来会跳到 /casLogin/?token=xxx&idserial=xxx，SPA 自己把这个 token 写进
    /// datalook_reimbursement_token 这个 cookie，再拿它当 X-Token 发请求。
    /// 我们不走浏览器，所以得自己把 token 从最终 URL 里抠出来存成 cookie。
    func loginWithExistingSession() async throws {
        var components = URLComponents(string: "https://authserver.xatu.edu.cn/authserver/login")
        components?.queryItems = [URLQueryItem(name: "service", value: Self.casService)]
        guard let url = components?.url else { throw AppError.badURL }

        // 自己跟一遍 302，把每一跳都记下来，出问题时能直接看到 token 是在哪一步给的
        let tracer = RedirectTracer()
        let session = ScopedHTTPSession { response, request in
            tracer.record(response: response, request: request)
        }
        let (data, response) = try await session.data(from: url)
        let host = response.url?.host ?? ""
        let html = String(data: data, encoding: .utf8) ?? ""
        if host.contains("authserver") || html.contains("pwdEncryptSalt") {
            throw AppError.sessionExpired
        }

        var tokenInURL: String?
        if let finalURL = response.url?.absoluteString {
            let parsed = Self.parseLoginURL(finalURL)
            tokenInURL = parsed.token
            if let token = parsed.token { storeToken(token) }
            if let serial = parsed.serial { Self.idserial = serial }
        }

        Self.lastLogin = """
        跳转链：
        \(tracer.hops.isEmpty ? "（没有跳转）" : tracer.hops.joined(separator: "\n"))
        GET \(url.absoluteString)
        → \(response.url?.absoluteString ?? "?")
        URL 里带 token：\(tokenInURL.map { "有（\($0.prefix(8))…）" } ?? "没有")
        cookie 里 token：\(token() == nil ? "没有" : "有")
        status：\((response as? HTTPURLResponse)?.statusCode ?? 0)
        内容开头：\(html.prefix(3000))
        """

        // 拿到票之后平台会给一个跳 js 的页面，里面写着真正的换票地址
        if token() == nil, let jump = Self.jzcasURL(from: html) {
            do {
                let (jumpData, jumpResponse) = try await Net.session.data(from: jump)
                let jumpHTML = String(data: jumpData, encoding: .utf8) ?? ""
                // 换完票的 token 藏在 #/middle_page?token=… 这种片段里，query 是取不到的
                if let jumpURL = jumpResponse.url?.absoluteString {
                    let parsed = Self.parseLoginURL(jumpURL)
                    if let token = parsed.token { storeToken(token) }
                    if let serial = parsed.serial { Self.idserial = serial }
                }
                Self.lastLogin = (Self.lastLogin ?? "") + """

                换票：GET \(jump.absoluteString)
                → \(jumpResponse.url?.absoluteString ?? "?")
                status：\((jumpResponse as? HTTPURLResponse)?.statusCode ?? 0)
                cookie 里 token：\(token() == nil ? "没有" : "有")
                cookie 名：\(HTTPCookieStorage.shared.cookies?.filter { $0.domain.contains("xatu") }.map(\.name).joined(separator: ",") ?? "-")
                内容开头：\(jumpHTML.prefix(400))
                """
            } catch {
                Self.lastLogin = (Self.lastLogin ?? "") + """

                换票：GET \(jump.absoluteString)
                请求本身失败：\(Net.describe(error))
                """
            }
        } else if token() == nil {
            Self.lastLogin = (Self.lastLogin ?? "") + """

            没在页面里找到 jzcas 换票地址
            """
        }

        // 没抠到 token 就当这次登录不算数，交给上层重新过一遍 CAS 再试
        if token() == nil {
            throw AppError.sessionExpired
        }
        CookieVault.pinAndSave()
    }

    /// 清掉 jfpay 的凭证，下次 request 会重新换一次
    func clearToken() {
        for cookie in HTTPCookieStorage.shared.cookies ?? []
        where cookie.name == "datalook_reimbursement_token" {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    /// token 可能挂在 query，也可能挂在 #/middle_page?token=… 这种片段里，两种都抠
    static func parseLoginURL(_ urlString: String) -> (token: String?, serial: String?) {
        let token = urlString.firstMatch(#"[?#&]token=([^&#]+)"#)
        let serial = urlString.firstMatch(#"[?#&]idserial=([^&#]+)"#)
        return (token, serial)
    }

    /// 从换票页里把 "jzcas/casLogin/学号/1" 这种真正的登录地址抠出来
    static func jzcasURL(from html: String) -> URL? {
        guard let path = html.firstMatch(#"(jzcas/casLogin/[0-9]+/[0-9]+)"#) else { return nil }
        return URL(string: "https://jfpay.xatu.edu.cn/api/pay/web/" + path)
    }

    /// 把 token 写进 cookie，后面的请求才能带 X-Token
    private func storeToken(_ value: String) {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: "jfpay.xatu.edu.cn",
            .path: "/",
            .name: "datalook_reimbursement_token",
            .value: value
        ]
        if let cookie = HTTPCookie(properties: properties) {
            HTTPCookieStorage.shared.setCookie(cookie)
            return
        }
        properties[.domain] = ".xatu.edu.cn"
        if let cookie = HTTPCookie(properties: properties) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// 前端把 token 放在 cookie 里，接口再通过 X-Token 头带上；两个都给它
    private func token() -> String? {
        HTTPCookieStorage.shared.cookies?
            .first { $0.name == "datalook_reimbursement_token" }?
            .value
    }

    // MARK: - 项目

    /// 找出"电费"这个收费项目
    func electricProjects() async throws -> [PayProject] {
        let data = try await request(path: "pay/project/getAllProjectList", method: "GET", body: nil)
        let list = Self.array(data)
        guard !list.isEmpty else {
            throw AppError.loginFailed("项目列表是空的（\(Self.preview(data))）")
        }

        return list.compactMap { dict -> PayProject? in
            guard let model = text(dict["proModelUrl"]),
                  model == "electric" || model == "electricNewCapec" else { return nil }
            guard let id = text(dict["id"]), !id.isEmpty else { return nil }
            let name = text(dict["projectName"]) ?? "电费"
            let code = text(dict["factoryCode"]) ?? ""
            return PayProject(id: id, name: name, modelURL: model, factoryCode: code)
        }
    }

    // MARK: - 校区 / 楼栋 / 房间

    func schools(projectID: String) async throws -> [DormOption] {
        let data = try await post("pay/web/payEleCostController/querySchoolList", ["projectId": projectID])
        return options(data, idKey: "schoolid", nameKey: "schoolname")
    }

    func buildings(projectID: String, areaID: String) async throws -> [DormOption] {
        let data = try await post("pay/web/payEleCostController/queryBuildingList",
                                  ["projectId": projectID, "areaid": areaID])
        return options(data, idKey: "buildid", nameKey: "buildname")
    }

    func rooms(projectID: String, areaID: String, buildID: String) async throws -> [DormOption] {
        let data = try await post("pay/web/payEleCostController/queryRoomList",
                                  ["projectId": projectID, "areaid": areaID, "buildid": buildID])
        return options(data, idKey: "roomid", nameKey: "roomname")
    }

    /// 剩余电费（元）
    /// 平台前端有两种口径：多数项目直接显示 oddl，但部分项目显示 suml - oddl。
    /// 实测本校：oddl=9183.18 是累计已用电金额，suml=9237.05 是累计充值，差 53.87 才是余额。
    func balance(projectID: String, dorm: DormSelection) async throws -> String {
        let data = try await post("pay/web/payEleCostController/querySydl", [
            "projectId": projectID,
            "areaid": dorm.areaID,
            "buildid": dorm.buildID,
            "roomid": dorm.roomID
        ])
        guard let first = Self.array(data).first else {
            throw AppError.loginFailed("余额接口没数据（\(Self.preview(data))）")
        }
        let oddl = Self.number(first["oddl"])
        let suml = Self.number(first["suml"])
        if let oddl, let suml {
            return Self.format(suml - oddl)
        }
        if let oddl {
            return Self.format(oddl)
        }
        throw AppError.loginFailed("余额字段对不上（\(Self.preview(first))）")
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - 底层

    private func post(_ path: String, _ body: [String: Any]) async throws -> Any {
        try await request(path: path, method: "POST", body: body)
    }

    /// 有凭证就直接打接口；只有没凭证、或平台说凭证过期了，才去 CAS 换一次票。
    /// 之前是每次查询都先过一遍 CAS，服务端会把那当成一次登录，账号容易被提示"频繁登录"。
    private func request(path: String, method: String, body: [String: Any]?) async throws -> Any {
        if token() == nil {
            try await loginWithExistingSession()
        }
        do {
            return try await send(path: path, method: method, body: body)
        } catch AppError.sessionExpired {
            clearToken()
            try await loginWithExistingSession()
            return try await send(path: path, method: method, body: body)
        }
    }

    private func send(path: String, method: String, body: [String: Any]?) async throws -> Any {
        guard let url = URL(string: Self.apiBase + path) else { throw AppError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let token = token() {
            request.setValue(token, forHTTPHeaderField: "X-Token")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await Net.session.data(for: request)
        let host = response.url?.host ?? ""
        let raw = String(data: data, encoding: .utf8) ?? ""
        Self.lastRaw = "\(method) \(path)\n→ \(raw.prefix(1500))"
        if host.contains("authserver") || raw.contains("pwdEncryptSalt") {
            throw AppError.sessionExpired
        }

        if response.url?.path.contains("casLogin") == true || raw.contains("<title>错误代码") {
            Self.lastError = "\(path) → 平台报错（疑似没拿到凭证）：\(raw.prefix(200))"
            throw AppError.loginFailed("缴费平台说服务器错误，多半是登录凭证没拿到")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            Self.lastError = "\(path) 返回的不是 JSON：\(raw.prefix(500))"
            throw AppError.loginFailed("返回的不是 JSON（\(raw.prefix(80))）")
        }
        // 有的接口外层包一层 {messageCode,message,data}，有的直接甩数组
        if let array = object as? [[String: Any]] { return array }
        guard let json = object as? [String: Any] else {
            Self.lastError = "\(path) 返回结构不认识：\(raw.prefix(500))"
            throw AppError.loginFailed("返回结构不认识（\(raw.prefix(80))）")
        }

        let code = text(json["messageCode"]) ?? ""
        let message = text(json["message"]) ?? "缴费平台返回 \(code)"

        switch code {
        case "0":
            return json["data"] ?? NSNull()
        case "-1", "-2", "-3", "-4", "-5", "50014":
            Self.lastError = "\(path) → \(code) \(message)"
            throw AppError.sessionExpired
        default:
            Self.lastError = "\(path) → \(code) \(message)"
            throw AppError.loginFailed(message)
        }
    }

    /// 后端有的接口直接给数组，有的包一层对象，两种都认
    static func array(_ data: Any) -> [[String: Any]] {
        if let list = data as? [[String: Any]] { return list }
        if let dict = data as? [String: Any] {
            for value in dict.values {
                if let list = value as? [[String: Any]] { return list }
            }
            return [dict]
        }
        return []
    }

    static func preview(_ value: Any) -> String {
        let text: String
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            text = json
        } else {
            text = String(describing: value)
        }
        return String(text.prefix(120))
    }

    private func options(_ data: Any, idKey: String, nameKey: String) -> [DormOption] {
        let list = Self.array(data)
        var seen = Set<String>()
        var result: [DormOption] = []
        for dict in list {
            guard let id = text(dict[idKey]), let name = text(dict[nameKey]) else { continue }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !trimmed.isEmpty, seen.insert(id).inserted else { continue }
            result.append(DormOption(id: id, name: trimmed))
        }
        return result
    }

    private func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
