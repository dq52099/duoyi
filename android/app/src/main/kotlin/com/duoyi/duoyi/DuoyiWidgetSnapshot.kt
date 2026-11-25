package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.text.Layout
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.util.Locale
import java.util.TimeZone
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Read-only rendering view; never replaces the saved account data or style. */
object DuoyiWidgetSnapshot {
    private data class TextListViews(
        val keyPrefix: String,
        val contentId: Int,
        val subtitleId: Int,
        val rowIds: List<Int>,
        val navigationId: Int,
        val thirdLineIsSmall: Boolean,
    )

    private val textLists = mapOf(
        R.layout.duoyi_schedule_widget to TextListViews(
            "schedule", R.id.widget_schedule_content, R.id.widget_schedule_subtitle,
            listOf(R.id.widget_schedule_1, R.id.widget_schedule_2, R.id.widget_schedule_3),
            R.id.widget_schedule_bottom_nav, true,
        ),
        R.layout.duoyi_course_widget to TextListViews(
            "course", R.id.widget_course_content, R.id.widget_course_subtitle,
            listOf(R.id.widget_course_1, R.id.widget_course_2, R.id.widget_course_3),
            R.id.widget_course_bottom_nav, true,
        ),
        R.layout.duoyi_goal_widget to TextListViews(
            "goal", R.id.widget_goal_content, R.id.widget_goal_subtitle,
            listOf(R.id.widget_goal_1, R.id.widget_goal_2, R.id.widget_goal_3),
            R.id.widget_goal_bottom_nav, true,
        ),
        R.layout.duoyi_note_widget to TextListViews(
            "note", R.id.widget_note_content, R.id.widget_note_subtitle,
            listOf(R.id.widget_note_1, R.id.widget_note_2, R.id.widget_note_3),
            R.id.widget_note_bottom_nav, false,
        ),
        R.layout.duoyi_diary_widget to TextListViews(
            "diary", R.id.widget_diary_content, R.id.widget_diary_subtitle,
            listOf(R.id.widget_diary_1, R.id.widget_diary_2, R.id.widget_diary_3),
            R.id.widget_diary_bottom_nav, false,
        ),
    )

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

    private fun values(read: DuoyiWidgetPublicationRead, backing: SharedPreferences, id: Int): Map<String, Any?> {
        val raw = LinkedHashMap<String, Any?>()
        read.envelope?.document?.toFlatValues()?.let { raw.putAll(it) }
        // Launcher layout choices are device-owned and may live in preferences.
        raw.putAll(DuoyiWidgetFrameCore.deviceDisplayValues(backing.all, id))
        return raw
    }

