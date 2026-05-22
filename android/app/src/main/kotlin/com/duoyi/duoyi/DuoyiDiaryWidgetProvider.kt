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

/** "日记" 小组件。 */
class DuoyiDiaryWidgetProvider : AppWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_diary_widget)

            views.setTextViewText(
                R.id.widget_diary_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_diary_subtitle, "日记")
            views.setTextViewText(
                R.id.widget_diary_1,
                prefs.getString("diary_highlight_1", "· 暂无日记") ?: "· 暂无日记"
            )
            views.setTextViewText(
                R.id.widget_diary_2,
                prefs.getString("diary_highlight_2", "") ?: ""
            )
            views.setTextViewText(
                R.id.widget_diary_3,
                prefs.getString("diary_highlight_3", "") ?: ""
            )
            views.setViewVisibility(
                R.id.widget_diary_2,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs)
            )
            views.setViewVisibility(
                R.id.widget_diary_3,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_diary_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_diary_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_diary_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_diary_nav_focus, tabFocus)

            val openDiary = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://diary")
            )
            val openTodo = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
            )
            val openHabit = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
            )
            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            val openFocus = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
            )

            views.setOnClickPendingIntent(R.id.widget_diary_root, openDiary)
            views.setOnClickPendingIntent(
                R.id.widget_diary_1,
                itemIntent(context, prefs, "diary_highlight_1_id", "duoyi://diary")
            )
            views.setOnClickPendingIntent(
                R.id.widget_diary_2,
                itemIntent(context, prefs, "diary_highlight_2_id", "duoyi://diary")
            )
            views.setOnClickPendingIntent(
                R.id.widget_diary_3,
                itemIntent(context, prefs, "diary_highlight_3_id", "duoyi://diary")
            )
            views.setOnClickPendingIntent(R.id.widget_diary_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_diary_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_diary_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_diary_nav_focus, openFocus)

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
            val ids = mgr.getAppWidgetIds(ComponentName(context, DuoyiDiaryWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, DuoyiDiaryWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
