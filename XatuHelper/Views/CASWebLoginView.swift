import SwiftUI
import WebKit

/// 持有当前登录 WebView 的弱引用，供"无法登录？"导出实时网页状态快照。
@MainActor
final class CASWebLoginController: ObservableObject {
    weak var webView: WKWebView?

    func captureSnapshot() async -> WebLoginLiveSnapshot? {
        guard let webView else { return nil }
        let currentURL = webView.url?.absoluteString ?? ""
        let title = webView.title ?? ""
        let isLoading = webView.isLoading
        let estimatedProgress = webView.estimatedProgress
        let canGoBack = webView.canGoBack
        let canGoForward = webView.canGoForward

        async let probe = evaluateDOMProbe(in: webView)
        async let cookies = fetchCookies(from: webView)
        let (probeResult, webCookies) = await (probe, cookies)

        return WebLoginLiveSnapshot(
            currentURL: currentURL,
            title: title,
            isLoading: isLoading,
            estimatedProgress: estimatedProgress,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            readyState: probeResult.readyState,
            domFlags: probeResult.domFlags,
            visibleErrors: probeResult.visibleErrors,
            textSnippet: probeResult.textSnippet,
            jsProbeError: probeResult.error,
            webCookies: webCookies
        )
    }

    private struct DOMProbeResult {
        var readyState = "unknown"
        var domFlags: [String] = []
        var visibleErrors: [String] = []
        var textSnippet = ""
        var error: String?
    }

    /// 仅读取页面结构特征与可见错误提示，严禁读取输入框值或 document.cookie。
    private static let domProbeScript = """
    (function() {
      var flags = [];
      if (document.getElementById('pwdEncryptSalt')) flags.push('pwdEncryptSalt');
      if (document.getElementById('execution') || document.querySelector('input[name="execution"]')) flags.push('execution');
      if (document.querySelector('input[type="password"]')) flags.push('passwordInput');
      if (document.querySelector('input[name*="captcha" i], img[id*="captcha" i], img[src*="captcha" i], #captchaResponse')) flags.push('captchaElement');
      if (document.querySelector('input[name*="dynamic" i], #dynamicCode, #mobile')) flags.push('dynamicCodeElement');
      if (document.querySelector('[class*="slider" i], [id*="slider" i], [class*="geetest" i], [class*="verify" i]')) flags.push('sliderOrVerify');
      if (document.querySelector('iframe')) flags.push('hasIframe(' + document.querySelectorAll('iframe').length + ')');
      if (typeof window.captchaSwitch !== 'undefined') flags.push('captchaSwitch=' + String(window.captchaSwitch));
      var form = document.querySelector('form');
      if (form && form.getAttribute('action')) {
        try {
          var actionURL = new URL(form.getAttribute('action'), location.href);
          flags.push('formAction=' + actionURL.host + actionURL.pathname);
        } catch (e) {}
      }
      var selectors = ['#msg', '.auth_error', '#errorMsg', '.ant-message', '.el-message', '[role="alert"]', '.error-msg', '.tips'];
      var errors = [];
      for (var i = 0; i < selectors.length; i++) {
        var nodes = document.querySelectorAll(selectors[i]);
        for (var j = 0; j < nodes.length && errors.length < 5; j++) {
          var el = nodes[j];
          var txt = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
          if (txt && txt.length > 0) {
            errors.push(txt.slice(0, 140));
          }
        }
      }
      var bodyText = ((document.body && document.body.innerText) || '').replace(/\\s+/g, ' ').trim().slice(0, 320);
      return {
        readyState: document.readyState || 'unknown',
        flags: flags,
        errors: errors,
        textSnippet: bodyText
      };
    })();
    """

    private func evaluateDOMProbe(in webView: WKWebView) async -> DOMProbeResult {
        await withCheckedContinuation { continuation in
            var completed = false
            let finish: (DOMProbeResult) -> Void = { result in
                guard !completed else { return }
                completed = true
                continuation.resume(returning: result)
            }

            webView.evaluateJavaScript(Self.domProbeScript) { value, error in
                if let error {
                    finish(DOMProbeResult(error: error.localizedDescription))
                    return
                }
                guard let dict = value as? [String: Any] else {
                    finish(DOMProbeResult(error: "unexpected JS probe result"))
                    return
                }
                let result = DOMProbeResult(
                    readyState: dict["readyState"] as? String ?? "unknown",
                    domFlags: dict["flags"] as? [String] ?? [],
                    visibleErrors: dict["errors"] as? [String] ?? [],
                    textSnippet: dict["textSnippet"] as? String ?? "",
                    error: nil
                )
                finish(result)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                finish(DOMProbeResult(error: "JS probe timeout"))
            }
        }
    }

    private func fetchCookies(from webView: WKWebView) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            var completed = false
            let finish: ([HTTPCookie]) -> Void = { cookies in
                guard !completed else { return }
                completed = true
                continuation.resume(returning: cookies)
            }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                finish(cookies)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                finish([])
            }
        }
    }
}

/// 需要验证码、手机动态码这类网页才走得通的登录，弹一个内置浏览器让用户自己过。
/// 登录成功后把 WKWebView 里的 cookie 搬回 URLSession 的共享存储，后面的请求就能接着用了。
struct CASWebLoginView: UIViewRepresentable {
    let startURL: URL
    let controller: CASWebLoginController
    /// 成功拿到业务系统会话传 true，用户中途放弃传 false
    var onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        controller.webView = webView

