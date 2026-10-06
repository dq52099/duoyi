package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.app.AlarmManager
import android.os.Build
import android.os.SystemClock
import android.view.View
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

/** "专注" 小组件。类名保留用于兼容已安装的旧小组件。 */
open class DuoyiFocusHabitWidgetProvider : DuoyiStyledWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED || intent.action == timerFinishedAction) {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_focus_habit_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_focus_habit_root,
                navId = R.id.widget_focus_habit_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_focus_habit_title,
                    R.id.widget_focus_count,
                    R.id.widget_focus_habit_progress,
                    R.id.widget_focus_streak_count,
                    R.id.widget_focus_nav_focus,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_focus_summary,
                    R.id.widget_focus_habit_summary,
                    R.id.widget_focus_streak_summary,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_focus_habit_date,
                    R.id.widget_focus_timer_caption,
                    R.id.widget_focus_nav_todo,
                    R.id.widget_focus_nav_habit,
                    R.id.widget_focus_nav_calendar,
                ),
                onPrimaryIds = intArrayOf(R.id.widget_focus_quick_start),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_focus_quick_start),
            )
            val today = SimpleDateFormat("MM/dd", Locale.getDefault()).format(Date())

            views.setTextViewText(
                R.id.widget_focus_habit_title,
                "专注"
            )
            views.setTextViewText(R.id.widget_focus_habit_date, today)
            val pomodoroToday = prefs.getInt("pomodoro_today", 0)
            val focusMinutesToday = prefs.getInt("focus_minutes_today", pomodoroToday * 25)
            val nextFocusLabel = prefs.getString("next_focus_label", "25 分钟专注") ?: "25 分钟专注"
            val sessionTrusted = DuoyiWidgetSnapshot.hasPublishedSession(prefs)
            val countUp = getBooleanCompat(prefs, "focus_timer_count_up")
            val storedRunning = getBooleanCompat(prefs, "focus_timer_running")
            val endsAt = getLongCompat(prefs, "focus_timer_ends_at_millis")
            val startedAt = getLongCompat(prefs, "focus_timer_started_at_millis")
            val now = System.currentTimeMillis()
            val expired = storedRunning && !countUp && endsAt > 0L && endsAt <= now
            val timerRunning = storedRunning && !expired
            val storedRemaining = getIntCompat(prefs, "focus_timer_remaining_seconds")
            val totalSeconds = getIntCompat(prefs, "focus_timer_total_seconds")
            val paused = sessionTrusted && !storedRunning && storedRemaining > 0 &&
                (countUp || storedRemaining != totalSeconds)
            val exactFinish = canScheduleExactTimerFinish(context)
            val showEndTime = timerRunning && !countUp && !exactFinish && endsAt > 0L
            val timerRemainingSeconds = if (countUp && timerRunning && startedAt > 0L) {
                ((now - startedAt).coerceAtLeast(0L) / 1000L).toInt()
            } else currentTimerRemainingSeconds(prefs, timerRunning)
            val timerLabel = prefs.getString("focus_timer_label", "专注倒计时") ?: "专注倒计时"
            val timerText = if (!sessionTrusted) "—" else if (showEndTime) {
                SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(endsAt))
            } else if (timerRunning || paused) {
                formatTimer(timerRemainingSeconds)
            } else if (expired) "00:00" else {
                extractFirstNumber(nextFocusLabel)
            }
            val timerCaption = when {
                !sessionTrusted -> "待刷新"
                expired -> "已结束"
                paused -> "已暂停"
                showEndTime -> "结束时间"
                timerRunning && countUp -> "正计时"
                timerRunning -> "倒计时"
                else -> "下一轮"
            }
            val timerSummary = if (!sessionTrusted) {
                "数据待刷新，打开多仪更新"
            } else if (showEndTime) {
                "预计 ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(endsAt))} 结束"
            } else if (timerRunning) {
                "$timerLabel：${formatTimer(timerRemainingSeconds)}"
            } else if (paused) {
                "已暂停：${formatTimer(storedRemaining)}"
            } else if (expired) {
                "计时已结束，打开多仪同步"
            } else {
                "下一轮：$nextFocusLabel"
            }
            val timerHint = if (timerRunning) {
                val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
                if (endsAtMillis > 0L) {
                    "预计 ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(endsAtMillis))} 结束"
                } else {
                    "正在专注中"
                }
            } else if (expired) {
                "打开应用查看本轮记录"
            } else {
                "结束后提醒休息"
            }
            val quickStartText = when {
                !sessionTrusted -> "打开专注刷新"
                expired -> "查看本轮记录"
                paused -> "继续专注"
                timerRunning && countUp -> "查看正计时"
                timerRunning -> "查看倒计时"
                else -> "开始$nextFocusLabel"
            }
            views.setTextViewText(
                R.id.widget_focus_count,
                pomodoroToday.toString()
            )
            views.setTextViewText(
                R.id.widget_focus_habit_progress,
                focusMinutesToday.toString()
            )
            views.setTextViewText(
                R.id.widget_focus_streak_count,
                timerText
            )
            val liveSupported = countUp || Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
            val live = sessionTrusted && timerRunning && liveSupported && !showEndTime
            views.setViewVisibility(R.id.widget_focus_live_timer, if (live) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_focus_streak_count, if (live) View.GONE else View.VISIBLE)
            views.setTextColor(R.id.widget_focus_live_timer, DuoyiWidgetTheme.read(prefs).primary)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                views.setChronometerCountDown(R.id.widget_focus_live_timer, !countUp)
            }
            val base = SystemClock.elapsedRealtime() + if (countUp) -timerRemainingSeconds * 1000L
                else (endsAt - now).coerceAtLeast(0L)
            views.setChronometer(R.id.widget_focus_live_timer, base, null, live)
            // During an invalidated/partial payload, preserve any existing alarm.
            if (sessionTrusted) scheduleTimerFinish(context, if (timerRunning && !countUp) endsAt else 0L)
            val timerOnly = DuoyiWidgetDisplayMode.isCompact(prefs, id) || timerRunning || paused || expired
            views.setViewVisibility(R.id.widget_focus_count_column, if (timerOnly) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.widget_focus_minutes_column, if (timerOnly) View.GONE else View.VISIBLE)
            views.setTextViewText(
                R.id.widget_focus_timer_caption,
                timerCaption
            )
            views.setTextViewText(
                R.id.widget_focus_summary,
                prefs.getString("focus_summary", "今日还未专注") ?: "今日还未专注"
            )
            views.setTextViewText(
                R.id.widget_focus_habit_summary,
                timerSummary
            )
            views.setTextViewText(
                R.id.widget_focus_streak_summary,
                timerHint
            )
            views.setTextViewText(
                R.id.widget_focus_quick_start,
                quickStartText
            )
            views.setViewVisibility(
                R.id.widget_focus_quick_start,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_focus_habit_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_focus_streak_summary,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_focus_habit_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_focus_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_focus_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_focus_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_focus_nav_focus, tabFocus)

            val openFocus = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
            )
            val openHabit = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
            )
            val openTodo = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
            )
            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            val startFocus: PendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                DuoyiWidgetSnapshot.actionUri(prefs, Uri.parse("duoyi://action/start_pomodoro"))
            )

            views.setOnClickPendingIntent(R.id.widget_focus_habit_root, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_title, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_date, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_count, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_summary, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_quick_start, if (storedRunning || !sessionTrusted) openFocus else startFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_progress, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_streak_count, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_live_timer, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_timer_caption, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_summary, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_streak_summary, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_focus, openFocus)

            DuoyiWidgetSnapshot.finishRender(context, views, prefs, id)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun extractFirstNumber(text: String): String {
        return Regex("\\d+").find(text)?.value ?: "0"
    }

    private fun currentTimerRemainingSeconds(prefs: SharedPreferences, running: Boolean): Int {
        val storedRemaining = getIntCompat(prefs, "focus_timer_remaining_seconds")
        if (!running) return storedRemaining
        val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
        if (endsAtMillis <= 0L) return storedRemaining
        val secondsUntilEnd = ((endsAtMillis - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L)
        return secondsUntilEnd.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    private fun formatTimer(totalSeconds: Int): String {
        val safeSeconds = totalSeconds.coerceAtLeast(0)
        val hours = safeSeconds / 3600
        val minutes = (safeSeconds % 3600) / 60
        val seconds = safeSeconds % 60
        return if (hours > 0) {
            "%d:%02d:%02d".format(Locale.getDefault(), hours, minutes, seconds)
        } else {
            "%02d:%02d".format(Locale.getDefault(), minutes, seconds)
        }
    }

    private fun getBooleanCompat(prefs: SharedPreferences, key: String): Boolean {
        return when (val value = prefs.all[key]) {
            is Boolean -> value
            is String -> value == "true"
            is Number -> value.toInt() != 0
            else -> false
        }
    }

    private fun getIntCompat(prefs: SharedPreferences, key: String): Int {
        return when (val value = prefs.all[key]) {
            is Int -> value
            is Long -> value.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
            is String -> value.toIntOrNull() ?: 0
            else -> 0
        }
    }

    private fun getLongCompat(prefs: SharedPreferences, key: String): Long {
        return when (val value = prefs.all[key]) {
            is Long -> value
            is Int -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    companion object {
        private const val timerFinishedAction = "com.duoyi.duoyi.WIDGET_FOCUS_TIMER_FINISHED"
        private fun canScheduleExactTimerFinish(context: Context): Boolean {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()
        }
        private fun scheduleTimerFinish(context: Context, endsAt: Long) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, DuoyiFocusHabitWidgetProvider::class.java).setAction(timerFinishedAction)
            val pending = PendingIntent.getBroadcast(context, 14101, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            if (endsAt <= System.currentTimeMillis()) { manager.cancel(pending); return }
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()) {
                    manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, pending)
                } else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, pending)
            } catch (_: SecurityException) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, pending)
            }
        }

        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "focus")
        }
    }
}
