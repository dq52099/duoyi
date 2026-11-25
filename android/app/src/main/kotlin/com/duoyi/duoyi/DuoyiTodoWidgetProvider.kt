package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
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
        when (intent.action) {
            Intent.ACTION_MY_PACKAGE_REPLACED -> requestUpdate(context)
            ACTION_COMPLETE_TODO_BG -> handleBackgroundComplete(context, intent)
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
                val layoutId = if (DuoyiWidgetSnapshot.needsTodoReflow(context, frame)) {
                    R.layout.duoyi_todo_widget_reflow
                } else {
                    R.layout.duoyi_todo_widget
                }
                val views = RemoteViews(context.packageName, layoutId)
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
                        R.id.widget_todo_recovery,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_todo_unit,
                        R.id.widget_todo_nav_habit,
                        R.id.widget_todo_nav_calendar,
                        R.id.widget_todo_nav_focus,
                    ),
                    context = context,
                    appWidgetId = id,
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
                    context = context,
                    appWidgetId = id,
                )

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                val todoCount = prefs.getInt("todo_top3_count", 0)
                views.setTextViewText(
                    R.id.widget_todo_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_count,
                    if (frame.fresh) todoCount.toString() else "—"
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
                views.setTextViewText(
                    R.id.widget_todo_item_1,
                    DuoyiWidgetCopy.todoItemTitle(prefs, 1, isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_item_2,
                    DuoyiWidgetCopy.todoItemTitle(prefs, 2, isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_item_3,
                    DuoyiWidgetCopy.todoItemTitle(prefs, 3, isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_today_summary,
                    DuoyiWidgetCopy.todoSummary(prefs.getInt("todo_top3_count", 0), isZh)
                )
                views.setTextViewText(
                    R.id.widget_todo_recovery,
                    DuoyiWidgetCopy.todoRecoveryText(isZh)
                )
                views.setViewVisibility(R.id.widget_todo_recovery, View.GONE)
                bindTodoRow(context, views, frame, backing, 1, R.id.widget_todo_item_1, R.id.widget_todo_done_1, id)
                bindTodoRow(context, views, frame, backing, 2, R.id.widget_todo_item_2, R.id.widget_todo_done_2, id)
                bindTodoRow(context, views, frame, backing, 3, R.id.widget_todo_item_3, R.id.widget_todo_done_3, id)
                val secondRowVisibility = DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
                val thirdRowVisibility = DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
                views.setViewVisibility(
                    R.id.widget_todo_bottom_nav,
                    DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
                )
                views.setViewVisibility(R.id.widget_todo_row_2, secondRowVisibility)
                views.setViewVisibility(
                    R.id.widget_todo_done_2,
                    if (!frame.fresh || (prefs.getString("todo_top3_2_id", "") ?: "").isBlank()) View.GONE else secondRowVisibility
                )
                views.setViewVisibility(R.id.widget_todo_row_3, thirdRowVisibility)
                views.setViewVisibility(
                    R.id.widget_todo_done_3,
                    if (!frame.fresh || (prefs.getString("todo_top3_3_id", "") ?: "").isBlank()) View.GONE else thirdRowVisibility
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
                views.setOnClickPendingIntent(R.id.widget_todo_recovery, open)
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
        backing: SharedPreferences,
        index: Int,
        itemViewId: Int,
        doneViewId: Int,
        appWidgetId: Int,
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
        val completedBgIds = backing.getStringSet(KEY_TODO_COMPLETED_BG_IDS, emptySet()) ?: emptySet()
        val optimisticallyCompleted = todoId in completedBgIds
        views.setContentDescription(doneViewId, DuoyiWidgetCopy.todoDoneContentDescription(todoTitle, isZh))
        views.setContentDescription(itemViewId, DuoyiWidgetCopy.todoItemContentDescription(todoTitle, isZh))
        views.setTextViewText(doneViewId, if (optimisticallyCompleted) "✓" else "○")
        if (optimisticallyCompleted) {
            val theme = DuoyiWidgetTheme.read(prefs, context, appWidgetId)
            views.setTextColor(itemViewId, theme.readableMutedText)
        }
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
        val completeUri = DuoyiWidgetSnapshot.actionUri(
            frame,
            Uri.parse("duoyi://action/complete_todo?id=$encodedTodoId"),
        )
        val donePendingIntent = try {
            val bgIntent = Intent(context, DuoyiTodoWidgetProvider::class.java).apply {
                action = ACTION_COMPLETE_TODO_BG
                data = completeUri
                putExtra(EXTRA_TODO_ID, todoId)
            }
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            PendingIntent.getBroadcast(context, 12000 + index, bgIntent, flags)
        } catch (_: Throwable) {
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, completeUri)
        }
        views.setOnClickPendingIntent(doneViewId, donePendingIntent)
    }

    private fun handleBackgroundComplete(context: Context, intent: Intent) {
        val todoId = intent.getStringExtra(EXTRA_TODO_ID)?.trim().orEmpty()
        val actionUriStr = intent.dataString?.takeIf { it.isNotBlank() }
            ?: if (todoId.isNotBlank()) "duoyi://action/complete_todo?id=${Uri.encode(todoId)}" else ""
        if (todoId.isBlank() || actionUriStr.isBlank()) return
        val backing = HomeWidgetPlugin.getData(context)
        val updatedQueue = DuoyiWidgetContent.appendPendingBgAction(
            backing.getString(KEY_PENDING_BG_ACTIONS, null),
            actionUriStr,
        )
        val completedIds = LinkedHashSet(
            backing.getStringSet(KEY_TODO_COMPLETED_BG_IDS, emptySet()) ?: emptySet(),
        )
        completedIds.add(todoId)
        backing.edit()
            .putString(KEY_PENDING_BG_ACTIONS, updatedQueue)
            .putStringSet(KEY_TODO_COMPLETED_BG_IDS, completedIds)
            .apply()
        requestUpdate(context)
        try {
            if (HomeWidgetPlugin.getDispatcherHandle(context) != 0L) {
                HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(actionUriStr)).send()
            }
        } catch (_: Throwable) {
            // Safe fallback when headless background dispatcher is not active.
        }
    }

    private fun cleanTodoTitle(raw: String): String = DuoyiWidgetCopy.cleanTodoTitle(raw)

    companion object {
        const val ACTION_COMPLETE_TODO_BG = "com.duoyi.duoyi.action.COMPLETE_TODO_BG"
        const val EXTRA_TODO_ID = "todo_id"
        private const val KEY_PENDING_BG_ACTIONS = "duoyi_widget_pending_bg_actions"
        private const val KEY_TODO_COMPLETED_BG_IDS = "todo_completed_bg_ids"

        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "todo")
        }
    }
}
