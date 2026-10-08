// These cases run after the production Foundation-only core is extracted into
// the same Swift file. They intentionally exercise the production declarations.

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("FAIL: \(message)")
    }
}

private func runCase(_ name: String, _ body: () -> Void) {
    body()
    print("PASS: \(name)")
}

private func millis(_ date: Date) -> Int64 {
    Int64(floor(date.timeIntervalSince1970 * 1000))
}

private func timerValues(
    countUp: Any = false,
    running: Any = false,
    saved: Any = 0,
    total: Any = 0,
    startedAt: Any = 0,
    endsAt: Any = 0
) -> [String: Any] {
    [
        "focus_timer_count_up": countUp,
        "focus_timer_running": running,
        "focus_timer_remaining_seconds": saved,
        "focus_timer_total_seconds": total,
        "focus_timer_started_at_millis": startedAt,
        "focus_timer_ends_at_millis": endsAt,
    ]
}

private func resolve(
    _ values: [String: Any],
    at date: Date,
    published: Bool = true
) -> DuoyiFocusTimerState {
    DuoyiFocusTimerState.resolve(
        values: values,
        sessionPublished: published,
        at: date
    )
}

private func gregorian(_ timeZoneID: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneID)!
    return calendar
}

private func localDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0,
    calendar: Calendar
) -> Date {
    calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    )!
}

runCase("count-up derives elapsed seconds from its start anchor") {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let start = now.addingTimeInterval(-10.875)
    let timer = resolve(
        timerValues(
            countUp: true,
            running: true,
            saved: Int64(73),
            total: Int64(0),
            startedAt: millis(start)
        ),
        at: now
    )

    expect(timer.phase == .runningCountUp, "running count-up phase")
    expect(timer.isRunning, "running count-up remains active")
    expect(timer.totalSeconds == 0, "zero count-up total is preserved")
    expect(timer.seconds == 10, "elapsed time is floored from the start anchor")
    expect(timer.seconds != 83, "stored seconds are not added to start-derived elapsed")
    expect(timer.startDate != nil, "count-up exposes its start date")
    expect(timer.endDate == nil, "count-up has no countdown end")
}

runCase("countdown rounds remaining milliseconds up to seconds") {
    let now = Date(timeIntervalSince1970: 1_000)
    let endMillis = millis(now) + 1_501
    let timer = resolve(
        timerValues(
            running: true,
            total: Int64(10),
            endsAt: endMillis
        ),
        at: now
    )

    expect(timer.phase == .runningCountdown, "countdown remains running")
    expect(timer.seconds == 2, "1.501 seconds rounds up to 2 seconds")
    expect(timer.totalSeconds == 10, "countdown total is retained")
}

runCase("countdown is ended at the exact end anchor") {
    let end = Date(timeIntervalSince1970: 1_001.501)
    let timer = resolve(
        timerValues(
            running: true,
            total: Int64(10),
            endsAt: millis(end)
        ),
        at: end
    )

    expect(timer.phase == .ended, "exact end is not a one-second countdown")
    expect(timer.seconds == 0, "ended countdown has no remaining seconds")
    expect(!timer.isRunning, "ended countdown is not running")
}

runCase("countdown seconds are clamped to the configured total") {
    let now = Date(timeIntervalSince1970: 2_000)
    let timer = resolve(
        timerValues(
            running: true,
            total: Int64(3),
            endsAt: millis(now.addingTimeInterval(12.250))
        ),
        at: now
    )

    expect(timer.phase == .runningCountdown, "clamped countdown remains running")
    expect(timer.seconds == 3, "remaining time cannot exceed its total")
    expect(timer.totalSeconds == 3, "configured total remains three seconds")
}

