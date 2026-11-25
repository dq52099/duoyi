// Executed beside source-extracted production control/provider members.
private func controlsExpect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("FAIL: \(message)")
        exit(1)
    }
}

private func controlsCase(_ name: String, _ body: () -> Void) {
    body()
    print("PASS: \(name)")
}

controlsCase("built-in navigation labels follow locale and preserve custom names") {
    let fields: [(String, String, [String])] = [
        ("待办", "Tasks", ["待办", "Tasks", "To-Do"]),
        ("习惯", "Habits", ["习惯", "Habits"]),
        ("日历", "Calendar", ["日历", "Calendar"]),
        ("专注", "Focus", ["专注", "Focus"])
    ]
    for (zh, en, generated) in fields {
        for locale in [DuoyiWidgetLocale.zh, .en] {
            for raw in generated + generated.map({ " \($0) " }) + ["", "  "] {
                controlsExpect(localizedNavigationLabel(raw, zh: zh, en: en, locale: locale) ==
                    (locale == .en ? en : zh), "generated navigation label \(raw) -> \(locale)")
            }
            for raw in ["我的工作", "My work", "Tasks for work", "Todo", "To Do", "  Custom  "] {
                controlsExpect(localizedNavigationLabel(raw, zh: zh, en: en, locale: locale) == raw,
                               "custom navigation label remains literal")
            }
        }
    }
}

controlsCase("all published focus phases and legacy labels follow widget locale") {
    let phases: [(String, String, [String])] = [
        ("专注倒计时", "Focus countdown", ["倒计时"]),
        ("正计时专注中", "Focus counting up", ["专注正计时", "正计时", "Focus count-up"]),
        ("短休息倒计时", "Short break countdown", []),
        ("长休息倒计时", "Long break countdown", [])
    ]
    for (zh, en, legacy) in phases {
        for raw in [zh, en] + legacy {
            controlsExpect(localizedFocusTimerLabel(raw, locale: .zh) == zh, "Chinese phase \(raw)")
            controlsExpect(localizedFocusTimerLabel(raw, locale: .en) == en, "English phase \(raw)")
            controlsExpect(localizedFocusTimerLabel(localizedFocusTimerLabel(raw, locale: .zh), locale: .en) == en,
                           "round trip phase \(raw)")
        }
    }
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let custom = "Focus countdown — read chapter 3"
        controlsExpect(localizedFocusTimerLabel(custom, locale: locale) == custom, "custom phase remains literal")
    }
}

private func controlsConfig(_ kind: String) -> DuoyiWidgetConfig {
    DuoyiWidgetConfig(
        kind: "Duoyi\(kind)Widget",
        deepLink: kind == "Schedule" ? "duoyi://calendar" : "duoyi://\(kind.lowercased())",
        primaryKey: kind == "Schedule" ? "today_event_summary" : "summary",
        fallback: kind == "Schedule" ? "今日没有日程" : "Fixture",
        rowKeys: kind == "Schedule" ? (1...3).map { "schedule_highlight_\($0)" } : [],
        quickActionTitle: "Fixture action",
        quickActionLink: kind == "Focus" ? "duoyi://action/start_pomodoro" : "duoyi://habit"
    )
}

private func controlsSnapshot(_ fresh: Bool) -> DuoyiWidgetSnapshot {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let now = Date()
    let date = fresh ? now : calendar.date(byAdding: .day, value: -1, to: now)!
    let fields = calendar.dateComponents([.year, .month, .day], from: date)
    return DuoyiWidgetSnapshot(values: [
        "widget_snapshot_day": String(format: "%04d-%02d-%02d", fields.year!, fields.month!, fields.day!),
        "widget_snapshot_utc_offset_minutes": calendar.timeZone.secondsFromGMT(for: date) / 60,
        "widget_account_nonce": "synthetic-account"
    ])
}

private func controlsTimer(_ phase: DuoyiFocusTimerPhase) -> DuoyiFocusTimerState {
    DuoyiFocusTimerState(
        phase: phase, seconds: 600, totalSeconds: 1500,
        startDate: nil, endDate: nil, capDate: nil,
        hasFutureStart: false, isAtCountUpCap: false
    )
}

private func controlsView(
    _ kind: String, locale: DuoyiWidgetLocale = .en,
    phase: DuoyiFocusTimerPhase = .idle, fresh: Bool = true,
    published: Bool = true, habitID: String = "",
    family: FixtureFamily = .systemMedium,
    todoIDs: [String] = [], displayMode: String = "standard",
    primaryTarget: String = "", rows: [DuoyiWidgetRow] = [],
    snapshotOverride: DuoyiWidgetSnapshot? = nil, primary: String = "First literal object",
    date: Date = Date(), todoCount: Int? = nil
) -> FixtureView {
    let snapshot = snapshotOverride ?? (published ? controlsSnapshot(fresh) : .empty)
    let todoRows = todoIDs.enumerated().map { item in
        DuoyiTodoRow(index: item.offset + 1, title: "User task \(item.offset + 1)",
                     todoId: item.element, snapshot: snapshot)
    }
    var view = FixtureView(entry: FixtureEntry(
        date: date, config: controlsConfig(kind), locale: locale,
        snapshot: snapshot, isDailyFresh: fresh && published,
        todoRows: todoRows, todoCount: todoCount, primaryTarget: primaryTarget, primary: primary, rows: rows, displayMode: displayMode,
        habitQuickCheckId: habitID,
        focusTimer: controlsTimer(phase),
        focusTimerLabel: locale == .en ? "Focus timer" : "专注计时"
    ))
    view.family = family
    return view
}

controlsCase("production count projection changes while the visible top three stay identical") {
    let snapshot = controlsSnapshot(true)
    let now = Date()
    let provider = FixtureProvider()
    var values: [String: Any] = [
        "todo_count": 5,
        "todo_top3_count": 5,
        "todo_top3_1": "A", "todo_top3_1_id": "A",
        "todo_top3_2": "B", "todo_top3_2_id": "B",
        "todo_top3_3": "C", "todo_top3_3_id": "C"
    ]
    let first = provider.readTodoCount(values, snapshot: snapshot, at: now)
    controlsExpect(first == 5, "total uses the publication count, not three visible rows")
    values["todo_count"] = 4
    values["todo_top3_count"] = 4
    let second = provider.readTodoCount(values, snapshot: snapshot, at: now)
    controlsExpect(second == 4, "completing a hidden item refreshes the total")
    controlsExpect(values["todo_top3_3_id"] as? String == "C", "visible item identities stay unchanged")
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let firstView = controlsView("Todo", locale: locale, family: .accessoryCircular,
                                    todoIDs: ["A", "B", "C"], todoCount: first)
        let secondView = controlsView("Todo", locale: locale, family: .accessoryCircular,
                                     todoIDs: ["A", "B", "C"], todoCount: second)
        controlsExpect(firstView.accessoryShortText == "5", "circular text displays the complete first count")
        controlsExpect(secondView.accessoryShortText == "4", "circular text follows the refreshed total")
    }
}

controlsCase("production count projection distinguishes zero from stale or malformed publications") {
    let provider = FixtureProvider()
    let now = Date()
    let fresh = controlsSnapshot(true)
    controlsExpect(provider.readTodoCount(["todo_count": 0], snapshot: fresh, at: now) == 0,
                   "an empty published list still has the exact zero count")
    controlsExpect(provider.readTodoCount(["todo_count": 4], snapshot: controlsSnapshot(false), at: now) == nil,
                   "yesterday's total is unavailable")
    controlsExpect(provider.readTodoCount(["todo_count": 4], snapshot: .empty, at: now) == nil,
                   "unpublished data cannot supply a total")
    let invalidCounts: [Any] = [true, "4", -1, Int64(Int32.max) + 1, 1.5]
    for raw in invalidCounts {
        controlsExpect(provider.readTodoCount(["todo_count": raw], snapshot: fresh, at: now) == nil,
                       "malformed count stays unavailable: \(raw)")
    }
    controlsExpect(provider.readTodoCount([:], snapshot: fresh, at: now) == nil,
                   "a missing field is unavailable, not zero")
}

controlsCase("independent links are limited to supported home-screen families") {
    for family in [FixtureFamily.systemSmall, .accessoryInline, .accessoryCircular,
                   .accessoryRectangular] {
        controlsExpect(!controlsView("Todo", family: family).supportsItemLinks,
                       "small/accessory widgets have no independent item links")
    }
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        controlsExpect(controlsView("Todo", family: family).supportsItemLinks,
                       "larger widgets retain independent links")
    }
}

