package com.duoyi.duoyi

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Test

class DuoyiWidgetCopyLocaleContractTest {
    @Test
    fun generatedNavigationLabelsFollowWidgetLocaleWithoutOverwritingCustomNames() {
        val labels: List<Triple<String, String, (SharedPreferences, Boolean) -> String>> = listOf(
            Triple("nav_todo", "待办", DuoyiWidgetCopy::navTodo),
            Triple("nav_habit", "习惯", DuoyiWidgetCopy::navHabit),
            Triple("nav_calendar", "日历", DuoyiWidgetCopy::navCalendar),
            Triple("nav_focus", "专注", DuoyiWidgetCopy::navFocus),
            Triple("nav_focus", "专注", DuoyiWidgetCopy::navPomodoro),
        )
        val english = mapOf("nav_todo" to "Tasks", "nav_habit" to "Habits", "nav_calendar" to "Calendar", "nav_focus" to "Focus")
        for ((key, zh, read) in labels) {
            val en = english.getValue(key)
            val generated = listOf(zh, en, " $zh ", " $en ", "", "  ", null) +
                if (key == "nav_todo") listOf("To-Do") else emptyList()
            for (saved in generated) {
                for (locale in listOf("zh-CN", "en-US")) {
                    val prefs = DuoyiFrozenWidgetPreferences(mapOf("widget_locale" to locale, key to saved))
                    val isZh = DuoyiWidgetCopy.isZh(prefs)
                    assertEquals("$key: $saved -> $locale", if (isZh) zh else en, read(prefs, isZh))
                }
            }
            for (custom in listOf("我的工作", "My work", "Tasks for work", "Todo", "To Do")) {
                val prefs = DuoyiFrozenWidgetPreferences(mapOf(key to custom))
                assertEquals(custom, read(prefs, true))
                assertEquals(custom, read(prefs, false))
            }
        }
    }

    @Test
    fun allPublishedFocusPhasesAndLegacyLabelsFollowWidgetLocale() {
        val phases = listOf(
            Triple("专注倒计时", "Focus countdown", listOf("倒计时")),
            Triple("正计时专注中", "Focus counting up", listOf("专注正计时", "正计时", "Focus count-up")),
            Triple("短休息倒计时", "Short break countdown", emptyList()),
            Triple("长休息倒计时", "Long break countdown", emptyList()),
        )
        for ((zh, en, legacy) in phases) {
            for (raw in listOf(zh, en) + legacy) {
                assertEquals(en, DuoyiWidgetCopy.localizeTimerLabel(raw, false))
                assertEquals(zh, DuoyiWidgetCopy.localizeTimerLabel(raw, true))
                assertEquals(en, DuoyiWidgetCopy.localizeTimerLabel(DuoyiWidgetCopy.localizeTimerLabel(raw, true), false))
            }
        }
        val custom = "Focus countdown — read chapter 3"
        assertEquals(custom, DuoyiWidgetCopy.localizeTimerLabel(custom, true))
        assertEquals(custom, DuoyiWidgetCopy.localizeTimerLabel(custom, false))
    }

    @Test
    fun unpublishedHabitActionFollowsWidgetLocaleAndKeepsTheEmptyActionHidden() {
        for (raw in listOf(DuoyiWidgetCopy.unpublishedMessage(true), DuoyiWidgetCopy.unpublishedMessage(false))) {
            assertEquals(DuoyiWidgetCopy.unpublishedMessage(true), DuoyiWidgetCopy.habitQuickCheckLabel(raw, true))
            assertEquals(DuoyiWidgetCopy.unpublishedMessage(false), DuoyiWidgetCopy.habitQuickCheckLabel(raw, false))
        }
        assertEquals("", DuoyiWidgetCopy.habitQuickCheckLabel("", true))
        assertEquals("", DuoyiWidgetCopy.habitQuickCheckLabel("", false))
    }

    @Test
    fun focusNarrowActionsDescribeTheActionActuallyBoundInBothLocales() {
        assertEquals("开始专注", DuoyiWidgetCopy.focusQuickStartShort(true, false, false, true))
        assertEquals("Start focus", DuoyiWidgetCopy.focusQuickStartShort(true, false, false, false))
        assertEquals("继续专注", DuoyiWidgetCopy.focusQuickStartShort(true, true, false, true))
        assertEquals("Resume focus", DuoyiWidgetCopy.focusQuickStartShort(true, true, false, false))
        assertEquals("查看计时", DuoyiWidgetCopy.focusQuickStartShort(false, false, true, true))
        assertEquals("View timer", DuoyiWidgetCopy.focusQuickStartShort(false, false, true, false))
        assertEquals("打开专注", DuoyiWidgetCopy.focusQuickStartShort(false, true, false, true))
        assertEquals("Open Focus", DuoyiWidgetCopy.focusQuickStartShort(false, true, false, false))
        assertEquals("分钟", DuoyiWidgetCopy.focusTimerUnit(true))
        assertEquals("min", DuoyiWidgetCopy.focusTimerUnit(false))
    }


