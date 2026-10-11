// These cases run beside the production Foundation-only display declarations.
// The verifier inserts the marked source from DuoyiWidgets.swift before this file.

private func displayExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("FAIL: \(message)")
    }
}

private func displayRunCase(_ name: String, _ body: () -> Void) {
    body()
    print("PASS: \(name)")
}

private func displayTimeZone(_ identifier: String) -> TimeZone {
    guard let timeZone = TimeZone(identifier: identifier) else {
        fatalError("FAIL: time zone is unavailable: \(identifier)")
    }
    return timeZone
}

private func displayFixedTimeZone(_ offsetSeconds: Int) -> TimeZone {
    guard let timeZone = TimeZone(secondsFromGMT: offsetSeconds) else {
        fatalError("FAIL: fixed time zone is unavailable: \(offsetSeconds) seconds")
    }
    return timeZone
}

private func displayGregorian(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}

private func displayLocalDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    calendar: Calendar
) -> Date {
    guard let date = calendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    ) else {
        fatalError("FAIL: could not construct fixture date \(year)-\(month)-\(day)")
    }
    return date
}

private func displayUTCInstant(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: value) else {
        fatalError("FAIL: could not parse ISO-8601 fixture instant: \(value)")
    }
    return date
}

private func displayAssertParsedAnniversary(
    _ raw: String?,
    target: String,
    identity: String?,
    context: String
) {
    let parsed = DuoyiWidgetDisplayCore.parseAnniversaryTarget(raw)
    displayExpect(parsed.target == target, "\(context) target is canonical and safe")
    displayExpect(parsed.identity == identity, "\(context) identity matches the target")
}

private func displayAssertGrid(
    _ grid: DuoyiMonthGridModel,
    expectedDays: Int,
    context: String
) {
    displayExpect(grid.cells.count == 42, "\(context) always has 42 cells")
    let dateCells = grid.cells.filter { $0.dayNumber > 0 }
    displayExpect(dateCells.count == expectedDays, "\(context) has every day of its month")
    displayExpect(
        Set(dateCells.map(\.dayNumber)) == Set(1...expectedDays),
        "\(context) day numbers cover the month exactly once"
    )
    let todayCells = grid.cells.filter(\.isToday)
    displayExpect(todayCells.count == 1, "\(context) has exactly one today marker")
    displayExpect(todayCells[0].dayNumber == grid.todayDay, "\(context) marks the anchor day")

    for cell in grid.cells where cell.dayNumber == 0 {
        displayExpect(cell.text == "  ", "\(context) empty cells are blank")
        displayExpect(!cell.isToday, "\(context) empty cells are never today")
    }
    for cell in dateCells {
        let expectedText = cell.dayNumber < 10 ? " \(cell.dayNumber)" : "\(cell.dayNumber)"
        displayExpect(cell.text == expectedText, "\(context) day text is paired with its number")
    }
}

private func displayCivilDateKey(year: Int, month: Int, day: Int) -> String {
    let rawYear = String(year)
    let paddedYear = String(repeating: "0", count: max(0, 4 - rawYear.utf8.count)) + rawYear
    let monthText = month < 10 ? "0\(month)" : "\(month)"
    let dayText = day < 10 ? "0\(day)" : "\(day)"
    return "\(paddedYear)-\(monthText)-\(dayText)"
}

private func displayAssertCivilGrid(
    _ grid: DuoyiMonthGridModel,
    year: Int,
    month: Int,
    daysInMonth: Int,
    todayDay: Int,
    context: String
) {
    displayExpect(grid.year == year && grid.month == month, "\(context) preserves its civil year and month")
    displayExpect(grid.todayDay == todayDay, "\(context) preserves the raw today day")
    displayExpect(grid.daysInMonth == daysInMonth, "\(context) has the expected Gregorian month length")
    displayExpect(grid.cells.count == 42, "\(context) always has 42 cells")

    let realCells = grid.cells.filter { $0.dayNumber > 0 }
    let blankCells = grid.cells.filter { $0.dayNumber == 0 }
    let expectedDays = Array(1...daysInMonth)
    let expectedKeys = expectedDays.map { displayCivilDateKey(year: year, month: month, day: $0) }
    let expectedTargets = expectedKeys.map { "duoyi://calendar?date=\($0)" }
    displayExpect(realCells.map(\.dayNumber) == expectedDays, "\(context) contains every real day in order")
    displayExpect(realCells.compactMap(\.dateKey) == expectedKeys, "\(context) pairs every real day with its canonical date key")
    displayExpect(Set(realCells.compactMap(\.dateKey)).count == daysInMonth, "\(context) real date keys are unique")
    displayExpect(realCells.compactMap(\.target) == expectedTargets, "\(context) pairs every date key with its Calendar target")
    displayExpect(Set(realCells.compactMap(\.target)).count == daysInMonth, "\(context) real Calendar targets are unique")
    displayExpect(blankCells.count == 42 - daysInMonth, "\(context) has the expected number of blank cells")

    for cell in blankCells {
        displayExpect(cell.text == "  ", "\(context) blank cells have blank text")
        displayExpect(!cell.isToday, "\(context) blank cells are not today")
        displayExpect(cell.dateKey == nil && cell.target == nil, "\(context) blank cells have no date key or target")
    }
    for cell in realCells {
        let expectedText = cell.dayNumber < 10 ? " \(cell.dayNumber)" : "\(cell.dayNumber)"
        displayExpect(cell.text == expectedText, "\(context) cell text stays paired with its day")
    }

    let todayCells = grid.cells.filter(\.isToday)
    if (1...daysInMonth).contains(todayDay) {
        displayExpect(todayCells.count == 1, "\(context) highlights one valid today day")
        displayExpect(todayCells[0].dayNumber == todayDay, "\(context) highlights the requested today day")
    } else {
        displayExpect(todayCells.isEmpty, "\(context) does not highlight an invalid today day")
    }
}

private func displayAssertAnchorToday(
    _ grid: DuoyiMonthGridModel,
    year: Int,
    month: Int,
    day: Int,
    context: String
) {
    displayExpect(grid.year == year && grid.month == month, "\(context) resolves the expected local month")
    displayExpect(grid.todayDay == day, "\(context) resolves the expected local day")
    displayExpect(grid.cells.count == 42, "\(context) keeps a 42-cell grid")
    let todayCells = grid.cells.filter(\.isToday)
    displayExpect(todayCells.count == 1, "\(context) has exactly one today cell")
    let expectedKey = displayCivilDateKey(year: year, month: month, day: day)
    displayExpect(todayCells[0].dateKey == Optional(expectedKey), "\(context) today cell has the expected date key")
    displayExpect(todayCells[0].target == Optional("duoyi://calendar?date=\(expectedKey)"), "\(context) today cell has the matching target")
}

private func displayAssertUnavailableGrid(
    _ grid: DuoyiMonthGridModel,
    isZh: Bool,
    context: String
) {
    displayExpect(grid.year == 0 && grid.month == 0 && grid.todayDay == 0, "\(context) has no fabricated civil date")
    displayExpect(grid.monthTitle == (isZh ? "日期不可用" : "Calendar unavailable"), "\(context) uses the localized unavailable title")
    displayExpect(grid.cells.count == 42, "\(context) still has 42 cells")
    displayExpect(grid.cells.allSatisfy { cell in
        cell.dayNumber == 0 && !cell.isToday && cell.text == "  " && cell.dateKey == nil && cell.target == nil
    }, "\(context) contains only blank cells without date keys or targets")
}

private func displayAssertVisibleGridWeeks(
    _ grid: DuoyiMonthGridModel,
    range: ClosedRange<Int>,
    context: String
) {
    for week in range {
        for column in 0..<7 {
            let index = week * 7 + column
            let cell = grid.cells[index]
            let expectedDay = index - grid.firstWeekdayOffset + 1
            if (1...grid.daysInMonth).contains(expectedDay) {
                let expectedKey = displayCivilDateKey(year: grid.year, month: grid.month, day: expectedDay)
                displayExpect(cell.dayNumber == expectedDay, "\(context) visible cell keeps its full-grid day number")
                displayExpect(cell.dateKey == Optional(expectedKey), "\(context) visible real cell keeps its full-grid date key")
                displayExpect(cell.target == Optional("duoyi://calendar?date=\(expectedKey)"), "\(context) visible real cell keeps its matching target")
            } else {
                displayExpect(cell.dayNumber == 0 && cell.dateKey == nil && cell.target == nil,
                              "\(context) visible blank cell remains blank and target-free")
            }
        }
    }
}

