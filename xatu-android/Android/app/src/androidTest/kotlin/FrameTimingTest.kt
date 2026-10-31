package xatu.android

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.HandlerThread
import android.view.FrameMetrics
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Collections

/** Fixed interaction sequence on one emulator, measured from the actual window.
 * Warm-up is excluded. Absolute numbers are not a physical-device FPS promise. */
@RunWith(AndroidJUnit4::class)
class FrameTimingTest {
    @Test fun warmTabAndTimetableFrames() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val device = UiDevice.getInstance(instrumentation)
        instrumentation.targetContext.startActivity(TestApp.launchIntent(instrumentation.targetContext)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        val tab = device.wait(Until.findObject(By.text("课程表")), 15_000)
        assumeTrue("Requires an existing session; no credentials or account changes", tab != null)
        tab!!.click()
        Thread.sleep(2_000)
        var activity: Activity? = null
        instrumentation.runOnMainSync {
            activity = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).firstOrNull()
        }
        assumeTrue(activity != null)
        val frames = Collections.synchronizedList(mutableListOf<Long>())
        val phases = Collections.synchronizedList(mutableListOf<LongArray>())
        val thread = HandlerThread("frame-regression").apply { start() }
        val listener = android.view.Window.OnFrameMetricsAvailableListener { _, metric, _ ->
            frames.add(metric.getMetric(FrameMetrics.TOTAL_DURATION))
            phases.add(longArrayOf(metric.getMetric(FrameMetrics.LAYOUT_MEASURE_DURATION),
                metric.getMetric(FrameMetrics.DRAW_DURATION), metric.getMetric(FrameMetrics.GPU_DURATION)))
        }
        instrumentation.runOnMainSync { activity!!.window.addOnFrameMetricsAvailableListener(listener, Handler(thread.looper)) }
        try {
            val w = device.displayWidth
            val h = device.displayHeight
            repeat(8) {
                device.swipe((w * .85).toInt(), (h * .45).toInt(), (w * .15).toInt(), (h * .45).toInt(), 18)
                Thread.sleep(300)
                device.swipe((w * .15).toInt(), (h * .45).toInt(), (w * .85).toInt(), (h * .45).toInt(), 18)
                Thread.sleep(300)
            }
        } finally {
            instrumentation.runOnMainSync { activity!!.window.removeOnFrameMetricsAvailableListener(listener) }
            thread.quitSafely()
        }
        val sorted = synchronized(frames) { frames.toList().sorted() }
        assumeTrue("Enough rendered frames are required", sorted.size > 10)
        fun percentile(p: Double) = sorted[((sorted.size - 1) * p).toInt()] / 1_000_000.0
        val slow = sorted.count { it > 16_666_667L }
        val averages = synchronized(phases) { (0..2).map { i -> phases.map { it[i] }.filter { it >= 0 }.average() / 1_000_000.0 } }
        println("XATU_FRAME_PHASES layoutMs=${averages[0]} drawMs=${averages[1]} gpuMs=${averages[2]}")
        println("XATU_FRAME_TIMING count=${sorted.size} p50ms=${percentile(.5)} p95ms=${percentile(.95)} over16ms=$slow slowPercent=${100.0 * slow / sorted.size}")
    }
}
