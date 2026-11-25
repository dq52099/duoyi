package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Calls the production policies with the proposed defaulted navigation inputs:
 * navigationHeight = 30 and navigationFitsWidth = true for both todo and habit.
 * Supplied metrics exercise layout admission, not Android font rendering.
 */
class DuoyiWidgetTodoHabitNavigationFitTest {

    @Test
    fun rejectedTodoNavigationWidthPreservesAllNonFooterContentAndSourceSlots() {
        for (mode in listOf("standard", "detailed")) {
            for (secondaryRows in listOf(listOf(true, true), listOf(false, true))) {
                val fits = DuoyiWidgetLayoutPolicy.todo(
                    mode, 250, 500, secondaryRows, 18, 16, 15,
                    navigationHeight = 42, navigationFitsWidth = true,
                )
                val rejected = DuoyiWidgetLayoutPolicy.todo(
                    mode, 250, 500, secondaryRows, 18, 16, 15,
                    navigationHeight = 42, navigationFitsWidth = false,
                )

                assertTrue("fitting footer: $mode, $secondaryRows", fits.showNavigation)
                assertFalse("rejected width: $mode, $secondaryRows", rejected.showNavigation)
                assertTodoContentEquals(fits, rejected)
                assertEquals(48, fits.usedHeight - rejected.usedHeight)
                if (mode == "detailed" && secondaryRows == listOf(false, true)) {
                    assertEquals(listOf(true, false, true), rejected.rows)
                    assertTrue(rejected.showSummary)
                }
            }
        }
    }

    @Test
    fun rejectedHabitNavigationWidthPreservesEveryNonFooterFlag() {
        for (mode in listOf("standard", "detailed")) {
            for (hasHint in listOf(false, true)) {
                for (hasStreak in listOf(false, true)) {
                    val fits = DuoyiWidgetLayoutPolicy.habit(
                        mode, 250, 500, hasHint, hasStreak, 18, 16, 15,
                        navigationHeight = 42, navigationFitsWidth = true,
                    )
                    val rejected = DuoyiWidgetLayoutPolicy.habit(
                        mode, 250, 500, hasHint, hasStreak, 18, 16, 15,
                        navigationHeight = 42, navigationFitsWidth = false,
                    )

                    assertTrue(fits.showNavigation)
                    assertFalse(rejected.showNavigation)
                    assertHabitContentEquals(fits, rejected)
                    assertEquals(hasHint, rejected.showHint)
                    assertEquals(hasStreak, rejected.showStreak)
                    assertTrue(rejected.showSummary)
                    assertTrue(rejected.showSubtitle)
                    assertEquals(50, fits.usedHeight - rejected.usedHeight)
                }
            }
        }
    }

