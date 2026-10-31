#if !os(Android)
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

    @Environment(\.dismiss) var dismiss
    @State var isLoading = true
    @State var errorText: String?
    @State var reloadToken = 0

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
                    WebPage(url: url, isLoading: $isLoading, errorText: $errorText, followUpURL: followUpURL)
                        .id(reloadToken)
                } else {
                    ContentUnavailableView("地址不对", systemImage: "link.badge.plus")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
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

struct WebPage: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorText: String?
    let followUpURL: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // WKWebView 自带的 navigator.geolocation 是空的，签到这类页面会一直转圈。
        // 注入一段垫片，把定位请求转给原生 CLLocationManager。
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "location")
        controller.addUserScript(WKUserScript(
            source: Self.locationShim,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
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
        Coordinator(isLoading: $isLoading, errorText: $errorText, followUpURL: followUpURL)
    }

    /// 把 navigator.geolocation 接到 window.webkit.messageHandlers.location
    private static let locationShim = """
    (function(){
      if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.location) return;
      if (!navigator.geolocation) {
        try { Object.defineProperty(navigator, 'geolocation', {value: {}, configurable: true}); } catch (e) { return; }
      }
      var bridge = window.webkit.messageHandlers.location;
      var seq = 0, pending = {}, watches = {};
      function reply(id, ok, lat, lng, acc, msg){
        var cb = pending[id] || watches[id];
        if (!cb) return;
        if (ok) {
          cb.success && cb.success({
            coords: {latitude: lat, longitude: lng, accuracy: acc, altitude: null, altitudeAccuracy: null, heading: null, speed: null},
            timestamp: Date.now()
          });
          if (!watches[id]) delete pending[id];
        } else {
          cb.error && cb.error({code: 2, message: msg || '定位失败', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3});
          delete pending[id];
          delete watches[id];
        }
      }
      window.__xatuLocation = reply;
      navigator.geolocation.getCurrentPosition = function(success, error){
        var id = ++seq;
        pending[id] = {success: success, error: error};
        bridge.postMessage({id: id, watch: false});
      };
      navigator.geolocation.watchPosition = function(success, error){
        var id = ++seq;
        watches[id] = {success: success, error: error};
        bridge.postMessage({id: id, watch: true});
        return id;
      };
      navigator.geolocation.clearWatch = function(id){
        delete watches[id];
        bridge.postMessage({id: id, clear: true});
      };
      if (navigator.permissions && navigator.permissions.query) {
        var query = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = function(desc){
          if (desc && desc.name === 'geolocation') return Promise.resolve({state: 'granted', onchange: null});
          return query(desc);
        };
      }
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var isLoading: Bool
        @Binding var errorText: String?
        private let followUpURL: String?
        var appliedFollowUp = false
        weak var webView: WKWebView?
        private let location = LocationBridge()

        init(isLoading: Binding<Bool>, errorText: Binding<String?>, followUpURL: String?) {
            _isLoading = isLoading
            _errorText = errorText
            self.followUpURL = followUpURL
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "location",
                  let body = message.body as? [String: Any],
                  let id = body["id"] as? Int else { return }
            if body["clear"] as? Bool == true {
                location.stopWatching(id: id)
                return
            }
            let isWatch = body["watch"] as? Bool ?? false
            if isWatch {
                location.startWatching(id: id) { [weak self] location in
                    guard let self, let location else { return }
                    self.reply(id: id, location: location)
                }
            } else {
                location.request { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case let .success(location):
                        self.reply(id: id, location: location)
                    case let .failure(error):
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        self.reply(id: id, error: message)
                    }
                }
            }
        }

        private func reply(id: Int, location: CLLocation) {
            let js = "window.__xatuLocation && window.__xatuLocation(\(id), true, \(location.coordinate.latitude), \(location.coordinate.longitude), \(location.horizontalAccuracy), '')"
            webView?.evaluateJavaScript(js)
        }

        private func reply(id: Int, error: String) {
            let escaped = error.replacingOccurrences(of: "'", with: "\\'")
            let js = "window.__xatuLocation && window.__xatuLocation(\(id), false, 0, 0, 0, '\(escaped)')"
            webView?.evaluateJavaScript(js)
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

#endif
