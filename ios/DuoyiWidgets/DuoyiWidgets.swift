import SwiftUI
import WidgetKit

private let appGroupId = "group.com.duoyi.duoyi"

private let duoyiPathSegmentAllowed: CharacterSet = {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
    return allowed
}()

private enum DuoyiWidgetLocale: String {
    case zh
    case en

    private static func language(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "-", with: "_")
            .components(separatedBy: "_").first ?? ""
    }

    static func resolve(_ defaults: UserDefaults?) -> DuoyiWidgetLocale {
        resolve(saved: defaults?.string(forKey: "widget_locale"))
    }

    static func resolve(saved: String?) -> DuoyiWidgetLocale {
        switch language(saved) {
        case "en": return .en
        case "zh": return .zh
        default:
            let system = Locale.preferredLanguages.first ?? Locale.current.languageCode
            return language(system) == "en" ? .en : .zh
        }
    }

}


// Freeze metadata with the payload; an old timeline must never borrow a newer
// account nonce when constructing a mutation link.
private struct DuoyiWidgetSnapshot {
    let day: String
    let utcOffsetMinutes: Int?
    let accountNonce: String

    static let empty = DuoyiWidgetSnapshot(day: "", utcOffsetMinutes: nil, accountNonce: "")

    init(values: [String: Any]) {
        day = values["widget_snapshot_day"] as? String ?? ""
        accountNonce = values["widget_account_nonce"] as? String ?? ""
        if let number = values["widget_snapshot_utc_offset_minutes"] as? NSNumber {
            utcOffsetMinutes = number.intValue
        } else if let text = values["widget_snapshot_utc_offset_minutes"] as? String {
            utcOffsetMinutes = Int(text)
        } else {
            utcOffsetMinutes = nil
        }
    }

    private init(day: String, utcOffsetMinutes: Int?, accountNonce: String) {
        self.day = day
        self.utcOffsetMinutes = utcOffsetMinutes
        self.accountNonce = accountNonce
    }