private func controlsBoundComponents(
    _ url: URL?, snapshot: DuoyiWidgetSnapshot,
    extraQuery: [(String, String)] = []
) -> URLComponents {
    guard let url = url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let offset = snapshot.utcOffsetMinutes else {
        print("FAIL: expected a bound URL and a published offset")
        exit(1)
    }
    controlsExpect(components.scheme == "duoyi", "bound URL uses the app scheme")
    controlsExpect(components.user == nil && components.password == nil &&
                   components.port == nil && components.fragment == nil,
                   "bound URL has no injected authority or fragment")
    let expected: [(String, String)] = [
        ("source", "widget"), ("widget_day", snapshot.day),
        ("widget_offset", String(offset)), ("widget_account", snapshot.accountNonce)
    ] + extraQuery
    let items = components.queryItems ?? []
    controlsExpect(items.count == expected.count, "exact query item count, without delivery or extra keys")
    for (name, value) in expected {
        let matching = items.filter { $0.name == name && $0.value == value }
        controlsExpect(matching.count == 1, "one exact query item for \(name)")
    }
    return components
}

private func controlsExpectTodoIdentity(_ components: URLComponents, id: String) {
    controlsExpect(components.host == "todo", "detail URL opens the todo host")
    // Split before decoding: a slash inside the opaque ID is not another route segment.
    let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
    controlsExpect(segments.count == 2 && segments[0].isEmpty &&
                   String(segments[1]).removingPercentEncoding == id,
                   "detail preserves exactly one path segment containing the original ID")
}

// A single accessory tap must identify the object whose title is displayed.
// These use extracted production display/provider members as well as routing.
private let accessoryFamilies: [FixtureFamily] = [.accessoryInline, .accessoryCircular, .accessoryRectangular]
private let accessoryKinds = ["Todo", "Note", "Goal", "Diary", "Anniversary", "Course", "Schedule"]

controlsCase("accessory primary display and exact encoded identity agree in every family and density") {
    let identities = [("plain", "plain"), ("%20%20padded%20%20", "  padded  "),
                      ("id%2F%3F%23%25%E6%B5%8B%E8%AF%95", "id/?#%测试"), ("%252F", "%2F")]
    for kind in accessoryKinds {
        let hosts = kind == "Schedule"
            ? ["todo", "habit", "anniversary", "course", "diary", "goal", "countdown", "time-entry", "event", "pomodoro"]
            : [kind.lowercased()]
        for family in accessoryFamilies {
            for locale in [DuoyiWidgetLocale.zh, .en] {
                for mode in ["compact", "standard", "detailed"] {
                    for host in hosts {
                        for (encoded, id) in identities {
                            let view = controlsView(kind, locale: locale, family: family,
                                todoIDs: [id, "second-object"], displayMode: mode,
                                primaryTarget: "duoyi://\(host)/\(encoded)",
                                rows: [DuoyiWidgetRow(index: 2, title: "Second unrelated object", target: "duoyi://goal/second")],
                                primary: "· First literal object")
                            let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                            let segments = bound.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                            controlsExpect(bound.host == host && segments.count == 2 &&
                                String(segments[1]).removingPercentEncoding == id, "accessory preserves visible primary identity")
                            let title = kind == "Todo" ? "User task 1" : "First literal object"
                            controlsExpect(view.accessoryPrimaryText == title, "literal first title is displayed")
                            controlsExpect(view.accessoryShortText == String(title.prefix(4)), "circular text uses same primary")
                            controlsExpect(view.accessorySecondaryText == nil, "one tap never advertises a second object")
                            controlsExpect(!view.supportsItemLinks, "accessory has only its root action")
                        }
                    }
                }
            }
        }
    }
}

controlsCase("accessory stale publications and invalid account or offset bindings cannot open an object") {
    let current = controlsSnapshot(true)
    let base: [String: Any] = ["widget_snapshot_day": current.day,
        "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
        "widget_account_nonce": current.accountNonce]
    var noNonce = base; noNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base; blankNonce["widget_account_nonce"] = "  "
    var wrongOffset = base; wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    let snapshots = [DuoyiWidgetSnapshot.empty, controlsSnapshot(false)] +
        [noNonce, blankNonce, wrongOffset].map { DuoyiWidgetSnapshot(values: $0) }
    for kind in accessoryKinds {
        for family in accessoryFamilies {
            for snapshot in snapshots {
                let host = kind == "Schedule" ? "event" : kind.lowercased()
                let view = controlsView(kind, family: family, todoIDs: ["old", "other"],
                    primaryTarget: "duoyi://\(host)/old", snapshotOverride: snapshot)
                controlsExpect(view.widgetRootURL?.absoluteString == view.entry.config.deepLink,
                    "invalid snapshot opens module without substituting another object")
            }
            let stale = controlsView(kind, fresh: false, family: family, todoIDs: ["old"],
                primaryTarget: "duoyi://\(kind.lowercased())/old")
            controlsExpect(stale.widgetRootURL?.absoluteString == stale.entry.config.deepLink,
                "explicit stale entry cannot retain an object action")
        }
    }
}

controlsCase("accessory invalid and empty targets never borrow a secondary object") {
    for kind in accessoryKinds {
        let host = kind == "Schedule" ? "event" : kind.lowercased()
        let invalid = ["", "duoyi://\(host)", "duoyi://\(host)/", "duoyi://\(host)/%20%20",
            "duoyi://\(host)/first/second", "https://\(host)/id", "duoyi://\(host)/id?q=1",
            "duoyi://\(host)/id#fragment", "duoyi://user@\(host)/id", "duoyi://\(host):123/id", "duoyi://alien/id"]
        for family in accessoryFamilies {
            for target in invalid {
                // Todo's published ID is an opaque value, not a route string.
                let view = controlsView(kind, family: family, todoIDs: ["", "valid-other"],
                    primaryTarget: target,
                    rows: [DuoyiWidgetRow(index: 2, title: "Other object", target: "duoyi://goal/other")])
                controlsExpect(view.widgetRootURL?.absoluteString == view.entry.config.deepLink,
                    "invalid primary falls back to the original module")
                controlsExpect(view.accessorySecondaryText == nil, "fallback does not display a clickable-looking second object")
            }
            let empty = controlsView(kind, family: family, primary: "")
            controlsExpect(empty.widgetRootURL?.absoluteString == empty.entry.config.deepLink, "empty state opens module")
            controlsExpect(empty.accessoryShortText == (empty.entry.locale == .en ? "None" : "暂无"), "circular empty state remains readable")
        }
    }
}

controlsCase("accessory schedule preserves deliberate calendar and focus module projections") {
    for family in accessoryFamilies {
        for host in ["calendar", "focus"] {
            let view = controlsView("Schedule", family: family, primaryTarget: "duoyi://\(host)")
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://\(host)", "module projection retains its own destination")
            controlsExpect(view.accessorySecondaryText == nil, "module projection does not expose another event")
        }
    }
}

controlsCase("accessory summary kinds retain their modules secondary summaries and focus timer") {
    for kind in ["Focus", "Habit"] {
        for family in accessoryFamilies {
            for locale in [DuoyiWidgetLocale.zh, .en] {
                let view = controlsView(kind, locale: locale, phase: .runningCountdown, family: family,
                    todoIDs: ["unrelated"], primaryTarget: "duoyi://todo/unrelated",
                    rows: [DuoyiWidgetRow(index: 1, title: "· Summary detail", target: "duoyi://goal/other")],
                    primary: "Literal summary")
                controlsExpect(view.widgetRootURL?.absoluteString == view.entry.config.deepLink, "summary does not select an unrelated object")
                controlsExpect(view.accessorySecondaryText == "Summary detail", "summary secondary text remains")
                controlsExpect(view.accessoryPrimaryText == (kind == "Focus"
                    ? (locale == .en ? "10 min" : "10分") : "Literal summary"), "focus countdown and summaries unchanged")
                if kind == "Focus" {
                    controlsExpect(view.accessoryShortText == (locale == .en ? "10m" : "10分"), "circular running focus unchanged")
                }
            }
        }
    }
}

controlsCase("calendar accessory display uses the entry date for every family and locale") {
    // Construct local noon because the extracted production property uses .current.
    // Expected literals are independent of the production date formatter.
    let samples: [(Int, Int, Int, String, String, String, String)] = [
        (2024, 4, 15, "Apr 15", "Apr 15 · Monday", "4月15日", "4月15日 · 周一"),
        (2026, 5, 17, "May 17", "May 17 · Sunday", "5月17日", "5月17日 · 周日"),
        (2024, 2, 29, "Feb 29", "Feb 29 · Thursday", "2月29日", "2月29日 · 周四"),
        (2025, 12, 31, "Dec 31", "Dec 31 · Wednesday", "12月31日", "12月31日 · 周三"),
        (2026, 1, 1, "Jan 1", "Jan 1 · Thursday", "1月1日", "1月1日 · 周四")
    ]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    for (year, month, day, inlineEn, rectangularEn, inlineZh, rectangularZh) in samples {
        guard let date = calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12
        )) else {
            fatalError("FAIL: cannot construct fixed local calendar entry date")
        }
        for locale in [DuoyiWidgetLocale.zh, .en] {
            let inline = locale == .zh ? inlineZh : inlineEn
            let rectangular = locale == .zh ? rectangularZh : rectangularEn
            for family in accessoryFamilies {
                // Calendar dates remain useful even when the business snapshot is stale.
                for fresh in [true, false] {
                    let view = controlsView("Calendar", locale: locale, fresh: fresh,
                        family: family, primaryTarget: "duoyi://todo/unrelated",
                        rows: [DuoyiWidgetRow(index: 1, title: "· Summary detail", target: "duoyi://goal/other")],
                        primary: "Summary must not replace the entry date", date: date)
                    controlsExpect(view.accessoryPrimaryText == (family == .accessoryInline ? inline : rectangular),
                        "calendar primary date matches family, locale, leap day, and year boundary")
                    controlsExpect(view.accessoryShortText == String(day),
                        "calendar circular text is the exact day, including two-digit days")
                    controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://calendar",
                        "calendar date display retains its module root")
                    controlsExpect(view.accessorySecondaryText == "Summary detail",
                        "calendar retains its secondary summary")
                }
            }
        }
    }
}

