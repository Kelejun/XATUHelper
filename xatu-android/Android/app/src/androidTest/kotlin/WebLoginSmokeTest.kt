package xatu.android

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercise the production login flow without credentials or Compose idle assumptions. */
@RunWith(AndroidJUnit4::class)
class WebLoginSmokeTest {
    @Test fun openingWebLoginSurvivesRedirect() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        context.startActivity(TestApp.launchIntent(context).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val device = UiDevice.getInstance(instrumentation)
        val login = device.wait(Until.findObject(By.text("需要验证码？用网页登录")), 15_000)
        if (login == null && (device.hasObject(By.text("首页")) || device.hasObject(By.desc("首页")))) {
            assumeTrue("Preserve the existing signed-in session instead of logging the user out", false)
        }
        assertNotNull("The login screen should appear", login)
        login.click()
        assertNotNull("The web login sheet should open", device.wait(Until.findObject(By.text("在网页里登录")), 15_000))
        // The original crash was asynchronous during shouldOverrideUrlLoading.
        Thread.sleep(8_000)
        assertNotNull("The web login sheet should survive navigation", device.findObject(By.text("在网页里登录")))
        val cancel = device.findObject(By.text("取消"))
        assertNotNull("The sheet should offer cancellation", cancel)
        cancel.click()
        assertNotNull("Cancel should return to the login screen", device.wait(Until.findObject(By.text("需要验证码？用网页登录")), 10_000))
    }
}