runCase("paused timer anchors may both be zero") {
    let now = Date(timeIntervalSince1970: 10_000)
    let pausedCountdown = resolve(
        timerValues(saved: Int64(120), total: Int64(300)),
        at: now
    )
    let pausedCountUp = resolve(
        timerValues(countUp: true, saved: Int64(120)),
        at: now
    )
    let idleCountUp = resolve(
        timerValues(countUp: true),
        at: now
    )

    expect(pausedCountdown.phase == .pausedCountdown, "paused countdown accepts zero anchors")
    expect(pausedCountdown.seconds == 120, "paused countdown retains saved seconds")
    expect(pausedCountdown.startDate == nil && pausedCountdown.endDate == nil, "paused anchors stay absent")
    expect(pausedCountUp.phase == .pausedCountUp, "positive saved count-up is paused")
    expect(pausedCountUp.seconds == 120, "paused count-up retains saved seconds")
    expect(pausedCountUp.startDate == nil && pausedCountUp.endDate == nil, "paused count-up anchors stay absent")
    expect(idleCountUp.phase == .idle, "zero paused count-up is idle")
    expect(idleCountUp.seconds == 0, "idle count-up has zero seconds")
}

runCase("countdown idle requires the complete saved duration") {
    let now = Date(timeIntervalSince1970: 10_000)
    let fullDuration = resolve(
        timerValues(saved: Int64(300), total: Int64(300)),
        at: now
    )
    let zeroSaved = resolve(
        timerValues(saved: Int64(0), total: Int64(300)),
        at: now
    )

    expect(fullDuration.phase == .idle, "complete saved countdown duration is idle")
    expect(fullDuration.seconds == 300, "idle countdown keeps its full duration")
    expect(zeroSaved.phase == .unavailable, "zero saved countdown duration is unavailable")
}

runCase("unpublished session does not restore saved timer state") {
    let now = Date(timeIntervalSince1970: 10_000)
    let timer = resolve(
        timerValues(
            countUp: true,
            running: true,
            saved: Int64(90),
            total: Int64(900),
            startedAt: millis(now.addingTimeInterval(-90))
        ),
        at: now,
        published: false
    )

    expect(timer.phase == .unavailable, "unpublished timer is unavailable")
    expect(timer.seconds == 0 && timer.totalSeconds == 0, "unpublished timer clears values")
    expect(timer.startDate == nil && timer.endDate == nil, "unpublished timer clears anchors")
}

runCase("focus action intent depends on a fresh timer phase") {
    let now = Date(timeIntervalSince1970: 10_000)
    let idle = resolve(timerValues(saved: Int64(300), total: Int64(300)), at: now)
    let paused = resolve(
        timerValues(saved: Int64(120), total: Int64(300)),
        at: now
    )
    let running = resolve(
        timerValues(
            running: true,
            total: Int64(300),
            endsAt: millis(now.addingTimeInterval(120))
        ),
        at: now
    )
    let ended = resolve(
        timerValues(
            running: true,
            total: Int64(300),
            endsAt: millis(now)
        ),
        at: now
    )

    expect(idle.phase == .idle, "fresh idle timer resolves as idle")
    expect(idle.actionIntent(isDailyFresh: true) == .start, "fresh idle timer starts")
    expect(paused.actionIntent(isDailyFresh: true) == .resume, "fresh paused timer resumes")
    expect(running.actionIntent(isDailyFresh: true) == .open, "running timer opens focus screen")
    expect(ended.actionIntent(isDailyFresh: true) == .open, "ended timer opens focus screen")
    expect(DuoyiFocusTimerState.unavailable.actionIntent(isDailyFresh: true) == .open,
           "unavailable timer opens focus screen")
    expect(idle.actionIntent(isDailyFresh: false) == .open, "daily-stale idle timer opens focus screen")
}

