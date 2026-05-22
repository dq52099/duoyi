package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** "月历" 小组件。 */
class DuoyiCalendarWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            requestUpdate(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.duoyi_calendar_widget)
            val now = Calendar.getInstance()
            val monthTitle = SimpleDateFormat("yyyy年M月", Locale.getDefault()).format(now.time)

            views.setTextViewText(
                R.id.widget_calendar_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_calendar_month, monthTitle)
            views.setTextViewText(R.id.widget_calendar_grid, buildMonthGrid(now))
            views.setTextViewText(
                R.id.widget_calendar_summary,
                prefs.getString("calendar_month_summary", "本月日期 · 今日已标记") ?: "本月日期 · 今日已标记"
            )
            views.setViewVisibility(
                R.id.widget_calendar_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_calendar_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_calendar_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_calendar_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_calendar_nav_focus, tabFocus)

            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            val openTodo = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
            )
            val openHabit = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
            )
            val openFocus = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
            )

            views.setOnClickPendingIntent(R.id.widget_calendar_root, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_grid, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_summary, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_focus, openFocus)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildMonthGrid(now: Calendar): String {
        val cal = now.clone() as Calendar
        val today = cal.get(Calendar.DAY_OF_MONTH)
        cal.set(Calendar.DAY_OF_MONTH, 1)
        val firstWeekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7
        val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        val cells = MutableList(42) { "  " }
        for (day in 1..maxDay) {
            val label = if (day == today) "*${day.toString().padStart(1, ' ')}" else day.toString().padStart(2, ' ')
            cells[firstWeekday + day - 1] = label.takeLast(2)
        }
        val lines = mutableListOf("一 二 三 四 五 六 日")
        for (week in 0 until 6) {
            lines += cells.subList(week * 7, week * 7 + 7).joinToString(" ")
        }
        return lines.joinToString("\n")
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, DuoyiCalendarWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, DuoyiCalendarWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
