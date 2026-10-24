import SwiftUI
import WebKit

/// 需要验证码、手机动态码这类网页才走得通的登录，弹一个内置浏览器让用户自己过。
/// 登录成功后把 WKWebView 里的 cookie 搬回 URLSession 的共享存储，后面的请求就能接着用了。
struct CASWebLoginView: UIViewRepresentable {
    let startURL: URL
    /// 成功拿到业务系统会话传 true，用户中途放弃传 false
    var onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // 先把陈旧的校园 cookie 清掉，免得带着过期会话反复弹回登录页
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            let stale = cookies.filter { $0.domain.contains("xatu.edu.cn") }
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

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: CASWebLoginView
        private var finished = false

        init(_ parent: CASWebLoginView) {
            self.parent = parent
        }

        /// 落到教务或缴费的页面，说明 ticket 已经换成业务系统会话了，这时候再把 cookie 捞出来
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished,
                  let host = webView.url?.host,
                  host.contains("jwgl2018") || host.contains("jfpay") else { return }

            finished = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let shared = cookies.filter { $0.domain.contains("xatu.edu.cn") }
                for cookie in shared {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                DispatchQueue.main.async {
                    self.parent.onFinished(!shared.isEmpty)
                }
            }
        }
    }
}

struct CASWebLoginSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CASWebLoginView(startURL: CASService.loginURL()) { success in
                dismiss()
                if success {
                    Task { await app.completeWebLogin() }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("在网页里登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
