import Foundation

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

        let (data, response) = try await Net.session.data(from: url)
        let host = response.url?.host ?? ""
        let html = String(data: data, encoding: .utf8) ?? ""
        if host.contains("authserver") || html.contains("pwdEncryptSalt") {
            throw AppError.sessionExpired
        }

        var tokenInURL: String?
        if let finalURL = response.url,
           let items = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?.queryItems {
            tokenInURL = items.first(where: { $0.name == "token" })?.value
            if let token = items.first(where: { $0.name == "token" })?.value, !token.isEmpty {
                storeToken(token)
            }
            if let serial = items.first(where: { $0.name == "idserial" })?.value, !serial.isEmpty {
                Self.idserial = serial
            }
        }

        Self.lastLogin = """
        GET \(url.absoluteString)
        → \(response.url?.absoluteString ?? "?")
        URL 里带 token：\(tokenInURL.map { "有（\($0.prefix(8))…）" } ?? "没有")
        cookie 里 token：\(token() == nil ? "没有" : "有")
        status：\((response as? HTTPURLResponse)?.statusCode ?? 0)
        内容开头：\(html.prefix(160))
        """

        // 没抠到 token 就当这次登录不算数，交给上层重新过一遍 CAS 再试
        if token() == nil {
            throw AppError.sessionExpired
        }
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

    /// 剩余电费（元），接口字段叫 oddl
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
        guard let value = text(first["oddl"]) else {
            throw AppError.loginFailed("余额字段对不上（\(Self.preview(first))）")
        }
        return value
    }

    // MARK: - 底层

    private func post(_ path: String, _ body: [String: Any]) async throws -> Any {
        try await request(path: path, method: "POST", body: body)
    }

    private func request(path: String, method: String, body: [String: Any]?) async throws -> Any {
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
