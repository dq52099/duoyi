package com.duoyi.duoyi

/** Space budgets in dp. Mode is an upper limit; source slots are never reordered. */
object DuoyiWidgetLayoutPolicy {
    fun timerWidthSample(countUp: Boolean, remainingSeconds: Int): String {
        if (countUp) return "88:88:88" // The live count-up is capped at 24 hours.
        val hours = remainingSeconds.coerceAtLeast(0) / 3600
        return if (hours == 0) "88:88" else "${"8".repeat(hours.toString().length)}:88:88"
    }

    data class Focus(
        val showHeader: Boolean,
        val showAction: Boolean,
        val showMetrics: Boolean,
        val showAllMetrics: Boolean,
        val summaries: List<Boolean>,
        val showNavigation: Boolean,
        val usedHeight: Int,
    )

    /** Main action survives before metrics; no font-size reduction is permitted. */
    fun focus(
        mode: String, height: Int, headerHeight: Int, actionHeight: Int,
        timerHeight: Int, allMetricsHeight: Int, timerFitsWidth: Boolean,
        allMetricsFitWidth: Boolean, smallLineHeight: Int,
        navigationHeight: Int, navigationFitsWidth: Boolean,
    ): Focus {
        val available = heightOrDefault(height, mode)
        var used = 18 // 8dp padding each side + pixel rounding reserve.
        val action = used + actionHeight + 6 <= available
        if (action) used += actionHeight + 6
        val header = used + headerHeight <= available
        if (header) used += headerHeight
        val metrics = action && header && timerFitsWidth && used + timerHeight + 8 <= available
        val allMetrics = metrics && mode != "compact" && allMetricsFitWidth &&
            used + allMetricsHeight + 8 <= available
        if (metrics) used += (if (allMetrics) allMetricsHeight else timerHeight) + 8
        val completeMetrics = metrics && (mode == "compact" || !allMetricsFitWidth || allMetrics)
        var precedingFits = action && header && completeMetrics
        val summaries = (0..2).map { slot ->
            val wanted = slot == 0 || (slot == 1 && mode != "compact") ||
                (slot == 2 && mode == "detailed")
            val cost = smallLineHeight + if (slot == 0) 6 else 2
            val shown = wanted && precedingFits && used + cost <= available
            if (shown) used += cost else if (wanted) precedingFits = false
            shown
        }
        val navigation = mode != "compact" && precedingFits && navigationFitsWidth &&
            used + navigationHeight + 8 <= available
        if (navigation) used += navigationHeight + 8
        return Focus(header, action, metrics, allMetrics, summaries, navigation, used)
    }

    data class Calendar(
        val weeks: List<Int>,
        val showDateFallback: Boolean,
        val showInfo: Boolean,
        val showNavigation: Boolean,
        val usedHeight: Int,
    )

    /** Add weeks nearest today first, but render them in chronological order. */
    fun calendar(
        mode: String, height: Int, currentWeek: Int, headerHeight: Int,
        weekdayHeight: Int, dateHeight: Int, gridFitsWidth: Boolean,
        fallbackHeight: Int, fallbackFitsWidth: Boolean,
        infoHeight: Int, navigationHeight: Int, navigationFitsWidth: Boolean,
        weekCount: Int = 6,
    ): Calendar {
        val available = if (height > 0) height else if (mode == "detailed") 180 else 110
        var used = 18 + headerHeight
        val lastWeek = weekCount.coerceIn(1, 6) - 1
        val current = currentWeek.coerceIn(0, lastWeek)
        val candidates = when (mode) {
            "compact" -> listOf(current)
            "detailed" -> (0..lastWeek).sortedWith(compareBy<Int> { kotlin.math.abs(it - current) }.thenBy { it })
            else -> (maxOf(0, current - 1)..minOf(lastWeek, current + 2))
                .sortedWith(compareBy<Int> { kotlin.math.abs(it - current) }.thenBy { it })
        }
        val weeks = mutableListOf<Int>()
        if (gridFitsWidth && used + weekdayHeight + 4 + dateHeight <= available) {
            used += weekdayHeight + 4 // Two XML top margins.
            for (week in candidates) {
                if (used + dateHeight > available) break
                weeks += week
                used += dateHeight
            }
        }
        val fallback = weeks.isEmpty() && fallbackFitsWidth && used + fallbackHeight + 2 <= available
        if (fallback) used += fallbackHeight + 2
        val complete = weeks.size == candidates.size
        val info = mode != "compact" && complete && used + infoHeight + 2 <= available
        if (info) used += infoHeight + 2
        val navigation = mode != "compact" && complete && info && navigationFitsWidth &&
            used + navigationHeight + 2 <= available
        if (navigation) used += navigationHeight + 2
        return Calendar(weeks.sorted(), fallback, info, navigation, used)
    }

