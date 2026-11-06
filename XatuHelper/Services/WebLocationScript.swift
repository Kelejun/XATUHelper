import CoreLocation
import WebKit

enum WebLocationScript {
    /// 把 navigator.geolocation 接到 window.webkit.messageHandlers.location
    static let source = """
    (function(){
      if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.location) return;
      if (!navigator.geolocation) {
        try { Object.defineProperty(navigator, 'geolocation', {value: {}, configurable: true}); } catch (e) { return; }
      }
      var bridge = window.webkit.messageHandlers.location;
      var seq = 0, pending = {}, watches = {};
      var context = Date.now().toString(36) + Math.random().toString(36).slice(2);
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
        bridge.postMessage({context: context, id: id, watch: false});
      };
      navigator.geolocation.watchPosition = function(success, error){
        var id = ++seq;
        watches[id] = {success: success, error: error};
        bridge.postMessage({context: context, id: id, watch: true});
        return id;
      };
      navigator.geolocation.clearWatch = function(id){
        delete watches[id];
        bridge.postMessage({context: context, id: id, clear: true});
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

    /// 定位 SDK 会在跨域 iframe 内请求定位，必须回传到请求所在 frame。
    static func reply(to frame: WKFrameInfo, in webView: WKWebView?, id: Int,
                      location: CLLocation? = nil, error: String? = nil) {
        webView?.callAsyncJavaScript(
            "window.__xatuLocation && window.__xatuLocation(id, ok, lat, lng, accuracy, message)",
            arguments: ["id": id, "ok": location != nil,
                        "lat": location?.coordinate.latitude ?? 0,
                        "lng": location?.coordinate.longitude ?? 0,
                        "accuracy": location?.horizontalAccuracy ?? 0,
                        "message": error ?? ""],
            in: frame, in: .page, completionHandler: nil
        )
    }
}