private func displayAssertBudgetedRange(
    _ range: ClosedRange<Int>,
    currentWeek: Int,
    totalWeeks: Int,
    expectedCount: Int? = nil,
    context: String
) {
    displayExpect(range.lowerBound >= 0, "\(context) starts inside the grid")
    displayExpect(range.upperBound < totalWeeks, "\(context) ends inside the grid")
    displayExpect(range.contains(currentWeek), "\(context) always includes today's week")
    displayExpect(range.count > 0 && range.count <= totalWeeks, "\(context) is a nonempty bounded range")
    if let expectedCount = expectedCount {
        displayExpect(range.count == expectedCount, "\(context) has the expected number of weeks")
    }
}

private func displayMaximumWeeksFitting(
    availableHeight: Double,
    hasEventSummary: Bool,
    monthTitleHeight: Double = 16,
    weekdayHeaderHeight: Double = 14,
    eventSummaryHeight: Double = 16,
    cellHeight: Double = 15,
    rowSpacing: Double = 2,
    contentSpacing: Double = 4
) -> Int {
    let fixedHeight = monthTitleHeight + weekdayHeaderHeight + 2 * contentSpacing +
        (hasEventSummary ? eventSummaryHeight + contentSpacing : 0)
    let firstWeekHeight = fixedHeight + cellHeight
    guard availableHeight >= firstWeekHeight else { return 0 }
    let additionalWeeks = (availableHeight - firstWeekHeight) / (cellHeight + rowSpacing)
    return 1 + Int(additionalWeeks.rounded(.down))
}

displayRunCase("anniversary five-slot ordering preserves each source, ID, and text") {
    let slots = [
        DuoyiAnniversaryRawSlot(sourceKey: "anniversary_highlight_1", text: "One", target: "duoyi://anniversary/a1"),
        DuoyiAnniversaryRawSlot(sourceKey: "anniversary_highlight_2", text: "Two", target: "duoyi://anniversary/a2"),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_1", text: "Three", target: "duoyi://anniversary/m1"),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_2", text: "Four", target: "duoyi://anniversary/m2"),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_3", text: "Five", target: "duoyi://anniversary/m3"),
    ]
    let items = DuoyiWidgetDisplayCore.resolveAnniversaryItems(slots: slots, isFresh: true, isZh: false)

    let expected: [(String, String, String)] = [
        ("anniversary_highlight_1", "One", "a1"),
        ("anniversary_highlight_2", "Two", "a2"),
        ("memorial_highlight_1", "Three", "m1"),
        ("memorial_highlight_2", "Four", "m2"),
        ("memorial_highlight_3", "Five", "m3"),
    ]
    displayExpect(items.count == expected.count, "all five nonempty slots are retained")
    for (item, value) in zip(items, expected) {
        displayExpect(item.sourceKey == value.0, "slot order and source key are retained")
        displayExpect(item.text == value.1, "slot text stays paired with its ID")
        displayExpect(item.identity == value.2, "slot ID stays paired with its text")
        displayExpect(item.target == "duoyi://anniversary/\(value.2)", "slot target is paired with its ID")
    }
}

displayRunCase("anniversary de-duplicates by decoded identity rather than display text") {
    let items = DuoyiWidgetDisplayCore.resolveAnniversaryItems(
        slots: [
            DuoyiAnniversaryRawSlot(sourceKey: "first", text: "Same text", target: "shared/id"),
            DuoyiAnniversaryRawSlot(sourceKey: "duplicate", text: "Same text", target: "duoyi://anniversary/shared%2Fid"),
            DuoyiAnniversaryRawSlot(sourceKey: "escaped-percent", text: "Same text", target: "duoyi://anniversary/shared%252Fid"),
            DuoyiAnniversaryRawSlot(sourceKey: "same-text-different-id", text: "Same text", target: "other-id"),
        ],
        isFresh: true,
        isZh: false
    )

    displayExpect(items.map(\.sourceKey) == ["first", "escaped-percent", "same-text-different-id"], "only the duplicate identity is removed")
    displayExpect(items.map(\.text) == ["Same text", "Same text", "Same text"], "equal text with distinct IDs remains visible")
    displayExpect(items[0].identity == "shared/id", "bare legacy ID is retained as its identity")
    displayExpect(items[0].target == "duoyi://anniversary/shared%2Fid", "legacy slash is encoded as one path segment")
    displayExpect(items[1].identity == "shared%2Fid", "a double-encoded slash is decoded exactly once")
    displayExpect(items[2].identity == "other-id", "the distinct ID remains paired with the repeated text")
}

displayRunCase("anniversary identities preserve Unicode normalization bytes as opaque IDs") {
    let items = DuoyiWidgetDisplayCore.resolveAnniversaryItems(
        slots: [
            DuoyiAnniversaryRawSlot(sourceKey: "A1", text: "Precomposed", target: "duoyi://anniversary/%C3%A9"),
            DuoyiAnniversaryRawSlot(sourceKey: "A2", text: "Decomposed", target: "duoyi://anniversary/e%CC%81"),
            DuoyiAnniversaryRawSlot(sourceKey: "M1", text: "Exact duplicate", target: "duoyi://anniversary/%C3%A9"),
        ],
        isFresh: true,
        isZh: false
    )

    displayExpect(items.map(\.sourceKey) == ["A1", "A2"], "precomposed and decomposed identities stay in source order while exact duplicate is removed")
    displayExpect(items.map(\.text) == ["Precomposed", "Decomposed"], "Unicode identities stay paired with their original text")
    displayExpect(items.map(\.target) == ["duoyi://anniversary/%C3%A9", "duoyi://anniversary/e%CC%81"], "each Unicode target preserves its percent-encoded form")
    guard let precomposed = items[0].identity, let decomposed = items[1].identity else {
        fatalError("FAIL: Unicode identity was lost")
    }
    displayExpect(Array(precomposed.utf8) == [0xC3, 0xA9], "precomposed ID keeps its UTF-8 bytes")
    displayExpect(Array(decomposed.utf8) == [0x65, 0xCC, 0x81], "decomposed ID keeps its UTF-8 bytes")
    displayExpect(Array(precomposed.utf8) != Array(decomposed.utf8), "canonical String equality does not merge distinct opaque IDs")
}

displayRunCase("anniversary empty, bullet-only, and known empty placeholders are omitted") {
    let items = DuoyiWidgetDisplayCore.resolveAnniversaryItems(
        slots: [
            DuoyiAnniversaryRawSlot(sourceKey: "empty", text: " \n ", target: nil),
            DuoyiAnniversaryRawSlot(sourceKey: "bullet-only", text: " ·   ", target: nil),
            DuoyiAnniversaryRawSlot(sourceKey: "english-empty", text: "· No upcoming anniversaries", target: ""),
            DuoyiAnniversaryRawSlot(sourceKey: "chinese-empty", text: "暂无近期纪念日", target: nil),
            DuoyiAnniversaryRawSlot(sourceKey: "real", text: "Birthday", target: "birthday-1"),
        ],
        isFresh: true,
        isZh: false
    )
    displayExpect(items.count == 1, "only a real anniversary remains")
    displayExpect(items[0].sourceKey == "real", "placeholder text never becomes an anniversary row")
    displayExpect(items[0].text == "Birthday", "the real anniversary text is retained")

    let allEmpty = DuoyiWidgetDisplayCore.resolveAnniversaryItems(
        slots: [
            DuoyiAnniversaryRawSlot(sourceKey: "empty", text: "", target: nil),
            DuoyiAnniversaryRawSlot(sourceKey: "placeholder", text: "· 暂无近期纪念日", target: " "),
        ],
        isFresh: true,
        isZh: true
    )
    displayExpect(allEmpty.count == 1, "all empty slots collapse to one localized placeholder")
    displayExpect(allEmpty[0].text == "· 暂无近期纪念日", "Chinese empty state is stable")
    displayExpect(allEmpty[0].target == "duoyi://anniversary", "empty state has no item target")
}

