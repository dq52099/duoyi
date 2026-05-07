package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
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

            // 点击任意区域都打开待办页
            val open = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java,
                Uri.parse("duoyi://tab/todo")
            )
            views.setOnClickPendingIntent(R.id.widget_todo_root, open)

            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
