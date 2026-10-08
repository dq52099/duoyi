// These cases run beside the production Foundation-only snapshot declarations.

private func snapshotExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("FAIL: \(message)")
    }
}

private func snapshotRunCase(_ name: String, _ body: () -> Void) {
    body()
    print("PASS: \(name)")
}

private func snapshotValues(
    day: Any? = "2026-04-05",
    offset: Any? = 0,
    nonce: Any? = "snapshot-nonce"
) -> [String: Any] {
    var values: [String: Any] = [:]
    if let day = day { values["widget_snapshot_day"] = day }
    if let offset = offset { values["widget_snapshot_utc_offset_minutes"] = offset }
    if let nonce = nonce { values["widget_account_nonce"] = nonce }
    return values
}

private func snapshotGregorianCalendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

private func snapshotTimeZone(_ identifier: String) -> TimeZone {
    guard let timeZone = TimeZone(identifier: identifier) else {
        fatalError("FAIL: time zone is unavailable: \(identifier)")
    }
    return timeZone
}

private func snapshotFixedTimeZone(_ offsetMinutes: Int) -> TimeZone {
    guard let timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60) else {
        fatalError("FAIL: fixed time zone is unavailable: \(offsetMinutes) minutes")
    }
    return timeZone
}

private func snapshotLocalDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0,
    calendar: Calendar
) -> Date {
    guard let date = calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    ) else {
        fatalError("FAIL: could not construct fixture date \(year)-\(month)-\(day)")
    }
    return date
}

private func snapshotCanonicalDay(_ date: Date, timeZone: TimeZone) -> String {
    let calendar = snapshotGregorianCalendar(timeZone)
    let fields = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = fields.year, let month = fields.month, let day = fields.day else {
        fatalError("FAIL: could not extract fixture Gregorian day")
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
}

private func snapshotComponents(
    scheme: String = "duoyi",
    host: String = "action",
    path: String,
    queryItems: [URLQueryItem] = []
) -> URLComponents {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = path.hasPrefix("/") ? path : "/\(path)"
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    return components
}

private func snapshotPercentEncodedComponents(
    _ encodedPath: String,
    queryItems: [URLQueryItem] = []
) -> URLComponents {
    var components = snapshotComponents(path: "/")
    components.percentEncodedPath = encodedPath
    components.queryItems = queryItems.isEmpty ? nil : queryItems
    return components
}

private func snapshotQueryItems(_ url: URL) -> [URLQueryItem] {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        fatalError("FAIL: could not parse returned action URL")
    }
    return components.queryItems ?? []
}

private func snapshotAssertBindings(
    _ url: URL?,
    day: String,
    offset: Int,
    nonce: String,
    context: String
) {
    guard let url = url else {
        fatalError("FAIL: \(context) did not return a mutation URL")
    }
    let items = snapshotQueryItems(url)
    let expected: [(String, String)] = [
        ("source", "widget"),
        ("widget_day", day),
        ("widget_offset", String(offset)),
        ("widget_account", nonce),
    ]
    for (name, value) in expected {
        let matches = items.filter { $0.name == name }
        snapshotExpect(matches.count == 1, "\(context) has one \(name) binding")
        snapshotExpect(matches.first?.value == value, "\(context) binds the frozen \(name)")
    }
}

private func snapshotAssertNoBindings(_ url: URL, context: String) {
    let bindingKeys: Set<String> = ["source", "widget_day", "widget_offset", "widget_account"]
    let items = snapshotQueryItems(url)
    snapshotExpect(
        items.allSatisfy { !bindingKeys.contains($0.name) },
        "\(context) does not add widget mutation bindings"
    )
}

snapshotRunCase("valid UTC, East-8, and half-hour offsets publish fresh sessions") {
    let zones: [(String, TimeZone, Int)] = [
        ("UTC", snapshotTimeZone("UTC"), 0),
        ("East-8", snapshotTimeZone("Asia/Shanghai"), 480),
        ("half-hour", snapshotTimeZone("Asia/Kolkata"), 330),
    ]

    for (name, timeZone, offset) in zones {
        let calendar = snapshotGregorianCalendar(timeZone)
        let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
        let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
            day: snapshotCanonicalDay(date, timeZone: timeZone),
            offset: offset,
            nonce: "nonce-\(name)"
        ))

        snapshotExpect(snapshot.hasPublishedSession, "\(name) snapshot is published")
        snapshotExpect(snapshot.isFresh(at: date, calendar: calendar), "\(name) offset is fresh")
    }

    let stringOffsetSnapshot = DuoyiWidgetSnapshot(values: snapshotValues(offset: "480"))
    snapshotExpect(stringOffsetSnapshot.hasPublishedSession, "integer offset strings are parsed")
}

