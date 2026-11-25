package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetTextListLayoutPolicyTest {

    @Test
    fun textListRespectsRepresentativeSizesAndHeightBudgets() {
        val compact = DuoyiWidgetLayoutPolicy.textList(
            "compact", 110, 110, listOf(true, true), 18, 16, 15, false,
        )
        val standard = DuoyiWidgetLayoutPolicy.textList(
            "standard", 250, 180, listOf(true, true), 18, 16, 15, false,
        )
        val detailedExpanded = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 360, 300, listOf(true, true), 38, 34, 31, false,
        )

        assertEquals(8, compact.padding)
        assertEquals(listOf(true, false, false), compact.rows)
        assertTrue(compact.showSubtitle)
        assertFalse(compact.showNavigation)
        assertEquals(79, compact.usedHeight)

        assertEquals(8, standard.padding)
        assertEquals(listOf(true, true, false), standard.rows)
        assertTrue(standard.showSubtitle)
        assertTrue(standard.showNavigation)
        assertEquals(157, standard.usedHeight)

        assertEquals(8, detailedExpanded.padding)
        assertEquals(listOf(true, true, true), detailedExpanded.rows)
        assertTrue(detailedExpanded.showSubtitle)
        assertTrue(detailedExpanded.showNavigation)
        assertEquals(251, detailedExpanded.usedHeight)

        for ((plan, availableHeight) in listOf(
            compact to 110,
            standard to 180,
            detailedExpanded to 300,
        )) {
            assertEquals(3, plan.rows.size)
            assertTrue(plan.usedHeight <= availableHeight)
        }
    }

    @Test
    fun thirdSlotUsesTheSelectedBodyOrSmallLineHeight() {
        val regularAtThirdThreshold = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 123, listOf(true, true), 18, 16, 15, false,
        )
        val smallAtThirdThreshold = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 123, listOf(true, true), 18, 16, 15, true,
        )
        val regularAtNavigationThreshold = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 178, listOf(true, true), 18, 16, 15, false,
        )
        val smallAtNavigationThreshold = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 178, listOf(true, true), 18, 16, 15, true,
        )

        assertEquals(listOf(true, true, false), regularAtThirdThreshold.rows)
        assertEquals(102, regularAtThirdThreshold.usedHeight)
        assertFalse(regularAtThirdThreshold.showSubtitle)
        assertEquals(listOf(true, true, true), smallAtThirdThreshold.rows)
        assertEquals(123, smallAtThirdThreshold.usedHeight)
        assertFalse(smallAtThirdThreshold.showSubtitle)

        assertEquals(listOf(true, true, true), regularAtNavigationThreshold.rows)
        assertTrue(regularAtNavigationThreshold.showSubtitle)
        assertFalse(regularAtNavigationThreshold.showNavigation)
        assertEquals(141, regularAtNavigationThreshold.usedHeight)
        assertTrue(smallAtNavigationThreshold.showSubtitle)
        assertTrue(smallAtNavigationThreshold.showNavigation)
        assertEquals(178, smallAtNavigationThreshold.usedHeight)
    }

    @Test
    fun emptySlotsDoNotConsumeSpaceOrMoveLaterSourceSlots() {
        val noSecondaryRows = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 500, listOf(false, false), 18, 16, 15, false,
        )
        val onlyThirdSourceRow = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 500, listOf(false, true), 18, 16, 15, false,
        )

        assertEquals(listOf(true, false, false), noSecondaryRows.rows)
        assertEquals(listOf(true, false, true), onlyThirdSourceRow.rows)
        assertEquals(22, onlyThirdSourceRow.usedHeight - noSecondaryRows.usedHeight)
    }

    @Test
    fun modesCapCandidatesBeforeOptionalSubtitleAndNavigation() {
        val compact = textListAtLargeSize("compact")
        val standard = textListAtLargeSize("standard")
        val detailed = textListAtLargeSize("detailed")

        assertEquals(listOf(true, false, false), compact.rows)
        assertTrue(compact.showSubtitle)
        assertFalse(compact.showNavigation)
        assertEquals(97, compact.usedHeight)

        assertEquals(listOf(true, true, false), standard.rows)
        assertTrue(standard.showSubtitle)
        assertTrue(standard.showNavigation)
        assertEquals(157, standard.usedHeight)

        assertEquals(listOf(true, true, true), detailed.rows)
        assertTrue(detailed.showSubtitle)
        assertTrue(detailed.showNavigation)
        assertEquals(179, detailed.usedHeight)
    }

    @Test
    fun unknownModeUsesStandardCandidateLimitAndZeroHeightFallback() {
        val unknown = DuoyiWidgetLayoutPolicy.textList(
            "future-mode", 250, 0, listOf(true, true), 18, 16, 15, false,
        )

        assertEquals(listOf(true, true, false), unknown.rows)
        assertFalse(unknown.showSubtitle)
        assertFalse(unknown.showNavigation)
        assertEquals(102, unknown.usedHeight)
    }

    @Test
    fun nonpositiveHeightUsesModeSpecificFallback() {
        val detailedDefault = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 0, listOf(true, true), 18, 16, 15, false,
        )
        val detailedNegative = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, -20, listOf(true, true), 18, 16, 15, false,
        )
        val detailedExplicit = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 180, listOf(true, true), 18, 16, 15, false,
        )
        val standardDefault = DuoyiWidgetLayoutPolicy.textList(
            "standard", 250, 0, listOf(true, true), 18, 16, 15, false,
        )
        val standardExplicit = DuoyiWidgetLayoutPolicy.textList(
            "standard", 250, 110, listOf(true, true), 18, 16, 15, false,
        )

        assertEquals(detailedExplicit, detailedDefault)
        assertEquals(detailedExplicit, detailedNegative)
        assertEquals(179, detailedDefault.usedHeight)
        assertEquals(standardExplicit, standardDefault)
        assertEquals(102, standardDefault.usedHeight)
    }

    @Test
    fun normalAndExpandedLineHeightsAreIncludedInTheBudget() {
        val normal = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 300, listOf(true, true), 18, 16, 15, false,
        )
        val expanded = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 300, listOf(true, true), 38, 34, 31, false,
        )

        for (plan in listOf(normal, expanded)) {
            assertEquals(listOf(true, true, true), plan.rows)
            assertTrue(plan.showSubtitle)
            assertTrue(plan.showNavigation)
            assertTrue(plan.usedHeight <= 300)
        }
        assertEquals(179, normal.usedHeight)
        assertEquals(251, expanded.usedHeight)
    }

    @Test
    fun visibleContentAndOptionalItemsAreMonotonicAcrossSupportedHeights() {
        val widths = listOf(110, 140, 180, 250)
        val modes = listOf("compact", "standard", "detailed")
        val lineHeights = listOf(Triple(18, 16, 15), Triple(38, 34, 31))
        val sourceRows = listOf(
            listOf(false, false),
            listOf(true, false),
            listOf(false, true),
            listOf(true, true),
        )

        for (width in widths) {
            for (mode in modes) {
                for ((titleLine, bodyLine, smallLine) in lineHeights) {
                    for (thirdLineIsSmall in listOf(false, true)) {
                        for (secondaryRows in sourceRows) {
                            var previous = emptySet<String>()
                            for (height in 110..300) {
                                val plan = DuoyiWidgetLayoutPolicy.textList(
                                    mode,
                                    width,
                                    height,
                                    secondaryRows,
                                    titleLine,
                                    bodyLine,
                                    smallLine,
                                    thirdLineIsSmall,
                                )
                                assertTrue(
                                    "$mode ${width}x$height used ${plan.usedHeight}dp",
                                    plan.usedHeight <= height,
                                )
                                assertEquals(3, plan.rows.size)
                                val visible = visibleItems(plan)
                                assertTrue(
                                    "$mode $width dp lost content at height $height " +
                                        "for sources $secondaryRows and thirdSmall=$thirdLineIsSmall",
                                    visible.containsAll(previous),
                                )
                                if (plan.showNavigation) {
                                    assertTrue(plan.showSubtitle)
                                }
                                if (plan.showSubtitle || plan.showNavigation) {
                                    val modeCandidates = (0 until rowLimit(mode)).filter { slot ->
                                        slot == 0 || secondaryRows.getOrElse(slot - 1) { false }
                                    }
                                    assertTrue(
                                        "optional content preceded a candidate row for " +
                                            "$mode ${width}x$height, sources=$secondaryRows",
                                        modeCandidates.all { plan.rows[it] },
                                    )
                                }
                                previous = visible
                            }
                        }
                    }
                }
            }
        }
    }

    @Test
    fun thirdRowCannotPassAnEarlierPresentRowThatDoesNotFit() {
        val beforeSecondRowFits = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 110, 137, listOf(true, true), 38, 34, 31, true,
        )
        val secondRowFits = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 110, 140, listOf(true, true), 38, 34, 31, true,
        )

        assertEquals(listOf(true, false, false), beforeSecondRowFits.rows)
        assertFalse(beforeSecondRowFits.showSubtitle)
        assertEquals(100, beforeSecondRowFits.usedHeight)
        assertEquals(listOf(true, true, false), secondRowFits.rows)
        assertFalse(secondRowFits.showSubtitle)
        assertEquals(140, secondRowFits.usedHeight)
    }

    @Test
    fun contentThatDoesNotFitIsHiddenBelowTheSupportedHeightRange() {
        val plan = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 1, listOf(true, true), 18, 16, 15, false,
        )

        assertEquals(listOf(false, false, false), plan.rows)
        assertFalse(plan.showSubtitle)
        assertFalse(plan.showNavigation)
        assertEquals(64, plan.usedHeight)
    }

    @Test
    fun measuredNavigationHeightWaitsForItsWholeNaturalLine() {
        fun plan(height: Int) = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, height, listOf(true, true), 18, 16, 15, false,
            navigationHeight = 42,
        )
        val before = plan(190)
        val fits = plan(191)
        assertEquals(listOf(true, true, true), before.rows)
        assertTrue(before.showSubtitle)
        assertFalse(before.showNavigation)
        assertEquals(141, before.usedHeight)
        assertTrue(fits.showNavigation)
        assertEquals(191, fits.usedHeight)
    }

    @Test
    fun insufficientNavigationWidthOnlyHidesNavigation() {
        val fits = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 180, 300, listOf(true, true), 18, 16, 15, false,
            navigationHeight = 42,
        )
        val narrow = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 180, 300, listOf(true, true), 18, 16, 15, false,
            navigationHeight = 42, navigationFitsWidth = false,
        )
        assertEquals(fits.rows, narrow.rows)
        assertTrue(narrow.showSubtitle)
        assertFalse(narrow.showNavigation)
        assertEquals(50, fits.usedHeight - narrow.usedHeight)
    }

    @Test
    fun anniversaryHeaderMatchesTheActualRefreshVisibility() {
        val withRefresh = DuoyiWidgetLayoutPolicy.textList(
            "standard", 110, 110, listOf(true, true), 18, 16, 15, false,
            headerHeight = 36,
        )
        val withoutRefresh = DuoyiWidgetLayoutPolicy.textList(
            "standard", 110, 110, listOf(true, true), 18, 16, 15, false,
            headerHeight = 18,
        )
        assertEquals(listOf(true, true, false), withRefresh.rows)
        assertEquals(102, withRefresh.usedHeight)
        assertFalse(withRefresh.showSubtitle)
        assertTrue(withoutRefresh.showSubtitle)
        assertEquals(101, withoutRefresh.usedHeight)
        assertFalse(withoutRefresh.showNavigation)
    }

    @Test
    fun resolvedAnniversaryRowsKeepModeLimitsAndSafeSingleMessage() {
        val safeMessage = DuoyiWidgetLayoutPolicy.textList(
            "detailed", 250, 300, listOf(false, false), 18, 16, 15, false,
        )
        assertEquals(listOf(true, false, false), safeMessage.rows)
        for ((mode, expectedRows) in listOf(
            "compact" to listOf(true, false, false),
            "standard" to listOf(true, true, false),
            "detailed" to listOf(true, true, true),
        )) {
            val plan = DuoyiWidgetLayoutPolicy.textList(
                mode, 250, 300, listOf(true, true), 18, 16, 15, false,
                headerHeight = 36, navigationHeight = 42,
            )
            assertEquals(expectedRows, plan.rows)
            assertTrue(plan.showSubtitle)
            assertEquals(mode != "compact", plan.showNavigation)
        }
    }

    @Test
    fun measuredPlansKeepContentAcrossHeightAndDensityBoundaries() {
        for (mode in listOf("compact", "standard", "detailed")) {
            for (header in listOf(18, 36, 50)) {
                for (line in listOf(16, 34, 48)) {
                    var previous = emptySet<String>()
                    for (height in 110..360) {
                        val plan = DuoyiWidgetLayoutPolicy.textList(
                            mode, 250, height, listOf(true, true), header, line, line - 1, false,
                            headerHeight = header, navigationHeight = maxOf(30, line),
                        )
                        assertTrue("$mode height=$height", plan.usedHeight <= height)
                        val visible = visibleItems(plan)
                        assertTrue("$mode height=$height lost $previous", visible.containsAll(previous))
                        previous = visible
                    }
                }
            }
        }
    }

    private fun textListAtLargeSize(mode: String) = DuoyiWidgetLayoutPolicy.textList(
        mode, 250, 500, listOf(true, true), 18, 16, 15, false,
    )

    private fun rowLimit(mode: String): Int = when (mode) {
        "compact" -> 1
        "detailed" -> 3
        else -> 2
    }

    private fun visibleItems(plan: DuoyiWidgetLayoutPolicy.TextList): Set<String> =
        mutableSetOf<String>().apply {
            plan.rows.forEachIndexed { index, visible ->
                if (visible) add("row$index")
            }
            if (plan.showSubtitle) add("subtitle")
            if (plan.showNavigation) add("navigation")
        }
}
