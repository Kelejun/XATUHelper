import Foundation

/// 缴费平台（jfpay）的只读接口。
/// 只做查询，不碰下单，所以不用管金额和支付渠道。
struct PayService {
    static let apiBase = "https://jfpay.xatu.edu.cn/api/"
    /// 缴费平台的 CAS service，和登录页上的"统一身份认证登录"走同一个入口
    static let casService = "https://jfpay.xatu.edu.cn/casLogin/"

    /// 出错时留一份原始响应，方便设置页复制
    static var lastError: String?

    // MARK: - 会话

    /// 借统一认证那边的登录态换一份 jfpay 的 cookie。
    /// TGC 还活着就是一路 302 到 jfpay；过期了会停在 authserver 的登录页。
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
        guard let list = data as? [[String: Any]] else { throw AppError.parseFailed }

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
        guard let first = (data as? [[String: Any]])?.first else { throw AppError.parseFailed }
        guard let value = text(first["oddl"]) else { throw AppError.parseFailed }
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
        if let token = token() {
            request.setValue(token, forHTTPHeaderField: "X-Token")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await Net.session.data(for: request)
        let host = response.url?.host ?? ""
        let raw = String(data: data, encoding: .utf8) ?? ""
        if host.contains("authserver") || raw.contains("pwdEncryptSalt") {
            throw AppError.sessionExpired
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.lastError = "\(path) 返回的不是 JSON：\(raw.prefix(500))"
            throw AppError.parseFailed
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

    private func options(_ data: Any, idKey: String, nameKey: String) -> [DormOption] {
        guard let list = data as? [[String: Any]] else { return [] }
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
