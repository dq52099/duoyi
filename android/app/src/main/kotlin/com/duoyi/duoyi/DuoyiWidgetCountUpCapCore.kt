package com.duoyi.duoyi

/**
 * Pure Kotlin calculations and decision seam for widget count-up 24-hour (86,400s) cap.
 * Used by [DuoyiFocusHabitWidgetProvider] and [DuoyiWidgetFrameCore].
 */
object DuoyiWidgetCountUpCapCore {
    const val COUNT_UP_CAP_SECONDS: Int = 86_400
    const val COUNT_UP_CAP_MILLIS: Long = 86_400_000L

    const val TIMER_FINISHED_REQUEST_CODE: Int = 14101
    const val TIMER_FINISHED_ACTION: String = "com.duoyi.duoyi.WIDGET_FOCUS_TIMER_FINISHED"

    const val TIMER_CAP_REQUEST_CODE: Int = 14103
    const val TIMER_CAP_ACTION: String = "com.duoyi.duoyi.WIDGET_FOCUS_COUNT_UP_CAP"

    data class CapEffectDecision(
        val scheduleCapMillis: Long? = null,
        val needsRefresh: Boolean = false,
        val cancelAlarm: Boolean = false,
    )

    /**
     * Target timestamp for cap refresh. Returns null if startedAt is invalid (<= 0)
     * or would cause Long overflow.
     */
    fun capMillis(startedAt: Long): Long? {
        if (startedAt <= 0L) return null
        if (startedAt > Long.MAX_VALUE - COUNT_UP_CAP_MILLIS) return null
        return startedAt + COUNT_UP_CAP_MILLIS
    }

    /**
     * Checks if startedAt is a valid count-up anchor that can safely compute a cap
     * and has already started (startedAt <= nowMillis).
     */
    fun isValidCountUpAnchor(startedAt: Long, nowMillis: Long): Boolean {
        if (startedAt <= 0L) return false
        if (startedAt > nowMillis) return false
        return startedAt <= Long.MAX_VALUE - COUNT_UP_CAP_MILLIS
    }

    /**
     * True if the session has reached or passed the 24-hour cap.
     */
    fun isAtOrPastCap(startedAt: Long, nowMillis: Long): Boolean {
        val cap = capMillis(startedAt) ?: return false
        return nowMillis >= cap
    }

    /**
     * Gate for enabling live Chronometer on count-up widgets.
     * Denies invalid anchors (<=0), future anchors (startedAt > now),
     * overflow anchors, and sessions that have reached or passed the 24h cap.
     */
    fun isLiveCountUpEligible(startedAt: Long, nowMillis: Long): Boolean {
        if (!isValidCountUpAnchor(startedAt, nowMillis)) return false
        return !isAtOrPastCap(startedAt, nowMillis)
    }

    /**
     * Checks if time crossed the cap boundary between capture and commit check.
     * Prevents committing a frame built as live Chronometer when time has already reached the cap.
     */
    fun isCrossingCap(startedAt: Long, captureWallMillis: Long, currentWallMillis: Long): Boolean {
        val cap = capMillis(startedAt) ?: return false
        return cap > captureWallMillis && cap <= currentWallMillis
    }

    /**
     * Determines whether a display refresh alarm should be scheduled.
     * Avoids bad anchors (<= 0), future anchors (startedAt > nowMillis),
     * overflow, and already capped sessions (cap后不重复调度).
     */
    fun canScheduleCap(startedAt: Long, nowMillis: Long): Boolean {
        if (!isValidCountUpAnchor(startedAt, nowMillis)) return false
        val cap = capMillis(startedAt) ?: return false
        return cap > nowMillis
    }

    /**
     * Computes elapsed seconds clamped to [0, 86400s].
     * Checks nowMillis <= startedAt first to prevent Long overflow when nowMillis is extreme negative.
     */
    fun computeElapsedSeconds(startedAt: Long, nowMillis: Long): Int {
        if (startedAt <= 0L) return 0
        if (nowMillis <= startedAt) return 0
        val delta = (nowMillis - startedAt).coerceAtLeast(0L)
        return (delta / 1000L).coerceAtMost(COUNT_UP_CAP_SECONDS.toLong()).toInt()
    }

    /**
     * Clamps paused count-up display seconds to [0, 86400s] without mutating session.
     */
    fun clampPausedSeconds(storedRemaining: Int): Int {
        return storedRemaining.coerceIn(0, COUNT_UP_CAP_SECONDS)
    }

    /**
     * Verifies that the canonical store document exactly matches the captured frame's
     * published state, account nonce, and timer parameters before scheduling or cancelling alarms.
     */
    fun isCanonicalMatch(
        canonicalStateWire: String?,
        canonicalNonce: String?,
        canonicalRunning: Boolean,
        canonicalCountUp: Boolean,
        canonicalStartedAt: Long,
        canonicalEndsAt: Long,
        frameNonce: String?,
        frameRunning: Boolean,
        frameCountUp: Boolean,
        frameStartedAt: Long,
        frameEndsAt: Long,
    ): Boolean {
        if (canonicalStateWire != "published") return false
        if (frameNonce.isNullOrBlank() || canonicalNonce != frameNonce) return false
        if (canonicalRunning != frameRunning) return false
        if (canonicalCountUp != frameCountUp) return false
        if (canonicalStartedAt != frameStartedAt) return false
        if (canonicalEndsAt != frameEndsAt) return false
        return true
    }

    /**
     * Decision seam for accepted effect handling:
     * - If time crossed cap between commit check and accepted effect, requests revalidated update
     *   for frames captured before cap to avoid live chronometer running without alarm.
     * - If captured at or after cap, cancels alarm without refresh loop.
     */
    fun evaluateCapEffect(
        sessionTrusted: Boolean,
        storedRunning: Boolean,
        countUp: Boolean,
        startedAt: Long,
        capturedAtCap: Boolean,
        effectNowMillis: Long,
    ): CapEffectDecision {
        if (!sessionTrusted || !storedRunning || !countUp) {
            return CapEffectDecision(cancelAlarm = true)
        }
        if (!isValidCountUpAnchor(startedAt, effectNowMillis)) {
            return CapEffectDecision(cancelAlarm = true)
        }
        val cap = startedAt + COUNT_UP_CAP_MILLIS
        return if (effectNowMillis < cap) {
            CapEffectDecision(scheduleCapMillis = cap)
        } else {
            if (!capturedAtCap) {
                CapEffectDecision(cancelAlarm = true, needsRefresh = true)
            } else {
                CapEffectDecision(cancelAlarm = true, needsRefresh = false)
            }
        }
    }
}
