package xatu.android

import android.webkit.CookieManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewFeature
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class WebSessionCookieTest {
    @Test fun scopedHttpOnlySessionIsExportedWithAttributes() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val url = "http://jwgl2018.xatu.edu.cn/eams/homeExt.action"
        val name = "XatuSessionRegression"
        val ready = CountDownLatch(1)
        instrumentation.runOnMainSync {
            CookieManager.getInstance().setCookie(url, "$name=fixture; Path=/eams; HttpOnly") { ready.countDown() }
        }
        assertTrue("The test cookie should be installed", ready.await(10, TimeUnit.SECONDS))
        try {
            // The old implementation queried only / and therefore could not see this cookie.
            assertFalse(CookieManager.getInstance().getCookie("http://jwgl2018.xatu.edu.cn/").orEmpty().contains("$name="))
            assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO))
            val records = JSONArray(PlatformServices.call("webCookieRecords", url))
            val record = (0 until records.length()).map { records.getString(it) }.single { it.startsWith("$name=") }
            assertTrue("Cookie path must survive the bridge", record.contains("path=/eams", ignoreCase = true))
            assertTrue("HttpOnly must survive the bridge", record.contains("httponly", ignoreCase = true))
        } finally {
            instrumentation.runOnMainSync {
                CookieManager.getInstance().setCookie(url, "$name=; Path=/eams; Max-Age=0; HttpOnly")
            }
        }
    }
}