    data class CalendarMeasured(
        val weeks: List<Int>,
        val showDateFallback: Boolean,
        val showMonthSummary: Boolean,
        val showEventSummary: Boolean,
        val showNavigation: Boolean,
        val usedHeight: Int,
    )

    /** Measure-driven calendar layout allowing vertical multi-line info with month grid or date fallback. */
    fun calendarMeasured(
        mode: String,
        height: Int,
        currentWeek: Int,
        headerFits: Boolean,
        headerHeight: Int,
        weekdayHeight: Int,
        dateHeight: Int,
        gridFitsWidth: Boolean,
        fallbackHeight: Int,
        fallbackFitsWidth: Boolean,
        monthSummaryHeight: Int,
        monthSummaryFitsWidth: Boolean,
        hasEventSummary: Boolean,
        eventSummaryHeight: Int,
        eventSummaryFitsWidth: Boolean,
        navigationHeight: Int,
        navigationFitsWidth: Boolean,
        weekCount: Int = 6,
    ): CalendarMeasured {
        val available = if (height > 0) height else if (mode == "detailed") 180 else 110
        if (!headerFits || 18 + headerHeight > available) {
            return CalendarMeasured(emptyList(), false, false, false, false, 18)
        }
        var used = 18 + headerHeight
        val lastWeek = weekCount.coerceIn(1, 6) - 1
        val current = currentWeek.coerceIn(0, lastWeek)
        val candidates = when (mode) {
            "compact" -> listOf(current)
            "detailed" -> (0..lastWeek).sortedWith(compareBy<Int> { kotlin.math.abs(it - current) }.thenBy { it })
            else -> (maxOf(0, current - 1)..minOf(lastWeek, current + 2))
                .sortedWith(compareBy<Int> { kotlin.math.abs(it - current) }.thenBy { it })
        }
        val monthSummaryCost = maxOf(14, monthSummaryHeight) + 2
        val eventSummaryCost = eventSummaryHeight + 2
        if (mode != "compact" && hasEventSummary) {
            val requiredInfoFits = monthSummaryFitsWidth && eventSummaryFitsWidth
            val requiredInfoCost = monthSummaryCost + eventSummaryCost
            val completeGridCost = weekdayHeight + 4 + candidates.size * dateHeight
            val completeGridFits = requiredInfoFits && gridFitsWidth &&
                used + completeGridCost + requiredInfoCost <= available
            val fallbackFits = !completeGridFits && requiredInfoFits && fallbackFitsWidth &&
                used + fallbackHeight + 2 + requiredInfoCost <= available
            val selectedWeeks = if (completeGridFits) candidates.sorted() else emptyList()
            val showRequired = completeGridFits || fallbackFits
            if (completeGridFits) {
                used += completeGridCost + requiredInfoCost
            } else if (fallbackFits) {
                used += fallbackHeight + 2 + requiredInfoCost
            }
            val showNavigation = showRequired && navigationFitsWidth &&
                used + navigationHeight + 2 <= available
            if (showNavigation) used += navigationHeight + 2
            return CalendarMeasured(
                weeks = selectedWeeks,
                showDateFallback = fallbackFits,
                showMonthSummary = showRequired,
                showEventSummary = showRequired,
                showNavigation = showNavigation,
                usedHeight = used,
            )
        }
        val weeks = mutableListOf<Int>()
        if (gridFitsWidth && used + weekdayHeight + 4 + dateHeight <= available) {
            used += weekdayHeight + 4
            for (week in candidates) {
                if (used + dateHeight > available) break
                weeks += week
                used += dateHeight
            }
        }
        val fallback = weeks.isEmpty() && fallbackFitsWidth && used + fallbackHeight + 2 <= available
        if (fallback) used += fallbackHeight + 2
        val completeGrid = weeks.isNotEmpty() && weeks.size == candidates.size
        val canShowInfo = mode != "compact" && (completeGrid || fallback)
        val showMonthSummary = canShowInfo && monthSummaryFitsWidth && used + monthSummaryCost <= available
        if (showMonthSummary) used += monthSummaryCost
        val showEventSummary = showMonthSummary && hasEventSummary && eventSummaryFitsWidth &&
            used + eventSummaryCost <= available
        if (showEventSummary) used += eventSummaryCost
        val allInfoShown = showMonthSummary && (!hasEventSummary || showEventSummary)
        val showNavigation = mode != "compact" && allInfoShown && navigationFitsWidth &&
            used + navigationHeight + 2 <= available
        if (showNavigation) used += navigationHeight + 2
        return CalendarMeasured(
            weeks = weeks.sorted(),
            showDateFallback = fallback,
            showMonthSummary = showMonthSummary,
            showEventSummary = showEventSummary,
            showNavigation = showNavigation,
            usedHeight = used,
        )
    }

