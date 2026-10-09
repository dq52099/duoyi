package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.util.Locale
import java.util.TimeZone

/** Read-only rendering view; never replaces the saved account data or style. */
object DuoyiWidgetSnapshot {
    private fun clock(): DuoyiWidgetFrameClock = DuoyiWidgetFrameClock(
        System.currentTimeMillis(), android.os.SystemClock.elapsedRealtime(),
        TimeZone.getDefault().toZoneId(),
    )

    private fun options(manager: AppWidgetManager, id: Int): DuoyiWidgetFrameOptions {
        val value = manager.getAppWidgetOptions(id)
        return DuoyiWidgetFrameOptions(
            value.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
            value.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0),
            value.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0),
            value.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0),
            value.getString("duoyi_widget_style"),
        )
    }

    private fun capture(manager: AppWidgetManager, backing: SharedPreferences, id: Int): DuoyiWidgetRenderFrame {
        val raw = backing.all
        return DuoyiWidgetRenderFrame(DuoyiWidgetFrameCore(
            raw, clock(), options(manager, id), id, Locale.getDefault().toLanguageTag(),
        ))
    }

    /** Keep validation and commit in the same main-looper segment as native writers. */
    fun renderWidget(
        context: Context,
        manager: AppWidgetManager,
        backing: SharedPreferences,
        id: Int,
        initialStyle: String?,
        build: (DuoyiWidgetRenderFrame) -> DuoyiWidgetBuiltViews,
    ): Boolean {
        if (android.os.Looper.myLooper() != android.os.Looper.getMainLooper()) {
            android.util.Log.w("DuoyiWidgetFrame", "render_skipped widgetId=$id reason=thread")
            return false
        }
        try {
            DuoyiWidgetDisplayMode.saveForWidgetIfMissing(backing, id, initialStyle)
            return DuoyiWidgetFrameAttempts.run(
                capture = { capture(manager, backing, id) },
                build = { frame -> build(frame).also { finishRender(it.views, frame) } },
                rejectionReason = { frame ->
                    frame.core.rejectionReason(backing.all, clock(), options(manager, id),
                        Locale.getDefault().toLanguageTag())
                },
                commit = { built -> manager.updateAppWidget(id, built.views) },
                acceptedEffect = { _, built ->
                    try { built.acceptedEffect?.invoke() } catch (_: RuntimeException) {
                        android.util.Log.w("DuoyiWidgetFrame", "effect_failed widgetId=$id")
                    }
                },
                rejected = { reason -> android.util.Log.i("DuoyiWidgetFrame", "render_rejected widgetId=$id reason=$reason") },
            )
        } catch (_: RuntimeException) {
            // A failed build/Binder call never runs an effect or blocks the next id.
            android.util.Log.w("DuoyiWidgetFrame", "render_failed widgetId=$id")
            return false
        }
    }

    fun actionUri(frame: DuoyiWidgetRenderFrame, action: Uri): Uri {
        require(frame.fresh) { "Widget action requires a fresh published session" }
        return action.buildUpon()
            .appendQueryParameter("source", "widget")
            .appendQueryParameter("widget_day", frame.core.day)
            .appendQueryParameter("widget_offset", frame.core.offset.toString())
            .appendQueryParameter("widget_account", frame.core.nonce)
            .build()
    }

    private fun finishRender(views: RemoteViews, frame: DuoyiWidgetRenderFrame) {
        val prefs = frame.prefs
        val width = frame.core.options.minWidth
        val height = frame.core.options.minHeight
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
        // Empty secondary rows should not reserve space or look like real data.
        // Only hide here: the provider's density choice remains the upper limit.
        val optionalRows = when (views.layoutId) {
            R.layout.duoyi_schedule_widget -> listOf(
                R.id.widget_schedule_2 to "schedule_highlight_2",
                R.id.widget_schedule_3 to "schedule_highlight_3")
            R.layout.duoyi_goal_widget -> listOf(
                R.id.widget_goal_2 to "goal_highlight_2",
                R.id.widget_goal_3 to "goal_highlight_3")
            R.layout.duoyi_course_widget -> listOf(
                R.id.widget_course_2 to "course_highlight_2",
                R.id.widget_course_3 to "course_highlight_3")
            R.layout.duoyi_note_widget -> listOf(
                R.id.widget_note_2 to "note_highlight_2",
                R.id.widget_note_3 to "note_highlight_3")
            R.layout.duoyi_diary_widget -> listOf(
                R.id.widget_diary_2 to "diary_highlight_2",
                R.id.widget_diary_3 to "diary_highlight_3")
            else -> emptyList()
        }
        optionalRows.forEach { (viewId, key) ->
            val value = prefs.getString(key, null)
            if (value.isNullOrBlank()) {
                views.setViewVisibility(viewId, View.GONE)
            }
        }
        val isZh = DuoyiWidgetCopy.isZh(prefs)
        views.setContentDescription(R.id.widget_refresh,
            DuoyiWidgetCopy.refreshContentDescription(frame.fresh, isZh))
        if (frame.fresh) return
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

}
