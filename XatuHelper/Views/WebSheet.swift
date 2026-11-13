import SwiftUI
import WebKit

/// 一个通用的内置网页，给签到这类只能走网页的功能用。
struct WebSheet: View {
    let title: String
    let urlString: String
    /// 换票落地后要整页跳到的地址（用真正的 navigation，不是改 hash）
    var followUpURL: String? = nil
    var showsCloseButton = true
    var showsSidebarToggle = false
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var paymentError: String?
    @State private var reloadToken = 0
    @State private var usesFreshSession = false
    @State private var hasRedirectLoop = false
    @State private var diagnosticText = ""

    var body: some View {
        NavigationStack {
            Group {
                if let message = errorText {
                    ContentUnavailableView {
                        Label("打不开这个页面", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        if hasRedirectLoop {
                            Button("重新登录网页") {
                                usesFreshSession = true
                                hasRedirectLoop = false
                                errorText = nil
                                isLoading = true
                                reloadToken += 1
                            }
                        }
                        Button("重试") {
                            errorText = nil
                            isLoading = true
                            reloadToken += 1
                        }
                        if !diagnosticText.isEmpty {
                            DiagnosticExportButton(filenamePrefix: "XATune-web-diagnostics") { diagnosticText }
                        }
                    }
                } else if let url = Self.makeURL(urlString) {
                    WebPage(url: url, isLoading: $isLoading, errorText: $errorText,
                            paymentError: $paymentError, followUpURL: followUpURL,
                            usesFreshSession: usesFreshSession, hasRedirectLoop: $hasRedirectLoop,
                            diagnosticText: $diagnosticText)
                        .id(reloadToken)
                } else {
                    ContentUnavailableView("地址不对", systemImage: "link.badge.plus")
                }
            }
            .campusSidebarToolbar(enabled: showsSidebarToggle)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .alert("无法打开支付应用", isPresented: Binding(
                get: { paymentError != nil },
                set: { if !$0 { paymentError = nil } }
            )) {
                Button("好", role: .cancel) { paymentError = nil }
            } message: {
                Text(paymentError ?? "")
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if let onClose { onClose() } else { dismiss() }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("关闭")
                    }
                }
                if isLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                    }
                }
            }
        }
    }

    /// 学校这套地址里带 * 和 # ，正常解码失败时退回百分号编码
    private static func makeURL(_ raw: String) -> URL? {
        if let url = URL(string: raw) { return url }
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: encoded)
    }
}

