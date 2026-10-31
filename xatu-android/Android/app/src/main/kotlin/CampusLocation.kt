package xatu.android

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/** Preserve SkipWeb callbacks while handling the campus WebView location prompt. */
object CampusLocation {
    private var pending: Pair<String, GeolocationPermissions.Callback>? = null
    fun attach(activity: Activity) {
        activity.runOnUiThread { walk(activity.window.decorView, activity) }
    }
    private fun walk(view: View, activity: Activity) {
        if (view is WebView && view.webChromeClient !is CampusChromeClient) {
            view.webChromeClient = CampusChromeClient(activity, view.webChromeClient)
        }
        if (view is ViewGroup) for (index in 0 until view.childCount) walk(view.getChildAt(index), activity)
    }
    fun permissionResult(granted: Boolean) {
        pending?.let { (origin, callback) -> callback.invoke(origin, granted, false) }
        pending = null
    }
    private class CampusChromeClient(val activity: Activity, val delegate: WebChromeClient?): WebChromeClient() {
        override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
            val uri = Uri.parse(origin)
            val host = uri.host.orEmpty()
            if (uri.scheme != "https" || !(host == "xatu.edu.cn" || host.endsWith(".xatu.edu.cn"))) {
                callback.invoke(origin, false, false); return
            }
            if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                callback.invoke(origin, true, false)
            } else {
                pending?.let { (oldOrigin, oldCallback) -> oldCallback.invoke(oldOrigin, false, false) }
                pending = origin to callback
                ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 411)
            }
        }
        override fun onGeolocationPermissionsHidePrompt() { permissionResult(false) }
        override fun onProgressChanged(view: WebView, progress: Int) { delegate?.onProgressChanged(view, progress) }
        override fun onReceivedTitle(view: WebView, title: String?) { delegate?.onReceivedTitle(view, title) }
        override fun onReceivedIcon(view: WebView, icon: android.graphics.Bitmap?) { delegate?.onReceivedIcon(view, icon) }
        override fun onConsoleMessage(message: ConsoleMessage): Boolean = delegate?.onConsoleMessage(message) ?: false
        override fun onCreateWindow(view: WebView, dialog: Boolean, gesture: Boolean, message: Message): Boolean = delegate?.onCreateWindow(view, dialog, gesture, message) ?: false
        override fun onCloseWindow(view: WebView) { delegate?.onCloseWindow(view) }
        override fun onJsAlert(view: WebView, url: String, message: String, result: JsResult): Boolean = delegate?.onJsAlert(view, url, message, result) ?: false
        override fun onJsConfirm(view: WebView, url: String, message: String, result: JsResult): Boolean = delegate?.onJsConfirm(view, url, message, result) ?: false
        override fun onJsPrompt(view: WebView, url: String, message: String, defaultValue: String?, result: JsPromptResult): Boolean = delegate?.onJsPrompt(view, url, message, defaultValue, result) ?: false
        override fun onShowFileChooser(view: WebView, callback: android.webkit.ValueCallback<Array<Uri>>, parameters: FileChooserParams): Boolean = delegate?.onShowFileChooser(view, callback, parameters) ?: false
        override fun onPermissionRequest(request: PermissionRequest) { if (delegate != null) delegate.onPermissionRequest(request) else request.deny() }
        override fun onPermissionRequestCanceled(request: PermissionRequest) { delegate?.onPermissionRequestCanceled(request) }
    }
}