    data class Goal(
        val padding: Int,
        val rows: List<Boolean>,
        val showSubtitle: Boolean,
        val showNavigation: Boolean,
        val usedHeight: Int,
        val requiredContentFits: Boolean,
    )

    fun goal(
        mode: String,
        height: Int,
        headerHeight: Int,
        rowHeights: List<Int>,
        rowFitsWidth: List<Boolean>,
        secondaryRows: List<Boolean>,
        subtitleHeight: Int,
        subtitleFitsWidth: Boolean,
        navigationHeight: Int = 30,
        navigationFitsWidth: Boolean = true,
        requiredHeaderFits: Boolean = true,
    ): Goal {
        val available = heightOrDefault(height, mode)
        val padding = 8
        if (!requiredHeaderFits) {
            return Goal(padding, listOf(false, false, false), false, false, padding * 2, false)
        }
        var used = padding * 2 + headerHeight + 10 + 2
        var precedingRowsFit = true
        val rows = (0..2).map { slot ->
            val present = slot == 0 || secondaryRows.getOrElse(slot - 1) { false }
            if (!present || slot >= rowLimit(mode)) {
                false
            } else {
                val fitsWidth = rowFitsWidth.getOrElse(slot) { false }
                val rowCost = rowHeights.getOrElse(slot) { 0 } + if (slot == 0) 0 else 6
                val shown = precedingRowsFit && fitsWidth && used + rowCost <= available
                if (shown) used += rowCost else precedingRowsFit = false
                shown
            }
        }
        val allRows = (0 until rowLimit(mode)).all { slot ->
            (slot > 0 && !secondaryRows.getOrElse(slot - 1) { false }) || rows[slot]
        }
        val requiredContentFits = rows[0] && allRows
        if (!requiredContentFits) {
            return Goal(padding, listOf(false, false, false), false, false, padding * 2, false)
        }
        val subtitleCost = subtitleHeight + 2
        val showSubtitle = subtitleFitsWidth && used + subtitleCost <= available
        if (showSubtitle) used += subtitleCost
        val navigationCost = navigationHeight + 8
        val showNavigation = mode != "compact" && showSubtitle &&
            navigationFitsWidth && used + navigationCost <= available
        if (showNavigation) used += navigationCost
        return Goal(padding, rows, showSubtitle, showNavigation, used, true)
    }

