package com.duoyi.duoyi

import java.time.Instant
import java.time.LocalDate
import java.util.Date
import java.util.Locale
import java.util.SimpleTimeZone
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetCalendarDateCoreTest {

    @Test
    fun everyRealCellHasAUniqueCanonicalCivilDateAndTarget() {
        val fixtures = listOf(
            MonthFixture(year = 1, month = 1, days = 31),
            MonthFixture(year = 2024, month = 2, days = 29),
            MonthFixture(year = 1582, month = 10, days = 31),
            MonthFixture(year = 9999, month = 12, days = 31),
        )

        fixtures.forEach { fixture ->
            val model = DuoyiWidgetContent.buildMonthGrid(
                fixture.year,
                fixture.month,
                todayDay = fixture.days,
                isZh = false,
                timeZone = utc,
            )
            val realCells = model.cells.filter { it.dayNumber > 0 }
            val blankCells = model.cells.filter { it.dayNumber == 0 }
            val expectedKeys = (1..fixture.days).map { day ->
                dateKey(fixture.year, fixture.month, day)
            }

            assertEquals(42, model.cells.size)
            assertEquals(expectedKeys, realCells.map { it.dateKey })
            assertEquals(
                expectedKeys.map { "duoyi://calendar?date=$it" },
                realCells.map { it.target },
            )
            assertEquals(realCells.size, realCells.map { it.dateKey }.distinct().size)
            assertEquals(realCells.size, realCells.map { it.target }.distinct().size)
            assertTrue(blankCells.isNotEmpty())
            assertTrue(blankCells.all { it.dateKey == null && it.target == null })
            assertEquals(
                LocalDate.of(fixture.year, fixture.month, 1).dayOfWeek.value - 1,
                model.firstWeekdayOffset,
            )
            assertEquals(1, model.cells.count { it.isToday })
            assertEquals(fixture.days, realCells.single { it.isToday }.dayNumber)
        }

        val firstSupported = DuoyiWidgetContent.buildMonthGrid(
            1,
            1,
            todayDay = 1,
            isZh = false,
            timeZone = utc,
        ).cells.single { it.dayNumber == 1 }
        val lastSupported = DuoyiWidgetContent.buildMonthGrid(
            9999,
            12,
            todayDay = 31,
            isZh = false,
            timeZone = utc,
        ).cells.single { it.dayNumber == 31 }
        assertEquals("0001-01-01", firstSupported.dateKey)
        assertEquals("duoyi://calendar?date=0001-01-01", firstSupported.target)
        assertEquals("9999-12-31", lastSupported.dateKey)
        assertEquals("duoyi://calendar?date=9999-12-31", lastSupported.target)
    }

    @Test
    fun leapYearsUseProlepticGregorianRules() {
        listOf(
            MonthFixture(year = 1500, month = 2, days = 28),
            MonthFixture(year = 1600, month = 2, days = 29),
            MonthFixture(year = 1900, month = 2, days = 28),
            MonthFixture(year = 2000, month = 2, days = 29),
        ).forEach { fixture ->
            val model = DuoyiWidgetContent.buildMonthGrid(
                fixture.year,
                fixture.month,
                todayDay = fixture.days,
                isZh = true,
                timeZone = utc,
            )
            val realCells = model.cells.filter { it.dayNumber > 0 }

            assertEquals(fixture.days, model.daysInMonth)
            assertEquals((1..fixture.days).toList(), realCells.map { it.dayNumber })
            assertEquals(
                (1..fixture.days).map { dateKey(fixture.year, fixture.month, it) },
                realCells.map { it.dateKey },
            )
        }
    }

    @Test
    fun october1582ContainsAllThirtyOneConsecutiveGregorianDates() {
        val model = DuoyiWidgetContent.buildMonthGrid(
            1582,
            10,
            todayDay = 31,
            isZh = false,
            timeZone = utc,
        )
        val realCells = model.cells.filter { it.dayNumber > 0 }
        val actual = realCells.map { it.dateKey }
        val expected = (1..31).map { dateKey(1582, 10, it) }

        assertEquals(31, model.daysInMonth)
        assertEquals(expected, actual)
        assertEquals(31, actual.distinct().size)
        actual.map { LocalDate.parse(requireNotNull(it)) }
            .zipWithNext()
            .forEach { (first, second) ->
                assertEquals(first.plusDays(1), second)
            }
        assertEquals(
            LocalDate.of(1582, 10, 1).dayOfWeek.value - 1,
            model.firstWeekdayOffset,
        )
    }

    @Test
    fun invalidTodayDayNeverMarksAnyCellAndValidDayMarksExactlyOne() {
        listOf(0, -1, 31, Int.MAX_VALUE).forEach { invalidToday ->
            val model = DuoyiWidgetContent.buildMonthGrid(
                2024,
                4,
                todayDay = invalidToday,
                isZh = false,
                timeZone = utc,
            )
            assertFalse(model.cells.any { it.isToday })
        }

        val valid = DuoyiWidgetContent.buildMonthGrid(
            2024,
            4,
            todayDay = 30,
            isZh = false,
            timeZone = utc,
        )
        assertEquals(1, valid.cells.count { it.isToday })
        assertEquals("2024-04-30", valid.cells.single { it.isToday }.dateKey)
    }

    @Test
    fun invalidGregorianYearAndMonthAreRejected() {
        listOf(0, -1, 10000).forEach { invalidYear ->
            assertThrows(IllegalArgumentException::class.java) {
                DuoyiWidgetContent.buildMonthGrid(
                    invalidYear,
                    1,
                    todayDay = 1,
                    isZh = false,
                    timeZone = utc,
                )
            }
        }
        listOf(0, -1, 13).forEach { invalidMonth ->
            assertThrows(IllegalArgumentException::class.java) {
                DuoyiWidgetContent.buildMonthGrid(
                    2024,
                    invalidMonth,
                    todayDay = 1,
                    isZh = false,
                    timeZone = utc,
                )
            }
        }
    }

    @Test
    fun anchorDateUsesExplicitTimezoneAcrossMidnightAndNewYear() {
        val losAngeles = TimeZone.getTimeZone("America/Los_Angeles")
        val kiritimati = TimeZone.getTimeZone("Pacific/Kiritimati")
        val atNewYear = Date.from(Instant.parse("2024-01-01T00:30:00Z"))

        val negativeOffset = DuoyiWidgetContent.buildMonthGrid(
            atNewYear,
            losAngeles,
            isZh = false,
        )
        val positiveOffset = DuoyiWidgetContent.buildMonthGrid(
            atNewYear,
            kiritimati,
            isZh = false,
        )

        assertEquals(2023, negativeOffset.year)
        assertEquals(12, negativeOffset.month)
        assertEquals(31, negativeOffset.todayDay)
        assertEquals("2023-12-31", negativeOffset.cells.single { it.isToday }.dateKey)
        assertEquals(
            "duoyi://calendar?date=2023-12-31",
            negativeOffset.cells.single { it.isToday }.target,
        )

        assertEquals(2024, positiveOffset.year)
        assertEquals(1, positiveOffset.month)
        assertEquals(1, positiveOffset.todayDay)
        assertEquals("2024-01-01", positiveOffset.cells.single { it.isToday }.dateKey)
        assertEquals(
            "duoyi://calendar?date=2024-01-01",
            positiveOffset.cells.single { it.isToday }.target,
        )

        val beforeMidnight = DuoyiWidgetContent.buildMonthGrid(
            Date.from(Instant.parse("2024-01-01T07:30:00Z")),
            losAngeles,
            isZh = false,
        )
        val afterMidnight = DuoyiWidgetContent.buildMonthGrid(
            Date.from(Instant.parse("2024-01-01T08:30:00Z")),
            losAngeles,
            isZh = false,
        )
        assertEquals("2023-12-31", beforeMidnight.cells.single { it.isToday }.dateKey)
        assertEquals("2024-01-01", afterMidnight.cells.single { it.isToday }.dateKey)
    }

    @Test
    fun anchorDateKeepsItsCivilDateAcrossDaylightSavingTransition() {
        val newYork = TimeZone.getTimeZone("America/New_York")
        val beforeSpringJump = DuoyiWidgetContent.buildMonthGrid(
            Date.from(Instant.parse("2024-03-10T06:30:00Z")),
            newYork,
            isZh = true,
        )
        val afterSpringJump = DuoyiWidgetContent.buildMonthGrid(
            Date.from(Instant.parse("2024-03-10T07:30:00Z")),
            newYork,
            isZh = true,
        )

        listOf(beforeSpringJump, afterSpringJump).forEach { model ->
            assertEquals(2024, model.year)
            assertEquals(3, model.month)
            assertEquals(10, model.todayDay)
            assertEquals("2024-03-10", model.cells.single { it.isToday }.dateKey)
            assertEquals(
                "duoyi://calendar?date=2024-03-10",
                model.cells.single { it.isToday }.target,
            )
        }
    }

    @Test
    fun localeAndDefaultLocaleDoNotChangeDateKeysOrUseNonAsciiDigits() {
        val previousDefault = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("ar-EG"))
            val english = DuoyiWidgetContent.buildMonthGrid(
                2024,
                2,
                todayDay = 29,
                isZh = false,
                timeZone = utc,
            )
            val chinese = DuoyiWidgetContent.buildMonthGrid(
                2024,
                2,
                todayDay = 29,
                isZh = true,
                timeZone = utc,
            )
            val realEnglishCells = english.cells.filter { it.dayNumber > 0 }
            val realChineseCells = chinese.cells.filter { it.dayNumber > 0 }

            assertEquals("Mo Tu We Th Fr Sa Su", english.weekdayHeader)
            assertEquals("一 二 三 四 五 六 日", chinese.weekdayHeader)
            assertEquals(realEnglishCells.map { it.dateKey }, realChineseCells.map { it.dateKey })
            assertEquals(realEnglishCells.map { it.target }, realChineseCells.map { it.target })
            assertEquals("2024-02-29", english.cells.single { it.isToday }.dateKey)
            realEnglishCells.forEach { cell ->
                assertNotNull(cell.dateKey)
                assertNotNull(cell.target)
                assertTrue(cell.dateKey!!.matches(Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))
                assertEquals("duoyi://calendar?date=${cell.dateKey}", cell.target)
            }
        } finally {
            Locale.setDefault(previousDefault)
        }
    }

    @Test
    fun sameExplicitMonthProducesSameDateTargetsInDifferentTimezones() {
        val timeZones = listOf(
            TimeZone.getTimeZone("UTC"),
            TimeZone.getTimeZone("Asia/Kathmandu"),
            TimeZone.getTimeZone("America/Los_Angeles"),
        )
        val models = timeZones.map { zone ->
            DuoyiWidgetContent.buildMonthGrid(
                2024,
                2,
                todayDay = 29,
                isZh = false,
                timeZone = zone,
            )
        }
        val reference = models.first().cells
        models.drop(1).forEach { model ->
            assertEquals(reference.map { it.dateKey }, model.cells.map { it.dateKey })
            assertEquals(reference.map { it.target }, model.cells.map { it.target })
        }
    }

    @Test
    fun anchorDateUsesCustomSimpleTimeZoneEvenWhenItsIdIsUnknown() {
        val unknownZone = SimpleTimeZone(
            5 * MILLIS_PER_HOUR + 45 * MILLIS_PER_MINUTE,
            "Custom/Unknown-Calendar-Zone",
        )
        val anchor = Date.from(Instant.parse("2023-12-31T18:30:00Z"))

        assertEquals(5 * MILLIS_PER_HOUR + 45 * MILLIS_PER_MINUTE, unknownZone.getOffset(anchor.time))

        val model = DuoyiWidgetContent.buildMonthGrid(anchor, unknownZone, isZh = false)
        val today = model.cells.single { it.isToday }
        assertEquals(2024, model.year)
        assertEquals(1, model.month)
        assertEquals(1, model.todayDay)
        assertEquals("2024-01-01", today.dateKey)
        assertEquals("duoyi://calendar?date=2024-01-01", today.target)
    }

    @Test
    fun anchorDateUsesMutatedRawOffsetOnTheSuppliedTimezoneInstance() {
        val adjustedZone = TimeZone.getTimeZone("America/Los_Angeles")
        adjustedZone.rawOffset = 2 * MILLIS_PER_HOUR
        val anchor = Date.from(Instant.parse("2024-01-01T00:30:00Z"))

        assertEquals("America/Los_Angeles", adjustedZone.id)
        assertEquals(2 * MILLIS_PER_HOUR, adjustedZone.getOffset(anchor.time))

        val model = DuoyiWidgetContent.buildMonthGrid(anchor, adjustedZone, isZh = false)
        val today = model.cells.single { it.isToday }
        assertEquals(2024, model.year)
        assertEquals(1, model.month)
        assertEquals(1, model.todayDay)
        assertEquals("2024-01-01", today.dateKey)
        assertEquals("duoyi://calendar?date=2024-01-01", today.target)
    }

    @Test
    fun subsecondTimezoneOffsetChangesTheCivilDateAtMillisecondPrecision() {
        val halfSecondZone = SimpleTimeZone(500, "Custom/Half-Second-Offset")
        val beforeLocalMidnight = Date.from(Instant.parse("2024-01-01T23:59:59.300Z"))
        val afterLocalMidnight = Date.from(Instant.parse("2024-01-01T23:59:59.700Z"))

        assertEquals(500, halfSecondZone.getOffset(beforeLocalMidnight.time))
        assertEquals(500, halfSecondZone.getOffset(afterLocalMidnight.time))

        val before = DuoyiWidgetContent.buildMonthGrid(
            beforeLocalMidnight,
            halfSecondZone,
            isZh = false,
        )
        val after = DuoyiWidgetContent.buildMonthGrid(
            afterLocalMidnight,
            halfSecondZone,
            isZh = false,
        )

        assertEquals("2024-01-01", before.cells.single { it.isToday }.dateKey)
        assertEquals("2024-01-02", after.cells.single { it.isToday }.dateKey)
        assertEquals(
            "duoyi://calendar?date=2024-01-01",
            before.cells.single { it.isToday }.target,
        )
        assertEquals(
            "duoyi://calendar?date=2024-01-02",
            after.cells.single { it.isToday }.target,
        )
    }

    @Test
    fun daylightSavingOffsetAtLocalMidnightUsesTheOffsetAtEachAnchorInstant() {
        val newYork = TimeZone.getTimeZone("America/New_York")
        val beforeMidnight = Date.from(Instant.parse("2024-11-03T03:59:59.999Z"))
        val atMidnight = Date.from(Instant.parse("2024-11-03T04:00:00.000Z"))
        val afterFallback = Date.from(Instant.parse("2024-11-03T06:00:00.000Z"))

        assertEquals(-4 * MILLIS_PER_HOUR, newYork.getOffset(beforeMidnight.time))
        assertEquals(-4 * MILLIS_PER_HOUR, newYork.getOffset(atMidnight.time))
        assertEquals(-5 * MILLIS_PER_HOUR, newYork.getOffset(afterFallback.time))

        val before = DuoyiWidgetContent.buildMonthGrid(beforeMidnight, newYork, isZh = false)
        val midnight = DuoyiWidgetContent.buildMonthGrid(atMidnight, newYork, isZh = false)
        val after = DuoyiWidgetContent.buildMonthGrid(afterFallback, newYork, isZh = false)

        assertEquals("2024-11-02", before.cells.single { it.isToday }.dateKey)
        listOf(midnight, after).forEach { model ->
            val today = model.cells.single { it.isToday }
            assertEquals(2024, model.year)
            assertEquals(11, model.month)
            assertEquals(3, model.todayDay)
            assertEquals("2024-11-03", today.dateKey)
            assertEquals("duoyi://calendar?date=2024-11-03", today.target)
        }
    }

    @Test
    fun legacyThreeArgumentMonthCellDefaultsDateAndTargetToNull() {
        val legacyCell = DuoyiMonthCell(dayNumber = 0, isToday = false, text = "  ")

        assertNull(legacyCell.dateKey)
        assertNull(legacyCell.target)
    }

    private fun dateKey(year: Int, month: Int, day: Int): String =
        String.format(Locale.ROOT, "%04d-%02d-%02d", year, month, day)

    private data class MonthFixture(val year: Int, val month: Int, val days: Int)

    private companion object {
        const val MILLIS_PER_MINUTE = 60 * 1000
        const val MILLIS_PER_HOUR = 60 * MILLIS_PER_MINUTE
        val utc: TimeZone = TimeZone.getTimeZone("UTC")
    }
}