displayRunCase("stale anniversary data yields one localized pending item") {
    let slots = [
        DuoyiAnniversaryRawSlot(sourceKey: "anniversary_highlight_1", text: "Old event", target: "old-id"),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_1", text: "Old memorial", target: "old-memorial"),
    ]
    let english = DuoyiWidgetDisplayCore.resolveAnniversaryItems(slots: slots, isFresh: false, isZh: false)
    let chinese = DuoyiWidgetDisplayCore.resolveAnniversaryItems(slots: slots, isFresh: false, isZh: true)

    displayExpect(english.count == 1, "stale English data has one item")
    displayExpect(english[0].text == "Dates pending refresh", "stale English text is localized")
    displayExpect(english[0].target == "duoyi://anniversary" && english[0].identity == nil, "stale English item has no stale ID")
    displayExpect(chinese.count == 1, "stale Chinese data has one item")
    displayExpect(chinese[0].text == "日期数据待刷新", "stale Chinese text is localized")
    displayExpect(chinese[0].target == "duoyi://anniversary" && chinese[0].identity == nil, "stale Chinese item has no stale ID")
}

displayRunCase("legacy anniversary text without IDs is retained in slot order") {
    let items = DuoyiWidgetDisplayCore.resolveAnniversaryItems(
        slots: [
            DuoyiAnniversaryRawSlot(sourceKey: "legacy-1", text: "Family birthday", target: nil),
            DuoyiAnniversaryRawSlot(sourceKey: "legacy-2", text: "Family birthday", target: "  "),
            DuoyiAnniversaryRawSlot(sourceKey: "legacy-3", text: "Memorial day", target: nil),
        ],
        isFresh: true,
        isZh: false
    )

    displayExpect(items.map(\.sourceKey) == ["legacy-1", "legacy-2", "legacy-3"], "legacy slots remain ordered")
    displayExpect(items.map(\.identity) == [nil, nil, nil], "missing IDs stay absent")
    displayExpect(items.map(\.target) == Array(repeating: "duoyi://anniversary", count: 3), "legacy rows open the anniversary root")
    displayExpect(items[0].text == items[1].text, "same legacy text is not mistaken for an identity duplicate")
}

displayRunCase("anniversary target canonicalization preserves encoded path identities") {
    displayAssertParsedAnniversary(
        "duoyi://anniversary/alpha%2Fbeta",
        target: "duoyi://anniversary/alpha%2Fbeta",
        identity: "alpha/beta",
        context: "encoded slash"
    )
    displayAssertParsedAnniversary(
        "生日",
        target: "duoyi://anniversary/%E7%94%9F%E6%97%A5",
        identity: "生日",
        context: "Chinese legacy ID"
    )
    displayAssertParsedAnniversary(
        "  two words  ",
        target: "duoyi://anniversary/two%20words",
        identity: "two words",
        context: "spaces in a legacy ID"
    )
    displayAssertParsedAnniversary(
        "record:42",
        target: "duoyi://anniversary/record%3A42",
        identity: "record:42",
        context: "legacy ID with a colon"
    )
    displayAssertParsedAnniversary(
        "bad%ZZ",
        target: "duoyi://anniversary/bad%25ZZ",
        identity: "bad%ZZ",
        context: "legacy ID with a malformed percent sequence"
    )
    for rawLegacyID in ["record:42", "bad%ZZ"] {
        let encodedLegacyID = DuoyiWidgetDisplayCore.parseAnniversaryTarget(rawLegacyID)
        let roundTripped = DuoyiWidgetDisplayCore.parseAnniversaryTarget(encodedLegacyID.target)
        displayExpect(roundTripped.identity == rawLegacyID, "legacy ID round-trips without URI validation: \(rawLegacyID)")
    }
    let canonicalPlus = DuoyiWidgetDisplayCore.parseAnniversaryTarget("duoyi://anniversary/a%2Bb")
    let literalPlus = DuoyiWidgetDisplayCore.parseAnniversaryTarget("duoyi://anniversary/a+b")
    let legacyPlus = DuoyiWidgetDisplayCore.parseAnniversaryTarget("a+b")
    let legacySpace = DuoyiWidgetDisplayCore.parseAnniversaryTarget("a b")
    displayExpect(canonicalPlus.target == "duoyi://anniversary/a%2Bb", "encoded plus remains encoded in the target")
    displayExpect(literalPlus.target == "duoyi://anniversary/a+b", "a literal plus in a path stays a plus")
    displayExpect(legacyPlus.target == "duoyi://anniversary/a%2Bb", "legacy plus is percent-encoded instead of becoming a space")
    displayExpect(canonicalPlus.identity == "a+b", "encoded plus decodes to a literal plus")
    displayExpect(legacyPlus.identity == canonicalPlus.identity, "canonical and legacy plus forms share one identity")
    displayExpect(literalPlus.identity == canonicalPlus.identity, "a path plus is not decoded as a space")
    displayExpect(legacySpace.target == "duoyi://anniversary/a%20b", "a literal space is encoded as %20")
    displayExpect(legacySpace.identity == "a b", "a literal space remains distinct from plus")
    displayExpect(legacySpace.identity != canonicalPlus.identity, "plus and space IDs are not conflated")
    displayAssertParsedAnniversary(
        "duoyi://anniversary/a%252Fb",
        target: "duoyi://anniversary/a%252Fb",
        identity: "a%2Fb",
        context: "double-encoded slash"
    )
    displayAssertParsedAnniversary(nil, target: "duoyi://anniversary", identity: nil, context: "missing target")
    displayAssertParsedAnniversary(" \n ", target: "duoyi://anniversary", identity: nil, context: "blank target")
}