    data class Todo(
        val padding: Int,
        val rows: List<Boolean>,
        val showNavigation: Boolean,
        val showSummary: Boolean,
        val usedHeight: Int,
    )

    data class Habit(
        val padding: Int,
        val showSubtitle: Boolean,
        val showSummary: Boolean,
        val showStreak: Boolean,
        val showHint: Boolean,
        val showNavigation: Boolean,
        val usedHeight: Int,
    )

    data class TextList(
        val padding: Int,
        val rows: List<Boolean>,
        val showSubtitle: Boolean,
        val showNavigation: Boolean,
        val usedHeight: Int,
    )

    private fun rowLimit(mode: String): Int = when (mode) {
        "compact" -> 1
        "detailed" -> 3
        else -> 2
    }

    fun heightOrDefault(height: Int, mode: String): Int =
        if (height > 0) height else if (mode == "detailed") 180 else 110

    fun textList(
        mode: String,
        width: Int,
        height: Int,
        secondaryRows: List<Boolean>,
        titleLineHeight: Int,
        bodyLineHeight: Int,
        smallLineHeight: Int,
        thirdLineIsSmall: Boolean,
        headerHeight: Int = maxOf(if (width in 1..139) 0 else 36, titleLineHeight),
        navigationHeight: Int = 30,
        navigationFitsWidth: Boolean = true,
        roundingReserveDp: Int = 2,
        rowFitsWidth: List<Boolean>? = null,
        subtitleFitsWidth: Boolean = true,
    ): TextList {
        val available = heightOrDefault(height, mode)
        val padding = 8
        var used = padding * 2 + headerHeight + 10 + roundingReserveDp // Body top margin + rounding reserve.
        var precedingRowsFit = true
        val rows = (0..2).map { slot ->
            val present = slot == 0 || secondaryRows.getOrElse(slot - 1) { false }
            if (!present || slot >= rowLimit(mode)) {
                false
            } else {
                val fitsWidth = rowFitsWidth?.getOrElse(slot) { false } ?: true
                val line = if (slot == 2 && thirdLineIsSmall) smallLineHeight else bodyLineHeight
                val cost = line + if (slot == 0) 0 else 6
                val shown = precedingRowsFit && fitsWidth && used + cost <= available
                if (shown) used += cost else precedingRowsFit = false
                shown
            }
        }
        val allRows = (0 until rowLimit(mode)).all { slot ->
            (slot > 0 && !secondaryRows.getOrElse(slot - 1) { false }) || rows[slot]
        }
        val subtitleCost = smallLineHeight + 2
        val subtitle = allRows && subtitleFitsWidth && used + subtitleCost <= available
        if (subtitle) used += subtitleCost
        val navigationCost = navigationHeight + 8 // Natural bar height + XML top margin.
        val navigation = mode != "compact" && allRows && subtitle && navigationFitsWidth &&
            used + navigationCost <= available
        if (navigation) used += navigationCost
        return TextList(padding, rows, subtitle, navigation, used)
    }

