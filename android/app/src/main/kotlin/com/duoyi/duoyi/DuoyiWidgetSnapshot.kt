package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Read-only rendering view; never replaces the saved account data or style. */
object DuoyiWidgetSnapshot {
    fun isFresh(prefs: SharedPreferences): Boolean {
        val now = System.currentTimeMillis()
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
        return prefs.getString("widget_snapshot_day", "") == day &&
            prefs.getInt("widget_snapshot_utc_offset_minutes", Int.MIN_VALUE) ==
            TimeZone.getDefault().getOffset(now) / 60_000
    }

    fun forDisplay(context: Context, backing: SharedPreferences): SharedPreferences {
        val fresh = isFresh(backing)
        val sessionTrusted = hasPublishedSession(backing)
        return object : SharedPreferences by backing {
            override fun getAll(): Map<String, *> = if (sessionTrusted) backing.all else
                backing.all.filterKeys { !it.startsWith("focus_timer_") }

            override fun getString(key: String?, defValue: String?): String? {
                if (key?.startsWith("widget_display_mode_") == true) {
                    val id = key.removePrefix("widget_display_mode_").toIntOrNull()
                    if (id != null) return effectiveMode(context, backing, id)
                }
                if (!fresh && key != null) {
                    if (key in staleMessages) return staleMessages[key]
                    if (key.startsWith("todo_top3_") && key.endsWith("_id")) return ""
                    if (key == "habit_quick_check_id" || key.endsWith("_id")) return ""
                    if ((key.startsWith("course_highlight_") ||
                            key.startsWith("schedule_highlight_") ||
                            key.startsWith("anniversary_highlight_") ||
                            key.startsWith("memorial_highlight_")) && key.endsWith("_id")) return ""
                }
                return backing.getString(key, defValue)
            }

            override fun getInt(key: String?, defValue: Int): Int {
                if (!fresh && key in staleCounters) return 0
                return backing.getInt(key, defValue)
            }
        }
    }

    fun hasPublishedSession(prefs: SharedPreferences): Boolean =
        !prefs.getString("widget_snapshot_day", "").isNullOrBlank() &&
            !prefs.getString("widget_account_nonce", "").isNullOrBlank()

    private fun effectiveMode(context: Context, prefs: SharedPreferences, id: Int): String {
        val preferred = prefs.getString("widget_display_mode_$id", null)
            ?: prefs.getString("widget_display_mode", "standard") ?: "standard"
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        if (width <= 0 || height <= 0) return preferred
        // Both dimensions must fit. Preserve the user's chosen upper density.
        if (width < 180 || height < 100 || preferred == "compact") return "compact"
        if (preferred == "detailed" && width >= 250 && height >= 170) return "detailed"
        return "standard"
    }

    fun actionUri(prefs: SharedPreferences, action: Uri): Uri = action.buildUpon()
        .appendQueryParameter("source", "widget")
        .appendQueryParameter("widget_day", prefs.getString("widget_snapshot_day", ""))
        .appendQueryParameter("widget_offset", prefs.getInt("widget_snapshot_utc_offset_minutes", Int.MIN_VALUE).toString())
        .appendQueryParameter("widget_account", prefs.getString("widget_account_nonce", ""))
        .build()

