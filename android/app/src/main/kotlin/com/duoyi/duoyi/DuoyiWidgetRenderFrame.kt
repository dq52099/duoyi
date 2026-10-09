package com.duoyi.duoyi

import android.content.SharedPreferences
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class DuoyiWidgetRenderFrame(val core: DuoyiWidgetFrameCore) {
    val prefs: SharedPreferences = DuoyiFrozenWidgetPreferences(displayValues(core))
    val fresh: Boolean get() = core.fresh
    val sessionTrusted: Boolean get() = core.sessionTrusted
    val wallMillis: Long get() = core.clock.wallMillis
    val elapsedMillis: Long get() = core.clock.elapsedMillis
    val appLocale: Locale = if (core.language == "en") Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE

    fun calendar(): Calendar = Calendar.getInstance(TimeZone.getTimeZone(core.clock.zone), appLocale)
        .apply { timeInMillis = wallMillis }

    fun formatTime(pattern: String, instantMillis: Long = wallMillis): String =
        SimpleDateFormat(pattern, appLocale).apply {
            timeZone = TimeZone.getTimeZone(core.clock.zone)
        }.format(Date(instantMillis))

    companion object {
        private val counters = setOf("todo_count", "todo_top3_count", "habit_percent",
            "habit_active_count", "pomodoro_today", "focus_minutes_today")
        private val entityId = Regex("(?:todo_top3_\\d+|(?:goal|schedule|course|note|diary|anniversary|memorial)_highlight_\\d+)_id")
        private val dailyTextKeys = buildSet {
            addAll(listOf("habit_summary", "streak_summary", "habit_quick_check_label",
                "focus_summary", "today_event_summary", "calendar_month_summary"))
            for (prefix in listOf("todo_top3", "goal_highlight", "schedule_highlight",
                "course_highlight", "note_highlight", "diary_highlight",
                "anniversary_highlight", "memorial_highlight")) {
                for (slot in 1..3) add("${prefix}_$slot")
            }
        }

        internal fun displayValues(core: DuoyiWidgetFrameCore): Map<String, *> {
            val display = core.rawValues.toMutableMap()
            display["widget_locale"] = core.language
            display["widget_display_mode_${core.widgetId}"] = core.effectiveMode
            if (!core.fresh) {
                val isZh = core.language == "zh"
                dailyTextKeys.forEach { key ->
                    display[key] = DuoyiWidgetCopy.staleMessage(key, isZh)
                        ?: if (key == "calendar_month_summary") {
                            if (isZh) "月历 · 安排日程" else "Month view · Plan your day"
                        } else ""
                }
                core.rawValues.keys.filter { entityId.matches(it) || it == "habit_quick_check_id" }
                    .forEach { display[it] = "" }
                counters.forEach { display[it] = 0 }
            }
            if (!core.sessionTrusted) {
                display.keys.filter { it.startsWith("focus_timer_") }.forEach { display.remove(it) }
                display["next_focus_label"] = if (core.language == "zh") "25 分钟专注" else "25-min focus"
            }
            return display
        }
    }
}

data class DuoyiWidgetBuiltViews(
    val views: RemoteViews,
    val acceptedEffect: (() -> Unit)? = null,
)