snapshotRunCase("positive and negative 18-hour offsets are valid boundaries") {
    for offset in [-1_080, 1_080] {
        let timeZone = snapshotFixedTimeZone(offset)
        let calendar = snapshotGregorianCalendar(timeZone)
        let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
        let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
            day: "2026-04-05",
            offset: offset,
            nonce: "boundary-\(offset)"
        ))

        snapshotExpect(snapshot.hasPublishedSession, "\(offset) minute offset publishes")
        snapshotExpect(snapshot.isFresh(at: date, calendar: calendar), "\(offset) minute offset is fresh")
    }

    let tooFarEast = DuoyiWidgetSnapshot(values: snapshotValues(offset: 1_081))
    let tooFarWest = DuoyiWidgetSnapshot(values: snapshotValues(offset: -1_081))
    snapshotExpect(!tooFarEast.hasPublishedSession, "offset above +18 hours is rejected")
    snapshotExpect(!tooFarWest.hasPublishedSession, "offset below -18 hours is rejected")
}

snapshotRunCase("Boolean, fractional, nonfinite, and overflowing offsets are rejected") {
    let invalidOffsets: [(String, Any)] = [
        ("Boolean zero", NSNumber(value: false)),
        ("Boolean one", NSNumber(value: true)),
        ("fraction", NSNumber(value: 0.5)),
        ("NaN", NSNumber(value: Double.nan)),
        ("infinity", NSNumber(value: Double.infinity)),
        ("huge finite number", NSNumber(value: Double.greatestFiniteMagnitude)),
        ("integer overflow", NSNumber(value: Int64.max)),
        ("fractional text", "480.5"),
    ]

    for (name, offset) in invalidOffsets {
        let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(offset: offset))
        snapshotExpect(!snapshot.hasPublishedSession, "\(name) offset is invalid")
    }
}

snapshotRunCase("missing, malformed, and non-Gregorian dates cannot publish") {
    let invalidDays = [
        "2026-4-05",
        "2026-04-5",
        "2026-02-29",
        "2026-02-30",
        "2026-04-05 ",
        "not-a-day",
    ]

    let missingDay = DuoyiWidgetSnapshot(values: snapshotValues(day: nil))
    snapshotExpect(!missingDay.hasPublishedSession, "missing day is rejected")
    for day in invalidDays {
        let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(day: day))
        snapshotExpect(!snapshot.hasPublishedSession, "invalid day \(day) is rejected")
    }

    let missingOffset = DuoyiWidgetSnapshot(values: snapshotValues(offset: nil))
    let missingNonce = DuoyiWidgetSnapshot(values: snapshotValues(nonce: nil))
    let emptyNonce = DuoyiWidgetSnapshot(values: snapshotValues(nonce: ""))
    snapshotExpect(!missingOffset.hasPublishedSession, "missing offset is rejected")
    snapshotExpect(!missingNonce.hasPublishedSession, "missing nonce is rejected")
    snapshotExpect(!emptyNonce.hasPublishedSession, "empty nonce is rejected")
}

snapshotRunCase("canonical leap day and raw nonce strings are preserved") {
    let utc = snapshotTimeZone("UTC")
    let calendar = snapshotGregorianCalendar(utc)
    let leapDay = snapshotLocalDate(2024, 2, 29, hour: 12, calendar: calendar)
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2024-02-29",
        offset: 0,
        nonce: "  raw nonce  "
    ))

    snapshotExpect(snapshot.hasPublishedSession, "valid leap day publishes")
    snapshotExpect(snapshot.isFresh(at: leapDay, calendar: calendar), "valid leap day is fresh")

    let components = snapshotComponents(
        path: "complete_todo",
        queryItems: [URLQueryItem(name: "id", value: "todo-29")]
    )
    let url = snapshot.actionURL(components, at: leapDay, calendar: calendar)
    snapshotAssertBindings(
        url,
        day: "2024-02-29",
        offset: 0,
        nonce: "  raw nonce  ",
        context: "raw nonce action"
    )
}