    var hasPublishedSession: Bool {
        !day.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !accountNonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isFresh(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let fields = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = fields.year, let month = fields.month, let dateDay = fields.day else {
            return false
        }
        let localDay = String(format: "%04d-%02d-%02d", year, month, dateDay)
        return hasPublishedSession && day == localDay &&
            utcOffsetMinutes == TimeZone.current.secondsFromGMT(for: date) / 60
    }

    func actionURL(_ components: URLComponents?) -> URL? {
        guard var components = components else { return nil }
        guard components.host == "action" else { return components.url }
        let action = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasQuickText = components.queryItems?.contains {
            $0.name == "text" && !($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        // Opening quick entry and requesting refresh are recoverable navigation.
        let mutates = ["complete_todo", "checkin_habit", "start_pomodoro"].contains(action) ||
            (action == "quick_todo" && hasQuickText)
        guard mutates else { return components.url }
        guard isFresh(at: Date()), let offset = utcOffsetMinutes else { return nil }
        let bindingKeys = Set(["source", "widget_day", "widget_offset", "widget_account"])
        var items = (components.queryItems ?? []).filter { !bindingKeys.contains($0.name) }
        items.append(contentsOf: [
            URLQueryItem(name: "source", value: "widget"),
            URLQueryItem(name: "widget_day", value: day),
            URLQueryItem(name: "widget_offset", value: String(offset)),
            URLQueryItem(name: "widget_account", value: accountNonce)
        ])
        components.queryItems = items
        return components.url
    }
}

private struct DuoyiWidgetConfig {
    let kind: String
    let title: String
    let deepLink: String
    let accent: Color
    let primaryKey: String
    let fallback: String
    let rowKeys: [String]
    let quickActionTitle: String
    let quickActionLink: String
    let titleEn: String
    let fallbackEn: String
    let quickActionTitleEn: String

    func localized(for locale: DuoyiWidgetLocale) -> DuoyiWidgetConfig {
        guard locale == .en else {
            return self
        }
        return DuoyiWidgetConfig(
            kind: kind,
            title: titleEn,
            deepLink: deepLink,
            accent: accent,
            primaryKey: primaryKey,
            fallback: fallbackEn,
            rowKeys: rowKeys,
            quickActionTitle: quickActionTitleEn,
            quickActionLink: quickActionLink,
            titleEn: titleEn,
            fallbackEn: fallbackEn,
            quickActionTitleEn: quickActionTitleEn
        )
    }

    func galleryDescription(for locale: DuoyiWidgetLocale) -> String {
        if locale == .en {
            return "Duoyi \(titleEn) widget"
        } else {
            return "多仪 \(title) 小组件"
        }
    }
}

private struct DuoyiWidgetTheme {
    let primary: Color
    let background: Color
    let surface: Color
    let navBackground: Color
    let text: Color
    let mutedText: Color
    let onPrimary: Color
    let accentStart: Color
    let accentEnd: Color

    static let fallback = DuoyiWidgetTheme(
        primary: color("#FFFF6B6B"),
        background: color("#FFFFFFFF"),
        surface: color("#FFFFFFFF"),
        navBackground: color("#FFFFF6F2"),
        text: color("#FF333333"),
        mutedText: color("#FF666666"),
        onPrimary: color("#FFFFFFFF"),
        accentStart: color("#FFFF6B6B"),
        accentEnd: color("#FFFFB088")
    )

    init(values: [String: Any]) {
        self.primary = Self.read(values, key: "widget_theme_primary", fallback: "#FFFF6B6B")
        self.background = Self.read(values, key: "widget_theme_background", fallback: "#FFFFFFFF")
        self.surface = Self.read(values, key: "widget_theme_surface", fallback: "#FFFFFFFF")
        self.navBackground = Self.read(values, key: "widget_theme_nav_background", fallback: "#FFFFF6F2")
        self.text = Self.read(values, key: "widget_theme_text", fallback: "#FF333333")
        self.mutedText = Self.read(values, key: "widget_theme_muted_text", fallback: "#FF666666")
        self.onPrimary = Self.read(values, key: "widget_theme_on_primary", fallback: "#FFFFFFFF")
        self.accentStart = Self.read(values, key: "widget_theme_accent_start", fallback: "#FFFF6B6B")
        self.accentEnd = Self.read(values, key: "widget_theme_accent_end", fallback: "#FFFFB088")
    }

    private init(
        primary: Color,
        background: Color,
        surface: Color,
        navBackground: Color,
        text: Color,
        mutedText: Color,
        onPrimary: Color,
        accentStart: Color,
        accentEnd: Color
    ) {
        self.primary = primary
        self.background = background
        self.surface = surface
        self.navBackground = navBackground
        self.text = text
        self.mutedText = mutedText
        self.onPrimary = onPrimary
        self.accentStart = accentStart
        self.accentEnd = accentEnd
    }

    private static func read(_ values: [String: Any], key: String, fallback: String) -> Color {
        color(values[key] as? String ?? fallback)
    }

    private static func color(_ raw: String) -> Color {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let normalized: String
        if clean.count == 6 {
            normalized = "FF\(clean)"
        } else if clean.count == 8 {
            normalized = clean
        } else {
            normalized = "FFFF6B6B"
        }
        guard let value = UInt64(normalized, radix: 16) else {
            return Color(red: 1.0, green: 0.42, blue: 0.42)
        }
        let alpha = Double((value >> 24) & 0xFF) / 255.0
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct DuoyiTodoRow: Identifiable {
    let index: Int
    let title: String
    let todoId: String
    let snapshot: DuoyiWidgetSnapshot

    var id: Int { index }

    var detailURL: URL? {
        guard !todoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let encodedId = todoId.addingPercentEncoding(withAllowedCharacters: duoyiPathSegmentAllowed) ?? todoId
        return URL(string: "duoyi://todo/\(encodedId)")
    }

    var completeURL: URL? {
        guard !todoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var components = URLComponents(string: "duoyi://action/complete_todo")
        components?.queryItems = [URLQueryItem(name: "id", value: todoId)]
        return snapshot.actionURL(components)
    }
}

private struct DuoyiWidgetRow: Identifiable {
    let index: Int
    let title: String
    let target: String

    var id: Int { index }

    var url: URL? {
        let clean = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return nil
        }
        return URL(string: clean)
    }
}

private func localizedFallbackString(_ raw: String, kind: String, locale: DuoyiWidgetLocale) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = value.hasPrefix("· ") ? "· " : ""
    let trimmed = prefix.isEmpty ? value : String(value.dropFirst(2))
    switch kind {
    case "DuoyiTodoWidget":
        if trimmed == "今天没有未完成待办" || trimmed == "No open tasks today" {
            return prefix + (locale == .en ? "No open tasks today" : "今天没有未完成待办")
        }
    case "DuoyiFocusWidget":
        if trimmed == "25 分钟专注" || trimmed == "25-min focus" {
            return prefix + (locale == .en ? "25-min focus" : "25 分钟专注")
        }
    case "DuoyiHabitWidget":
        if trimmed == "今日习惯待打卡" || trimmed == "Habits to check in today" {
            return prefix + (locale == .en ? "Habits to check in today" : "今日习惯待打卡")
        }
    case "DuoyiCalendarWidget":
        if trimmed == "本月日期 · 今日已标记" || trimmed == "Month view · today is marked" {
            return prefix + (locale == .en ? "Month view · today is marked" : "本月日期 · 今日已标记")
        }
    case "DuoyiScheduleWidget":
        if trimmed == "今日没有日程" || trimmed == "No events today" {
            return prefix + (locale == .en ? "No events today" : "今日没有日程")
        }
    case "DuoyiGoalWidget":
        if trimmed == "暂无进行中目标" || trimmed == "No active goals" {
            return prefix + (locale == .en ? "No active goals" : "暂无进行中目标")
        }
    case "DuoyiCourseWidget":
        if trimmed == "今日暂无课程" || trimmed == "No courses today" {
            return prefix + (locale == .en ? "No courses today" : "今日暂无课程")
        }
    case "DuoyiNoteWidget":
        if trimmed == "暂无随手记" || trimmed == "No notes yet" {
            return prefix + (locale == .en ? "No notes yet" : "暂无随手记")
        }
    case "DuoyiAnniversaryWidget":
        if trimmed == "暂无近期纪念日" || trimmed == "No upcoming anniversaries" || trimmed == "暂无纪念日" {
            return prefix + (locale == .en ? "No upcoming anniversaries" : "暂无近期纪念日")
        }
    case "DuoyiDiaryWidget":
        if trimmed == "暂无日记" || trimmed == "No diary entries yet" {
            return prefix + (locale == .en ? "No diary entries yet" : "暂无日记")
        }
    default:
        break
    }
    return raw
}

private func isAnniversaryFallback(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ||
        trimmed == "暂无近期纪念日" ||
        trimmed == "No upcoming anniversaries" ||
        trimmed == "暂无纪念日"
}

private struct DuoyiWidgetEntry: TimelineEntry {
    let date: Date
    let config: DuoyiWidgetConfig
    let locale: DuoyiWidgetLocale
    let snapshot: DuoyiWidgetSnapshot
    let primary: String
    let primaryTarget: String
    let rows: [DuoyiWidgetRow]
    let todoRows: [DuoyiTodoRow]
    let brandTitle: String
    let navTodo: String
    let navHabit: String
    let navCalendar: String
    let navFocus: String
    let displayMode: String
    let habitQuickCheckId: String
    let focusTimerRunning: Bool
    let focusTimerRemainingSeconds: Int
    let focusTimerTotalSeconds: Int
    let focusTimerEndsAtMillis: Int64
    let focusTimerLabel: String
    let theme: DuoyiWidgetTheme

    var focusTimerEndDate: Date? {
        guard focusTimerEndsAtMillis > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(focusTimerEndsAtMillis) / 1000)
    }
}

private struct DuoyiWidgetProvider: TimelineProvider {
    let config: DuoyiWidgetConfig

    func placeholder(in context: Context) -> DuoyiWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let locale = DuoyiWidgetLocale.resolve(defaults)
        let localizedConfig = config.localized(for: locale)
        return DuoyiWidgetEntry(
            date: Date(),
            config: localizedConfig,
            locale: locale,
            snapshot: .empty,
            primary: localizedConfig.fallback,
            primaryTarget: localizedConfig.deepLink,
            rows: localizedConfig.rowKeys.enumerated().map {
                DuoyiWidgetRow(index: $0.offset + 2, title: localizedConfig.fallback, target: localizedConfig.deepLink)
            },
            todoRows: [],
            brandTitle: locale == .en ? "Duoyi" : "多仪",
            navTodo: locale == .en ? "Tasks" : "待办",
            navHabit: locale == .en ? "Habits" : "习惯",
            navCalendar: locale == .en ? "Calendar" : "日历",
            navFocus: locale == .en ? "Focus" : "专注",
            displayMode: "standard",
            habitQuickCheckId: "",
            focusTimerRunning: false,
            focusTimerRemainingSeconds: 0,
            focusTimerTotalSeconds: 0,
            focusTimerEndsAtMillis: 0,
            focusTimerLabel: locale == .en ? "Focus countdown" : "专注倒计时",
            theme: .fallback
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DuoyiWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DuoyiWidgetEntry>) -> Void) {
        let current = entry()
        let refreshMinutes = current.focusTimerRunning ? 1 : 15
        let now = current.date
        var nextRefresh = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: now) ?? now.addingTimeInterval(60)
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            nextRefresh = min(nextRefresh, midnight)
        }
        if current.focusTimerRunning, let end = current.focusTimerEndDate, end > now {
            nextRefresh = min(nextRefresh, end)
        }
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry() -> DuoyiWidgetEntry {
        // One immutable read avoids mixing item IDs and account metadata.
        let defaults = UserDefaults(suiteName: appGroupId)?.dictionaryRepresentation() ?? [:]
        let now = Date()
        let snapshot = DuoyiWidgetSnapshot(values: defaults)
        let fresh = snapshot.isFresh(at: now)
        let locale = DuoyiWidgetLocale.resolve(saved: defaults["widget_locale"] as? String)
        let localizedConfig = config.localized(for: locale)
        let todoRows = fresh ? readTodoRows(defaults, locale: locale, snapshot: snapshot) : []
        let primary: String
        let primaryTarget: String
        let rows: [DuoyiWidgetRow]
        if !fresh {
            primary = locale == .en ? "Open Duoyi to refresh" : "打开多仪刷新数据"
            primaryTarget = localizedConfig.deepLink
            rows = []
        } else if localizedConfig.kind == "DuoyiTodoWidget" {
            primary = todoRows.first?.title ?? localizedConfig.fallback
            primaryTarget = todoRows.first?.detailURL?.absoluteString ?? localizedConfig.deepLink
            rows = []
        } else {
            let primarySource = readPrimary(defaults, config: localizedConfig, locale: locale)
            primary = primarySource.title
            primaryTarget = primarySource.target
            rows = readRows(defaults, config: localizedConfig, locale: locale, excluding: primarySource.sourceKey)
        }
        let brandFallback = locale == .en ? "Duoyi" : "多仪"
        let rawBrand = readString(defaults, key: "brand_app_title", fallback: brandFallback)
        let brandTitle = (locale == .en && rawBrand == "多仪") ? "Duoyi" : (locale == .zh && rawBrand == "Duoyi" ? "多仪" : rawBrand)

        let navTodoFallback = locale == .en ? "Tasks" : "待办"
        let rawNavTodo = readString(defaults, key: "nav_todo", fallback: navTodoFallback)
        let navTodo = (locale == .en && rawNavTodo == "待办") ? "Tasks" : (locale == .zh && rawNavTodo == "Tasks" ? "待办" : rawNavTodo)

        let navHabitFallback = locale == .en ? "Habits" : "习惯"
        let rawNavHabit = readString(defaults, key: "nav_habit", fallback: navHabitFallback)
        let navHabit = (locale == .en && rawNavHabit == "习惯") ? "Habits" : (locale == .zh && rawNavHabit == "Habits" ? "习惯" : rawNavHabit)

        let navCalendarFallback = locale == .en ? "Calendar" : "日历"
        let rawNavCalendar = readString(defaults, key: "nav_calendar", fallback: navCalendarFallback)
        let navCalendar = (locale == .en && rawNavCalendar == "日历") ? "Calendar" : (locale == .zh && rawNavCalendar == "Calendar" ? "日历" : rawNavCalendar)

        let navFocusFallback = locale == .en ? "Focus" : "专注"
        let rawNavFocus = readString(defaults, key: "nav_focus", fallback: navFocusFallback)
        let navFocus = (locale == .en && rawNavFocus == "专注") ? "Focus" : (locale == .zh && rawNavFocus == "Focus" ? "专注" : rawNavFocus)

        let focusTimerLabelFallback = locale == .en ? "Focus countdown" : "专注倒计时"
        let rawTimerLabel = readString(defaults, key: "focus_timer_label", fallback: focusTimerLabelFallback)
        let focusTimerLabel = (locale == .en && rawTimerLabel == "专注倒计时") ? "Focus countdown" : (locale == .zh && rawTimerLabel == "Focus countdown" ? "专注倒计时" : rawTimerLabel)

        return DuoyiWidgetEntry(
            date: now,
            config: localizedConfig,
            locale: locale,
            snapshot: snapshot,
            primary: primary,
            primaryTarget: primaryTarget,
            rows: rows,
            todoRows: todoRows,
            brandTitle: brandTitle,
            navTodo: navTodo,
            navHabit: navHabit,
            navCalendar: navCalendar,
            navFocus: navFocus,
            displayMode: readString(defaults, key: "widget_display_mode", fallback: "standard"),
            habitQuickCheckId: fresh ? readString(defaults, key: "habit_quick_check_id", fallback: "") : "",
            focusTimerRunning: snapshot.hasPublishedSession ? readBool(defaults, key: "focus_timer_running") : false,
            focusTimerRemainingSeconds: snapshot.hasPublishedSession ? readInt(defaults, key: "focus_timer_remaining_seconds") : 0,
            focusTimerTotalSeconds: snapshot.hasPublishedSession ? readInt(defaults, key: "focus_timer_total_seconds") : 0,
            focusTimerEndsAtMillis: snapshot.hasPublishedSession ? readInt64(defaults, key: "focus_timer_ends_at_millis") : 0,
            focusTimerLabel: focusTimerLabel,
            theme: DuoyiWidgetTheme(values: defaults)
        )
    }

