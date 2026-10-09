package com.duoyi.duoyi

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetDayBoundaryPolicyTest {

    @Test
    fun nextBoundaryCoversUtcShanghaiKathmanduAndNegativeOffsetCalendarEdges() {
        assertBoundary(
            nowUtc = "2024-01-31T23:59:59.999Z",
            zone = "UTC",
            expectedUtc = "2024-02-01T00:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-02-29T23:59:59.999Z",
            zone = "UTC",
            expectedUtc = "2024-03-01T00:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-12-31T23:59:59.999Z",
            zone = "UTC",
            expectedUtc = "2025-01-01T00:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-04-30T15:59:59.999Z",
            zone = "Asia/Shanghai",
            expectedUtc = "2024-04-30T16:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-04-30T18:14:59.999Z",
            zone = "Asia/Kathmandu",
            expectedUtc = "2024-04-30T18:15:00Z",
        )
        assertBoundary(
            nowUtc = "2024-03-01T07:59:59.999Z",
            zone = "America/Los_Angeles",
            expectedUtc = "2024-03-01T08:00:00Z",
        )
        assertBoundary(
            nowUtc = "2025-01-01T07:59:59.999Z",
            zone = "America/Los_Angeles",
            expectedUtc = "2025-01-01T08:00:00Z",
        )
    }

    @Test
    fun newYorkSpringAndFallBoundariesUseExactTransitionThenFollowingMidnight() {
        assertBoundary(
            nowUtc = "2024-03-10T06:59:59.999Z",
            zone = "America/New_York",
            expectedUtc = "2024-03-10T07:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-03-10T07:00:00Z",
            zone = "America/New_York",
            expectedUtc = "2024-03-11T04:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-11-03T05:59:59.999Z",
            zone = "America/New_York",
            expectedUtc = "2024-11-03T06:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-11-03T06:00:00Z",
            zone = "America/New_York",
            expectedUtc = "2024-11-04T05:00:00Z",
        )
    }

    @Test
    fun lordHoweHalfHourTransitionsAreBoundariesAndExactNowMovesForward() {
        assertBoundary(
            nowUtc = "2024-10-05T15:29:59.999Z",
            zone = "Australia/Lord_Howe",
            expectedUtc = "2024-10-05T15:30:00Z",
        )
        assertBoundary(
            nowUtc = "2024-10-05T15:30:00Z",
            zone = "Australia/Lord_Howe",
            expectedUtc = "2024-10-06T13:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-04-06T14:59:59.999Z",
            zone = "Australia/Lord_Howe",
            expectedUtc = "2024-04-06T15:00:00Z",
        )
        assertBoundary(
            nowUtc = "2024-04-06T15:00:00Z",
            zone = "Australia/Lord_Howe",
            expectedUtc = "2024-04-07T13:30:00Z",
        )
    }

    @Test
    fun historicMidnightGapAndOverlapResolveToStrictlyFutureInstants() {
        // São Paulo skipped local midnight at the start of 2018-11-04.
        assertBoundary(
            nowUtc = "2018-11-04T02:59:59.999Z",
            zone = "America/Sao_Paulo",
            expectedUtc = "2018-11-04T03:00:00Z",
        )
        assertBoundary(
            nowUtc = "2018-11-04T03:00:00Z",
            zone = "America/Sao_Paulo",
            expectedUtc = "2018-11-05T02:00:00Z",
        )

        // Havana repeated local midnight when clocks moved back on 2020-11-01.
        assertBoundary(
            nowUtc = "2020-11-01T04:59:59.999Z",
            zone = "America/Havana",
            expectedUtc = "2020-11-01T05:00:00Z",
        )
        assertBoundary(
            nowUtc = "2020-11-01T05:00:00Z",
            zone = "America/Havana",
            expectedUtc = "2020-11-02T05:00:00Z",
        )
    }

    @Test
    fun skippedApiaCivilDateUsesTheFirstRepresentableFutureBoundary() {
        assertBoundary(
            nowUtc = "2011-12-30T09:59:59.999Z",
            zone = "Pacific/Apia",
            expectedUtc = "2011-12-30T10:00:00Z",
        )
        assertBoundary(
            nowUtc = "2011-12-30T10:00:00Z",
            zone = "Pacific/Apia",
            expectedUtc = "2011-12-31T10:00:00Z",
        )
    }

    @Test
    fun exactTransitionNowNeverReturnsTheDeliveredInstant() {
        val transitionCases = listOf(
            Triple("2024-03-10T07:00:00Z", "America/New_York", "2024-03-11T04:00:00Z"),
            Triple("2024-11-03T06:00:00Z", "America/New_York", "2024-11-04T05:00:00Z"),
            Triple("2024-10-05T15:30:00Z", "Australia/Lord_Howe", "2024-10-06T13:00:00Z"),
            Triple("2018-11-04T03:00:00Z", "America/Sao_Paulo", "2018-11-05T02:00:00Z"),
            Triple("2011-12-30T10:00:00Z", "Pacific/Apia", "2011-12-31T10:00:00Z"),
        )

        transitionCases.forEach { (nowUtc, zone, expectedUtc) ->
            val now = Instant.parse(nowUtc)
            val result = Instant.ofEpochMilli(
                DuoyiWidgetDayBoundaryPolicy.nextBoundaryAt(now.toEpochMilli(), ZoneId.of(zone)),
            )
            assertEquals(Instant.parse(expectedUtc), result)
            assertTrue("$zone returned a non-future boundary at $now", result.isAfter(now))
        }
    }

    @Test
    fun controllerSchedulesOnceForManyInstancesAndDeduplicatesReconciliation() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort()
        val now = millis("2024-06-01T12:00:00Z")
        val expected = millis("2024-06-02T00:00:00Z")

        val first = controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.SCHEDULED, first.outcome)
        assertEquals(expected, first.atMillis)

        listOf(2, 3, 8, 21, 64).forEach { realInstanceCount ->
            val repeated = controller.reconcile(
                now,
                utc,
                installedWidgetCount = realInstanceCount,
                alarm = alarm,
            )
            assertEquals(DuoyiWidgetBoundaryOutcome.UNCHANGED, repeated.outcome)
            assertEquals(expected, repeated.atMillis)
        }

        assertEquals(listOf(expected), alarm.scheduleCalls)
        assertEquals(0, alarm.cancelCalls)
    }

    @Test
    fun deletingLastWidgetCancelsTheExistingAlarm() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort()
        val now = millis("2024-06-01T12:00:00Z")

        assertEquals(
            DuoyiWidgetBoundaryOutcome.SCHEDULED,
            controller.reconcile(now, utc, installedWidgetCount = 2, alarm = alarm).outcome,
        )
        val deleted = controller.reconcile(now, utc, installedWidgetCount = 0, alarm = alarm)

        assertEquals(DuoyiWidgetBoundaryOutcome.CANCELLED, deleted.outcome)
        assertNull(deleted.atMillis)
        assertEquals(1, alarm.scheduleCalls.size)
        assertEquals(1, alarm.cancelCalls)
    }

    @Test
    fun forceAndInvalidateEachRearmTheSameBoundary() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort()
        val now = millis("2024-06-01T12:00:00Z")
        val expected = millis("2024-06-02T00:00:00Z")

        assertEquals(
            DuoyiWidgetBoundaryOutcome.SCHEDULED,
            controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm).outcome,
        )
        assertEquals(
            DuoyiWidgetBoundaryOutcome.UNCHANGED,
            controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm).outcome,
        )
        assertEquals(
            DuoyiWidgetBoundaryOutcome.SCHEDULED,
            controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm, force = true).outcome,
        )

        controller.invalidate()
        val invalidated = controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.SCHEDULED, invalidated.outcome)
        assertEquals(expected, invalidated.atMillis)
        assertEquals(listOf(expected, expected, expected), alarm.scheduleCalls)
    }

    @Test
    fun lateDeliveryClockMovementAndZoneChangeRecalculateAndRearm() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort()

        val first = controller.reconcile(
            millis("2024-05-10T12:00:00Z"),
            utc,
            installedWidgetCount = 1,
            alarm = alarm,
        )
        assertScheduledAt(first, "2024-05-11T00:00:00Z")

        // Reconcile after the alarm was missed by several civil days.
        val deliveredLate = controller.reconcile(
            millis("2024-05-14T18:00:00Z"),
            utc,
            installedWidgetCount = 1,
            alarm = alarm,
        )
        assertScheduledAt(deliveredLate, "2024-05-15T00:00:00Z")

        // A backward clock adjustment makes the next local boundary earlier.
        val movedBackward = controller.reconcile(
            millis("2024-05-12T10:00:00Z"),
            utc,
            installedWidgetCount = 1,
            alarm = alarm,
        )
        assertScheduledAt(movedBackward, "2024-05-13T00:00:00Z")

        // A forward adjustment across midnight advances it again.
        val movedForward = controller.reconcile(
            millis("2024-05-13T00:00:00Z"),
            utc,
            installedWidgetCount = 1,
            alarm = alarm,
        )
        assertScheduledAt(movedForward, "2024-05-14T00:00:00Z")

        // At the same instant, a changed civil zone has a different boundary.
        val changedZone = controller.reconcile(
            millis("2024-05-13T00:00:00Z"),
            ZoneId.of("Asia/Kathmandu"),
            installedWidgetCount = 1,
            alarm = alarm,
        )
        assertScheduledAt(changedZone, "2024-05-13T18:15:00Z")
        assertEquals(
            listOf(
                millis("2024-05-11T00:00:00Z"),
                millis("2024-05-15T00:00:00Z"),
                millis("2024-05-13T00:00:00Z"),
                millis("2024-05-14T00:00:00Z"),
                millis("2024-05-13T18:15:00Z"),
            ),
            alarm.scheduleCalls,
        )
    }

    @Test
    fun falseScheduleResultCanBeRetriedOnTheNextReconcile() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort().apply { scheduleResults += false }
        val now = millis("2024-06-01T12:00:00Z")
        val expected = millis("2024-06-02T00:00:00Z")

        val failed = controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.FAILED, failed.outcome)
        assertEquals(expected, failed.atMillis)

        val retried = controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.SCHEDULED, retried.outcome)
        assertEquals(expected, retried.atMillis)
        assertEquals(listOf(expected, expected), alarm.scheduleCalls)

        val deduplicated = controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.UNCHANGED, deduplicated.outcome)
        assertEquals(2, alarm.scheduleCalls.size)
    }

    @Test
    fun throwingScheduleHandoffCanBeRetriedOnTheNextReconcile() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort().apply { throwNextSchedule = true }
        val now = millis("2024-06-01T12:00:00Z")
        val expected = millis("2024-06-02T00:00:00Z")

        var didThrow = false
        try {
            controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        } catch (_: IllegalStateException) {
            didThrow = true
        }
        assertTrue(didThrow)
        assertEquals(listOf(expected), alarm.scheduleCalls)

        val retried = controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.SCHEDULED, retried.outcome)
        assertEquals(expected, retried.atMillis)
        assertEquals(listOf(expected, expected), alarm.scheduleCalls)
    }

    @Test
    fun failedCancellationRemainsRetryable() {
        val controller = DuoyiWidgetBoundaryController()
        val alarm = FakeAlarmPort().apply { cancelResults += false }
        val now = millis("2024-06-01T12:00:00Z")

        controller.reconcile(now, utc, installedWidgetCount = 1, alarm = alarm)
        val failedCancel = controller.reconcile(now, utc, installedWidgetCount = 0, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.FAILED, failedCancel.outcome)
        assertNull(failedCancel.atMillis)
        assertEquals(1, alarm.cancelCalls)

        val retriedCancel = controller.reconcile(now, utc, installedWidgetCount = 0, alarm = alarm)
        assertEquals(DuoyiWidgetBoundaryOutcome.CANCELLED, retriedCancel.outcome)
        assertEquals(2, alarm.cancelCalls)
        assertEquals(1, alarm.scheduleCalls.size)
    }

    private fun assertBoundary(nowUtc: String, zone: String, expectedUtc: String) {
        val now = Instant.parse(nowUtc)
        val expected = Instant.parse(expectedUtc)
        val result = Instant.ofEpochMilli(
            DuoyiWidgetDayBoundaryPolicy.nextBoundaryAt(now.toEpochMilli(), ZoneId.of(zone)),
        )

        assertEquals("Unexpected boundary for $zone at $nowUtc", expected, result)
        assertTrue("Boundary must be strictly future for $zone at $nowUtc", result.isAfter(now))
    }

    private fun assertScheduledAt(result: DuoyiWidgetBoundaryResult, expectedUtc: String) {
        assertEquals(DuoyiWidgetBoundaryOutcome.SCHEDULED, result.outcome)
        assertEquals(millis(expectedUtc), result.atMillis)
    }

    private fun millis(utcInstant: String): Long = Instant.parse(utcInstant).toEpochMilli()

    private class FakeAlarmPort : DuoyiWidgetBoundaryAlarmPort {
        val scheduleCalls = mutableListOf<Long>()
        val scheduleResults = mutableListOf<Boolean>()
        var cancelCalls = 0
            private set
        val cancelResults = mutableListOf<Boolean>()
        var throwNextSchedule = false

        override fun schedule(atMillis: Long): Boolean {
            scheduleCalls += atMillis
            if (throwNextSchedule) {
                throwNextSchedule = false
                throw IllegalStateException("fake alarm handoff failure")
            }
            return if (scheduleResults.isEmpty()) true else scheduleResults.removeAt(0)
        }

        override fun cancel(): Boolean {
            cancelCalls += 1
            return if (cancelResults.isEmpty()) true else cancelResults.removeAt(0)
        }
    }

    private companion object {
        val utc: ZoneId = ZoneId.of("UTC")
    }
}
