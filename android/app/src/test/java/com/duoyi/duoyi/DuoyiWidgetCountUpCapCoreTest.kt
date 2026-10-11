package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetCountUpCapCoreTest {

    @Test
    fun capConstantsAlignWith24Hours() {
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_SECONDS)
        assertEquals(86_400_000L, DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS)
        assertEquals(
            DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_SECONDS * 1000L,
            DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS,
        )
    }

    @Test
    fun distinct14101And14103Identities() {
        assertEquals(14101, DuoyiWidgetCountUpCapCore.TIMER_FINISHED_REQUEST_CODE)
        assertEquals(14103, DuoyiWidgetCountUpCapCore.TIMER_CAP_REQUEST_CODE)
        assertNotEquals(
            DuoyiWidgetCountUpCapCore.TIMER_FINISHED_REQUEST_CODE,
            DuoyiWidgetCountUpCapCore.TIMER_CAP_REQUEST_CODE,
        )

        assertEquals("com.duoyi.duoyi.WIDGET_FOCUS_TIMER_FINISHED", DuoyiWidgetCountUpCapCore.TIMER_FINISHED_ACTION)
        assertEquals("com.duoyi.duoyi.WIDGET_FOCUS_COUNT_UP_CAP", DuoyiWidgetCountUpCapCore.TIMER_CAP_ACTION)
        assertNotEquals(
            DuoyiWidgetCountUpCapCore.TIMER_FINISHED_ACTION,
            DuoyiWidgetCountUpCapCore.TIMER_CAP_ACTION,
        )
    }

    @Test
    fun capMillisRejectsBadOrOverflowAnchors() {
        assertNull(DuoyiWidgetCountUpCapCore.capMillis(0L))
        assertNull(DuoyiWidgetCountUpCapCore.capMillis(-1000L))
        assertNull(DuoyiWidgetCountUpCapCore.capMillis(Long.MAX_VALUE))
        assertNull(DuoyiWidgetCountUpCapCore.capMillis(Long.MAX_VALUE - 1000L))

        val maxValidStart = Long.MAX_VALUE - DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS
        assertEquals(Long.MAX_VALUE, DuoyiWidgetCountUpCapCore.capMillis(maxValidStart))

        val normalStart = 1_000_000L
        assertEquals(
            normalStart + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS,
            DuoyiWidgetCountUpCapCore.capMillis(normalStart),
        )
    }

    @Test
    fun beforeCapRunningIsNeitherCappedNorBlockedFromRefresh() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        // 1 hour in
        val oneHourLater = start + 3_600_000L
        assertFalse(DuoyiWidgetCountUpCapCore.isAtOrPastCap(start, oneHourLater))
        assertTrue(DuoyiWidgetCountUpCapCore.canScheduleCap(start, oneHourLater))
        assertEquals(3600, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(start, oneHourLater))

        // 1 ms before cap
        val justBefore = cap - 1L
        assertFalse(DuoyiWidgetCountUpCapCore.isAtOrPastCap(start, justBefore))
        assertTrue(DuoyiWidgetCountUpCapCore.canScheduleCap(start, justBefore))
        assertEquals(86_399, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(start, justBefore))
    }

    @Test
    fun exactlyAtCapTransitionsToCappedDisplayAndStopsRescheduling() {
        val start = 1_000_000L
        val exactCap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        assertTrue(DuoyiWidgetCountUpCapCore.isAtOrPastCap(start, exactCap))
        // Cap reached: do not reschedule display refresh ("cap后不重复调度")
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(start, exactCap))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(start, exactCap))
    }

    @Test
    fun afterCapFreezesDisplayAt86400AndDeniesScheduling() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        // 25 hours (1h past cap)
        val twentyFiveHours = cap + 3_600_000L
        assertTrue(DuoyiWidgetCountUpCapCore.isAtOrPastCap(start, twentyFiveHours))
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(start, twentyFiveHours))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(start, twentyFiveHours))

        // 100 hours past cap
        val wayPast = cap + 100 * 3_600_000L
        assertTrue(DuoyiWidgetCountUpCapCore.isAtOrPastCap(start, wayPast))
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(start, wayPast))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(start, wayPast))
    }

    @Test
    fun badAndFutureAnchorsDenyCapScheduling() {
        val now = 10_000_000L

        // Bad anchor: <= 0
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(0L, now))
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(-500L, now))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(0L, now))

        // Future anchor: start in the future
        val futureStart = now + 5_000L
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(futureStart, now))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(futureStart, now))

        // Overflow anchor
        assertFalse(DuoyiWidgetCountUpCapCore.canScheduleCap(Long.MAX_VALUE - 100L, now))
    }

    @Test
    fun crossingCapBoundaryIsDetectedAccurately() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        // Crosses cap between capture and commit
        assertTrue(DuoyiWidgetCountUpCapCore.isCrossingCap(start, cap - 50L, cap))
        assertTrue(DuoyiWidgetCountUpCapCore.isCrossingCap(start, cap - 100L, cap + 50L))

        // Entirely before cap
        assertFalse(DuoyiWidgetCountUpCapCore.isCrossingCap(start, cap - 200L, cap - 50L))

        // Entirely at or after cap (already capped when captured)
        assertFalse(DuoyiWidgetCountUpCapCore.isCrossingCap(start, cap, cap + 50L))
        assertFalse(DuoyiWidgetCountUpCapCore.isCrossingCap(start, cap + 50L, cap + 100L))

        // Bad or overflow anchors do not cross cap
        assertFalse(DuoyiWidgetCountUpCapCore.isCrossingCap(0L, cap - 50L, cap))
        assertFalse(DuoyiWidgetCountUpCapCore.isCrossingCap(-100L, cap - 50L, cap))
        assertFalse(DuoyiWidgetCountUpCapCore.isCrossingCap(Long.MAX_VALUE, cap - 50L, cap))
    }

    @Test
    fun pausedCountUpSecondsClampedWithoutSessionMutation() {
        assertEquals(0, DuoyiWidgetCountUpCapCore.clampPausedSeconds(-5))
        assertEquals(0, DuoyiWidgetCountUpCapCore.clampPausedSeconds(0))
        assertEquals(3600, DuoyiWidgetCountUpCapCore.clampPausedSeconds(3600))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.clampPausedSeconds(86_400))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.clampPausedSeconds(90_000))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.clampPausedSeconds(Int.MAX_VALUE))
    }

    @Test
    fun canonicalMatchGuardsAgainstNonceAndTimerMismatches() {
        fun match(
            canonicalState: String? = "published",
            canonicalNonce: String? = "nonce-1",
            canonicalRunning: Boolean = true,
            canonicalCountUp: Boolean = true,
            canonicalStartedAt: Long = 1_000_000L,
            canonicalEndsAt: Long = 0L,
            frameNonce: String? = "nonce-1",
            frameRunning: Boolean = true,
            frameCountUp: Boolean = true,
            frameStartedAt: Long = 1_000_000L,
            frameEndsAt: Long = 0L,
        ) = DuoyiWidgetCountUpCapCore.isCanonicalMatch(
            canonicalStateWire = canonicalState,
            canonicalNonce = canonicalNonce,
            canonicalRunning = canonicalRunning,
            canonicalCountUp = canonicalCountUp,
            canonicalStartedAt = canonicalStartedAt,
            canonicalEndsAt = canonicalEndsAt,
            frameNonce = frameNonce,
            frameRunning = frameRunning,
            frameCountUp = frameCountUp,
            frameStartedAt = frameStartedAt,
            frameEndsAt = frameEndsAt,
        )

        // Matching published state and timer fields
        assertTrue(match())

        // Nonce mismatch (different account / relogin)
        assertFalse(match(canonicalNonce = "nonce-2", frameNonce = "nonce-1"))
        assertFalse(match(frameNonce = null))
        assertFalse(match(frameNonce = "   "))

        // State mismatch (cleared or blocked)
        assertFalse(match(canonicalState = "cleared"))
        assertFalse(match(canonicalState = "blocked"))
        assertFalse(match(canonicalState = null))

        // Running mismatch (session was paused or stopped)
        assertFalse(match(canonicalRunning = false, frameRunning = true))

        // Mode mismatch (switched to countdown)
        assertFalse(match(canonicalCountUp = false, frameCountUp = true))

        // StartedAt mismatch (new session started)
        assertFalse(match(canonicalStartedAt = 2_000_000L, frameStartedAt = 1_000_000L))

        // EndsAt mismatch
        assertFalse(match(canonicalEndsAt = 5_000L, frameEndsAt = 0L))
    }

    @Test
    fun evaluateCapEffectHandlesBeforeCapNormalScheduling() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS
        val now = start + 3_600_000L // 1 hour in

        val decision = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = start,
            capturedAtCap = false,
            effectNowMillis = now,
        )

        assertEquals(cap, decision.scheduleCapMillis)
        assertFalse(decision.needsRefresh)
        assertFalse(decision.cancelAlarm)
    }

    @Test
    fun evaluateCapEffectTriggersRefreshWhenClockCrossesCapBeforeEffect() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        // Frame was captured BEFORE cap (capturedAtCap = false, live Chronometer was built),
        // but commit-to-effect delay crossed the cap (effectNowMillis >= cap).
        val effectNow = cap + 50L
        val decision = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = start,
            capturedAtCap = false,
            effectNowMillis = effectNow,
        )

        assertNull(decision.scheduleCapMillis)
        assertTrue(decision.cancelAlarm)
        assertTrue(decision.needsRefresh) // Must trigger revalidation update!
    }

    @Test
    fun evaluateCapEffectDoesNotLoopWhenCapturedAtCap() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        // Frame was captured AT OR AFTER cap (capturedAtCap = true, static 24:00:00 already built).
        val effectNow = cap + 50L
        val decision = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = start,
            capturedAtCap = true,
            effectNowMillis = effectNow,
        )

        assertNull(decision.scheduleCapMillis)
        assertTrue(decision.cancelAlarm)
        assertFalse(decision.needsRefresh) // Must NOT loop!
    }

    @Test
    fun evaluateCapEffectCancelsOnUntrustedOrPausedOrBadAnchor() {
        val start = 1_000_000L
        val now = start + 1000L

        // Untrusted session
        val untrusted = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = false,
            storedRunning = true,
            countUp = true,
            startedAt = start,
            capturedAtCap = false,
            effectNowMillis = now,
        )
        assertTrue(untrusted.cancelAlarm)
        assertNull(untrusted.scheduleCapMillis)
        assertFalse(untrusted.needsRefresh)

        // Paused session
        val paused = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = false,
            countUp = true,
            startedAt = start,
            capturedAtCap = false,
            effectNowMillis = now,
        )
        assertTrue(paused.cancelAlarm)
        assertNull(paused.scheduleCapMillis)
        assertFalse(paused.needsRefresh)

        // Countdown session
        val countdown = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = false,
            startedAt = start,
            capturedAtCap = false,
            effectNowMillis = now,
        )
        assertTrue(countdown.cancelAlarm)

        // Bad anchor (0L)
        val badAnchor = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = 0L,
            capturedAtCap = false,
            effectNowMillis = now,
        )
        assertTrue(badAnchor.cancelAlarm)

        // Future anchor
        val futureAnchor = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = now + 5000L,
            capturedAtCap = false,
            effectNowMillis = now,
        )
        assertTrue(futureAnchor.cancelAlarm)
    }

    @Test
    fun staleDailyTrustedSessionStillCapsAndEvaluatesEffect() {
        val start = 1_000_000L
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS
        val pastCap = cap + 3_600_000L // 25 hours later

        // Daily snapshot is stale across midnight, but session is trusted
        val isAtCap = DuoyiWidgetCountUpCapCore.isAtOrPastCap(start, pastCap)
        assertTrue(isAtCap)

        val decision = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = start,
            capturedAtCap = true,
            effectNowMillis = pastCap,
        )
        assertTrue(decision.cancelAlarm)
        assertFalse(decision.needsRefresh)
    }

    @Test
    fun computeElapsedSecondsHandlesNegativeWallExtremeEqualFutureAndExtremeInputs() {
        // Negative wall extreme: now = Long.MIN_VALUE, startedAt = 1L
        // Must return 0, avoiding signed Long subtraction underflow wrapping to Long.MAX_VALUE and clamping to 86400
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 1L, nowMillis = Long.MIN_VALUE))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 100L, nowMillis = Long.MIN_VALUE))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 100L, nowMillis = -1000L))

        // start <= 0 logic preserved
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 0L, nowMillis = 1000L))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = -1L, nowMillis = 1000L))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = Long.MIN_VALUE, nowMillis = 1000L))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 0L, nowMillis = Long.MIN_VALUE))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = -10L, nowMillis = Long.MIN_VALUE))

        // Equality: now == startedAt
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 1L, nowMillis = 1L))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 50_000L, nowMillis = 50_000L))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = Long.MAX_VALUE, nowMillis = Long.MAX_VALUE))

        // Future: now < startedAt
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 2000L, nowMillis = 1000L))
        assertEquals(0, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = Long.MAX_VALUE, nowMillis = 1L))

        // Normal elapsed and cap clamping
        assertEquals(1, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 1000L, nowMillis = 2000L))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 1000L, nowMillis = 1000L + 86_400_000L))
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 1000L, nowMillis = 1000L + 100_000_000L))

        // Extreme positive: Long.MAX_VALUE
        assertEquals(86_400, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = 1L, nowMillis = Long.MAX_VALUE))
        assertEquals(1, DuoyiWidgetCountUpCapCore.computeElapsedSeconds(startedAt = Long.MAX_VALUE - 1000L, nowMillis = Long.MAX_VALUE))
    }

    @Test
    fun isValidCountUpAnchorAndLiveCountUpEligible() {
        val now = 10_000_000L
        val maxSafeStart = Long.MAX_VALUE - DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS

        // Valid anchors
        assertTrue(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = 1L, nowMillis = now))
        assertTrue(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = now, nowMillis = now))
        assertTrue(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = 5_000_000L, nowMillis = now))

        // Invalid anchors: <= 0
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = 0L, nowMillis = now))
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = -1L, nowMillis = now))
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = Long.MIN_VALUE, nowMillis = now))

        // Invalid anchors: future (startedAt > now)
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = now + 1L, nowMillis = now))
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = now + 10_000L, nowMillis = now))

        // Invalid anchors: overflow (> Long.MAX_VALUE - 86400000)
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = maxSafeStart + 1L, nowMillis = Long.MAX_VALUE))
        assertFalse(DuoyiWidgetCountUpCapCore.isValidCountUpAnchor(startedAt = Long.MAX_VALUE, nowMillis = Long.MAX_VALUE))

        // Live count-up eligibility:
        // Must be valid anchor AND not at or past cap
        val start = now - 3_600_000L // 1 hour ago
        assertTrue(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = start, nowMillis = now))

        // Just before cap: eligible
        val cap = start + DuoyiWidgetCountUpCapCore.COUNT_UP_CAP_MILLIS
        assertTrue(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = start, nowMillis = cap - 1L))

        // At or past cap: ineligible
        assertFalse(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = start, nowMillis = cap))
        assertFalse(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = start, nowMillis = cap + 1000L))

        // Future anchor: ineligible
        assertFalse(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = now + 5000L, nowMillis = now))

        // Bad anchor (<= 0): ineligible
        assertFalse(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = 0L, nowMillis = now))
        assertFalse(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = -500L, nowMillis = now))

        // Overflow anchor: ineligible
        assertFalse(DuoyiWidgetCountUpCapCore.isLiveCountUpEligible(startedAt = Long.MAX_VALUE, nowMillis = Long.MAX_VALUE))
    }

    @Test
    fun evaluateCapEffectCancelsOnOverflowAnchor() {
        val now = 10_000_000L
        val overflowAnchor = DuoyiWidgetCountUpCapCore.evaluateCapEffect(
            sessionTrusted = true,
            storedRunning = true,
            countUp = true,
            startedAt = Long.MAX_VALUE - 100L,
            capturedAtCap = false,
            effectNowMillis = now,
        )
        assertTrue(overflowAnchor.cancelAlarm)
        assertNull(overflowAnchor.scheduleCapMillis)
        assertFalse(overflowAnchor.needsRefresh)
    }
}
