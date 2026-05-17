package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * "今日待办 Top 3" 小组件。
 *
 * Flutter 端把以下键写入 HomeWidget：
 *   todo_top3_1 / todo_top3_2 / todo_top3_3 ：未完成待办文字
 *   todo_top3_count                       ：今日未完成总数
 *   brand_app_title                       ：品牌标题
 */
class DuoyiTodoWidgetProvider : AppWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_todo_widget)

            views.setTextViewText(
                R.id.widget_todo_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(
                R.id.widget_todo_count,
                prefs.getInt("todo_top3_count", 0).toString()
            )
            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_todo_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_todo_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_todo_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_todo_nav_focus, tabFocus)
            views.setTextViewText(
                R.id.widget_todo_item_1,
                prefs.getString("todo_top3_1", "") ?: ""
            )
            views.setTextViewText(
                R.id.widget_todo_item_2,
                prefs.getString("todo_top3_2", "") ?: ""
            )
            views.setTextViewText(
                R.id.widget_todo_item_3,
                prefs.getString("todo_top3_3", "") ?: ""
            )
            bindTodoRow(context, views, prefs, 1, R.id.widget_todo_item_1, R.id.widget_todo_done_1)
            bindTodoRow(context, views, prefs, 2, R.id.widget_todo_item_2, R.id.widget_todo_done_2)
            bindTodoRow(context, views, prefs, 3, R.id.widget_todo_item_3, R.id.widget_todo_done_3)

            // 点击任意区域都打开待办页
            val open = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("duoyi://tab/todo")
            )
            views.setOnClickPendingIntent(R.id.widget_todo_root, open)
            views.setOnClickPendingIntent(R.id.widget_todo_nav_todo, open)
            views.setOnClickPendingIntent(
                R.id.widget_todo_nav_habit,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_todo_nav_calendar,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_todo_nav_focus,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
                )
            )

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun bindTodoRow(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        index: Int,
        itemViewId: Int,
        doneViewId: Int
    ) {
        val todoId = prefs.getString("todo_top3_${index}_id", "") ?: ""
        if (todoId.isBlank()) {
            views.setViewVisibility(doneViewId, View.GONE)
            return
        }
        views.setViewVisibility(doneViewId, View.VISIBLE)
        views.setOnClickPendingIntent(
            itemViewId,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("duoyi://todo/$todoId")
            )
        )
        views.setOnClickPendingIntent(
            doneViewId,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("duoyi://action/complete_todo?id=$todoId")
            )
        )
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, DuoyiTodoWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, DuoyiTodoWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