snapshotRunCase("whitespace-only nonce is rejected without trimming stored values") {
    let utc = snapshotTimeZone("UTC")
    let calendar = snapshotGregorianCalendar(utc)
    let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
    let rawNonce = "  "
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-04-05",
        offset: 0,
        nonce: rawNonce
    ))

    snapshotExpect(!snapshot.hasPublishedSession, "whitespace-only nonce is unpublished")
    snapshotExpect(!snapshot.isFresh(at: date, calendar: calendar), "whitespace-only nonce is stale")
    let url = snapshot.actionURL(
        snapshotComponents(path: "complete_todo"),
        at: date,
        calendar: calendar
    )
    snapshotExpect(url == nil, "mutation with whitespace-only nonce is withheld")
}

snapshotRunCase("published prior-day snapshots remain published but become stale") {
    let utc = snapshotTimeZone("UTC")
    let calendar = snapshotGregorianCalendar(utc)
    let beforeMidnight = snapshotLocalDate(2026, 4, 5, hour: 23, minute: 55, calendar: calendar)
    let afterMidnight = snapshotLocalDate(2026, 4, 6, hour: 0, minute: 5, calendar: calendar)
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-04-05",
        offset: 0,
        nonce: "frozen-prior-day"
    ))

    snapshotExpect(snapshot.hasPublishedSession, "prior-day session stays published for timer reads")
    snapshotExpect(snapshot.isFresh(at: beforeMidnight, calendar: calendar), "prior day is fresh before midnight")
    snapshotExpect(!snapshot.isFresh(at: afterMidnight, calendar: calendar), "prior day is stale after midnight")
}

snapshotRunCase("daylight-saving offset changes stale same-day snapshots") {
    let timeZone = snapshotTimeZone("America/New_York")
    let calendar = snapshotGregorianCalendar(timeZone)
    let beforeTransition = snapshotLocalDate(2026, 3, 8, hour: 1, minute: 59, calendar: calendar)
    let afterTransition = snapshotLocalDate(2026, 3, 8, hour: 3, minute: 0, calendar: calendar)
    let beforeOffset = timeZone.secondsFromGMT(for: beforeTransition) / 60
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-03-08",
        offset: beforeOffset,
        nonce: "before-dst"
    ))

    snapshotExpect(beforeOffset == -300, "fixture starts on the New York standard offset")
    snapshotExpect(snapshot.hasPublishedSession, "pre-transition session remains published")
    snapshotExpect(snapshot.isFresh(at: beforeTransition, calendar: calendar), "snapshot is fresh before DST")
    snapshotExpect(!snapshot.isFresh(at: afterTransition, calendar: calendar), "old offset is stale after DST")
}

snapshotRunCase("freshness uses Gregorian dates with any injected calendar identifier") {
    let timeZone = snapshotTimeZone("Asia/Kolkata")
    let date = snapshotLocalDate(2024, 2, 29, hour: 12, calendar: snapshotGregorianCalendar(timeZone))
    var buddhistCalendar = Calendar(identifier: .buddhist)
    buddhistCalendar.timeZone = timeZone
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2024-02-29",
        offset: 330,
        nonce: "calendar-independent"
    ))

    snapshotExpect(
        snapshot.isFresh(at: date, calendar: buddhistCalendar),
        "non-Gregorian identifier still computes the Gregorian local day"
    )
}

snapshotRunCase("nonfinite dates are stale without producing a session day") {
    let calendar = snapshotGregorianCalendar(snapshotTimeZone("UTC"))
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues())
    let infiniteDate = Date(timeIntervalSince1970: Double.infinity)
    let nanDate = Date(timeIntervalSince1970: Double.nan)

    snapshotExpect(!snapshot.isFresh(at: infiniteDate, calendar: calendar), "infinite date is stale")
    snapshotExpect(!snapshot.isFresh(at: nanDate, calendar: calendar), "NaN date is stale")
}