controlsCase("accessory joins real provider selection to visible title and bound root") {
    let provider = FixtureProvider()
    for kind in accessoryKinds.filter({ $0 != "Todo" }) {
        let config = controlsConfig(kind)
        let host = kind == "Schedule" ? "pomodoro" : kind.lowercased()
        var values: [String: Any] = [config.primaryKey: "Literal published title",
            "\(config.primaryKey)_id": "duoyi://\(host)/published%2FID"]
        if kind == "Schedule" {
            values["schedule_highlight_1"] = "Literal published title"
            values["schedule_highlight_1_id"] = "duoyi://\(host)/published%2FID"
            values["schedule_highlight_2"] = "Other event"
            values["schedule_highlight_2_id"] = "duoyi://goal/other"
        }
        for locale in [DuoyiWidgetLocale.zh, .en] {
            let primary = provider.readPrimary(values, config: config, locale: locale)
            let rows = provider.readRows(values, config: config, locale: locale, excluding: primary.sourceKey)
            for family in accessoryFamilies {
                let view = controlsView(kind, locale: locale, family: family,
                    primaryTarget: primary.target, rows: rows, primary: primary.title)
                let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                controlsExpect(view.accessoryPrimaryText == "Literal published title", "real provider title reaches the accessory")
                controlsExpect(bound.host == host && bound.percentEncodedPath == "/published%2FID", "same real provider object receives the tap")
                controlsExpect(view.accessorySecondaryText == nil, "other provider rows are not shown under this root")
            }
        }
    }
}

controlsCase("small todo root opens the first task with exact frozen binding in every density") {
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            let view = controlsView("Todo", locale: locale, family: .systemSmall,
                                    todoIDs: ["todo-A", "todo-B", "todo-C"], displayMode: mode)
            let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
            controlsExpectTodoIdentity(components, id: "todo-A")
            controlsExpect(view.entry.todoRows.count == 3, "input publication retains all three rows")
            controlsExpect(view.visibleTodoRows.isEmpty, "single-target small card shows no additional task")
            controlsExpect(!view.supportsItemLinks, "small root detail does not enable independent links")
        }
    }
}

controlsCase("small todo root preserves reserved Unicode and padded IDs as one identity") {
    for id in ["todo /?#&=% 测试🌙", "second/segment", "  padded ID  "] {
        let view = controlsView("Todo", family: .systemSmall, todoIDs: [id, "other-task"])
        let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpectTodoIdentity(components, id: id)
    }
}

controlsCase("small todo root falls back for absent or blank first IDs without choosing another task") {
    let inputs: [[String]] = [[], [""], [" \n "], ["", "second-valid"]]
    for ids in inputs {
        let view = controlsView("Todo", family: .systemSmall, todoIDs: ids)
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://todo", "unavailable first task opens module")
        controlsExpect(view.visibleTodoRows.isEmpty, "small never exposes another task under the first target")
    }
}

controlsCase("stale and unpublished small todo entries open the module") {
    for view in [controlsView("Todo", fresh: false, family: .systemSmall, todoIDs: ["old-task"]),
                 controlsView("Todo", published: false, family: .systemSmall, todoIDs: ["old-task"])] {
        controlsExpect(!view.entry.isDailyFresh, "entry freshness guard is false")
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://todo", "stale entry has no object target")
    }
}

controlsCase("a retained fresh small todo entry rechecks its now-old row snapshot") {
    let view = controlsView("Todo", family: .systemSmall, todoIDs: ["old-task"],
                            snapshotOverride: controlsSnapshot(false))
    controlsExpect(view.entry.isDailyFresh, "retained entry still carries its original fresh flag")
    controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://todo", "old row cannot bypass current snapshot validation")
}

controlsCase("small todo root rejects missing blank nonce and mismatched offset despite a fresh flag") {
    let current = controlsSnapshot(true)
    let base: [String: Any] = [
        "widget_snapshot_day": current.day,
        "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
        "widget_account_nonce": current.accountNonce
    ]
    var missingNonce = base
    missingNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base
    blankNonce["widget_account_nonce"] = " \n "
    var wrongOffset = base
    wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    for values in [missingNonce, blankNonce, wrongOffset] {
        let view = controlsView("Todo", family: .systemSmall, todoIDs: ["unsafe-task"],
                                snapshotOverride: DuoyiWidgetSnapshot(values: values))
        controlsExpect(view.entry.isDailyFresh, "captured freshness does not prove current binding")
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://todo", "invalid binding falls back without an entity URL")
    }
}

controlsCase("larger todo families retain module roots visible rows and bound detail completion links") {
    let expectations: [(FixtureFamily, String, [String])] = [
        (.systemMedium, "compact", ["todo-B"]),
        (.systemMedium, "standard", ["todo-B", "todo-C"]),
        (.systemMedium, "detailed", ["todo-B", "todo-C"]),
        (.systemLarge, "compact", ["todo-B", "todo-C"]),
        (.systemLarge, "standard", ["todo-B", "todo-C"]),
        (.systemLarge, "detailed", ["todo-B", "todo-C"]),
        (.systemExtraLarge, "compact", ["todo-B", "todo-C"]),
        (.systemExtraLarge, "standard", ["todo-B", "todo-C"]),
        (.systemExtraLarge, "detailed", ["todo-B", "todo-C"])
    ]
    for (family, mode, expectedRows) in expectations {
        let view = controlsView("Todo", family: family,
                                todoIDs: ["todo-A /?#测试", "todo-B", "todo-C"], displayMode: mode)
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://todo", "larger root keeps module navigation")
        controlsExpect(view.supportsItemLinks, "larger family retains independent links")
        controlsExpect(view.visibleTodoRows.map(\.todoId) == expectedRows, "larger density preserves its exact additional rows")
        for row in view.entry.todoRows {
            let detail = controlsBoundComponents(row.detailURL, snapshot: view.entry.snapshot)
            controlsExpectTodoIdentity(detail, id: row.todoId)
            let completion = controlsBoundComponents(row.completeURL, snapshot: view.entry.snapshot,
                                                     extraQuery: [("id", row.todoId)])
            controlsExpect(completion.host == "action" && completion.percentEncodedPath == "/complete_todo",
                           "completion keeps its action route and exact query ID")
        }
    }
}

controlsCase("all accessory todo families open the first task without independent links") {
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Todo", family: family, todoIDs: ["todo-A", "todo-B"])
        let target = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpectTodoIdentity(target, id: "todo-A")
        controlsExpect(!view.supportsItemLinks, "accessory has no independent item links")
    }
}

controlsCase("other small widget kinds keep their module targets even with accidental todo rows") {
    let expectations = [
        ("Focus", "duoyi://focus"), ("Habit", "duoyi://habit"),
        ("Calendar", "duoyi://calendar"), ("Schedule", "duoyi://calendar"),
        ("Goal", "duoyi://goal"), ("Course", "duoyi://course"),
        ("Note", "duoyi://note"), ("Anniversary", "duoyi://anniversary"),
        ("Diary", "duoyi://diary")
    ]
    for (kind, expected) in expectations {
        let view = controlsView(kind, family: .systemSmall, todoIDs: ["do-not-open-this-task"])
        controlsExpect(view.widgetRootURL?.absoluteString == expected, "\(kind) root does not become a todo detail")
        controlsExpect(!view.supportsItemLinks, "other small kinds retain their link capability")
    }
}

controlsCase("small note opens its visible first note with exact snapshot binding") {
    let identities = [
        ("note-A", "note-A"),
        ("note%20%2F%3F%23%26%3D%25%20%E6%B5%8B%E8%AF%95%F0%9F%8C%99", "note /?#&=% 测试🌙"),
        ("second%2Fsegment", "second/segment"),
        ("%20%20padded%20ID%20%20", "  padded ID  ")
    ]
    let extra = [DuoyiWidgetRow(index: 2, title: "Other note", target: "duoyi://note/other")]
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            for (encoded, original) in identities {
                let view = controlsView("Note", locale: locale, family: .systemSmall,
                                        displayMode: mode, primaryTarget: "duoyi://note/\(encoded)", rows: extra)
                let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                controlsExpect(components.host == "note", "visible note opens note detail")
                let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                controlsExpect(segments.count == 2 && segments[0].isEmpty &&
                               String(segments[1]).removingPercentEncoding == original,
                               "note preserves the exact original ID as one segment")
                controlsExpect(view.entry.rows.count == 1, "publication retains other notes")
                controlsExpect(view.visibleRows.isEmpty, "single-target small note hides secondary notes")
                controlsExpect(!view.supportsItemLinks, "small note keeps one root target")
            }
        }
    }
}

