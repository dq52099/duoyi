package com.example.fingertip_time

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home screen widget for MIUI / generic Android.
 * Pulls counters that the Flutter side wrote via HomeWidget.saveWidgetData.
 */
class FingertipWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.fingertip_widget)
            val today = SimpleDateFormat("MM/dd", Locale.getDefault()).format(Date())

            views.setTextViewText(R.id.widget_title, prefs.getString("brand_app_title", "指尖时光"))
            views.setTextViewText(R.id.widget_date, today)
            views.setTextViewText(R.id.widget_todo_count, prefs.getInt("todo_count", 0).toString())
            views.setTextViewText(R.id.widget_habit_progress, "${prefs.getInt("habit_percent", 0)}%")
            views.setTextViewText(R.id.widget_pomodoro_count, prefs.getInt("pomodoro_today", 0).toString())

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabFocus = prefs.getString("nav_focus", "番茄") ?: "番茄"
            views.setTextViewText(R.id.widget_quick_pomodoro, "开始$tabFocus")
            views.setTextViewText(R.id.widget_quick_open, "打开 App")

            // Tap title/stats area opens the app on the calendar tab
            val openAppIntent: PendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("fingertip://tab/calendar")
            )
            views.setOnClickPendingIntent(R.id.widget_title, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_date, openAppIntent)
            views.setOnClickPendingIntent(R.id.widget_quick_open, openAppIntent)

            // Tap todo number opens todo tab
            views.setOnClickPendingIntent(
                R.id.widget_todo_count,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("fingertip://tab/todo")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_habit_progress,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("fingertip://tab/habit")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_pomodoro_count,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("fingertip://tab/focus")
                )
            )

            // Quick start pomodoro: launch into focus tab with auto-start flag
            val quickPomodoroIntent: PendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse("fingertip://action/start_pomodoro")
            )
            views.setOnClickPendingIntent(R.id.widget_quick_pomodoro, quickPomodoroIntent)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget */
        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, FingertipWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, FingertipWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