displayRunCase("unsafe anniversary URLs fall back to the safe root") {
    let unsafeTargets = [
        "https://example.invalid/anniversary/42",
        "ftp://example.invalid/anniversary/42",
        "file://example.invalid/anniversary/42",
        "custom-widget://anniversary/42",
        "duoyi+widget://anniversary/42",
        "mailto:owner@example.invalid",
        "duoyi://user@anniversary/42",
        "duoyi://user:password@anniversary/42",
        "duoyi://anniversary@evil.invalid/42",
        "duoyi://anniversary:443/42",
        "duoyi://action/42",
        "duoyi://anniversary/42/extra",
        "duoyi://anniversary/42/",
        "duoyi://anniversary/",
        "duoyi://anniversary/bad%ZZ",
        "duoyi://anniversary/%",
        "duoyi://anniversary/%2",
        "duoyi://anniversary/%GG",
        "duoyi://anniversary/%E0%A4%A",
        "duoyi://anniversary/%C3%28",
        "duoyi://anniversary/%FF",
        "duoyi://anniversary/%ED%A0%80",
        "duoyi://anniversary/%F0%80%80%80",
        "duoyi://anniversary/42?redirect=https://example.invalid",
        "duoyi://anniversary/42#fragment",
        "duoyi://anniversary/42?query=value#fragment",
        "duoyi://anniversary/%20",
        "duoyi://anniversary/id with space",
        "duoyi://anniversary/id\\tail",
        "duoyi://anniversary/id\nwith-newline",
        "duoyi://anniversary/id\u{0001}control",
        "duoyi://anniversary/id\"quote",
        "duoyi://anniversary/id{brace",
        "duoyi://anniversary/id}brace",
        "duoyi://anniversary/id|bar",
        "duoyi://anniversary/id[bracket",
        "duoyi://anniversary/id]bracket",
        "duoyi://anniversary/id`backtick",
        "duoyi://anniversary/id^caret",
    ]
    for raw in unsafeTargets {
        displayAssertParsedAnniversary(
            raw,
            target: "duoyi://anniversary",
            identity: nil,
            context: "unsafe anniversary target \(raw)"
        )
    }
    displayAssertParsedAnniversary(
        "action",
        target: "duoyi://anniversary/action",
        identity: "action",
        context: "legacy ID that happens to read action"
    )
    displayAssertParsedAnniversary(
        "duoyi://anniversary:/x",
        target: "duoyi://anniversary",
        identity: nil,
        context: "anniversary URI with an empty port"
    )

    let encodedEmoji = DuoyiWidgetDisplayCore.parseAnniversaryTarget("duoyi://anniversary/%F0%9F%8E%82")
    displayExpect(encodedEmoji.target == "duoyi://anniversary/%F0%9F%8E%82", "valid UTF-8 emoji escape is retained")
    displayExpect(encodedEmoji.identity == "🎂", "valid UTF-8 emoji escape decodes to the same identity")

    let rawEmoji = DuoyiWidgetDisplayCore.parseAnniversaryTarget("duoyi://anniversary/🎂")
    let rawEmojiWasPreserved = rawEmoji.target == "duoyi://anniversary/🎂" && rawEmoji.identity == "🎂"
    let rawEmojiWasCanonicalized = rawEmoji.target == "duoyi://anniversary/%F0%9F%8E%82" && rawEmoji.identity == "🎂"
    let rawEmojiWasRejected = rawEmoji.target == "duoyi://anniversary" && rawEmoji.identity == nil
    displayExpect(rawEmojiWasPreserved || rawEmojiWasCanonicalized || rawEmojiWasRejected, "raw emoji is preserved, canonicalized, or rejected safely")

    let legacyEmoji = DuoyiWidgetDisplayCore.parseAnniversaryTarget("🎂")
    let legacyEmojiWasPreserved = legacyEmoji.identity == "🎂" &&
        (legacyEmoji.target == "duoyi://anniversary/%F0%9F%8E%82" || legacyEmoji.target == "duoyi://anniversary/🎂")
    let legacyEmojiWasRejected = legacyEmoji.target == "duoyi://anniversary" && legacyEmoji.identity == nil
    displayExpect(legacyEmojiWasPreserved || legacyEmojiWasRejected, "legacy emoji is encoded intact or rejected safely")

    let encodedPunctuation: [(String, String)] = [
        ("id%22quote", "id\"quote"),
        ("id%7Bbrace", "id{brace"),
        ("id%7Dbrace", "id}brace"),
        ("id%7Cbar", "id|bar"),
        ("id%5Bbracket", "id[bracket"),
        ("id%5Dbracket", "id]bracket"),
        ("id%60backtick", "id`backtick"),
        ("id%5Ecaret", "id^caret"),
    ]
    for (encodedSegment, decodedIdentity) in encodedPunctuation {
        let target = "duoyi://anniversary/\(encodedSegment)"
        displayAssertParsedAnniversary(
            target,
            target: target,
            identity: decodedIdentity,
            context: "valid percent-encoded path character \(encodedSegment)"
        )
    }
}

displayRunCase("calendar read-only targets, mutation targets, summaries, and empty states are bounded") {
    for raw in ["duoyi://calendar", "duoyi://focus"] {
        displayExpect(
            DuoyiWidgetDisplayCore.resolveCalendarEventTarget(raw) == raw,
            "read-only calendar host is valid without an item ID"
        )
    }
    for raw in [
        "duoyi://todo/42",
        "duoyi://todo/add",
        "duoyi://todo/create",
        "duoyi://habit/new",
        "duoyi://habit/entry%2Fpart",
        "duoyi://course/class%2B1",
        "duoyi://todo/id%22quote",
        "duoyi://todo/id%7Bbrace",
        "duoyi://todo/id%7Dbrace",
        "duoyi://todo/id%7Cbar",
        "duoyi://todo/id%5Bbracket",
        "duoyi://todo/id%5Dbracket",
        "duoyi://todo/id%60backtick",
        "duoyi://todo/id%5Ecaret",
    ] {
        displayExpect(
            DuoyiWidgetDisplayCore.resolveCalendarEventTarget(raw) == raw,
            "a supported mutation host with one encoded ID segment is retained"
        )
    }

    let invalidTargets: [String?] = [
        nil,
        " \t ",
        "https://example.invalid/event/42",
        "duoyi://action/42",
        "ftp://example.invalid/event/42",
        "file://example.invalid/event/42",
        "custom-widget://todo/42",
        "mailto:owner@example.invalid",
        "duoyi://user@todo/42",
        "duoyi://user:password@todo/42",
        "duoyi://todo@evil.invalid/42",
        "duoyi://todo:443/42",
        "duoyi://todo:/x",
        "duoyi://focus:",
        "duoyi://calendar/extra",
        "duoyi://calendar?view=month",
        "duoyi://calendar#fragment",
        "duoyi://focus/extra",
        "duoyi://focus?view=month",
        "duoyi://focus#fragment",
        "duoyi://todo",
        "duoyi://todo/",
        "duoyi://todo/42/extra",
        "duoyi://todo/42?redirect=https://example.invalid",
        "duoyi://todo/42#fragment",
        "duoyi://todo/add?query=1",
        "duoyi://todo/bad%ZZ",
        "duoyi://todo/%",
        "duoyi://todo/%2",
        "duoyi://todo/%GG",
        "duoyi://todo/%E0%A4%A",
        "duoyi://todo/%C3%28",
        "duoyi://todo/%FF",
        "duoyi://todo/%20",
        "duoyi://todo/id with space",
        "duoyi://todo/id\\tail",
        "duoyi://todo/id\nwith-newline",
        "duoyi://todo/id\u{0001}control",
        "duoyi://todo/id\"quote",
        "duoyi://todo/id{brace",
        "duoyi://todo/id}brace",
        "duoyi://todo/id|bar",
        "duoyi://todo/id[bracket",
        "duoyi://todo/id]bracket",
        "duoyi://todo/id`backtick",
        "duoyi://todo/id^caret",
    ]
    for raw in invalidTargets {
        displayExpect(
            DuoyiWidgetDisplayCore.resolveCalendarEventTarget(raw) == "duoyi://calendar",
            "invalid calendar target falls back safely: \(raw ?? "nil")"
        )
    }

    displayExpect(DuoyiWidgetDisplayCore.calendarEventSummary(raw: nil, isZh: false) == nil, "missing summary stays absent")
    displayExpect(DuoyiWidgetDisplayCore.calendarEventSummary(raw: " \n ", isZh: true) == nil, "blank summary stays absent")
    displayExpect(
        DuoyiWidgetDisplayCore.calendarEventSummary(raw: "· No events today", isZh: false) == "No events today",
        "known English no-event text is normalized"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.calendarEventSummary(raw: "今日没有日程", isZh: false) == "No events today",
        "Chinese no-event text is normalized for English"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.calendarEventSummary(raw: "Today's schedule", isZh: true) == "今日没有日程",
        "known English schedule text is normalized for Chinese"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.calendarEventSummary(raw: "  Project review  ", isZh: false) == "  Project review  ",
        "unknown summary text is preserved"
    )
}