controlsCase("small note invalid targets fall back without selecting another note") {
    let invalid = ["", " \n ", "duoyi://note", "duoyi://note/", "duoyi://note/%20%0A",
                   "duoyi://note/one/two", "duoyi://note/one/", "duoyi://todo/wrong",
                   "https://note/wrong", "duoyi://action/complete_todo?id=wrong",
                   "duoyi://user@note/wrong", "duoyi://note:81/wrong", "duoyi://note/wrong#fragment",
                   "duoyi://note/wrong?extra=value"]
    for target in invalid {
        let view = controlsView("Note", family: .systemSmall, primaryTarget: target,
                                rows: [DuoyiWidgetRow(index: 2, title: "Other note", target: "duoyi://note/other")])
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://note", "invalid target falls back: \(target)")
        controlsExpect(view.visibleRows.isEmpty, "fallback does not display another unaddressable note")
    }
}

controlsCase("small note stale or missing bindings fall back to the module") {
    let target = "duoyi://note/note-A"
    for view in [controlsView("Note", fresh: false, family: .systemSmall, primaryTarget: target),
                 controlsView("Note", published: false, family: .systemSmall, primaryTarget: target),
                 controlsView("Note", family: .systemSmall, primaryTarget: target, snapshotOverride: controlsSnapshot(false)),
                 controlsView("Note", family: .systemSmall, primaryTarget: target,
                              snapshotOverride: DuoyiWidgetSnapshot(values: ["widget_snapshot_day": controlsSnapshot(true).day,
                                                                           "widget_snapshot_utc_offset_minutes": 0]))] {
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://note", "unbound note opens module")
    }
}

controlsCase("larger note families retain secondary rows and module roots") {
    let extra = [DuoyiWidgetRow(index: 2, title: "Other note", target: "duoyi://note/other")]
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        let view = controlsView("Note", family: family, primaryTarget: "duoyi://note/note-A", rows: extra)
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://note", "larger note keeps module root")
        controlsExpect(view.supportsItemLinks, "larger note retains independent links")
        controlsExpect(view.visibleRows.count == 1 && view.visibleRows[0].target == "duoyi://note/other",
                       "larger note retains exact secondary row target")
    }
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Note", family: family, primaryTarget: "duoyi://note/note-A")
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.host == "note" && bound.percentEncodedPath == "/note-A", "accessory note opens its visible object")
        controlsExpect(!view.supportsItemLinks, "accessory note has no independent links")
    }
}

controlsCase("focus paused and ended status labels use the entry language") {
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for phase in [DuoyiFocusTimerPhase.pausedCountdown, .pausedCountUp] {
            controlsExpect(controlsView("Focus", locale: locale, phase: phase).focusStatusLabel ==
                (locale == .en ? "Paused · Focus timer" : "已暂停 · 专注计时"), "paused status")
        }
        controlsExpect(controlsView("Focus", locale: locale, phase: .ended).focusStatusLabel ==
            (locale == .en ? "Finished · Focus timer" : "已结束 · 专注计时"), "ended status")
        controlsExpect(controlsView("Focus", locale: locale, phase: .runningCountUp).focusStatusLabel ==
            (locale == .en ? "Focus timer" : "专注计时"), "running label remains literal")
    }
}

controlsCase("fresh idle focus starts with snapshot account/day binding") {
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let view = controlsView("Focus", locale: locale)
        controlsExpect(view.quickActionTitle == (locale == .en ? "Start" : "开始"), "idle label")
        let url = view.quickURL!
        controlsExpect(url.host == "action" && url.path == "/start_pomodoro", "idle route")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        controlsExpect(query.contains { $0.name == "widget_account" && $0.value == "synthetic-account" }, "bound account")
        controlsExpect(query.contains { $0.name == "widget_day" }, "bound day")
    }
}

controlsCase("running and paused focus phases toggle with snapshot binding while ended and unavailable open") {
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for phase in [DuoyiFocusTimerPhase.runningCountdown, .runningCountUp] {
            let view = controlsView("Focus", locale: locale, phase: phase)
            controlsExpect(view.quickActionTitle == (locale == .en ? "Pause" : "暂停"), "running label \(phase)")
            let url = controlsBoundComponents(view.quickURL, snapshot: view.entry.snapshot)
            controlsExpect(url.host == "action" && url.percentEncodedPath == "/toggle_pomodoro", "running toggle route \(phase)")
        }
        for phase in [DuoyiFocusTimerPhase.pausedCountdown, .pausedCountUp] {
            let view = controlsView("Focus", locale: locale, phase: phase)
            controlsExpect(view.quickActionTitle == (locale == .en ? "Resume" : "继续"), "paused label \(phase)")
            let url = controlsBoundComponents(view.quickURL, snapshot: view.entry.snapshot)
            controlsExpect(url.host == "action" && url.percentEncodedPath == "/toggle_pomodoro", "paused resume route \(phase)")
        }
        for phase in [DuoyiFocusTimerPhase.ended, .unavailable] {
            let view = controlsView("Focus", locale: locale, phase: phase)
            controlsExpect(view.quickActionTitle == (locale == .en ? "Open" : "打开"), "nonidle label \(phase)")
            controlsExpect(view.quickURL?.absoluteString == "duoyi://focus", "nonidle navigation \(phase)")
        }
    }
}

controlsCase("stale and unpublished focus phases open without a mutation") {
    for phase in [DuoyiFocusTimerPhase.idle, .runningCountdown, .runningCountUp,
                  .pausedCountdown, .pausedCountUp, .ended, .unavailable] {
        for locale in [DuoyiWidgetLocale.zh, .en] {
            for view in [controlsView("Focus", locale: locale, phase: phase, fresh: false),
                         controlsView("Focus", locale: locale, phase: phase, published: false)] {
                controlsExpect(view.quickActionTitle == (locale == .en ? "Open" : "打开"), "stale label \(phase)")
                controlsExpect(view.quickURL?.absoluteString == "duoyi://focus", "stale route \(phase)")
            }
        }
    }
}

controlsCase("eligible habit checkin preserves encoded ID and snapshot binding") {
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let view = controlsView("Habit", locale: locale, habitID: "habit / 测试 & 1")
        controlsExpect(view.quickActionTitle == (locale == .en ? "Check In" : "打卡"), "checkin label")
        let url = view.quickURL!
        controlsExpect(url.path == "/checkin_habit", "checkin path")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        controlsExpect(query.contains { $0.name == "id" && $0.value == "habit / 测试 & 1" }, "exact ID")
        controlsExpect(query.contains { $0.name == "widget_account" }, "checkin bound")
    }
}

controlsCase("habit checkin preserves nonblank opaque IDs with boundary whitespace") {
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for id in [" habit /?#&=é ", "\thabit/测试\n", " habit", "habit "] {
            let view = controlsView("Habit", locale: locale, habitID: id)
            controlsExpect(view.quickActionTitle == (locale == .en ? "Check In" : "打卡"), "eligible label")
            let url = view.quickURL!
            controlsExpect(url.host == "action" && url.path == "/checkin_habit", "checkin route")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            let ids = query.filter { $0.name == "id" }
            controlsExpect(ids.count == 1 && ids[0].value == id, "opaque ID round trip: \(id.debugDescription)")
            controlsExpect(query.contains { $0.name == "widget_account" && $0.value == "synthetic-account" }, "bound account")
            controlsExpect(query.contains { $0.name == "widget_day" }, "bound day")
        }
    }
}

controlsCase("empty, whitespace, stale and unpublished habit opens the list") {
    for view in [controlsView("Habit"), controlsView("Habit", habitID: " \n "),
                 controlsView("Habit", fresh: false, habitID: "old"),
                 controlsView("Habit", published: false, habitID: "old")] {
        controlsExpect(view.quickActionTitle == "View", "list label")
        controlsExpect(view.quickURL?.absoluteString == "duoyi://habit", "list navigation")
    }
}

