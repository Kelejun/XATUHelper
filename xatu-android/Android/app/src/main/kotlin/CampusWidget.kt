package xatu.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.LocalDate
import java.time.ZoneId
import java.time.Instant
import java.util.Locale

/** Home-screen overview backed by the same snapshot as the iOS widget. */
class CampusWidget: AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, render(context))
    }
    companion object {
        fun save(context: Context, snapshot: String) {
            context.getSharedPreferences("xatu.widget", Context.MODE_PRIVATE).edit().putString("snapshot", snapshot).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CampusWidget::class.java))
            for (id in ids) manager.updateAppWidget(id, render(context))
        }
        private fun render(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.campus_widget)
            val raw = context.getSharedPreferences("xatu.widget", Context.MODE_PRIVATE).getString("snapshot", null)
            val snapshot = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            var title = "XATU Helper"
            var text = "打开 App 登录并刷新课表"
            if (snapshot?.optBoolean("loggedIn") == true) {
                title += " · 第${snapshot.optInt("week")}周"
                val generated = runCatching { Instant.parse(snapshot.getString("generatedAt")).atZone(ZoneId.systemDefault()).toLocalDate() }.getOrNull()
                val today = LocalDate.now()
                val courses = when {
                    generated == today -> snapshot.optJSONArray("courses")
                    generated?.plusDays(1) == today -> snapshot.optJSONArray("tomorrowCourses")
                    else -> null
                }
                val rows = mutableListOf<String>()
                if (!snapshot.isNull("balance")) rows += String.format(Locale.CHINA, "电费余额 ¥%.2f", snapshot.optDouble("balance"))
                if (courses == null) rows += "课表已过期，打开 App 刷新"
                else if (courses.length() == 0) rows += "今天没有课"
                else for (i in 0 until minOf(4, courses.length())) {
                    val course = courses.getJSONObject(i)
                    val minutes = course.optInt("startMinutes")
                    rows += String.format(Locale.CHINA, "%02d:%02d  %s  %s", minutes / 60, minutes % 60, course.optString("name"), course.optString("room"))
                }
                text = rows.joinToString("\n")
            }
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_content, text)
            val launch = PendingIntent.getActivity(context, 1, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_root, launch)
            return views
        }
    }
}