    fun finishRender(context: Context, views: RemoteViews, prefs: SharedPreferences, id: Int) {
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        // Keep navigation out of a two-cell widget while retaining its main action.
        views.setViewVisibility(R.id.widget_refresh, if (width in 1..139) View.GONE else View.VISIBLE)
        if (height in 1..149) {
            val navId = when (views.layoutId) {
                R.layout.duoyi_todo_widget -> R.id.widget_todo_bottom_nav
                R.layout.duoyi_habit_widget -> R.id.widget_habit_bottom_nav
                R.layout.duoyi_focus_habit_widget -> R.id.widget_focus_habit_bottom_nav
                R.layout.duoyi_calendar_widget -> R.id.widget_calendar_bottom_nav
                R.layout.duoyi_schedule_widget -> R.id.widget_schedule_bottom_nav
                R.layout.duoyi_course_widget -> R.id.widget_course_bottom_nav
                R.layout.duoyi_goal_widget -> R.id.widget_goal_bottom_nav
                R.layout.duoyi_anniversary_widget -> R.id.widget_anniversary_bottom_nav
                R.layout.duoyi_note_widget -> R.id.widget_note_bottom_nav
                R.layout.duoyi_diary_widget -> R.id.widget_diary_bottom_nav
                else -> R.id.widget_bottom_nav
            }
            views.setViewVisibility(navId, View.GONE)
        }
        if (views.layoutId == R.layout.duoyi_focus_habit_widget && height in 1..159) {
            intArrayOf(R.id.widget_focus_quick_start, R.id.widget_focus_summary,
                R.id.widget_focus_habit_summary, R.id.widget_focus_streak_summary).forEach {
                views.setViewVisibility(it, View.GONE)
            }
        }
        if (views.layoutId == R.layout.duoyi_habit_widget && height in 1..139) {
            views.setViewVisibility(R.id.widget_habit_streak, View.GONE)
            views.setViewVisibility(R.id.widget_habit_subtitle, View.GONE)
        }
        if (views.layoutId == R.layout.duoyi_todo_widget) {
            if (height in 1..199) views.setViewVisibility(R.id.widget_todo_today_summary, View.GONE)
            if (prefs.getString("todo_top3_2_id", "").isNullOrBlank()) views.setViewVisibility(R.id.widget_todo_row_2, View.GONE)
            if (prefs.getString("todo_top3_3_id", "").isNullOrBlank()) views.setViewVisibility(R.id.widget_todo_row_3, View.GONE)
        }
        views.setContentDescription(R.id.widget_refresh,
            if (isFresh(prefs)) "刷新小组件" else "数据待刷新，点按更新")
        if (isFresh(prefs)) return
        val numericIds = when (views.layoutId) {
            R.layout.duoyi_todo_widget -> intArrayOf(R.id.widget_todo_count)
            R.layout.duoyi_habit_widget -> intArrayOf(R.id.widget_habit_percent)
            R.layout.duoyi_focus_habit_widget -> intArrayOf(
                R.id.widget_focus_count, R.id.widget_focus_habit_progress)
            R.layout.duoyi_widget -> intArrayOf(
                R.id.widget_todo_count, R.id.widget_habit_progress, R.id.widget_pomodoro_count)
            else -> intArrayOf()
        }
        numericIds.forEach { views.setTextViewText(it, "—") }
    }

    private val staleCounters = setOf("todo_count", "todo_top3_count", "habit_percent",
        "pomodoro_today", "focus_minutes_today")
    private val staleMessages = mapOf(
        "todo_top3_1" to "数据待刷新，打开多仪更新",
        "todo_top3_2" to "", "todo_top3_3" to "",
        "habit_summary" to "数据待刷新，打开多仪更新",
        "habit_quick_check_label" to "打开习惯刷新", "streak_summary" to "",
        "focus_summary" to "今日数据待刷新",
        "goal_highlight_1" to "数据待刷新", "goal_highlight_2" to "", "goal_highlight_3" to "",
        "note_highlight_1" to "数据待刷新", "note_highlight_2" to "", "note_highlight_3" to "",
        "diary_highlight_1" to "数据待刷新", "diary_highlight_2" to "", "diary_highlight_3" to "",
        "today_event_summary" to "今日数据待刷新",
        "course_highlight_1" to "今日课程待刷新", "course_highlight_2" to "", "course_highlight_3" to "",
        "schedule_highlight_1" to "今日日程待刷新", "schedule_highlight_2" to "", "schedule_highlight_3" to "",
        "anniversary_highlight_1" to "日期数据待刷新", "anniversary_highlight_2" to "",
        "memorial_highlight_1" to "日期数据待刷新", "memorial_highlight_2" to "", "memorial_highlight_3" to "",
    )
}
