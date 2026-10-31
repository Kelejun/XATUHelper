package xatu.android

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Separate process, like a macrobenchmark: never mix test Kotlin libraries with
 * R8-renamed app libraries. Frame timings come from Android HWUI framestats. */
@RunWith(AndroidJUnit4::class)
class ReleaseFrameTimingTest {
    @Test fun warmTimetableFramesFromSystemRenderer() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        instrumentation.context.startActivity(TestApp.launchIntent(instrumentation.context)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        val tab = device.wait(Until.findObject(By.text("课程表")), 15_000)
        assumeTrue("Requires existing user session", tab != null)
        tab!!.click()
        Thread.sleep(2_000)
        device.executeShellCommand("dumpsys gfxinfo com.cell.xatuapp reset")
        val durations = linkedMapOf<Long, Double>()
        var finalDump = ""
        fun collect() {
            val raw = device.executeShellCommand("dumpsys gfxinfo com.cell.xatuapp framestats")
            finalDump = raw
            var headers: List<String>? = null
            raw.lineSequence().forEach { line ->
                if (line.startsWith("Flags,") && line.contains("IntendedVsync")) headers = line.split(',')
                else if (line.firstOrNull()?.isDigit() == true && line.contains(',')) {
                    val keys = headers ?: return@forEach
                    val values = line.split(',')
                    val start = values.getOrNull(keys.indexOf("IntendedVsync"))?.toLongOrNull() ?: return@forEach
                    val end = values.getOrNull(keys.indexOf("FrameCompleted"))?.toLongOrNull() ?: return@forEach
                    if (values.firstOrNull() == "0" && end > start && end - start < 1_000_000_000) {
                        durations[start] = (end - start) / 1_000_000.0
                    }
                }
            }
        }
        val w = device.displayWidth
        val h = device.displayHeight
        repeat(8) {
            device.swipe((w * .85).toInt(), (h * .45).toInt(), (w * .15).toInt(), (h * .45).toInt(), 18)
            Thread.sleep(300)
            device.swipe((w * .15).toInt(), (h * .45).toInt(), (w * .85).toInt(), (h * .45).toInt(), 18)
            Thread.sleep(300)
            collect()
        }
        val summary = finalDump.lineSequence().filter {
            it.startsWith("Total frames rendered:") || it.startsWith("Janky frames:") || it.startsWith("95th percentile:")
        }.take(3).joinToString("; ")
        println("XATU_HWUI_SUMMARY $summary")
        val sorted = durations.values.sorted()
        assertTrue("System renderer must report enough frames", sorted.size > 30)
        fun percentile(p: Double) = sorted[((sorted.size - 1) * p).toInt()]
        println("XATU_HWUI_TIMING count=${sorted.size} p50ms=${percentile(.5)} p95ms=${percentile(.95)} over32ms=${sorted.count { it > 32.0 }}")
    }
}