controlsCase("schedule first event is primary with detail and remaining rows preserved") {
    let values: [String: Any] = [
        "today_event_summary": "First event summary",
        "schedule_highlight_1": "· First literal event",
        "schedule_highlight_1_id": "duoyi://todo/first",
        "schedule_highlight_2": "· Second literal event",
        "schedule_highlight_2_id": "duoyi://habit/second",
        "schedule_highlight_3": "· Third literal event",
        "schedule_highlight_3_id": "duoyi://course/third"
    ]
    let provider = FixtureProvider()
    let config = controlsConfig("Schedule")
    let primary = provider.readPrimary(values, config: config, locale: .en)
    controlsExpect(primary.title == "· First literal event", "literal primary")
    controlsExpect(primary.target == "duoyi://todo/first", "first detail target retained")
    let detailURL = controlsSnapshot(true).actionURL(URLComponents(string: primary.target))
    controlsExpect(detailURL?.host == "todo" && detailURL?.path == "/first", "published entity detail route")
    controlsExpect(URLComponents(url: detailURL!, resolvingAgainstBaseURL: false)!.queryItems!.contains {
        $0.name == "widget_account" && $0.value == "synthetic-account"
    }, "primary detail carries the snapshot binding")
    controlsExpect(controlsSnapshot(false).actionURL(URLComponents(string: primary.target)) == nil,
                   "old primary entity detail cannot bypass snapshot freshness")
    let rows = provider.readRows(values, config: config, locale: .en, excluding: primary.sourceKey)
    controlsExpect(rows.map(\.title) == ["· Second literal event", "· Third literal event"], "no first duplication")
    controlsExpect(rows.map(\.target) == ["duoyi://habit/second", "duoyi://course/third"], "remaining detail targets")
}

controlsCase("schedule summary fallback preserves first detail target") {
    let provider = FixtureProvider()
    let config = controlsConfig("Schedule")
    let primary = provider.readPrimary([
        "today_event_summary": "09:00 User event",
        "schedule_highlight_1_id": "duoyi://todo/first"
    ], config: config, locale: .en)
    controlsExpect(primary.title == "09:00 User event", "summary fallback")
    controlsExpect(primary.target == "duoyi://todo/first", "fallback detail")
}

controlsCase("real published empty schedule placeholders follow the active locale") {
    let provider = FixtureProvider()
    let config = controlsConfig("Schedule")
    // HomeWidgetService publishes the bullet even when there are no events.
    for raw in ["今日没有日程", "No events today"] {
        for locale in [DuoyiWidgetLocale.zh, .en] {
            let primary = provider.readPrimary([
                "today_event_summary": raw,
                "schedule_highlight_1": "· \(raw)"
            ], config: config, locale: locale)
            let expected = locale == .en ? "No events today" : "今日没有日程"
            controlsExpect(primary.title.contains(expected), "empty schedule translated \(raw) -> \(locale)")
            controlsExpect(primary.target == "duoyi://calendar", "empty schedule root")
            let rows = provider.readRows([
                "today_event_summary": raw,
                "schedule_highlight_1": "· \(raw)"
            ], config: config, locale: locale, excluding: primary.sourceKey)
            controlsExpect(rows.isEmpty, "empty schedule has no placeholder rows \(raw) -> \(locale)")
        }
    }
}

controlsCase("a user event named like an empty placeholder retains literal copy and detail") {
    let provider = FixtureProvider()
    let config = controlsConfig("Schedule")
    for title in ["今日没有日程", "No events today"] {
        let primary = provider.readPrimary([
            "today_event_summary": title,
            "schedule_highlight_1": "· \(title)",
            "schedule_highlight_1_id": "duoyi://goal/literal"
        ], config: config, locale: .en)
        controlsExpect(primary.title == "· \(title)", "literal event title preserved")
        controlsExpect(primary.target == "duoyi://goal/literal", "literal event detail retained")
    }
}

controlsCase("small goal opens the visible primary goal with exact identity and frozen binding") {
    let identities = [
        ("goal-A", "goal-A"),
        ("goal%20%2F%3F%23%26%3D%25%20%E6%B5%8B%E8%AF%95%F0%9F%8C%99", "goal /?#&=% 测试🌙"),
        ("second%2Fsegment", "second/segment"),
        ("%20%20padded%20ID%20%20", "  padded ID  ")
    ]
    let secondary = [DuoyiWidgetRow(index: 2, title: "Other goal", target: "duoyi://goal/other")]
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            for (encoded, original) in identities {
                let view = controlsView("Goal", locale: locale, family: .systemSmall,
                                        displayMode: mode, primaryTarget: "duoyi://goal/\(encoded)", rows: secondary)
                let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                controlsExpect(components.host == "goal", "visible goal opens goal detail")
                let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                controlsExpect(segments.count == 2 && segments[0].isEmpty &&
                               String(segments[1]).removingPercentEncoding == original,
                               "goal preserves exactly one original opaque ID")
                controlsExpect(view.entry.rows.count == 1, "publication retains secondary goal data")
                controlsExpect(view.visibleRows.isEmpty, "single-target small goal displays only the primary object")
                controlsExpect(!view.supportsItemLinks, "small goal retains one root target")
            }
        }
    }
}

controlsCase("small goal rejects invalid primary targets without choosing another goal") {
    let invalid = ["", " \n ", "duoyi://goal", "duoyi://goal/", "duoyi://goal/%20%0A",
                   "https://example.com/goal/A", "duoyi://note/A", "duoyi://goal/A/B",
                   "duoyi://goal//A", "duoyi://goal/A/", "duoyi://user@goal/A",
                   "duoyi://user:password@goal/A", "duoyi://goal:99/A",
                   "duoyi://goal/A?confirm=1", "duoyi://goal/A#fragment"]
    for target in invalid {
        let view = controlsView("Goal", family: .systemSmall, primaryTarget: target,
                                rows: [DuoyiWidgetRow(index: 2, title: "Other", target: "duoyi://goal/other")])
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://goal", "invalid primary falls back to goal module")
        controlsExpect(view.visibleRows.isEmpty, "fallback does not expose a second object under one root")
    }
}

controlsCase("small goal rejects stale unpublished and retained-old bindings") {
    let views = [
        controlsView("Goal", fresh: false, family: .systemSmall, primaryTarget: "duoyi://goal/old"),
        controlsView("Goal", published: false, family: .systemSmall, primaryTarget: "duoyi://goal/old"),
        controlsView("Goal", family: .systemSmall, primaryTarget: "duoyi://goal/old",
                     snapshotOverride: controlsSnapshot(false))
    ]
    for view in views {
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://goal", "unusable goal snapshot opens module")
    }
    let current = controlsSnapshot(true)
    let base: [String: Any] = [
        "widget_snapshot_day": current.day,
        "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
        "widget_account_nonce": current.accountNonce
    ]
    var missingNonce = base
    missingNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base
    blankNonce["widget_account_nonce"] = " \n "
    var wrongOffset = base
    wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    for values in [missingNonce, blankNonce, wrongOffset] {
        let view = controlsView("Goal", family: .systemSmall, primaryTarget: "duoyi://goal/unsafe",
                                snapshotOverride: DuoyiWidgetSnapshot(values: values))
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://goal", "invalid goal binding opens module")
    }
}

controlsCase("larger goal families retain module root and original secondary rows") {
    let rows = (2...5).map { DuoyiWidgetRow(index: $0, title: "Goal \($0)", target: "duoyi://goal/id-\($0)") }
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        for mode in ["compact", "standard", "detailed"] {
            let view = controlsView("Goal", family: family, displayMode: mode,
                                    primaryTarget: "duoyi://goal/first", rows: rows)
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://goal", "larger goal retains module root")
            controlsExpect(view.supportsItemLinks, "larger goal keeps independent links")
            let expectedCount = family == .systemMedium ? (mode == "compact" ? 2 : 3) : (mode == "compact" ? 3 : 4)
            controlsExpect(view.visibleRows.map(\.target) == Array(rows.prefix(expectedCount)).map(\.target),
                           "larger goal keeps exact secondary rows and order")
        }
    }
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Goal", family: family, primaryTarget: "duoyi://goal/first", rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.host == "goal" && bound.percentEncodedPath == "/first", "accessory goal opens its visible object")
        controlsExpect(!view.supportsItemLinks, "accessory goal link capability unchanged")
    }
}

controlsCase("small diary opens the visible primary diary with exact identity and frozen binding") {
    let identities = [
        ("diary-A", "diary-A"),
        ("diary%20%2F%3F%23%26%3D%25%20%E6%B5%8B%E8%AF%95%F0%9F%8C%99", "diary /?#&=% 测试🌙"),
        ("second%2Fsegment", "second/segment"),
        ("%20%20padded%20ID%20%20", "  padded ID  ")
    ]
    let secondary = [DuoyiWidgetRow(index: 2, title: "Other diary", target: "duoyi://diary/other")]
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            for (encoded, original) in identities {
                let view = controlsView("Diary", locale: locale, family: .systemSmall,
                                        displayMode: mode, primaryTarget: "duoyi://diary/\(encoded)", rows: secondary)
                let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                controlsExpect(components.host == "diary", "visible diary opens diary detail")
                let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                controlsExpect(segments.count == 2 && segments[0].isEmpty &&
                               String(segments[1]).removingPercentEncoding == original,
                               "diary preserves exactly one original opaque ID")
                controlsExpect(view.entry.rows.count == 1, "publication retains secondary diary data")
                controlsExpect(view.visibleRows.isEmpty, "single-target small diary displays only the primary object")
                controlsExpect(!view.supportsItemLinks, "small diary retains one root target")
            }
        }
    }
}