    /** Hold the store's read lock across a published frame's final commit. */
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
            val store = DuoyiWidgetPublicationStore.forContext(context)
            return DuoyiWidgetFrameAttempts.run(
                capture = { store.read(nonBlocking = true) },
                canBuild = { read -> read.status != "busy" },
                build = { read ->
                    val frame = DuoyiWidgetRenderFrame(DuoyiWidgetFrameCore(
                        values(read, backing, id), clock(), options(manager, id), id,
                        Locale.getDefault().toLanguageTag(),
                    ))
                    val built = build(frame)
                    finishRender(context, built.views, frame)
                    frame to built
                },
                rejectionReason = { read, (frame, _) ->
                    val latest = store.read(nonBlocking = true)
                    val reason = frame.core.rejectionReason(values(latest, backing, id), clock(),
                        options(manager, id), Locale.getDefault().toLanguageTag())
                    if (reason != null || latest.status != read.status) {
                        reason ?: "store_changed"
                    } else {
                        null
                    }
                },
                commit = { read, (_, built) ->
                    if (read.envelope != null) {
                        store.acceptSnapshot(read.envelope) {
                            manager.updateAppWidget(id, built.views)
                            true
                        }
                    } else {
                        // An absent or unreadable store may only render an empty frame.
                        val finalRead = store.read(nonBlocking = true)
                        if (finalRead.status == read.status && finalRead.envelope == null) {
                            manager.updateAppWidget(id, built.views)
                            true
                        } else false
                    }
                },
                acceptedEffect = { _, (_, built) ->
                    try { built.acceptedEffect?.invoke() } catch (_: RuntimeException) {
                        android.util.Log.w("DuoyiWidgetFrame", "effect_failed widgetId=$id")
                    }
                },
                rejected = { reason ->
                    android.util.Log.i("DuoyiWidgetFrame", "render_rejected widgetId=$id reason=$reason")
                },
            )
        } catch (_: RuntimeException) {
            // A failed build/Binder call never runs an effect or blocks the next id.
            android.util.Log.w("DuoyiWidgetFrame", "render_failed widgetId=$id")
            return false
        }
    }

    fun actionUri(frame: DuoyiWidgetRenderFrame, action: Uri): Uri {
        require(frame.fresh) { "Widget action requires a fresh published session" }
        val bindingKeys = setOf("source", "widget_day", "widget_offset", "widget_account", "widget_delivery")
        val builder = action.buildUpon().clearQuery()
        for (name in action.queryParameterNames) {
            if (name in bindingKeys) continue
            for (value in action.getQueryParameters(name)) builder.appendQueryParameter(name, value)
        }
        return builder
            .appendQueryParameter("source", "widget")
            .appendQueryParameter("widget_day", frame.core.day)
            .appendQueryParameter("widget_offset", frame.core.offset.toString())
            .appendQueryParameter("widget_account", frame.core.nonce)
            .build()
    }

    fun entityUri(frame: DuoyiWidgetRenderFrame, target: Uri, fallback: Uri): Uri {
        val hosts = setOf("todo", "habit", "course", "note", "diary", "goal",
            "anniversary", "countdown", "time-entry", "event", "pomodoro", "calendar", "focus", "tab")
        if (!frame.fresh || target.scheme != "duoyi" || !target.isHierarchical || target.host !in hosts) {
            return fallback
        }
        return runCatching { actionUri(frame, target) }.getOrDefault(fallback)
    }

    private fun finishRender(context: Context, views: RemoteViews, frame: DuoyiWidgetRenderFrame) {
        val prefs = frame.prefs
        val width = frame.core.options.minWidth
        val height = frame.core.options.minHeight
        // Keep navigation out of a two-cell widget while retaining its main action.
        val providerFitsLayout = views.layoutId == R.layout.duoyi_focus_habit_widget ||
            views.layoutId == R.layout.duoyi_calendar_widget ||
            views.layoutId == R.layout.duoyi_anniversary_widget
        if (!providerFitsLayout) {
            views.setViewVisibility(R.id.widget_refresh, if (width in 1..139) View.GONE else View.VISIBLE)
        }
        if (!providerFitsLayout && height in 1..149) {
            val navId = when (views.layoutId) {
                R.layout.duoyi_todo_widget, R.layout.duoyi_todo_widget_reflow -> R.id.widget_todo_bottom_nav
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
        if (views.layoutId == R.layout.duoyi_todo_widget ||
            views.layoutId == R.layout.duoyi_todo_widget_reflow ||
            views.layoutId == R.layout.duoyi_habit_widget || views.layoutId in textLists) {
            fitPrimaryWidget(context, views, frame)
        }
        val isZh = DuoyiWidgetCopy.isZh(prefs)
        views.setContentDescription(R.id.widget_refresh,
            DuoyiWidgetCopy.refreshContentDescription(frame.fresh, isZh, frame.core.publicationState))
        if (frame.fresh) return
        val numericIds = when (views.layoutId) {
            R.layout.duoyi_todo_widget, R.layout.duoyi_todo_widget_reflow -> intArrayOf(R.id.widget_todo_count)
            R.layout.duoyi_habit_widget -> intArrayOf(R.id.widget_habit_percent)
            R.layout.duoyi_focus_habit_widget -> intArrayOf(
                R.id.widget_focus_count, R.id.widget_focus_habit_progress)
            R.layout.duoyi_widget -> intArrayOf(
                R.id.widget_todo_count, R.id.widget_habit_progress, R.id.widget_pomodoro_count)
            else -> intArrayOf()
        }
        numericIds.forEach { views.setTextViewText(it, "—") }
    }

    fun needsTodoReflow(context: Context, frame: DuoyiWidgetRenderFrame): Boolean {
        val prefs = frame.prefs
        val width = frame.core.options.minWidth
        val metrics = context.resources.displayMetrics
        val textMetrics = DuoyiWidgetTextMetrics(metrics)
        val isZh = DuoyiWidgetCopy.isZh(prefs)
        val count = prefs.getInt("todo_top3_count", 0)
        val visibleCount = if (frame.fresh) count.toString() else "—"
        val countWidth = textMetrics.width(visibleCount, 14f)
        val quickAdd = DuoyiWidgetCopy.todoQuickAdd(isZh)
        val quickAddWidth = maxOf(44, textMetrics.width(quickAdd, 11f) + 16)
        val refreshGlyphWidth = textMetrics.width("↻", 14f)
        val refreshWidth = maxOf(36, refreshGlyphWidth)
        val minimalHeaderWidth = countWidth + 6 + quickAddWidth + 4 + refreshWidth
        val padding = 8
        val contentWidth = maxOf(0, (width.takeIf { it > 0 } ?: 180) - padding * 2)
        return contentWidth > 0 && minimalHeaderWidth > contentWidth
    }

    /** Fit real content before optional navigation; all intents remain provider-owned. */
    private fun fitPrimaryWidget(context: Context, views: RemoteViews, frame: DuoyiWidgetRenderFrame) {
        val prefs = frame.prefs
        val width = frame.core.options.minWidth
        val height = frame.core.options.minHeight
        val metrics = context.resources.displayMetrics
        val textMetrics = DuoyiWidgetTextMetrics(metrics)
        fun lineHeight(sp: Float): Int {
            val font = Paint().apply {
                typeface = Typeface.DEFAULT
                textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, metrics)
            }.fontMetricsInt
            // TextView includes top/bottom font padding by default. Options are dp.
            return ceil((font.bottom - font.top).toDouble() / metrics.density).toInt()
        }
        fun textWidth(value: String, sp: Float): Int = textMetrics.width(value, sp)
        fun visibility(shown: Boolean): Int = if (shown) View.VISIBLE else View.GONE
        fun padding(viewId: Int, dp: Int) {
            val px = (dp * metrics.density).roundToInt()
            views.setViewPadding(viewId, px, px, px, px)
        }
        val titleLine = lineHeight(14f)
        val bodyLine = lineHeight(12f)
        val smallLine = lineHeight(11f)
        val isZh = DuoyiWidgetCopy.isZh(prefs)
        val navigationLabels = listOf(
            DuoyiWidgetCopy.navTodo(prefs, isZh), DuoyiWidgetCopy.navHabit(prefs, isZh),
            DuoyiWidgetCopy.navCalendar(prefs, isZh), DuoyiWidgetCopy.navFocus(prefs, isZh),
        )
        // The weighted bar has 4dp padding at each end and four equal columns.
        val navigationCellWidth = ((width.takeIf { it > 0 } ?: 140) - 16 - 8) / 4
        val navigationHeight = maxOf(30, lineHeight(10f))
        val navigationFitsWidth = navigationCellWidth > 2 && navigationLabels.all {
            textMetrics.fitsSingleLine(it, 10f, navigationCellWidth - 2)
        }
        if (views.layoutId == R.layout.duoyi_todo_widget ||
            views.layoutId == R.layout.duoyi_todo_widget_reflow) {
            val count = prefs.getInt("todo_top3_count", 0)
            val visibleCount = if (frame.fresh) count.toString() else "—"
            views.setTextViewText(R.id.widget_todo_count, visibleCount)
            val unit = DuoyiWidgetCopy.todoCountUnit(count, isZh)
            views.setContentDescription(R.id.widget_todo_count, "$visibleCount $unit")
            val quickAdd = DuoyiWidgetCopy.todoQuickAdd(isZh)
            views.setContentDescription(R.id.widget_todo_quick_add, quickAdd)
            views.setTextViewText(R.id.widget_todo_quick_add, quickAdd)

            val padding = 8
            val contentWidth = maxOf(0, (width.takeIf { it > 0 } ?: 180) - padding * 2)
            val isReflow = views.layoutId == R.layout.duoyi_todo_widget_reflow
            val baseHeader = if (width in 1..151) 34 else 36
            val available = DuoyiWidgetLayoutPolicy.heightOrDefault(height, frame.core.effectiveMode)

            val countMeasurement = textMetrics.measureSingleLine(visibleCount, 14f, contentWidth)
            val refreshMeasurement = textMetrics.measureSingleLine("↻", 14f, contentWidth, minWidthDp = 36, minHeightDp = 36)
            val unitMeasurement = textMetrics.measureSingleLine(unit, 11f, contentWidth)
            val titleText = DuoyiWidgetCopy.appTitle(prefs, isZh)

            val headerHeight: Int
            val requiredHeaderFits: Boolean
            val showTitle: Boolean
            val showUnit: Boolean
            val showCount: Boolean
            val showQuickAdd: Boolean

            if (isReflow) {
                val quickAddMeasurement = textMetrics.measureWrappedAction(
                    quickAdd, 11f, contentWidth,
                    minWidthDp = 44, minHeightDp = 34,
                    horizontalPaddingDp = 16, verticalPaddingDp = 0,
                )
                val row2Fits = contentWidth > 0 && quickAddMeasurement.fits
                val row2Height = if (row2Fits) quickAddMeasurement.height else 0

                val requiredRow1Width = countMeasurement.width + 4 + refreshMeasurement.width
                val requiredRow1Height = maxOf(baseHeader, countMeasurement.height, refreshMeasurement.height)
                val requiredRow1Fits = contentWidth > 0 && requiredRow1Width <= contentWidth &&
                    countMeasurement.fits && refreshMeasurement.fits

                val strictlyRequiredHeaderHeight = requiredRow1Height + 4 + row2Height
                val strictlyRequiredFitsInHeight = available >= padding * 2 + strictlyRequiredHeaderHeight + 2
                val strictlyRequiredFits = requiredRow1Fits && row2Fits && strictlyRequiredFitsInHeight

                if (!strictlyRequiredFits) {
                    showTitle = false
                    showUnit = false
                    showCount = false
                    showQuickAdd = false
                    headerHeight = 0
                    requiredHeaderFits = false
                } else {
                    showCount = true
                    showQuickAdd = true

                    val availableUnitWidth = contentWidth - (countMeasurement.width + 2 + 4 + refreshMeasurement.width)
                    val unitFitsWidth = availableUnitWidth > 0 && textMetrics.fitsSingleLine(unit, 11f, availableUnitWidth)
                    val row1HeightWithUnit = maxOf(requiredRow1Height, unitMeasurement.height)
                    val headerHeightWithUnit = row1HeightWithUnit + 4 + row2Height
                    val unitFitsHeight = available >= padding * 2 + headerHeightWithUnit + 2
                    val unitFits = unitFitsWidth && unitFitsHeight

                    val effectiveUnitWidth = if (unitFits) 2 + unitMeasurement.width else 0
                    val effectiveUnitHeight = if (unitFits) unitMeasurement.height else 0
                    val availableTitleWidth = contentWidth - (6 + countMeasurement.width + effectiveUnitWidth + 4 + refreshMeasurement.width)
                    val titleFitsWidth = width !in 1..179 && availableTitleWidth > 0 &&
                        textMetrics.fitsSingleLine(titleText, 14f, availableTitleWidth)
                    val titleMeasurement = if (titleFitsWidth) textMetrics.measureSingleLine(titleText, 14f, availableTitleWidth) else null
                    val row1HeightWithTitle = maxOf(
                        baseHeader,
                        titleMeasurement?.height ?: 0,
                        countMeasurement.height,
                        effectiveUnitHeight,
                        refreshMeasurement.height
                    )
                    val headerHeightWithTitle = row1HeightWithTitle + 4 + row2Height
                    val titleFitsHeight = available >= padding * 2 + headerHeightWithTitle + 2
                    val titleFits = titleFitsWidth && titleMeasurement != null && titleMeasurement.fits && titleFitsHeight

                    showTitle = titleFits
                    showUnit = unitFits
                    headerHeight = if (showTitle) headerHeightWithTitle else (if (showUnit) headerHeightWithUnit else strictlyRequiredHeaderHeight)
                    requiredHeaderFits = true
                }
            } else {
                val quickAddMeasurement = textMetrics.measureSingleLine(
                    quickAdd, 11f, contentWidth,
                    minWidthDp = 44, minHeightDp = 34,
                    horizontalPaddingDp = 16,
                )

                val minimalRequiredWidth = countMeasurement.width + 6 + quickAddMeasurement.width + 4 + refreshMeasurement.width
                val requiredRowHeight = maxOf(baseHeader, countMeasurement.height, quickAddMeasurement.height, refreshMeasurement.height)
                val strictlyRequiredFitsInHeight = available >= padding * 2 + requiredRowHeight + 2
                val strictlyRequiredRowFits = contentWidth > 0 && minimalRequiredWidth <= contentWidth &&
                    countMeasurement.fits && quickAddMeasurement.fits && refreshMeasurement.fits
                val strictlyRequiredFits = strictlyRequiredRowFits && strictlyRequiredFitsInHeight

                if (!strictlyRequiredFits) {
                    showTitle = false
                    showUnit = false
                    showCount = false
                    showQuickAdd = false
                    headerHeight = 0
                    requiredHeaderFits = false
                } else {
                    showCount = true
                    showQuickAdd = true

                    val availableUnitWidth = contentWidth - (countMeasurement.width + 2 + 6 + quickAddMeasurement.width + 4 + refreshMeasurement.width)
                    val unitFitsWidth = availableUnitWidth > 0 && textMetrics.fitsSingleLine(unit, 11f, availableUnitWidth)
                    val rowHeightWithUnit = maxOf(requiredRowHeight, unitMeasurement.height)
                    val unitFitsHeight = available >= padding * 2 + rowHeightWithUnit + 2
                    val unitFits = unitFitsWidth && unitFitsHeight

                    val effectiveUnitWidth = if (unitFits) 2 + unitMeasurement.width else 0
                    val effectiveUnitHeight = if (unitFits) unitMeasurement.height else 0
                    val availableTitleWidth = contentWidth - (6 + countMeasurement.width + effectiveUnitWidth + 6 + quickAddMeasurement.width + 4 + refreshMeasurement.width)
                    val titleFitsWidth = width !in 1..179 && availableTitleWidth > 0 &&
                        textMetrics.fitsSingleLine(titleText, 14f, availableTitleWidth)
                    val titleMeasurement = if (titleFitsWidth) textMetrics.measureSingleLine(titleText, 14f, availableTitleWidth) else null
                    val rowHeightWithTitle = maxOf(
                        baseHeader,
                        titleMeasurement?.height ?: 0,
                        countMeasurement.height,
                        effectiveUnitHeight,
                        quickAddMeasurement.height,
                        refreshMeasurement.height
                    )
                    val titleFitsHeight = available >= padding * 2 + rowHeightWithTitle + 2
                    val titleFits = titleFitsWidth && titleMeasurement != null && titleMeasurement.fits && titleFitsHeight

                    showTitle = titleFits
                    showUnit = unitFits
                    headerHeight = if (showTitle) rowHeightWithTitle else (if (showUnit) rowHeightWithUnit else requiredRowHeight)
                    requiredHeaderFits = true
                }
            }

            val doneFrameWidth = maxOf(38, textMetrics.width("○", 14f))
            val doneFrameHeight = maxOf(38, textMetrics.line(14f, includePadding = true))
            val rowMeasurements = if (requiredHeaderFits) {
                (1..3).map { slot ->
                    val todoId = prefs.getString("todo_top3_${slot}_id", "") ?: ""
                    val hasDone = frame.fresh && todoId.isNotBlank()
                    val effectiveDoneWidth = if (hasDone) doneFrameWidth else 0
                    val usableTextWidth = maxOf(0, contentWidth - effectiveDoneWidth)
                    val itemTitle = DuoyiWidgetCopy.todoItemTitle(prefs, slot, isZh)
                    val measurement = if (usableTextWidth > 0) {
                        textMetrics.measureWrapped(itemTitle, 12f, usableTextWidth)
                    } else {
                        null
                    }
                    val textHeight = measurement?.height ?: bodyLine
                    val naturalFrame = if (hasDone) doneFrameHeight else bodyLine
                    maxOf(38, maxOf(naturalFrame, textHeight)) to (measurement?.fits == true)
                }
            } else {
                emptyList()
            }
            val measuredRowHeights = rowMeasurements.map { it.first }
            val rowFitsWidth = rowMeasurements.map { it.second }

            val summaryText = DuoyiWidgetCopy.todoSummary(prefs.getInt("todo_top3_count", 0), isZh)
            val summaryHeight = if (contentWidth > 0) textMetrics.wrapped(summaryText, 11f, contentWidth) else smallLine

            val hasSecondaryRows = (2..3).map { slot ->
                !prefs.getString("todo_top3_${slot}_id", "").isNullOrBlank() &&
                    !prefs.getString("todo_top3_$slot", "").isNullOrBlank()
            }
            val plan = if (requiredHeaderFits) {
                DuoyiWidgetLayoutPolicy.todo(
                    frame.core.effectiveMode, width, height,
                    hasSecondaryRows,
                    if (showTitle) headerHeight else 0, bodyLine, smallLine,
                    headerHeight = headerHeight,
                    navigationHeight = navigationHeight,
                    navigationFitsWidth = navigationFitsWidth,
                    rowHeights = measuredRowHeights,
                    summaryHeight = summaryHeight,
                    requiredHeaderFits = requiredHeaderFits,
                )
            } else {
                null
            }
            val requiredRow1Fits = requiredHeaderFits &&
                rowFitsWidth.getOrElse(0) { false } &&
                (plan?.rows?.getOrElse(0) { false } == true)

            if (!requiredRow1Fits) {
                val recoveryText = DuoyiWidgetCopy.todoRecoveryText(isZh)
                val recoveryMeasurement = textMetrics.measureWrapped(recoveryText, 12f, contentWidth)
                val recoveryFits = contentWidth > 0 && recoveryMeasurement.fits &&
                    available >= padding * 2 + recoveryMeasurement.height
                val recoveryDesc = DuoyiWidgetCopy.todoNoFitContentDescription(
                    frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits
                )

                views.setViewVisibility(R.id.widget_todo_header, View.GONE)
                views.setViewVisibility(R.id.widget_todo_title, View.GONE)
                views.setViewVisibility(R.id.widget_todo_unit, View.GONE)
                views.setViewVisibility(R.id.widget_todo_count, View.GONE)
                views.setViewVisibility(R.id.widget_todo_quick_add, View.GONE)
                views.setViewVisibility(R.id.widget_refresh, View.GONE)
                views.setViewVisibility(R.id.widget_todo_row_1, View.GONE)
                views.setViewVisibility(R.id.widget_todo_row_2, View.GONE)
                views.setViewVisibility(R.id.widget_todo_row_3, View.GONE)
                views.setViewVisibility(R.id.widget_todo_done_1, View.GONE)
                views.setViewVisibility(R.id.widget_todo_done_2, View.GONE)
                views.setViewVisibility(R.id.widget_todo_done_3, View.GONE)
                views.setViewVisibility(R.id.widget_todo_today_summary, View.GONE)
                views.setViewVisibility(R.id.widget_todo_spacer, View.GONE)
                views.setViewVisibility(R.id.widget_todo_bottom_nav, View.GONE)

                if (recoveryFits) {
                    views.setViewVisibility(R.id.widget_todo_recovery, View.VISIBLE)
                    views.setTextViewText(R.id.widget_todo_recovery, recoveryText)
                    views.setContentDescription(R.id.widget_todo_recovery, recoveryDesc)
                } else {
                    views.setViewVisibility(R.id.widget_todo_recovery, View.GONE)
                }
                views.setContentDescription(R.id.widget_todo_root, recoveryDesc)
                padding(R.id.widget_todo_content, padding)
            } else {
                val nonNullPlan = plan!!
                views.setViewVisibility(R.id.widget_todo_recovery, View.GONE)
                views.setContentDescription(R.id.widget_todo_root, null)
                views.setViewVisibility(R.id.widget_todo_header, View.VISIBLE)
                views.setViewVisibility(R.id.widget_todo_title, visibility(showTitle))
                views.setViewVisibility(R.id.widget_todo_unit, visibility(showUnit))
                views.setViewVisibility(R.id.widget_todo_count, visibility(showCount))
                views.setViewVisibility(R.id.widget_todo_quick_add, visibility(showQuickAdd))
                views.setViewVisibility(R.id.widget_refresh, View.VISIBLE)

                val showRow1 = nonNullPlan.rows[0]
                val showRow2 = nonNullPlan.rows[1] && rowFitsWidth[1]
                val showRow3 = nonNullPlan.rows[2] && (!hasSecondaryRows[0] || showRow2) && rowFitsWidth[2]
                val visibleRows = booleanArrayOf(showRow1, showRow2, showRow3)
                val allAdmittedRowsShown = (0..2).all { slot -> !nonNullPlan.rows[slot] || visibleRows[slot] }
                val showSummary = nonNullPlan.showSummary && allAdmittedRowsShown && frame.fresh
                val showNavigation = nonNullPlan.showNavigation && allAdmittedRowsShown
                padding(R.id.widget_todo_content, nonNullPlan.padding)
                val rowIds = intArrayOf(R.id.widget_todo_row_1, R.id.widget_todo_row_2, R.id.widget_todo_row_3)
                val doneIds = intArrayOf(R.id.widget_todo_done_1, R.id.widget_todo_done_2, R.id.widget_todo_done_3)
                rowIds.forEachIndexed { slot, viewId ->
                    val rowVisible = visibleRows[slot]
                    views.setViewVisibility(viewId, visibility(rowVisible))
                    val todoId = prefs.getString("todo_top3_${slot + 1}_id", "") ?: ""
                    views.setViewVisibility(doneIds[slot], visibility(rowVisible && frame.fresh && todoId.isNotBlank()))
                }
                views.setViewVisibility(R.id.widget_todo_spacer, View.VISIBLE)
                views.setViewVisibility(R.id.widget_todo_bottom_nav, visibility(showNavigation))
                views.setViewVisibility(R.id.widget_todo_today_summary, visibility(showSummary))
            }
        } else if (views.layoutId == R.layout.duoyi_habit_widget) {
            val padding = 8
            val contentWidth = maxOf(0, (width.takeIf { it > 0 } ?: 140) - padding * 2)
            val noHabitsToday = prefs.getInt("habit_active_count", -1) == 0
            val visiblePercent = if (!frame.fresh || noHabitsToday) "—" else "${prefs.getInt("habit_percent", 0).coerceIn(0, 100)}%"
            views.setTextViewText(R.id.widget_habit_percent, visiblePercent)
            views.setContentDescription(R.id.widget_habit_percent, visiblePercent)

            val titleText = DuoyiWidgetCopy.appTitle(prefs, isZh)
            val showRefresh = width !in 1..139
            val refreshMargin = if (showRefresh) 4 else 0
            val refreshMeasurement = if (showRefresh) {
                textMetrics.measureSingleLine("↻", 14f, contentWidth, minWidthDp = 36, minHeightDp = 36)
            } else null
            val refreshWidth = if (showRefresh) refreshMeasurement!!.width else 0
            val refreshHeight = if (showRefresh) refreshMeasurement!!.height else 0

            val percentMeasurement = textMetrics.measureSingleLine(
                visiblePercent, 14f, maxOf(0, contentWidth - refreshMargin - refreshWidth)
            )
            val percentWidth = percentMeasurement.width
            val percentHeight = percentMeasurement.height

            val requiredHeaderWidth = percentWidth + refreshMargin + refreshWidth
            val requiredHeaderHeight = maxOf(36, percentHeight, refreshHeight)
            val requiredHeaderWidthFits = contentWidth > 0 &&
                requiredHeaderWidth <= contentWidth &&
                percentMeasurement.fits &&
                (!showRefresh || refreshMeasurement!!.fits)

            val available = DuoyiWidgetLayoutPolicy.heightOrDefault(height, frame.core.effectiveMode)

            val rawHint = prefs.getString("habit_quick_check_label", null)
            val hint = DuoyiWidgetCopy.habitQuickCheckLabel(rawHint, isZh)
            val hasHint = hint.isNotBlank()
            val hintMeasurement = if (hasHint && contentWidth > 0) {
                textMetrics.measureWrappedAction(
                    hint, 11f, contentWidth,
                    minWidthDp = 0, minHeightDp = 36,
                    horizontalPaddingDp = 0, verticalPaddingDp = 0,
                )
            } else null
            val hintFits = hintMeasurement?.fits == true
            val hintHeight = hintMeasurement?.height ?: maxOf(36, smallLine)

            val summaryText = DuoyiWidgetCopy.habitSummary(prefs.getString("habit_summary", null), isZh)
            val summaryMeasurement = if (contentWidth > 0) textMetrics.measureWrapped(summaryText, 12f, contentWidth) else null
            val summaryFits = summaryMeasurement?.fits == true
            val habitSummaryHeight = summaryMeasurement?.height ?: bodyLine

            val subtitleText = DuoyiWidgetCopy.habitSubtitle(isZh)
            val subtitleMeasurement = if (contentWidth > 0) textMetrics.measureWrapped(subtitleText, 11f, contentWidth) else null
            val subtitleFits = subtitleMeasurement?.fits == true
            val subtitleHeight = subtitleMeasurement?.height ?: smallLine

            val streakText = DuoyiWidgetCopy.streakSummary(prefs.getString("streak_summary", null), isZh)
            val streakMeasurement = if (contentWidth > 0) textMetrics.measureWrapped(streakText, 12f, contentWidth) else null
            val streakFits = streakMeasurement?.fits == true
            val streakHeight = streakMeasurement?.height ?: bodyLine

            val requiredContextFits = if (hasHint) hintFits else summaryFits
            val requiredContextHeight = if (hasHint) hintHeight + 6 else habitSummaryHeight

            val strictlyRequiredFitsInHeight = available >= padding * 2 + requiredHeaderHeight + 10 + requiredContextHeight + 2
            val strictlyRequiredFits = requiredHeaderWidthFits && requiredContextFits && strictlyRequiredFitsInHeight

            val showTitle: Boolean
            val headerHeight: Int
            val requiredHabitFits: Boolean

            if (!strictlyRequiredFits) {
                showTitle = false
                headerHeight = 0
                requiredHabitFits = false
            } else {
                val availableTitleWidth = contentWidth - (6 + requiredHeaderWidth)
                val titleFitsWidth = width !in 1..139 && availableTitleWidth > 0 &&
                    textMetrics.fitsSingleLine(titleText, 14f, availableTitleWidth)
                val titleMeasurement = if (titleFitsWidth) textMetrics.measureSingleLine(titleText, 14f, availableTitleWidth) else null
                val headerHeightWithTitle = maxOf(requiredHeaderHeight, titleMeasurement?.height ?: 0)
                val fitsInHeightWithTitle = available >= padding * 2 + headerHeightWithTitle + 10 + requiredContextHeight + 2
                val titleFits = titleFitsWidth && titleMeasurement != null && titleMeasurement.fits && fitsInHeightWithTitle

                showTitle = titleFits
                headerHeight = if (showTitle) headerHeightWithTitle else requiredHeaderHeight
                requiredHabitFits = true
            }

            if (!requiredHabitFits) {
                val recoveryText = DuoyiWidgetCopy.habitRecoveryText(isZh)
                val recoveryMeasurement = textMetrics.measureWrapped(recoveryText, 12f, contentWidth)
                val recoveryFits = contentWidth > 0 && recoveryMeasurement.fits &&
                    available >= padding * 2 + recoveryMeasurement.height
                val recoveryDesc = DuoyiWidgetCopy.habitNoFitContentDescription(
                    frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits
                )

                views.setViewVisibility(R.id.widget_habit_header, View.GONE)
                views.setViewVisibility(R.id.widget_habit_title, View.GONE)
                views.setViewVisibility(R.id.widget_habit_percent, View.GONE)
                views.setViewVisibility(R.id.widget_refresh, View.GONE)
                views.setViewVisibility(R.id.widget_habit_subtitle, View.GONE)
                views.setViewVisibility(R.id.widget_habit_body, View.GONE)
                views.setViewVisibility(R.id.widget_habit_summary, View.GONE)
                views.setViewVisibility(R.id.widget_habit_streak, View.GONE)
                views.setViewVisibility(R.id.widget_habit_hint, View.GONE)
                views.setViewVisibility(R.id.widget_habit_spacer, View.GONE)
                views.setViewVisibility(R.id.widget_habit_bottom_nav, View.GONE)

                if (recoveryFits) {
                    views.setViewVisibility(R.id.widget_habit_recovery, View.VISIBLE)
                    views.setTextViewText(R.id.widget_habit_recovery, recoveryText)
                    views.setContentDescription(R.id.widget_habit_recovery, recoveryDesc)
                } else {
                    views.setViewVisibility(R.id.widget_habit_recovery, View.GONE)
                }
                views.setContentDescription(R.id.widget_habit_root, recoveryDesc)
                padding(R.id.widget_habit_content, padding)
            } else {
                views.setViewVisibility(R.id.widget_habit_recovery, View.GONE)
                views.setContentDescription(R.id.widget_habit_root, null)
                views.setViewVisibility(R.id.widget_habit_header, View.VISIBLE)
                views.setViewVisibility(R.id.widget_habit_title, visibility(showTitle))
                views.setViewVisibility(R.id.widget_habit_percent, View.VISIBLE)
                views.setViewVisibility(R.id.widget_refresh, visibility(showRefresh))

                val plan = DuoyiWidgetLayoutPolicy.habit(
                    frame.core.effectiveMode, width, height,
                    hasHint, !noHabitsToday,
                    if (showTitle) headerHeight else 0, bodyLine, smallLine,
                    navigationHeight = navigationHeight,
                    navigationFitsWidth = navigationFitsWidth,
                    headerHeight = headerHeight,
                    hintHeight = hintHeight,
                    summaryHeight = habitSummaryHeight,
                    streakHeight = streakHeight,
                    subtitleHeight = subtitleHeight,
                    requiredHeaderFits = requiredHabitFits,
                )
                val wantsStreak = !noHabitsToday && frame.core.effectiveMode != "compact"
                val showHint = plan.showHint
                val showSummary = plan.showSummary && summaryFits
                val showStreak = plan.showStreak && showSummary && streakFits
                val showSubtitle = plan.showSubtitle && showSummary && (!wantsStreak || showStreak) && subtitleFits
                val showNavigation = plan.showNavigation && showSummary && (!wantsStreak || showStreak) && showSubtitle
                padding(R.id.widget_habit_content, plan.padding)
                views.setViewVisibility(R.id.widget_habit_subtitle, visibility(showSubtitle))
                views.setViewVisibility(R.id.widget_habit_body, visibility(showSummary || showStreak || showHint))
                views.setViewVisibility(R.id.widget_habit_summary, visibility(showSummary))
                views.setViewVisibility(R.id.widget_habit_streak, visibility(showStreak))
                views.setViewVisibility(R.id.widget_habit_hint, visibility(showHint))
                views.setViewVisibility(R.id.widget_habit_spacer, View.VISIBLE)
                views.setViewVisibility(R.id.widget_habit_bottom_nav, visibility(showNavigation))
            }
        } else if (views.layoutId == R.layout.duoyi_goal_widget) {
            val padding = 8
            val contentWidth = maxOf(0, (width.takeIf { it > 0 } ?: 140) - padding * 2)
            val available = DuoyiWidgetLayoutPolicy.heightOrDefault(height, frame.core.effectiveMode)

            val titleText = DuoyiWidgetCopy.appTitle(prefs, isZh)
            val showRefresh = width !in 1..139
            val refreshMeasurement = if (showRefresh) {
                textMetrics.measureSingleLine("↻", 14f, contentWidth, minWidthDp = 36, minHeightDp = 36)
            } else {
                null
            }
            val refreshFits = !showRefresh || (contentWidth > 0 && refreshMeasurement?.fits == true)
            val refreshWidth = if (showRefresh && refreshMeasurement != null) refreshMeasurement.width else 0
            val refreshHeight = if (showRefresh && refreshMeasurement != null) refreshMeasurement.height else 0

            val titleAvailableWidth = maxOf(0, contentWidth - refreshWidth)
            val titleMeasurement = if (titleAvailableWidth > 0) {
                textMetrics.measureWrapped(titleText, 14f, titleAvailableWidth)
            } else {
                null
            }
            val showTitle = titleMeasurement?.fits == true
            val headerHeight = maxOf(
                refreshHeight,
                if (showTitle) titleMeasurement!!.height else 0,
            )

            val slotTexts = listOf(
                DuoyiWidgetCopy.goalHighlight1(prefs.getString("goal_highlight_1", null), isZh),
                DuoyiWidgetCopy.goalHighlight2(prefs.getString("goal_highlight_2", null), isZh),
                DuoyiWidgetCopy.goalHighlight3(prefs.getString("goal_highlight_3", null), isZh),
            )
            val hasSecondaryRows = (2..3).map { slot ->
                !prefs.getString("goal_highlight_$slot", "").isNullOrBlank()
            }
            val slotMeasurements = slotTexts.mapIndexed { index, text ->
                if (index > 0 && !hasSecondaryRows[index - 1]) {
                    null
                } else if (contentWidth > 0) {
                    val sp = if (index == 2) 11f else 12f
                    textMetrics.measureWrapped(text, sp, contentWidth)
                } else {
                    null
                }
            }
            val rowHeights = slotMeasurements.map { it?.height ?: 0 }
            val rowFitsWidth = slotMeasurements.map { it?.fits == true }

            val subtitleText = DuoyiWidgetCopy.goalSubtitle(isZh)
            val subtitleMeasurement = if (contentWidth > 0) {
                textMetrics.measureWrapped(subtitleText, 11f, contentWidth)
            } else {
                null
            }

            val plan = DuoyiWidgetLayoutPolicy.goal(
                mode = frame.core.effectiveMode,
                height = height,
                headerHeight = headerHeight,
                rowHeights = rowHeights,
                rowFitsWidth = rowFitsWidth,
                secondaryRows = hasSecondaryRows,
                subtitleHeight = subtitleMeasurement?.height ?: smallLine,
                subtitleFitsWidth = subtitleMeasurement?.fits == true,
                navigationHeight = navigationHeight,
                navigationFitsWidth = navigationFitsWidth,
                requiredHeaderFits = refreshFits && available >= padding * 2 + headerHeight + 10 + 2,
            )

            if (!plan.requiredContentFits) {
                val recoveryText = DuoyiWidgetCopy.goalRecoveryText(isZh)
                val recoveryMeasurement = textMetrics.measureWrapped(recoveryText, 12f, contentWidth)
                val recoveryFits = contentWidth > 0 && recoveryMeasurement.fits &&
                    available >= padding * 2 + recoveryMeasurement.height
                val recoveryIconTouchDp = 48
                val recoveryIconFits = contentWidth >= recoveryIconTouchDp &&
                    available >= padding * 2 + recoveryIconTouchDp
                val recoveryDesc = DuoyiWidgetCopy.goalNoFitContentDescription(
                    frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits,
                )

                views.setViewVisibility(R.id.widget_goal_header, View.GONE)
                views.setViewVisibility(R.id.widget_goal_title, View.GONE)
                views.setViewVisibility(R.id.widget_refresh, View.GONE)
                views.setViewVisibility(R.id.widget_goal_subtitle, View.GONE)
                views.setViewVisibility(R.id.widget_goal_body, View.GONE)
                views.setViewVisibility(R.id.widget_goal_1, View.GONE)
                views.setViewVisibility(R.id.widget_goal_2, View.GONE)
                views.setViewVisibility(R.id.widget_goal_3, View.GONE)
                views.setViewVisibility(R.id.widget_goal_bottom_nav, View.GONE)

                if (recoveryFits) {
                    views.setViewVisibility(R.id.widget_goal_recovery, View.VISIBLE)
                    views.setTextViewText(R.id.widget_goal_recovery, recoveryText)
                    views.setTextColor(R.id.widget_goal_recovery, DuoyiWidgetTheme.read(prefs).text)
                    views.setContentDescription(R.id.widget_goal_recovery, recoveryDesc)
                    views.setOnClickPendingIntent(
                        R.id.widget_goal_recovery,
                        HomeWidgetLaunchIntent.getActivity(
                            context, MainActivity::class.java, Uri.parse("duoyi://goal"),
                        ),
                    )
                    views.setViewVisibility(R.id.widget_goal_recovery_icon, View.GONE)
                    views.setContentDescription(R.id.widget_goal_recovery_icon, null)
                    views.setOnClickPendingIntent(R.id.widget_goal_recovery_icon, null)
                } else {
                    views.setViewVisibility(R.id.widget_goal_recovery, View.GONE)
                    views.setContentDescription(R.id.widget_goal_recovery, null)
                    views.setOnClickPendingIntent(R.id.widget_goal_recovery, null)
                    if (recoveryIconFits) {
                        val theme = DuoyiWidgetTheme.read(prefs)
                        val iconColor = if (theme.backgroundAssetKey.isEmpty() &&
                            (theme.navBackground ushr 24) == 255 &&
                            (theme.background ushr 24) == 255
                        ) {
                            DuoyiWidgetReadableColors.foreground(
                                theme.text,
                                intArrayOf(theme.navBackground, theme.background),
                            )
                        } else {
                            theme.text
                        }
                        DuoyiWidgetTheme.applyButtonSurfaces(
                            views,
                            prefs,
                            secondaryIds = intArrayOf(R.id.widget_goal_recovery_icon),
                        )
                        views.setViewVisibility(R.id.widget_goal_recovery_icon, View.VISIBLE)
                        views.setInt(R.id.widget_goal_recovery_icon, "setColorFilter", iconColor)
                        views.setContentDescription(R.id.widget_goal_recovery_icon, recoveryDesc)
                        views.setOnClickPendingIntent(
                            R.id.widget_goal_recovery_icon,
                            HomeWidgetLaunchIntent.getActivity(
                                context, MainActivity::class.java, Uri.parse("duoyi://goal"),
                            ),
                        )
                    } else {
                        views.setViewVisibility(R.id.widget_goal_recovery_icon, View.GONE)
                        views.setContentDescription(R.id.widget_goal_recovery_icon, null)
                        views.setOnClickPendingIntent(R.id.widget_goal_recovery_icon, null)
                    }
                }
                views.setContentDescription(R.id.widget_goal_root, recoveryDesc)
                padding(R.id.widget_goal_content, padding)
            } else {
                views.setViewVisibility(R.id.widget_goal_recovery, View.GONE)
                views.setContentDescription(R.id.widget_goal_root, null)
                views.setContentDescription(R.id.widget_goal_recovery, null)
                views.setOnClickPendingIntent(R.id.widget_goal_recovery, null)
                views.setViewVisibility(R.id.widget_goal_recovery_icon, View.GONE)
                views.setContentDescription(R.id.widget_goal_recovery_icon, null)
                views.setOnClickPendingIntent(R.id.widget_goal_recovery_icon, null)
                views.setViewVisibility(R.id.widget_goal_header, visibility(showTitle || showRefresh))
                views.setViewVisibility(R.id.widget_goal_title, visibility(showTitle))
                views.setViewVisibility(R.id.widget_refresh, visibility(showRefresh))
                views.setViewVisibility(R.id.widget_goal_subtitle, visibility(plan.showSubtitle))
                views.setViewVisibility(R.id.widget_goal_body, View.VISIBLE)
                views.setViewVisibility(R.id.widget_goal_1, visibility(plan.rows[0]))
                views.setViewVisibility(R.id.widget_goal_2, visibility(plan.rows[1]))
                views.setViewVisibility(R.id.widget_goal_3, visibility(plan.rows[2]))
                views.setViewVisibility(R.id.widget_goal_bottom_nav, visibility(plan.showNavigation))
                padding(R.id.widget_goal_content, plan.padding)
            }
        } else if (views.layoutId == R.layout.duoyi_note_widget) {
            fitNoteWidget(context, views, frame, metrics.density, isZh)
        } else {
            val spec = textLists[views.layoutId] ?: return
            val isCourse = views.layoutId == R.layout.duoyi_course_widget
            val rowFitsWidth: List<Boolean>?
            val subtitleFitsWidth: Boolean
            if (isCourse) {
                val widgetWidthDp = width.takeIf { it > 0 } ?: 140
                val horizontalPaddingDp = 16
                val rowTexts = listOf(
                    DuoyiWidgetCopy.courseHighlight1(prefs.getString("course_highlight_1", null), isZh),
                    prefs.getString("course_highlight_2", "") ?: "",
                    prefs.getString("course_highlight_3", "") ?: "",
                )
                rowFitsWidth = rowTexts.mapIndexed { slot, text ->
                    val sp = if (slot == 2 && spec.thirdLineIsSmall) 11f else 12f
                    text.isEmpty() || textMetrics.measureSingleLine(
                        text,
                        sp,
                        widgetWidthDp,
                        horizontalPaddingDp = horizontalPaddingDp,
                    ).fits
                }
                subtitleFitsWidth = textMetrics.measureSingleLine(
                    DuoyiWidgetCopy.courseSubtitle(isZh),
                    11f,
                    widgetWidthDp,
                    horizontalPaddingDp = horizontalPaddingDp,
                ).fits
            } else {
                rowFitsWidth = null
                subtitleFitsWidth = true
            }
            val plan = DuoyiWidgetLayoutPolicy.textList(
                frame.core.requestedMode, width, height,
                (2..3).map { slot ->
                    !prefs.getString("${spec.keyPrefix}_highlight_$slot", "").isNullOrBlank()
                },
                titleLine, bodyLine, smallLine, spec.thirdLineIsSmall,
                navigationHeight = navigationHeight,
                navigationFitsWidth = navigationFitsWidth,
                roundingReserveDp = if (views.layoutId == R.layout.duoyi_diary_widget) 0 else 2,
                rowFitsWidth = rowFitsWidth,
                subtitleFitsWidth = subtitleFitsWidth,
            )
            padding(spec.contentId, plan.padding)
            spec.rowIds.forEachIndexed { slot, viewId ->
                views.setViewVisibility(viewId, visibility(plan.rows[slot]))
            }
            views.setViewVisibility(spec.subtitleId, visibility(plan.showSubtitle))
            views.setViewVisibility(spec.navigationId, visibility(plan.showNavigation))
        }
    }

    private const val NOTE_RECOVERY_LABEL_ZH = "笔记"
    private const val NOTE_RECOVERY_LABEL_EN = "Notes"
    private const val NOTE_RECOVERY_AX_ZH = "打开笔记查看完整内容"
    private const val NOTE_RECOVERY_AX_EN = "Open Notes to view all content"

    private data class NotePxMeasurement(
        val fits: Boolean,
        val heightPx: Int,
        val textHeightPx: Int,
    )

    private class NoteLayoutPlan(
        val showHeader: Boolean,
        val showTitle: Boolean,
        val showRefresh: Boolean,
        val showRows: BooleanArray,
        val row2Text: String,
        val row3Text: String,
        val useHorizontalTail: Boolean,
        val showSubtitle: Boolean,
        val showNavigation: Boolean,
        val showRecovery: Boolean,
        val shownCount: Int,
        val totalRequestedCount: Int,
    )

    private fun hasNoteLineSeparators(text: String): Boolean =
        text.contains('\n') || text.contains('\r') || text.contains('\u0085') ||
            text.contains('\u2028') || text.contains('\u2029')

    private fun measureNoteTextView(
        context: Context,
        text: String,
        sp: Float,
        availableWidthPx: Int,
        singleLine: Boolean,
        centered: Boolean = false,
        simpleBreak: Boolean = true,
        ellipsizeEnd: Boolean = false,
        sidePaddingPx: Int = 0,
        minWidthPx: Int = 0,
        minHeightPx: Int = 0,
    ): NotePxMeasurement {
        val view = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
            typeface = Typeface.DEFAULT
            includeFontPadding = true
            setLineSpacing(0f, 1f)
            letterSpacing = 0f
            textScaleX = 1f
            setHorizontallyScrolling(false)
            gravity = if (centered) Gravity.CENTER else (Gravity.TOP or Gravity.START)
            breakStrategy = if (simpleBreak) Layout.BREAK_STRATEGY_SIMPLE else Layout.BREAK_STRATEGY_HIGH_QUALITY
            hyphenationFrequency = Layout.HYPHENATION_FREQUENCY_NONE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                isFallbackLineSpacing = true
            }
            if (ellipsizeEnd) {
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            } else {
                maxLines = Integer.MAX_VALUE
                ellipsize = null
            }
            setPadding(sidePaddingPx, 0, sidePaddingPx, 0)
            minimumWidth = minWidthPx
            minWidth = minWidthPx
            minimumHeight = minHeightPx
            minHeight = minHeightPx
        }
        val horizontalPadPx = sidePaddingPx * 2
        if (!singleLine && (availableWidthPx <= 0 || text.isEmpty())) {
            return NotePxMeasurement(
                fits = text.isEmpty() && availableWidthPx >= 0,
                heightPx = 0,
                textHeightPx = 0,
            )
        }
        if (singleLine && text.isEmpty()) {
            val fm = view.paint.fontMetricsInt
            val fontHeightPx = fm.bottom - fm.top
            return NotePxMeasurement(
                fits = availableWidthPx >= horizontalPadPx && availableWidthPx >= minWidthPx,
                heightPx = maxOf(minHeightPx, fontHeightPx),
                textHeightPx = fontHeightPx,
            )
        }
        val innerWidthPx = availableWidthPx - horizontalPadPx
        if (availableWidthPx <= 0 || innerWidthPx <= 0 || (singleLine && hasNoteLineSeparators(text))) {
            val fm = view.paint.fontMetricsInt
            val fontHeightPx = fm.bottom - fm.top
            return NotePxMeasurement(
                fits = false,
                heightPx = maxOf(minHeightPx, fontHeightPx),
                textHeightPx = fontHeightPx,
            )
        }

        view.text = text
        val widthSpec = View.MeasureSpec.makeMeasureSpec(availableWidthPx, View.MeasureSpec.EXACTLY)
        val heightSpec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        view.measure(widthSpec, heightSpec)
        view.layout(0, 0, view.measuredWidth, view.measuredHeight)

        val layout = view.layout
        val contentWidthPx = view.measuredWidth - view.compoundPaddingLeft - view.compoundPaddingRight
        val maxWidthPx = contentWidthPx.toFloat()
        val lineCount = layout?.lineCount ?: 0
        var linesFit = layout != null &&
            contentWidthPx > 0 &&
            lineCount > 0 &&
            layout.getLineEnd(lineCount - 1) == text.length &&
            layout.height + view.compoundPaddingTop + view.compoundPaddingBottom <= view.measuredHeight
        if (singleLine && lineCount != 1) {
            linesFit = false
        }
        if (singleLine && view.paint.measureText(text) > maxWidthPx) {
            linesFit = false
        }
        if (layout != null) {
            for (i in 0 until lineCount) {
                val lineStart = layout.getLineStart(i)
                val lineEnd = layout.getLineEnd(i)
                val lineVisibleEnd = layout.getLineVisibleEnd(i)
                val lineLeft = layout.getLineLeft(i)
                val lineRight = layout.getLineRight(i)
                val lineMax = layout.getLineMax(i)
                val lineWidth = layout.getLineWidth(i)

                val validRanges = lineStart >= 0 &&
                    lineStart <= lineVisibleEnd &&
                    lineVisibleEnd <= lineEnd &&
                    lineEnd <= text.length
                val finiteNonNegative = lineLeft.isFinite() &&
                    lineRight.isFinite() &&
                    lineMax.isFinite() &&
                    lineWidth.isFinite() &&
                    lineLeft >= 0f &&
                    lineRight >= 0f &&
                    lineMax >= 0f &&
                    lineWidth >= 0f
                val visibleBoundsFit = finiteNonNegative &&
                    lineLeft <= lineRight &&
                    lineLeft <= maxWidthPx &&
                    lineRight <= maxWidthPx &&
                    lineMax <= maxWidthPx
                val unconditionalBoundsOk = layout.getEllipsisCount(i) == 0 &&
                    validRanges &&
                    visibleBoundsFit

                var eligibleTrailingSpaceException = false
                if (!singleLine &&
                    unconditionalBoundsOk &&
                    lineWidth > maxWidthPx &&
                    i < lineCount - 1 &&
                    lineVisibleEnd < lineEnd
                ) {
                    var asciiSpaceSuffix = true
                    for (offset in lineVisibleEnd until lineEnd) {
                        if (text[offset] != '\u0020') {
                            asciiSpaceSuffix = false
                            break
                        }
                    }
                    if (asciiSpaceSuffix && layout.getParagraphDirection(i) == Layout.DIR_LEFT_TO_RIGHT) {
                        var hasRtlRun = false
                        for (offset in lineStart until lineEnd) {
                            if (layout.isRtlCharAt(offset)) {
                                hasRtlRun = true
                                break
                            }
                        }
                        eligibleTrailingSpaceException = !hasRtlRun
                    }
                }

                if (!unconditionalBoundsOk || (lineWidth > maxWidthPx && !eligibleTrailingSpaceException)) {
                    linesFit = false
                }
            }
        }
        return NotePxMeasurement(
            fits = linesFit,
            heightPx = view.measuredHeight,
            textHeightPx = layout?.height ?: 0,
        )
    }

    private fun fitNoteWidget(
        context: Context,
        views: RemoteViews,
        frame: DuoyiWidgetRenderFrame,
        rawDensity: Float,
        isZh: Boolean,
    ) {
        val density = rawDensity.takeIf { it > 0f } ?: 1f
        val paddingDp = 8
        val padPx = (paddingDp * density).roundToInt()
        views.setViewPadding(R.id.widget_note_content, padPx, padPx, padPx, padPx)

        val plan = planNoteLayout(context, frame, density, padPx, isZh)
        applyNoteLayout(context, views, frame, plan, isZh)
    }

    private fun planNoteLayout(
        context: Context,
        frame: DuoyiWidgetRenderFrame,
        density: Float,
        padPx: Int,
        isZh: Boolean,
    ): NoteLayoutPlan {
        fun dpToPxSize(dp: Int): Int = if (dp == 0) 0 else (dp * density + 0.5f).toInt()

        val prefs = frame.prefs
        val requestedMode = frame.core.requestedMode
        val width = frame.core.options.minWidth
        val height = frame.core.options.minHeight
        val widgetWidthDp = if (width > 0) width else when (requestedMode) {
            "detailed" -> 250
            "standard" -> 180
            else -> 110
        }
        val widgetHeightDp = DuoyiWidgetLayoutPolicy.heightOrDefault(height, requestedMode)
        val outerWidthPx = (widgetWidthDp * density).toInt()
        val outerHeightPx = (widgetHeightDp * density).toInt()
        val innerWidthPx = maxOf(0, outerWidthPx - padPx * 2)
        val innerHeightPx = maxOf(0, outerHeightPx - padPx * 2)

        val bodyTopGapPx = dpToPxSize(10)
        val rowGapPx = dpToPxSize(6)
        val subtitleGapPx = dpToPxSize(2)
        val navGapPx = dpToPxSize(8)
        val navMinHeightPx = dpToPxSize(30)
        val refreshBoxPx = dpToPxSize(36)

        val wantsRefresh = width !in 1..139
        val refreshMeasure = if (wantsRefresh && innerWidthPx >= refreshBoxPx && refreshBoxPx <= innerHeightPx) {
            measureNoteTextView(
                context = context,
                text = "↻",
                sp = 14f,
                availableWidthPx = refreshBoxPx,
                singleLine = true,
                centered = true,
                simpleBreak = false,
                ellipsizeEnd = true,
                minWidthPx = refreshBoxPx,
                minHeightPx = refreshBoxPx,
            )
        } else {
            null
        }
        val showRefresh = wantsRefresh &&
            refreshMeasure?.fits == true &&
            refreshMeasure.textHeightPx <= refreshBoxPx &&
            refreshMeasure.heightPx <= refreshBoxPx

        val titleAvailPx = maxOf(0, innerWidthPx - if (showRefresh) refreshBoxPx else 0)
        val titleText = DuoyiWidgetCopy.appTitle(prefs, isZh)
        val titleMeasure = if (titleAvailPx > 0) {
            measureNoteTextView(
                context = context,
                text = titleText,
                sp = 14f,
                availableWidthPx = titleAvailPx,
                singleLine = true,
                centered = false,
                simpleBreak = true,
                ellipsizeEnd = true,
            )
        } else {
            null
        }
        val showTitle = titleMeasure?.fits == true && titleMeasure.heightPx <= innerHeightPx
        val showHeader = showTitle || showRefresh
        val headerNaturalHeightPx = maxOf(
            if (showRefresh) refreshBoxPx else 0,
            if (showTitle) titleMeasure!!.heightPx else 0,
        )

        val rowCap = when (requestedMode) {
            "compact" -> 1
            "detailed" -> 3
            else -> 2
        }
        val row1Text = DuoyiWidgetCopy.noteHighlight1(prefs.getString("note_highlight_1", null), isZh)
        val row2Text = prefs.getString("note_highlight_2", "") ?: ""
        val row3Text = prefs.getString("note_highlight_3", "") ?: ""
        val rowTexts = listOf(row1Text, row2Text, row3Text)
        val rowPresent = booleanArrayOf(
            true,
            rowCap >= 2 && row2Text.isNotBlank(),
            rowCap >= 3 && row2Text.isNotBlank() && row3Text.isNotBlank(),
        )
        val totalRequestedCount = rowPresent.count { it }
        val verticalMeasures = (0..2).map { slot ->
            if (rowPresent[slot] && innerWidthPx > 0) {
                measureNoteTextView(
                    context = context,
                    text = rowTexts[slot],
                    sp = 12f,
                    availableWidthPx = innerWidthPx,
                    singleLine = false,
                    centered = false,
                    simpleBreak = true,
                    ellipsizeEnd = false,
                )
            } else {
                null
            }
        }

        val verticalShown = BooleanArray(3)
        var verticalUsedPx = headerNaturalHeightPx + bodyTopGapPx
        if (showHeader && verticalUsedPx <= innerHeightPx) {
            for (slot in 0..2) {
                if (!rowPresent[slot]) break
                val measure = verticalMeasures[slot] ?: break
                if (!measure.fits) break
                val gap = if (slot == 0) 0 else rowGapPx
                if (verticalUsedPx + gap + measure.heightPx <= innerHeightPx) {
                    verticalShown[slot] = true
                    verticalUsedPx += gap + measure.heightPx
                } else {
                    break
                }
            }
        }
        val allRequestedVerticalFit = (0..2).all { slot -> !rowPresent[slot] || verticalShown[slot] }

        var useHorizontalTail = false
        var tailUsedPx = 0
        if (requestedMode == "detailed" &&
            !allRequestedVerticalFit &&
            rowPresent[0] && rowPresent[1] && rowPresent[2] &&
            showHeader &&
            verticalMeasures[0]?.fits == true
        ) {
            val tailAvailPx = maxOf(0, innerWidthPx - rowGapPx)
            val candidateLeftPx = tailAvailPx / 2
            val candidateRightPx = tailAvailPx - candidateLeftPx
            val tail2 = if (candidateLeftPx > 0) {
                measureNoteTextView(
                    context = context,
                    text = rowTexts[1],
                    sp = 12f,
                    availableWidthPx = candidateLeftPx,
                    singleLine = true,
                    centered = false,
                    simpleBreak = true,
                    ellipsizeEnd = false,
                )
            } else {
                null
            }
            val tail3 = if (candidateRightPx > 0) {
                measureNoteTextView(
                    context = context,
                    text = rowTexts[2],
                    sp = 12f,
                    availableWidthPx = candidateRightPx,
                    singleLine = true,
                    centered = false,
                    simpleBreak = true,
                    ellipsizeEnd = false,
                )
            } else {
                null
            }
            if (tail2?.fits == true && tail3?.fits == true) {
                val row1Px = verticalMeasures[0]!!.heightPx
                val tailHeightPx = maxOf(tail2.heightPx, tail3.heightPx)
                val candidateUsedPx = headerNaturalHeightPx + bodyTopGapPx + row1Px + rowGapPx + tailHeightPx
                if (candidateUsedPx <= innerHeightPx) {
                    useHorizontalTail = true
                    tailUsedPx = candidateUsedPx
                }
            }
        }

        val showRows = if (useHorizontalTail) booleanArrayOf(true, true, true) else verticalShown
        val row1Admitted = showRows[0]
        val allRequestedAdmitted = allRequestedVerticalFit || useHorizontalTail
        var usedPx = if (useHorizontalTail) tailUsedPx else verticalUsedPx

        val subtitleMeasure = if (allRequestedAdmitted && innerWidthPx > 0) {
            measureNoteTextView(
                context = context,
                text = DuoyiWidgetCopy.noteSubtitle(isZh),
                sp = 11f,
                availableWidthPx = innerWidthPx,
                singleLine = true,
                centered = false,
                simpleBreak = true,
                ellipsizeEnd = true,
            )
        } else {
            null
        }
        val subtitleCostPx = if (subtitleMeasure != null) subtitleGapPx + subtitleMeasure.heightPx else 0
        val showSubtitle = allRequestedAdmitted &&
            subtitleMeasure?.fits == true &&
            usedPx + subtitleCostPx <= innerHeightPx
        if (showSubtitle) {
            usedPx += subtitleCostPx
        }

        val navPadPx = dpToPxSize(4)
        val navInnerPx = maxOf(0, innerWidthPx - navPadPx * 2)
        var navRemPx = navInnerPx
        val navCellWidths = IntArray(4) { idx ->
            val w = navRemPx / (4 - idx)
            navRemPx -= w
            w
        }
        val navLabels = listOf(
            DuoyiWidgetCopy.navTodo(prefs, isZh),
            DuoyiWidgetCopy.navHabit(prefs, isZh),
            DuoyiWidgetCopy.navCalendar(prefs, isZh),
            DuoyiWidgetCopy.navFocus(prefs, isZh),
        )
        val navMeasures = if (requestedMode != "compact" && allRequestedAdmitted && showSubtitle && navCellWidths.all { it > 0 }) {
            navLabels.mapIndexed { idx, label ->
                measureNoteTextView(
                    context = context,
                    text = label,
                    sp = 10f,
                    availableWidthPx = navCellWidths[idx],
                    singleLine = true,
                    centered = true,
                    simpleBreak = false,
                    ellipsizeEnd = true,
                    minHeightPx = navMinHeightPx,
                )
            }
        } else {
            emptyList()
        }
        val navFitsWidth = navMeasures.size == 4 && navMeasures.all { it.fits }
        val navHeightPx = if (navFitsWidth) {
            maxOf(navMinHeightPx, navMeasures.maxOf { it.heightPx })
        } else {
            0
        }
        val showNavigation = requestedMode != "compact" &&
            allRequestedAdmitted &&
            showSubtitle &&
            navFitsWidth &&
            usedPx + navGapPx + navHeightPx <= innerHeightPx

        val recoveryLabel = if (isZh) NOTE_RECOVERY_LABEL_ZH else NOTE_RECOVERY_LABEL_EN
        val recoverySidePadPx = dpToPxSize(4)
        val recoveryMinHeightPx = dpToPxSize(36)
        val recoveryMeasure = if (!row1Admitted && innerWidthPx > 0) {
            measureNoteTextView(
                context = context,
                text = recoveryLabel,
                sp = 12f,
                availableWidthPx = innerWidthPx,
                singleLine = true,
                centered = true,
                simpleBreak = true,
                ellipsizeEnd = false,
                sidePaddingPx = recoverySidePadPx,
                minHeightPx = recoveryMinHeightPx,
            )
        } else {
            null
        }
        val recoveryTopGapPx = if (showHeader) rowGapPx else 0
        val showRecovery = !row1Admitted &&
            recoveryMeasure?.fits == true &&
            headerNaturalHeightPx + recoveryTopGapPx + recoveryMeasure.heightPx <= innerHeightPx

        return NoteLayoutPlan(
            showHeader = showHeader,
            showTitle = showHeader && showTitle,
            showRefresh = showHeader && showRefresh,
            showRows = showRows,
            row2Text = row2Text,
            row3Text = row3Text,
            useHorizontalTail = useHorizontalTail,
            showSubtitle = row1Admitted && showSubtitle,
            showNavigation = row1Admitted && showNavigation,
            showRecovery = showRecovery,
            shownCount = showRows.count { it },
            totalRequestedCount = totalRequestedCount,
        )
    }

    private fun noteItemPendingIntent(
        context: Context,
        frame: DuoyiWidgetRenderFrame,
        idKey: String,
    ) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        entityUri(
            frame,
            run {
                val rawId = frame.prefs.getString(idKey, "")?.trim().orEmpty()
                when {
                    rawId.isBlank() -> Uri.parse("duoyi://note")
                    rawId.startsWith("duoyi://") -> Uri.parse(rawId)
                    else -> Uri.parse("duoyi://note/${Uri.encode(rawId)}")
                }
            },
            Uri.parse("duoyi://note"),
        ),
    )

    private fun applyNoteLayout(
        context: Context,
        views: RemoteViews,
        frame: DuoyiWidgetRenderFrame,
        plan: NoteLayoutPlan,
        isZh: Boolean,
    ) {
        fun visibility(shown: Boolean): Int = if (shown) View.VISIBLE else View.GONE
        val prefs = frame.prefs
        val row1Admitted = plan.showRows[0]
        val showTail = row1Admitted && (plan.showRows[1] || plan.showRows[2])

        views.setViewVisibility(R.id.widget_note_header, visibility(plan.showHeader))
        views.setViewVisibility(R.id.widget_note_title, visibility(plan.showTitle))
        views.setViewVisibility(R.id.widget_refresh, visibility(plan.showRefresh))
        views.setViewVisibility(R.id.widget_note_recovery_gap, visibility(plan.showRecovery && plan.showHeader))
        views.setViewVisibility(R.id.widget_note_subtitle, visibility(plan.showSubtitle))
        views.setViewVisibility(R.id.widget_note_body, visibility(row1Admitted))
        views.setViewVisibility(R.id.widget_note_1, visibility(plan.showRows[0]))
        views.setContentDescription(R.id.widget_note_1, null)

        val tailLayoutId = if (plan.useHorizontalTail) {
            R.layout.duoyi_note_widget_tail_horizontal
        } else {
            R.layout.duoyi_note_widget_tail_vertical
        }
        val tailViews = RemoteViews(context.packageName, tailLayoutId)
        tailViews.setTextViewText(R.id.widget_note_2, plan.row2Text)
        tailViews.setTextViewText(R.id.widget_note_3, plan.row3Text)
        DuoyiWidgetTheme.applyTextColors(
            tailViews,
            prefs,
            bodyIds = intArrayOf(R.id.widget_note_2, R.id.widget_note_3),
        )
        tailViews.setContentDescription(R.id.widget_note_2, null)
        tailViews.setContentDescription(R.id.widget_note_3, null)
        tailViews.setOnClickPendingIntent(
            R.id.widget_note_2,
            noteItemPendingIntent(context, frame, "note_highlight_2_id"),
        )
        tailViews.setOnClickPendingIntent(
            R.id.widget_note_3,
            noteItemPendingIntent(context, frame, "note_highlight_3_id"),
        )
        tailViews.setViewVisibility(R.id.widget_note_2, visibility(plan.showRows[1]))
        tailViews.setViewVisibility(R.id.widget_note_3, visibility(plan.showRows[2]))
        views.removeAllViews(R.id.widget_note_tail)
        views.addView(R.id.widget_note_tail, tailViews)
        views.setViewVisibility(R.id.widget_note_tail, visibility(showTail))

        views.setViewVisibility(R.id.widget_note_spacer, visibility(plan.showNavigation))
        views.setViewVisibility(R.id.widget_note_bottom_nav, visibility(plan.showNavigation))

        if (!row1Admitted) {
            val noFitDesc = noteNoFitContentDescription(
                frame.fresh,
                isZh,
                frame.core.publicationState,
                recoveryVisible = plan.showRecovery,
            )
            if (plan.showRecovery) {
                val theme = DuoyiWidgetTheme.read(prefs)
                val recoveryTextColor = if (theme.backgroundAssetKey.isEmpty() &&
                    (theme.navBackground ushr 24) == 255 &&
                    (theme.background ushr 24) == 255
                ) {
                    DuoyiWidgetReadableColors.foreground(
                        theme.text,
                        intArrayOf(theme.navBackground, theme.background),
                    )
                } else {
                    theme.text
                }
                DuoyiWidgetTheme.applyButtonSurfaces(
                    views,
                    prefs,
                    secondaryIds = intArrayOf(R.id.widget_note_recovery),
                )
                views.setViewVisibility(R.id.widget_note_recovery, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_note_recovery,
                    if (isZh) NOTE_RECOVERY_LABEL_ZH else NOTE_RECOVERY_LABEL_EN,
                )
                views.setTextColor(R.id.widget_note_recovery, recoveryTextColor)
                views.setContentDescription(
                    R.id.widget_note_recovery,
                    if (isZh) NOTE_RECOVERY_AX_ZH else NOTE_RECOVERY_AX_EN,
                )
                views.setOnClickPendingIntent(
                    R.id.widget_note_recovery,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("duoyi://note"),
                    ),
                )
            } else {
                views.setViewVisibility(R.id.widget_note_recovery, View.GONE)
                views.setTextViewText(R.id.widget_note_recovery, "")
                views.setContentDescription(R.id.widget_note_recovery, null)
                views.setOnClickPendingIntent(R.id.widget_note_recovery, null)
            }
            views.setContentDescription(R.id.widget_note_root, noFitDesc)
        } else {
            views.setViewVisibility(R.id.widget_note_recovery, View.GONE)
            views.setTextViewText(R.id.widget_note_recovery, "")
            views.setContentDescription(R.id.widget_note_recovery, null)
            views.setOnClickPendingIntent(R.id.widget_note_recovery, null)
            val partialDesc = if (plan.shownCount < plan.totalRequestedCount) {
                if (isZh) {
                    "显示${plan.shownCount}/${plan.totalRequestedCount}条，打开笔记查看完整内容"
                } else {
                    "Showing ${plan.shownCount} of ${plan.totalRequestedCount}, open Notes to view all content"
                }
            } else {
                null
            }
            views.setContentDescription(R.id.widget_note_root, partialDesc)
        }
    }

    private fun noteNoFitContentDescription(
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State?,
        recoveryVisible: Boolean,
    ): String = when {
        publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开多仪更新并查看笔记完整内容"
                else "Widget space insufficient, open Duoyi to update and view all notes"
            } else {
                if (isZh) "空间不足无可见内容，打开多仪更新并查看笔记"
                else "Widget space insufficient, no visible content, open Duoyi to update and view notes"
            }
        }
        !isFresh -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，数据待刷新，打开笔记查看完整内容"
                else "Widget space insufficient, data pending refresh, open Notes to view all content"
            } else {
                if (isZh) "空间不足无可见内容，数据待刷新，打开笔记"
                else "Widget space insufficient, no visible content, data pending refresh, open Notes"
            }
        }
        else -> {
            if (recoveryVisible) {
                if (isZh) "空间不足，打开笔记查看完整内容"
                else "Widget space insufficient, open Notes to view all content"
            } else {
                if (isZh) "空间不足无可见内容，打开笔记"
                else "Widget space insufficient, no visible content, open Notes"
            }
        }
    }
}