    @Test
    fun focusSummaryMapsCurrentAndLegacyPlaceholdersToCurrentCopy() {
        val generatedPlaceholders = listOf(
            "今日还未专注",
            "No focus today yet",
            "No focus sessions today",
        )

        for (isZh in listOf(true, false)) {
            val expected = if (isZh) "今日还未专注" else "No focus today yet"
            for (raw in generatedPlaceholders) {
                assertEquals(expected, DuoyiWidgetCopy.focusSummary(raw, isZh))
            }
            assertEquals(expected, DuoyiWidgetCopy.focusSummary(null, isZh))
            assertEquals(expected, DuoyiWidgetCopy.focusSummary("  ", isZh))
        }
    }

    @Test
    fun focusSummaryPreservesUnknownTextAndUnpublishedCopy() {
        val unknown = "No focus today yet — finish the project plan"
        assertEquals(unknown, DuoyiWidgetCopy.focusSummary(unknown, isZh = true))
        assertEquals(unknown, DuoyiWidgetCopy.focusSummary(unknown, isZh = false))

        for (state in listOf(
            DuoyiWidgetPublicationDocument.State.CLEARED,
            DuoyiWidgetPublicationDocument.State.BLOCKED,
            null,
        )) {
            assertEquals(
                "打开多仪以更新小组件",
                DuoyiWidgetCopy.focusSummary("No focus today yet", true, state),
            )
            assertEquals(
                "Open Duoyi to update this widget",
                DuoyiWidgetCopy.focusSummary("今日还未专注", false, state),
            )
        }
    }

    @Test
    fun calendarMonthSummaryMapsCurrentAndLegacyPlaceholders() {
        val generatedPlaceholders = listOf(
            "本月日期 · 今日已标记",
            "Month view · today is marked",
            "Monthly view · Today marked",
        )

        for (isZh in listOf(true, false)) {
            val expected = if (isZh) "本月日期 · 今日已标记" else "Month view · today is marked"
            for (raw in generatedPlaceholders) {
                assertEquals(expected, DuoyiWidgetCopy.calendarMonthSummary(raw, isZh))
            }
            assertEquals(expected, DuoyiWidgetCopy.calendarMonthSummary(null, isZh))
            assertEquals(expected, DuoyiWidgetCopy.calendarMonthSummary("  ", isZh))
        }

        val authoredLookingText = "Project notes · Month view · today is marked"
        assertEquals(
            authoredLookingText,
            DuoyiWidgetCopy.calendarMonthSummary(authoredLookingText, isZh = true),
        )
        assertEquals(
            authoredLookingText,
            DuoyiWidgetCopy.calendarMonthSummary(authoredLookingText, isZh = false),
        )
    }

    @Test
    fun todayEventSummaryMapsCurrentAndLegacyEmptyPlaceholders() {
        val generatedPlaceholders = listOf(
            "今日没有日程",
            "No events today",
            "No schedule today",
        )

        for (isZh in listOf(true, false)) {
            val expected = if (isZh) "今日没有日程" else "No events today"
            for (raw in generatedPlaceholders) {
                assertEquals(expected, DuoyiWidgetCopy.todayEventSummary(raw, isZh))
            }
            val scheduleTitle = if (isZh) "今日日程" else "Today’s schedule"
            assertEquals(scheduleTitle, DuoyiWidgetCopy.todayEventSummary(null, isZh))
            assertEquals(scheduleTitle, DuoyiWidgetCopy.todayEventSummary("  ", isZh))
        }

        val authoredSummary = "Today: 09:00 Meeting · No events today review"
        assertEquals(authoredSummary, DuoyiWidgetCopy.todayEventSummary(authoredSummary, true))
        assertEquals(authoredSummary, DuoyiWidgetCopy.todayEventSummary(authoredSummary, false))
    }