controlsCase("small diary rejects invalid primary targets without choosing another diary") {
    let invalid = ["", " \n ", "duoyi://diary", "duoyi://diary/", "duoyi://diary/%20%0A",
                   "https://example.com/diary/A", "duoyi://note/A", "duoyi://diary/A/B",
                   "duoyi://diary//A", "duoyi://diary/A/", "duoyi://user@diary/A",
                   "duoyi://user:password@diary/A", "duoyi://diary:99/A",
                   "duoyi://diary/A?confirm=1", "duoyi://diary/A#fragment"]
    for target in invalid {
        let view = controlsView("Diary", family: .systemSmall, primaryTarget: target,
                                rows: [DuoyiWidgetRow(index: 2, title: "Other", target: "duoyi://diary/other")])
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://diary", "invalid primary falls back to diary module")
        controlsExpect(view.visibleRows.isEmpty, "fallback does not expose a second object under one root")
    }
}

controlsCase("small diary rejects stale unpublished and retained-old bindings") {
    let views = [
        controlsView("Diary", fresh: false, family: .systemSmall, primaryTarget: "duoyi://diary/old"),
        controlsView("Diary", published: false, family: .systemSmall, primaryTarget: "duoyi://diary/old"),
        controlsView("Diary", family: .systemSmall, primaryTarget: "duoyi://diary/old",
                     snapshotOverride: controlsSnapshot(false))
    ]
    for view in views {
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://diary", "unusable diary snapshot opens module")
    }
    let current = controlsSnapshot(true)
    let base: [String: Any] = [
        "widget_snapshot_day": current.day,
        "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
        "widget_account_nonce": current.accountNonce
    ]
    var missingNonce = base
    missingNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base
    blankNonce["widget_account_nonce"] = " \n "
    var wrongOffset = base
    wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    for values in [missingNonce, blankNonce, wrongOffset] {
        let view = controlsView("Diary", family: .systemSmall, primaryTarget: "duoyi://diary/unsafe",
                                snapshotOverride: DuoyiWidgetSnapshot(values: values))
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://diary", "invalid diary binding opens module")
    }
}

controlsCase("larger diary families retain module root and original secondary rows") {
    let rows = (2...5).map { DuoyiWidgetRow(index: $0, title: "Diary \($0)", target: "duoyi://diary/id-\($0)") }
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        for mode in ["compact", "standard", "detailed"] {
            let view = controlsView("Diary", family: family, displayMode: mode,
                                    primaryTarget: "duoyi://diary/first", rows: rows)
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://diary", "larger diary retains module root")
            controlsExpect(view.supportsItemLinks, "larger diary keeps independent links")
            let expectedCount = family == .systemMedium ? (mode == "compact" ? 2 : 3) : (mode == "compact" ? 3 : 4)
            controlsExpect(view.visibleRows.map(\.target) == Array(rows.prefix(expectedCount)).map(\.target),
                           "larger diary keeps exact secondary rows and order")
        }
    }
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Diary", family: family, primaryTarget: "duoyi://diary/first", rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.host == "diary" && bound.percentEncodedPath == "/first", "accessory diary opens its visible object")
        controlsExpect(!view.supportsItemLinks, "accessory diary link capability unchanged")
    }
}

controlsCase("historical diary keeps its title and identity under a current publication") {
    let config = DuoyiWidgetConfig(kind: "DuoyiDiaryWidget", deepLink: "duoyi://diary",
                                    primaryKey: "diary_highlight_1", fallback: "No diary entries yet",
                                    rowKeys: ["diary_highlight_2", "diary_highlight_3"],
                                    quickActionTitle: "Write", quickActionLink: "duoyi://diary")
    let values: [String: Any] = [
        "diary_highlight_1": "1/2 Historical diary title",
        "diary_highlight_1_id": "duoyi://diary/entry-from-2001%2F01%2F02",
        "diary_highlight_2": "3/4 Another diary",
        "diary_highlight_2_id": "duoyi://diary/another"
    ]
    let provider = FixtureProvider()
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let primary = provider.readPrimary(values, config: config, locale: locale)
        let rows = provider.readRows(values, config: config, locale: locale)
        controlsExpect(primary.title == "1/2 Historical diary title", "historical user copy is retained")
        controlsExpect(primary.sourceKey == "diary_highlight_1", "first published diary stays selected")
        let view = controlsView("Diary", locale: locale, family: .systemSmall,
                                primaryTarget: primary.target, rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.percentEncodedPath.removingPercentEncoding == "/entry-from-2001/01/02",
                       "historical entry ID remains the selected detail identity")
        controlsExpect(view.entry.rows.count == 1 && view.entry.rows[0].target == "duoyi://diary/another",
                       "publication retains other diary data")
        controlsExpect(view.visibleRows.isEmpty, "small card exposes only the selected historical diary")
    }
}

controlsCase("small anniversary opens the visible primary anniversary with exact identity and frozen binding") {
    let identities = [
        ("anniversary-A", "anniversary-A"),
        ("anniversary%20%2F%3F%23%26%3D%25%20%E6%B5%8B%E8%AF%95%F0%9F%8C%99", "anniversary /?#&=% 测试🌙"),
        ("second%2Fsegment", "second/segment"),
        ("%20%20padded%20ID%20%20", "  padded ID  ")
    ]
    let secondary = [DuoyiWidgetRow(index: 2, title: "Other anniversary", target: "duoyi://anniversary/other")]
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            for (encoded, original) in identities {
                let view = controlsView("Anniversary", locale: locale, family: .systemSmall,
                                        displayMode: mode, primaryTarget: "duoyi://anniversary/\(encoded)", rows: secondary)
                let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                controlsExpect(components.host == "anniversary", "visible anniversary opens anniversary detail")
                let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                controlsExpect(segments.count == 2 && segments[0].isEmpty &&
                               String(segments[1]).removingPercentEncoding == original,
                               "anniversary preserves exactly one original opaque ID")
                controlsExpect(view.entry.rows.count == 1, "publication retains secondary anniversary data")
                controlsExpect(view.visibleRows.isEmpty, "single-target small anniversary displays only the primary object")
                controlsExpect(!view.supportsItemLinks, "small anniversary retains one root target")
            }
        }
    }
}

controlsCase("small anniversary rejects invalid primary targets without choosing another anniversary") {
    let invalid = ["", " \n ", "duoyi://anniversary", "duoyi://anniversary/", "duoyi://anniversary/%20%0A",
                   "https://example.com/anniversary/A", "duoyi://note/A", "duoyi://anniversary/A/B",
                   "duoyi://anniversary//A", "duoyi://anniversary/A/", "duoyi://user@anniversary/A",
                   "duoyi://user:password@anniversary/A", "duoyi://anniversary:99/A",
                   "duoyi://anniversary/A?confirm=1", "duoyi://anniversary/A#fragment"]
    for target in invalid {
        let view = controlsView("Anniversary", family: .systemSmall, primaryTarget: target,
                                rows: [DuoyiWidgetRow(index: 2, title: "Other", target: "duoyi://anniversary/other")])
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://anniversary", "invalid primary falls back to anniversary module")
        controlsExpect(view.visibleRows.isEmpty, "fallback does not expose a second object under one root")
    }
}

controlsCase("small anniversary rejects stale unpublished and retained-old bindings") {
    let views = [
        controlsView("Anniversary", fresh: false, family: .systemSmall, primaryTarget: "duoyi://anniversary/old"),
        controlsView("Anniversary", published: false, family: .systemSmall, primaryTarget: "duoyi://anniversary/old"),
        controlsView("Anniversary", family: .systemSmall, primaryTarget: "duoyi://anniversary/old",
                     snapshotOverride: controlsSnapshot(false))
    ]
    for view in views {
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://anniversary", "unusable anniversary snapshot opens module")
    }
    let current = controlsSnapshot(true)
    let base: [String: Any] = [
        "widget_snapshot_day": current.day,
        "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
        "widget_account_nonce": current.accountNonce
    ]
    var missingNonce = base
    missingNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base
    blankNonce["widget_account_nonce"] = " \n "
    var wrongOffset = base
    wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    for values in [missingNonce, blankNonce, wrongOffset] {
        let view = controlsView("Anniversary", family: .systemSmall, primaryTarget: "duoyi://anniversary/unsafe",
                                snapshotOverride: DuoyiWidgetSnapshot(values: values))
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://anniversary", "invalid anniversary binding opens module")
    }
}

