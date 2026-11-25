package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetLayoutPolicyTest {

    @Test
    fun todoAndHabitStayWithinRepresentativeSupportedHeightsAtBothTextScales() {
        val sizes = listOf(
            110 to 110,
            140 to 110,
            180 to 110,
            250 to 180,
            320 to 240,
            360 to 300,
        )
        val modes = listOf("compact", "standard", "detailed")
        val lineHeights = listOf(Triple(18, 16, 15), Triple(38, 34, 31))

        for ((width, height) in sizes) {
            for (mode in modes) {
                for ((titleLine, bodyLine, smallLine) in lineHeights) {
                    val todo = DuoyiWidgetLayoutPolicy.todo(
                        mode,
                        width,
                        height,
                        listOf(true, true),
                        titleLine,
                        bodyLine,
                        smallLine,
                    )
                    assertTrue(
                        "todo $mode at ${width}x$height used ${todo.usedHeight}dp",
                        todo.usedHeight <= height,
                    )
                    assertEquals(3, todo.rows.size)

                    val habit = DuoyiWidgetLayoutPolicy.habit(
                        mode,
                        width,
                        height,
                        hasHint = true,
                        hasStreak = true,
                        titleLineHeight = titleLine,
                        bodyLineHeight = bodyLine,
                        smallLineHeight = smallLine,
                    )
                    assertTrue(
                        "habit $mode at ${width}x$height used ${habit.usedHeight}dp",
                        habit.usedHeight <= height,
                    )
                }
            }
        }
    }

    @Test
    fun visibleContentDoesNotShrinkAsSupportedHeightGrows() {
        val widths = listOf(110, 140, 180, 250)
        val modes = listOf("compact", "standard", "detailed")
        val lineHeights = listOf(Triple(18, 16, 15), Triple(38, 34, 31))

        for (width in widths) {
            for (mode in modes) {
                for ((titleLine, bodyLine, smallLine) in lineHeights) {
                    for (hasHint in listOf(false, true)) {
                        var previousTodo = emptySet<String>()
                        var previousHabit = emptySet<String>()
                        for (height in 110..300) {
                            val todo = DuoyiWidgetLayoutPolicy.todo(
                                mode,
                                width,
                                height,
                                listOf(true, true),
                                titleLine,
                                bodyLine,
                                smallLine,
                            )
                            assertTrue(
                                "todo $mode ${width}x$height used ${todo.usedHeight}dp",
                                todo.usedHeight <= height,
                            )
                            val visibleTodo = visibleTodoItems(todo)
                            assertTrue(
                                "todo $mode $width dp lost content at height $height",
                                visibleTodo.containsAll(previousTodo),
                            )
                            previousTodo = visibleTodo

                            val habit = DuoyiWidgetLayoutPolicy.habit(
                                mode,
                                width,
                                height,
                                hasHint,
                                hasStreak = true,
                                titleLineHeight = titleLine,
                                bodyLineHeight = bodyLine,
                                smallLineHeight = smallLine,
                            )
                            assertTrue(
                                "habit $mode ${width}x$height used ${habit.usedHeight}dp",
                                habit.usedHeight <= height,
                            )
                            assertEquals(
                                "hint must fit from the minimum supported height when present",
                                hasHint,
                                habit.showHint,
                            )
                            val visibleHabit = visibleHabitItems(habit)
                            assertTrue(
                                "habit $mode $width dp lost content at height $height",
                                visibleHabit.containsAll(previousHabit),
                            )
                            previousHabit = visibleHabit
                        }
                    }
                }
            }
        }
    }

    @Test
    fun todoReservesWidthSensitiveHeaderHeightAtMinimumSize() {
        val twoCell = DuoyiWidgetLayoutPolicy.todo(
            "standard", 110, 110, emptyList(), 18, 16, 15,
        )
        val threeCell = DuoyiWidgetLayoutPolicy.todo(
            "standard", 152, 110, emptyList(), 18, 16, 15,
        )

        assertEquals(8, twoCell.padding)
        assertEquals(8, threeCell.padding)
        assertEquals(96, twoCell.usedHeight)
        assertEquals(98, threeCell.usedHeight)
        for (width in listOf(140, 149, 150, 151)) {
            assertEquals(96, DuoyiWidgetLayoutPolicy.todo(
                "standard", width, 110, emptyList(), 18, 16, 15,
            ).usedHeight)
        }
    }

    @Test
    fun detailedTodoAt250By180KeepsThreeNormalRowsBeforeOptionalContent() {
        val plan = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 180, listOf(true, true), 18, 16, 15,
        )

        assertEquals(listOf(true, true, true), plan.rows)
        assertFalse(plan.showSummary)
        assertFalse(plan.showNavigation)
        assertEquals(180, plan.usedHeight)
    }

    @Test
    fun todoKeepsTheFirstEmptyStateSlotAndDoesNotMoveLaterSourceSlots() {
        val empty = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 320, 300, emptyList(), 18, 16, 15,
        )
        val slotThreeOnly = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 320, 300, listOf(false, true), 18, 16, 15,
        )

        assertEquals(listOf(true, false, false), empty.rows)
        assertEquals(listOf(true, false, true), slotThreeOnly.rows)
    }

    @Test
    fun anEmptyTodoSourceSlotDoesNotConsumeRowSpace() {
        val noSecondaryRows = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 320, 300, listOf(false, false), 18, 16, 15,
        )
        val onlyThirdSourceRow = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 320, 300, listOf(false, true), 18, 16, 15,
        )

        assertEquals(listOf(true, false, false), noSecondaryRows.rows)
        assertEquals(listOf(true, false, true), onlyThirdSourceRow.rows)
        assertEquals(41, onlyThirdSourceRow.usedHeight - noSecondaryRows.usedHeight)
    }

    @Test
    fun todoModesCapRowsAndOptionalNavigationAndSummary() {
        val compact = todoAtLargeSize("compact")
        val standard = todoAtLargeSize("standard")
        val detailed = todoAtLargeSize("detailed")

        assertEquals(listOf(true, false, false), compact.rows)
        assertFalse(compact.showSummary)
        assertFalse(compact.showNavigation)

        assertEquals(listOf(true, true, false), standard.rows)
        assertFalse(standard.showSummary)
        assertTrue(standard.showNavigation)

        assertEquals(listOf(true, true, true), detailed.rows)
        assertTrue(detailed.showSummary)
        assertTrue(detailed.showNavigation)
    }

    @Test
    fun unknownTodoModeUsesStandardRowLimitAndDefaultHeightForZero() {
        val plan = DuoyiWidgetLayoutPolicy.todo(
            "future-mode", 250, 0, listOf(true, true), 18, 16, 15,
        )

        assertEquals(listOf(true, false, false), plan.rows)
        assertFalse(plan.showSummary)
        assertFalse(plan.showNavigation)
        assertEquals(98, plan.usedHeight)
    }

    @Test
    fun detailedTodoDefaultsZeroHeightTo180Dp() {
        val defaulted = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 0, listOf(true, true), 18, 16, 15,
        )
        val explicit = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 180, listOf(true, true), 18, 16, 15,
        )

        assertEquals(explicit, defaulted)
        assertEquals(180, defaulted.usedHeight)
    }

    @Test
    fun detailedTodoRestoresSummaryAndNavigationWhenAllRowsFitWithRoom() {
        val plan = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 260, listOf(true, true), 18, 16, 15,
        )

        assertEquals(listOf(true, true, true), plan.rows)
        assertTrue(plan.showSummary)
        assertTrue(plan.showNavigation)
        assertEquals(235, plan.usedHeight)
    }

    @Test
    fun todoAccountsForNormalAndExpandedTitleAndSummaryLineHeights() {
        val normal = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 300, listOf(true, true), 18, 16, 15,
        )
        val expanded = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 300, listOf(true, true), 38, 34, 31,
        )

        assertEquals(listOf(true, true, true), normal.rows)
        assertEquals(listOf(true, true, true), expanded.rows)
        assertTrue(normal.showSummary)
        assertTrue(normal.showNavigation)
        assertTrue(expanded.showSummary)
        assertTrue(expanded.showNavigation)
        assertEquals(235, normal.usedHeight)
        assertEquals(253, expanded.usedHeight)
    }

    @Test
    fun todoReservesExplicitHeaderHeightAndPreservesRowSpace() {
        val plan = DuoyiWidgetLayoutPolicy.todo(
            "standard", 152, 120, listOf(true, true), 38, 16, 15,
            headerHeight = 44,
        )
        assertEquals(listOf(true, false, false), plan.rows)
        assertEquals(106, plan.usedHeight)
    }

    @Test
    fun habitAt180By110KeepsAvailableHintAndHidesSummaryWhenItCannotFit() {
        val plan = DuoyiWidgetLayoutPolicy.habit(
            "standard", 180, 110, true, true, 18, 16, 15,
        )

        assertTrue(plan.showHint)
        assertFalse(plan.showSummary)
        assertFalse(plan.showStreak)
        assertFalse(plan.showSubtitle)
        assertFalse(plan.showNavigation)
        assertEquals(106, plan.usedHeight)
    }

    @Test
    fun habitHintPriorityReplacesSummaryAtItsThresholdBelowSupportedHeight() {
        val scalesAndHintThresholds = listOf(
            Triple(18, 16, 15) to 106,
            Triple(38, 34, 31) to 108,
        )

        for ((lineHeights, hintThreshold) in scalesAndHintThresholds) {
            val beforeHintFits = DuoyiWidgetLayoutPolicy.habit(
                "standard",
                180,
                hintThreshold - 1,
                true,
                true,
                lineHeights.first,
                lineHeights.second,
                lineHeights.third,
            )
            val hintFits = DuoyiWidgetLayoutPolicy.habit(
                "standard",
                180,
                hintThreshold,
                true,
                true,
                lineHeights.first,
                lineHeights.second,
                lineHeights.third,
            )

            assertFalse(beforeHintFits.showHint)
            assertTrue(beforeHintFits.showSummary)
            assertTrue(beforeHintFits.usedHeight <= hintThreshold - 1)
            assertTrue(hintFits.showHint)
            assertFalse(hintFits.showSummary)
            assertTrue(hintFits.usedHeight <= hintThreshold)
        }
    }

    @Test
    fun habitWithoutHintPreservesSummaryAndUsesRemainingSubtitleSpace() {
        val plan = DuoyiWidgetLayoutPolicy.habit(
            "standard", 180, 110, false, false, 18, 16, 15,
        )

        assertFalse(plan.showHint)
        assertTrue(plan.showSummary)
        assertFalse(plan.showStreak)
        assertTrue(plan.showSubtitle)
        assertFalse(plan.showNavigation)
        assertEquals(97, plan.usedHeight)
    }

    @Test
    fun habitRestoresSubtitleAndNavigationWhenRemainingBudgetAllowsThem() {
        val withoutNavigationRoom = DuoyiWidgetLayoutPolicy.habit(
            "standard", 250, 180, true, true, 18, 16, 15,
        )
        val withNavigationRoom = DuoyiWidgetLayoutPolicy.habit(
            "standard", 250, 210, true, true, 18, 16, 15,
        )
        val detailedWithRoom = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 210, true, true, 18, 16, 15,
        )

        for (plan in listOf(withoutNavigationRoom, withNavigationRoom, detailedWithRoom)) {
            assertTrue(plan.showHint)
            assertTrue(plan.showSummary)
            assertTrue(plan.showStreak)
            assertTrue(plan.showSubtitle)
        }
        assertFalse(withoutNavigationRoom.showNavigation)
        assertTrue(withNavigationRoom.showNavigation)
        assertTrue(detailedWithRoom.showNavigation)
        assertEquals(161, withoutNavigationRoom.usedHeight)
        assertEquals(199, withNavigationRoom.usedHeight)
        assertEquals(38, withNavigationRoom.usedHeight - withoutNavigationRoom.usedHeight)
    }

    @Test
    fun compactHabitSuppressesStreakAndNavigationEvenWithSpace() {
        val plan = DuoyiWidgetLayoutPolicy.habit(
            "compact", 250, 300, true, true, 18, 16, 15,
        )

        assertTrue(plan.showHint)
        assertTrue(plan.showSummary)
        assertFalse(plan.showStreak)
        assertTrue(plan.showSubtitle)
        assertFalse(plan.showNavigation)
        assertEquals(139, plan.usedHeight)
    }

    @Test
    fun habitZeroHeightUsesDetailedAndFallbackDefaults() {
        val detailed = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 0, true, true, 18, 16, 15,
        )
        val unknown = DuoyiWidgetLayoutPolicy.habit(
            "future-mode", 250, 0, true, true, 18, 16, 15,
        )

        assertTrue(detailed.showHint)
        assertTrue(detailed.showSummary)
        assertTrue(detailed.showStreak)
        assertTrue(detailed.showSubtitle)
        assertFalse(detailed.showNavigation)
        assertEquals(161, detailed.usedHeight)

        assertTrue(unknown.showHint)
        assertFalse(unknown.showSummary)
        assertFalse(unknown.showStreak)
        assertFalse(unknown.showSubtitle)
        assertFalse(unknown.showNavigation)
        assertEquals(106, unknown.usedHeight)
    }

    @Test
    fun habitAccountsForExpandedLineHeightsIncludingSubtitleCost() {
        val normal = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 300, true, true, 18, 16, 15,
        )
        val expanded = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 300, true, true, 38, 34, 31,
        )

        for (plan in listOf(normal, expanded)) {
            assertTrue(plan.showHint)
            assertTrue(plan.showSummary)
            assertTrue(plan.showStreak)
            assertTrue(plan.showSubtitle)
            assertTrue(plan.showNavigation)
        }
        assertEquals(199, normal.usedHeight)
        assertEquals(253, expanded.usedHeight)
    }

    @Test
    fun focusPreservesMainActionInShortWidgetsAcrossModes() {
        for (mode in listOf("compact", "standard", "detailed")) {
            val plan = focusPlan(mode, 110)
            assertTrue(plan.showAction)
            assertTrue(plan.showHeader)
            assertFalse(plan.showMetrics)
            assertFalse(plan.showNavigation)
            assertEquals(96, plan.usedHeight)
        }
        val enlarged = DuoyiWidgetLayoutPolicy.focus(
            "standard", 110, 60, 60, 90, 100, true, true, 40, 40, true)
        assertTrue(enlarged.showAction)
        assertFalse(enlarged.showHeader)
        assertFalse(enlarged.showMetrics)
        assertTrue(enlarged.usedHeight <= 110)
    }

    @Test
    fun timerWidthReservationTracksLiveFormatsWithoutRequiringHoursForShortCountdowns() {
        assertEquals("88:88", DuoyiWidgetLayoutPolicy.timerWidthSample(false, 0))
        assertEquals("88:88", DuoyiWidgetLayoutPolicy.timerWidthSample(false, 3599))
        assertEquals("8:88:88", DuoyiWidgetLayoutPolicy.timerWidthSample(false, 3600))
        assertEquals("88:88:88", DuoyiWidgetLayoutPolicy.timerWidthSample(false, 36000))
        assertEquals("888888:88:88", DuoyiWidgetLayoutPolicy.timerWidthSample(false, Int.MAX_VALUE))
        assertEquals("88:88:88", DuoyiWidgetLayoutPolicy.timerWidthSample(true, 0))
    }

    @Test
    fun calendarNeverAllocatesBlankTrailingWeeks() {
        for (weekCount in 4..6) {
            val plan = DuoyiWidgetLayoutPolicy.calendar(
                "detailed", 500, weekCount - 1, 24, 12, 24, true, 15, true, 14, 24, true,
                weekCount = weekCount)
            assertEquals((0 until weekCount).toList(), plan.weeks)
            assertTrue(plan.showInfo)
            assertTrue(plan.showNavigation)
        }
    }

    @Test
    fun focusMetricBoundariesReserveCompleteTimerAndLabels() {
        assertFalse(focusPlan("standard", 141).showMetrics)
        assertTrue(focusPlan("standard", 142).showMetrics)
        assertFalse(focusPlan("standard", 144).showAllMetrics)
        assertTrue(focusPlan("standard", 145).showAllMetrics)
        assertFalse(focusPlan("standard", 144).summaries.any { it })
        assertFalse(focusPlan("standard", 500, timerFits = false).showMetrics)
        assertFalse(focusPlan("standard", 500, columnsFit = false).showAllMetrics)
        assertTrue(focusPlan("standard", 500, columnsFit = false).showMetrics)
        assertFalse(focusPlan("compact", 500).showAllMetrics)
        assertFalse(focusPlan("compact", 500).showNavigation)
    }

    @Test
    fun focusContentOnlyGrowsAsHeightIncreases() {
        for (mode in listOf("compact", "standard", "detailed")) {
            for (columnsFit in listOf(false, true)) {
                var previous = emptySet<String>()
                for (height in 80..500) {
                    val plan = focusPlan(mode, height, columnsFit = columnsFit)
                    val items = mutableSetOf<String>()
                    if (plan.showHeader) items += "header"
                    if (plan.showAction) items += "action"
                    if (plan.showMetrics) items += "timer"
                    if (plan.showAllMetrics) items += "statistics"
                    plan.summaries.forEachIndexed { i, shown -> if (shown) items += "summary$i" }
                    if (plan.showNavigation) items += "navigation"
                    assertTrue("focus $mode at $height lost $previous", items.containsAll(previous))
                    assertTrue(plan.usedHeight <= height)
                    previous = items
                }
            }
        }
    }

    @Test
    fun calendarKeepsCurrentWeekThenAddsNearestWeeksInVisualOrder() {
        val shortest = calendarPlan("detailed", 82, current = 3)
        assertEquals(listOf(3), shortest.weeks)
        assertEquals(listOf(2, 3), calendarPlan("detailed", 106, current = 3).weeks)
        assertEquals(listOf(2, 3, 4), calendarPlan("detailed", 130, current = 3).weeks)
        for (current in 0..5) {
            assertEquals(listOf(current), calendarPlan("compact", 500, current).weeks)
            assertEquals((0..5).toList(), calendarPlan("detailed", 500, current).weeks)
            assertEquals((maxOf(0, current - 1)..minOf(5, current + 2)).toList(),
                calendarPlan("standard", 500, current).weeks)
        }
    }

    @Test
    fun calendarHasReadableFallbackWhenSevenColumnsOrOneFullWeekCannotFit() {
        val narrow = calendarPlan("detailed", 500, gridFits = false)
        assertTrue(narrow.weeks.isEmpty())
        assertTrue(narrow.showDateFallback)
        assertFalse(narrow.showInfo)
        assertFalse(narrow.showNavigation)
        assertFalse(calendarPlan("standard", 81).weeks.any())
        assertTrue(calendarPlan("standard", 81).showDateFallback)
        assertFalse(calendarPlan("standard", 82).showDateFallback)
        val impossible = DuoyiWidgetLayoutPolicy.calendar(
            "standard", 110, 2, 24, 12, 24, false, 15, false, 14, 24, true)
        assertFalse(impossible.showDateFallback)
        assertTrue(impossible.weeks.isEmpty())
    }

    @Test
    fun calendarDoesNotEvictWeeksOrDetailsAtNextHeightThreshold() {
        for (mode in listOf("compact", "standard", "detailed")) {
            for (current in 0..5) {
                var previous = emptySet<String>()
                for (height in 80..500) {
                    val plan = calendarPlan(mode, height, current)
                    val items = plan.weeks.map { "week$it" }.toMutableSet()
                    if (plan.showInfo) items += "info"
                    if (plan.showNavigation) items += "navigation"
                    assertTrue("calendar $mode at $height lost $previous", items.containsAll(previous))
                    assertTrue(plan.usedHeight <= height)
                    previous = items
                }
            }
        }
    }

    @Test
    fun calendarUsesExpandedNaturalFontHeightsWithoutChangingItsContentOrder() {
        val expanded = DuoyiWidgetLayoutPolicy.calendar(
            "detailed", 180, 3, 42, 38, 50, true, 40, true, 38, 38, true)
        assertEquals(listOf(3), expanded.weeks)
        assertFalse(expanded.showInfo)
        assertFalse(expanded.showNavigation)
        assertTrue(expanded.usedHeight <= 180)
        assertFalse(calendarPlan("detailed", 500, navigationFits = false).showNavigation)
        assertEquals(calendarPlan("standard", 110), calendarPlan("standard", 0))
        assertEquals(focusPlan("standard", 110), focusPlan("standard", 0))
    }

    private fun focusPlan(mode: String, height: Int, timerFits: Boolean = true, columnsFit: Boolean = true) =
        DuoyiWidgetLayoutPolicy.focus(mode, height, 36, 36, 38, 41, timerFits, columnsFit, 15, 30, true)

    private fun calendarPlan(mode: String, height: Int, current: Int = 3,
        gridFits: Boolean = true, navigationFits: Boolean = true) =
        DuoyiWidgetLayoutPolicy.calendar(mode, height, current, 24, 12, 24, gridFits, 15, true, 14, 24, navigationFits)

    private fun todoAtLargeSize(mode: String) = DuoyiWidgetLayoutPolicy.todo(
        mode, 250, 500, listOf(true, true), 18, 16, 15,
    )

    private fun visibleTodoItems(plan: DuoyiWidgetLayoutPolicy.Todo): Set<String> =
        mutableSetOf<String>().apply {
            plan.rows.forEachIndexed { index, visible ->
                if (visible) add("row$index")
            }
            if (plan.showSummary) add("summary")
            if (plan.showNavigation) add("navigation")
        }

    private fun visibleHabitItems(plan: DuoyiWidgetLayoutPolicy.Habit): Set<String> =
        mutableSetOf<String>().apply {
            if (plan.showHint) add("hint")
            if (plan.showSummary) add("summary")
            if (plan.showStreak) add("streak")
            if (plan.showSubtitle) add("subtitle")
            if (plan.showNavigation) add("navigation")
        }
}