displayRunCase("calendar summary and target are resolved together with freshness and locale") {
    let real = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
        rawSummary: "Quarterly review",
        rawSchedule1Id: "duoyi://todo/add",
        isFresh: true,
        isZh: false
    )
    displayExpect(real.summary == "Quarterly review", "real event summary is preserved exactly")
    displayExpect(real.target == "duoyi://todo/add", "real event keeps its valid opaque ID")
    displayExpect(real.isReal, "real event is distinguished from empty states")

    let realChinese = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
        rawSummary: "家人生日",
        rawSchedule1Id: "duoyi://habit/new",
        isFresh: true,
        isZh: true
    )
    displayExpect(realChinese.summary == "家人生日", "real Chinese summary is preserved exactly")
    displayExpect(realChinese.target == "duoyi://habit/new", "Chinese real event keeps its valid opaque ID")
    displayExpect(realChinese.isReal, "Chinese real event is distinguished from empty states")

    let invalidRealTarget = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
        rawSummary: "Quarterly review",
        rawSchedule1Id: "https://example.invalid/event/42",
        isFresh: true,
        isZh: false
    )
    displayExpect(invalidRealTarget.summary == "Quarterly review", "invalid target does not change real event text")
    displayExpect(invalidRealTarget.target == "duoyi://calendar", "invalid real target falls back to calendar root")
    displayExpect(invalidRealTarget.isReal, "a real summary stays real when its target is rejected")

    let emptySummaries: [String?] = [nil, "", " \t\n "]
    for emptySummary in emptySummaries {
        let empty = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
            rawSummary: emptySummary,
            rawSchedule1Id: "duoyi://todo/old-event",
            isFresh: true,
            isZh: false
        )
        displayExpect(empty.summary == nil, "blank or missing summary stays absent")
        displayExpect(empty.target == "duoyi://calendar", "blank or missing summary cannot retain a schedule target")
        displayExpect(!empty.isReal, "blank or missing summary is not a real event")
    }

    let noEventFixtures: [(String, Bool, String)] = [
        ("No schedule today", false, "No events today"),
        ("No events today", true, "今日没有日程"),
        ("Today's schedule", true, "今日没有日程"),
        ("今日没有日程", false, "No events today"),
    ]
    for (rawSummary, isZh, expectedSummary) in noEventFixtures {
        let noEvent = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
            rawSummary: rawSummary,
            rawSchedule1Id: "duoyi://todo/residual-old-event",
            isFresh: true,
            isZh: isZh
        )
        displayExpect(noEvent.summary == expectedSummary, "known no-event summary is localized")
        displayExpect(noEvent.target == "duoyi://calendar", "no-event summary discards a residual event ID")
        displayExpect(!noEvent.isReal, "no-event summary is not a real event")
    }

    let staleFixtures: [(String, Bool, String)] = [
        ("Old stale event", false, "Today’s data pending refresh"),
        ("旧日程", true, "今日数据待刷新"),
    ]
    for (oldSummary, isZh, expectedSummary) in staleFixtures {
        let stale = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
            rawSummary: oldSummary,
            rawSchedule1Id: "duoyi://todo/residual-old-event",
            isFresh: false,
            isZh: isZh
        )
        displayExpect(stale.summary == expectedSummary, "stale data uses the localized pending text")
        displayExpect(stale.target == "duoyi://calendar", "stale data discards a residual event ID")
        displayExpect(!stale.isReal, "stale data is not a real event")
    }
}

displayRunCase("calendar cell accessibility labels use the same dates and localized month names") {
    let leapDay = DuoyiWidgetDisplayCore.buildMonthGrid(
        anchorDate: displayLocalDate(2024, 2, 29, hour: 12, calendar: displayGregorian(displayTimeZone("UTC"))),
        timeZone: displayTimeZone("UTC"),
        isZh: false
    )
    let dayNumber = leapDay.cells.first(where: { $0.isToday })!.dayNumber
    displayExpect(dayNumber == 29, "leap day grid has the expected today date")
    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(
            year: leapDay.year,
            month: leapDay.month,
            day: dayNumber,
            isToday: false,
            isZh: false
        ) == "February 29, 2024",
        "English accessibility label uses a full month name and grid date"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(
            year: leapDay.year,
            month: leapDay.month,
            day: dayNumber,
            isToday: true,
            isZh: false
        ) == "Today, February 29, 2024",
        "English today label prefixes the same grid date"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(
            year: leapDay.year,
            month: leapDay.month,
            day: dayNumber,
            isToday: false,
            isZh: true
        ) == "2024年2月29日",
        "Chinese accessibility label uses the same grid date"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(
            year: leapDay.year,
            month: leapDay.month,
            day: dayNumber,
            isToday: true,
            isZh: true
        ) == "2024年2月29日，今天",
        "Chinese today label appends today to the same grid date"
    )

    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(year: 2025, month: 12, day: 31, isToday: false, isZh: false) == "December 31, 2025",
        "December label keeps its year at the year boundary"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(year: 2026, month: 1, day: 1, isToday: true, isZh: false) == "Today, January 1, 2026",
        "January today label uses the new year"
    )
    displayExpect(
        DuoyiWidgetDisplayCore.cellAccessibilityLabel(year: 2025, month: 12, day: 31, isToday: true, isZh: true) == "2025年12月31日，今天",
        "Chinese December label keeps its year at the year boundary"
    )
}

displayRunCase("month grids cover 28, 29, 30, and 31 day months") {
    let utc = displayTimeZone("UTC")
    let calendar = displayGregorian(utc)
    let fixtures: [(Int, Int, Int, Int)] = [
        (2025, 2, 14, 28),
        (2024, 2, 29, 29),
        (2026, 4, 15, 30),
        (2026, 1, 15, 31),
    ]
    for (year, month, today, days) in fixtures {
        let anchor = displayLocalDate(year, month, today, hour: 12, calendar: calendar)
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: anchor, timeZone: utc, isZh: false)
        displayExpect(grid.year == year && grid.month == month, "month grid has the requested year and month")
        displayExpect(grid.todayDay == today && grid.daysInMonth == days, "month grid has the requested anchor and length")
        displayAssertGrid(grid, expectedDays: days, context: "\(year)-\(month)")
    }
}

displayRunCase("month grids use Monday-first columns for Monday and Sunday starts") {
    let utc = displayTimeZone("UTC")
    let calendar = displayGregorian(utc)
    let monday = DuoyiWidgetDisplayCore.buildMonthGrid(
        anchorDate: displayLocalDate(2026, 6, 1, hour: 12, calendar: calendar),
        timeZone: utc,
        isZh: false
    )
    let sunday = DuoyiWidgetDisplayCore.buildMonthGrid(
        anchorDate: displayLocalDate(2026, 2, 1, hour: 12, calendar: calendar),
        timeZone: utc,
        isZh: true
    )

    displayExpect(monday.firstWeekdayOffset == 0, "a Monday month starts in the first column")
    displayExpect(monday.cells[0].dayNumber == 1, "Monday month starts with day one")
    displayExpect(monday.weekdayHeaders == ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"], "English headers are Monday-first")
    displayExpect(sunday.firstWeekdayOffset == 6, "a Sunday month starts in the last Monday-first column")
    displayExpect(sunday.cells[6].dayNumber == 1, "Sunday month places day one in the Sunday column")
    displayExpect(sunday.weekdayHeaders == ["一", "二", "三", "四", "五", "六", "日"], "Chinese headers are Monday-first")
    displayAssertGrid(monday, expectedDays: 30, context: "Monday-start month")
    displayAssertGrid(sunday, expectedDays: 28, context: "Sunday-start month")
}

displayRunCase("UTC, Shanghai, and New York grids use explicit local dates across a year boundary") {
    let instant = displayUTCInstant("2026-01-01T00:30:00Z")
    let utc = displayTimeZone("UTC")
    let shanghai = displayTimeZone("Asia/Shanghai")
    let newYork = displayTimeZone("America/New_York")
    let utcGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: instant, timeZone: utc, isZh: false)
    let shanghaiGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: instant, timeZone: shanghai, isZh: true)
    let newYorkGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: instant, timeZone: newYork, isZh: false)

    displayExpect(utcGrid.year == 2026 && utcGrid.month == 1 && utcGrid.todayDay == 1, "UTC uses January 1")
    displayExpect(shanghaiGrid.year == 2026 && shanghaiGrid.month == 1 && shanghaiGrid.todayDay == 1, "Shanghai uses January 1")
    displayExpect(newYorkGrid.year == 2025 && newYorkGrid.month == 12 && newYorkGrid.todayDay == 31, "New York crosses into December 2025")
    displayExpect(utcGrid.monthTitle == "Jan 2026", "UTC title includes the new year")
    displayExpect(shanghaiGrid.monthTitle == "2026年1月", "Chinese title includes the new year")
    displayExpect(newYorkGrid.monthTitle == "Dec 2025", "New York title uses its local year")
    displayAssertGrid(utcGrid, expectedDays: 31, context: "UTC new year")
    displayAssertGrid(shanghaiGrid, expectedDays: 31, context: "Shanghai new year")
    displayAssertGrid(newYorkGrid, expectedDays: 31, context: "New York year crossing")
}