runCase("future count-up start stays running and exposes its start and cap") {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let startMillis = millis(now.addingTimeInterval(30))
    let start = Date(timeIntervalSince1970: Double(startMillis) / 1000)
    let timer = resolve(
        timerValues(
            countUp: true,
            running: true,
            startedAt: startMillis
        ),
        at: now
    )
    let dates = DuoyiFocusTimerTimeline.dates(
        now: now,
        timer: timer,
        calendar: gregorian()
    )

    expect(timer.phase == .runningCountUp && timer.isRunning, "future start is still running")
    expect(timer.seconds == 0, "future count-up elapsed time is clamped to zero")
    expect(timer.hasFutureStart, "future start is identified")
    expect(timer.startDate == start, "future start anchor is retained")
    expect(
        timer.capDate == start.addingTimeInterval(86_400),
        "future count-up exposes a cap one day after its start"
    )
    expect(dates.contains(start), "timeline includes future start")
    expect(dates.contains(timer.capDate!), "timeline includes future cap")
}

runCase("count-up remains running when its 24-hour cap is reached") {
    let now = Date(timeIntervalSince1970: 200_000)
    let startMillis = millis(now.addingTimeInterval(-86_400))
    let timer = resolve(
        timerValues(
            countUp: true,
            running: true,
            startedAt: startMillis
        ),
        at: now
    )

    expect(timer.phase == .runningCountUp, "cap does not convert count-up to ended")
    expect(timer.isRunning, "count-up remains running at its cap")
    expect(timer.seconds == 86_400, "elapsed count-up seconds stop at 24 hours")
    expect(timer.isAtCountUpCap, "cap state is exposed")
    expect(timer.capDate == now, "count-up cap date equals the current date")
}

runCase("count-up reaches its cap from a nonzero millisecond start anchor") {
    let startedAtMillis: Int64 = 1_800_000_000_371
    let values = timerValues(
        countUp: true,
        running: true,
        startedAt: startedAtMillis
    )
    let startDate = Date(timeIntervalSince1970: Double(startedAtMillis) / 1000)
    let beforeCap = resolve(values, at: startDate)
    let capDate = beforeCap.capDate!
    let atCap = resolve(values, at: capDate)

    expect(beforeCap.phase == .runningCountUp, "nonzero millisecond start resolves as running")
    expect(atCap.phase == .runningCountUp, "reaching the cap does not end count-up")
    expect(atCap.isRunning, "count-up stays running at its cap")
    expect(atCap.seconds == 86_400, "cap date resolves to exactly 24 hours")
    expect(atCap.isAtCountUpCap, "cap date sets the cap state")
}

runCase("missing, malformed, negative, and unrepresentable inputs are unavailable") {
    let now = Date(timeIntervalSince1970: 10_000)
    func isUnavailable(_ input: [String: Any], at date: Date = now) -> Bool {
        resolve(input, at: date).phase == .unavailable
    }

    var missing = timerValues()
    missing.removeAll()
    expect(isUnavailable(missing), "missing timer input defaults to unavailable")

    var missingRunningStart = timerValues(countUp: true, running: true)
    missingRunningStart.removeValue(forKey: "focus_timer_started_at_millis")
    expect(isUnavailable(missingRunningStart), "running count-up requires a start anchor")

    var missingRunningTotal = timerValues(
        running: true,
        total: Int64(60),
        endsAt: millis(now.addingTimeInterval(30))
    )
    missingRunningTotal.removeValue(forKey: "focus_timer_total_seconds")
    expect(isUnavailable(missingRunningTotal), "running countdown requires a positive total")

    expect(
        isUnavailable(timerValues(total: Int64(-1))),
        "negative integer input is rejected"
    )
    expect(
        isUnavailable(timerValues(saved: NSNumber(value: true))),
        "Boolean values are not accepted as integer seconds"
    )
    expect(
        isUnavailable(timerValues(total: NSNumber(value: 1.5))),
        "fractional seconds are rejected"
    )
    expect(
        isUnavailable(timerValues(total: NSNumber(value: Double.nan))),
        "NaN input is rejected"
    )
    expect(
        isUnavailable(timerValues(total: NSNumber(value: Double.greatestFiniteMagnitude))),
        "overflowing numeric input is rejected"
    )
    expect(
        isUnavailable(
            timerValues(countUp: true, running: true, startedAt: Int64.max)
        ),
        "NSDate-unrepresentable anchor is rejected"
    )
    expect(
        isUnavailable(
            timerValues(countUp: true, running: true, startedAt: millis(now)),
            at: Date(timeIntervalSince1970: Double.infinity)
        ),
        "NSDate-unrepresentable current date is rejected"
    )
}

