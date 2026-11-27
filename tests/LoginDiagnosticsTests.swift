import Foundation

enum AppError: LocalizedError {
    case needCaptcha
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .needCaptcha: return "needCaptcha"
        case .loginFailed(let message): return message
        }
    }
}

@main
struct LoginDiagnosticsTests {
    static func main() async {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, "FAILED: \(label)")
            count += 1
        }

        // 1. URL sanitization
        let casURL = "https://user:pass@authserver.xatu.edu.cn/authserver/login;jsessionid=SECRET_JSESS_123?service=http%3A%2F%2Fjwgl2018.xatu.edu.cn%2Feams%2FhomeExt.action%3Bjsessionid%3DABC999%3Fticket%3DST-123456-abcdef&execution=e1s1SECRET&cllt=userNameLogin#token=xyz"
        let cleanURL = LoginDiagnosticRedactor.sanitizeURLString(casURL)
        check(!cleanURL.contains("user:pass"), "userinfo stripped")
        check(!cleanURL.contains("SECRET_JSESS_123"), "path jsessionid stripped")
        check(!cleanURL.contains("ABC999"), "nested service jsessionid stripped")
        check(!cleanURL.contains("ST-123456-abcdef"), "nested service ticket redacted")
        check(!cleanURL.contains("e1s1SECRET"), "execution query value redacted")
        check(!cleanURL.contains("token=xyz"), "fragment redacted")
        check(cleanURL.contains("authserver.xatu.edu.cn/authserver/login"), "host and path preserved")
        check(cleanURL.contains("jwgl2018.xatu.edu.cn/eams/homeExt.action"), "nested service host and path preserved")
        check(cleanURL.contains("cllt=userNameLogin"), "safe scalar query key preserved")

        // 2. Text redaction
        let secretPass = "My$ecretP@ss99"
        let secretStu = "2206010123"
        let rawText = """
        登录失败 username=\(secretStu) password=\(secretPass)
        联系手机 13812345678 邮箱 alice@example.com 身份证 61010220040102123X
        欢迎您，张三 <input id="pwdEncryptSalt" value="SALT_SECRET_999" />
        CASTGC=TGT-999999999999999999999999999999
        """
        let redacted = LoginDiagnosticRedactor.redact(rawText, secrets: [secretStu, secretPass])
        check(!redacted.contains(secretPass), "password redacted")
        check(!redacted.contains(secretStu), "student id redacted")
        check(!redacted.contains("13812345678"), "phone redacted")
        check(!redacted.contains("alice@example.com"), "email redacted")
        check(!redacted.contains("61010220040102123X"), "id card redacted")
        check(!redacted.contains("张三"), "chinese name redacted")
        check(!redacted.contains("SALT_SECRET_999"), "input value redacted")
        check(!redacted.contains("TGT-999999999999999999999999999999"), "CASTGC redacted")

        // 3. Cookie metadata only (never values)
        let secretCookieValue = "SUPER_SECRET_COOKIE_VAL_888"
        let cookie = HTTPCookie(properties: [
            .domain: ".xatu.edu.cn",
            .path: "/",
            .name: "CASTGC",
            .value: secretCookieValue,
            .secure: "TRUE"
        ])!
        let otherCookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "OTHER",
            .value: "IGNORE_ME"
        ])!
        let described = LoginDiagnosticRedactor.describeCookies([cookie, otherCookie]).joined(separator: "\n")
        check(described.contains("CASTGC"), "xatu cookie name present")
        check(described.contains(".xatu.edu.cn"), "xatu cookie domain present")
        check(!described.contains(secretCookieValue), "cookie value never emitted")
        check(!described.contains("example.com"), "non-xatu cookie excluded")

        // 4. HTML summary
        let html = """
        <html><head><title>统一身份认证</title></head>
        <body>
        <script>var captchaSwitch = "1";</script>
        <input id="pwdEncryptSalt" value="SALT123456" />
        <span id="msg">请输入验证码 2206010123</span>
        </body></html>
        """
        let htmlSummary = LoginDiagnosticRedactor.summarizeHTML(html, secrets: [secretStu])
        check(htmlSummary.contains("统一身份认证"), "title extracted")
        check(htmlSummary.contains("pwdEncryptSalt"), "pwdEncryptSalt marker detected")
        check(htmlSummary.contains("captchaSwitch"), "captchaSwitch marker detected")
        check(!htmlSummary.contains("SALT123456"), "salt value not leaked")
        check(!htmlSummary.contains(secretStu), "student id in page error redacted")

        // 5. Full report build
        LoginDiagnostics.shared.beginAttempt(trigger: "nativeLogin", studentID: secretStu, password: secretPass)
        LoginDiagnostics.shared.record(
            category: "CAS",
            message: "POST 失败 \(secretPass)",
            url: URL(string: "https://authserver.xatu.edu.cn/authserver/login?ticket=ST-SECRET-999"),
            statusCode: 200,
            error: AppError.needCaptcha
        )
        let webSnapshot = WebLoginLiveSnapshot(
            currentURL: "https://authserver.xatu.edu.cn/authserver/login?ticket=ST-WEB-888",
            title: "统一身份认证",
            isLoading: false,
            estimatedProgress: 1.0,
            canGoBack: false,
            canGoForward: false,
            readyState: "complete",
            domFlags: ["pwdEncryptSalt", "captchaElement"],
            visibleErrors: ["账号 \(secretStu) 需要手机动态码"],
            textSnippet: "欢迎您，李四 请输入动态码",
            jsProbeError: nil,
            webCookies: [cookie]
        )
        let report = await LoginDiagnostics.shared.buildReport(
            webSnapshot: webSnapshot,
            appSummary: ["isLoggedIn=false", "isLoading=false"],
            eamsShellStatus: 302,
            eamsShellURL: "http://jwgl2018.xatu.edu.cn/eams/courseTableForStd.action;jsessionid=EAMS_SECRET",
            eamsShellHTML: "<html><title>教务系统</title><body>请先完成评教</body></html>",
            eamsTableStatus: nil,
            eamsTableURL: "",
            eamsTableHTML: "",
            eamsLastError: "课表外壳页回到了树维登录页"
        )
        check(report.contains("XATune 登录诊断报告"), "report header present")
        check(report.contains("登录过程时间线"), "timeline section present")
        check(report.contains("当前网页实时状态"), "web snapshot section present")
        check(report.contains("WKWebView Cookie 元数据"), "wkwebview cookie section present")
        check(report.contains("evaluation"), "evaluation marker detected in shell html")
        check(!report.contains(secretPass), "report never leaks password")
        check(!report.contains(secretStu), "report never leaks student id")
        check(!report.contains(secretCookieValue), "report never leaks cookie value")
        check(!report.contains("ST-SECRET-999"), "report never leaks cas ticket")
        check(!report.contains("ST-WEB-888"), "report never leaks web ticket")
        check(!report.contains("EAMS_SECRET"), "report never leaks jsessionid")
        check(!report.contains("李四"), "report never leaks chinese name")

        print("LoginDiagnosticsTests passed (\(count) checks)")
    }
}