displayRunCase("a future WidgetKit entry date, not wall-clock now, selects the grid month") {
    let utc = displayTimeZone("UTC")
    let calendar = displayGregorian(utc)
    let timelineNow = displayLocalDate(2026, 12, 31, hour: 23, minute: 59, calendar: calendar)
    guard let futureEntryDate = calendar.date(byAdding: .day, value: 1, to: timelineNow) else {
        fatalError("FAIL: could not construct next timeline entry date")
    }
    let currentGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: timelineNow, timeZone: utc, isZh: false)
    let futureGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: futureEntryDate, timeZone: utc, isZh: false)

    displayExpect(currentGrid.year == 2026 && currentGrid.month == 12, "simulated current entry is in December")
    displayExpect(futureGrid.year == 2027 && futureGrid.month == 1 && futureGrid.todayDay == 1, "future entry date selects January 1, 2027")
    displayExpect(futureGrid.monthTitle == "Jan 2027", "future entry title uses the future year")
    displayAssertGrid(futureGrid, expectedDays: 31, context: "future timeline entry")
}

displayRunCase("New York local midnights remain correct across the spring DST change") {
    let newYork = displayTimeZone("America/New_York")
    let calendar = displayGregorian(newYork)
    let transitionMidnight = displayLocalDate(2026, 3, 8, calendar: calendar)
    guard let nextLocalMidnight = calendar.date(byAdding: .day, value: 1, to: transitionMidnight) else {
        fatalError("FAIL: could not construct the midnight after DST transition")
    }
    let elapsed = nextLocalMidnight.timeIntervalSince(transitionMidnight)
    let beforeGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: transitionMidnight, timeZone: newYork, isZh: false)
    let afterGrid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: nextLocalMidnight, timeZone: newYork, isZh: false)

    displayExpect(elapsed == 23 * 60 * 60, "New York spring transition has a 23-hour local day")
    displayExpect(beforeGrid.year == 2026 && beforeGrid.month == 3 && beforeGrid.todayDay == 8, "transition-day midnight maps to March 8")
    displayExpect(afterGrid.year == 2026 && afterGrid.month == 3 && afterGrid.todayDay == 9, "next local midnight maps to March 9")
    displayAssertGrid(beforeGrid, expectedDays: 31, context: "DST transition midnight")
    displayAssertGrid(afterGrid, expectedDays: 31, context: "midnight after DST transition")
}

displayRunCase("available-height thresholds include only rows that fit and preserve today at grid edges") {
    let thresholdFixtures: [(Double, Bool, Int, Int, String)] = [
        (69.9, false, 1, 0, "no-summary just below two rows"),
        (70, false, 2, 0, "no-summary exact two-row threshold"),
        (86.9, false, 2, 5, "no-summary just below three rows"),
        (87, false, 3, 5, "no-summary exact three-row threshold"),
        (137.9, false, 5, 0, "no-summary just below six rows"),
        (138, false, 6, 5, "no-summary exact six-row threshold"),
        (89.9, true, 1, 5, "summary just below two rows"),
        (90, true, 2, 0, "summary exact two-row threshold"),
        (106.9, true, 2, 5, "summary just below three rows"),
        (107, true, 3, 0, "summary exact three-row threshold"),
        (157.9, true, 5, 5, "summary just below six rows"),
        (158, true, 6, 0, "summary exact six-row threshold"),
    ]

    for (height, hasSummary, expectedCount, currentWeek, context) in thresholdFixtures {
        let range = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
            familyKind: "systemLarge",
            displayMode: "detailed",
            currentWeek: currentWeek,
            totalWeeks: 6,
            hasEventSummary: hasSummary,
            availableHeight: height
        )
        displayAssertBudgetedRange(
            range,
            currentWeek: currentWeek,
            totalWeeks: 6,
            expectedCount: expectedCount,
            context: context
        )
        let rowsThatFit = displayMaximumWeeksFitting(availableHeight: height, hasEventSummary: hasSummary)
        displayExpect(range.count <= rowsThatFit, "\(context) does not exceed its height budget")
    }

    for (hasSummary, heights) in [
        (false, [Double(53), 69.9, 70, 86.9, 87, 137.9, 138]),
        (true, [Double(73), 89.9, 90, 106.9, 107, 157.9, 158]),
    ] {
        var previousCount = 0
        for height in heights {
            let range = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
                familyKind: "systemLarge",
                displayMode: "detailed",
                currentWeek: 2,
                totalWeeks: 6,
                hasEventSummary: hasSummary,
                availableHeight: height
            )
            displayAssertBudgetedRange(range, currentWeek: 2, totalWeeks: 6, context: "monotone height budget")
            displayExpect(range.count >= previousCount, "more available height never reduces visible weeks")
            displayExpect(
                range.count <= displayMaximumWeeksFitting(availableHeight: height, hasEventSummary: hasSummary),
                "visible weeks stay within the row-height budget"
            )
            previousCount = range.count
        }
    }

    for familyKind in ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"] {
        for displayMode in ["compact", "standard", "detailed"] {
            for hasSummary in [false, true] {
                let height: Double = hasSummary ? 158 : 138
                for currentWeek in [0, 5] {
                    let range = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
                        familyKind: familyKind,
                        displayMode: displayMode,
                        currentWeek: currentWeek,
                        totalWeeks: 6,
                        hasEventSummary: hasSummary,
                        availableHeight: height
                    )
                    displayAssertBudgetedRange(
                        range,
                        currentWeek: currentWeek,
                        totalWeeks: 6,
                        context: "\(familyKind)/\(displayMode) at grid edge"
                    )
                    displayExpect(
                        range.count <= displayMaximumWeeksFitting(availableHeight: height, hasEventSummary: hasSummary),
                        "\(familyKind)/\(displayMode) stays within available height"
                    )
                }
            }
        }
    }

    let emptyHeight = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
        familyKind: "systemLarge",
        displayMode: "detailed",
        currentWeek: 3,
        totalWeeks: 6,
        hasEventSummary: false,
        availableHeight: 0
    )
    displayAssertBudgetedRange(emptyHeight, currentWeek: 3, totalWeeks: 6, context: "zero-height fallback")

    let oneWeekGrid = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
        familyKind: "systemLarge",
        displayMode: "detailed",
        currentWeek: 0,
        totalWeeks: 1,
        hasEventSummary: false,
        availableHeight: 138
    )
    displayAssertBudgetedRange(oneWeekGrid, currentWeek: 0, totalWeeks: 1, expectedCount: 1, context: "one-week grid")
    let threeWeekGrid = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
        familyKind: "systemLarge",
        displayMode: "detailed",
        currentWeek: 2,
        totalWeeks: 3,
        hasEventSummary: false,
        availableHeight: 138
    )
    displayAssertBudgetedRange(threeWeekGrid, currentWeek: 2, totalWeeks: 3, expectedCount: 3, context: "three-week grid")
}

