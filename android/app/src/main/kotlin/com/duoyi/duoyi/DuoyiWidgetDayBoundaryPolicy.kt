package com.duoyi.duoyi

import java.time.Instant
import java.time.ZoneId

/** Local civil-day arithmetic; a day is not always 24 hours long. */
object DuoyiWidgetDayBoundaryPolicy {
    fun nextBoundaryAt(nowMillis: Long, zone: ZoneId): Long {
        val now = Instant.ofEpochMilli(nowMillis)
        var nextDate = now.atZone(zone).toLocalDate().plusDays(1)
        var nextDay = nextDate.atStartOfDay(zone).toInstant()
        while (!nextDay.isAfter(now)) {
            nextDate = nextDate.plusDays(1)
            nextDay = nextDate.atStartOfDay(zone).toInstant()
        }
        val transition = zone.rules.nextTransition(now)?.instant
            ?.takeIf { it.isAfter(now) }
        return if (transition != null && transition.isBefore(nextDay)) {
            transition.toEpochMilli()
        } else {
            nextDay.toEpochMilli()
        }
    }
}

/** The production Android alarm adapter and unit fixtures use the same controller. */
interface DuoyiWidgetBoundaryAlarmPort {
    fun schedule(atMillis: Long): Boolean
    fun cancel(): Boolean
}

enum class DuoyiWidgetBoundaryOutcome { SCHEDULED, UNCHANGED, CANCELLED, FAILED }

data class DuoyiWidgetBoundaryResult(
    val outcome: DuoyiWidgetBoundaryOutcome,
    val atMillis: Long? = null,
)

class DuoyiWidgetBoundaryController {
    private var scheduledAt: Long? = null

    @Synchronized
    fun invalidate() {
        scheduledAt = null
    }

    @Synchronized
    fun reconcile(
        nowMillis: Long,
        zone: ZoneId,
        installedWidgetCount: Int,
        alarm: DuoyiWidgetBoundaryAlarmPort,
        force: Boolean = false,
    ): DuoyiWidgetBoundaryResult {
        require(installedWidgetCount >= 0)
        if (installedWidgetCount == 0) {
            scheduledAt = null
            return DuoyiWidgetBoundaryResult(
                if (alarm.cancel()) DuoyiWidgetBoundaryOutcome.CANCELLED else DuoyiWidgetBoundaryOutcome.FAILED,
            )
        }
        val next = DuoyiWidgetDayBoundaryPolicy.nextBoundaryAt(nowMillis, zone)
        if (!force && scheduledAt == next) {
            return DuoyiWidgetBoundaryResult(DuoyiWidgetBoundaryOutcome.UNCHANGED, next)
        }
        // A failed/throwing handoff must remain retryable on the next lifecycle event.
        scheduledAt = null
        if (!alarm.schedule(next)) {
            return DuoyiWidgetBoundaryResult(DuoyiWidgetBoundaryOutcome.FAILED, next)
        }
        scheduledAt = next
        return DuoyiWidgetBoundaryResult(DuoyiWidgetBoundaryOutcome.SCHEDULED, next)
    }
}