    @Test
    fun todoRequiresTheWhole42DpNavigationBarAndItsMarginAt246And247Dp() {
        val below = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 246, listOf(true, true), 18, 16, 15,
            navigationHeight = 42, navigationFitsWidth = true,
        )
        val exact = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 247, listOf(true, true), 18, 16, 15,
            navigationHeight = 42, navigationFitsWidth = true,
        )

        assertEquals(listOf(true, true, true), below.rows)
        assertTrue(below.showSummary)
        assertFalse(below.showNavigation)
        assertEquals(199, below.usedHeight)
        assertTodoContentEquals(below, exact)
        assertTrue(exact.showNavigation)
        assertEquals(247, exact.usedHeight)
        assertTrue(below.usedHeight <= 246)
        assertTrue(exact.usedHeight <= 247)
    }

    @Test
    fun habitRequiresTheWhole42DpNavigationBarAndItsMarginAt210And211Dp() {
        val below = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 210, true, true, 18, 16, 15,
            navigationHeight = 42, navigationFitsWidth = true,
        )
        val exact = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 211, true, true, 18, 16, 15,
            navigationHeight = 42, navigationFitsWidth = true,
        )

        assertTrue(below.showHint)
        assertTrue(below.showSummary)
        assertTrue(below.showStreak)
        assertTrue(below.showSubtitle)
        assertFalse(below.showNavigation)
        assertEquals(161, below.usedHeight)
        assertHabitContentEquals(below, exact)
        assertTrue(exact.showNavigation)
        assertEquals(211, exact.usedHeight)
        assertTrue(below.usedHeight <= 210)
        assertTrue(exact.usedHeight <= 211)
    }

    @Test
    fun todoDefaultNavigationArgumentsPreserveThe30DpBarThreshold() {
        for (height in listOf(234, 235, 300)) {
            val defaults = DuoyiWidgetLayoutPolicy.todo(
                "detailed", 250, height, listOf(true, true), 18, 16, 15,
            )
            val explicit = DuoyiWidgetLayoutPolicy.todo(
                "detailed", 250, height, listOf(true, true), 18, 16, 15,
                navigationHeight = 30, navigationFitsWidth = true,
            )

            assertEquals(defaults, explicit)
            assertEquals(listOf(true, true, true), defaults.rows)
            assertTrue(defaults.showSummary)
            assertEquals(height >= 235, defaults.showNavigation)
            assertEquals(if (height >= 235) 235 else 199, defaults.usedHeight)
        }
    }

    @Test
    fun habitDefaultNavigationArgumentsPreserveThe30DpBarThreshold() {
        for (height in listOf(198, 199, 300)) {
            val defaults = DuoyiWidgetLayoutPolicy.habit(
                "detailed", 250, height, true, true, 18, 16, 15,
            )
            val explicit = DuoyiWidgetLayoutPolicy.habit(
                "detailed", 250, height, true, true, 18, 16, 15,
                navigationHeight = 30, navigationFitsWidth = true,
            )

            assertEquals(defaults, explicit)
            assertTrue(defaults.showHint)
            assertTrue(defaults.showSummary)
            assertTrue(defaults.showStreak)
            assertTrue(defaults.showSubtitle)
            assertEquals(height >= 199, defaults.showNavigation)
            assertEquals(if (height >= 199) 199 else 161, defaults.usedHeight)
        }
    }

    @Test
    fun compactPoliciesSuppressNavigationRegardlessOfHeightOrWidthAdmission() {
        for (navigationHeight in listOf(30, 42)) {
            for (navigationFitsWidth in listOf(false, true)) {
                val todo = DuoyiWidgetLayoutPolicy.todo(
                    "compact", 250, 500, listOf(true, true), 18, 16, 15,
                    navigationHeight = navigationHeight,
                    navigationFitsWidth = navigationFitsWidth,
                )
                val habit = DuoyiWidgetLayoutPolicy.habit(
                    "compact", 250, 500, true, true, 18, 16, 15,
                    navigationHeight = navigationHeight,
                    navigationFitsWidth = navigationFitsWidth,
                )

                assertFalse(todo.showNavigation)
                assertEquals(listOf(true, false, false), todo.rows)
                assertFalse(todo.showSummary)
                assertEquals(98, todo.usedHeight)
                assertFalse(habit.showNavigation)
                assertTrue(habit.showHint)
                assertTrue(habit.showSummary)
                assertFalse(habit.showStreak)
                assertTrue(habit.showSubtitle)
                assertEquals(139, habit.usedHeight)
            }
        }
    }

    @Test
    fun tallerNavigationCannotEvictAlreadyFittingTodoOrHabitContent() {
        val normalTodo = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 240, listOf(true, true), 18, 16, 15,
            navigationHeight = 30, navigationFitsWidth = true,
        )
        val enlargedTodo = DuoyiWidgetLayoutPolicy.todo(
            "detailed", 250, 240, listOf(true, true), 18, 16, 15,
            navigationHeight = 42, navigationFitsWidth = true,
        )
        val normalHabit = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 205, true, true, 18, 16, 15,
            navigationHeight = 30, navigationFitsWidth = true,
        )
        val enlargedHabit = DuoyiWidgetLayoutPolicy.habit(
            "detailed", 250, 205, true, true, 18, 16, 15,
            navigationHeight = 42, navigationFitsWidth = true,
        )

        assertTrue(normalTodo.showNavigation)
        assertFalse(enlargedTodo.showNavigation)
        assertTodoContentEquals(normalTodo, enlargedTodo)
        assertEquals(listOf(true, true, true), enlargedTodo.rows)
        assertTrue(enlargedTodo.showSummary)
        assertEquals(235, normalTodo.usedHeight)
        assertEquals(199, enlargedTodo.usedHeight)
        assertTrue(normalHabit.showNavigation)
        assertFalse(enlargedHabit.showNavigation)
        assertHabitContentEquals(normalHabit, enlargedHabit)
        assertTrue(enlargedHabit.showHint)
        assertTrue(enlargedHabit.showSummary)
        assertTrue(enlargedHabit.showStreak)
        assertTrue(enlargedHabit.showSubtitle)
        assertEquals(199, normalHabit.usedHeight)
        assertEquals(161, enlargedHabit.usedHeight)
    }

    private fun assertTodoContentEquals(
        expected: DuoyiWidgetLayoutPolicy.Todo,
        actual: DuoyiWidgetLayoutPolicy.Todo,
    ) {
        assertEquals(expected.padding, actual.padding)
        assertEquals(expected.rows, actual.rows)
        assertEquals(expected.showSummary, actual.showSummary)
    }

    private fun assertHabitContentEquals(
        expected: DuoyiWidgetLayoutPolicy.Habit,
        actual: DuoyiWidgetLayoutPolicy.Habit,
    ) {
        assertEquals(expected.padding, actual.padding)
        assertEquals(expected.showSubtitle, actual.showSubtitle)
        assertEquals(expected.showSummary, actual.showSummary)
        assertEquals(expected.showStreak, actual.showStreak)
        assertEquals(expected.showHint, actual.showHint)
    }
}