displayRunCase("calendar family and display modes enforce their exact week caps") {
    let capFixtures: [(String, String, Bool, Int)] = [
        ("systemSmall", "compact", false, 1),
        ("systemSmall", "compact", true, 1),
        ("systemSmall", "standard", false, 2),
        ("systemSmall", "standard", true, 1),
        ("systemSmall", "detailed", false, 3),
        ("systemSmall", "detailed", true, 1),
        ("systemMedium", "compact", false, 1),
        ("systemMedium", "compact", true, 1),
        ("systemMedium", "standard", false, 2),
        ("systemMedium", "standard", true, 2),
        ("systemMedium", "detailed", false, 3),
        ("systemMedium", "detailed", true, 2),
        ("systemLarge", "compact", false, 1),
        ("systemLarge", "compact", true, 1),
        ("systemLarge", "standard", false, 6),
        ("systemLarge", "standard", true, 6),
        ("systemLarge", "detailed", false, 6),
        ("systemLarge", "detailed", true, 6),
        ("systemExtraLarge", "compact", false, 1),
        ("systemExtraLarge", "compact", true, 1),
        ("systemExtraLarge", "standard", false, 6),
        ("systemExtraLarge", "standard", true, 6),
        ("systemExtraLarge", "detailed", false, 6),
        ("systemExtraLarge", "detailed", true, 6),
    ]

    for (familyKind, displayMode, hasSummary, expectedCount) in capFixtures {
        let currentWeek = expectedCount == 1 || expectedCount == 3 ? 5 : 0
        let range = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
            familyKind: familyKind,
            displayMode: displayMode,
            currentWeek: currentWeek,
            totalWeeks: 6,
            hasEventSummary: hasSummary
        )
        displayAssertBudgetedRange(
            range,
            currentWeek: currentWeek,
            totalWeeks: 6,
            expectedCount: expectedCount,
            context: "\(familyKind)/\(displayMode), summary=\(hasSummary)"
        )
    }
}

displayRunCase("custom calendar metrics change the available-week threshold") {
    let exactThreeWeeks = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
        familyKind: "systemLarge",
        displayMode: "detailed",
        currentWeek: 1,
        totalWeeks: 6,
        hasEventSummary: false,
        availableHeight: 98,
        monthTitleHeight: 20,
        weekdayHeaderHeight: 11,
        eventSummaryHeight: 23,
        cellHeight: 17,
        rowSpacing: 3,
        contentSpacing: 5
    )
    let justBelowThreeWeeks = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
        familyKind: "systemLarge",
        displayMode: "detailed",
        currentWeek: 4,
        totalWeeks: 6,
        hasEventSummary: false,
        availableHeight: 97.9,
        monthTitleHeight: 20,
        weekdayHeaderHeight: 11,
        eventSummaryHeight: 23,
        cellHeight: 17,
        rowSpacing: 3,
        contentSpacing: 5
    )

    displayAssertBudgetedRange(exactThreeWeeks, currentWeek: 1, totalWeeks: 6, expectedCount: 3, context: "custom metrics exact three-row threshold")
    displayAssertBudgetedRange(justBelowThreeWeeks, currentWeek: 4, totalWeeks: 6, expectedCount: 2, context: "custom metrics just below three-row threshold")
    displayExpect(
        exactThreeWeeks.count <= displayMaximumWeeksFitting(
            availableHeight: 98,
            hasEventSummary: false,
            monthTitleHeight: 20,
            weekdayHeaderHeight: 11,
            eventSummaryHeight: 23,
            cellHeight: 17,
            rowSpacing: 3,
            contentSpacing: 5
        ),
        "custom dimensions, not hard-coded defaults, determine fit"
    )
}

displayRunCase("civil month models bind every real date and keep all 42 blank and real cells distinct") {
    let fixtures: [(Int, Int, Int, Int)] = [
        (2024, 2, 29, 29),
        (2026, 4, 15, 30),
        (2026, 1, 31, 31),
    ]

    for (year, month, todayDay, daysInMonth) in fixtures {
        guard let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            year: year,
            month: month,
            todayDay: todayDay,
            isZh: false
        ) else {
            fatalError("FAIL: valid civil month \(year)-\(month) was rejected")
        }
        displayAssertCivilGrid(
            grid,
            year: year,
            month: month,
            daysInMonth: daysInMonth,
            todayDay: todayDay,
            context: "civil \(year)-\(month)"
        )
    }
}

displayRunCase("civil month models cover the first and last supported dates") {
    let fixtures: [(Int, Int, Int, Int, String)] = [
        (1, 1, 1, 31, "0001-01-01"),
        (9999, 12, 31, 31, "9999-12-31"),
    ]

    for (year, month, todayDay, daysInMonth, expectedKey) in fixtures {
        guard let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            year: year,
            month: month,
            todayDay: todayDay,
            isZh: false
        ) else {
            fatalError("FAIL: supported civil year \(year) was rejected")
        }
        displayAssertCivilGrid(
            grid,
            year: year,
            month: month,
            daysInMonth: daysInMonth,
            todayDay: todayDay,
            context: "supported endpoint \(expectedKey)"
        )
        let endpoint = grid.cells.first { $0.dayNumber == todayDay }
        displayExpect(endpoint?.dateKey == Optional(expectedKey), "\(expectedKey) is a canonical date key")
        displayExpect(endpoint?.target == Optional("duoyi://calendar?date=\(expectedKey)"), "\(expectedKey) has its exact Calendar target")
    }
}

displayRunCase("civil month models apply proleptic Gregorian century leap rules") {
    let fixtures: [(Int, Int)] = [
        (1500, 28),
        (1600, 29),
        (1900, 28),
        (2000, 29),
        (2100, 28),
        (2400, 29),
    ]

    for (year, expectedDays) in fixtures {
        guard let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            year: year,
            month: 2,
            todayDay: expectedDays,
            isZh: true
        ) else {
            fatalError("FAIL: valid proleptic Gregorian February \(year) was rejected")
        }
        displayAssertCivilGrid(
            grid,
            year: year,
            month: 2,
            daysInMonth: expectedDays,
            todayDay: expectedDays,
            context: "Gregorian February \(year)"
        )
    }
}

displayRunCase("1582 October stays continuous and the historical Unix anchor uses Gregorian weekdays") {
    guard let october = DuoyiWidgetDisplayCore.buildMonthGrid(
        year: 1582,
        month: 10,
        todayDay: 15,
        isZh: false
    ) else {
        fatalError("FAIL: proleptic Gregorian October 1582 was rejected")
    }
    displayAssertCivilGrid(
        october,
        year: 1582,
        month: 10,
        daysInMonth: 31,
        todayDay: 15,
        context: "civil October 1582"
    )
    displayExpect(october.firstWeekdayOffset == 4, "proleptic Gregorian October 1, 1582 starts Friday in a Monday-first grid")

    let historicInstant = Date(timeIntervalSince1970: -12_219_292_800)
    let historical = DuoyiWidgetDisplayCore.buildMonthGrid(
        anchorDate: historicInstant,
        timeZone: displayFixedTimeZone(0),
        isZh: false
    )
    displayAssertAnchorToday(historical, year: 1582, month: 10, day: 15, context: "1582-10-15 Unix anchor")
    displayExpect(historical.firstWeekdayOffset == 4, "historical Unix anchor uses the proleptic Gregorian Monday offset")
    displayExpect(historical.cells.map(\.dateKey) == october.cells.map(\.dateKey), "historical and civil October grids contain the same 31 dates")
    displayExpect(historical.cells.map(\.target) == october.cells.map(\.target), "historical and civil October grids bind the same dates")

    // Independent proleptic Gregorian Unix instants; do not build these dates
    // using Foundation's historical calendar cutover.
    let anchorFixtures: [(Double, Int, Int, Int)] = [
        (-62_135_553_600, 1, 1, 1),
        (-14_826_715_200, 1500, 2, 28),
        (-12_220_459_200, 1582, 10, 1),
        (-12_220_113_600, 1582, 10, 5),
        (-12_219_336_000, 1582, 10, 14),
        (-12_219_249_600, 1582, 10, 15),
        (-11_670_955_200, 1600, 2, 29),
        (43_200, 1970, 1, 1),
        (253_402_257_600, 9999, 12, 31),
    ]
    for (seconds, year, month, day) in anchorFixtures {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            anchorDate: Date(timeIntervalSince1970: seconds),
            timeZone: displayFixedTimeZone(0),
            isZh: false
        )
        displayAssertAnchorToday(grid, year: year, month: month, day: day, context: "historical UTC anchor \(year)-\(month)-\(day)")
    }
}

