import SwiftUI
import WebKit

/// 一个通用的内置网页，给签到这类只能走网页的功能用。
struct WebSheet: View {
    let title: String
    let urlString: String
    /// 换票落地后要整页跳到的地址（用真正的 navigation，不是改 hash）
    var followUpURL: String? = nil
    /// 进页面前用 document.cookie 写进去的键值（绕开 path 不匹配）
    var cookies: [String: String] = [:]
    var showsCloseButton = true
    var showsSidebarToggle = false
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var paymentError: String?
    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            Group {
                if let message = errorText {
                    ContentUnavailableView {
                        Label("打不开这个页面", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            errorText = nil
                            isLoading = true
                            reloadToken += 1
                        }
                    }
                } else if let url = Self.makeURL(urlString) {
                    WebPage(url: url, isLoading: $isLoading, errorText: $errorText,
                            paymentError: $paymentError, followUpURL: followUpURL)
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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

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

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorText: $errorText, paymentError: $paymentError,
                    followUpURL: followUpURL,
                    allowsCustomLocation: url.host == "ehall.xatu.edu.cn"
                        && url.path.hasPrefix("/xsfw/sys/swmqdzsapp/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        @Binding private var isLoading: Bool
        @Binding private var errorText: String?
        @Binding private var paymentError: String?
        private let followUpURL: String?
        private var appliedFollowUp = false
        weak var webView: WKWebView?
        private let location: LocationBridge
        private var nextWatchID = 0
        private var watchIDs: [String: Int] = [:]

        init(isLoading: Binding<Bool>, errorText: Binding<String?>, paymentError: Binding<String?>,
             followUpURL: String?, allowsCustomLocation: Bool) {
            _isLoading = isLoading
            _errorText = errorText
            _paymentError = paymentError
            self.followUpURL = followUpURL
            self.location = LocationBridge(allowsCustomLocation: allowsCustomLocation)
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
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            applyFollowUpIfNeeded(webView)
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

        /// 只有真的打不开才提示，用户自己取消（-999）之类的忽略
        private func record(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            let detail = ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
            if ns.code == NSURLErrorNotConnectedToInternet || ns.code == NSURLErrorCannotFindHost {
                errorText = "这个页面要连校内网才能打开，先连上校园网再试。"
            } else if let detail {
                errorText = "\(ns.localizedDescription)\n\(detail)"
            } else {
                errorText = ns.localizedDescription
            }
        }
    }
}