runCase("seconds and total stay safe for accessory plus-59 formatting") {
    let now = Date(timeIntervalSince1970: 200_000)
    let countUp = resolve(
        timerValues(
            countUp: true,
            saved: Int64.max,
            total: Int64.max
        ),
        at: now
    )
    let safeLimit = Int.max - 59
    let countdown = resolve(
        timerValues(saved: Int64.max - 1, total: Int64.max),
        at: now
    )

    expect(countUp.phase == .pausedCountUp, "large paused count-up remains valid")
    expect(countUp.seconds <= safeLimit, "count-up seconds cannot overflow accessory rounding")
    expect(countUp.totalSeconds == safeLimit, "count-up total is clamped to the display-safe limit")
    expect(countUp.seconds + 59 <= Int.max, "count-up accessory plus-59 arithmetic is safe")
    expect(countdown.phase == .pausedCountdown, "large paused countdown remains valid")
    expect(countdown.seconds == safeLimit, "countdown seconds are clamped before accessory rounding")
    expect(countdown.totalSeconds == safeLimit, "countdown total is clamped to the display-safe limit")
    expect(countdown.seconds + 59 <= Int.max, "countdown accessory plus-59 arithmetic is safe")
}

runCase("timeline sorts and deduplicates midnight with an equal timer end") {
    let calendar = gregorian()
    let now = localDate(2026, 4, 5, hour: 23, minute: 0, second: 17, calendar: calendar)
    let midnight = calendar.dateInterval(of: .day, for: now)!.end
    let timer = resolve(
        timerValues(
            running: true,
            total: Int64(3_600),
            endsAt: millis(midnight)
        ),
        at: now
    )
    let dates = DuoyiFocusTimerTimeline.dates(now: now, timer: timer, calendar: calendar)

    expect(timer.phase == .runningCountdown, "timer end at midnight is still future")
    expect(dates == [now, midnight], "midnight and equal timer end are deduplicated")
    expect(dates.filter { $0 == midnight }.count == 1, "one midnight refresh is scheduled")
}

runCase("timeline retains the exact seconds of midnight and timer-end refreshes") {
    let calendar = gregorian()
    let now = localDate(2026, 4, 5, hour: 22, minute: 30, second: 17, calendar: calendar)
    let endMillis = millis(now.addingTimeInterval(17.321))
    let timer = resolve(
        timerValues(running: true, total: Int64(1_800), endsAt: endMillis),
        at: now
    )
    let dates = DuoyiFocusTimerTimeline.dates(now: now, timer: timer, calendar: calendar)
    let midnight = calendar.dateInterval(of: .day, for: now)!.end
    let end = timer.endDate!

    expect(abs(end.timeIntervalSince(now) - 17.321) < 0.002, "timer end keeps its millisecond anchor")
    expect(abs(midnight.timeIntervalSince(now) - 5_383) < 0.001, "midnight keeps its local second")
    expect(dates.contains(end), "timeline contains the timer end")
    expect(dates.contains(midnight), "timeline contains the next local midnight")
}

