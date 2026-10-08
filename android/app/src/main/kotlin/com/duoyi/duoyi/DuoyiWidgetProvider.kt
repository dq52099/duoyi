package com.duoyi.duoyi

import android.app.PendingIntent
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
import java.util.Date
import java.util.Locale

/**
 * Home screen widget for MIUI / generic Android.
 * Pulls counters that the Flutter side wrote via HomeWidget.saveWidgetData.
 */
class DuoyiWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(context)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = HomeWidgetPlugin.getData(context)
        appWidgetIds.forEach { DuoyiWidgetDisplayMode.clearForWidget(prefs, it) }
        super.onDeleted(context, appWidgetIds)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs: SharedPreferences = DuoyiWidgetSnapshot.forDisplay(context, HomeWidgetPlugin.getData(context))

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.duoyi_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_root,
                navId = R.id.widget_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_title,
                    R.id.widget_todo_count,
                    R.id.widget_habit_progress,
                    R.id.widget_pomodoro_count,
                    R.id.widget_quick_open,
                    R.id.widget_nav_calendar,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_today_event,
                    R.id.widget_goal_summary,
                    R.id.widget_anniversary_summary,
                    R.id.widget_course_summary,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_date,
                    R.id.widget_overview_todo_label,
                    R.id.widget_overview_habit_label,
                    R.id.widget_overview_pomodoro_label,
                    R.id.widget_nav_todo,
                    R.id.widget_nav_habit,
                    R.id.widget_nav_focus,
                ),
                onPrimaryIds = intArrayOf(R.id.widget_quick_pomodoro),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_quick_pomodoro),
                secondaryIds = intArrayOf(R.id.widget_quick_open),
            )
            val isZh = DuoyiWidgetCopy.isZh(prefs)
            val appLocale = DuoyiWidgetCopy.resolveLocale(prefs)
            val today = SimpleDateFormat("MM/dd", appLocale).format(Date())

            views.setTextViewText(R.id.widget_title, DuoyiWidgetCopy.appTitle(prefs, isZh))
            views.setTextViewText(R.id.widget_date, today)
            views.setTextViewText(R.id.widget_todo_count, prefs.getInt("todo_count", 0).toString())
            views.setTextViewText(R.id.widget_overview_todo_label, DuoyiWidgetCopy.navTodo(prefs, isZh))
            views.setTextViewText(R.id.widget_habit_progress, "${prefs.getInt("habit_percent", 0)}%")
            views.setTextViewText(R.id.widget_overview_habit_label, DuoyiWidgetCopy.navHabit(prefs, isZh))
            views.setTextViewText(R.id.widget_pomodoro_count, prefs.getInt("pomodoro_today", 0).toString())
            views.setTextViewText(R.id.widget_overview_pomodoro_label, DuoyiWidgetCopy.navPomodoro(prefs, isZh))
            views.setTextViewText(
                R.id.widget_today_event,
                DuoyiWidgetCopy.todayEventSummary(prefs.getString("today_event_summary", null), isZh)
            )
            views.setTextViewText(
                R.id.widget_goal_summary,
                DuoyiWidgetCopy.goalHighlight1(prefs.getString("goal_highlight_1", null), isZh)
            )
            views.setTextViewText(
                R.id.widget_anniversary_summary,
                DuoyiWidgetCopy.anniversaryHighlight1(prefs.getString("anniversary_highlight_1", null), isZh)
            )
            views.setTextViewText(
                R.id.widget_course_summary,
                DuoyiWidgetCopy.courseHighlight1(prefs.getString("course_highlight_1", null), isZh)
            )
            views.setViewVisibility(
                R.id.widget_quick_row,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_goal_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_anniversary_summary,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_course_summary,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
            val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
            val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
            val tabFocus = DuoyiWidgetCopy.navPomodoro(prefs, isZh)
            views.setTextViewText(R.id.widget_quick_pomodoro, DuoyiWidgetCopy.quickPomodoro(isZh))
            views.setTextViewText(R.id.widget_quick_open, DuoyiWidgetCopy.quickOpen(isZh))
            views.setTextViewText(R.id.widget_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_nav_focus, tabFocus)

            // Tap title/stats area opens the app on the calendar tab
            val openAppIntent: PendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("duoyi://tab/calendar")
            )
            views.setOnClickPendingIntent(R.id.widget_title, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_date, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_quick_open, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_today_event, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_nav_calendar, openAppIntent)

            // Tap todo number opens todo tab
            val openTodoIntent = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("duoyi://tab/todo")
            )
            views.setOnClickPendingIntent(R.id.widget_todo_count, openTodoIntent)
            views.setOnClickPendingIntent(R.id.widget_nav_todo, openTodoIntent)
            views.setOnClickPendingIntent(
                R.id.widget_nav_habit,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_nav_focus,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_habit_progress,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("duoyi://tab/habit")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_pomodoro_count,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("duoyi://tab/focus")
                )
            )

            // Quick start pomodoro: launch into focus tab with auto-start flag.
            val quickPomodoroIntent: PendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("duoyi://action/start_pomodoro")
            )
            views.setOnClickPendingIntent(R.id.widget_quick_pomodoro, quickPomodoroIntent)

            DuoyiWidgetSnapshot.finishRender(context, views, prefs, id)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget */
        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, DuoyiWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, DuoyiWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
