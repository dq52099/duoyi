package com.duoyi.duoyi

import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Shared localization and presentation copy for Android home screen widgets.
 * Matches app locale preference with system locale fallback.
 */
object DuoyiWidgetCopy {
    fun resolveLocale(prefs: SharedPreferences): Locale {
        val rawLocale = prefs.getString("widget_locale", null)?.trim()?.lowercase(Locale.ROOT)
        if (!rawLocale.isNullOrBlank()) {
            val normalized = rawLocale.replace('-', '_')
            val lang = normalized.split('_').firstOrNull()?.trim()
            if (lang == "en") return Locale.ENGLISH
            if (lang == "zh") return Locale.SIMPLIFIED_CHINESE
        }
        val systemLang = Locale.getDefault().language.lowercase(Locale.ROOT)
        val normalizedSystem = systemLang.replace('-', '_').split('_').firstOrNull()?.trim()
        return if (normalizedSystem == "en") Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE
    }

    fun isZh(prefs: SharedPreferences): Boolean = resolveLocale(prefs).language == "zh"

    fun appTitle(prefs: SharedPreferences, isZh: Boolean): String {
        val raw = prefs.getString("brand_app_title", null)?.trim()
        if (raw.isNullOrBlank()) return if (isZh) "多仪" else "Duoyi"
        if (!isZh && raw == "多仪") return "Duoyi"
        if (isZh && raw == "Duoyi") return "多仪"
        return raw
    }

    fun unpublishedMessage(isZh: Boolean): String =
        if (isZh) "打开多仪以更新小组件" else "Open Duoyi to update this widget"

    fun unpublishedMessage(key: String, isZh: Boolean): String? {
        val message = unpublishedMessage(isZh)
        return when (key) {
            "todo_top3_1", "habit_summary", "focus_summary", "today_event_summary",
            "goal_highlight_1", "note_highlight_1", "diary_highlight_1",
            "course_highlight_1", "schedule_highlight_1",
            "anniversary_highlight_1", "memorial_highlight_1" -> message
            "todo_top3_2", "todo_top3_3", "streak_summary",
            "habit_quick_check_label",
            "goal_highlight_2", "goal_highlight_3",
            "note_highlight_2", "note_highlight_3",
            "diary_highlight_2", "diary_highlight_3",
            "course_highlight_2", "course_highlight_3",
            "schedule_highlight_2", "schedule_highlight_3",
            "anniversary_highlight_2", "anniversary_highlight_3",
            "memorial_highlight_2", "memorial_highlight_3" -> ""
            else -> null
        }
    }

    fun staleMessage(key: String, isZh: Boolean): String? {
        return if (isZh) {
            when (key) {
                "todo_top3_1", "habit_summary" -> "数据待刷新，打开多仪更新"
                "todo_top3_2", "todo_top3_3", "streak_summary" -> ""
                "habit_quick_check_label" -> "打开习惯刷新"
                "focus_summary", "today_event_summary" -> "今日数据待刷新"
                "goal_highlight_1", "note_highlight_1", "diary_highlight_1" -> "数据待刷新"
                "goal_highlight_2", "goal_highlight_3",
                "note_highlight_2", "note_highlight_3",
                "diary_highlight_2", "diary_highlight_3" -> ""
                "course_highlight_1" -> "今日课程待刷新"
                "course_highlight_2", "course_highlight_3" -> ""
                "schedule_highlight_1" -> "今日日程待刷新"
                "schedule_highlight_2", "schedule_highlight_3" -> ""
                "anniversary_highlight_1", "memorial_highlight_1" -> "日期数据待刷新"
                "anniversary_highlight_2", "memorial_highlight_2", "memorial_highlight_3" -> ""
                else -> null
            }
        } else {
            when (key) {
                "todo_top3_1", "habit_summary" -> "Data pending refresh, open Duoyi to update"
                "todo_top3_2", "todo_top3_3", "streak_summary" -> ""
                "habit_quick_check_label" -> "Open habits to refresh"
                "focus_summary", "today_event_summary" -> "Today’s data pending refresh"
                "goal_highlight_1", "note_highlight_1", "diary_highlight_1" -> "Data pending refresh"
                "goal_highlight_2", "goal_highlight_3",
                "note_highlight_2", "note_highlight_3",
                "diary_highlight_2", "diary_highlight_3" -> ""
                "course_highlight_1" -> "Today’s timetable pending refresh"
                "course_highlight_2", "course_highlight_3" -> ""
                "schedule_highlight_1" -> "Today’s schedule pending refresh"
                "schedule_highlight_2", "schedule_highlight_3" -> ""
                "anniversary_highlight_1", "memorial_highlight_1" -> "Dates pending refresh"
                "anniversary_highlight_2", "memorial_highlight_2", "memorial_highlight_3" -> ""
                else -> null
            }
        }
    }

