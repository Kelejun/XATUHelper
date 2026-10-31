package xatu.android

import androidx.core.graphics.ColorUtils
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MaterialThemeTest {
    @Test fun lightAndDarkSemanticColorsHaveReadableContrast() {
        for (mode in listOf("light", "dark")) {
            val roles = JSONObject(TestApp.call("materialColors", mode))
            fun color(role: String) = android.graphics.Color.parseColor("#" + roles.getString(role))
            for ((foreground, background) in listOf(
                "onSurface" to "surface", "onSurfaceVariant" to "surfaceContainer",
                "onPrimary" to "primary", "onPrimaryContainer" to "primaryContainer")) {
                val ratio = ColorUtils.calculateContrast(color(foreground), color(background))
                assertTrue("$mode $foreground on $background must meet normal-text contrast: $ratio", ratio >= 4.5)
            }
        }
    }
}
