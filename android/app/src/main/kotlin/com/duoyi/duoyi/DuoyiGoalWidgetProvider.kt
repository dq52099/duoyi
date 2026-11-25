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

/** "目标" 小组件。 */
open class DuoyiGoalWidgetProvider : DuoyiStyledWidgetProvider() {
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
                val views = RemoteViews(context.packageName, R.layout.duoyi_goal_widget)
                DuoyiWidgetTheme.applyContainer(
                    context = context,
                    views = views,
                    prefs = prefs,
                    rootId = R.id.widget_goal_root,
                    navId = R.id.widget_goal_bottom_nav,
                    appWidgetId = id,
                )
                DuoyiWidgetTheme.applyTextColors(
                    views,
                    prefs,
                    primaryIds = intArrayOf(
                        R.id.widget_goal_title,
                        R.id.widget_goal_quick_add,
                        R.id.widget_goal_nav_calendar,
                    ),
                    bodyIds = intArrayOf(
                        R.id.widget_goal_1,
                        R.id.widget_goal_2,
                        R.id.widget_goal_3,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_goal_subtitle,
                        R.id.widget_goal_nav_todo,
                        R.id.widget_goal_nav_habit,
                        R.id.widget_goal_nav_focus,
                    ),
                    context = context,
                    appWidgetId = id,
                )

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                views.setTextViewText(
                    R.id.widget_goal_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                views.setTextViewText(R.id.widget_goal_subtitle, DuoyiWidgetCopy.goalSubtitle(isZh))
                val goalRaw1 = prefs.getString("goal_highlight_1", null)
                val goalRaw2 = prefs.getString("goal_highlight_2", null)
                val goalRaw3 = prefs.getString("goal_highlight_3", null)
                views.setTextViewText(
                    R.id.widget_goal_1,
                    DuoyiWidgetCopy.goalHighlight1(goalRaw1, isZh)
                )
                views.setTextViewText(
                    R.id.widget_goal_2,
                    DuoyiWidgetCopy.goalHighlight2(goalRaw2, isZh)
                )
                views.setTextViewText(
                    R.id.widget_goal_3,
                    DuoyiWidgetCopy.goalHighlight3(goalRaw3, isZh)
                )
                val goalProgressPercent = DuoyiWidgetContent.resolveGoalProgressPercent(
                    listOf(goalRaw1, goalRaw2, goalRaw3),
                    frame.fresh,
                    frame.core.publicationState,
                )
                if (goalProgressPercent != null) {
                    views.setViewVisibility(R.id.widget_goal_progress_bar, View.VISIBLE)
                    DuoyiWidgetTheme.applyProgressBar(
                        views = views,
                        progressBarId = R.id.widget_goal_progress_bar,
                        progress = goalProgressPercent,
                        prefs = prefs,
                        context = context,
                        appWidgetId = id,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_goal_progress_bar, View.GONE)
                }
                views.setViewVisibility(
                    R.id.widget_goal_2,
                    DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
                )
                views.setViewVisibility(
                    R.id.widget_goal_3,
                    DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
                )
                views.setViewVisibility(
                    R.id.widget_goal_bottom_nav,
                    DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
                )

                val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
                val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
                val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
                val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
                views.setTextViewText(R.id.widget_goal_nav_todo, tabTodo)
                views.setTextViewText(R.id.widget_goal_nav_habit, tabHabit)
                views.setTextViewText(R.id.widget_goal_nav_calendar, tabCalendar)
                views.setTextViewText(R.id.widget_goal_nav_focus, tabFocus)

                val openGoal = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://goal")
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

                val showQuickAdd = !DuoyiWidgetDisplayMode.isCompact(prefs, id) && frame.fresh
                views.setViewVisibility(R.id.widget_goal_quick_add, if (showQuickAdd) View.VISIBLE else View.GONE)
                views.setContentDescription(R.id.widget_goal_quick_add, DuoyiWidgetCopy.quickAddGoalDescription(isZh))
                views.setOnClickPendingIntent(
                    R.id.widget_goal_quick_add,
                    if (showQuickAdd) HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        DuoyiWidgetSnapshot.actionUri(frame, Uri.parse("duoyi://action/quick_goal")),
                    ) else openGoal,
                )
                views.setOnClickPendingIntent(R.id.widget_goal_root, openGoal)
                views.setOnClickPendingIntent(R.id.widget_goal_title, openGoal)
                views.setOnClickPendingIntent(R.id.widget_goal_subtitle, openGoal)
                views.setOnClickPendingIntent(
                    R.id.widget_goal_1,
                    itemIntent(context, frame, "goal_highlight_1_id", "duoyi://goal")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_goal_2,
                    itemIntent(context, frame, "goal_highlight_2_id", "duoyi://goal")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_goal_3,
                    itemIntent(context, frame, "goal_highlight_3_id", "duoyi://goal")
                )
                views.setOnClickPendingIntent(R.id.widget_goal_nav_todo, openTodo)
                views.setOnClickPendingIntent(R.id.widget_goal_nav_habit, openHabit)
                views.setOnClickPendingIntent(R.id.widget_goal_nav_calendar, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_goal_nav_focus, openFocus)

                DuoyiWidgetBuiltViews(views)
            }
        }
    }

    companion object {
        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
            )

        private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
            val rawId = prefs.getString(key, "")?.trim().orEmpty()
            if (rawId.isBlank()) return Uri.parse(fallback)
            if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)
            return Uri.parse("$fallback/${Uri.encode(rawId)}")
        }

        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "goal")
        }
    }
}
