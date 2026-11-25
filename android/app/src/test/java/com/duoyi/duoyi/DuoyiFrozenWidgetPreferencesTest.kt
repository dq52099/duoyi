package com.duoyi.duoyi

import java.time.Instant
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiFrozenWidgetPreferencesTest {

    @Test
    fun typedReadsContainsAndAllShareTheSameFrozenSnapshot() {
        val sourceSet = linkedSetOf("one", "two")
        val source = linkedMapOf<String, Any?>(
            "string" to "before",
            "string_set" to sourceSet,
            "int" to 17,
            "long" to 1234567890123L,
            "float" to 0.75f,
            "boolean" to true,
        )
        val prefs = DuoyiFrozenWidgetPreferences(source)

        source["string"] = "after"
        source["int"] = 99
        sourceSet += "three"

        assertEquals("before", prefs.getString("string", "default"))
        assertEquals(setOf("one", "two"), prefs.getStringSet("string_set", null))
        assertEquals(17, prefs.getInt("int", -1))
        assertEquals(1234567890123L, prefs.getLong("long", -1L))
        assertEquals(0.75f, prefs.getFloat("float", -1f))
        assertTrue(prefs.getBoolean("boolean", false))
        source.keys.forEach { assertTrue("missing frozen key: $it", prefs.contains(it)) }
        assertFalse(prefs.contains("missing"))
        assertEquals(
            mapOf(
                "string" to "before",
                "string_set" to setOf("one", "two"),
                "int" to 17,
                "long" to 1234567890123L,
                "float" to 0.75f,
                "boolean" to true,
            ),
            prefs.getAll(),
        )

        assertEquals("fallback", prefs.getString("missing", "fallback"))
        assertEquals(-2, prefs.getInt("missing", -2))
        assertEquals(-3L, prefs.getLong("missing", -3L))
        assertEquals(-4f, prefs.getFloat("missing", -4f))
        assertTrue(prefs.getBoolean("missing", true))
    }

    @Test
    fun wrongTypesThrowClassCastExceptionFromTypedGetters() {
        val prefs = DuoyiFrozenWidgetPreferences(
            mapOf(
                "string" to "text",
                "string_set" to setOf("x"),
                "int" to 1,
                "long" to 2L,
                "float" to 3f,
                "boolean" to true,
            ),
        )

        assertThrows(ClassCastException::class.java) { prefs.getString("int", null) }
        assertThrows(ClassCastException::class.java) { prefs.getStringSet("string", null) }
        assertThrows(ClassCastException::class.java) { prefs.getInt("string", 0) }
        assertThrows(ClassCastException::class.java) { prefs.getLong("int", 0L) }
        assertThrows(ClassCastException::class.java) { prefs.getFloat("int", 0f) }
        assertThrows(ClassCastException::class.java) { prefs.getBoolean("int", false) }
    }

    @Test
    fun stringSetsAreCopiedAndImmutableAndMissingDefaultsAreCopied() {
        val sourceSet = linkedSetOf("en", "zh")
        val prefs = DuoyiFrozenWidgetPreferences(mapOf("locales" to sourceSet))
        sourceSet += "fr"

        val exposed = prefs.getStringSet("locales", null)!!
        assertEquals(setOf("en", "zh"), exposed)
        assertThrows(UnsupportedOperationException::class.java) { exposed.add("fr") }
        assertEquals(setOf("en", "zh"), prefs.getStringSet("locales", null))

        val default = linkedSetOf("default")
        val copiedDefault = prefs.getStringSet("missing", default)!!
        copiedDefault += "caller-change"
        assertEquals(setOf("default"), default)
        assertEquals(setOf("default"), prefs.getStringSet("missing", default))
    }

    @Test
    fun editIsRejected() {
        val prefs = DuoyiFrozenWidgetPreferences(emptyMap<String, Any?>())

        assertThrows(UnsupportedOperationException::class.java) { prefs.edit() }
    }

    @Test
    fun freshDisplayProjectionPreservesContentAndSessionData() {
        val values = baseValues().apply {
            put("todo_count", 8)
            put("todo_top3_1", "Fresh task")
            put("todo_top3_1_id", "task-42")
            put("widget_theme_brand_id", "brand-7")
            put("widget_theme_card_skin_id", "skin-3")
            put("widget_locale", "en-US")
            put("widget_display_mode_3", "detailed")
            put("next_focus_label", "Upcoming session")
        }
        val core = core(values = values)

        assertTrue(core.fresh)
        val display = DuoyiWidgetRenderFrame.displayValues(core)

        assertEquals("Fresh task", display["todo_top3_1"])
        assertEquals("task-42", display["todo_top3_1_id"])
        assertEquals(8, display["todo_count"])
        assertEquals("brand-7", display["widget_theme_brand_id"])
        assertEquals("skin-3", display["widget_theme_card_skin_id"])
        assertEquals("en", display["widget_locale"])
        assertEquals("detailed", display["widget_display_mode_3"])
        assertEquals("Upcoming session", display["next_focus_label"])
        assertEquals("en-US", core.rawValues["widget_locale"])
    }

    @Test
    fun staleProjectionClearsBusinessEntityIdsButKeepsThemeLocaleAndMode() {
        val entityIds = listOf(
            "todo_top3_1_id",
            "goal_highlight_1_id",
            "schedule_highlight_1_id",
            "course_highlight_1_id",
            "note_highlight_1_id",
            "diary_highlight_1_id",
            "anniversary_highlight_1_id",
            "memorial_highlight_1_id",
            "habit_quick_check_id",
        )
        val values = baseValues(day = "2024-06-14", language = "zh-CN").apply {
            entityIds.forEach { put(it, "business-$it") }
            put("widget_theme_brand_id", "brand-7")
            put("widget_theme_card_skin_id", "skin-3")
            put("widget_display_mode", "compact")
            put("widget_display_mode_3", "detailed")
        }
        val display = DuoyiWidgetRenderFrame.displayValues(
            core(
                values = values,
                options = DuoyiWidgetFrameOptions(minWidth = 300, minHeight = 200),
            ),
        )

        entityIds.forEach { assertEquals("", display[it]) }
        assertEquals("brand-7", display["widget_theme_brand_id"])
        assertEquals("skin-3", display["widget_theme_card_skin_id"])
        assertEquals("zh", display["widget_locale"])
        assertEquals("detailed", display["widget_display_mode_3"])
        assertEquals("compact", display["widget_display_mode"])
    }

    @Test
    fun calendarMonthTitleUsesSuppliedCalendarZoneForBothLanguagesAndWidths() {
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"), Locale.US).apply {
            timeInMillis = Instant.parse("2024-02-29T16:30:00Z").toEpochMilli()
        }
        val previousDefaultZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))

            listOf(false, true).forEach { compact ->
                val english = DuoyiWidgetCopy.calendarMonthTitle(calendar, compact, isZh = false)
                val chinese = DuoyiWidgetCopy.calendarMonthTitle(calendar, compact, isZh = true)
                assertTrue("English title should use March: $english", english.contains("Mar"))
                assertTrue("Chinese title should use March: $chinese", chinese.contains("3月"))
            }
        } finally {
            TimeZone.setDefault(previousDefaultZone)
        }
    }

    @Test
    fun staleDailyContentAndEveryVisibleCounterUseSafeBilingualPlaceholders() {
        listOf("zh" to true, "en" to false).forEach { (language, isZh) ->
            val values = baseValues(day = "2024-06-14", language = language).apply {
                dailyTextKeys().forEach { put(it, "private-old-content:$it") }
                listOf(
                    "todo_count",
                    "todo_top3_count",
                    "habit_percent",
                    "habit_active_count",
                    "pomodoro_today",
                    "focus_minutes_today",
                ).forEach { put(it, 99) }
            }
            val display = DuoyiWidgetRenderFrame.displayValues(core(values = values))

            assertEquals(expectedStaleText(isZh), dailyTextKeys().associateWith { display[it] as String })
            listOf(
                "todo_count",
                "todo_top3_count",
                "habit_percent",
                "habit_active_count",
                "pomodoro_today",
                "focus_minutes_today",
            ).forEach { assertEquals("counter should be hidden: $it", 0, display[it]) }
            assertTrue(display.values.none { it == "private-old-content" })
            dailyTextKeys().forEach { assertFalse(display[it] == "private-old-content:$it") }
        }
    }

    @Test
    fun noSessionHidesEveryFocusTimerKeyAndReplacesOldNextFocusLabel() {
        val timerValues = linkedMapOf<String, Any?>(
            "focus_timer_running" to true,
            "focus_timer_count_up" to false,
            "focus_timer_ends_at_millis" to 1718452805000L,
            "focus_timer_remaining_seconds" to 300,
            "focus_timer_progress" to 0.4f,
            "focus_timer_label" to "private old account timer",
            "next_focus_label" to "private old account label",
        )
        val values = baseValues(nonce = "").apply { putAll(timerValues) }
        val display = DuoyiWidgetRenderFrame.displayValues(core(values = values))
        val prefs = DuoyiFrozenWidgetPreferences(display)

        assertTrue(display.keys.none { it.startsWith("focus_timer_") })
        timerValues.keys.filter { it.startsWith("focus_timer_") }.forEach { key ->
            assertFalse("$key must not appear in contains", prefs.contains(key))
        }
        assertEquals("25-min focus", display["next_focus_label"])
        assertFalse(display["next_focus_label"].toString().contains("private old account"))

        val all = prefs.getAll()
        timerValues.keys.filter { it.startsWith("focus_timer_") }.forEach { key ->
            assertFalse("$key must not appear in all", all.containsKey(key))
        }
        assertFalse(prefs.getBoolean("focus_timer_running", false))
        assertTrue(prefs.getBoolean("focus_timer_count_up", true))
        assertEquals(-10L, prefs.getLong("focus_timer_ends_at_millis", -10L))
        assertEquals(-20, prefs.getInt("focus_timer_remaining_seconds", -20))
        assertEquals(-0.5f, prefs.getFloat("focus_timer_progress", -0.5f))
        assertEquals("fallback", prefs.getString("focus_timer_label", "fallback"))
    }

    @Test
    fun trustedButDailyStaleProjectionRetainsAbsoluteTimerFields() {
        val start = 1718452000000L
        val end = 1718452900000L
        val values = baseValues(day = "2024-06-14").apply {
            put("focus_timer_running", true)
            put("focus_timer_started_at_millis", start)
            put("focus_timer_ends_at_millis", end)
            put("focus_timer_label", "Trusted old timer")
        }
        val projection = DuoyiWidgetRenderFrame.displayValues(core(values = values))
        val prefs = DuoyiFrozenWidgetPreferences(projection)

        assertTrue(projection.containsKey("focus_timer_started_at_millis"))
        assertTrue(projection.containsKey("focus_timer_ends_at_millis"))
        assertEquals(start, projection["focus_timer_started_at_millis"])
        assertEquals(end, projection["focus_timer_ends_at_millis"])
        assertTrue(prefs.getBoolean("focus_timer_running", false))
        assertEquals(start, prefs.getLong("focus_timer_started_at_millis", -1L))
        assertEquals(end, prefs.getLong("focus_timer_ends_at_millis", -1L))
        assertEquals("Trusted old timer", prefs.getString("focus_timer_label", null))
    }

    @Test
    fun unpublishedStatesClearedBlockedAndAbsentUseNeutralPromptAcrossBothLanguages() {
        val states = listOf("cleared", "blocked", "invalid_wire", null)
        val languages = listOf("zh" to true, "en" to false)

        for (stateWire in states) {
            for ((language, isZh) in languages) {
                val values = linkedMapOf<String, Any?>(
                    "widget_snapshot_day" to "2024-06-15",
                    "widget_snapshot_utc_offset_minutes" to 0,
                    "widget_account_nonce" to "session-nonce",
                    "widget_locale" to language,
                ).apply {
                    if (stateWire != null) {
                        put("widget_publication_state", stateWire)
                    }
                    dailyTextKeys().forEach { put(it, "private-old-content:$it") }
                    listOf(
                        "todo_count",
                        "todo_top3_count",
                        "habit_percent",
                        "habit_active_count",
                        "pomodoro_today",
                        "focus_minutes_today",
                    ).forEach { put(it, 42) }
                    listOf(
                        "todo_top3_1_id",
                        "todo_top3_2_id",
                        "habit_quick_check_id",
                        "goal_highlight_1_id",
                    ).forEach { put(it, "entity-$it") }
                    put("focus_timer_running", true)
                    put("focus_timer_ends_at_millis", 1718452900000L)
                    put("next_focus_label", "Old account plan 45-min")
                }

                val frameCore = core(
                    values = values,
                    systemLocaleTag = if (isZh) "zh-CN" else "en-US",
                )
                val display = DuoyiWidgetRenderFrame.displayValues(frameCore)
                val prefs = DuoyiFrozenWidgetPreferences(display)

                // 1. Verify publicationState is non-published
                val expectedDocState = when (stateWire) {
                    "cleared" -> DuoyiWidgetPublicationDocument.State.CLEARED
                    "blocked" -> DuoyiWidgetPublicationDocument.State.BLOCKED
                    else -> null
                }
                assertEquals(expectedDocState, frameCore.publicationState)
                assertFalse("Unpublished frame must not be trusted", frameCore.sessionTrusted)
                assertFalse("Unpublished frame must not be fresh", frameCore.fresh)

                // 2. Daily texts match neutral prompt for primary rows and empty for secondary
                val expectedTexts = expectedUnpublishedText(isZh)
                assertEquals(
                    "State $stateWire ($language) daily texts mismatch",
                    expectedTexts,
                    dailyTextKeys().associateWith { display[it] as String },
                )

                // 3. Counters are zeroed
                listOf(
                    "todo_count",
                    "todo_top3_count",
                    "habit_percent",
                    "habit_active_count",
                    "pomodoro_today",
                    "focus_minutes_today",
                ).forEach { key ->
                    assertEquals("Counter $key should be 0", 0, display[key])
                }

                // 4. Entity IDs are cleared
                listOf(
                    "todo_top3_1_id",
                    "todo_top3_2_id",
                    "habit_quick_check_id",
                    "goal_highlight_1_id",
                ).forEach { key ->
                    assertEquals("Entity ID $key should be blank", "", display[key])
                }

                // 5. Timers stripped and safe next focus label
                assertTrue(display.keys.none { it.startsWith("focus_timer_") })
                assertEquals(
                    if (isZh) "25 分钟专注" else "25-min focus",
                    display["next_focus_label"],
                )

                // 6. No private account / business data leaked in daily display slots
                dailyTextKeys().forEach { key ->
                    assertFalse(display[key] == "private-old-content:$key")
                }

                // 7. Refresh accessibility matches neutral prompt
                val neutralPrompt = if (isZh) "打开多仪以更新小组件" else "Open Duoyi to update this widget"
                assertEquals(
                    neutralPrompt,
                    DuoyiWidgetCopy.refreshContentDescription(
                        isFresh = frameCore.fresh,
                        isZh = isZh,
                        publicationState = frameCore.publicationState,
                    ),
                )

                // 8. Focus summary matches neutral prompt
                assertEquals(
                    neutralPrompt,
                    DuoyiWidgetCopy.focusSummary(
                        raw = prefs.getString("focus_summary", null),
                        isZh = isZh,
                        publicationState = frameCore.publicationState,
                    ),
                )
                assertEquals(
                    neutralPrompt,
                    DuoyiWidgetCopy.focusSummary(
                        raw = prefs.getString("focus_summary", null),
                        isZh = isZh,
                    ),
                )

                // 9. Raw values in core were not modified
                assertEquals(42, frameCore.rawValues["todo_count"])
                assertEquals("entity-todo_top3_1_id", frameCore.rawValues["todo_top3_1_id"])
                assertEquals("private-old-content:habit_summary", frameCore.rawValues["habit_summary"])
            }
        }
    }

    @Test
    fun publishedStaleVsPublishedFreshVsUnpublishedDistinction() {
        listOf("zh" to true, "en" to false).forEach { (language, isZh) ->
            val neutralPrompt = if (isZh) "打开多仪以更新小组件" else "Open Duoyi to update this widget"
            val normalEmptyFocus = if (isZh) "今日还未专注" else "No focus today yet"
            val staleFocus = if (isZh) "今日数据待刷新" else "Today’s data pending refresh"

            // A. Published Fresh: retains real content; ordinary empty content is NOT treated as unpublished
            val freshValues = baseValues(day = "2024-06-15", language = language).apply {
                put("todo_top3_1", "Real active task")
                put("focus_summary", "") // ordinary empty focus session
            }
            val freshCore = core(values = freshValues, systemLocaleTag = if (isZh) "zh-CN" else "en-US")
            assertTrue("Fresh core must be fresh", freshCore.fresh)
            assertEquals(DuoyiWidgetPublicationDocument.State.PUBLISHED, freshCore.publicationState)
            val freshDisplay = DuoyiWidgetRenderFrame.displayValues(freshCore)
            val freshPrefs = DuoyiFrozenWidgetPreferences(freshDisplay)

            assertEquals("Real active task", freshDisplay["todo_top3_1"])
            assertEquals(
                normalEmptyFocus,
                DuoyiWidgetCopy.focusSummary(freshPrefs.getString("focus_summary", null), isZh, freshCore.publicationState),
            )
            assertEquals(
                normalEmptyFocus,
                DuoyiWidgetCopy.focusSummary(freshPrefs.getString("focus_summary", null), isZh),
            )
            assertEquals(
                if (isZh) "刷新小组件" else "Refresh widgets",
                DuoyiWidgetCopy.refreshContentDescription(freshCore.fresh, isZh, freshCore.publicationState),
            )

            // B. Published Stale (day mismatch): retains pending-refresh stale texts
            val staleValues = baseValues(day = "2024-06-14", language = language).apply {
                dailyTextKeys().forEach { put(it, "old-business-content:$it") }
            }
            val staleCore = core(values = staleValues, systemLocaleTag = if (isZh) "zh-CN" else "en-US")
            assertFalse("Stale core must not be fresh", staleCore.fresh)
            assertEquals(DuoyiWidgetPublicationDocument.State.PUBLISHED, staleCore.publicationState)
            val staleDisplay = DuoyiWidgetRenderFrame.displayValues(staleCore)
            val stalePrefs = DuoyiFrozenWidgetPreferences(staleDisplay)

            assertEquals(expectedStaleText(isZh), dailyTextKeys().associateWith { staleDisplay[it] as String })
            assertEquals(
                staleFocus,
                DuoyiWidgetCopy.focusSummary(stalePrefs.getString("focus_summary", null), isZh, staleCore.publicationState),
            )
            assertEquals(
                staleFocus,
                DuoyiWidgetCopy.focusSummary(stalePrefs.getString("focus_summary", null), isZh),
            )
            assertEquals(
                if (isZh) "数据待刷新，点按更新" else "Data pending refresh, tap to update",
                DuoyiWidgetCopy.refreshContentDescription(staleCore.fresh, isZh, staleCore.publicationState),
            )

            // C. Unpublished (cleared): uses neutral prompt
            val unpubValues = baseValues(day = "2024-06-15", language = language).apply {
                put("widget_publication_state", "cleared")
                dailyTextKeys().forEach { put(it, "old-business-content:$it") }
            }
            val unpubCore = core(values = unpubValues, systemLocaleTag = if (isZh) "zh-CN" else "en-US")
            assertFalse("Unpublished core must not be fresh", unpubCore.fresh)
            assertEquals(DuoyiWidgetPublicationDocument.State.CLEARED, unpubCore.publicationState)
            val unpubDisplay = DuoyiWidgetRenderFrame.displayValues(unpubCore)
            val unpubPrefs = DuoyiFrozenWidgetPreferences(unpubDisplay)

            assertEquals(expectedUnpublishedText(isZh), dailyTextKeys().associateWith { unpubDisplay[it] as String })
            assertEquals(
                neutralPrompt,
                DuoyiWidgetCopy.focusSummary(unpubPrefs.getString("focus_summary", null), isZh, unpubCore.publicationState),
            )
            assertEquals(
                neutralPrompt,
                DuoyiWidgetCopy.focusSummary(unpubPrefs.getString("focus_summary", null), isZh),
            )
            assertEquals(
                neutralPrompt,
                DuoyiWidgetCopy.refreshContentDescription(unpubCore.fresh, isZh, unpubCore.publicationState),
            )
        }
    }

    private fun core(
        values: Map<String, *>,
        instant: String = "2024-06-15T12:00:00Z",
        zone: String = "UTC",
        elapsedMillis: Long = 10_000L,
        options: DuoyiWidgetFrameOptions = DuoyiWidgetFrameOptions(),
        widgetId: Int = 3,
        systemLocaleTag: String = "en-US",
    ): DuoyiWidgetFrameCore = DuoyiWidgetFrameCore(
        values = values,
        clock = DuoyiWidgetFrameClock(
            wallMillis = java.time.Instant.parse(instant).toEpochMilli(),
            elapsedMillis = elapsedMillis,
            zone = java.time.ZoneId.of(zone),
        ),
        options = options,
        widgetId = widgetId,
        systemLocaleTag = systemLocaleTag,
    )

    private fun baseValues(
        day: String = "2024-06-15",
        offset: Int = 0,
        nonce: String = "session-nonce",
        language: String = "en",
    ): LinkedHashMap<String, Any?> = linkedMapOf(
        "widget_publication_state" to "published",
        "widget_snapshot_day" to day,
        "widget_snapshot_utc_offset_minutes" to offset,
        "widget_account_nonce" to nonce,
        "widget_locale" to language,
    )

    private fun dailyTextKeys(): List<String> = buildList {
        addAll(
            listOf(
                "habit_summary",
                "streak_summary",
                "habit_quick_check_label",
                "focus_summary",
                "today_event_summary",
                "calendar_month_summary",
            ),
        )
        listOf(
            "todo_top3",
            "goal_highlight",
            "schedule_highlight",
            "course_highlight",
            "note_highlight",
            "diary_highlight",
            "anniversary_highlight",
            "memorial_highlight",
        ).forEach { prefix ->
            for (slot in 1..3) add("${prefix}_$slot")
        }
    }

    private fun expectedStaleText(isZh: Boolean): Map<String, String> {
        val refresh = if (isZh) "数据待刷新，打开多仪更新" else "Data pending refresh, open Duoyi to update"
        val pending = if (isZh) "数据待刷新" else "Data pending refresh"
        val expected = linkedMapOf(
            "habit_summary" to refresh,
            "streak_summary" to "",
            "habit_quick_check_label" to if (isZh) "打开习惯刷新" else "Open habits to refresh",
            "focus_summary" to if (isZh) "今日数据待刷新" else "Today’s data pending refresh",
            "today_event_summary" to if (isZh) "今日数据待刷新" else "Today’s data pending refresh",
            "calendar_month_summary" to if (isZh) "月历 · 安排日程" else "Month view · Plan your day",
        )
        listOf(
            "todo_top3" to refresh,
            "goal_highlight" to pending,
            "schedule_highlight" to if (isZh) "今日日程待刷新" else "Today’s schedule pending refresh",
            "course_highlight" to if (isZh) "今日课程待刷新" else "Today’s timetable pending refresh",
            "note_highlight" to pending,
            "diary_highlight" to pending,
            "anniversary_highlight" to if (isZh) "日期数据待刷新" else "Dates pending refresh",
            "memorial_highlight" to if (isZh) "日期数据待刷新" else "Dates pending refresh",
        ).forEach { (prefix, firstSlot) ->
            for (slot in 1..3) expected["${prefix}_$slot"] = if (slot == 1) firstSlot else ""
        }
        return expected
    }

    private fun expectedUnpublishedText(isZh: Boolean): Map<String, String> {
        val message = if (isZh) "打开多仪以更新小组件" else "Open Duoyi to update this widget"
        val expected = linkedMapOf(
            "habit_summary" to message,
            "streak_summary" to "",
            "habit_quick_check_label" to "",
            "focus_summary" to message,
            "today_event_summary" to message,
            "calendar_month_summary" to if (isZh) "月历 · 安排日程" else "Month view · Plan your day",
        )
        listOf(
            "todo_top3" to message,
            "goal_highlight" to message,
            "schedule_highlight" to message,
            "course_highlight" to message,
            "note_highlight" to message,
            "diary_highlight" to message,
            "anniversary_highlight" to message,
            "memorial_highlight" to message,
        ).forEach { (prefix, firstSlot) ->
            for (slot in 1..3) expected["${prefix}_$slot"] = if (slot == 1) firstSlot else ""
        }
        return expected
    }
}
