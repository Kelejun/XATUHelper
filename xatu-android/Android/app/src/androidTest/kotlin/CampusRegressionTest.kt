package xatu.android

import android.content.Intent
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CampusRegressionTest {
    @Test fun publicCalendarCanBeRecognizedOffline() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        // Official public 2026–2027 calendar, not a user document.
        // https://jwcw.xatu.edu.cn/news/content.jsp?urltype=news.NewsContentUrl&wbtreeid=15497&wbnewsid=200057
        val image = instrumentation.context.assets.open("calendar-2026.jpg").use { it.readBytes() }
        val payload = JSONObject().put("image", Base64.encodeToString(image, Base64.NO_WRAP))
            .put("x", 0.0).put("y", 0.0).put("width", 1.0).put("height", 1.0)
        val text = TestApp.call("ocr", payload.toString())
        assertTrue("Bundled Chinese OCR should read the calendar", text.contains("2026") && text.contains("2027"))
        assertTrue("OCR should read the semester dates", text.contains("学期"))
    }

    @Test fun timetableStaysOpen() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.targetContext.startActivity(TestApp.launchIntent(instrumentation.targetContext)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val device = UiDevice.getInstance(instrumentation)
        val tab = device.wait(Until.findObject(By.text("课程表")), 15_000)
        assumeTrue("Requires an existing user session; never enter credentials or reset data", tab != null)
        tab!!.click()
        Thread.sleep(2_000)
        assertNotNull("The app should survive timetable layout", device.findObject(By.pkg("com.cell.xatuapp")))

    }
}