runCase("running countdown updates across UTC midnight and ends at its anchor") {
    let calendar = gregorian()
    let now = localDate(2026, 4, 5, hour: 23, minute: 55, calendar: calendar)
    let midnight = localDate(2026, 4, 6, calendar: calendar)
    let end = localDate(2026, 4, 6, hour: 0, minute: 20, calendar: calendar)
    let values = timerValues(
        running: true,
        total: Int64(3_600),
        endsAt: millis(end)
    )
    let atStart = resolve(values, at: now)
    let atMidnight = resolve(values, at: midnight)
    let atEnd = resolve(values, at: end)

    expect(atStart.phase == .runningCountdown, "countdown is running before midnight")
    expect(atStart.seconds == 1_500, "23:55 has 25 minutes remaining")
    expect(atMidnight.phase == .runningCountdown, "countdown is running after midnight")
    expect(atMidnight.seconds == 1_200, "00:00 has 20 minutes remaining")
    expect(atEnd.phase == .ended, "countdown ends at 00:20")
    expect(atEnd.seconds == 0, "ended countdown has no remaining seconds")
}

runCase("paused countdown keeps its saved seconds across UTC midnight") {
    let calendar = gregorian()
    let now = localDate(2026, 4, 5, hour: 23, minute: 55, calendar: calendar)
    let midnight = localDate(2026, 4, 6, calendar: calendar)
    let values = timerValues(saved: Int64(120), total: Int64(3_600))
    let beforeMidnight = resolve(values, at: now)
    let afterMidnight = resolve(values, at: midnight)

    expect(beforeMidnight.phase == .pausedCountdown, "saved countdown is paused before midnight")
    expect(afterMidnight.phase == .pausedCountdown, "saved countdown stays paused after midnight")
    expect(beforeMidnight.seconds == 120, "paused countdown keeps 120 seconds before midnight")
    expect(afterMidnight.seconds == 120, "paused countdown keeps 120 seconds after midnight")
}

runCase("timeline uses real 23-hour and 25-hour daylight-saving days") {
    let calendar = gregorian("America/New_York")
    let idle = resolve(timerValues(countUp: true), at: Date(timeIntervalSince1970: 1_700_000_000))
    let springStart = localDate(2026, 3, 8, calendar: calendar)
    let fallStart = localDate(2026, 11, 1, calendar: calendar)
    let springMidnight = calendar.dateInterval(of: .day, for: springStart)!.end
    let fallMidnight = calendar.dateInterval(of: .day, for: fallStart)!.end
    let springTransition = calendar.timeZone.nextDaylightSavingTimeTransition(after: springStart)!
    let fallTransition = calendar.timeZone.nextDaylightSavingTimeTransition(after: fallStart)!
    let springDates = DuoyiFocusTimerTimeline.dates(
        now: springStart,
        timer: idle,
        calendar: calendar
    )
    let fallDates = DuoyiFocusTimerTimeline.dates(
        now: fallStart,
        timer: idle,
        calendar: calendar
    )

    expect(
        springMidnight.timeIntervalSince(springStart) == 23 * 60 * 60,
        "spring-forward day ends after 23 elapsed hours"
    )
    expect(
        fallMidnight.timeIntervalSince(fallStart) == 25 * 60 * 60,
        "fall-back day ends after 25 elapsed hours"
    )
    expect(springDates.contains(springMidnight), "spring-forward next local midnight is scheduled")
    expect(fallDates.contains(fallMidnight), "fall-back next local midnight is scheduled")
    expect(springDates.contains(springTransition), "spring daylight-saving transition is scheduled")
    expect(fallDates.contains(fallTransition), "fall daylight-saving transition is scheduled")
}

runCase("timeline includes only deadlines at or before the 48-hour horizon") {
    let calendar = gregorian()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let timer = resolve(
        timerValues(
            running: true,
            total: Int64(200_000),
            endsAt: millis(now.addingTimeInterval(48 * 60 * 60 + 1))
        ),
        at: now
    )
    let dates = DuoyiFocusTimerTimeline.dates(now: now, timer: timer, calendar: calendar)
    let horizon = now.addingTimeInterval(48 * 60 * 60)

    expect(timer.phase == .runningCountdown, "long countdown remains running")
    expect(dates.allSatisfy { $0 <= horizon }, "all timeline dates stay within 48 hours")
    expect(!dates.contains(timer.endDate!), "end beyond 48 hours is not scheduled")
}

print("PASS: all production-extracted timer core cases")
