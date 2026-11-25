package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unexecuted acceptance preparation for the two policy gaps in audit 46.
 * Calls the real current todo/habit APIs; no planner or font scaler is copied.
 * All supplied line heights are synthetic dp, not measured Android font curves.
 * Paint/StaticLayout, XML frames, full text, routes and Launcher rendering are
 * outside these pure policy assertions. Main owns guarded execution.
 */
class DuoyiWidgetContentPriorityTest {

    @Test
    fun aPresentPrimaryThatCannotFitPreventsEveryLaterSourceRow() {
        val expected = listOf(
            Triple(125, listOf(false, false, false), 74),
            Triple(126, listOf(false, false, false), 74),
            Triple(127, listOf(false, false, false), 74),
            Triple(128, listOf(true, false, false), 128),
        )
        for (mode in listOf("standard", "detailed")) {
            for ((height, rows, usedHeight) in expected) {
                val plan = DuoyiWidgetLayoutPolicy.todo(
                    mode, 400, height, listOf(true, true), 56, 48, 44,
                    navigationHeight = 40, navigationFitsWidth = true,
                )

                assertEquals("original positions at $mode/$height", rows, plan.rows)
                assertEquals("whole admitted content at $mode/$height", usedHeight, plan.usedHeight)
                assertFalse("summary cannot precede unfitted required rows", plan.showSummary)
                assertFalse("footer cannot precede unfitted required rows", plan.showNavigation)
                assertTrue(plan.usedHeight <= height)
            }
        }
    }

    @Test
    fun anAbsentSecondaryDoesNotBlockTheLaterLiteralSourcePosition() {
        val onlyThird = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 179, listOf(false, true), 56, 48, 44,
            navigationHeight = 40, navigationFitsWidth = true,
        )
        val onlySecond = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 179, listOf(true, false), 56, 48, 44,
            navigationHeight = 40, navigationFitsWidth = true,
        )
        val noSecondary = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 128, emptyList(), 56, 48, 44,
            navigationHeight = 40, navigationFitsWidth = true,
        )

        assertEquals(listOf(true, false, true), onlyThird.rows)
        assertEquals(listOf(true, true, false), onlySecond.rows)
        assertEquals(179, onlyThird.usedHeight)
        assertEquals(179, onlySecond.usedHeight)
        assertEquals(listOf(true, false, false), noSecondary.rows)
        assertEquals(128, noSecondary.usedHeight)
        for (plan in listOf(onlyThird, onlySecond, noSecondary)) {
            assertFalse(plan.showSummary)
            assertFalse(plan.showNavigation)
        }
    }

    @Test
    fun detailedSummaryWinsBeforeTheSmallerFooterAt276278And324Dp() {
        val boundaries = listOf(
            Triple(275, false, 230),
            Triple(276, false, 230),
            Triple(277, false, 230),
            Triple(278, true, 278),
            Triple(323, true, 278),
            Triple(324, true, 324),
        )
        for ((height, showsSummary, usedHeight) in boundaries) {
            val plan = DuoyiWidgetLayoutPolicy.todo(
                "detailed", 400, height, listOf(true, true), 56, 48, 44,
                navigationHeight = 40, navigationFitsWidth = true,
            )

            assertEquals("all original rows at $height", listOf(true, true, true), plan.rows)
            assertEquals("whole summary threshold at $height", showsSummary, plan.showSummary)
            assertEquals("footer waits for wanted summary at $height", height == 324, plan.showNavigation)
            assertEquals("whole admitted budget at $height", usedHeight, plan.usedHeight)
            assertTrue(plan.usedHeight <= height)
        }

        val widthRejected = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 400, 324, listOf(true, true), 56, 48, 44,
            navigationHeight = 40, navigationFitsWidth = false,
        )
        assertEquals(listOf(true, true, true), widthRejected.rows)
        assertTrue(widthRejected.showSummary)
        assertFalse(widthRejected.showNavigation)
        assertEquals(278, widthRejected.usedHeight)
    }

    @Test
    fun standardAndUnknownModesDoNotRequireAnUnwantedSummaryForTheirFooter() {
        for (mode in listOf("standard", "future-mode")) {
            val plan = DuoyiWidgetLayoutPolicy.todo(
                mode, 400, 225, listOf(true, true), 56, 48, 44,
                navigationHeight = 40, navigationFitsWidth = true,
            )

            assertEquals(listOf(true, true, false), plan.rows)
            assertFalse(plan.showSummary)
            assertTrue("unwanted summary cannot block $mode footer", plan.showNavigation)
            assertEquals(225, plan.usedHeight)
        }
    }

    @Test
    fun normalDefaultsRetainHistoricCompleteTodoAndHabitFooterCosts() {
        val todo = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 235, listOf(true, true), 18, 16, 15,
        )
        val explicitTodo = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 235, listOf(true, true), 18, 16, 15,
            navigationHeight = 30, navigationFitsWidth = true,
        )
        val habit = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 199, true, true, 18, 16, 15,
        )
        val explicitHabit = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 199, true, true, 18, 16, 15,
            navigationHeight = 30, navigationFitsWidth = true,
        )

        assertEquals(explicitTodo, todo)
        assertEquals(listOf(true, true, true), todo.rows)
        assertTrue(todo.showSummary)
        assertTrue(todo.showNavigation)
        assertEquals(235, todo.usedHeight)
        assertEquals(explicitHabit, habit)
        assertTrue(habit.showHint)
        assertTrue(habit.showSummary)
        assertTrue(habit.showStreak)
        assertTrue(habit.showSubtitle)
        assertTrue(habit.showNavigation)
        assertEquals(199, habit.usedHeight)
    }

    @Test
    fun compactRetainsItsExistingPrimaryAndHabitFlagsForBothSuppliedProfiles() {
        val profiles = listOf(
            Triple(Triple(18, 16, 15), 30, 98 to 139),
            Triple(Triple(56, 48, 44), 40, 128 to 228),
        )
        for ((lines, navigation, expectedHeights) in profiles) {
            val (title, body, small) = lines
            val (todoHeight, habitHeight) = expectedHeights
            for (fitsWidth in listOf(false, true)) {
                val todo = DuoyiWidgetLayoutPolicy.todo(
                    "compact", 400, 500, listOf(true, true), title, body, small,
                    navigationHeight = navigation, navigationFitsWidth = fitsWidth,
                )
                val habit = DuoyiWidgetLayoutPolicy.habit(
                    "compact", 400, 500, true, true, title, body, small,
                    navigationHeight = navigation, navigationFitsWidth = fitsWidth,
                )

                assertEquals(listOf(true, false, false), todo.rows)
                assertFalse(todo.showSummary)
                assertFalse(todo.showNavigation)
                assertEquals(todoHeight, todo.usedHeight)
                assertTrue(habit.showHint)
                assertTrue(habit.showSummary)
                assertFalse(habit.showStreak)
                assertTrue(habit.showSubtitle)
                assertFalse(habit.showNavigation)
                assertEquals(habitHeight, habit.usedHeight)
            }
        }
    }
}
