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

/** "习惯" 小组件。 */
open class DuoyiHabitWidgetProvider : DuoyiStyledWidgetProvider() {
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
                val views = RemoteViews(context.packageName, R.layout.duoyi_habit_widget)
                DuoyiWidgetTheme.applyContainer(
                    context = context,
                    views = views,
                    prefs = prefs,
                    rootId = R.id.widget_habit_root,
                    navId = R.id.widget_habit_bottom_nav,
                    appWidgetId = id,
                )
                DuoyiWidgetTheme.applyTextColors(
                    views,
                    prefs,
                    primaryIds = intArrayOf(
                        R.id.widget_habit_title,
                        R.id.widget_habit_percent,
                        R.id.widget_habit_nav_habit,
                    ),
                    bodyIds = intArrayOf(
                        R.id.widget_habit_summary,
                        R.id.widget_habit_streak,
                        R.id.widget_habit_hint,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_habit_subtitle,
                        R.id.widget_habit_nav_todo,
                        R.id.widget_habit_nav_calendar,
                        R.id.widget_habit_nav_focus,
                    ),
                )

                DuoyiWidgetTheme.applyButtonSurfaces(views, prefs, secondaryIds = intArrayOf(R.id.widget_habit_hint))

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                views.setTextViewText(
                    R.id.widget_habit_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                val noHabitsToday = prefs.getInt("habit_active_count", -1) == 0
                views.setTextViewText(R.id.widget_habit_percent,
                    if (noHabitsToday) "—" else "${prefs.getInt("habit_percent", 0).coerceIn(0, 100)}%")
                views.setTextViewText(R.id.widget_habit_subtitle, DuoyiWidgetCopy.habitSubtitle(isZh))
                views.setTextViewText(
                    R.id.widget_habit_summary,
                    DuoyiWidgetCopy.habitSummary(prefs.getString("habit_summary", null), isZh)
                )
                views.setTextViewText(
                    R.id.widget_habit_streak,
                    DuoyiWidgetCopy.streakSummary(prefs.getString("streak_summary", null), isZh)
                )
                val habitQuickCheckId = prefs.getString("habit_quick_check_id", "") ?: ""
                val habitQuickCheckLabel = DuoyiWidgetCopy.habitQuickCheckLabel(
                    prefs.getString("habit_quick_check_label", null),
                    isZh
                )
                views.setTextViewText(R.id.widget_habit_hint, habitQuickCheckLabel)
                views.setContentDescription(R.id.widget_habit_hint, habitQuickCheckLabel)
                views.setViewVisibility(
                    R.id.widget_habit_streak,
                    if (noHabitsToday) android.view.View.GONE
                    else DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
                )
                views.setViewVisibility(
                    R.id.widget_habit_bottom_nav,
                    DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
                )
                views.setViewVisibility(
                    R.id.widget_habit_hint,
                    android.view.View.VISIBLE
                )

                val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
                val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
                val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
                val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
                views.setTextViewText(R.id.widget_habit_nav_todo, tabTodo)
                views.setTextViewText(R.id.widget_habit_nav_habit, tabHabit)
                views.setTextViewText(R.id.widget_habit_nav_calendar, tabCalendar)
                views.setTextViewText(R.id.widget_habit_nav_focus, tabFocus)

                val openHabit = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
                )
                val openTodo = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
                )
                val openCalendar = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
                )
                val openFocus = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
                )
                val quickCheckHabit = if (frame.fresh && habitQuickCheckId.isNotBlank()) {
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        DuoyiWidgetSnapshot.actionUri(frame, Uri.parse("duoyi://action/checkin_habit?id=${Uri.encode(habitQuickCheckId)}"))
                    )
                } else {
                    openHabit
                }

                views.setOnClickPendingIntent(R.id.widget_habit_root, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_title, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_subtitle, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_percent, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_summary, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_streak, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_hint, quickCheckHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_nav_todo, openTodo)
                views.setOnClickPendingIntent(R.id.widget_habit_nav_habit, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_nav_calendar, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_habit_nav_focus, openFocus)

                DuoyiWidgetBuiltViews(views)
            }
        }
    }

    companion object {
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "habit")
        }
    }
}
