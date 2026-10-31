package xatu.android

import android.content.Context
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry

/** Access the installed production app without a Gradle implementation dependency. */
object TestApp {
    fun launchIntent(context: Context) = Intent().setClassName("com.cell.xatuapp", "xatu.android.MainActivity")
    fun call(operation: String, payload: String): String {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val platform = Class.forName("xatu.android.PlatformServices", true, context.classLoader)
        return platform.getMethod("call", String::class.java, String::class.java).invoke(null, operation, payload) as String
    }
}
