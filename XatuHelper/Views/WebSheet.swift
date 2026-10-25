import SwiftUI
import WebKit

/// 一个通用的内置网页，给签到这类只能走网页的功能用。
struct WebSheet: View {
    let title: String
    let urlString: String

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let url = Self.makeURL(urlString) {
                    WebPage(url: url, isLoading: $isLoading)
                } else {
                    ContentUnavailableView("地址不对", systemImage: "link.badge.plus")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true

        // 把 app 已经拿到的 xatu cookie 带进 WebKit 的存储，少登一次。
        // setCookie 是异步的，等全部落盘再发第一个请求，否则第一次会被踢去登录页。
        let store = web.configuration.websiteDataStore.httpCookieStore
        let cookies = (HTTPCookieStorage.shared.cookies ?? [])
            .filter { $0.domain.contains("xatu.edu.cn") }
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            // 网页里如果重新登过，把新 cookie 回写给 app，别让两边各登一次
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies where cookie.domain.contains("xatu.edu.cn") {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            isLoading = false
        }
    }
}