controlsCase("larger anniversary families retain module root and original secondary rows") {
    let rows = (2...5).map { DuoyiWidgetRow(index: $0, title: "Anniversary \($0)", target: "duoyi://anniversary/id-\($0)") }
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        for mode in ["compact", "standard", "detailed"] {
            let view = controlsView("Anniversary", family: family, displayMode: mode,
                                    primaryTarget: "duoyi://anniversary/first", rows: rows)
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://anniversary", "larger anniversary retains module root")
            controlsExpect(view.supportsItemLinks, "larger anniversary keeps independent links")
            let expectedCount = family == .systemMedium ? (mode == "compact" ? 2 : 3) : (mode == "compact" ? 3 : 4)
            controlsExpect(view.visibleRows.map(\.target) == Array(rows.prefix(expectedCount)).map(\.target),
                           "larger anniversary keeps exact secondary rows and order")
        }
    }
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Anniversary", family: family, primaryTarget: "duoyi://anniversary/first", rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.host == "anniversary" && bound.percentEncodedPath == "/first", "accessory anniversary opens its visible object")
        controlsExpect(!view.supportsItemLinks, "accessory anniversary link capability unchanged")
    }
}


controlsCase("small anniversary follows the resolved memorial primary without changing deduplication") {
    let encoded = "memorial%2F%E6%B5%8B%E8%AF%95"
    let slots = [
        DuoyiAnniversaryRawSlot(sourceKey: "anniversary_highlight_1", text: "· 暂无近期纪念日", target: ""),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_1", text: "User memorial · 12 days", target: "duoyi://anniversary/\(encoded)"),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_2", text: "Duplicate identity", target: "duoyi://anniversary/\(encoded)"),
        DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_3", text: "Another object", target: "duoyi://anniversary/another")
    ]
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let resolved = DuoyiWidgetDisplayCore.resolveAnniversaryItems(slots: slots, isFresh: true, isZh: locale == .zh)
        controlsExpect(resolved.count == 2, "existing resolver still removes placeholder and duplicate identity")
        controlsExpect(resolved[0].sourceKey == "memorial_highlight_1" && resolved[0].identity == "memorial/测试",
                       "resolved first memorial remains the displayed primary identity")
        controlsExpect(resolved[0].text == "User memorial · 12 days", "user title is retained")
        let rows = resolved.dropFirst().enumerated().map { DuoyiWidgetRow(index: $0.offset + 2, title: $0.element.text, target: $0.element.target) }
        let view = controlsView("Anniversary", locale: locale, family: .systemSmall,
                                primaryTarget: resolved[0].target, rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.percentEncodedPath == "/\(encoded)", "root preserves resolved memorial encoded identity")
        controlsExpect(view.entry.rows.count == 1 && view.entry.rows[0].target == "duoyi://anniversary/another",
                       "publication still retains the other resolved object")
        controlsExpect(view.visibleRows.isEmpty, "single root does not display another memorial object")
    }
}

controlsCase("small course opens the visible primary course with exact identity and frozen binding") {
    let identities = [
        ("course-A", "course-A"),
        ("course%20%2F%3F%23%26%3D%25%20%E6%B5%8B%E8%AF%95%F0%9F%8C%99", "course /?#&=% 测试🌙"),
        ("second%2Fsegment", "second/segment"),
        ("%20%20padded%20ID%20%20", "  padded ID  ")
    ]
    let secondary = [DuoyiWidgetRow(index: 2, title: "Other course", target: "duoyi://course/other")]
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            for (encoded, original) in identities {
                let view = controlsView("Course", locale: locale, family: .systemSmall,
                                        displayMode: mode, primaryTarget: "duoyi://course/\(encoded)", rows: secondary)
                let components = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                controlsExpect(components.host == "course", "visible course opens course detail")
                let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                controlsExpect(segments.count == 2 && segments[0].isEmpty &&
                               String(segments[1]).removingPercentEncoding == original,
                               "course preserves exactly one original opaque ID")
                controlsExpect(view.entry.rows.count == 1, "publication retains secondary course data")
                controlsExpect(view.visibleRows.isEmpty, "single-target small course displays only the primary object")
                controlsExpect(!view.supportsItemLinks, "small course retains one root target")
            }
        }
    }
}

controlsCase("small course rejects invalid primary targets without choosing another course") {
    let invalid = ["", " \n ", "duoyi://course", "duoyi://course/", "duoyi://course/%20%0A",
                   "https://example.com/course/A", "duoyi://note/A", "duoyi://course/A/B",
                   "duoyi://course//A", "duoyi://course/A/", "duoyi://user@course/A",
                   "duoyi://user:password@course/A", "duoyi://course:99/A",
                   "duoyi://course/A?confirm=1", "duoyi://course/A#fragment"]
    for target in invalid {
        let view = controlsView("Course", family: .systemSmall, primaryTarget: target,
                                rows: [DuoyiWidgetRow(index: 2, title: "Other", target: "duoyi://course/other")])
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://course", "invalid primary falls back to course module")
        controlsExpect(view.visibleRows.isEmpty, "fallback does not expose a second object under one root")
    }
}

controlsCase("small course rejects stale unpublished and retained-old bindings") {
    let views = [
        controlsView("Course", fresh: false, family: .systemSmall, primaryTarget: "duoyi://course/old"),
        controlsView("Course", published: false, family: .systemSmall, primaryTarget: "duoyi://course/old"),
        controlsView("Course", family: .systemSmall, primaryTarget: "duoyi://course/old",
                     snapshotOverride: controlsSnapshot(false))
    ]
    for view in views {
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://course", "unusable course snapshot opens module")
    }
    let current = controlsSnapshot(true)
    let base: [String: Any] = [
        "widget_snapshot_day": current.day,
        "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
        "widget_account_nonce": current.accountNonce
    ]
    var missingNonce = base
    missingNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base
    blankNonce["widget_account_nonce"] = " \n "
    var wrongOffset = base
    wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    for values in [missingNonce, blankNonce, wrongOffset] {
        let view = controlsView("Course", family: .systemSmall, primaryTarget: "duoyi://course/unsafe",
                                snapshotOverride: DuoyiWidgetSnapshot(values: values))
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://course", "invalid course binding opens module")
    }
}

controlsCase("larger course families retain module root and original secondary rows") {
    let rows = (2...5).map { DuoyiWidgetRow(index: $0, title: "Course \($0)", target: "duoyi://course/id-\($0)") }
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        for mode in ["compact", "standard", "detailed"] {
            let view = controlsView("Course", family: family, displayMode: mode,
                                    primaryTarget: "duoyi://course/first", rows: rows)
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://course", "larger course retains module root")
            controlsExpect(view.supportsItemLinks, "larger course keeps independent links")
            let expectedCount = family == .systemMedium ? (mode == "compact" ? 2 : 3) : (mode == "compact" ? 3 : 4)
            controlsExpect(view.visibleRows.map(\.target) == Array(rows.prefix(expectedCount)).map(\.target),
                           "larger course keeps exact secondary rows and order")
        }
    }
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Course", family: family, primaryTarget: "duoyi://course/first", rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.host == "course" && bound.percentEncodedPath == "/first", "accessory course opens its visible object")
        controlsExpect(!view.supportsItemLinks, "accessory course link capability unchanged")
    }
}

controlsCase("small course selects its primary without exposing another course or cross-module summary") {
    let config = DuoyiWidgetConfig(kind: "DuoyiCourseWidget", deepLink: "duoyi://course",
                                    primaryKey: "course_highlight_1", fallback: "No courses today",
                                    rowKeys: ["course_highlight_2", "today_event_summary"],
                                    quickActionTitle: "Courses", quickActionLink: "duoyi://course")
    let provider = FixtureProvider()
    for locale in [DuoyiWidgetLocale.zh, .en] {
        let values: [String: Any] = [
            "course_highlight_1": "Sections 3-4 User course · User classroom",
            "course_highlight_1_id": "duoyi://course/selected%2Fcourse",
            "course_highlight_2": "Sections 5-6 Other course",
            "course_highlight_2_id": "duoyi://course/other",
            "today_event_summary": "Today: Unrelated user goal",
            "today_event_summary_id": "duoyi://goal/unrelated"
        ]
        let primary = provider.readPrimary(values, config: config, locale: locale)
        let rows = provider.readRows(values, config: config, locale: locale)
        controlsExpect(primary.title == "Sections 3-4 User course · User classroom", "primary includes its own sections and classroom")
        controlsExpect(primary.sourceKey == "course_highlight_1", "primary selection unchanged")
        controlsExpect(rows.map(\.target) == ["duoyi://course/other", "duoyi://goal/unrelated"], "provider retains second course and cross-module summary")
        for mode in ["compact", "standard", "detailed"] {
            let small = controlsView("Course", locale: locale, family: .systemSmall,
                                     displayMode: mode, primaryTarget: primary.target, rows: rows)
            let bound = controlsBoundComponents(small.widgetRootURL, snapshot: small.entry.snapshot)
            controlsExpect(bound.host == "course" && bound.percentEncodedPath == "/selected%2Fcourse", "root selects only visible primary course")
            controlsExpect(small.visibleRows.isEmpty, "small card hides both unrelated secondary targets")
            let medium = controlsView("Course", locale: locale, family: .systemMedium,
                                      displayMode: mode, primaryTarget: primary.target, rows: rows)
            controlsExpect(medium.visibleRows.map(\.target) == rows.map(\.target), "larger card retains original summary targets and order")
        }
        let empty = provider.readPrimary([:], config: config, locale: locale)
        controlsExpect(empty.target == "duoyi://course", "empty course stays a module entry")
        let emptyView = controlsView("Course", locale: locale, family: .systemSmall,
                                     primaryTarget: empty.target, rows: rows)
        controlsExpect(emptyView.widgetRootURL?.absoluteString == "duoyi://course", "empty primary does not choose another target")
    }
}

