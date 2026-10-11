package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
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
open class DuoyiTodoWidgetProvider : DuoyiStyledWidgetProvider() {
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
        val backing = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetSnapshot.renderWidget(context, appWidgetManager, backing, id,
                DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)) { frame ->
                val prefs = frame.prefs
                val views = RemoteViews(context.packageName, R.layout.duoyi_todo_widget)
                DuoyiWidgetTheme.applyContainer(
                    context = context,
                    views = views,
                    prefs = prefs,
                    rootId = R.id.widget_todo_root,
                    navId = R.id.widget_todo_bottom_nav,
                    appWidgetId = id,
                )
                DuoyiWidgetTheme.applyTextColors(
                    views,
                    prefs,
                    primaryIds = intArrayOf(
                        R.id.widget_todo_title,
                        R.id.widget_todo_count,
                        R.id.widget_todo_nav_todo,
                        R.id.widget_todo_quick_add,
                        R.id.widget_todo_today_summary,
                        R.id.widget_todo_done_1,
                        R.id.widget_todo_done_2,
                        R.id.widget_todo_done_3,
                    ),
                    bodyIds = intArrayOf(
                        R.id.widget_todo_item_1,
                        R.id.widget_todo_item_2,
                        R.id.widget_todo_item_3,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_todo_unit,
                        R.id.widget_todo_nav_habit,
                        R.id.widget_todo_nav_calendar,
                        R.id.widget_todo_nav_focus,
                    ),
                )
                DuoyiWidgetTheme.applyButtonSurfaces(
                    views,
                    prefs,
                    secondaryIds = intArrayOf(
                        R.id.widget_todo_quick_add,
                        R.id.widget_todo_done_1,
                        R.id.widget_todo_done_2,
                        R.id.widget_todo_done_3,
                    ),
                )

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                val todoCount = prefs.getInt("todo_top3_count", 0)
                views.setTextViewText(
                    R.id.widget_todo_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_count,
                    todoCount.toString()
                )
                views.setTextViewText(
                    R.id.widget_todo_unit,
                    DuoyiWidgetCopy.todoCountUnit(todoCount, isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_quick_add,
                    DuoyiWidgetCopy.todoQuickAdd(isZh)
                )
                val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
                val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
                val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
                val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
                views.setTextViewText(R.id.widget_todo_nav_todo, tabTodo)
                views.setTextViewText(R.id.widget_todo_nav_habit, tabHabit)
                views.setTextViewText(R.id.widget_todo_nav_calendar, tabCalendar)
                views.setTextViewText(R.id.widget_todo_nav_focus, tabFocus)
                val todo1 = prefs.getString("todo_top3_1", null)
                val todo1Title = if (todo1.isNullOrBlank() || todo1 == "今天没有未完成待办" || todo1 == "No open tasks today") {
                    DuoyiWidgetCopy.defaultTodoEmpty(isZh)
                } else {
                    cleanTodoTitle(todo1)
                }
                views.setTextViewText(
                    R.id.widget_todo_item_1,
                    todo1Title
                )
                views.setTextViewText(
                    R.id.widget_todo_item_2,
                    cleanTodoTitle(prefs.getString("todo_top3_2", "") ?: "")
                )
                views.setTextViewText(
                    R.id.widget_todo_item_3,
                    cleanTodoTitle(prefs.getString("todo_top3_3", "") ?: "")
                )
                views.setTextViewText(
                    R.id.widget_todo_today_summary,
                    DuoyiWidgetCopy.todoSummary(prefs.getInt("todo_top3_count", 0), isZh)
                )
                bindTodoRow(context, views, frame, 1, R.id.widget_todo_item_1, R.id.widget_todo_done_1)
                bindTodoRow(context, views, frame, 2, R.id.widget_todo_item_2, R.id.widget_todo_done_2)
                bindTodoRow(context, views, frame, 3, R.id.widget_todo_item_3, R.id.widget_todo_done_3)
                val secondRowVisibility = DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
                val thirdRowVisibility = DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
                views.setViewVisibility(
                    R.id.widget_todo_bottom_nav,
                    DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
                )
                views.setViewVisibility(R.id.widget_todo_row_2, secondRowVisibility)
                views.setViewVisibility(
                    R.id.widget_todo_done_2,
                    if ((prefs.getString("todo_top3_2_id", "") ?: "").isBlank()) View.GONE else secondRowVisibility
                )
                views.setViewVisibility(R.id.widget_todo_row_3, thirdRowVisibility)
                views.setViewVisibility(
                    R.id.widget_todo_done_3,
                    if ((prefs.getString("todo_top3_3_id", "") ?: "").isBlank()) View.GONE else thirdRowVisibility
                )
                views.setViewVisibility(
                    R.id.widget_todo_today_summary,
                    DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
                )

                // 点击任意区域都打开待办页
                val open = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("duoyi://tab/todo")
                )
                val quickAdd = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java,
                    Uri.parse("duoyi://action/quick_todo")
                )
                views.setOnClickPendingIntent(R.id.widget_todo_root, open)
                views.setOnClickPendingIntent(R.id.widget_todo_title, open)
                views.setOnClickPendingIntent(R.id.widget_todo_count, open)
                views.setOnClickPendingIntent(R.id.widget_todo_quick_add, quickAdd)
                views.setOnClickPendingIntent(R.id.widget_todo_row_1, open)
                views.setOnClickPendingIntent(R.id.widget_todo_row_2, open)
                views.setOnClickPendingIntent(R.id.widget_todo_row_3, open)
                views.setOnClickPendingIntent(R.id.widget_todo_today_summary, open)
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

                DuoyiWidgetBuiltViews(views)
            }
        }
    }

    private fun bindTodoRow(
        context: Context,
        views: RemoteViews,
        frame: DuoyiWidgetRenderFrame,
        index: Int,
        itemViewId: Int,
        doneViewId: Int
    ) {
        val prefs = frame.prefs
        val todoId = prefs.getString("todo_top3_${index}_id", "") ?: ""
        if (!frame.fresh || todoId.isBlank()) {
            views.setViewVisibility(doneViewId, View.GONE)
            views.setOnClickPendingIntent(
                itemViewId,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("duoyi://tab/todo")
                )
            )
            return
        }
        val encodedTodoId = Uri.encode(todoId)
        val isZh = DuoyiWidgetCopy.isZh(prefs)
        val todoTitle = cleanTodoTitle(prefs.getString("todo_top3_${index}", "") ?: "")
        views.setContentDescription(doneViewId, DuoyiWidgetCopy.todoDoneContentDescription(todoTitle, isZh))
        views.setContentDescription(itemViewId, DuoyiWidgetCopy.todoItemContentDescription(todoTitle, isZh))
        views.setTextViewText(doneViewId, "○")
        views.setViewVisibility(doneViewId, View.VISIBLE)
        views.setOnClickPendingIntent(
            itemViewId,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                DuoyiWidgetSnapshot.entityUri(
                    frame, Uri.parse("duoyi://todo/$encodedTodoId"), Uri.parse("duoyi://todo")
                )
            )
        )
        views.setOnClickPendingIntent(
            doneViewId,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                DuoyiWidgetSnapshot.actionUri(frame, Uri.parse("duoyi://action/complete_todo?id=$encodedTodoId"))
            )
        )
    }

    private fun cleanTodoTitle(raw: String): String {
        val title = raw.trim().removePrefix("·").trim()
        return title.ifBlank { raw }
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "todo")
        }
    }
}