    fun refreshContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
    ): String = when {
        publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED -> unpublishedMessage(isZh)
        isFresh -> if (isZh) "刷新小组件" else "Refresh widgets"
        else -> if (isZh) "数据待刷新，点按更新" else "Data pending refresh, tap to update"
    }

    private fun navLabel(
        prefs: SharedPreferences,
        key: String,
        isZh: Boolean,
        zh: String,
        en: String,
    ): String {
        val saved = prefs.getString(key, null)?.trim()
        return localizeGeneratedLabel(saved, isZh, zh, en)
    }

    /**
     * Normalize labels written by the app's built-in locale while preserving
     * user-authored navigation names. This keeps an old payload from leaking
     * Chinese labels into an English widget (or the reverse) after a switch.
     */
    private fun localizeGeneratedLabel(
        saved: String?,
        isZh: Boolean,
        zh: String,
        en: String,
    ): String {
        val value = saved?.trim().orEmpty()
        if (value.isEmpty()) return if (isZh) zh else en
        val generated = value == zh || value == en || (zh == "待办" && value == "To-Do")
        return if (generated) {
            if (isZh) zh else en
        } else {
            value
        }
    }

    fun navTodo(prefs: SharedPreferences, isZh: Boolean): String =
        navLabel(prefs, "nav_todo", isZh, "待办", "Tasks")
    fun navHabit(prefs: SharedPreferences, isZh: Boolean): String =
        navLabel(prefs, "nav_habit", isZh, "习惯", "Habits")
    fun navCalendar(prefs: SharedPreferences, isZh: Boolean): String =
        navLabel(prefs, "nav_calendar", isZh, "日历", "Calendar")
    fun navFocus(prefs: SharedPreferences, isZh: Boolean): String =
        navLabel(prefs, "nav_focus", isZh, "专注", "Focus")
    fun navPomodoro(prefs: SharedPreferences, isZh: Boolean): String =
        navFocus(prefs, isZh)
    fun quickPomodoro(isZh: Boolean): String = if (isZh) "开始番茄" else "Start Focus"
    fun quickOpen(isZh: Boolean): String = if (isZh) "打开 App" else "Open App"

    // Todo
    fun todoQuickAdd(isZh: Boolean): String = if (isZh) "+ 记一笔" else "+ Add"
    fun todoCountUnit(count: Int, isZh: Boolean): String =
        if (isZh) " 项" else if (count == 1) " item" else " items"
    fun todoSummary(count: Int, isZh: Boolean): String =
        if (isZh) "今日待办 · $count 项" else "Today’s tasks · $count ${if (count == 1) "item" else "items"}"
    fun todoDoneContentDescription(title: String, isZh: Boolean): String =
        if (isZh) "完成待办：$title" else "Complete todo: $title"
    fun todoItemContentDescription(title: String, isZh: Boolean): String =
        if (isZh) "查看待办：$title" else "View todo: $title"
    fun defaultTodoEmpty(isZh: Boolean): String =
        if (isZh) "今天没有未完成待办" else "No open tasks today"
    fun cleanTodoTitle(raw: String): String {
        val title = raw.trim().removePrefix("·").trim()
        return title.ifBlank { raw }
    }
    fun todoItemTitle(prefs: SharedPreferences, slot: Int, isZh: Boolean): String {
        val raw = prefs.getString("todo_top3_$slot", null)
        return if (slot == 1 && (raw.isNullOrBlank() || raw == "今天没有未完成待办" || raw == "No open tasks today")) {
            defaultTodoEmpty(isZh)
        } else {
            cleanTodoTitle(raw ?: "")
        }
    }

    // Focus
    fun focusTitle(isZh: Boolean): String = if (isZh) "专注" else "Focus"
    fun focusMetricSessions(isZh: Boolean): String = if (isZh) "次数" else "Sessions"
    fun focusMetricDuration(isZh: Boolean): String = if (isZh) "分钟" else "Min"
    fun focusTimerCaption(
        sessionTrusted: Boolean,
        expired: Boolean,
        paused: Boolean,
        showEndTime: Boolean,
        timerRunning: Boolean,
        countUp: Boolean,
        isZh: Boolean,
    ): String = when {
        !sessionTrusted -> if (isZh) "待刷新" else "Pending"
        expired -> if (isZh) "已结束" else "Ended"
        paused -> if (isZh) "已暂停" else "Paused"
        showEndTime -> if (isZh) "结束时间" else "Ends at"
        timerRunning && countUp -> if (isZh) "正计时" else "Count Up"
        timerRunning -> if (isZh) "倒计时" else "Timer"
        else -> if (isZh) "下一轮" else "Next"
    }

    fun focusSummary(
        raw: String?,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
    ): String {
        if (publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED) {
            return unpublishedMessage(isZh)
        }
        if (raw == unpublishedMessage(true) || raw == unpublishedMessage(false)) {
            return unpublishedMessage(isZh)
        }
        if (raw.isNullOrBlank() || raw == "今日还未专注" || raw == "No focus sessions today" ||
            raw == "No focus today yet") {
            return if (isZh) "今日还未专注" else "No focus today yet"
        }
        return raw
    }

    fun focusTimerSummary(
        sessionTrusted: Boolean,
        showEndTime: Boolean,
        endsAt: Long,
        timerRunning: Boolean,
        timerLabel: String,
        remainingSeconds: Int,
        paused: Boolean,
        storedRemaining: Int,
        expired: Boolean,
        nextFocusLabel: String,
        appLocale: Locale,
        isZh: Boolean,
        timeZone: TimeZone = TimeZone.getDefault(),
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
    ): String = when {
        publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED -> unpublishedMessage(isZh)
        !sessionTrusted -> if (isZh) "数据待刷新，打开多仪更新" else "Data pending refresh, open Duoyi to update"
        showEndTime -> {
            val timeStr = SimpleDateFormat("HH:mm", appLocale).apply { this.timeZone = timeZone }.format(Date(endsAt))
            if (isZh) "预计 $timeStr 结束" else "Est. finish at $timeStr"
        }
        timerRunning -> {
            val formatted = formatTimer(remainingSeconds, appLocale)
            val label = localizeTimerLabel(timerLabel, isZh)
            if (isZh) "$label：$formatted" else "$label: $formatted"
        }
        paused -> {
            val formatted = formatTimer(storedRemaining, appLocale)
            if (isZh) "已暂停：$formatted" else "Paused: $formatted"
        }
        expired -> if (isZh) "计时已结束，打开多仪同步" else "Timer ended, open Duoyi to sync"
        else -> {
            val next = localizeNextFocusLabel(nextFocusLabel, isZh)
            if (isZh) "下一轮：$next" else "Next: $next"
        }
    }

    fun focusTimerHint(
        timerRunning: Boolean,
        endsAtMillis: Long,
        expired: Boolean,
        appLocale: Locale,
        isZh: Boolean,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): String = when {
        timerRunning -> {
            if (endsAtMillis > 0L) {
                val timeStr = SimpleDateFormat("HH:mm", appLocale).apply { this.timeZone = timeZone }.format(Date(endsAtMillis))
                if (isZh) "预计 $timeStr 结束" else "Est. finish at $timeStr"
            } else {
                if (isZh) "正在专注中" else "Focus in progress"
            }
        }
        expired -> if (isZh) "打开应用查看本轮记录" else "Open app to view session summary"
        else -> if (isZh) "结束后提醒休息" else "Rest reminder after session"
    }

    fun focusQuickStartText(
        sessionTrusted: Boolean,
        expired: Boolean,
        paused: Boolean,
        timerRunning: Boolean,
        countUp: Boolean,
        nextFocusLabel: String,
        isZh: Boolean,
    ): String = when {
        !sessionTrusted -> if (isZh) "打开专注刷新" else "Open Focus to refresh"
        expired -> if (isZh) "查看本轮记录" else "View session summary"
        paused -> if (isZh) "继续专注" else "Resume focus"
        timerRunning && countUp -> if (isZh) "查看正计时" else "View count-up"
        timerRunning -> if (isZh) "查看倒计时" else "View countdown"
        else -> {
            val next = localizeNextFocusLabel(nextFocusLabel, isZh)
            if (isZh) "开始$next" else "Start $next"
        }
    }

    fun focusQuickStartShort(canStart: Boolean, paused: Boolean, running: Boolean, isZh: Boolean): String = when {
        canStart && paused -> if (isZh) "继续专注" else "Resume focus"
        canStart -> if (isZh) "开始专注" else "Start focus"
        running -> if (isZh) "查看计时" else "View timer"
        else -> if (isZh) "打开专注" else "Open Focus"
    }

    fun focusControlText(
        sessionTrusted: Boolean,
        expired: Boolean,
        paused: Boolean,
        timerRunning: Boolean,
        countUp: Boolean,
        nextFocusLabel: String,
        isZh: Boolean,
    ): String = when {
        sessionTrusted && !expired && timerRunning -> if (isZh) "暂停专注" else "Pause focus"
        else -> focusQuickStartText(
            sessionTrusted = sessionTrusted,
            expired = expired,
            paused = paused,
            timerRunning = timerRunning,
            countUp = countUp,
            nextFocusLabel = nextFocusLabel,
            isZh = isZh,
        )
    }

    fun focusControlShort(canStart: Boolean, paused: Boolean, running: Boolean, isZh: Boolean): String = when {
        running && !canStart -> if (isZh) "暂停" else "Pause"
        else -> focusQuickStartShort(canStart, paused, running, isZh)
    }

    fun focusFinishLabel(isZh: Boolean): String = if (isZh) "结束" else "Stop"

    fun quickAddNoteDescription(isZh: Boolean): String = if (isZh) "快速记一笔" else "Quick add note"
    fun quickAddDiaryDescription(isZh: Boolean): String = if (isZh) "写今日日记" else "Quick add diary"
    fun quickAddGoalDescription(isZh: Boolean): String = if (isZh) "新建目标" else "Quick add goal"
    fun quickAddScheduleDescription(isZh: Boolean): String = if (isZh) "新建日程" else "Quick add schedule"

    fun focusTimerUnit(isZh: Boolean): String = if (isZh) "分钟" else "min"

    fun localizeTimerLabel(label: String, isZh: Boolean): String = when (label) {
        "专注倒计时", "倒计时", "Focus countdown" -> if (isZh) "专注倒计时" else "Focus countdown"
        "专注正计时", "正计时", "正计时专注中", "Focus count-up", "Focus counting up" ->
            if (isZh) "正计时专注中" else "Focus counting up"
        "短休息倒计时", "Short break countdown" -> if (isZh) "短休息倒计时" else "Short break countdown"
        "长休息倒计时", "Long break countdown" -> if (isZh) "长休息倒计时" else "Long break countdown"
        else -> label
    }

    fun localizeNextFocusLabel(label: String, isZh: Boolean): String {
        if (!isZh && label.contains("分钟")) {
            val digits = Regex("\\d+").find(label)?.value ?: "25"
            return "$digits-min focus"
        }
        if (isZh && label.contains("-min")) {
            val digits = Regex("\\d+").find(label)?.value ?: "25"
            return "$digits 分钟专注"
        }
        return label
    }

    fun formatTimer(totalSeconds: Int, locale: Locale): String {
        val safeSeconds = totalSeconds.coerceAtLeast(0)
        val hours = safeSeconds / 3600
        val minutes = (safeSeconds % 3600) / 60
        val seconds = safeSeconds % 60
        return if (hours > 0) {
            String.format(locale, "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format(locale, "%02d:%02d", minutes, seconds)
        }
    }

    // Habit
    fun habitSubtitle(isZh: Boolean): String = if (isZh) "今日习惯" else "Today’s habits"
    fun habitSummary(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 今日习惯待打卡" || raw == "· Habits pending check-in") {
            return if (isZh) "· 今日习惯待打卡" else "· Habits pending check-in"
        }
        return raw
    }
    private val generatedStreakPatterns = listOf(
        Regex("(?:· )?当前连续 (\\d+) 天"),
        Regex("(?:· )?Current streak: (\\d+) days"),
        Regex("(?:· )?连续记录 (\\d+) 天"),
        Regex("(?:· )?(\\d+)-day streak"),
        Regex("(?:· )?Streak: (\\d+) days"),
    )

    fun streakSummary(raw: String?, isZh: Boolean): String {
        val n = if (raw.isNullOrBlank()) {
            "0"
        } else {
            generatedStreakPatterns.firstNotNullOfOrNull {
                it.matchEntire(raw)?.groupValues?.get(1)
            } ?: return raw
        }
        return if (isZh) "· 当前连续 $n 天" else "· Current streak: $n days"
    }
    fun habitQuickCheckLabel(raw: String?, isZh: Boolean): String {
        if (raw == "") return ""
        if (raw == unpublishedMessage(isZh) || raw == unpublishedMessage(!isZh)) {
            return unpublishedMessage(isZh)
        }
        if (raw == "打开习惯刷新" || raw == "Open habits to refresh") {
            return if (isZh) "打开习惯刷新" else "Open habits to refresh"
        }
        if (raw.isNullOrBlank() || raw == "点击进入习惯打卡" || raw == "Tap to check in" ||
            raw == "Tap to check in habits") {
            return if (isZh) "点击进入习惯打卡" else "Tap to check in"
        }
        val generatedPrefix = listOf("打卡：", "Check in: ", "Check-in: ")
            .firstOrNull { raw.startsWith(it) }
        if (generatedPrefix != null) {
            return (if (isZh) "打卡：" else "Check in: ") + raw.substring(generatedPrefix.length)
        }
        return raw
    }

    // Calendar
    fun calendarMonthTitle(now: Calendar, compact: Boolean, isZh: Boolean): String {
        return if (isZh) {
            val pattern = if (compact) "M月" else "yyyy年M月"
            SimpleDateFormat(pattern, Locale.SIMPLIFIED_CHINESE).apply { timeZone = now.timeZone }.format(now.time)
        } else {
            val pattern = if (compact) "MMM" else "MMM yyyy"
            SimpleDateFormat(pattern, Locale.ENGLISH).apply { timeZone = now.timeZone }.format(now.time)
        }
    }
    fun calendarTodayButton(isZh: Boolean): String = if (isZh) "今天" else "Today"
    fun calendarMonthSummary(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "本月日期 · 今日已标记" || raw == "Monthly view · Today marked" ||
            raw == "Month view · today is marked") {
            return if (isZh) "本月日期 · 今日已标记" else "Month view · today is marked"
        }
        return raw
    }
    fun calendarWeekdayHeader(isZh: Boolean): String =
        if (isZh) "一 二 三 四 五 六 日" else "Mo Tu We Th Fr Sa Su"
    fun calendarEventSummary(raw: String?, isZh: Boolean): String? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim()
        val clean = if (trimmed.startsWith("· ")) trimmed.removePrefix("· ").trim() else trimmed
        if (clean == "今日没有日程" || clean == "No schedule today" || clean == "No events today" ||
            clean == "今天暂无日程" || clean == "今日日程" || clean == "Today's schedule" || clean == "Today’s schedule") {
            return if (isZh) "今日没有日程" else "No events today"
        }
        return raw
    }

    // Schedule
    fun scheduleSubtitle(isZh: Boolean): String = if (isZh) "今日日程" else "Today’s schedule"
    fun todayEventSummary(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "今日日程" || raw == "Today Schedule" ||
            raw == "Today’s schedule" || raw == "Today's schedule") {
            return if (isZh) "今日日程" else "Today’s schedule"
        }
        if (raw == "今日没有日程" || raw == "No schedule today" || raw == "No events today") {
            return if (isZh) "今日没有日程" else "No events today"
        }
        return raw
    }
    fun scheduleHighlight1(raw: String?, todayEvent: String, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 今日没有日程" || raw == "今日没有日程" ||
            raw == "· No schedule today" || raw == "No schedule today" ||
            raw == "· No events today" || raw == "No events today") {
            return "· $todayEvent"
        }
        return raw
    }
    fun scheduleHighlight2(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 打开日历查看完整安排" || raw == "· Open calendar for full schedule") {
            return if (isZh) "· 打开日历查看完整安排" else "· Open calendar for full schedule"
        }
        return raw
    }
    fun scheduleHighlight3(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "提醒会跟随系统时区" || raw == "Reminders follow system timezone") {
            return if (isZh) "提醒会跟随系统时区" else "Reminders follow system timezone"
        }
        return raw
    }

    // Goal
    fun goalSubtitle(isZh: Boolean): String = if (isZh) "目标" else "Goals"
    fun goalHighlight1(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 暂无进行中目标" || raw == "暂无进行中目标" ||
            raw == "· No active goals" || raw == "No active goals") {
            return if (isZh) "· 暂无进行中目标" else "· No active goals"
        }
        return raw
    }
    fun goalHighlight2(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 打开今日查看目标进度" || raw == "· Open Today to view progress") {
            return if (isZh) "· 打开今日查看目标进度" else "· Open Today to view progress"
        }
        return raw
    }
    fun goalHighlight3(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "本周目标保持推进" || raw == "Keep progressing on weekly goals") {
            return if (isZh) "本周目标保持推进" else "Keep progressing on weekly goals"
        }
        return raw
    }

    // Course
    fun courseSubtitle(isZh: Boolean): String = if (isZh) "今日课程" else "Timetable"
    fun courseHighlight1(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 今日暂无课程" || raw == "今日暂无课程" ||
            raw == "· No classes today" || raw == "No classes today") {
            return if (isZh) "· 今日暂无课程" else "· No classes today"
        }
        return raw
    }

    // Note
    fun noteSubtitle(isZh: Boolean): String = if (isZh) "随手记" else "Quick Notes"
    fun noteHighlight1(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 暂无随手记" || raw == "暂无随手记" ||
            raw == "· No notes yet" || raw == "No notes yet") {
            return if (isZh) "· 暂无随手记" else "· No notes yet"
        }
        return raw
    }

    // Anniversary
    fun anniversarySubtitle(isZh: Boolean): String = if (isZh) "纪念日" else "Anniversaries"
    fun anniversaryHighlight1(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 暂无近期纪念日" || raw == "暂无近期纪念日" ||
            raw == "· No upcoming anniversaries" || raw == "No upcoming anniversaries") {
            return if (isZh) "· 暂无近期纪念日" else "· No upcoming anniversaries"
        }
        return raw
    }

    // Diary
    fun diarySubtitle(isZh: Boolean): String = if (isZh) "日记" else "Diary"
    fun diaryHighlight1(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 暂无日记" || raw == "暂无日记" ||
            raw == "· No diary entries yet" || raw == "No diary entries yet") {
            return if (isZh) "· 暂无日记" else "· No diary entries yet"
        }
        return raw
    }

    // Recovery / No-fit
    fun todoRecoveryText(isZh: Boolean): String =
        if (isZh) "打开待办查看完整内容" else "Open Tasks to view all content"

    fun habitRecoveryText(isZh: Boolean): String =
        if (isZh) "打开习惯查看完整内容" else "Open Habits to view all content"

    fun goalRecoveryText(isZh: Boolean): String =
        if (isZh) "打开目标查看完整内容" else "Open Goals to view all content"

    fun calendarRecoveryText(isZh: Boolean): String =
        if (isZh) "打开日历查看完整内容" else "Open Calendar to view all content"

    private fun buildNoFitContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State?,
        recoveryVisible: Boolean,
        zhSubject: String,
        enSubjectTitle: String,
        enSubjectNoun: String,
    ): String = when {
        publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开多仪更新并查看${zhSubject}完整内容"
                else "Widget space insufficient, open Duoyi to update and view all $enSubjectNoun"
            } else {
                if (isZh) "空间不足无可见内容，打开多仪更新并查看${zhSubject}"
                else "Widget space insufficient, no visible content, open Duoyi to update and view $enSubjectNoun"
            }
        }
        !isFresh -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，数据待刷新，打开${zhSubject}查看完整内容"
                else "Widget space insufficient, data pending refresh, open $enSubjectTitle to view all content"
            } else {
                if (isZh) "空间不足无可见内容，数据待刷新，打开${zhSubject}"
                else "Widget space insufficient, no visible content, data pending refresh, open $enSubjectTitle"
            }
        }
        else -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开${zhSubject}查看完整内容"
                else "Widget space insufficient, open $enSubjectTitle to view all content"
            } else {
                if (isZh) "空间不足无可见内容，打开${zhSubject}"
                else "Widget space insufficient, no visible content, open $enSubjectTitle"
            }
        }
    }

    fun goalNoFitContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
        recoveryVisible: Boolean = false,
    ): String = buildNoFitContentDescription(
        isFresh = isFresh,
        isZh = isZh,
        publicationState = publicationState,
        recoveryVisible = recoveryVisible,
        zhSubject = "目标",
        enSubjectTitle = "Goals",
        enSubjectNoun = "goals",
    )

    fun calendarNoFitContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
        recoveryVisible: Boolean = false,
    ): String = buildNoFitContentDescription(
        isFresh = isFresh,
        isZh = isZh,
        publicationState = publicationState,
        recoveryVisible = recoveryVisible,
        zhSubject = "日历",
        enSubjectTitle = "Calendar",
        enSubjectNoun = "calendar",
    )

    fun todoNoFitContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
        recoveryVisible: Boolean = false,
    ): String = when {
        publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开多仪更新并查看待办完整内容"
                else "Widget space insufficient, open Duoyi to update and view all tasks"
            } else {
                if (isZh) "空间不足无可见内容，打开多仪更新并查看待办"
                else "Widget space insufficient, no visible content, open Duoyi to update and view tasks"
            }
        }
        !isFresh -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，数据待刷新，打开待办查看完整内容"
                else "Widget space insufficient, data pending refresh, open Tasks to view all content"
            } else {
                if (isZh) "空间不足无可见内容，数据待刷新，打开待办"
                else "Widget space insufficient, no visible content, data pending refresh, open Tasks"
            }
        }
        else -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开待办查看完整内容"
                else "Widget space insufficient, open Tasks to view all content"
            } else {
                if (isZh) "空间不足无可见内容，打开待办"
                else "Widget space insufficient, no visible content, open Tasks"
            }
        }
    }

    fun habitNoFitContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
        recoveryVisible: Boolean = false,
    ): String = when {
        publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开多仪更新并查看习惯完整内容"
                else "Widget space insufficient, open Duoyi to update and view all habits"
            } else {
                if (isZh) "空间不足无可见内容，打开多仪更新并查看习惯"
                else "Widget space insufficient, no visible content, open Duoyi to update and view habits"
            }
        }
        !isFresh -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，数据待刷新，打开习惯查看完整内容"
                else "Widget space insufficient, data pending refresh, open Habits to view all content"
            } else {
                if (isZh) "空间不足无可见内容，数据待刷新，打开习惯"
                else "Widget space insufficient, no visible content, data pending refresh, open Habits"
            }
        }
        else -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开习惯查看完整内容"
                else "Widget space insufficient, open Habits to view all content"
            } else {
                if (isZh) "空间不足无可见内容，打开习惯"
                else "Widget space insufficient, no visible content, open Habits"
            }
        }
    }
}
