package com.duoyi.duoyi

import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

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

    fun refreshContentDescription(isFresh: Boolean, isZh: Boolean): String {
        return if (isFresh) {
            if (isZh) "刷新小组件" else "Refresh widgets"
        } else {
            if (isZh) "数据待刷新，点按更新" else "Data pending refresh, tap to update"
        }
    }

    private fun navLabel(
        prefs: SharedPreferences,
        key: String,
        isZh: Boolean,
        zh: String,
        en: String,
    ): String {
        // Theme navigation is already localized by Flutter; keep its wording.
        val saved = prefs.getString(key, null)?.trim()
        return saved?.takeIf { it.isNotEmpty() } ?: if (isZh) zh else en
    }

    fun navTodo(prefs: SharedPreferences, isZh: Boolean): String =
        navLabel(prefs, "nav_todo", isZh, "待办", "To-Do")
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

    fun focusSummary(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "今日还未专注" || raw == "No focus sessions today") {
            return if (isZh) "今日还未专注" else "No focus sessions today"
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
    ): String = when {
        !sessionTrusted -> if (isZh) "数据待刷新，打开多仪更新" else "Data pending refresh, open Duoyi to update"
        showEndTime -> {
            val timeStr = SimpleDateFormat("HH:mm", appLocale).format(Date(endsAt))
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
    ): String = when {
        timerRunning -> {
            if (endsAtMillis > 0L) {
                val timeStr = SimpleDateFormat("HH:mm", appLocale).format(Date(endsAtMillis))
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

    fun localizeTimerLabel(label: String, isZh: Boolean): String = when {
        !isZh && (label == "专注倒计时" || label == "倒计时") -> "Focus countdown"
        !isZh && (label == "专注正计时" || label == "正计时") -> "Focus count-up"
        isZh && label == "Focus countdown" -> "专注倒计时"
        isZh && label == "Focus count-up" -> "专注正计时"
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
    fun streakSummary(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank()) return if (isZh) "· 连续记录 0 天" else "· 0-day streak"
        if (!isZh && raw.contains("连续记录")) {
            val n = Regex("\\d+").find(raw)?.value ?: "0"
            return "· $n-day streak"
        }
        if (isZh && raw.contains("-day streak")) {
            val n = Regex("\\d+").find(raw)?.value ?: "0"
            return "· 连续记录 $n 天"
        }
        return raw
    }
    fun habitQuickCheckLabel(raw: String?, isZh: Boolean): String {
        if (raw == "打开习惯刷新" || raw == "Open habits to refresh") {
            return if (isZh) "打开习惯刷新" else "Open habits to refresh"
        }
        if (raw.isNullOrBlank() || raw == "点击进入习惯打卡" || raw == "Tap to check in" ||
            raw == "Tap to check in habits") {
            return if (isZh) "点击进入习惯打卡" else "Tap to check in"
        }
        if (!isZh && raw.startsWith("打卡：")) {
            return "Check-in: " + raw.removePrefix("打卡：")
        }
        if (isZh && raw.startsWith("Check-in: ")) {
            return "打卡：" + raw.removePrefix("Check-in: ")
        }
        return raw
    }

    // Calendar
    fun calendarMonthTitle(now: Calendar, compact: Boolean, isZh: Boolean): String {
        return if (isZh) {
            val pattern = if (compact) "M月" else "yyyy年M月"
            SimpleDateFormat(pattern, Locale.SIMPLIFIED_CHINESE).format(now.time)
        } else {
            val pattern = if (compact) "MMM" else "MMM yyyy"
            SimpleDateFormat(pattern, Locale.ENGLISH).format(now.time)
        }
    }
    fun calendarTodayButton(isZh: Boolean): String = if (isZh) "今天" else "Today"
    fun calendarMonthSummary(raw: String?, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "本月日期 · 今日已标记" || raw == "Monthly view · Today marked") {
            return if (isZh) "本月日期 · 今日已标记" else "Monthly view · Today marked"
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
        if (raw == "今日没有日程" || raw == "No schedule today") {
            return if (isZh) "今日没有日程" else "No schedule today"
        }
        return raw
    }
    fun scheduleHighlight1(raw: String?, todayEvent: String, isZh: Boolean): String {
        if (raw.isNullOrBlank() || raw == "· 今日没有日程" || raw == "今日没有日程" ||
            raw == "· No schedule today" || raw == "No schedule today") {
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
}