displayRunCase("civil month builder rejects invalid years and months and preserves invalid today days") {
    for invalidYear in [0, -1, 10_000, Int.min, Int.max] {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            year: invalidYear,
            month: 1,
            todayDay: 1,
            isZh: false
        )
        displayExpect(grid == nil, "invalid civil year \(invalidYear) returns nil")
    }
    for invalidMonth in [0, -1, 13, Int.min, Int.max] {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            year: 2024,
            month: invalidMonth,
            todayDay: 1,
            isZh: false
        )
        displayExpect(grid == nil, "invalid civil month \(invalidMonth) returns nil")
    }

    for invalidToday in [0, -1, 31, Int.max] {
        guard let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            year: 2024,
            month: 4,
            todayDay: invalidToday,
            isZh: false
        ) else {
            fatalError("FAIL: invalid today day must not reject a valid civil month")
        }
        displayAssertCivilGrid(
            grid,
            year: 2024,
            month: 4,
            daysInMonth: 30,
            todayDay: invalidToday,
            context: "April with invalid today \(invalidToday)"
        )
    }
}

displayRunCase("legacy month cells default their date keys and targets to nil") {
    let legacy = DuoyiMonthCell(dayNumber: 0, isToday: false, text: "  ")
    displayExpect(legacy.dateKey == nil, "legacy initializer defaults dateKey to nil")
    displayExpect(legacy.target == nil, "legacy initializer does not fabricate a Calendar target")
}

displayRunCase("Unix month anchors use the supplied zone across midnight and New Year") {
    let instant = Date(timeIntervalSince1970: 1_704_069_000)
    let fixtures: [(String, Int, Int, Int, String)] = [
        ("UTC", 2024, 1, 1, "UTC January anchor"),
        ("America/Los_Angeles", 2023, 12, 31, "Los Angeles previous-year anchor"),
        ("Pacific/Kiritimati", 2024, 1, 1, "Kiritimati new-year anchor"),
    ]

    for (zone, year, month, day, context) in fixtures {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            anchorDate: instant,
            timeZone: displayTimeZone(zone),
            isZh: false
        )
        displayAssertAnchorToday(grid, year: year, month: month, day: day, context: context)
    }
}

displayRunCase("Unix month anchors preserve local dates through both daylight-saving transitions") {
    let newYork = displayTimeZone("America/New_York")
    let fixtures: [(Double, Int, Int, Int, String)] = [
        (1_710_052_200, 2024, 3, 10, "before spring jump"),
        (1_710_055_800, 2024, 3, 10, "after spring jump"),
        (1_730_606_399.999, 2024, 11, 2, "before fall-back midnight"),
        (1_730_606_400, 2024, 11, 3, "at fall-back midnight"),
        (1_730_613_600, 2024, 11, 3, "after fall-back repeats an hour"),
    ]

    for (seconds, year, month, day, context) in fixtures {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            anchorDate: Date(timeIntervalSince1970: seconds),
            timeZone: newYork,
            isZh: false
        )
        displayAssertAnchorToday(grid, year: year, month: month, day: day, context: context)
    }
}

displayRunCase("Unix anchor conversion adds second offsets before flooring fractional timestamps") {
    let fixtures: [(Double, Int, Int, Int, Int, String)] = [
        (-0.25, 0, 1969, 12, 31, "negative fraction at UTC"),
        (0.25, 0, 1970, 1, 1, "positive fraction at UTC"),
        (-0.25, 1, 1970, 1, 1, "positive offset carries negative fraction into epoch day"),
        (0.25, -1, 1969, 12, 31, "negative offset carries positive fraction into prior day"),
    ]

    for (seconds, offset, year, month, day, context) in fixtures {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            anchorDate: Date(timeIntervalSince1970: seconds),
            timeZone: displayFixedTimeZone(offset),
            isZh: false
        )
        displayAssertAnchorToday(grid, year: year, month: month, day: day, context: context)
    }
}

displayRunCase("unsupported and nonfinite Unix anchors produce localized blank grids without targets") {
    let lowerBound = Date(timeIntervalSince1970: -62_135_596_800)
    let upperBound = Date(timeIntervalSince1970: 253_402_300_799)
    let utc = displayFixedTimeZone(0)
    let plusFourteen = displayFixedTimeZone(14 * 60 * 60)
    let minusFourteen = displayFixedTimeZone(-14 * 60 * 60)

    let validBoundaryFixtures: [(Date, TimeZone, Int, Int, Int, String)] = [
        (lowerBound, utc, 1, 1, 1, "minimum supported UTC instant"),
        (lowerBound, plusFourteen, 1, 1, 1, "positive offset remains within minimum supported date"),
        (upperBound, utc, 9999, 12, 31, "maximum supported UTC instant"),
        (Date(timeIntervalSince1970: 253_402_300_799.5), utc, 9999, 12, 31, "fractional last second remains within year 9999"),
        (upperBound, minusFourteen, 9999, 12, 31, "negative offset remains within maximum supported date"),
        (lowerBound.addingTimeInterval(-14 * 60 * 60), plusFourteen, 1, 1, 1, "UTC before year 1 resolves to a valid local date"),
        (upperBound.addingTimeInterval(14 * 60 * 60), minusFourteen, 9999, 12, 31, "UTC after year 9999 resolves to a valid local date"),
    ]
    for (instant, timeZone, year, month, day, context) in validBoundaryFixtures {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: instant, timeZone: timeZone, isZh: false)
        displayAssertAnchorToday(grid, year: year, month: month, day: day, context: context)
    }

    let unsupportedFixtures: [(Date, TimeZone, Bool, String)] = [
        (lowerBound, minusFourteen, false, "negative offset crosses below year 1"),
        (upperBound, plusFourteen, true, "positive offset crosses above year 9999"),
        (lowerBound, displayFixedTimeZone(-1), false, "negative one-second offset crosses below year 1"),
        (upperBound, displayFixedTimeZone(1), true, "positive one-second offset crosses above year 9999"),
        (Date(timeIntervalSince1970: -62_135_596_800.5), utc, false, "fractional instant floors before year 1"),
        (Date(timeIntervalSince1970: 253_402_300_800.5), utc, true, "fractional instant exceeds year 9999"),
        (Date(timeIntervalSince1970: Double.greatestFiniteMagnitude), utc, false, "maximum finite anchor is outside supported dates"),
        (Date(timeIntervalSince1970: -Double.greatestFiniteMagnitude), utc, true, "minimum finite anchor is outside supported dates"),
        (Date(timeIntervalSince1970: Double.infinity), utc, false, "positive infinite anchor"),
        (Date(timeIntervalSince1970: -Double.infinity), utc, true, "negative infinite anchor"),
        (Date(timeIntervalSince1970: Double.nan), utc, false, "NaN anchor"),
    ]
    for (instant, timeZone, isZh, context) in unsupportedFixtures {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(anchorDate: instant, timeZone: timeZone, isZh: isZh)
        displayAssertUnavailableGrid(grid, isZh: isZh, context: context)
    }
}

displayRunCase("visible family and height budgets retain each real cell date and target from the full month model") {
    guard let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
        year: 2024,
        month: 4,
        todayDay: 30,
        isZh: false
    ) else {
        fatalError("FAIL: valid April 2024 model was rejected")
    }
    let currentWeek = (grid.firstWeekdayOffset + grid.todayDay - 1) / 7
    let families = ["systemSmall", "systemMedium", "systemLarge", "systemExtraLarge"]
    let modes = ["compact", "standard", "detailed"]
    let heights: [Double] = [0, 70, 90, 107, 138, 158]

    for family in families {
        for mode in modes {
            for hasSummary in [false, true] {
                for height in heights {
                    let context = "\(family)/\(mode), summary=\(hasSummary), height=\(height)"
                    let visibleWeeks = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
                        familyKind: family,
                        displayMode: mode,
                        currentWeek: currentWeek,
                        totalWeeks: grid.cells.count / 7,
                        hasEventSummary: hasSummary,
                        availableHeight: height
                    )
                    displayAssertBudgetedRange(
                        visibleWeeks,
                        currentWeek: currentWeek,
                        totalWeeks: grid.cells.count / 7,
                        context: context
                    )
                    displayAssertVisibleGridWeeks(grid, range: visibleWeeks, context: context)
                }
            }
        }
    }
}
