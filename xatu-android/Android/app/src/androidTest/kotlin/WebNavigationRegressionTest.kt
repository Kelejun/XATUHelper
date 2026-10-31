package xatu.android

import android.net.Uri
import android.webkit.WebResourceRequest
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import androidx.test.platform.app.InstrumentationRegistry

/** Exercise the exact SkipWeb boundary from the production crash stack. */
@RunWith(AndroidJUnit4::class)
class WebNavigationRegressionTest {
    private fun request(headers: MutableMap<String, String>?): WebResourceRequest = object : WebResourceRequest {
        override fun getUrl(): Uri = Uri.parse("https://authserver.xatu.edu.cn/authserver/login")
        override fun isForMainFrame() = true
        override fun isRedirect() = true
        override fun hasGesture() = false
        override fun getMethod() = "GET"
        override fun getRequestHeaders(): MutableMap<String, String>? = headers
    }

    private fun copiedHeaders(headers: MutableMap<String, String>?): Any {
        val loader = InstrumentationRegistry.getInstrumentation().targetContext.classLoader
        val companion = Class.forName("skip.web.WebEngine", true, loader).getField("Companion").get(null)!!
        // The Swift fileprivate helper has a Kotlin module suffix. Resolve it by name
        // so a module-name change cannot silently bypass this regression test.
        val method = companion.javaClass.methods.single {
            it.name.startsWith("androidRequestHeaders") && it.parameterTypes.contentEquals(arrayOf(WebResourceRequest::class.java))
        }
        return method.invoke(companion, request(headers))!!
    }

    @Test fun redirectWithNullHeadersDoesNotCrash() {
        val headers = copiedHeaders(null)
        val count = headers.javaClass.getMethod("getCount").invoke(headers) as Int
        assertEquals(0, count)
    }

    @Test fun normalRequestHeadersArePreserved() {
        val headers = copiedHeaders(linkedMapOf("Accept" to "text/html", "Referer" to "https://authserver.xatu.edu.cn/"))
        val count = headers.javaClass.getMethod("getCount").invoke(headers) as Int
        assertEquals(2, count)
    }
}