    @Test
    fun scheduleHighlightMapsDottedAndUndottedCurrentAndLegacyEmptyCopy() {
        val generatedPlaceholders = listOf(
            "今日没有日程",
            "· 今日没有日程",
            "No events today",
            "· No events today",
            "No schedule today",
            "· No schedule today",
        )

        for (isZh in listOf(true, false)) {
            val localizedTodayEvent = if (isZh) "今日没有日程" else "No events today"
            for (raw in generatedPlaceholders) {
                assertEquals(
                    "· $localizedTodayEvent",
                    DuoyiWidgetCopy.scheduleHighlight1(raw, localizedTodayEvent, isZh),
                )
            }
            assertEquals(
                "· $localizedTodayEvent",
                DuoyiWidgetCopy.scheduleHighlight1(null, localizedTodayEvent, isZh),
            )
        }

        val authoredTitle = "· 09:00 Meeting · Review No events today"
        assertEquals(
            authoredTitle,
            DuoyiWidgetCopy.scheduleHighlight1(authoredTitle, "No events today", isZh = true),
        )
        assertEquals(
            authoredTitle,
            DuoyiWidgetCopy.scheduleHighlight1(authoredTitle, "No events today", isZh = false),
        )
    }

    @Test
    fun habitQuickCheckMapsCurrentAndLegacyPrefixesAndPreservesSuffix() {
        val suffixes = listOf(
            "Morning stretch",
            "Check-in: Check in: Morning stretch",
            "Check in: Check-in: Morning stretch",
        )
        val inputPrefixes = listOf("打卡：", "Check in: ", "Check-in: ")

        for (prefix in inputPrefixes) {
            for (suffix in suffixes) {
                assertEquals(
                    "打卡：$suffix",
                    DuoyiWidgetCopy.habitQuickCheckLabel(prefix + suffix, isZh = true),
                )
                assertEquals(
                    "Check in: $suffix",
                    DuoyiWidgetCopy.habitQuickCheckLabel(prefix + suffix, isZh = false),
                )
            }
        }
    }

    @Test
    fun habitQuickCheckKeepsUnknownTextAndExistingBlankBehavior() {
        val unknown = "My reminder says Check in: Morning stretch"
        assertEquals(unknown, DuoyiWidgetCopy.habitQuickCheckLabel(unknown, isZh = true))
        assertEquals(unknown, DuoyiWidgetCopy.habitQuickCheckLabel(unknown, isZh = false))
        assertEquals("", DuoyiWidgetCopy.habitQuickCheckLabel("", isZh = true))
        assertEquals("", DuoyiWidgetCopy.habitQuickCheckLabel("", isZh = false))
        assertEquals(
            "点击进入习惯打卡",
            DuoyiWidgetCopy.habitQuickCheckLabel(null, isZh = true),
        )
        assertEquals(
            "Tap to check in",
            DuoyiWidgetCopy.habitQuickCheckLabel("  ", isZh = false),
        )
    }

    @Test
    fun streakSummaryMapsCurrentLegacyAndDefaultGeneratedPatterns() {
        val generatedPlaceholders = listOf(
            "当前连续 12 天",
            "Current streak: 12 days",
            "连续记录 12 天",
            "· 连续记录 12 天",
            "12-day streak",
            "· 12-day streak",
            "Streak: 12 days",
        )

        for (isZh in listOf(true, false)) {
            val expected = if (isZh) "· 当前连续 12 天" else "· Current streak: 12 days"
            for (raw in generatedPlaceholders) {
                assertEquals(expected, DuoyiWidgetCopy.streakSummary(raw, isZh))
                assertEquals(
                    expected,
                    DuoyiWidgetCopy.streakSummary(
                        DuoyiWidgetCopy.streakSummary(raw, !isZh),
                        isZh,
                    ),
                )
            }
            val zero = if (isZh) "· 当前连续 0 天" else "· Current streak: 0 days"
            assertEquals(zero, DuoyiWidgetCopy.streakSummary(null, isZh))
            assertEquals(zero, DuoyiWidgetCopy.streakSummary("  ", isZh))
        }
    }

    @Test
    fun streakSummaryOnlyRewritesExactGeneratedPatterns() {
        val unknownValues = listOf(
            "My current streak: 12 days",
            "Current streak: 12 days in a row with the team",
            "12-day streak challenge",
            "Reminder · 连续记录 12 天",
            "Streak: 12 days until vacation",
        )

        for (raw in unknownValues) {
            assertEquals(raw, DuoyiWidgetCopy.streakSummary(raw, isZh = true))
            assertEquals(raw, DuoyiWidgetCopy.streakSummary(raw, isZh = false))
        }
    }
}
