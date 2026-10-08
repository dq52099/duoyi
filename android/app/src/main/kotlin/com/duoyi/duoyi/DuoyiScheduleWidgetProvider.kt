package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/** "今日日程" 小组件。 */
open class DuoyiScheduleWidgetProvider : DuoyiStyledWidgetProvider() {
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
        val prefs: SharedPreferences = DuoyiWidgetSnapshot.forDisplay(context, HomeWidgetPlugin.getData(context))

        appWidgetIds.forEach { id ->
            DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)?.let { style ->
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)
            }
            val views = RemoteViews(context.packageName, R.layout.duoyi_schedule_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_schedule_root,
                navId = R.id.widget_schedule_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_schedule_title,
                    R.id.widget_schedule_nav_calendar,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_schedule_1,
                    R.id.widget_schedule_2,
                    R.id.widget_schedule_3,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_schedule_subtitle,
                    R.id.widget_schedule_nav_todo,
                    R.id.widget_schedule_nav_habit,
                    R.id.widget_schedule_nav_focus,
                ),
            )
            val isZh = DuoyiWidgetCopy.isZh(prefs)
            val todayEventSummary = DuoyiWidgetCopy.todayEventSummary(
                prefs.getString("today_event_summary", null),
                isZh
            )

            views.setTextViewText(
                R.id.widget_schedule_title,
                DuoyiWidgetCopy.appTitle(prefs, isZh)
            )
            views.setTextViewText(R.id.widget_schedule_subtitle, DuoyiWidgetCopy.scheduleSubtitle(isZh))
            views.setTextViewText(
                R.id.widget_schedule_1,
                DuoyiWidgetCopy.scheduleHighlight1(
                    prefs.getString("schedule_highlight_1", null),
                    todayEventSummary,
                    isZh
                )
            )
            views.setTextViewText(
                R.id.widget_schedule_2,
                DuoyiWidgetCopy.scheduleHighlight2(
                    prefs.getString("schedule_highlight_2", null),
                    isZh
                )
            )
            views.setTextViewText(
                R.id.widget_schedule_3,
                DuoyiWidgetCopy.scheduleHighlight3(
                    prefs.getString("schedule_highlight_3", null),
                    isZh
                )
            )
            views.setViewVisibility(
                R.id.widget_schedule_2,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_schedule_3,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_schedule_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
            val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
            val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
            val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
            views.setTextViewText(R.id.widget_schedule_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_schedule_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_schedule_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_schedule_nav_focus, tabFocus)

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

            views.setOnClickPendingIntent(R.id.widget_schedule_root, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_schedule_title, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_schedule_subtitle, openCalendar)
            views.setOnClickPendingIntent(
                R.id.widget_schedule_1,
                itemIntent(context, prefs, "schedule_highlight_1_id", "duoyi://calendar")
            )
            views.setOnClickPendingIntent(
                R.id.widget_schedule_2,
                itemIntent(context, prefs, "schedule_highlight_2_id", "duoyi://calendar")
            )
            views.setOnClickPendingIntent(
                R.id.widget_schedule_3,
                itemIntent(context, prefs, "schedule_highlight_3_id", "duoyi://calendar")
            )
            views.setOnClickPendingIntent(R.id.widget_schedule_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_schedule_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_schedule_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_schedule_nav_focus, openFocus)

            DuoyiWidgetSnapshot.finishRender(context, views, prefs, id)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                detailUri(prefs, key, fallback)
            )

        private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
            val rawId = prefs.getString(key, "")?.trim().orEmpty()
            if (rawId.isBlank()) return Uri.parse(fallback)
            if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)
            return Uri.parse("$fallback/${Uri.encode(rawId)}")
        }

        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "schedule")
        }
    }
}