        // 先把陈旧的校园 cookie 清掉，免得带着过期会话反复弹回登录页
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.contains("xatu.edu.cn") }
            LoginDiagnostics.shared.record(
                category: "WEB",
                message: "初始化网页登录，清理旧 WKWebView Cookie count=\(stale.count)",
                url: startURL
            )
            guard !stale.isEmpty else {
                DispatchQueue.main.async { webView.load(URLRequest(url: startURL)) }
                return
            }
            let group = DispatchGroup()
            for cookie in stale {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                webView.load(URLRequest(url: startURL))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: CASWebLoginView
        private var finished = false

        init(_ parent: CASWebLoginView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isMain = navigationAction.targetFrame?.isMainFrame ?? false
            let isPopup = navigationAction.targetFrame == nil
            if isMain || isPopup {
                let method = navigationAction.request.httpMethod ?? "GET"
                let type = Self.describeNavigationType(navigationAction.navigationType)
                let frameTag = isPopup ? "newWindow" : "mainFrame"
                LoginDiagnostics.shared.record(
                    category: "WEB",
                    message: "decideAction(\(frameTag)) method=\(method) type=\(type)",
                    url: navigationAction.request.url
                )
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame {
                let http = navigationResponse.response as? HTTPURLResponse
                let mime = navigationResponse.response.mimeType ?? "unknown"
                LoginDiagnostics.shared.record(
                    category: "WEB",
                    message: "decideResponse mime=\(mime) canShow=\(navigationResponse.canShowMIMEType)",
                    url: navigationResponse.response.url,
                    statusCode: http?.statusCode
                )
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            LoginDiagnostics.shared.record(category: "WEB", message: "didStartProvisional", url: webView.url)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            LoginDiagnostics.shared.record(category: "WEB", message: "didReceiveServerRedirect", url: webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            LoginDiagnostics.shared.record(category: "WEB", message: "didCommit", url: webView.url)
        }

        /// 落到教务或缴费的页面，说明 ticket 已经换成业务系统会话了，这时候再把 cookie 捞出来
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let host = webView.url?.host ?? ""
            let matched = host.contains("jwgl2018") || host.contains("jfpay")
            LoginDiagnostics.shared.record(
                category: "WEB",
                message: "didFinish matchedBusinessHost=\(matched) alreadyFinished=\(finished)",
                url: webView.url
            )
            guard !finished, matched else { return }

            finished = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let shared = cookies.filter { $0.domain.contains("xatu.edu.cn") }
                for cookie in shared {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                let names = shared.map(\.name).sorted().joined(separator: ",")
                LoginDiagnostics.shared.record(
                    category: "WEB",
                    message: "搬运 WKWebView Cookie 到共享存储 count=\(shared.count) names=[\(names)]",
                    url: webView.url
                )
                DispatchQueue.main.async {
                    self.parent.onFinished(!shared.isEmpty)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            LoginDiagnostics.shared.record(category: "WEB", message: "didFail", url: webView.url, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            LoginDiagnostics.shared.record(category: "WEB", message: "didFailProvisional", url: webView.url, error: error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            LoginDiagnostics.shared.record(category: "WEB", message: "WebContent 进程异常终止", url: webView.url)
        }

        private static func describeNavigationType(_ type: WKNavigationType) -> String {
            switch type {
            case .linkActivated: return "linkActivated"
            case .formSubmitted: return "formSubmitted"
            case .backForward: return "backForward"
            case .reload: return "reload"
            case .formResubmitted: return "formResubmitted"
            case .other: return "other"
            @unknown default: return "unknown"
            }
        }
    }
}

struct CASWebLoginSheet: View {
    @EnvironmentObject var app: AppState
    @StateObject private var webController = CASWebLoginController()
    @State private var completionTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var showHelpAlert = false
    @State private var isExportingDiagnostics = false
    @State private var sharedFile: DiagnosticSharedFile?
    @State private var temporaryDirectory: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            CASWebLoginView(startURL: CASService.loginURL(), controller: webController) { success in
                if success {
                    completionTask = Task { await app.completeWebLogin() }
                } else {
                    LoginDiagnostics.shared.record(category: "WEB", message: "网页登录落地后未获取到有效 xatu.edu.cn Cookie")
                }
            }
            .id(app.webLoginSessionID)
            .onDisappear {
                completionTask?.cancel()
                exportTask?.cancel()
                removeTemporaryFile()
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if app.isLoading || isExportingDiagnostics {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("在网页里登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { app.cancelWebLogin() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("无法登录？") { showHelpAlert = true }
                        .disabled(isExportingDiagnostics)
                }
            }
            .alert("无法登录？", isPresented: $showHelpAlert) {
                Button("导出诊断报告") { exportDiagnostics() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("可以导出脱敏后的登录诊断报告并发送给开发者排查。报告不包含密码、学号及 Cookie 值等敏感信息。")
            }
            .sheet(item: $sharedFile, onDismiss: removeTemporaryFile) { file in
                DiagnosticShareSheet(url: file.url) { error in
                    exportError = error.localizedDescription
                }
            }
            .alert("导出失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("好", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private func exportDiagnostics() {
        guard !isExportingDiagnostics else { return }
        isExportingDiagnostics = true
        exportTask?.cancel()
        exportTask = Task {
            defer { isExportingDiagnostics = false }
            let snapshot = await webController.captureSnapshot()
            guard !Task.isCancelled else { return }
            let report = await app.buildLoginDiagnosticReport(webSnapshot: snapshot)
            guard !Task.isCancelled else { return }
            do {
                removeTemporaryFile()
                let created = try DiagnosticSharedFile.writeTemporary(
                    prefix: "XATune-login-diagnostics",
                    content: report
                )
                temporaryDirectory = created.directory
                sharedFile = created.file
            } catch {
                removeTemporaryFile()
                exportError = error.localizedDescription
            }
        }
    }

    private func removeTemporaryFile() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }
}
