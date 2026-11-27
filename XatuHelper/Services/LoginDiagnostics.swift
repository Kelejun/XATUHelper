import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

/// 登录诊断数据脱敏工具，确保导出的报告不包含密码、学号、Cookie 值、票据或个人身份信息。
enum LoginDiagnosticRedactor {
    private static let passthroughURLQueryKeys: Set<String> = [
        "service", "redirect", "redirect_uri", "redirecturl", "target", "url", "next", "goto"
    ]

    private static let safeScalarQueryKeys: Set<String> = [
        "locale", "lang", "type", "cllt", "dllt", "_eventid", "kind", "setting.kind"
    ]

    /// 脱敏 URL：保留 scheme/host/path，移除 userinfo、`;jsessionid=...`、fragment 及敏感 query 值。
    static func sanitizeURL(_ url: URL?) -> String {
        guard let url else { return "(nil)" }
        return sanitizeURLString(url.absoluteString)
    }

    static func sanitizeURLString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(empty)" }
        guard var components = URLComponents(string: trimmed) else {
            return redact(trimmed)
        }

        components.user = nil
        components.password = nil
        components.fragment = components.fragment.map { $0.isEmpty ? "" : "[REDACTED_FRAGMENT]" }
        if !components.path.isEmpty {
            components.path = stripPathSessionParams(components.path)
        }

        if let items = components.queryItems, !items.isEmpty {
            let renderedQuery = items.map { item -> String in
                let lowerKey = item.name.lowercased()
                guard let value = item.value, !value.isEmpty else {
                    return item.name
                }
                if passthroughURLQueryKeys.contains(lowerKey),
                   (value.hasPrefix("http://") || value.hasPrefix("https://")) {
                    return "\(item.name)=\(sanitizeURLString(value))"
                }
                if safeScalarQueryKeys.contains(lowerKey), value.count <= 32,
                   value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil {
                    return "\(item.name)=\(value)"
                }
                return "\(item.name)=[REDACTED]"
            }.joined(separator: "&")

            components.queryItems = nil
            let base = components.string ?? "\(components.scheme ?? "")://\(components.host ?? "")\(components.path)"
            return "\(base)?\(renderedQuery)"
        }

