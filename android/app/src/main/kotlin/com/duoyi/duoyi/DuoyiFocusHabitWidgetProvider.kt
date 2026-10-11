package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.app.AlarmManager
import android.os.Build
import android.view.View
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/** "专注" 小组件。类名保留用于兼容已安装的旧小组件。 */
open class DuoyiFocusHabitWidgetProvider : DuoyiStyledWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == timerFinishedAction ||
            intent.action == timerCapAction) {
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
                        R.id.widget_focus_count_label,
                        R.id.widget_focus_minutes_label,
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
                val isZh = DuoyiWidgetCopy.isZh(prefs)
                val appLocale = DuoyiWidgetCopy.resolveLocale(prefs)
                val today = frame.formatTime("MM/dd")

                views.setTextViewText(
                    R.id.widget_focus_habit_title,
                    DuoyiWidgetCopy.focusTitle(isZh)
                )
                views.setTextViewText(R.id.widget_focus_habit_date, today)
                views.setTextViewText(
                    R.id.widget_focus_count_label,
                    DuoyiWidgetCopy.focusMetricSessions(isZh)
                )
                views.setTextViewText(
                    R.id.widget_focus_minutes_label,
                    DuoyiWidgetCopy.focusMetricDuration(isZh)
                )
                val pomodoroToday = prefs.getInt("pomodoro_today", 0)
                val focusMinutesToday = prefs.getInt("focus_minutes_today", pomodoroToday * 25)
                val nextFocusLabel = prefs.getString("next_focus_label", if (isZh) "25 分钟专注" else "25-min focus")
                    ?: if (isZh) "25 分钟专注" else "25-min focus"
                val sessionTrusted = frame.sessionTrusted
                val countUp = getBooleanCompat(prefs, "focus_timer_count_up")
                val storedRunning = getBooleanCompat(prefs, "focus_timer_running")
                val endsAt = getLongCompat(prefs, "focus_timer_ends_at_millis")
                val startedAt = getLongCompat(prefs, "focus_timer_started_at_millis")
                val now = frame.wallMillis
                val expired = storedRunning && !countUp && endsAt > 0L && endsAt <= now
                val timerRunning = storedRunning && !expired &&
                    (if (countUp) startedAt > 0L else endsAt > 0L)
                val storedRemaining = getIntCompat(prefs, "focus_timer_remaining_seconds")
                val totalSeconds = getIntCompat(prefs, "focus_timer_total_seconds")
                val paused = sessionTrusted && !storedRunning && storedRemaining > 0 &&
                    (countUp || storedRemaining != totalSeconds)
                val exactFinish = canScheduleExactTimerFinish(context)
                val showEndTime = timerRunning && !countUp && !exactFinish && endsAt > 0L
                val isAtOrPastCap = countUp && DuoyiWidgetCountUpCapCore.isAtOrPastCap(startedAt, now)
                val timerRemainingSeconds = if (countUp) {
                    if (timerRunning && startedAt > 0L) {
                        DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt, now)
                    } else {
                        DuoyiWidgetCountUpCapCore.clampPausedSeconds(storedRemaining)
                    }
                } else currentTimerRemainingSeconds(prefs, timerRunning, now)
                val timerLabel = DuoyiWidgetCopy.localizeTimerLabel(
                    prefs.getString("focus_timer_label", if (isZh) "专注倒计时" else "Focus countdown")
                        ?: if (isZh) "专注倒计时" else "Focus countdown",
                    isZh
                )
                val timerText = if (!sessionTrusted) "—" else if (showEndTime) {
                    frame.formatTime("HH:mm", endsAt)
                } else if (timerRunning || paused) {
                    DuoyiWidgetCopy.formatTimer(timerRemainingSeconds, appLocale)
                } else if (expired) "00:00" else {
                    extractFirstNumber(nextFocusLabel)
                }
                val timerCaption = DuoyiWidgetCopy.focusTimerCaption(
                    sessionTrusted = sessionTrusted,
                    expired = expired,
                    paused = paused,
                    showEndTime = showEndTime,
                    timerRunning = timerRunning,
                    countUp = countUp,
                    isZh = isZh
                )
                val timerSummary = DuoyiWidgetCopy.focusTimerSummary(
                    sessionTrusted = sessionTrusted,
                    showEndTime = showEndTime,
                    endsAt = endsAt,
                    timerRunning = timerRunning,
                    timerLabel = timerLabel,
                    remainingSeconds = timerRemainingSeconds,
                    paused = paused,
                    storedRemaining = if (countUp) DuoyiWidgetCountUpCapCore.clampPausedSeconds(storedRemaining) else storedRemaining,
                    expired = expired,
                    nextFocusLabel = nextFocusLabel,
                    appLocale = appLocale,
                    isZh = isZh,
                    timeZone = java.util.TimeZone.getTimeZone(frame.core.clock.zone),
                    publicationState = frame.core.publicationState,
                )
                val timerHint = DuoyiWidgetCopy.focusTimerHint(
                    timerRunning = timerRunning,
                    endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis"),
                    expired = expired,
                    appLocale = appLocale,
                    isZh = isZh,
                    timeZone = java.util.TimeZone.getTimeZone(frame.core.clock.zone)
                )
                val quickStartText = DuoyiWidgetCopy.focusQuickStartText(
                    sessionTrusted = sessionTrusted,
                    expired = expired,
                    paused = paused,
                    timerRunning = timerRunning,
                    countUp = countUp,
                    nextFocusLabel = nextFocusLabel,
                    isZh = isZh
                )
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
                val liveSupported = if (countUp) DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt, now)
                    else Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                val live = sessionTrusted && timerRunning && liveSupported && !showEndTime
                views.setViewVisibility(R.id.widget_focus_live_timer, if (live) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_focus_streak_count, if (live) View.GONE else View.VISIBLE)
                views.setTextColor(R.id.widget_focus_live_timer, DuoyiWidgetTheme.read(prefs).primary)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    views.setChronometerCountDown(R.id.widget_focus_live_timer, !countUp)
                }
                val base = frame.elapsedMillis + if (countUp) -(now - startedAt).coerceAtLeast(0L)
                    else (endsAt - now).coerceAtLeast(0L)
                views.setChronometer(R.id.widget_focus_live_timer, base, null, live)
                // The accepted commit alone may update 14101; invalidated frames preserve it.
                val timerAlarmEffect: (() -> Unit)? = if (sessionTrusted) {
                    {
                        val store = DuoyiWidgetPublicationStore.forContext(context)
                        val read = store.read(nonBlocking = true)
                        val envelope = read.envelope
                        if (envelope != null) {
                            val doc = envelope.document
                            val canonicalValues = doc.values
                            val canonicalRunning = canonicalValues["focus_timer_running"] == true
                            val canonicalCountUp = canonicalValues["focus_timer_count_up"] == true
                            val canonicalStartedAt = (canonicalValues["focus_timer_started_at_millis"] as? Number)?.toLong() ?: 0L
                            val canonicalEndsAt = (canonicalValues["focus_timer_ends_at_millis"] as? Number)?.toLong() ?: 0L
                            val matches = DuoyiWidgetCountUpCapCore.isCanonicalMatch(
                                canonicalStateWire = doc.state.wire,
                                canonicalNonce = doc.ownerEpoch,
                                canonicalRunning = canonicalRunning,
                                canonicalCountUp = canonicalCountUp,
                                canonicalStartedAt = canonicalStartedAt,
                                canonicalEndsAt = canonicalEndsAt,
                                frameNonce = frame.core.nonce,
                                frameRunning = storedRunning,
                                frameCountUp = countUp,
                                frameStartedAt = startedAt,
                                frameEndsAt = endsAt,
                            )
                            if (matches) {
                                store.acceptSnapshot(envelope) {
                                    scheduleTimerFinish(context, if (timerRunning && !countUp) endsAt else 0L)
                                    val effectNow = System.currentTimeMillis()
                                    val decision = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
                                        sessionTrusted = sessionTrusted,
                                        storedRunning = timerRunning,
                                        countUp = countUp,
                                        startedAt = startedAt,
                                        capturedAtCap = isAtOrPastCap,
                                        effectNowMillis = effectNow,
                                    )
                                    if (decision.scheduleCapMillis != null) {
                                        scheduleCountUpCap(context, decision.scheduleCapMillis)
                                    } else if (decision.cancelAlarm) {
                                        scheduleCountUpCap(context, 0L)
                                    }
                                    if (decision.needsRefresh) {
                                        requestUpdate(context)
                                    }
                                    true
                                }
                            }
                        }
                    }
                } else null
                val timerOnly = DuoyiWidgetDisplayMode.isCompact(prefs, id) || timerRunning || paused || expired
                views.setViewVisibility(R.id.widget_focus_count_column, if (timerOnly) View.GONE else View.VISIBLE)
                views.setViewVisibility(R.id.widget_focus_minutes_column, if (timerOnly) View.GONE else View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_focus_timer_caption,
                    timerCaption
                )
                views.setTextViewText(
                    R.id.widget_focus_summary,
                    DuoyiWidgetCopy.focusSummary(prefs.getString("focus_summary", null), isZh)
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

                val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
                val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
                val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
                val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
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
                val startFocus: PendingIntent = if (frame.fresh && !storedRunning) HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    DuoyiWidgetSnapshot.actionUri(frame, Uri.parse("duoyi://action/start_pomodoro"))
                ) else openFocus

                views.setOnClickPendingIntent(R.id.widget_focus_habit_root, openFocus)
                views.setOnClickPendingIntent(R.id.widget_focus_habit_title, openFocus)
                views.setOnClickPendingIntent(R.id.widget_focus_habit_date, openFocus)
                views.setOnClickPendingIntent(R.id.widget_focus_count, openFocus)
                views.setOnClickPendingIntent(R.id.widget_focus_summary, openFocus)
                views.setOnClickPendingIntent(R.id.widget_focus_quick_start, startFocus)
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

                DuoyiWidgetBuiltViews(views, timerAlarmEffect)
            }
        }
    }

    private fun extractFirstNumber(text: String): String {
        return Regex("\\d+").find(text)?.value ?: "0"
    }

    private fun currentTimerRemainingSeconds(prefs: SharedPreferences, running: Boolean, now: Long): Int {
        val storedRemaining = getIntCompat(prefs, "focus_timer_remaining_seconds")
        if (!running) return storedRemaining
        val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
        if (endsAtMillis <= 0L) return storedRemaining
        val secondsUntilEnd = ((endsAtMillis - now) / 1000L).coerceAtLeast(0L)
        return secondsUntilEnd.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
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
        private const val timerCapAction = "com.duoyi.duoyi.WIDGET_FOCUS_COUNT_UP_CAP"
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
        private fun scheduleCountUpCap(context: Context, capMillis: Long) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, DuoyiFocusHabitWidgetProvider::class.java).setAction(timerCapAction)
            val pending = PendingIntent.getBroadcast(context, 14103, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            if (capMillis <= 0L) { manager.cancel(pending); return }
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()) {
                    manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, capMillis, pending)
                } else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, capMillis, pending)
            } catch (_: SecurityException) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, capMillis, pending)
            }
        }

        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "focus")
        }
    }
}
