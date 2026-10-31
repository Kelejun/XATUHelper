#if os(Android)
import Foundation
import FoundationNetworking
import SwiftUI
import SkipWeb

/// Keep WebView and URLSession sessions synchronized, including HttpOnly cookies.
@MainActor
enum WebCookies {
    static func importCookies(from engine: WebEngine) async {
        var scopes = WebSessionCookies.scopes
        if let current = engine.url, let host = current.host, WebSessionCookies.isCampusHost(host) {
            let base = current.path.hasPrefix("/eams/") ? "/eams" : current.path.hasPrefix("/authserver/") ? "/authserver" : "/"
            scopes.append(.init(url: current, fallbackPath: base))
        }
        var imported: [HTTPCookie] = []
        for scope in scopes {
            if let json = AndroidPlatform.call("webCookieRecords", scope.url.absoluteString),
               let data = json.data(using: .utf8), let records = try? JSONDecoder().decode([String].self, from: data) {
                imported += WebSessionCookies.parse(records: records, for: scope.url)
            } else if let header = await engine.cookieHeader(for: scope.url) {
                let scoped = WebSessionCookies.parseLegacy(header: header, scope: scope)
                // Avoid manufacturing a second scoped copy of the same root cookie.
                imported += scoped.filter { cookie in
                    !imported.contains { $0.domain == cookie.domain && $0.name == cookie.name && $0.value == cookie.value }
                }
            }
        }
        WebSessionCookies.install(imported)
        CookieVault.pinAndSave()
    }
    static func exportCookies(to engine: WebEngine) async {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] where WebSessionCookies.isCampusHost(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
            try? await engine.setCookie(WebCookie(name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path, expires: cookie.expiresDate, isSecure: cookie.isSecure, isHTTPOnly: cookie.isHTTPOnly))
        }
    }
}

struct CASWebLoginSheet: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss
    @State var navigator = WebViewNavigator()
    @State var completed = false
    @State var completing = false
    @State var syncError: String?
    var body: some View {
        NavigationStack {
            WebView(navigator: navigator, url: CASService.loginURL(), onNavigationFinished: {
                Task { @MainActor in
                    guard !completed, !completing, let engine = navigator.webEngine, let host = engine.url?.host,
                          host == "jwgl2018.xatu.edu.cn" || host == "jfpay.xatu.edu.cn" else { return }
                    await finishLogin(using: engine)
                }
            })
            .overlay(alignment: .bottom) {
                if let syncError {
                    VStack(spacing: 8) {
                        Text(syncError).font(.footnote)
                        Button("重新同步登录状态") {
                            Task { @MainActor in
                                if let engine = navigator.webEngine { await finishLogin(using: engine) }
                            }
                        }.disabled(completing)
                    }.padding().background(.regularMaterial)
                }
            }
            .navigationTitle("在网页里登录")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
    @MainActor private func finishLogin(using engine: WebEngine) async {
        guard !completing else { return }
        completing = true
        syncError = nil
        await WebCookies.importCookies(from: engine)
        if await app.completeWebLogin() {
            completed = true
            dismiss()
        } else {
            syncError = app.errorMessage ?? "登录状态尚未同步，请等待网页加载完成后重试。"
        }
        completing = false
    }

}

struct WebSheet: View {
    let title: String
    let urlString: String
    var followUpURL: String? = nil
    var cookies: [String: String] = [:]
    @Environment(\.dismiss) var dismiss
    @State var navigator = WebViewNavigator()
    @State var followedUp = false
    @State var ready = false
    private var cacheID: String { "xatu-" + urlString }
    var body: some View {
        NavigationStack {
            Group {
                if ready, let url = URL(string: urlString) {
                    WebView(navigator: navigator, url: url, onNavigationCommitted: {
                        _ = AndroidPlatform.call("enableLocation")
                    }, onNavigationFinished: {
                        Task { @MainActor in
                            _ = AndroidPlatform.call("enableLocation")
                            guard let engine = navigator.webEngine else { return }
                            await WebCookies.importCookies(from: engine)
                            if !followedUp, let followUpURL, let next = URL(string: followUpURL) {
                                followedUp = true
                                try? await engine.load(url: next)
                            }
                        }
                    }, persistentWebViewID: cacheID)
                } else { ProgressView() }
            }
            .task {
                let engine = WebEngine()
                await WebCookies.exportCookies(to: engine)
                if let url = URL(string: urlString) {
                    for (name, value) in cookies {
                        try? await engine.setCookie(WebCookie(name: name, value: value, domain: url.host, path: "/"), requestURL: url)
                    }
                }
                ready = true
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .onDisappear { WebView.removePersistentWebView(id: cacheID) }
    }
}
#endif