    private func readString(_ defaults: [String: Any], key: String, fallback: String) -> String {
        guard let value = defaults[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }

    private func readPrimary(_ defaults: [String: Any], config: DuoyiWidgetConfig, locale: DuoyiWidgetLocale) -> (title: String, target: String, sourceKey: String) {
        let rawTitle = readString(defaults, key: config.primaryKey, fallback: config.fallback)
        let itemTarget = readString(defaults, key: "\(config.primaryKey)_id", fallback: "")
        var target = itemTarget.isEmpty ? config.deepLink : itemTarget
        var sourceKey = config.primaryKey
        var title = itemTarget.isEmpty
            ? localizedFallbackString(rawTitle, kind: config.kind, locale: locale)
            : rawTitle

        if config.kind == "DuoyiAnniversaryWidget" {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if isAnniversaryFallback(trimmedTitle) {
                let memorialTitle = readString(defaults, key: "memorial_highlight_1", fallback: "")
                let trimmedMemorialTitle = memorialTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedMemorialTitle.isEmpty && !isAnniversaryFallback(trimmedMemorialTitle) {
                    title = memorialTitle
                    target = readString(defaults, key: "memorial_highlight_1_id", fallback: config.deepLink)
                    sourceKey = "memorial_highlight_1"
                }
            }
        }

        return (title, target, sourceKey)
    }

    private func readBool(_ defaults: [String: Any], key: String) -> Bool {
        (defaults[key] as? NSNumber)?.boolValue ?? false
    }

    private func readInt(_ defaults: [String: Any], key: String) -> Int {
        Int(readInt64(defaults, key: key))
    }

    private func readInt64(_ defaults: [String: Any], key: String) -> Int64 {
        guard let value = defaults[key] else {
            return 0
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String {
            return Int64(string) ?? 0
        }
        return 0
    }

    private func readTodoRows(_ defaults: [String: Any], locale: DuoyiWidgetLocale, snapshot: DuoyiWidgetSnapshot) -> [DuoyiTodoRow] {
        guard config.kind == "DuoyiTodoWidget" else {
            return []
        }
        return (1...3).compactMap { index in
            let title = readString(defaults, key: "todo_top3_\(index)", fallback: "")
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let todoId = readString(defaults, key: "todo_top3_\(index)_id", fallback: "")
            return DuoyiTodoRow(
                index: index,
                title: todoId.isEmpty
                    ? localizedFallbackString(title, kind: config.kind, locale: locale)
                    : title,
                todoId: todoId,
                snapshot: snapshot
            )
        }
    }

    private func readRows(_ defaults: [String: Any], config: DuoyiWidgetConfig, locale: DuoyiWidgetLocale, excluding excludedKey: String? = nil) -> [DuoyiWidgetRow] {
        return config.rowKeys.enumerated().compactMap { offset, key in
            if let excludedKey = excludedKey, key == excludedKey {
                return nil
            }
            let title = readString(defaults, key: key, fallback: "")
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let itemTarget = readString(defaults, key: "\(key)_id", fallback: "")
            return DuoyiWidgetRow(
                index: offset + 2,
                title: itemTarget.isEmpty
                    ? localizedFallbackString(title, kind: config.kind, locale: locale)
                    : title,
                target: itemTarget.isEmpty ? config.deepLink : itemTarget
            )
        }
    }
}

private struct DuoyiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DuoyiWidgetEntry

    @ViewBuilder
    var body: some View {
        if isAccessoryFamily {
            accessoryContent
                .widgetURL(URL(string: entry.config.deepLink))
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                header
                content
                Spacer(minLength: 0)
                if family != .systemSmall {
                    footer
                }
            }
            .padding(padding)
            .duoyiWidgetBackground(entry.theme)
            .widgetURL(URL(string: entry.config.deepLink))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.theme.primary)
                .frame(width: 8, height: 8)
            Text(entry.config.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(entry.theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(entry.brandTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(entry.theme.mutedText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let quickURL {
                Link(destination: quickURL) {
                    Text(entry.config.quickActionTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(entry.theme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if entry.config.kind == "DuoyiTodoWidget" {
            todoContent
        } else if entry.config.kind == "DuoyiFocusWidget" {
            focusContent
        } else {
            defaultContent
        }
    }

    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.focusTimerRunning, let endDate = entry.focusTimerEndDate, endDate > Date() {
                Text(endDate, style: .timer)
                    .font(.system(size: primarySize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                    .foregroundColor(entry.theme.primary)
                Text(entry.focusTimerLabel)
                    .font(.system(size: rowSize, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(entry.theme.mutedText)
            } else {
                linkedText(entry.primary, target: entry.primaryTarget, primary: true)
            }
            ForEach(visibleRows) { row in
                linkedText(row.title, target: row.target, primary: false)
            }
        }
    }

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            linkedText(entry.primary, target: entry.primaryTarget, primary: true)
            ForEach(visibleRows) { row in
                linkedText(row.title, target: row.target, primary: false)
            }
        }
    }

    private func linkedText(_ title: String, target: String, primary: Bool) -> some View {
        Group {
            if let url = entry.snapshot.actionURL(URLComponents(string: target)), !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Link(destination: url) {
                    rowText(title, primary: primary)
                }
            } else {
                rowText(title, primary: primary)
            }
        }
    }

    private func rowText(_ title: String, primary: Bool) -> some View {
        Text(cleanRow(title))
            .font(.system(size: primary ? primarySize : rowSize, weight: primary ? .semibold : .regular))
            .lineLimit(primary ? primaryLines : 1)
            .truncationMode(.tail)
            .foregroundColor(primary ? entry.theme.text : entry.theme.mutedText)
    }

    private var todoContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let first = entry.todoRows.first {
                todoRow(first, primary: true)
            } else {
                Text(entry.primary)
                    .font(.system(size: primarySize, weight: .semibold))
                    .lineLimit(primaryLines)
                    .truncationMode(.tail)
                    .foregroundColor(entry.theme.text)
            }
            ForEach(visibleTodoRows) { row in
                todoRow(row, primary: false)
            }
        }
    }

    private func todoRow(_ row: DuoyiTodoRow, primary: Bool) -> some View {
        HStack(spacing: 6) {
            if let detailURL = row.detailURL {
                Link(destination: detailURL) {
                    todoText(row.title, primary: primary)
                }
            } else {
                todoText(row.title, primary: primary)
            }
            Spacer(minLength: 0)
            if let completeURL = row.completeURL {
                Link(destination: completeURL) {
                    Text("o")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(entry.theme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func todoText(_ title: String, primary: Bool) -> some View {
        Text(cleanRow(title))
            .font(.system(size: primary ? primarySize : rowSize, weight: primary ? .semibold : .regular))
            .lineLimit(primary ? primaryLines : 1)
            .truncationMode(.tail)
            .foregroundColor(primary ? entry.theme.text : entry.theme.mutedText)
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if #available(iOSApplicationExtension 16.0, *) {
            switch family {
            case .accessoryInline:
                Text("\(entry.config.title) \(accessoryPrimaryText)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        if entry.locale == .en {
                            Image(systemName: accessorySFSymbol)
                                .font(.system(size: 15, weight: .semibold))
                        } else {
                            Text(accessorySymbol)
                                .font(.system(size: 18, weight: .bold))
                        }
                        Text(accessoryShortText)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.7)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.config.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(accessoryPrimaryText)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let row = accessorySecondaryText {
                        Text(row)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            default:
                Text(accessoryPrimaryText)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(accessoryPrimaryText)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            navLink(entry.navTodo, "duoyi://todo")
            navLink(entry.navHabit, "duoyi://habit")
            navLink(entry.navCalendar, "duoyi://calendar")
            navLink(entry.navFocus, "duoyi://focus")
        }
    }

    private func navLink(_ text: String, _ urlString: String) -> some View {
        Group {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    navText(text)
                }
            } else {
                navText(text)
            }
        }
    }

    private func navText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(entry.theme.mutedText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var visibleRows: [DuoyiWidgetRow] {
        let limit: Int
        switch family {
        case .systemSmall:
            limit = entry.displayMode == "detailed" ? 2 : 1
        case .systemMedium:
            limit = entry.displayMode == "compact" ? 2 : 3
        default:
            limit = entry.displayMode == "compact" ? 3 : 5
        }
        return Array(entry.rows.prefix(limit))
    }

    private var visibleTodoRows: [DuoyiTodoRow] {
        let limit: Int
        switch family {
        case .systemSmall:
            limit = entry.displayMode == "detailed" ? 1 : 0
        case .systemMedium:
            limit = entry.displayMode == "compact" ? 1 : 2
        default:
            limit = entry.displayMode == "compact" ? 2 : 2
        }
        return Array(entry.todoRows.dropFirst().prefix(limit))
    }

    private func cleanRow(_ row: String) -> String {
        row.hasPrefix("· ") ? String(row.dropFirst(2)) : row
    }

    private var spacing: CGFloat {
        family == .systemSmall ? 7 : 9
    }

    private var padding: CGFloat {
        family == .systemSmall ? 12 : 14
    }

    private var primarySize: CGFloat {
        family == .systemSmall ? 15 : 17
    }

    private var primaryLines: Int {
        family == .systemSmall ? 2 : 3
    }

    private var rowSize: CGFloat {
        family == .systemSmall ? 11 : 12
    }

    private var isAccessoryFamily: Bool {
        if #available(iOSApplicationExtension 16.0, *) {
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                return true
            default:
                return false
            }
        }
        return false
    }

    private var accessoryPrimaryText: String {
        if entry.config.kind == "DuoyiTodoWidget", let first = entry.todoRows.first {
            return cleanRow(first.title)
        }
        if entry.config.kind == "DuoyiFocusWidget",
           entry.focusTimerRunning,
           entry.focusTimerRemainingSeconds > 0 {
            return formatMinutes(entry.focusTimerRemainingSeconds)
        }
        return cleanRow(entry.primary)
    }

    private var accessorySecondaryText: String? {
        if entry.config.kind == "DuoyiTodoWidget" {
            return entry.todoRows.dropFirst().first.map { cleanRow($0.title) }
        }
        return visibleRows.first.map { cleanRow($0.title) }
    }

    private var accessoryShortText: String {
        if entry.config.kind == "DuoyiFocusWidget",
           entry.focusTimerRunning,
           entry.focusTimerRemainingSeconds > 0 {
            let minutes = max(1, (entry.focusTimerRemainingSeconds + 59) / 60)
            return entry.locale == .en ? "\(minutes)m" : "\(minutes)分"
        }
        let text = accessoryPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return entry.locale == .en ? "None" : "暂无"
        }
        if isKnownFallback(text) {
            return entry.locale == .en ? "None" : "暂无"
        }
        return String(text.prefix(4))
    }

    private var accessorySymbol: String {
        if entry.locale == .en {
            switch entry.config.kind {
            case "DuoyiTodoWidget":
                return "✓"
            case "DuoyiFocusWidget":
                return "⏱"
            case "DuoyiHabitWidget":
                return "★"
            case "DuoyiCalendarWidget", "DuoyiScheduleWidget":
                return "📅"
            case "DuoyiGoalWidget":
                return "🎯"
            case "DuoyiCourseWidget":
                return "📚"
            case "DuoyiNoteWidget":
                return "📝"
            case "DuoyiAnniversaryWidget":
                return "♥"
            case "DuoyiDiaryWidget":
                return "📖"
            default:
                return "D"
            }
        }
        switch entry.config.kind {
        case "DuoyiTodoWidget":
            return "待"
        case "DuoyiFocusWidget":
            return "专"
        case "DuoyiHabitWidget":
            return "习"
        case "DuoyiCalendarWidget", "DuoyiScheduleWidget":
            return "历"
        case "DuoyiGoalWidget":
            return "目"
        case "DuoyiCourseWidget":
            return "课"
        case "DuoyiNoteWidget":
            return "记"
        case "DuoyiAnniversaryWidget":
            return "念"
        case "DuoyiDiaryWidget":
            return "日"
        default:
            return "多"
        }
    }

    private var accessorySFSymbol: String {
        switch entry.config.kind {
        case "DuoyiTodoWidget":
            return "checkmark.circle"
        case "DuoyiFocusWidget":
            return "timer"
        case "DuoyiHabitWidget":
            return "flame"
        case "DuoyiCalendarWidget":
            return "calendar"
        case "DuoyiScheduleWidget":
            return "clock"
        case "DuoyiGoalWidget":
            return "target"
        case "DuoyiCourseWidget":
            return "book"
        case "DuoyiNoteWidget":
            return "square.and.pencil"
        case "DuoyiAnniversaryWidget":
            return "heart"
        case "DuoyiDiaryWidget":
            return "book.closed"
        default:
            return "app"
        }
    }

    private func isKnownFallback(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == entry.config.fallback {
            return true
        }
        switch entry.config.kind {
        case "DuoyiTodoWidget":
            return trimmed == "今天没有未完成待办" || trimmed == "No open tasks today"
        case "DuoyiFocusWidget":
            return trimmed == "25 分钟专注" || trimmed == "25-min focus"
        case "DuoyiHabitWidget":
            return trimmed == "今日习惯待打卡" || trimmed == "Habits to check in today"
        case "DuoyiCalendarWidget":
            return trimmed == "本月日期 · 今日已标记" || trimmed == "Month view · today is marked"
        case "DuoyiScheduleWidget":
            return trimmed == "今日没有日程" || trimmed == "No events today"
        case "DuoyiGoalWidget":
            return trimmed == "暂无进行中目标" || trimmed == "No active goals"
        case "DuoyiCourseWidget":
            return trimmed == "今日暂无课程" || trimmed == "No courses today"
        case "DuoyiNoteWidget":
            return trimmed == "暂无随手记" || trimmed == "No notes yet"
        case "DuoyiAnniversaryWidget":
            return trimmed == "暂无近期纪念日" || trimmed == "No upcoming anniversaries" || trimmed == "暂无纪念日"
        case "DuoyiDiaryWidget":
            return trimmed == "暂无日记" || trimmed == "No diary entries yet"
        default:
            return false
        }
    }

    private func formatMinutes(_ seconds: Int) -> String {
        let minutes = max(1, (seconds + 59) / 60)
        return entry.locale == .en ? "\(minutes) min" : "\(minutes)分"
    }

    private var quickURL: URL? {
        if entry.config.kind == "DuoyiHabitWidget" {
            let id = entry.habitQuickCheckId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                return URL(string: entry.config.quickActionLink)
            }
            var components = URLComponents(string: "duoyi://action/checkin_habit")
            components?.queryItems = [URLQueryItem(name: "id", value: id)]
            return entry.snapshot.actionURL(components)
        }
        return entry.snapshot.actionURL(URLComponents(string: entry.config.quickActionLink))
    }
}

private let todoConfig = DuoyiWidgetConfig(
    kind: "DuoyiTodoWidget",
    title: "今日待办",
    deepLink: "duoyi://todo",
    accent: .blue,
    primaryKey: "todo_top3_1",
    fallback: "今天没有未完成待办",
    rowKeys: ["todo_top3_2", "todo_top3_3"],
    quickActionTitle: "+ 添加",
    quickActionLink: "duoyi://action/quick_todo",
    titleEn: "Today's Tasks",
    fallbackEn: "No open tasks today",
    quickActionTitleEn: "+ Add"
)

private let focusConfig = DuoyiWidgetConfig(
    kind: "DuoyiFocusWidget",
    title: "专注",
    deepLink: "duoyi://focus",
    accent: .red,
    primaryKey: "next_focus_label",
    fallback: "25 分钟专注",
    rowKeys: ["focus_summary", "streak_summary"],
    quickActionTitle: "开始",
    quickActionLink: "duoyi://action/start_pomodoro",
    titleEn: "Focus",
    fallbackEn: "25-min focus",
    quickActionTitleEn: "Start"
)

private let habitConfig = DuoyiWidgetConfig(
    kind: "DuoyiHabitWidget",
    title: "习惯",
    deepLink: "duoyi://habit",
    accent: .green,
    primaryKey: "habit_summary",
    fallback: "今日习惯待打卡",
    rowKeys: ["habit_quick_check_label", "streak_summary"],
    quickActionTitle: "打卡",
    quickActionLink: "duoyi://habit",
    titleEn: "Habits",
    fallbackEn: "Habits to check in today",
    quickActionTitleEn: "Check In"
)

private let calendarConfig = DuoyiWidgetConfig(
    kind: "DuoyiCalendarWidget",
    title: "月历",
    deepLink: "duoyi://calendar",
    accent: .indigo,
    primaryKey: "calendar_month_summary",
    fallback: "本月日期 · 今日已标记",
    rowKeys: ["today_event_summary", "schedule_highlight_2"],
    quickActionTitle: "打开",
    quickActionLink: "duoyi://calendar",
    titleEn: "Calendar",
    fallbackEn: "Month view · today is marked",
    quickActionTitleEn: "Open"
)

private let scheduleConfig = DuoyiWidgetConfig(
    kind: "DuoyiScheduleWidget",
    title: "今日日程",
    deepLink: "duoyi://calendar",
    accent: .cyan,
    primaryKey: "today_event_summary",
    fallback: "今日没有日程",
    rowKeys: ["schedule_highlight_1", "schedule_highlight_2", "schedule_highlight_3"],
    quickActionTitle: "打开",
    quickActionLink: "duoyi://calendar",
    titleEn: "Today's Schedule",
    fallbackEn: "No events today",
    quickActionTitleEn: "Open"
)

private let goalConfig = DuoyiWidgetConfig(
    kind: "DuoyiGoalWidget",
    title: "目标",
    deepLink: "duoyi://goal",
    accent: .orange,
    primaryKey: "goal_highlight_1",
    fallback: "暂无进行中目标",
    rowKeys: ["goal_highlight_2", "goal_highlight_3"],
    quickActionTitle: "查看",
    quickActionLink: "duoyi://goal",
    titleEn: "Goals",
    fallbackEn: "No active goals",
    quickActionTitleEn: "View"
)

private let courseConfig = DuoyiWidgetConfig(
    kind: "DuoyiCourseWidget",
    title: "课程表",
    deepLink: "duoyi://course",
    accent: .yellow,
    primaryKey: "course_highlight_1",
    fallback: "今日暂无课程",
    rowKeys: ["course_highlight_2", "today_event_summary"],
    quickActionTitle: "课表",
    quickActionLink: "duoyi://course",
    titleEn: "Courses",
    fallbackEn: "No courses today",
    quickActionTitleEn: "Courses"
)

private let noteConfig = DuoyiWidgetConfig(
    kind: "DuoyiNoteWidget",
    title: "随手记",
    deepLink: "duoyi://note",
    accent: .purple,
    primaryKey: "note_highlight_1",
    fallback: "暂无随手记",
    rowKeys: ["note_highlight_2", "note_highlight_3"],
    quickActionTitle: "记录",
    quickActionLink: "duoyi://note",
    titleEn: "Quick Notes",
    fallbackEn: "No notes yet",
    quickActionTitleEn: "Note"
)

private let anniversaryConfig = DuoyiWidgetConfig(
    kind: "DuoyiAnniversaryWidget",
    title: "纪念日",
    deepLink: "duoyi://anniversary",
    accent: .pink,
    primaryKey: "anniversary_highlight_1",
    fallback: "暂无近期纪念日",
    rowKeys: ["anniversary_highlight_2", "memorial_highlight_1", "memorial_highlight_2", "memorial_highlight_3"],
    quickActionTitle: "查看",
    quickActionLink: "duoyi://anniversary",
    titleEn: "Anniversary",
    fallbackEn: "No upcoming anniversaries",
    quickActionTitleEn: "View"
)

private let diaryConfig = DuoyiWidgetConfig(
    kind: "DuoyiDiaryWidget",
    title: "日记",
    deepLink: "duoyi://diary",
    accent: .teal,
    primaryKey: "diary_highlight_1",
    fallback: "暂无日记",
    rowKeys: ["diary_highlight_2", "diary_highlight_3"],
    quickActionTitle: "写日记",
    quickActionLink: "duoyi://diary",
    titleEn: "Diary",
    fallbackEn: "No diary entries yet",
    quickActionTitleEn: "Write"
)

private struct DuoyiAnyWidget: Widget {
    let config: DuoyiWidgetConfig

    var body: some WidgetConfiguration {
        let locale = DuoyiWidgetLocale.resolve(UserDefaults(suiteName: appGroupId))
        let localizedConfig = config.localized(for: locale)
        return StaticConfiguration(kind: config.kind, provider: DuoyiWidgetProvider(config: config)) { entry in
            DuoyiWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(localizedConfig.title))
        .description(Text(localizedConfig.galleryDescription(for: locale)))
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOSApplicationExtension 15.0, *) {
            families.append(.systemExtraLarge)
        }
        if #available(iOSApplicationExtension 16.0, *) {
            families.append(contentsOf: [.accessoryInline, .accessoryCircular, .accessoryRectangular])
        }
        return families
    }
}

private extension View {
    @ViewBuilder
    func duoyiWidgetBackground(_ theme: DuoyiWidgetTheme) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                duoyiWidgetBackgroundView(theme)
            }
        } else {
            self.background(duoyiWidgetBackgroundView(theme))
        }
    }

    private func duoyiWidgetBackgroundView(_ theme: DuoyiWidgetTheme) -> some View {
        LinearGradient(
            colors: [theme.background, theme.surface, theme.accentEnd.opacity(0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

@main
struct DuoyiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DuoyiAnyWidget(config: todoConfig)
        DuoyiAnyWidget(config: focusConfig)
        DuoyiAnyWidget(config: habitConfig)
        DuoyiAnyWidget(config: calendarConfig)
        DuoyiAnyWidget(config: scheduleConfig)
        DuoyiAnyWidget(config: goalConfig)
        DuoyiAnyWidget(config: courseConfig)
        DuoyiAnyWidget(config: noteConfig)
        DuoyiAnyWidget(config: anniversaryConfig)
        DuoyiAnyWidget(config: diaryConfig)
    }
}