snapshotRunCase("mutation links freeze snapshot bindings and remove duplicate query keys") {
    let timeZone = snapshotTimeZone("Asia/Shanghai")
    let calendar = snapshotGregorianCalendar(timeZone)
    let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
    let rawNonce = "  frozen nonce  "
    var values = snapshotValues(day: "2026-04-05", offset: 480, nonce: rawNonce)
    let snapshot = DuoyiWidgetSnapshot(values: values)
    values["widget_snapshot_day"] = "2026-04-06"
    values["widget_snapshot_utc_offset_minutes"] = -300
    values["widget_account_nonce"] = "newer-account-nonce"

    let components = snapshotComponents(
        path: "complete_todo",
        queryItems: [
            URLQueryItem(name: "id", value: "todo-42"),
            URLQueryItem(name: "source", value: "stale-source-a"),
            URLQueryItem(name: "source", value: "stale-source-b"),
            URLQueryItem(name: "widget_day", value: "stale-day"),
            URLQueryItem(name: "widget_offset", value: "-300"),
            URLQueryItem(name: "widget_account", value: "newer-account-nonce"),
        ]
    )
    let url = snapshot.actionURL(components, at: date, calendar: calendar)

    snapshotAssertBindings(
        url,
        day: "2026-04-05",
        offset: 480,
        nonce: rawNonce,
        context: "duplicate-key completion action"
    )
    let queryItems = snapshotQueryItems(url!)
    snapshotExpect(queryItems.contains { $0.name == "id" && $0.value == "todo-42" }, "action item id is preserved")
}

snapshotRunCase("all mutation actions bind and typed quick todos count as mutations") {
    let timeZone = snapshotTimeZone("UTC")
    let calendar = snapshotGregorianCalendar(timeZone)
    let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-04-05",
        offset: 0,
        nonce: "mutation-nonce"
    ))
    let actions: [(String, [URLQueryItem])] = [
        ("complete_todo", [URLQueryItem(name: "id", value: "todo-1")]),
        ("checkin_habit", [URLQueryItem(name: "id", value: "habit-2")]),
        ("start_pomodoro", [URLQueryItem(name: "id", value: "focus-3")]),
        ("quick_todo", [URLQueryItem(name: "text", value: "Buy milk")]),
    ]

    for (action, queryItems) in actions {
        let components = snapshotComponents(path: action, queryItems: queryItems)
        let url = snapshot.actionURL(components, at: date, calendar: calendar)
        snapshotAssertBindings(
            url,
            day: "2026-04-05",
            offset: 0,
            nonce: "mutation-nonce",
            context: action
        )
    }
}

snapshotRunCase("stale day and offset mutations are withheld") {
    let utc = snapshotTimeZone("UTC")
    let utcCalendar = snapshotGregorianCalendar(utc)
    let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: utcCalendar)
    let nextDay = snapshotLocalDate(2026, 4, 6, hour: 0, minute: 5, calendar: utcCalendar)
    let mutation = snapshotComponents(path: "complete_todo")
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-04-05",
        offset: 0,
        nonce: "stale-check"
    ))
    let staleDayURL = snapshot.actionURL(mutation, at: nextDay, calendar: utcCalendar)

    snapshotExpect(staleDayURL == nil, "mutation for a prior local day is withheld")

    let newYorkCalendar = snapshotGregorianCalendar(snapshotTimeZone("America/New_York"))
    let staleOffsetURL = snapshot.actionURL(mutation, at: date, calendar: newYorkCalendar)
    snapshotExpect(staleOffsetURL == nil, "mutation with a stale UTC offset is withheld")
}

