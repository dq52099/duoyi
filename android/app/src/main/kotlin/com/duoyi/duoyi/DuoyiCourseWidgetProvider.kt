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

/** "课程表" 小组件。 */
class DuoyiCourseWidgetProvider : AppWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_course_widget)

            views.setTextViewText(
                R.id.widget_course_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_course_subtitle, "今日课程")
            views.setTextViewText(
                R.id.widget_course_1,
                prefs.getString("course_highlight_1", "· 今日暂无课程") ?: "· 今日暂无课程"
            )
            views.setTextViewText(
                R.id.widget_course_2,
                prefs.getString("course_highlight_2", "") ?: ""
            )
            views.setTextViewText(
                R.id.widget_course_3,
                prefs.getString("today_event_summary", "打开日历查看完整日程") ?: "打开日历查看完整日程"
            )
            views.setViewVisibility(
                R.id.widget_course_2,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs)
            )
            views.setViewVisibility(
                R.id.widget_course_3,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_course_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_course_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_course_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_course_nav_focus, tabFocus)

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

            views.setOnClickPendingIntent(R.id.widget_course_root, openCalendar)
            views.setOnClickPendingIntent(
                R.id.widget_course_1,
                itemIntent(context, prefs, "course_highlight_1_id", "duoyi://course")
            )
            views.setOnClickPendingIntent(
                R.id.widget_course_2,
                itemIntent(context, prefs, "course_highlight_2_id", "duoyi://course")
            )
            views.setOnClickPendingIntent(R.id.widget_course_3, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_course_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_course_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_course_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_course_nav_focus, openFocus)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse((prefs.getString(key, "") ?: "").ifBlank { fallback })
            )

        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, DuoyiCourseWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, DuoyiCourseWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
