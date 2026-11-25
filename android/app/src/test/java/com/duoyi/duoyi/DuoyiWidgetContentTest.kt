package com.duoyi.duoyi

import java.time.Instant
import java.util.Date
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetContentTest {

    @Test
    fun anniversaryItemsDeduplicateA1AndM3ByIdentityAndKeepTheirTargetsPaired() {
        val items = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = listOf(
                slot("a1", "Anniversary A1", "A/M1"),
                slot("a1-duplicate", "Duplicate A1", "duoyi://anniversary/A%2FM1"),
                slot("a2", "Anniversary M3", "M3"),
                slot("a2-duplicate", "Duplicate M3", "duoyi://anniversary/M3"),
            ),
            isFresh = true,
            isZh = false,
        )

        assertEquals(listOf("a1", "a2"), items.map { it.sourceKey })
        assertEquals(listOf("Anniversary A1", "Anniversary M3"), items.map { it.text })
        assertEquals(listOf("A/M1", "M3"), items.map { it.identity })
        assertEquals(
            listOf("duoyi://anniversary/A%2FM1", "duoyi://anniversary/M3"),
            items.map { it.target },
        )
    }

    @Test
    fun anniversaryItemsKeepEqualTextWhenTheirIdsDiffer() {
        val items = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = listOf(
                slot("one", "Same memorial text", "memorial-1"),
                slot("two", "Same memorial text", "memorial-2"),
            ),
            isFresh = true,
            isZh = false,
        )

        assertEquals(2, items.size)
        assertEquals(listOf("Same memorial text", "Same memorial text"), items.map { it.text })
        assertEquals(listOf("memorial-1", "memorial-2"), items.map { it.identity })
        assertEquals(
            listOf("duoyi://anniversary/memorial-1", "duoyi://anniversary/memorial-2"),
            items.map { it.target },
        )
    }

    @Test
    fun memorialOnlyAndMixedPlaceholderSlotsUseFallbackWithoutDroppingRealIds() {
        val memorialOnly = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = listOf(slot("memorial", "纪念日 · 暂无近期纪念日", null)),
            isFresh = true,
            isZh = true,
        )
        assertFallback(memorialOnly, "· 暂无近期纪念日")

        val mixed = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = listOf(
                slot("empty", "· 暂无近期纪念日", null),
                slot("real", "Birthday", "birthday-42"),
                slot("english-empty", "No upcoming anniversaries", "  "),
            ),
            isFresh = true,
            isZh = false,
        )
        assertEquals(1, mixed.size)
        assertEquals("real", mixed.single().sourceKey)
        assertEquals("Birthday", mixed.single().text)
        assertEquals("duoyi://anniversary/birthday-42", mixed.single().target)
        assertEquals("birthday-42", mixed.single().identity)
    }

    @Test
    fun legacyAnniversariesWithoutIdsStayDistinctAndBulletTextWithAnIdIsKept() {
        val items = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = listOf(
                slot("legacy-1", "Legacy anniversary", null),
                slot("legacy-2", "Legacy anniversary", " "),
                slot("bullet-real", "· 暂无近期纪念日", "memorial-real-id"),
            ),
            isFresh = true,
            isZh = true,
        )

        assertEquals(listOf("legacy-1", "legacy-2", "bullet-real"), items.map { it.sourceKey })
        assertEquals(listOf(null, null, "memorial-real-id"), items.map { it.identity })
        assertEquals("· 暂无近期纪念日", items.last().text)
        assertEquals("duoyi://anniversary/memorial-real-id", items.last().target)
    }

    @Test
    fun knownEmptyAnniversaryPlaceholdersAreRecognizedWithWhitespaceAndBullet() {
        listOf(
            "暂无近期纪念日",
            "No upcoming anniversaries",
            "暂无纪念日",
            "纪念日 · 暂无近期纪念日",
            "Anniversaries · No upcoming anniversaries",
            "  · 暂无纪念日  ",
        ).forEach { text ->
            assertTrue("Expected placeholder: $text", DuoyiWidgetContent.isKnownAnniversaryEmptyPlaceholder(text))
        }
        assertFalse(DuoyiWidgetContent.isKnownAnniversaryEmptyPlaceholder("A real anniversary"))
    }

    @Test
    fun emptyAnniversaryResultUsesLocalizedBulletFallback() {
        val zh = DuoyiWidgetContent.resolveAnniversaryItems(emptyList(), isFresh = true, isZh = true)
        val en = DuoyiWidgetContent.resolveAnniversaryItems(emptyList(), isFresh = true, isZh = false)

        assertFallback(zh, "· 暂无近期纪念日")
        assertFallback(en, "· No upcoming anniversaries")
    }

    @Test
    fun staleAnniversaryDataBecomesExactlyOneLocalizedRefreshHint() {
        val slots = listOf(
            slot("one", "Old anniversary", "old-1"),
            slot("two", "Old anniversary", "old-2"),
        )

        val zh = DuoyiWidgetContent.resolveAnniversaryItems(slots, isFresh = false, isZh = true)
        val en = DuoyiWidgetContent.resolveAnniversaryItems(slots, isFresh = false, isZh = false)

        assertEquals(1, zh.size)
        assertEquals("anniversary_highlight_1", zh.single().sourceKey)
        assertEquals("日期数据待刷新", zh.single().text)
        assertEquals("duoyi://anniversary", zh.single().target)
        assertNull(zh.single().identity)
        assertEquals(1, en.size)
        assertEquals("Dates pending refresh", en.single().text)
        assertEquals("duoyi://anniversary", en.single().target)
        assertNull(en.single().identity)
    }

    @Test
    fun anniversaryTargetCanonicalEncodingRoundTripsPlainIdsExactly() {
        val plainId = "A/M1 中文 +plus"
        val fromPlain = DuoyiWidgetContent.parseAnniversaryTarget(plainId)
        val fromCanonical = DuoyiWidgetContent.parseAnniversaryTarget(fromPlain.first)

        assertEquals(
            "duoyi://anniversary/A%2FM1%20%E4%B8%AD%E6%96%87%20%2Bplus",
            fromPlain.first,
        )
        assertEquals(plainId, fromPlain.second)
        assertEquals(fromPlain, fromCanonical)
        assertEquals(plainId, fromCanonical.second)

        val plainPlus = DuoyiWidgetContent.parseAnniversaryTarget("A+B")
        val canonicalPlus = DuoyiWidgetContent.parseAnniversaryTarget("duoyi://anniversary/A%2BB")
        assertEquals("duoyi://anniversary/A%2BB", plainPlus.first)
        assertEquals("A+B", plainPlus.second)
        assertEquals(plainPlus, canonicalPlus)

        val canonicalLiteralPlus = DuoyiWidgetContent.parseAnniversaryTarget("duoyi://anniversary/A+B")
        assertEquals("A+B", canonicalLiteralPlus.second)

        val plainPercentSlash = DuoyiWidgetContent.parseAnniversaryTarget("A%2FM1")
        val canonicalPercentSlash = DuoyiWidgetContent.parseAnniversaryTarget("duoyi://anniversary/A%252FM1")
        val plainSlash = DuoyiWidgetContent.parseAnniversaryTarget("A/M1")
        assertEquals("duoyi://anniversary/A%252FM1", plainPercentSlash.first)
        assertEquals("A%2FM1", plainPercentSlash.second)
        assertEquals(plainPercentSlash, canonicalPercentSlash)
        assertEquals("A/M1", plainSlash.second)
        assertEquals("duoyi://anniversary/A%2FM1", plainSlash.first)
        assertFalse(plainPercentSlash.second == plainSlash.second)
    }

    @Test
    fun malformedForeignUnrelatedExtraPathAndQueryTargetsFallBackToSafeRoot() {
        listOf(
            null,
            "  ",
            "duoyi://anniversary/%ZZ",
            "duoyi://anniversary/%E0%A4%A",
            "duoyi://anniversary/%E2%82",
            "duoyi://anniversary/%E2%82%AC%FF",
            "duoyi://anniversary/%C0%AF",
            "duoyi://anniversary/%ED%A0%80",
            "duoyi://anniversary/%80",
            "duoyi://user@anniversary/id",
            "duoyi://anniversary@evil.test/id",
            "duoyi://anniversary:443/id",
            "duoyi://anniversary:invalid/id",
            "duoyi://anniversary:/x",
            "duoyi://anniversary/id/extra",
            "duoyi://anniversary/id?source=widget",
            "duoyi://anniversary/id?",
            "duoyi://anniversary/id#details",
            "duoyi://anniversary/id#",
            "duoyi://anniversary/a|b",
            "duoyi://anniversary/a\"b",
            "duoyi://anniversary/a{b}",
            "duoyi://anniversary/a[b]",
            "duoyi://anniversary/id with space",
            "duoyi://anniversary/id\\tail",
            "duoyi://anniversary/id\nwith-newline",
            "duoyi://anniversary/id?source=widget#details",
            "duoyi://todo/42",
            "https://example.test/anniversary/id",
            "content://com.example/anniversary/id",
            "custom://anniversary/id",
        ).forEach { target ->
            assertEquals(
                "Unsafe target should use the anniversary root: $target",
                "duoyi://anniversary" to null,
                DuoyiWidgetContent.parseAnniversaryTarget(target),
            )
        }
    }

    @Test
    fun calendarTargetsPreserveEverySupportedReadOnlyProducerDestination() {
        val targets = listOf(
            "duoyi://calendar",
            "duoyi://focus",
            "duoyi://todo/todo-42",
            "duoyi://todo/add",
            "duoyi://todo/create",
            "duoyi://habit/new",
            "duoyi://habit/habit-7",
            "duoyi://anniversary/memorial-2",
            "duoyi://course/course-3",
            "duoyi://diary/diary-5",
            "duoyi://goal/goal-9",
            "duoyi://countdown/countdown-1",
            "duoyi://time-entry/entry-6",
            "duoyi://event/%20local%2Fid%20",
            "duoyi://pomodoro/%E6%B5%8B%E8%AF%95%2Fsession",
        )

        targets.forEach { target ->
            assertEquals(target, DuoyiWidgetContent.resolveCalendarEventTarget(target))
        }
    }

    @Test
    fun invalidCalendarActionsHostsAndPathsUseCalendarRoot() {
        listOf(
            null,
            "  ",
            "https://example.test/todo/42",
            "custom://calendar",
            "duoyi://unknown/item-1",
            "duoyi://todo",
            "duoyi://todo/",
            "duoyi://habit//",
            "duoyi://todo/edit/42",
            "duoyi://todo/delete/42",
            "duoyi://anniversary/remove/42",
            "duoyi://course/42/details",
            "duoyi://calendar/month",
            "duoyi://calendar/",
            "duoyi://focus/event-42",
            "duoyi://focus/?source=widget",
            "duoyi://todo:/x",
            "duoyi://focus:",
            "duoyi://event",
            "duoyi://pomodoro/",
            "duoyi://event/a/b",
            "duoyi://pomodoro/%20%0A",
            "duoyi://event/%FF",
            "duoyi://pomodoro/id?source=widget",
            "duoyi://todo/a|b",
            "duoyi://todo/a\"b",
            "duoyi://todo/a{b}",
            "duoyi://todo/a[b]",
            "duoyi://todo/id with space",
            "duoyi://todo/id\\tail",
            "duoyi://todo/%ED%A0%80",
            "duoyi://todo/%F0%80%80%80",
            "duoyi://todo/%C3%28",
            "duoyi://todo/42?",
            "duoyi://todo/42#",
        ).forEach { target ->
            assertEquals(
                "Invalid calendar destination should use the calendar root: $target",
                "duoyi://calendar",
                DuoyiWidgetContent.resolveCalendarEventTarget(target),
            )
        }
    }

    @Test
    fun monthGridSupports28Through31DaysWithOneTodayAnd42Cells() {
        val fixtures = listOf(
            MonthFixture(2023, 2, 28),
            MonthFixture(2024, 2, 29),
            MonthFixture(2024, 4, 30),
            MonthFixture(2024, 1, 31),
        )

        fixtures.forEach { fixture ->
            val model = DuoyiWidgetContent.buildMonthGrid(
                fixture.year,
                fixture.month,
                todayDay = fixture.days,
                isZh = false,
                timeZone = utc,
            )
            val dateCells = model.cells.filter { it.dayNumber > 0 }
            val blankCells = model.cells.filter { it.dayNumber == 0 }

            assertEquals(fixture.year, model.year)
            assertEquals(fixture.month, model.month)
            assertEquals(fixture.days, model.daysInMonth)
            assertEquals(42, model.cells.size)
            assertEquals((1..fixture.days).toList(), dateCells.map { it.dayNumber })
            assertEquals(1, model.cells.count { it.isToday })
            assertTrue(model.cells[model.firstWeekdayOffset + fixture.days - 1].isToday)
            assertTrue(blankCells.all { it.text == "  " })
            assertTrue(blankCells.none { it.isToday })
        }
    }

    @Test
    fun monthGridUsesMondayFirstOffsetsAndHandlesYearBoundaries() {
        val mondayFirst = DuoyiWidgetContent.buildMonthGrid(2024, 1, 2, isZh = false, timeZone = utc)
        val sundayFirst = DuoyiWidgetContent.buildMonthGrid(2024, 9, 2, isZh = true, timeZone = utc)
        val december = DuoyiWidgetContent.buildMonthGrid(2024, 12, 31, isZh = false, timeZone = utc)
        val january = DuoyiWidgetContent.buildMonthGrid(2025, 1, 1, isZh = false, timeZone = utc)

        assertEquals(0, mondayFirst.firstWeekdayOffset)
        assertEquals("Mo Tu We Th Fr Sa Su", mondayFirst.weekdayHeader)
        assertEquals(6, sundayFirst.firstWeekdayOffset)
        assertEquals("一 二 三 四 五 六 日", sundayFirst.weekdayHeader)
        assertEquals(6, december.firstWeekdayOffset)
        assertEquals(2024, december.year)
        assertEquals(12, december.month)
        assertEquals(2, january.firstWeekdayOffset)
        assertEquals(2025, january.year)
        assertEquals(1, january.month)
        assertEquals(42, december.cells.size)
        assertEquals(42, january.cells.size)
    }

    @Test
    fun monthGridLeavesBlankCellsUnmarkedAndInvalidTodayHasNoTodayCell() {
        val model = DuoyiWidgetContent.buildMonthGrid(2024, 4, 31, isZh = false, timeZone = utc)
        val blanks = model.cells.filter { it.dayNumber == 0 }

        assertEquals(42, model.cells.size)
        assertTrue(blanks.isNotEmpty())
        assertTrue(blanks.all { it.text == "  " && !it.isToday })
        assertEquals(0, model.cells.count { it.isToday })
    }

    @Test
    fun anchorDateUsesTheRequestedTimezoneAtLocalMidnight() {
        val losAngeles = TimeZone.getTimeZone("America/Los_Angeles")
        val beforeMidnight = Date.from(Instant.parse("2024-01-01T07:30:00Z"))
        val afterMidnight = Date.from(Instant.parse("2024-01-01T08:30:00Z"))

        val before = DuoyiWidgetContent.buildMonthGrid(beforeMidnight, losAngeles, isZh = false)
        val after = DuoyiWidgetContent.buildMonthGrid(afterMidnight, losAngeles, isZh = false)

        assertEquals(2023, before.year)
        assertEquals(12, before.month)
        assertEquals(31, before.todayDay)
        assertEquals(2024, after.year)
        assertEquals(1, after.month)
        assertEquals(1, after.todayDay)
        assertEquals(42, before.cells.size)
        assertEquals(42, after.cells.size)
    }

    @Test
    fun anchorDateKeepsCalendarDayCorrectAcrossDstTransition() {
        val newYork = TimeZone.getTimeZone("America/New_York")
        val beforeDstJump = Date.from(Instant.parse("2024-03-10T04:30:00Z"))
        val afterDstJump = Date.from(Instant.parse("2024-03-10T07:30:00Z"))

        val before = DuoyiWidgetContent.buildMonthGrid(beforeDstJump, newYork, isZh = true)
        val after = DuoyiWidgetContent.buildMonthGrid(afterDstJump, newYork, isZh = true)

        assertEquals(2024, before.year)
        assertEquals(3, before.month)
        assertEquals(9, before.todayDay)
        assertEquals(2024, after.year)
        assertEquals(3, after.month)
        assertEquals(10, after.todayDay)
        assertEquals(1, before.cells.count { it.isToday })
        assertEquals(1, after.cells.count { it.isToday })
        assertEquals(42, before.cells.size)
        assertEquals(42, after.cells.size)
    }

    @Test
    fun anniversaryUnionPreservesAllFiveOrderedSlotsAndLegacyPunctuationIds() {
        val keys = listOf("anniversary_highlight_1", "anniversary_highlight_2", "memorial_highlight_1", "memorial_highlight_2", "memorial_highlight_3")
        val ids = listOf("record:42", "a+b", "中文", "🎂", "a|b")
        val items = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = keys.indices.map { slot(keys[it], "Event $it", ids[it]) },
            isFresh = true,
            isZh = false,
        )
        assertEquals(keys, items.map { it.sourceKey })
        assertEquals(ids, items.map { it.identity })
        assertEquals(keys.indices.map { "Event $it" }, items.map { it.text })
        items.forEach { assertEquals(it.identity, DuoyiWidgetContent.parseAnniversaryTarget(it.target).second) }
    }

    @Test
    fun encodedUriPunctuationAndUnicodePreserveOneDecodedIdentity() {
        listOf(
            "%7C" to "|", "%22" to "\"", "%7B%7D" to "{}", "%5B%5D" to "[]",
            "%E4%B8%AD%E6%96%87" to "中文", "%F0%9F%8E%82" to "🎂", "a+b" to "a+b",
            "a%252Fb" to "a%2Fb",
        ).forEach { (segment, id) ->
            val anniversary = "duoyi://anniversary/$segment"
            assertEquals(anniversary to id, DuoyiWidgetContent.parseAnniversaryTarget(anniversary))
            val todo = "duoyi://todo/$segment"
            assertEquals(todo, DuoyiWidgetContent.resolveCalendarEventTarget(todo))
        }
    }

    @Test
    fun opaqueIdentityDedupKeepsDistinctUnicodeByteSequences() {
        val items = DuoyiWidgetContent.resolveAnniversaryItems(
            slots = listOf(
                slot("a1", "Precomposed", "duoyi://anniversary/%C3%A9"),
                slot("a2", "Decomposed", "duoyi://anniversary/e%CC%81"),
                slot("m1", "Exact duplicate", "duoyi://anniversary/%C3%A9"),
            ),
            isFresh = true,
            isZh = false,
        )
        assertEquals(listOf("a1", "a2"), items.map { it.sourceKey })
        assertEquals(listOf("\u00E9", "e\u0301"), items.map { it.identity })
        assertEquals(listOf("duoyi://anniversary/%C3%A9", "duoyi://anniversary/e%CC%81"), items.map { it.target })
    }

    @Test
    fun calendarSummaryPairsRealContentWithTargetAndPreservesUnknownUserText() {
        val result = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
            rawSummary = "  Review with 陈  ",
            rawSchedule1Id = "duoyi://todo/add",
            isFresh = true,
            isZh = false,
        )
        assertEquals("  Review with 陈  ", result.summary)
        assertEquals("duoyi://todo/add", result.target)
        assertTrue(result.isReal)
    }

    @Test
    fun calendarEmptyAndStaleSummariesNeverUseResidualEntityTargets() {
        listOf<String?>(null, "  ", "· No events today", "今日没有日程", "Today's schedule").forEach { raw ->
            val result = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = raw,
                rawSchedule1Id = "duoyi://todo/residual-id",
                isFresh = true,
                isZh = false,
            )
            assertFalse("Known empty state must not be real: $raw", result.isReal)
            assertEquals("duoyi://calendar", result.target)
        }
        for (isZh in listOf(false, true)) {
            val result = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = "Old account event",
                rawSchedule1Id = "duoyi://todo/old-id",
                isFresh = false,
                isZh = isZh,
            )
            assertFalse(result.isReal)
            assertEquals("duoyi://calendar", result.target)
            assertEquals(if (isZh) "今日数据待刷新" else "Today’s data pending refresh", result.summary)
        }
    }

    @Test
    fun anniversaryItemsUnpublishedStatesUseNeutralPromptAndSingleSlotAcrossBothLanguages() {
        val states = listOf(
            DuoyiWidgetPublicationDocument.State.CLEARED,
            DuoyiWidgetPublicationDocument.State.BLOCKED,
            null,
        )
        val languages = listOf(true to "打开多仪以更新小组件", false to "Open Duoyi to update this widget")
        val slots = listOf(
            slot("anniversary_highlight_1", "Private wedding anniversary", "anniv-1"),
            slot("anniversary_highlight_2", "Private graduation", "anniv-2"),
            slot("memorial_highlight_1", "Private birthday", "mem-1"),
        )

        for (state in states) {
            for ((isZh, expectedPrompt) in languages) {
                listOf(false, true).forEach { isFresh ->
                    val items = DuoyiWidgetContent.resolveAnniversaryItems(
                        slots = slots,
                        isFresh = isFresh,
                        isZh = isZh,
                        publicationState = state,
                    )
                    assertEquals("Unpublished anniversary items must only contain 1 item (secondary rows empty)", 1, items.size)
                    val first = items.single()
                    assertEquals("anniversary_highlight_1", first.sourceKey)
                    assertEquals(expectedPrompt, first.text)
                    assertEquals("duoyi://anniversary", first.target)
                    assertNull(first.identity)
                }
            }
        }
    }

    @Test
    fun anniversaryItemsPublishedStaleVsPublishedFreshVsEmpty() {
        val slots = listOf(
            slot("anniversary_highlight_1", "Real anniversary", "anniv-1"),
            slot("anniversary_highlight_2", "Real graduation", "anniv-2"),
        )

        listOf(
            Triple(true, "日期数据待刷新", "· 暂无近期纪念日"),
            Triple(false, "Dates pending refresh", "· No upcoming anniversaries"),
        ).forEach { (isZh, expectedStale, expectedEmpty) ->
            // Published stale
            val staleItems = DuoyiWidgetContent.resolveAnniversaryItems(
                slots = slots,
                isFresh = false,
                isZh = isZh,
                publicationState = DuoyiWidgetPublicationDocument.State.PUBLISHED,
            )
            assertEquals(1, staleItems.size)
            assertEquals(expectedStale, staleItems.single().text)
            assertEquals("duoyi://anniversary", staleItems.single().target)
            assertNull(staleItems.single().identity)

            // Default parameter matches published behavior
            val defaultStaleItems = DuoyiWidgetContent.resolveAnniversaryItems(
                slots = slots,
                isFresh = false,
                isZh = isZh,
            )
            assertEquals(staleItems, defaultStaleItems)

            // Published fresh with real data
            val freshItems = DuoyiWidgetContent.resolveAnniversaryItems(
                slots = slots,
                isFresh = true,
                isZh = isZh,
                publicationState = DuoyiWidgetPublicationDocument.State.PUBLISHED,
            )
            assertEquals(2, freshItems.size)
            assertEquals("Real anniversary", freshItems[0].text)
            assertEquals("duoyi://anniversary/anniv-1", freshItems[0].target)
            assertEquals("anniv-1", freshItems[0].identity)

            // Published fresh with empty data
            val emptyItems = DuoyiWidgetContent.resolveAnniversaryItems(
                slots = emptyList(),
                isFresh = true,
                isZh = isZh,
                publicationState = DuoyiWidgetPublicationDocument.State.PUBLISHED,
            )
            assertFallback(emptyItems, expectedEmpty)
        }
    }

    @Test
    fun calendarSummaryUnpublishedStatesUseNeutralPromptAndGenericTargetAcrossBothLanguages() {
        val states = listOf(
            DuoyiWidgetPublicationDocument.State.CLEARED,
            DuoyiWidgetPublicationDocument.State.BLOCKED,
            null,
        )
        val languages = listOf(true to "打开多仪以更新小组件", false to "Open Duoyi to update this widget")

        for (state in states) {
            for ((isZh, expectedPrompt) in languages) {
                listOf(false, true).forEach { isFresh ->
                    val result = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                        rawSummary = "Private executive review",
                        rawSchedule1Id = "duoyi://todo/private-id-123",
                        isFresh = isFresh,
                        isZh = isZh,
                        publicationState = state,
                    )
                    assertEquals(expectedPrompt, result.summary)
                    assertEquals("duoyi://calendar", result.target)
                    assertFalse(result.isReal)
                }
            }
        }
    }

    @Test
    fun calendarSummaryPublishedStaleVsPublishedFreshVsEmpty() {
        listOf(
            Triple(true, "今日数据待刷新", "今日没有日程"),
            Triple(false, "Today’s data pending refresh", "No events today"),
        ).forEach { (isZh, expectedStale, expectedEmpty) ->
            // Published stale
            val staleResult = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = "Real meeting",
                rawSchedule1Id = "duoyi://todo/meet-42",
                isFresh = false,
                isZh = isZh,
                publicationState = DuoyiWidgetPublicationDocument.State.PUBLISHED,
            )
            assertEquals(expectedStale, staleResult.summary)
            assertEquals("duoyi://calendar", staleResult.target)
            assertFalse(staleResult.isReal)

            // Default parameter matches published behavior
            val defaultStaleResult = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = "Real meeting",
                rawSchedule1Id = "duoyi://todo/meet-42",
                isFresh = false,
                isZh = isZh,
            )
            assertEquals(staleResult, defaultStaleResult)

            // Published fresh with real content
            val freshResult = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = "Real meeting",
                rawSchedule1Id = "duoyi://todo/meet-42",
                isFresh = true,
                isZh = isZh,
                publicationState = DuoyiWidgetPublicationDocument.State.PUBLISHED,
            )
            assertEquals("Real meeting", freshResult.summary)
            assertEquals("duoyi://todo/meet-42", freshResult.target)
            assertTrue(freshResult.isReal)

            // Published fresh with empty placeholder
            val emptyResult = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = "· No events today",
                rawSchedule1Id = "duoyi://todo/meet-42",
                isFresh = true,
                isZh = isZh,
                publicationState = DuoyiWidgetPublicationDocument.State.PUBLISHED,
            )
            assertEquals(expectedEmpty, emptyResult.summary)
            assertEquals("duoyi://calendar", emptyResult.target)
            assertFalse(emptyResult.isReal)
        }
    }

    private fun slot(sourceKey: String, text: String?, target: String?) =
        DuoyiAnniversaryRawSlot(sourceKey = sourceKey, text = text, target = target)

    private fun assertFallback(items: List<DuoyiAnniversaryItem>, text: String) {
        assertEquals(1, items.size)
        assertEquals("anniversary_highlight_1", items.single().sourceKey)
        assertEquals(text, items.single().text)
        assertEquals("duoyi://anniversary", items.single().target)
        assertNull(items.single().identity)
    }

    private data class MonthFixture(val year: Int, val month: Int, val days: Int)

    private companion object {
        val utc: TimeZone
            get() = TimeZone.getTimeZone("UTC")
    }
}
