import AppKit
import CoreLocation
import WebKit

/// 使用真正的 WKWebView，复现百度 iframe 定位并向父页面 postMessage 的流程。
@main
@MainActor
struct WebLocationFrameTests {
    final class Handler: NSObject, WKScriptMessageHandler {
        weak var web: WKWebView?
        var results: Set<String> = []
        var contexts: Set<String> = []
        var sawChildRequest = false

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "result", let result = message.body as? String {
                results.insert(result)
                return
            }
            guard let body = message.body as? [String: Any], let id = body["id"] as? Int else { return }
            if body["clear"] as? Bool == true { return }
            contexts.insert(body["context"] as! String)
            sawChildRequest = sawChildRequest || !message.frameInfo.isMainFrame
            if message.frameInfo.isMainFrame {
                WebLocationScript.reply(to: message.frameInfo, in: web, id: id, error: "测试'错误\n消息")
            } else {
                WebLocationScript.reply(to: message.frameInfo, in: web, id: id,
                                        location: CLLocation(latitude: 34.38, longitude: 108.97))
            }
        }
    }

    static func main() {
        _ = NSApplication.shared
        let handler = Handler()
        let config = WKWebViewConfiguration()
        config.userContentController.add(handler, name: "location")
        config.userContentController.add(handler, name: "result")
        config.userContentController.addUserScript(WKUserScript(source: WebLocationScript.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let web = WKWebView(frame: .zero, configuration: config)
        handler.web = web
        web.loadHTMLString("""
        <html><body>
        <script>
        window.addEventListener('message', function(e) {
          if (e.data === 'child-ok' || e.data === 'watch-ok') window.webkit.messageHandlers.result.postMessage(e.data);
        });
        navigator.geolocation.getCurrentPosition(function() {}, function(e) {
          if (e.message === "测试'错误\\n消息") window.webkit.messageHandlers.result.postMessage('error-ok');
        });
        </script>
        <iframe sandbox="allow-scripts" srcdoc="<script>
        navigator.geolocation.getCurrentPosition(function(p) {
          if (p.coords.latitude === 34.38 &amp;&amp; p.coords.longitude === 108.97) parent.postMessage('child-ok', '*');
        });
        </script>"></iframe>
        <iframe sandbox="allow-scripts" srcdoc="<script>
        var id = navigator.geolocation.watchPosition(function(p) {
          if (p.coords.latitude === 34.38 &amp;&amp; p.coords.longitude === 108.97) parent.postMessage('watch-ok', '*');
          navigator.geolocation.clearWatch(id);
        });
        </script>"></iframe>
        </body></html>
        """, baseURL: URL(string: "https://ehall.xatu.edu.cn"))
        let deadline = Date().addingTimeInterval(20)
        while handler.results.count < 3 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(handler.sawChildRequest, "Fixture must make a real iframe location request")
        precondition(handler.contexts.count == 3, "Frames must have independent callback namespaces")
        precondition(handler.results == ["child-ok", "watch-ok", "error-ok"], "Every frame must receive its own callback: \(handler.results)")
        print("WKWebView cross-origin iframe, watch, and error callback tests passed")
    }
}