        return components.string ?? redact(trimmed)
    }

    /// 对任意诊断文本进行多层脱敏。
    static func redact(_ text: String, secrets: [String] = []) -> String {
        guard !text.isEmpty else { return text }
        var output = text

        // 1. 优先精确替换当前会话的已知敏感串（密码、学号等）
        let orderedSecrets = secrets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for secret in orderedSecrets {
            output = output.replacingOccurrences(of: secret, with: "[REDACTED]")
        }

        // 2. 替换文本中内嵌的完整 URL
        output = replaceRegex(
            in: output,
            pattern: #"https?://[^\s"'<>()（）]+"#,
            transform: { sanitizeURLString($0) }
        )

        // 3. 路径或参数中的会话票据与表单加密字段
        let rules: [(String, String)] = [
            (#"(?i);jsessionid=[A-Za-z0-9._-]+"#, ";jsessionid=[REDACTED]"),
            (#"(?i)\b(jsessionid|gsessionid|castgc|mod_auth_cas|ticket|st|token|access_token|refresh_token|execution|lt|pwdEncryptSalt|password|passwd|pwd|username|userName|mobile|phone|smsCode|dynamicCode)\s*[:=]\s*['"]?[^&\s"'<>;,]+['"]?"#, "$1=[REDACTED]"),
            (#"(?i)(<input\b[^>]*\bvalue\s*=\s*['"])[^'"]*(['"])"#, "$1[REDACTED]$2"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[REDACTED_EMAIL]"),
            (#"(?<!\d)\d{17}[\dXx](?!\d)"#, "[REDACTED_ID]"),
            (#"(?<!\d)1[3-9]\d{9}(?!\d)"#, "[REDACTED_PHONE]"),
            (#"(?<!\d)\d{8,16}(?!\d)"#, "[REDACTED_NUM]"),
            (#"(?i)(欢迎您|欢迎|当前用户|姓名)[：:，,\s]*[\p{Han}A-Za-z·]{2,12}"#, "$1：[REDACTED_NAME]"),
            (#"\b[A-Fa-f0-9]{32,}\b"#, "[REDACTED_HEX]"),
            (#"(?<=[=:])[A-Za-z0-9+/_-]{28,}={0,2}"#, "[REDACTED_TOKEN]")
        ]

        for (pattern, replacement) in rules {
            output = replacingMatches(in: output, pattern: pattern, with: replacement)
        }
        return output
    }

    /// 脱敏描述学号格式（只保留长度与字符特征，不暴露学号本身）。
    static func describeAccountShape(_ account: String?) -> String {
        guard let raw = account?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "empty"
        }
        let digitsOnly = raw.allSatisfy(\.isNumber)
        return "len=\(raw.count), digitsOnly=\(digitsOnly)"
    }

    /// 仅输出 Cookie 元数据，严禁读取或记录 `cookie.value`。
    static func describeCookies(_ cookies: [HTTPCookie]) -> [String] {
        let filtered = cookies
            .filter { $0.domain.lowercased().contains("xatu.edu.cn") }
            .sorted {
                if $0.domain != $1.domain { return $0.domain < $1.domain }
                if $0.path != $1.path { return $0.path < $1.path }
                return $0.name < $1.name
            }
        guard !filtered.isEmpty else { return ["(无 xatu.edu.cn Cookie)"] }
        return filtered.map { cookie in
            let expiry: String
            if let date = cookie.expiresDate {
                expiry = "expires=\(date.ISO8601Format())"
            } else {
                expiry = "sessionOnly"
            }
            var flags: [String] = []
            if cookie.isSecure { flags.append("Secure") }
            if cookie.isHTTPOnly { flags.append("HttpOnly") }
            if let policy = cookie.sameSitePolicy?.rawValue {
                flags.append("SameSite=\(policy)")
            }
            let flagText = flags.isEmpty ? "none" : flags.joined(separator: ",")
            return "\(cookie.domain)\(cookie.path) name=\(cookie.name) [\(flagText); \(expiry)]"
        }
    }

    /// 从 HTML 提取安全的结构摘要，方便排查页面改版、验证码、维护页、拦截页等问题。
    static func summarizeHTML(_ html: String, secrets: [String] = []) -> String {
        guard !html.isEmpty else { return "empty (0 bytes)" }
        let title = firstCapture(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#)
            .map(cleanText)
            .map { redact($0, secrets: secrets) } ?? "(无标题)"

        let markers: [(String, Bool)] = [
            ("pwdEncryptSalt", html.contains("pwdEncryptSalt")),
            ("execution", html.contains("id=\"execution\"") || html.contains("name=\"execution\"")),
            ("lt", html.contains("id=\"lt\"") || html.contains("name=\"lt\"")),
            ("captchaSwitch", html.contains("captchaSwitch")),
            ("captchaKeyword", html.contains("验证码") || html.lowercased().contains("captcha")),
            ("dynamicCode", html.contains("动态码") || html.lowercased().contains("dynamiccode")),
            ("slider", html.lowercased().contains("slider") || html.lowercased().contains("geetest") || html.contains("滑动")),
            ("loginExt", html.contains("loginExt.action")),
            ("passwordInput", html.contains("name=\"password\"") || html.contains("type=\"password\"")),
            ("courseTableIds", html.range(of: #""ids"\s*,\s*"\d+""#, options: .regularExpression) != nil),
            ("semesterCalendar", html.contains("semesterCalendar(")),
            ("maintenance", html.contains("维护") || html.contains("升级中") || html.contains("暂停服务")),
            ("evaluation", html.contains("评教") || html.contains("教学评价")),
            ("passwordChange", html.contains("修改密码") || html.contains("弱密码") || html.contains("重置密码"))
        ]
        let activeMarkers = markers.filter(\.1).map(\.0)

        var lines: [String] = [
            "length=\(html.utf8.count)B, title=\(title)",
            "markers=\(activeMarkers.isEmpty ? "none" : activeMarkers.joined(separator: ", "))"
        ]

        let errorPatterns = [
            #"(?is)id="msg"[^>]*>(.*?)</"#,
            #"(?is)class="auth_error"[^>]*>(.*?)</"#,
            #"(?is)id="errorMsg"[^>]*>(.*?)</"#,
            #"(?is)class="[^"]*error[^"]*"[^>]*>(.*?)</"#
        ]
        for pattern in errorPatterns {
            if let raw = firstCapture(in: html, pattern: pattern) {
                let cleaned = cleanText(raw)
                if !cleaned.isEmpty {
                    lines.append("pageError=\(redact(String(cleaned.prefix(160)), secrets: secrets))")
                    break
                }
            }
        }

        let strippedBody = stripHTMLToText(html)
        if !strippedBody.isEmpty {
            let snippet = redact(String(strippedBody.prefix(240)), secrets: secrets)
            lines.append("textSnippet=\(snippet)")
        }
        return lines.joined(separator: " | ")
    }

    private static func stripPathSessionParams(_ path: String) -> String {
        replacingMatches(in: path, pattern: #"(?i);jsessionid=[^/?#]*"#, with: ";jsessionid=[REDACTED]")
    }

    private static func stripHTMLToText(_ html: String) -> String {
        var text = replacingMatches(in: html, pattern: #"(?is)<(script|style|noscript)[^>]*>.*?</\1>"#, with: " ")
        text = replacingMatches(in: text, pattern: #"(?is)<[^>]+>"#, with: " ")
        return cleanText(text)
    }

    private static func cleanText(_ raw: String) -> String {
        let collapsed = replacingMatches(in: raw, pattern: #"\s+"#, with: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capture])
    }

    private static func replacingMatches(in text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replaceRegex(in text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matched = String(result[range])
            result.replaceSubrange(range, with: transform(matched))
        }
        return result
    }
}

/// 导出诊断报告时从当前 WKWebView 抓取的实时状态快照（不含输入值与 Cookie 值）。
struct WebLoginLiveSnapshot {
    var currentURL: String
    var title: String
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var readyState: String
    var domFlags: [String]
    var visibleErrors: [String]
    var textSnippet: String
    var jsProbeError: String?
    var webCookies: [HTTPCookie]
}

/// 登录全链路诊断记录器（线程安全，供 CASService、AppState、CASWebLoginView 写入）。
final class LoginDiagnostics {
    static let shared = LoginDiagnostics()

    struct Entry {
        let timestamp: Date
        let elapsedMs: Int
        let category: String
        let message: String
    }

    private let lock = NSLock()
    private var attemptStartedAt = Date()
    private var attemptTrigger = "unknown"
    private var accountShape = "empty"
    private var secrets: [String] = []
    private var entries: [Entry] = []
    private let maxEntries = 140

    private init() {}

    func beginAttempt(trigger: String, studentID: String?, password: String?) {
        lock.lock()
        attemptStartedAt = Date()
        attemptTrigger = trigger
        accountShape = LoginDiagnosticRedactor.describeAccountShape(studentID)
        var newSecrets: [String] = []
        if let studentID, studentID.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
            newSecrets.append(studentID)
        }
        if let password, !password.isEmpty {
            newSecrets.append(password)
        }
        secrets = newSecrets
        entries.removeAll(keepingCapacity: true)
        lock.unlock()

        record(category: "LOGIN", message: "开始登录尝试 trigger=\(trigger), account=(\(accountShape))")
    }

    func registerKnownStudentID(_ studentID: String?) {
        guard let id = studentID?.trimmingCharacters(in: .whitespacesAndNewlines), id.count >= 4 else { return }
        lock.lock()
        if !secrets.contains(id) {
            secrets.append(id)
        }
        if accountShape == "empty" {
            accountShape = LoginDiagnosticRedactor.describeAccountShape(id)
        }
        lock.unlock()
    }

    func clearPasswordSecret() {
        lock.lock()
        // 仅保留学号长度特征和已知学号用于脱敏，不长期滞留密码
        if secrets.count > 1 {
            secrets = Array(secrets.prefix(1))
        }
        lock.unlock()
    }

    func record(category: String, message: String, url: URL? = nil, statusCode: Int? = nil, error: Error? = nil) {
        var parts = [message]
        if let statusCode {
            parts.append("status=\(statusCode)")
        }
        if let url {
            parts.append("url=\(LoginDiagnosticRedactor.sanitizeURL(url))")
        }
        if let error {
            parts.append("error=\(describeError(error))")
        }
        append(category: category, rawMessage: parts.joined(separator: " | "))
    }

    func recordRedirectHops(_ hops: [String], category: String, label: String) {
        guard !hops.isEmpty else { return }
        let trail = hops.suffix(10).map { LoginDiagnosticRedactor.sanitizeURLString($0) }.joined(separator: " -> ")
        append(category: category, rawMessage: "\(label) redirects(\(hops.count)): \(trail)")
    }

    func recordHTML(category: String, label: String, html: String, url: URL? = nil, statusCode: Int? = nil) {
        let currentSecrets = snapshotSecrets()
        var parts = [label]
        if let statusCode {
            parts.append("status=\(statusCode)")
        }
        if let url {
            parts.append("url=\(LoginDiagnosticRedactor.sanitizeURL(url))")
        }
        parts.append(LoginDiagnosticRedactor.summarizeHTML(html, secrets: currentSecrets))
        append(category: category, rawMessage: parts.joined(separator: " | "))
    }

    func buildReport(
        webSnapshot: WebLoginLiveSnapshot?,
        appSummary: [String],
        eamsShellStatus: Int?,
        eamsShellURL: String,
        eamsShellHTML: String,
        eamsTableStatus: Int?,
        eamsTableURL: String,
        eamsTableHTML: String,
        eamsLastError: String
    ) async -> String {
        let networkSummary = await Self.captureNetworkSummary()
        let proxySummary = Self.captureProxySummary()
        let sharedCookies = LoginDiagnosticRedactor.describeCookies(HTTPCookieStorage.shared.cookies ?? [])

        let snapshot = snapshotState()
        let startedAt = snapshot.startedAt
        let trigger = snapshot.trigger
        let shape = snapshot.accountShape
        let recordedEntries = snapshot.entries
        let currentSecrets = snapshot.secrets

        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info["CFBundleVersion"] as? String ?? "?"
        let deviceModel = Self.deviceModelIdentifier()
        #if canImport(UIKit)
        let iosVersion = await MainActor.run { UIDevice.current.systemVersion }
        #else
        let iosVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        var sections: [String] = []

        sections.append([
            "===== XATune 登录诊断报告（已脱敏）=====",
            "ExportTime: \(Date().ISO8601Format())",
            "TimeZone: \(TimeZone.current.identifier) (offset=\(TimeZone.current.secondsFromGMT())s)",
            "App: \(shortVersion) (\(buildNumber)) commit=\(BuildInfo.commit) builtAt=\(BuildInfo.builtAt)",
            "Device: \(deviceModel) / iOS \(iosVersion)",
            "Locale: \(Locale.current.identifier)",
            "AttemptStart: \(startedAt.ISO8601Format())",
            "AttemptTrigger: \(trigger)",
            "AccountShape: \(shape)",
            "Network: \(networkSummary)",
            "SystemProxy: \(proxySummary)"
        ].joined(separator: "\n"))

        if !appSummary.isEmpty {
            sections.append((["===== 应用状态 ====="] + appSummary).joined(separator: "\n"))
        }

        let timelineLines: [String]
        if recordedEntries.isEmpty {
            timelineLines = ["(本次会话暂无记录到的登录事件)"]
        } else {
            timelineLines = recordedEntries.map { entry in
                let offset = String(format: "+%05dms", max(0, entry.elapsedMs))
                return "[\(entry.timestamp.ISO8601Format())] \(offset) [\(entry.category)] \(entry.message)"
            }
        }
        sections.append((["===== 登录过程时间线 ====="] + timelineLines).joined(separator: "\n"))

        if let webSnapshot {
            var webLines: [String] = [
                "===== 当前网页实时状态 =====",
                "URL: \(LoginDiagnosticRedactor.sanitizeURLString(webSnapshot.currentURL))",
                "Title: \(LoginDiagnosticRedactor.redact(webSnapshot.title, secrets: currentSecrets))",
                "Loading: \(webSnapshot.isLoading), Progress: \(String(format: "%.2f", webSnapshot.estimatedProgress))",
                "History: canGoBack=\(webSnapshot.canGoBack), canGoForward=\(webSnapshot.canGoForward)",
                "ReadyState: \(webSnapshot.readyState)",
                "DOMFlags: \(webSnapshot.domFlags.isEmpty ? "none" : webSnapshot.domFlags.joined(separator: ", "))"
            ]
            if !webSnapshot.visibleErrors.isEmpty {
                let errors = webSnapshot.visibleErrors.map { LoginDiagnosticRedactor.redact($0, secrets: currentSecrets) }
                webLines.append("VisibleErrors: \(errors.joined(separator: " ; "))")
            }
            if !webSnapshot.textSnippet.isEmpty {
                webLines.append("TextSnippet: \(LoginDiagnosticRedactor.redact(webSnapshot.textSnippet, secrets: currentSecrets))")
            }
            if let jsProbeError = webSnapshot.jsProbeError {
                webLines.append("JSProbeError: \(LoginDiagnosticRedactor.redact(jsProbeError, secrets: currentSecrets))")
            }
            sections.append(webLines.joined(separator: "\n"))

            let webCookies = LoginDiagnosticRedactor.describeCookies(webSnapshot.webCookies)
            sections.append((["===== WKWebView Cookie 元数据（不含值）====="] + webCookies).joined(separator: "\n"))
        } else {
            sections.append("===== 当前网页实时状态 =====\n(未获取到 WebView 实例)")
        }

        sections.append((["===== URLSession 共享 Cookie 元数据（不含值）====="] + sharedCookies).joined(separator: "\n"))

        var eamsLines = [
            "===== 教务系统最近响应摘要（已脱敏）=====",
            "LastError: \(eamsLastError.isEmpty ? "无" : LoginDiagnosticRedactor.redact(eamsLastError, secrets: currentSecrets))"
        ]
        if !eamsShellHTML.isEmpty || eamsShellStatus != nil || !eamsShellURL.isEmpty {
            let statusText = eamsShellStatus.map(String.init) ?? "?"
            eamsLines.append("Shell: status=\(statusText), url=\(LoginDiagnosticRedactor.sanitizeURLString(eamsShellURL)), \(LoginDiagnosticRedactor.summarizeHTML(eamsShellHTML, secrets: currentSecrets))")
        }
        if !eamsTableHTML.isEmpty || eamsTableStatus != nil || !eamsTableURL.isEmpty {
            let statusText = eamsTableStatus.map(String.init) ?? "?"
            eamsLines.append("Table: status=\(statusText), url=\(LoginDiagnosticRedactor.sanitizeURLString(eamsTableURL)), \(LoginDiagnosticRedactor.summarizeHTML(eamsTableHTML, secrets: currentSecrets))")
        }
        sections.append(eamsLines.joined(separator: "\n"))

        let rawReport = sections.joined(separator: "\n\n")
        return LoginDiagnosticRedactor.redact(rawReport, secrets: currentSecrets)
    }

    // MARK: - 内部

    private func append(category: String, rawMessage: String) {
        let now = Date()
        lock.lock()
        let currentSecrets = secrets
        let elapsed = Int(now.timeIntervalSince(attemptStartedAt) * 1000)
        lock.unlock()

        let sanitized = LoginDiagnosticRedactor.redact(rawMessage, secrets: currentSecrets)

        lock.lock()
        entries.append(Entry(timestamp: now, elapsedMs: elapsed, category: category, message: sanitized))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
    }

    private struct StateSnapshot {
        let startedAt: Date
        let trigger: String
        let accountShape: String
        let entries: [Entry]
        let secrets: [String]
    }

    private func snapshotState() -> StateSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return StateSnapshot(
            startedAt: attemptStartedAt,
            trigger: attemptTrigger,
            accountShape: accountShape,
            entries: entries,
            secrets: secrets
        )
    }

    private func snapshotSecrets() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return secrets
    }

    private func describeError(_ error: Error) -> String {
        if let appError = error as? AppError {
            return "AppError(\(appError.localizedDescription))"
        }
        let ns = error as NSError
        var parts = ["\(ns.domain)#\(ns.code): \(ns.localizedDescription)"]
        if let failingURL = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (ns.userInfo["NSErrorFailingURLStringKey"] as? String).flatMap(URL.init(string:)) {
            parts.append("failingURL=\(LoginDiagnosticRedactor.sanitizeURL(failingURL))")
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)#\(underlying.code)")
        }
        return parts.joined(separator: ", ")
    }

    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let bytes = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return bytes.isEmpty ? "unknown" : bytes
    }

    private static func captureProxySummary() -> String {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return "unavailable"
        }
        let httpEnabled = (settings["HTTPEnable"] as? NSNumber)?.boolValue ?? false
        let httpsEnabled = (settings["HTTPSEnable"] as? NSNumber)?.boolValue ?? false
        let pacEnabled = (settings["ProxyAutoConfigEnable"] as? NSNumber)?.boolValue ?? false
        let socksEnabled = (settings["SOCKSEnable"] as? NSNumber)?.boolValue ?? false
        return "http=\(httpEnabled), https=\(httpsEnabled), pac=\(pacEnabled), socks=\(socksEnabled)"
    }

    private static func captureNetworkSummary() async -> String {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.cell.XatuHelper.loginDiagnostics.network")
            let finished = LockedFlag()

            monitor.pathUpdateHandler = { path in
                guard finished.claim() else { return }
                monitor.cancel()
                let status: String
                switch path.status {
                case .satisfied: status = "satisfied"
                case .unsatisfied: status = "unsatisfied"
                case .requiresConnection: status = "requiresConnection"
                @unknown default: status = "unknown"
                }
                var interfaces: [String] = []
                if path.usesInterfaceType(.wifi) { interfaces.append("wifi") }
                if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
                if path.usesInterfaceType(.wiredEthernet) { interfaces.append("ethernet") }
                if path.usesInterfaceType(.other) { interfaces.append("other/vpn") }
                if path.usesInterfaceType(.loopback) { interfaces.append("loopback") }
                let ifaceText = interfaces.isEmpty ? "none" : interfaces.joined(separator: ",")
                continuation.resume(
                    returning: "status=\(status), interfaces=[\(ifaceText)], expensive=\(path.isExpensive), constrained=\(path.isConstrained), ipv4=\(path.supportsIPv4), ipv6=\(path.supportsIPv6), dns=\(path.supportsDNS)"
                )
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 0.6) {
                guard finished.claim() else { return }
                monitor.cancel()
                continuation.resume(returning: "timeout")
            }
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