private struct WebPage: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorText: String?
    @Binding var paymentError: String?
    let followUpURL: String?
    let usesFreshSession: Bool
    @Binding var hasRedirectLoop: Bool
    @Binding var diagnosticText: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if usesFreshSession {
            config.websiteDataStore = .nonPersistent()
        }

        // WKWebView 自带的 navigator.geolocation 是空的，签到这类页面会一直转圈。
        // 注入一段垫片，把定位请求转给原生 CLLocationManager。
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "location")
        controller.addUserScript(WKUserScript(
            source: WebLocationScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = web

        // 把 app 已经拿到的 xatu cookie 带进 WebKit 的存储，少登一次。
        // setCookie 是异步的，等全部落盘再发第一个请求，否则第一次会被踢去登录页。
        if usesFreshSession {
            // 不导入共享 Cookie，也不删除其他网页或原生请求的会话。
            web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            return web
        }
        let store = web.configuration.websiteDataStore.httpCookieStore
        // 页面自己会写 token；先清掉旧的，免得 SPA 启动时读到过期值、后面怎么跳都报「系统维护」
        store.getAllCookies { existing in
            let stale = existing.filter { $0.domain.contains("jfpay.xatu.edu.cn") }
            let purge = DispatchGroup()
            for cookie in stale {
                purge.enter()
                store.delete(cookie) { purge.leave() }
            }
            purge.notify(queue: .main) {
                let cookies = (HTTPCookieStorage.shared.cookies ?? [])
                    .filter { $0.domain.contains("xatu.edu.cn") && !$0.domain.contains("jfpay.xatu.edu.cn") }
                let group = DispatchGroup()
                for cookie in cookies {
                    group.enter()
                    store.setCookie(cookie) { group.leave() }
                }
                group.notify(queue: .main) {
                    web.load(URLRequest(url: url))
                }
            }
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stopLocation()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "location")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorText: $errorText, paymentError: $paymentError,
                    followUpURL: followUpURL, usesFreshSession: usesFreshSession,
                    hasRedirectLoop: $hasRedirectLoop, diagnosticText: $diagnosticText,
                    allowsCustomLocation: url.host == "ehall.xatu.edu.cn"
                        && url.path.hasPrefix("/xsfw/sys/swmqdzsapp/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        @Binding private var isLoading: Bool
        @Binding private var errorText: String?
        @Binding private var paymentError: String?
        private let followUpURL: String?
        private let usesFreshSession: Bool
        @Binding private var hasRedirectLoop: Bool
        @Binding private var diagnosticText: String
        private var diagnosticEvents: [String] = []
        private var appliedFollowUp = false
        weak var webView: WKWebView?
        private let location: LocationBridge
        private var nextWatchID = 0
        private var watchIDs: [String: Int] = [:]

        init(isLoading: Binding<Bool>, errorText: Binding<String?>, paymentError: Binding<String?>,
             followUpURL: String?, usesFreshSession: Bool,
             hasRedirectLoop: Binding<Bool>, diagnosticText: Binding<String>, allowsCustomLocation: Bool) {
            _isLoading = isLoading
            _errorText = errorText
            _paymentError = paymentError
            self.followUpURL = followUpURL
            self.usesFreshSession = usesFreshSession
            _hasRedirectLoop = hasRedirectLoop
            _diagnosticText = diagnosticText
            self.location = LocationBridge(allowsCustomLocation: allowsCustomLocation)
        }

        func stopLocation() {
            location.stopAllWatching()
            watchIDs.removeAll()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "location",
                  let body = message.body as? [String: Any],
                  let id = body["id"] as? Int else { return }
            let frame = message.frameInfo
            let key = "\(body["context"] as? String ?? "main"):\(id)"
            if body["clear"] as? Bool == true {
                if let watchID = watchIDs.removeValue(forKey: key) {
                    location.stopWatching(id: watchID)
                }
                return
            }
            let isWatch = body["watch"] as? Bool ?? false
            if isWatch {
                nextWatchID += 1
                let watchID = nextWatchID
                watchIDs[key] = watchID
                location.startWatching(id: watchID) { [weak self] location in
                    guard let self, let location else { return }
                    WebLocationScript.reply(to: frame, in: self.webView, id: id, location: location)
                }
            } else {
                location.request { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case let .success(location):
                        WebLocationScript.reply(to: frame, in: self.webView, id: id, location: location)
                    case let .failure(error):
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        WebLocationScript.reply(to: frame, in: self.webView, id: id, error: message)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, openPaymentApp(url) {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame != false {
                trace("navigate", url: navigationAction.request.url)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            trace("redirect", url: webView.url)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame {
                let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
                trace("response \(status)", url: navigationResponse.response.url)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil else { return nil }
            if let url = navigationAction.request.url, openPaymentApp(url) { return nil }
            // 保留原始请求（包括 POST），让新窗口中的支付页沿用当前会话。
            webView.load(navigationAction.request)
            return nil
        }

        private func openPaymentApp(_ url: URL) -> Bool {
            let appName: String
            switch url.scheme?.lowercased() {
            case "weixin": appName = "微信"
            case "alipay", "alipays": appName = "支付宝"
            default: return false
            }
            // 直接打开并检查结果，无需依赖 canOpenURL 的查询白名单。
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                guard !opened else { return }
                self?.paymentError = "未能打开\(appName)，请确认已安装\(appName)后重试。"
            }
            return true
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            stopLocation()
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            applyFollowUpIfNeeded(webView)
            // 恢复会话保持隔离，避免登录过程中的 Cookie 改动影响 App 当前账号。
            guard !usesFreshSession else { return }
            // 网页里如果重新登过，把新 cookie 回写给 app，别让两边各登一次
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies where cookie.domain.contains("xatu.edu.cn") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            record(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            isLoading = false
            record(error)
        }

        /// 换票落地后，把 SPA 带到指定路由。等一会儿是因为落地页要先在 mounted 里写 cookie。
        private func applyFollowUpIfNeeded(_ webView: WKWebView) {
            guard !appliedFollowUp,
                  let target = followUpURL,
                  let targetURL = URL(string: target),
                  let host = webView.url?.host,
                  host.contains("jfpay.xatu.edu.cn"),
                  webView.url?.absoluteString != target else { return }
            appliedFollowUp = true
            // 等落地页把 token 写完，再整页重新加载目标地址，SPA 才会用新登录态启动
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak webView] in
                var request = URLRequest(url: targetURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                webView?.load(request)
            }
        }

        // 只记录主机，不收集 URL 路径、查询、fragment、请求头或 Cookie。
        private func trace(_ event: String, url: URL?) {
            diagnosticEvents.append("\(event): \(url?.host ?? "unknown")")
            if diagnosticEvents.count > 32 { diagnosticEvents.removeFirst() }
        }

        /// 只有真的打不开才提示，用户自己取消（-999）之类的忽略
        private func record(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            let failingURL = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
                ?? (ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
            trace("failure \(ns.domain) \(ns.code)", url: failingURL)
            let info = Bundle.main.infoDictionary ?? [:]
            diagnosticText = [
                "网页访问诊断",
                "App \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
                "iOS \(UIDevice.current.systemVersion)",
                "Time \(Date().ISO8601Format())",
                "Session \(usesFreshSession ? "isolated" : "shared")",
                diagnosticEvents.joined(separator: "\n")
            ].joined(separator: "\n")
            hasRedirectLoop = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorHTTPTooManyRedirects
            if hasRedirectLoop {
                errorText = "网页跳转次数过多，可尝试重新登录网页。若仍无法打开，请稍后重试并导出诊断文件。"
            } else if ns.domain == NSURLErrorDomain &&
                        (ns.code == NSURLErrorNotConnectedToInternet || ns.code == NSURLErrorCannotFindHost) {
                errorText = "网络不可用或无法找到服务器，请检查网络连接后重试。"
            } else {
                errorText = ns.localizedDescription
            }
        }
    }
}
