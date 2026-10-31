package xatu.android

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import org.json.JSONObject
import org.json.JSONArray
import android.webkit.CookieManager
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import java.lang.ref.WeakReference
import java.util.concurrent.TimeUnit

/** Explicit JNI surface: keep signatures stable and preserve it in R8. */
object PlatformServices {
    lateinit var context: Context
    var activity = WeakReference<Activity>(null)
    private val prefs get() = context.getSharedPreferences("xatu.reminders", Context.MODE_PRIVATE)
    @JvmStatic fun call(operation: String, payload: String): String {
        return when (operation) {
            "webCookieRecords" -> {
                val uri = android.net.Uri.parse(payload)
                val host = uri.host.orEmpty()
                require(host == "xatu.edu.cn" || host.endsWith(".xatu.edu.cn"))
                if (WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)) {
                    JSONArray(CookieManagerCompat.getCookieInfo(CookieManager.getInstance(), payload)).toString()
                } else "null"
            }
            "notificationStatus" -> notificationStatus()
            "requestNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33 && notificationStatus() != "authorized") {
                    activity.get()?.let { current -> current.runOnUiThread {
                        prefs.edit().putBoolean("prompted", true).apply()
                        ActivityCompat.requestPermissions(current, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 410)
                    } }
                }
                notificationStatus()
            }
            "schedule" -> { schedule(JSONObject(payload)); "ok" }
            "clearReminders" -> { clear(); "ok" }
            "ocr" -> recognize(JSONObject(payload))
            "enableLocation" -> { activity.get()?.let { CampusLocation.attach(it) }; "ok" }
            "widget" -> { CampusWidget.save(context, payload); "ok" }
            else -> throw IllegalArgumentException("Unknown Android operation: $operation")
        }
    }
    private fun notificationStatus(): String {
        if (NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)) return "authorized"
        return if (prefs.getBoolean("prompted", false)) "denied" else "notDetermined"
    }
    private fun intent(id: String): Intent = Intent(context, ReminderReceiver::class.java).setAction("xatu.reminder.$id")
    private fun pending(id: String, json: String = ""): PendingIntent = PendingIntent.getBroadcast(context, 0,
        intent(id).putExtra("reminder", json), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(data: JSONObject) {
        val id = data.getString("id")
        prefs.edit().putString("reminder.$id", data.toString()).apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fire = data.getLong("time")
        // Does not require special exact-alarm access; Android may defer while idle.
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fire, pending(id, data.toString()))
    }
    private fun clear() {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val edit = prefs.edit()
        for (key in prefs.all.keys.filter { it.startsWith("reminder.") }) {
            val p = pending(key.removePrefix("reminder.")); alarm.cancel(p); p.cancel(); edit.remove(key)
        }
        edit.apply()
    }
    fun restore() {
        for ((key, value) in prefs.all) if (key.startsWith("reminder.") && value is String) {
            val data = JSONObject(value)
            if (data.getLong("time") > System.currentTimeMillis()) schedule(data)
            else prefs.edit().remove(key).apply()
        }
    }
    fun delivered(id: String) { prefs.edit().remove("reminder.$id").apply() }
    private fun recognize(data: JSONObject): String {
        val bytes = Base64.decode(data.getString("image"), Base64.DEFAULT)
        val original = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return ""
        val x = (data.getDouble("x") * original.width).toInt().coerceIn(0, original.width - 1)
        val y = ((1 - data.getDouble("y") - data.getDouble("height")) * original.height).toInt().coerceIn(0, original.height - 1)
        val width = (data.getDouble("width") * original.width).toInt().coerceIn(1, original.width - x)
        val height = (data.getDouble("height") * original.height).toInt().coerceIn(1, original.height - y)
        val cropped = Bitmap.createBitmap(original, x, y, width, height)
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        return try { Tasks.await(recognizer.process(InputImage.fromBitmap(cropped, 0)), 45, TimeUnit.SECONDS).text }
        finally { recognizer.close(); if (cropped !== original) cropped.recycle(); original.recycle() }
    }
}

class ReminderReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PlatformServices.context = context.applicationContext
        val raw = intent.getStringExtra("reminder") ?: return
        val data = JSONObject(raw)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel("classes-exams", "课程与考试提醒", NotificationManager.IMPORTANCE_HIGH))
        val launch = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, "classes-exams")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(data.getString("title"))
            .setContentText(data.getString("body")).setContentIntent(launch).setAutoCancel(true).build()
        if (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            manager.notify(data.getString("id"), 0, notification)
        }
        PlatformServices.delivered(data.getString("id"))
    }
}
class ReminderBootReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PlatformServices.context = context.applicationContext
        PlatformServices.restore()
    }
}
