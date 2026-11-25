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

/** "习惯" 小组件。 */
open class DuoyiHabitWidgetProvider : DuoyiStyledWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_MY_PACKAGE_REPLACED -> requestUpdate(context)
            ACTION_CHECKIN_HABIT_BG -> handleBackgroundCheckin(context, intent)
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
                        R.id.widget_habit_recovery,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_habit_subtitle,
                        R.id.widget_habit_nav_todo,
                        R.id.widget_habit_nav_calendar,
                        R.id.widget_habit_nav_focus,
                    ),
                    context = context,
                    appWidgetId = id,
                )

                DuoyiWidgetTheme.applyButtonSurfaces(
                    views,
                    prefs,
                    secondaryIds = intArrayOf(R.id.widget_habit_hint),
                    context = context,
                    appWidgetId = id,
                )

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                views.setTextViewText(
                    R.id.widget_habit_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                val noHabitsToday = prefs.getInt("habit_active_count", -1) == 0
                val habitPercent = prefs.getInt("habit_percent", 0).coerceIn(0, 100)
                views.setTextViewText(R.id.widget_habit_percent,
                    if (!frame.fresh || noHabitsToday) "—" else "$habitPercent%")
                val showProgressBar = frame.fresh && !noHabitsToday &&
                    !DuoyiWidgetDisplayMode.isCompact(prefs, id)
                views.setViewVisibility(
                    R.id.widget_habit_progress_bar,
                    if (showProgressBar) View.VISIBLE else View.GONE,
                )
                if (showProgressBar) {
                    DuoyiWidgetTheme.applyProgressBar(
                        views = views,
                        progressBarId = R.id.widget_habit_progress_bar,
                        progress = habitPercent,
                        prefs = prefs,
                        context = context,
                        appWidgetId = id,
                    )
                }
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
                val checkedBgIds = backing.getStringSet(KEY_HABIT_CHECKED_BG_IDS, emptySet()) ?: emptySet()
                val optimisticallyChecked = frame.fresh &&
                    habitQuickCheckId.isNotBlank() &&
                    habitQuickCheckId in checkedBgIds
                val habitQuickCheckLabel = if (optimisticallyChecked) {
                    if (isZh) "✓ 已记录打卡" else "✓ Checked in"
                } else {
                    DuoyiWidgetCopy.habitQuickCheckLabel(
                        prefs.getString("habit_quick_check_label", null),
                        isZh
                    )
                }
                views.setTextViewText(R.id.widget_habit_hint, habitQuickCheckLabel)
                views.setContentDescription(R.id.widget_habit_hint, habitQuickCheckLabel)
                views.setTextViewText(
                    R.id.widget_habit_recovery,
                    DuoyiWidgetCopy.habitRecoveryText(isZh)
                )
                views.setViewVisibility(R.id.widget_habit_recovery, android.view.View.GONE)
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
                views.setViewVisibility(
                    R.id.widget_habit_body,
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
                    val checkinUri = DuoyiWidgetSnapshot.actionUri(
                        frame,
                        Uri.parse("duoyi://action/checkin_habit?id=${Uri.encode(habitQuickCheckId)}"),
                    )
                    try {
                        val bgIntent = Intent(context, DuoyiHabitWidgetProvider::class.java).apply {
                            action = ACTION_CHECKIN_HABIT_BG
                            data = checkinUri
                            putExtra(EXTRA_HABIT_ID, habitQuickCheckId)
                        }
                        var flags = PendingIntent.FLAG_UPDATE_CURRENT
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            flags = flags or PendingIntent.FLAG_IMMUTABLE
                        }
                        PendingIntent.getBroadcast(context, 13001, bgIntent, flags)
                    } catch (_: Throwable) {
                        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, checkinUri)
                    }
                } else {
                    openHabit
                }

                views.setOnClickPendingIntent(R.id.widget_habit_root, openHabit)
                views.setOnClickPendingIntent(R.id.widget_habit_recovery, openHabit)
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

    private fun handleBackgroundCheckin(context: Context, intent: Intent) {
        val habitId = intent.getStringExtra(EXTRA_HABIT_ID)?.trim().orEmpty()
        val actionUriStr = intent.dataString?.takeIf { it.isNotBlank() }
            ?: if (habitId.isNotBlank()) "duoyi://action/checkin_habit?id=${Uri.encode(habitId)}" else ""
        if (habitId.isBlank() || actionUriStr.isBlank()) return
        val backing = HomeWidgetPlugin.getData(context)
        val updatedQueue = DuoyiWidgetContent.appendPendingBgAction(
            backing.getString(KEY_PENDING_BG_ACTIONS, null),
            actionUriStr,
        )
        val checkedIds = LinkedHashSet(
            backing.getStringSet(KEY_HABIT_CHECKED_BG_IDS, emptySet()) ?: emptySet(),
        )
        checkedIds.add(habitId)
        backing.edit()
            .putString(KEY_PENDING_BG_ACTIONS, updatedQueue)
            .putStringSet(KEY_HABIT_CHECKED_BG_IDS, checkedIds)
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

    companion object {
        const val ACTION_CHECKIN_HABIT_BG = "com.duoyi.duoyi.action.CHECKIN_HABIT_BG"
        const val EXTRA_HABIT_ID = "habit_id"
        private const val KEY_PENDING_BG_ACTIONS = "duoyi_widget_pending_bg_actions"
        private const val KEY_HABIT_CHECKED_BG_IDS = "habit_checked_bg_ids"

        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "habit")
        }
    }
}