    fun todo(
        mode: String,
        width: Int,
        height: Int,
        secondaryRows: List<Boolean>,
        titleLineHeight: Int,
        bodyLineHeight: Int,
        smallLineHeight: Int,
        headerHeight: Int = maxOf(if (width in 1..151) 34 else 36, titleLineHeight),
        navigationHeight: Int = 30,
        navigationFitsWidth: Boolean = true,
        rowHeights: List<Int>? = null,
        summaryHeight: Int? = null,
        requiredHeaderFits: Boolean = true,
    ): Todo {
        val available = heightOrDefault(height, mode)
        val padding = 8
        val header = maxOf(headerHeight, titleLineHeight)
        var used = padding * 2 + header + 2 // Pixel rounding reserve.
        val defaultRowHeight = maxOf(38, bodyLineHeight)
        var precedingRowsFit = true
        val rows = (0..2).map { slot ->
            val present = slot == 0 || secondaryRows.getOrElse(slot - 1) { false }
            if (!present || slot >= rowLimit(mode)) {
                false
            } else {
                val rowCost = (rowHeights?.getOrNull(slot) ?: defaultRowHeight) + if (slot == 0) 6 else 3
                val shown = precedingRowsFit && used + rowCost <= available
                if (shown) {
                    used += rowCost
                } else {
                    precedingRowsFit = false
                }
                shown
            }
        }
        val allRows = (0 until rowLimit(mode)).all { slot ->
            (slot > 0 && !secondaryRows.getOrElse(slot - 1) { false }) || rows[slot]
        }
        // Do not reveal low-priority details only to evict them at the next row threshold.
        val summaryCost = 4 + (summaryHeight ?: smallLineHeight)
        val wantsSummary = mode == "detailed"
        val summary = wantsSummary && allRows && used + summaryCost <= available
        if (summary) used += summaryCost
        val navigationCost = navigationHeight + 6 // Natural bar height + XML top margin.
        val navigation = mode != "compact" && requiredHeaderFits && allRows && (!wantsSummary || summary) && navigationFitsWidth &&
            used + navigationCost <= available
        if (navigation) used += navigationCost
        return Todo(padding, rows, navigation, summary, used)
    }

    fun habit(
        mode: String,
        width: Int,
        height: Int,
        hasHint: Boolean,
        hasStreak: Boolean,
        titleLineHeight: Int,
        bodyLineHeight: Int,
        smallLineHeight: Int,
        navigationHeight: Int = 30,
        navigationFitsWidth: Boolean = true,
        headerHeight: Int = maxOf(if (width in 1..139) 0 else 36, titleLineHeight),
        hintHeight: Int? = null,
        summaryHeight: Int? = null,
        streakHeight: Int? = null,
        subtitleHeight: Int? = null,
        requiredHeaderFits: Boolean = true,
    ): Habit {
        val available = heightOrDefault(height, mode)
        val padding = 8
        val header = maxOf(headerHeight, titleLineHeight)
        var used = padding * 2 + header + 10 + 2 // Body top margin + rounding.
        val defaultHintCost = maxOf(36, smallLineHeight) + 6
        val hintCost = if (hintHeight != null) maxOf(36, hintHeight) + 6 else defaultHintCost
        val hint = hasHint && used + hintCost <= available
        if (hint) used += hintCost
        // An empty/stale/unpublished message wins when no usable hint exists.
        val effectiveSummaryHeight = summaryHeight ?: bodyLineHeight
        val summary = used + effectiveSummaryHeight <= available
        if (summary) used += effectiveSummaryHeight
        val streakCost = (streakHeight ?: bodyLineHeight) + 6
        val wantsStreak = hasStreak && mode != "compact"
        val streak = wantsStreak && summary &&
            used + streakCost <= available
        if (streak) used += streakCost
        val subtitleCost = (subtitleHeight ?: smallLineHeight) + 2
        val subtitle = summary && (!wantsStreak || streak) &&
            used + subtitleCost <= available
        if (subtitle) used += subtitleCost
        val navigationCost = navigationHeight + 8 // Natural bar height + XML top margin.
        val navigation = mode != "compact" && requiredHeaderFits && (!hasHint || hint) && summary &&
            (!wantsStreak || streak) && subtitle && navigationFitsWidth &&
            used + navigationCost <= available
        if (navigation) used += navigationCost
        return Habit(padding, subtitle, summary, streak, hint, navigation, used)
    }
}