snapshotRunCase("action routing follows the receiver first literal path segment") {
    let utc = snapshotTimeZone("UTC")
    let calendar = snapshotGregorianCalendar(utc)
    let freshDate = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
    let staleDate = snapshotLocalDate(2026, 4, 6, hour: 0, minute: 5, calendar: calendar)
    let freshSnapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-04-05",
        offset: 0,
        nonce: "path-routing"
    ))
    let staleSnapshot = DuoyiWidgetSnapshot(values: snapshotValues(
        day: "2026-04-05",
        offset: 0,
        nonce: "stale-path-routing"
    ))

    let staleCanonicalPaths: [(String, URLComponents)] = [
        ("tail segment", snapshotComponents(path: "complete_todo/ignored")),
        ("trailing slash", snapshotComponents(path: "complete_todo/")),
        (
            "percent-encoded first action segment",
            snapshotPercentEncodedComponents("/complete%5Ftodo/ignored")
        ),
    ]
    for (name, components) in staleCanonicalPaths {
        let url = staleSnapshot.actionURL(components, at: staleDate, calendar: calendar)
        snapshotExpect(url == nil, "stale canonical action with \(name) is withheld")
    }

    let freshTail = snapshotComponents(
        path: "complete_todo/ignored",
        queryItems: [URLQueryItem(name: "id", value: "todo-tail")]
    )
    let freshTailURL = freshSnapshot.actionURL(freshTail, at: freshDate, calendar: calendar)
    snapshotAssertBindings(
        freshTailURL,
        day: "2026-04-05",
        offset: 0,
        nonce: "path-routing",
        context: "fresh action with trailing segment"
    )

    let encodedSlash = snapshotPercentEncodedComponents("/complete_todo%2Fignored")
    let doubleLeadingSlash = snapshotPercentEncodedComponents("//complete_todo")
    for (name, components) in [
        ("encoded slash inside action", encodedSlash),
        ("double leading slash", doubleLeadingSlash),
    ] {
        let staleURL = staleSnapshot.actionURL(components, at: staleDate, calendar: calendar)
        snapshotExpect(staleURL == components.url, "unrecognized \(name) remains navigation when stale")
        snapshotAssertNoBindings(staleURL!, context: "stale \(name)")

        let freshURL = freshSnapshot.actionURL(components, at: freshDate, calendar: calendar)
        snapshotExpect(freshURL == components.url, "unrecognized \(name) remains navigation when fresh")
        snapshotAssertNoBindings(freshURL!, context: "fresh \(name)")
    }
}

snapshotRunCase("navigation, refresh, and empty quick entry add no bindings") {
    let calendar = snapshotGregorianCalendar(snapshotTimeZone("UTC"))
    let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues())
    let ordinaryNavigation = snapshotComponents(host: "todo", path: "/")
    let refresh = snapshotComponents(path: "refresh")
    let emptyQuickEntry = snapshotComponents(
        path: "quick_todo",
        queryItems: [URLQueryItem(name: "text", value: "")]
    )
    let whitespaceQuickEntry = snapshotComponents(
        path: "quick_todo",
        queryItems: [URLQueryItem(name: "text", value: "  \n ")]
    )

    for (name, components) in [
        ("navigation", ordinaryNavigation),
        ("refresh", refresh),
        ("empty quick entry", emptyQuickEntry),
        ("whitespace quick entry", whitespaceQuickEntry),
    ] {
        let url = snapshot.actionURL(components, at: date, calendar: calendar)
        snapshotExpect(url == components.url, "\(name) URL is unchanged")
        snapshotAssertNoBindings(url!, context: name)
    }
}

snapshotRunCase("foreign action hosts do not receive widget bindings") {
    let calendar = snapshotGregorianCalendar(snapshotTimeZone("UTC"))
    let date = snapshotLocalDate(2026, 4, 5, hour: 12, calendar: calendar)
    let snapshot = DuoyiWidgetSnapshot(values: snapshotValues())
    let foreign = snapshotComponents(
        scheme: "https",
        path: "complete_todo",
        queryItems: [URLQueryItem(name: "id", value: "web-1")]
    )
    let url = snapshot.actionURL(foreign, at: date, calendar: calendar)

    snapshotExpect(url == foreign.url, "HTTPS action host remains unchanged")
    snapshotAssertNoBindings(url!, context: "HTTPS action host")
}

snapshotRunCase("nil components and legacy wrappers keep safe behavior") {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar = snapshotGregorianCalendar(snapshotTimeZone("UTC"))
    let empty = DuoyiWidgetSnapshot.empty
    let navigation = snapshotComponents(host: "todo", path: "/")

    snapshotExpect(!empty.isFresh(at: date), "legacy freshness wrapper rejects empty snapshot")
    snapshotExpect(empty.actionURL(nil) == nil, "legacy URL wrapper accepts nil components")
    snapshotExpect(empty.actionURL(navigation) == navigation.url, "legacy URL wrapper preserves navigation")
    snapshotExpect(
        empty.actionURL(nil, at: date, calendar: calendar) == nil,
        "injected URL overload accepts nil components"
    )
}

print("PASS: all production-extracted snapshot core cases")