controlsCase("small schedule binds every published entity host and encoded identity") {
    let hosts = ["todo", "habit", "anniversary", "course", "diary", "goal", "countdown", "time-entry", "event", "pomodoro"]
    let identities = [
        ("event-A", "event-A"),
        ("first%2Fevent", "first/event"),
        ("event%20%2F%3F%23%26%3D%25%20%E6%B5%8B%E8%AF%95%F0%9F%8C%99", "event /?#&=% 测试🌙"),
        ("%20%20padded%20ID%20%20", "  padded ID  ")
    ]
    let rows = [DuoyiWidgetRow(index: 2, title: "Other event", target: "duoyi://habit/other")]
    for host in hosts {
        for (encoded, original) in identities {
            for locale in [DuoyiWidgetLocale.zh, .en] {
                for mode in ["compact", "standard", "detailed"] {
                    let view = controlsView("Schedule", locale: locale, family: .systemSmall,
                                            displayMode: mode, primaryTarget: "duoyi://\(host)/\(encoded)", rows: rows)
                    let target = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
                    controlsExpect(target.host == host, "schedule opens its visible event host")
                    controlsExpect(target.percentEncodedPath == "/\(encoded)", "original encoded path retained")
                    let parts = target.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
                    controlsExpect(parts.count == 2 && parts[0].isEmpty && String(parts[1]).removingPercentEncoding == original,
                                   "opaque event identity is decoded only after splitting")
                    controlsExpect(view.visibleRows.isEmpty, "single-root schedule displays only its primary object")
                    controlsExpect(!view.supportsItemLinks, "small schedule does not invent independent links")
                }
            }
        }
    }
}

controlsCase("small schedule accepts only the two actual module projections") {
    for target in ["duoyi://calendar", "duoyi://focus"] {
        for locale in [DuoyiWidgetLocale.zh, .en] {
            for mode in ["compact", "standard", "detailed"] {
                let view = controlsView("Schedule", locale: locale, family: .systemSmall,
                                        displayMode: mode, primaryTarget: target,
                                        rows: [DuoyiWidgetRow(index: 2, title: "Other", target: "duoyi://todo/other")])
                controlsExpect(view.widgetRootURL?.absoluteString == target, "local event/pomodoro retains its published module")
                controlsExpect(view.visibleRows.isEmpty, "module primary does not expose a different object")
            }
        }
    }
}

controlsCase("small schedule rejects malformed foreign and ambiguous primary targets") {
    let invalid = ["", " ", "duoyi://todo", "duoyi://habit/", "duoyi://todo/%20%0A",
                   "https://todo/A", "duoyi://note/A", "duoyi://unknown/A", "duoyi://action/complete_todo?id=A",
                   "duoyi://tab/calendar", "duoyi://todo/A/B", "duoyi://todo//A", "duoyi://todo/A/",
                   "duoyi://user@todo/A", "duoyi://user:password@habit/A", "duoyi://course:99/A",
                   "duoyi://goal/A?source=widget", "duoyi://diary/A?", "duoyi://anniversary/A#fragment",
                   "duoyi://calendar/", "duoyi://calendar/event-A", "duoyi://calendar?date=2026-10-20",
                   "duoyi://calendar?", "duoyi://focus/", "duoyi://focus/A", "duoyi://focus#fragment",
                   "duoyi://focus?source=widget", "duoyi://user@calendar", "duoyi://focus:99"]
    for target in invalid {
        let view = controlsView("Schedule", family: .systemSmall, primaryTarget: target,
                                rows: [DuoyiWidgetRow(index: 2, title: "Do not select this", target: "duoyi://todo/other")])
        controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://calendar", "invalid primary falls back without choosing another row: \(target)")
        controlsExpect(view.visibleRows.isEmpty, "invalid target does not change the displayed object")
    }
}

controlsCase("small schedule rejects stale unpublished and inconsistent snapshot bindings") {
    let current = controlsSnapshot(true)
    let base: [String: Any] = ["widget_snapshot_day": current.day,
                              "widget_snapshot_utc_offset_minutes": current.utcOffsetMinutes!,
                              "widget_account_nonce": current.accountNonce]
    var missingNonce = base
    missingNonce.removeValue(forKey: "widget_account_nonce")
    var blankNonce = base
    blankNonce["widget_account_nonce"] = " \n "
    var wrongOffset = base
    wrongOffset["widget_snapshot_utc_offset_minutes"] = current.utcOffsetMinutes == 0 ? 60 : 0
    for target in ["duoyi://todo/old", "duoyi://focus", "duoyi://calendar"] {
        var views = [controlsView("Schedule", fresh: false, family: .systemSmall, primaryTarget: target),
                     controlsView("Schedule", published: false, family: .systemSmall, primaryTarget: target),
                     controlsView("Schedule", family: .systemSmall, primaryTarget: target,
                                  snapshotOverride: controlsSnapshot(false))]
        for values in [missingNonce, blankNonce, wrongOffset] {
            views.append(controlsView("Schedule", family: .systemSmall, primaryTarget: target,
                                      snapshotOverride: DuoyiWidgetSnapshot(values: values)))
        }
        for view in views {
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://calendar", "invalid binding returns original module even for focus navigation")
        }
    }
}

controlsCase("larger schedule keeps rows while accessory opens its single primary") {
    let rows = (2...5).map { DuoyiWidgetRow(index: $0, title: "Other event \($0)", target: "duoyi://habit/id-\($0)") }
    for family in [FixtureFamily.systemMedium, .systemLarge, .systemExtraLarge] {
        for mode in ["compact", "standard", "detailed"] {
            let view = controlsView("Schedule", family: family, displayMode: mode,
                                    primaryTarget: "duoyi://todo/first", rows: rows)
            controlsExpect(view.widgetRootURL?.absoluteString == "duoyi://calendar", "larger schedule keeps calendar root")
            controlsExpect(view.supportsItemLinks, "larger schedule keeps per-event links")
            let limit = family == .systemMedium ? (mode == "compact" ? 2 : 3) : (mode == "compact" ? 3 : 5)
            controlsExpect(view.visibleRows.map(\.target) == Array(rows.prefix(limit)).map(\.target), "larger rows retain order and exact targets")
        }
    }
    for family in [FixtureFamily.accessoryInline, .accessoryCircular, .accessoryRectangular] {
        let view = controlsView("Schedule", family: family, primaryTarget: "duoyi://todo/first", rows: rows)
        let bound = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
        controlsExpect(bound.host == "todo" && bound.percentEncodedPath == "/first", "accessory schedule opens its visible first event")
        controlsExpect(!view.supportsItemLinks, "accessory link support unchanged")
    }
}

controlsCase("small schedule joins production primary projection to its one visible target") {
    let provider = FixtureProvider()
    let config = controlsConfig("Schedule")
    for locale in [DuoyiWidgetLocale.zh, .en] {
        for mode in ["compact", "standard", "detailed"] {
            let values: [String: Any] = [
                "today_event_summary": "Today: First literal event",
                "schedule_highlight_1": "09:00 First literal event",
                "schedule_highlight_1_id": "duoyi://countdown/first%2Fevent",
                "schedule_highlight_2": "10:00 Other literal event",
                "schedule_highlight_2_id": "duoyi://goal/other",
                "schedule_highlight_3": "11:00 Third literal event",
                "schedule_highlight_3_id": "duoyi://diary/third"
            ]
            let primary = provider.readPrimary(values, config: config, locale: locale)
            let rows = provider.readRows(values, config: config, locale: locale, excluding: primary.sourceKey)
            controlsExpect(primary.title == "09:00 First literal event" && rows.count == 2, "actual projection selects first and excludes duplication")
            let view = controlsView("Schedule", locale: locale, family: .systemSmall, displayMode: mode,
                                    primaryTarget: primary.target, rows: rows)
            let target = controlsBoundComponents(view.widgetRootURL, snapshot: view.entry.snapshot)
            controlsExpect(target.host == "countdown" && target.percentEncodedPath == "/first%2Fevent", "root and visible first event agree")
            controlsExpect(view.visibleRows.isEmpty, "second and third objects are not displayed under the primary root")
            let empty = provider.readPrimary([:], config: config, locale: locale)
            let emptyView = controlsView("Schedule", locale: locale, family: .systemSmall, displayMode: mode,
                                         primaryTarget: empty.target, rows: rows)
            controlsExpect(emptyView.widgetRootURL?.absoluteString == "duoyi://calendar", "empty schedule remains a calendar entry")
        }
    }
}
