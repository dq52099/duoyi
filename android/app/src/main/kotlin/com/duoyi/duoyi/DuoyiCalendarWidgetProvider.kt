package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
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
open class DuoyiCalendarWidgetProvider : DuoyiStyledWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            requestUpdate(context)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = HomeWidgetPlugin.getData(context)
        appWidgetIds.forEach { DuoyiWidgetDisplayMode.clearForWidget(prefs, it) }
        super.onDeleted(context, appWidgetIds)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)?.let { style ->
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)
            }
            val views = RemoteViews(context.packageName, R.layout.duoyi_calendar_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_calendar_root,
                navId = R.id.widget_calendar_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_calendar_title,
                    R.id.widget_calendar_summary,
                    R.id.widget_calendar_nav_calendar,
                    R.id.widget_calendar_schedule_button,
                ),
                onPrimaryIds = intArrayOf(R.id.widget_calendar_today_button),
                bodyIds = intArrayOf(R.id.widget_calendar_grid),
                mutedIds = intArrayOf(
                    R.id.widget_calendar_month,
                    R.id.widget_calendar_nav_todo,
                    R.id.widget_calendar_nav_habit,
                    R.id.widget_calendar_nav_focus,
                ),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_calendar_today_button),
                secondaryIds = intArrayOf(R.id.widget_calendar_schedule_button),
            )
            val now = Calendar.getInstance()
            val monthTitle = SimpleDateFormat("yyyy年M月", Locale.getDefault()).format(now.time)
            val visibleWeekRows = when {
                DuoyiWidgetDisplayMode.isCompact(prefs, id) -> 1
                DuoyiWidgetDisplayMode.isDetailed(prefs, id) -> 6
                else -> 3
            }

            views.setTextViewText(
                R.id.widget_calendar_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_calendar_month, monthTitle)
            views.setTextViewText(R.id.widget_calendar_grid, buildMonthGrid(now, visibleWeekRows))
            views.setTextViewText(
                R.id.widget_calendar_summary,
                prefs.getString("calendar_month_summary", "本月日期 · 今日已标记") ?: "本月日期 · 今日已标记"
            )
            views.setViewVisibility(
                R.id.widget_calendar_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_calendar_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_calendar_actions,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
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
            views.setOnClickPendingIntent(R.id.widget_calendar_title, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_month, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_grid, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_summary, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_today_button, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_schedule_button, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_focus, openFocus)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildMonthGrid(now: Calendar, visibleWeekRows: Int): String {
        val cal = now.clone() as Calendar
        val today = cal.get(Calendar.DAY_OF_MONTH)
        cal.set(Calendar.DAY_OF_MONTH, 1)
        val firstWeekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7
        val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        val cells = MutableList(42) { "   " }
        for (day in 1..maxDay) {
            cells[firstWeekday + day - 1] = if (day == today) {
                day.toString().padStart(2, ' ') + "*"
            } else {
                day.toString().padStart(2, ' ') + " "
            }
        }
        val lines = mutableListOf("一   二   三   四   五   六   日")
        val todayWeek = ((firstWeekday + today - 1) / 7).coerceIn(0, 5)
        val rows = visibleWeekRows.coerceIn(1, 6)
        val startWeek = when {
            rows >= 6 -> 0
            rows == 1 -> todayWeek
            else -> (todayWeek - 1).coerceIn(0, 6 - rows)
        }
        for (week in startWeek until startWeek + rows) {
            lines += cells.subList(week * 7, week * 7 + 7).joinToString(" ")
        }
        return lines.joinToString("\n")
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "calendar")
        }
    }
}
