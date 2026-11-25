import SwiftUI
import WidgetKit
import Foundation
import CoreFoundation
#if canImport(UIKit)
import UIKit
#endif

// BEGIN DUOYI_WIDGET_TIMER_CORE
// Foundation-only logic is exercised directly by the portable Swift verifier.
private enum DuoyiFocusTimerPhase: Equatable {
    case unavailable, idle
    case runningCountdown, runningCountUp
    case pausedCountdown, pausedCountUp
    case ended
}

private enum DuoyiFocusTimerDisplay: Equatable {
    case fallback
    case fixed(String)
    case countdown(Date)
    case countUp(Date, Date)
}

private struct DuoyiFocusTimerInput {
    let countUp: Bool
    let storedRunning: Bool
    let savedSeconds: Int64
    let totalSeconds: Int64
    let startedAtMillis: Int64
    let endsAtMillis: Int64

    init?(values: [String: Any]) {
        guard let countUp = Self.boolean(values["focus_timer_count_up"]),
              let running = Self.boolean(values["focus_timer_running"]),
              let saved = Self.integer(values["focus_timer_remaining_seconds"]),
              let total = Self.integer(values["focus_timer_total_seconds"]),
              let start = Self.integer(values["focus_timer_started_at_millis"]),
              let end = Self.integer(values["focus_timer_ends_at_millis"]),
              saved >= 0, total >= 0, start >= 0, end >= 0 else { return nil }
        self.countUp = countUp
        storedRunning = running
        savedSeconds = saved
        totalSeconds = total
        startedAtMillis = start
        endsAtMillis = end
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value else { return false }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        guard let raw = integer(number), raw == 0 || raw == 1 else { return nil }
        return raw == 1
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let value = value else { return 0 }
        if let text = value as? String {
            return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        // Preserve full-width integer NSNumber values before considering Double.
        if let exact = Int64(number.stringValue) { return exact }
        let raw = number.doubleValue
        guard raw.isFinite, let exact = Int64(exactly: raw),
              number.compare(NSNumber(value: exact)) == .orderedSame else { return nil }
        return exact
    }
}

private struct DuoyiFocusTimerState {
    static let countUpCapSeconds: Int64 = 86_400
    // Existing accessory formatting adds 59 before rounding to minutes.
    private static let safeDisplayLimit = Int64(Int.max - 59)

    let phase: DuoyiFocusTimerPhase
    let seconds: Int
    let totalSeconds: Int
    let startDate: Date?
    let endDate: Date?
    let capDate: Date?
    let hasFutureStart: Bool
    let isAtCountUpCap: Bool

    static let unavailable = DuoyiFocusTimerState(
        phase: .unavailable, seconds: 0, totalSeconds: 0,
        startDate: nil, endDate: nil, capDate: nil,
        hasFutureStart: false, isAtCountUpCap: false
    )

    var isRunning: Bool { phase == .runningCountdown || phase == .runningCountUp }

    func display(at date: Date) -> DuoyiFocusTimerDisplay {
        switch phase {
        case .unavailable, .idle:
            return .fallback
        case .runningCountdown:
            guard let end = endDate else { return .fixed(clockText) }
            let remaining = end.timeIntervalSince(date)
            if remaining <= 0 { return .fixed("00:00") }
            // A clock rollback must not display more than the saved duration.
            guard remaining.isFinite, remaining <= Double(totalSeconds) else {
                return .fixed(clockText)
            }
            return .countdown(end)
        case .runningCountUp:
            guard !hasFutureStart, !isAtCountUpCap,
                  let start = startDate, let cap = capDate else {
                return .fixed(clockText)
            }
            return .countUp(start, cap)
        case .pausedCountdown, .pausedCountUp, .ended:
            return .fixed(clockText)
        }
    }

    // Documented shared numeric clock formatting authority:
    // Digital countdown and count-up timers format with standard ASCII Western Arabic digits ('0'...'9')
    // and colon separators (e.g. "59:59", "100:59:59", "24:00:00").
    // Both conservative sample measurement and live SwiftUI Text rendering share this
    // fixed POSIX numeric locale (.environment(\.locale, DuoyiFocusTimerState.timerClockLocale))
    // so that measured glyph widths bound the rendered characters, while surrounding
    // status copy (e.g. focusStatusLabel) remains localized in the user's entry locale.
    static let timerClockLocale = Locale(identifier: "en_US_POSIX")

    static func supportsNumericClock(locale: Locale) -> Bool {
        let id = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if id == "en-us-posix" || id == "posix" || id.hasPrefix("en") || id.hasPrefix("zh") {
            return true
        }
        return false
    }

    func conservativeClockSample(at date: Date, locale: Locale = timerClockLocale) -> String? {
        guard date.timeIntervalSince1970.isFinite,
              date <= Date.distantFuture,
              date >= Date.distantPast,
              Self.supportsNumericClock(locale: locale) else {
            return nil
        }
        switch display(at: date) {
        case .fallback:
            return nil
        case .fixed(let clock):
            return clock
        case .countdown(let end):
            let remaining = end.timeIntervalSince(date)
            let maxSec = min(Int64(totalSeconds), max(0, Int64(ceil(remaining))))
            let hours = maxSec / 3600
            return hours > 0 ? "\(hours):59:59" : "59:59"
        case .countUp:
            return "24:59:59"
        }
    }

    private var clockText: String {
        func padded(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        let hours = seconds / 3600
        let minutes = (seconds / 60) % 60
        let tail = "\(padded(minutes)):\(padded(seconds % 60))"
        return hours > 0 ? "\(hours):\(tail)" : tail
    }

    func actionIntent(isDailyFresh: Bool) -> DuoyiFocusActionIntent {
        guard isDailyFresh else { return .open }
        switch phase {
        case .idle: return .start
        case .pausedCountdown, .pausedCountUp: return .resume
        default: return .open
        }
    }

    static func resolve(values: [String: Any], sessionPublished: Bool, at date: Date) -> DuoyiFocusTimerState {
        guard sessionPublished,
              let input = DuoyiFocusTimerInput(values: values),
              let nowMillis = milliseconds(date) else { return .unavailable }
        let total = Int(min(input.totalSeconds, safeDisplayLimit))
        if input.storedRunning {
            if input.countUp {
                guard let start = anchorDate(input.startedAtMillis) else { return .unavailable }
                let delta = nowMillis.subtractingReportingOverflow(input.startedAtMillis)
                guard !delta.overflow else { return .unavailable }
                let cap = start.addingTimeInterval(TimeInterval(countUpCapSeconds))
                let elapsed = date >= cap
                    ? countUpCapSeconds
                    : min(max(0, delta.partialValue / 1000), countUpCapSeconds)
                return DuoyiFocusTimerState(
                    phase: .runningCountUp, seconds: Int(elapsed), totalSeconds: total,
                    startDate: start, endDate: nil,
                    capDate: cap <= Date.distantFuture ? cap : nil,
                    hasFutureStart: date < start,
                    isAtCountUpCap: elapsed == countUpCapSeconds
                )
            }
            guard input.totalSeconds > 0,
                  let end = anchorDate(input.endsAtMillis) else { return .unavailable }
            // Compare Dates first: an entry created from this exact end anchor
            // must be ended even when Date-to-millisecond conversion rounds.
            if date >= end {
                return fixed(phase: .ended, seconds: 0, total: total)
            }
            let delta = input.endsAtMillis.subtractingReportingOverflow(nowMillis)
            guard !delta.overflow, delta.partialValue > 0 else { return .unavailable }
            let remaining = delta.partialValue / 1000 + (delta.partialValue % 1000 == 0 ? 0 : 1)
            return DuoyiFocusTimerState(
                phase: .runningCountdown,
                seconds: Int(min(remaining, input.totalSeconds, safeDisplayLimit)),
                totalSeconds: total, startDate: nil, endDate: end, capDate: nil,
                hasFutureStart: false, isAtCountUpCap: false
            )
        }
        if input.countUp {
            let elapsed = min(input.savedSeconds, countUpCapSeconds)
            return fixed(
                phase: input.savedSeconds == 0 ? .idle : .pausedCountUp,
                seconds: Int(elapsed), total: total,
                atCountUpCap: elapsed == countUpCapSeconds
            )
        }
        guard input.totalSeconds > 0,
              input.savedSeconds > 0,
              input.savedSeconds <= input.totalSeconds else { return .unavailable }
        return fixed(
            phase: input.savedSeconds == input.totalSeconds ? .idle : .pausedCountdown,
            seconds: Int(min(input.savedSeconds, safeDisplayLimit)), total: total
        )
    }

    private static func fixed(
        phase: DuoyiFocusTimerPhase, seconds: Int, total: Int, atCountUpCap: Bool = false
    ) -> DuoyiFocusTimerState {
        DuoyiFocusTimerState(
            phase: phase, seconds: seconds, totalSeconds: total,
            startDate: nil, endDate: nil, capDate: nil,
            hasFutureStart: false, isAtCountUpCap: atCountUpCap
        )
    }

    private static func milliseconds(_ date: Date) -> Int64? {
        let raw = date.timeIntervalSince1970 * 1000
        guard raw.isFinite else { return nil }
        return Int64(exactly: floor(raw))
    }

    private static func anchorDate(_ milliseconds: Int64) -> Date? {
        guard milliseconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        guard date <= Date.distantFuture else { return nil }
        return date
    }
}

private enum DuoyiFocusActionIntent: Equatable {
    case start, resume, open
}

private enum DuoyiFocusTimerTimeline {
    static func dates(now: Date, timer: DuoyiFocusTimerState, calendar: Calendar) -> [Date] {
        guard now.timeIntervalSince1970.isFinite else { return [now] }
        let horizon = now.addingTimeInterval(48 * 60 * 60)
        var dates = [now]
        func append(_ date: Date?) {
            guard let date = date, date > now, date <= horizon else { return }
            dates.append(date)
        }
        append(calendar.dateInterval(of: .day, for: now)?.end)
        // A saved UTC offset becomes stale at the known daylight-saving change.
        append(calendar.timeZone.nextDaylightSavingTimeTransition(after: now))
        if timer.phase == .runningCountdown { append(timer.endDate) }
        if timer.phase == .runningCountUp {
            if timer.hasFutureStart { append(timer.startDate) }
            if !timer.isAtCountUpCap { append(timer.capDate) }
        }
        return Array(Set(dates)).sorted()
    }
}
// END DUOYI_WIDGET_TIMER_CORE

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
// BEGIN DUOYI_WIDGET_SNAPSHOT_CORE
private struct DuoyiWidgetSnapshot {
    let day: String
    let utcOffsetMinutes: Int?
    let accountNonce: String

    static let empty = DuoyiWidgetSnapshot(day: "", utcOffsetMinutes: nil, accountNonce: "")

    init(values: [String: Any]) {
        day = values["widget_snapshot_day"] as? String ?? ""
        accountNonce = values["widget_account_nonce"] as? String ?? ""
        utcOffsetMinutes = Self.offset(values["widget_snapshot_utc_offset_minutes"])
    }

    private init(day: String, utcOffsetMinutes: Int?, accountNonce: String) {
        self.day = day
        self.utcOffsetMinutes = utcOffsetMinutes
        self.accountNonce = accountNonce
    }

    var hasPublishedSession: Bool {
        Self.isValidDay(day) && utcOffsetMinutes != nil &&
            !accountNonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func offset(_ value: Any?) -> Int? {
        let offset: Int
        if let text = value as? String {
            guard let exact = Int(text) else { return nil }
            offset = exact
        } else if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            if let exact = Int(number.stringValue) {
                offset = exact
            } else {
                let raw = number.doubleValue
                guard raw.isFinite, let exact = Int(exactly: raw),
                      number.compare(NSNumber(value: exact)) == .orderedSame else { return nil }
                offset = exact
            }
        } else {
            return nil
        }
        let seconds = offset.multipliedReportingOverflow(by: 60)
        guard !seconds.overflow, TimeZone(secondsFromGMT: seconds.partialValue) != nil else { return nil }
        return offset
    }

    private static func isValidDay(_ day: String) -> Bool {
        let bytes = Array(day.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return false }
        for index in [0, 1, 2, 3, 5, 6, 8, 9] {
            guard bytes[index] >= 48, bytes[index] <= 57 else { return false }
        }
        let fields = day.split(separator: "-")
        guard fields.count == 3,
              let year = Int(fields[0]), let month = Int(fields[1]), let dateDay = Int(fields[2]),
              year > 0, (1...12).contains(month), (1...31).contains(dateDay) else { return false }
        // Validate the same proleptic Gregorian civil dates as Flutter, without
        // Foundation's historical Gregorian cutover or date normalization.
        let isLeap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let monthDays = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return dateDay <= monthDays[month - 1]
    }

    func isFresh(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return isFresh(at: date, calendar: calendar)
    }

    func isFresh(at date: Date, calendar: Calendar) -> Bool {
        guard hasPublishedSession, date.timeIntervalSince1970.isFinite else { return false }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let fields = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let year = fields.year, let month = fields.month, let dateDay = fields.day else {
            return false
        }
        let localDay = String(format: "%04d-%02d-%02d", year, month, dateDay)
        return day == localDay &&
            utcOffsetMinutes == gregorian.timeZone.secondsFromGMT(for: date) / 60
    }

    func actionURL(_ components: URLComponents?) -> URL? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return actionURL(components, at: Date(), calendar: calendar)
    }

    func actionURL(_ components: URLComponents?, at date: Date, calendar: Calendar) -> URL? {
        guard var components = components else { return nil }
        guard components.scheme?.lowercased() == "duoyi" else { return components.url }
        let entityHosts = Set(["todo", "habit", "course", "note", "diary", "goal",
                               "anniversary", "countdown", "time-entry", "event", "pomodoro"])
        let host = components.host?.lowercased() ?? ""
        let isEntity = entityHosts.contains(host) &&
            components.percentEncodedPath.split(separator: "/").first != nil
        let queryItems = components.queryItems ?? []
        let datedItems = queryItems.filter { $0.name == "date" }
        let isDatedCalendar = host == "calendar" && !datedItems.isEmpty
        let bindingKeys = Set(["source", "widget_day", "widget_offset", "widget_account", "widget_delivery"])
        if isDatedCalendar {
            guard components.percentEncodedPath.isEmpty,
                  components.user == nil, components.password == nil,
                  components.port == nil, components.fragment == nil,
                  datedItems.count == 1, let selectedDay = datedItems.first?.value,
                  Self.isValidDay(selectedDay),
                  queryItems.allSatisfy({ $0.name == "date" || bindingKeys.contains($0.name) }) else { return nil }
        }
        guard host == "action" || isEntity || isDatedCalendar else { return components.url }
        // Flutter dispatches the first decoded path segment, including when
        // extra trailing segments are present. Decode after splitting so an
        // encoded slash does not create a different action.
        let encodedPath = components.percentEncodedPath
        let path = encodedPath.hasPrefix("/") ? String(encodedPath.dropFirst()) : encodedPath
        let encodedAction = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let action = encodedAction.removingPercentEncoding ?? ""
        let hasQuickText = components.queryItems?.contains {
            $0.name == "text" && !($0.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        // Opening textless quick_todo and requesting refresh are recoverable navigation.
        let mutates = isEntity || ["complete_todo", "checkin_habit", "start_pomodoro"].contains(action) ||
            action == "toggle_pomodoro" ||
            ["stop_pomodoro", "pause_pomodoro", "finish_pomodoro",
             "quick_goal", "quick_schedule", "quick_note", "quick_diary"].contains(action) ||
            (action == "quick_todo" && hasQuickText)
        // A selected calendar date also belongs to the snapshot's account/day;
        // stale cells must fall back through the enclosing calendar root URL.
        guard mutates || isDatedCalendar else { return components.url }
        guard isFresh(at: date, calendar: calendar), let offset = utcOffsetMinutes else { return nil }
        var items = queryItems.filter { !bindingKeys.contains($0.name) }
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
// END DUOYI_WIDGET_SNAPSHOT_CORE

// BEGIN DUOYI_WIDGET_DISPLAY_CORE
// Foundation-only logic is exercised directly by the portable Swift verifier.

struct DuoyiAnniversaryRawSlot: Equatable {
    let sourceKey: String
    let text: String?
    let target: String?
}

struct DuoyiAnniversaryItem: Equatable {
    let sourceKey: String
    let text: String
    let target: String
    let identity: String?
}

struct DuoyiMonthCell: Equatable {
    let dayNumber: Int
    let isToday: Bool
    let text: String
    let dateKey: String?

    init(dayNumber: Int, isToday: Bool, text: String, dateKey: String? = nil) {
        self.dayNumber = dayNumber
        self.isToday = isToday
        self.text = text
        self.dateKey = dateKey
    }

    var target: String? {
        dateKey.map { "duoyi://calendar?date=\($0)" }
    }
}

struct DuoyiMonthGridModel: Equatable {
    let year: Int
    let month: Int
    let todayDay: Int
    let firstWeekdayOffset: Int
    let daysInMonth: Int
    let cells: [DuoyiMonthCell]
    let weekdayHeaders: [String]
    let monthTitle: String
}

struct DuoyiCalendarEventSummaryResult: Equatable {
    let summary: String?
    let target: String
    let isReal: Bool
}

struct DuoyiCalendarAccessoryDateDisplay: Equatable {
    let inline: String
    let short: String
    let rectangular: String
}

enum DuoyiWidgetDisplayCore {
    static func isKnownAnniversaryEmptyPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.hasPrefix("· ") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        return clean == "暂无近期纪念日" ||
            clean == "No upcoming anniversaries" ||
            clean == "暂无纪念日" ||
            clean == "纪念日 · 暂无近期纪念日" ||
            clean == "Anniversaries · No upcoming anniversaries"
    }

    static func isBareBulletOrEmpty(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let stripped = trimmed.replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            return byte - 0x30
        case 0x41...0x46:
            return byte - 0x41 + 10
        case 0x61...0x66:
            return byte - 0x61 + 10
        default:
            return nil
        }
    }

    static func hasIllegalUriCharacters(_ s: String) -> Bool {
        let utf8 = Array(s.utf8)
        var i = 0
        while i < utf8.count {
            let byte = utf8[i]
            if byte <= 0x20 || byte == 0x7F || byte == 0x5C || // <= space, DEL, '\'
               byte == 0x22 || // '"'
               byte == 0x3C || byte == 0x3E || // '<', '>'
               byte == 0x7B || byte == 0x7D || // '{', '}'
               byte == 0x7C || // '|'
               byte == 0x5E || // '^'
               byte == 0x60 || // '`'
               byte == 0x5B || byte == 0x5D || // '[', ']'
               byte == 0x3F || byte == 0x23 { // '?', '#'
                return true
            }
            if byte == 0x25 { // '%'
                if i + 2 >= utf8.count {
                    return true
                }
                guard hexValue(utf8[i + 1]) != nil, hexValue(utf8[i + 2]) != nil else {
                    return true
                }
                i += 3
            } else {
                i += 1
            }
        }
        return false
    }

    static func strictPercentDecode(_ s: String) -> String? {
        var bytes = [UInt8]()
        bytes.reserveCapacity(s.utf8.count)
        var iterator = s.utf8.makeIterator()
        while let byte = iterator.next() {
            if byte == 0x25 { // '%'
                guard let h1 = iterator.next(),
                      let h2 = iterator.next(),
                      let d1 = hexValue(h1),
                      let d2 = hexValue(h2) else {
                    return nil
                }
                bytes.append((d1 << 4) | d2)
            } else {
                // In URL path, '+' is literal '+', not form-urlencoded space!
                bytes.append(byte)
            }
        }
        var string = ""
        var utf8Iterator = bytes.makeIterator()
        var utf8Decoder = UTF8()
        while true {
            switch utf8Decoder.decode(&utf8Iterator) {
            case .scalarValue(let scalar):
                string.unicodeScalars.append(scalar)
            case .emptyInput:
                return string
            case .error:
                return nil
            }
        }
    }

    static func encodePathSegment(_ raw: String) -> String {
        var result = ""
        for byte in raw.utf8 {
            if (byte >= 0x41 && byte <= 0x5A) || // A-Z
               (byte >= 0x61 && byte <= 0x7A) || // a-z
               (byte >= 0x30 && byte <= 0x39) || // 0-9
               byte == 0x2D || byte == 0x5F ||   // '-', '_'
               byte == 0x2E || byte == 0x7E {     // '.', '~'
                result.append(Character(UnicodeScalar(byte)))
            } else {
                result.append(String(format: "%%%02X", byte))
            }
        }
        return result
    }

    static func parseAnniversaryTarget(_ rawTarget: String?) -> (target: String, identity: String?) {
        guard let raw = rawTarget?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ("duoyi://anniversary", nil)
        }
        if raw.lowercased().hasPrefix("duoyi://") {
            if hasIllegalUriCharacters(raw) || raw.hasSuffix("/") {
                return ("duoyi://anniversary", nil)
            }
            let afterScheme = String(raw.dropFirst("duoyi://".count))
            let slashIndex = afterScheme.firstIndex(of: "/")
            let rawAuthority = slashIndex != nil ? String(afterScheme[..<slashIndex!]) : afterScheme
            if rawAuthority.isEmpty || rawAuthority.contains("@") || rawAuthority.contains(":") {
                return ("duoyi://anniversary", nil)
            }
            guard let components = URLComponents(string: raw) else {
                return ("duoyi://anniversary", nil)
            }
            guard components.scheme?.lowercased() == "duoyi" else {
                return ("duoyi://anniversary", nil)
            }
            guard components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.query == nil,
                  components.fragment == nil else {
                return ("duoyi://anniversary", nil)
            }
            guard let host = components.host?.lowercased(), host == "anniversary" else {
                return ("duoyi://anniversary", nil)
            }
            let path = components.percentEncodedPath
            guard path.hasPrefix("/"), path.count > 1 else {
                return ("duoyi://anniversary", nil)
            }
            let segment = String(path.dropFirst())
            if segment.contains("/") {
                return ("duoyi://anniversary", nil)
            }
            guard let decoded = strictPercentDecode(segment),
                  !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ("duoyi://anniversary", nil)
            }
            return ("duoyi://anniversary/\(segment)", decoded)
        } else {
            let isForeignUri: Bool = {
                if raw.contains("://") || raw.hasPrefix("//") { return true }
                let lower = raw.lowercased()
                if lower.hasPrefix("mailto:") || lower.hasPrefix("tel:") ||
                   lower.hasPrefix("sms:") || lower.hasPrefix("data:") ||
                   lower.hasPrefix("javascript:") || lower.hasPrefix("urn:") ||
                   lower.hasPrefix("file:") {
                    return true
                }
                return false
            }()
            if isForeignUri {
                return ("duoyi://anniversary", nil)
            }
            let encoded = encodePathSegment(raw)
            return ("duoyi://anniversary/\(encoded)", raw)
        }
    }

    static func resolveAnniversaryItems(
        slots: [DuoyiAnniversaryRawSlot],
        isFresh: Bool,
        isZh: Bool
    ) -> [DuoyiAnniversaryItem] {
        if !isFresh {
            let staleText = isZh ? "日期数据待刷新" : "Dates pending refresh"
            return [
                DuoyiAnniversaryItem(
                    sourceKey: "anniversary_highlight_1",
                    text: staleText,
                    target: "duoyi://anniversary",
                    identity: nil
                )
            ]
        }

        var seenIdentities = Set<[UInt8]>()
        var result: [DuoyiAnniversaryItem] = []

        for slot in slots {
            guard let rawText = slot.text,
                  !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let rawTarget = (slot.target ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if rawTarget.isEmpty && (isBareBulletOrEmpty(rawText) || isKnownAnniversaryEmptyPlaceholder(rawText)) {
                continue
            }
            let (targetUrl, identity) = parseAnniversaryTarget(slot.target)
            if let id = identity {
                let identityBytes = Array(id.utf8)
                if seenIdentities.contains(identityBytes) {
                    continue
                }
                seenIdentities.insert(identityBytes)
            }
            result.append(
                DuoyiAnniversaryItem(
                    sourceKey: slot.sourceKey,
                    text: rawText,
                    target: targetUrl,
                    identity: identity
                )
            )
        }

        if result.isEmpty {
            let emptyText = isZh ? "· 暂无近期纪念日" : "· No upcoming anniversaries"
            return [
                DuoyiAnniversaryItem(
                    sourceKey: "anniversary_highlight_1",
                    text: emptyText,
                    target: "duoyi://anniversary",
                    identity: nil
                )
            ]
        }

        return result
    }

    static func resolveCalendarEventTarget(_ rawTarget: String?) -> String {
        guard let raw = rawTarget?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "duoyi://calendar"
        }
        guard raw.lowercased().hasPrefix("duoyi://") else {
            return "duoyi://calendar"
        }
        if hasIllegalUriCharacters(raw) || raw.hasSuffix("/") {
            return "duoyi://calendar"
        }
        let afterScheme = String(raw.dropFirst("duoyi://".count))
        let slashIndex = afterScheme.firstIndex(of: "/")
        let rawAuthority = slashIndex != nil ? String(afterScheme[..<slashIndex!]) : afterScheme
        if rawAuthority.isEmpty || rawAuthority.contains("@") || rawAuthority.contains(":") {
            return "duoyi://calendar"
        }
        guard let components = URLComponents(string: raw) else {
            return "duoyi://calendar"
        }
        guard components.scheme?.lowercased() == "duoyi" else {
            return "duoyi://calendar"
        }
        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            return "duoyi://calendar"
        }
        guard let host = components.host?.lowercased() else {
            return "duoyi://calendar"
        }

        if host == "calendar" || host == "focus" {
            let path = components.percentEncodedPath
            return path.isEmpty ? raw : "duoyi://calendar"
        }

        let supportedMutationHosts: Set<String> = [
            "todo", "habit", "anniversary", "course", "diary", "goal", "countdown", "time-entry", "event", "pomodoro"
        ]
        if supportedMutationHosts.contains(host) {
            let path = components.percentEncodedPath
            guard path.hasPrefix("/"), path.count > 1 else {
                return "duoyi://calendar"
            }
            let segment = String(path.dropFirst())
            if segment.contains("/") {
                return "duoyi://calendar"
            }
            guard let decoded = strictPercentDecode(segment),
                  !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "duoyi://calendar"
            }
            return raw
        }
        return "duoyi://calendar"
    }

    static func calendarEventSummary(raw: String?, isZh: Bool) -> String? {
        guard let raw = raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.hasPrefix("· ") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        if clean == "今日没有日程" || clean == "No schedule today" || clean == "No events today" ||
            clean == "今天暂无日程" || clean == "今日日程" || clean == "Today's schedule" || clean == "Today’s schedule" {
            return isZh ? "今日没有日程" : "No events today"
        }
        return raw
    }

    static func resolveCalendarSummaryAndTarget(
        rawSummary: String?,
        rawSchedule1Id: String?,
        isFresh: Bool,
        isZh: Bool
    ) -> DuoyiCalendarEventSummaryResult {
        if !isFresh {
            let staleText = isZh ? "今日数据待刷新" : "Today’s data pending refresh"
            return DuoyiCalendarEventSummaryResult(
                summary: staleText,
                target: "duoyi://calendar",
                isReal: false
            )
        }

        guard let raw = rawSummary, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return DuoyiCalendarEventSummaryResult(
                summary: nil,
                target: "duoyi://calendar",
                isReal: false
            )
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.hasPrefix("· ") ? String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        let isNoEventsPlaceholder = clean == "今日没有日程" ||
            clean == "No schedule today" ||
            clean == "No events today" ||
            clean == "今天暂无日程" ||
            clean == "今日日程" ||
            clean == "Today's schedule" ||
            clean == "Today’s schedule"

        if isNoEventsPlaceholder {
            let emptyText = isZh ? "今日没有日程" : "No events today"
            return DuoyiCalendarEventSummaryResult(
                summary: emptyText,
                target: "duoyi://calendar",
                isReal: false
            )
        }

        let target = resolveCalendarEventTarget(rawSchedule1Id)
        return DuoyiCalendarEventSummaryResult(
            summary: raw,
            target: target,
            isReal: true
        )
    }

    static func buildMonthGrid(
        anchorDate: Date,
        timeZone: TimeZone,
        isZh: Bool,
        firstDayOfWeek: Int = 1
    ) -> DuoyiMonthGridModel {
        let seconds = anchorDate.timeIntervalSince1970
        guard seconds.isFinite else {
            return unavailableMonthGrid(isZh: isZh, firstDayOfWeek: firstDayOfWeek)
        }
        let localSeconds = seconds + Double(timeZone.secondsFromGMT(for: anchorDate))
        // Floor before converting: a negative fractional epoch day belongs to
        // the previous day. Foundation calendars use a historical cutover.
        let ordinal = floor(localSeconds / 86_400) + Double(daysBeforeYear(1970))
        guard ordinal.isFinite, ordinal >= 0, ordinal < Double(daysBeforeYear(10000)) else {
            return unavailableMonthGrid(isZh: isZh, firstDayOfWeek: firstDayOfWeek)
        }

        let dayOrdinal = Int(ordinal)
        var year = 1
        var upperYear = 10000
        while year + 1 < upperYear {
            let candidate = year + (upperYear - year) / 2
            if daysBeforeYear(candidate) <= dayOrdinal {
                year = candidate
            } else {
                upperYear = candidate
            }
        }
        let monthLengths = gregorianMonthLengths(year: year)
        var remainingDays = dayOrdinal - daysBeforeYear(year)
        var month = 1
        while remainingDays >= monthLengths[month - 1] {
            remainingDays -= monthLengths[month - 1]
            month += 1
        }
        return buildMonthGrid(year: year, month: month, todayDay: remainingDays + 1, isZh: isZh, firstDayOfWeek: firstDayOfWeek)
            ?? unavailableMonthGrid(isZh: isZh, firstDayOfWeek: firstDayOfWeek)
    }

    static func buildMonthGrid(
        year: Int,
        month: Int,
        todayDay: Int,
        isZh: Bool,
        firstDayOfWeek: Int = 1
    ) -> DuoyiMonthGridModel? {
        guard (1...9999).contains(year), (1...12).contains(month) else {
            return nil
        }
        let monthLengths = gregorianMonthLengths(year: year)
        let daysInMonth = monthLengths[month - 1]
        // Proleptic Gregorian 0001-01-01 was Monday.
        let first = normalizeFirstDayOfWeek(firstDayOfWeek)
        let monthFirstISO = (daysBeforeYear(year) + monthLengths.prefix(month - 1).reduce(0, +)) % 7 + 1
        let firstWeekdayOffset = (monthFirstISO - first + 7) % 7

        var cells: [DuoyiMonthCell] = []
        cells.reserveCapacity(42)

        for index in 0..<42 {
            if index < firstWeekdayOffset || index >= firstWeekdayOffset + daysInMonth {
                cells.append(DuoyiMonthCell(dayNumber: 0, isToday: false, text: "  "))
            } else {
                let day = index - firstWeekdayOffset + 1
                let isToday = (day == todayDay)
                let text = day < 10 ? " \(day)" : "\(day)"
                let dateKey = String(
                    format: "%04d-%02d-%02d",
                    locale: Locale(identifier: "en_US_POSIX"),
                    year, month, day
                )
                cells.append(DuoyiMonthCell(dayNumber: day, isToday: isToday, text: text, dateKey: dateKey))
            }
        }

        let monthTitle: String
        if isZh {
            monthTitle = "\(year)年\(month)月"
        } else {
            let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            monthTitle = "\(monthNames[month - 1]) \(year)"
        }

        return DuoyiMonthGridModel(
            year: year,
            month: month,
            todayDay: todayDay,
            firstWeekdayOffset: firstWeekdayOffset,
            daysInMonth: daysInMonth,
            cells: cells,
            weekdayHeaders: calendarWeekdayHeaders(isZh: isZh, firstDayOfWeek: firstDayOfWeek),
            monthTitle: monthTitle
        )
    }

    private static func daysBeforeYear(_ year: Int) -> Int {
        let previous = year - 1
        return 365 * previous + previous / 4 - previous / 100 + previous / 400
    }

    private static func gregorianMonthLengths(year: Int) -> [Int] {
        let isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    }

    static func normalizeFirstDayOfWeek(_ value: Int) -> Int {
        (1...7).contains(value) ? value : 1
    }

    // HomeWidget writes integers; never interpret Bool, floating or text values as a weekday.
    static func resolveFirstDayOfWeek(_ value: Any?) -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)),
              let exact = Int(number.stringValue), (1...7).contains(exact) else { return 1 }
        return exact
    }

    static func calendarWeekdayHeaders(isZh: Bool, firstDayOfWeek: Int = 1, full: Bool = false) -> [String] {
        let first = normalizeFirstDayOfWeek(firstDayOfWeek)
        let labels: [String]
        if isZh {
            labels = full ? ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"] : ["一", "二", "三", "四", "五", "六", "日"]
        } else {
            labels = full ? ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        }
        return (0..<7).map { labels[(first - 1 + $0) % 7] }
    }

    private static func unavailableMonthGrid(isZh: Bool, firstDayOfWeek: Int = 1) -> DuoyiMonthGridModel {
        DuoyiMonthGridModel(
            year: 0,
            month: 0,
            todayDay: 0,
            firstWeekdayOffset: 0,
            daysInMonth: 0,
            cells: Array(repeating: DuoyiMonthCell(dayNumber: 0, isToday: false, text: "  "), count: 42),
            weekdayHeaders: calendarWeekdayHeaders(isZh: isZh, firstDayOfWeek: firstDayOfWeek),
            monthTitle: isZh ? "日期不可用" : "Calendar unavailable"
        )
    }

    static func unavailableCalendarAccessoryDates(isZh: Bool) -> DuoyiCalendarAccessoryDateDisplay {
        DuoyiCalendarAccessoryDateDisplay(
            inline: isZh ? "本月日期 · 今日已标记" : "Month view · today is marked",
            short: isZh ? "暂无" : "None",
            rectangular: isZh ? "本月日期 · 今日已标记" : "Month view · today is marked"
        )
    }

    static func calendarAccessoryDates(
        year: Int,
        month: Int,
        day: Int,
        isZh: Bool
    ) -> DuoyiCalendarAccessoryDateDisplay? {
        guard (1...9999).contains(year), (1...12).contains(month) else {
            return nil
        }
        let monthLengths = gregorianMonthLengths(year: year)
        guard (1...monthLengths[month - 1]).contains(day) else {
            return nil
        }
        let dayOrdinal = daysBeforeYear(year) + monthLengths.prefix(month - 1).reduce(0, +) + (day - 1)
        let weekdayISO = (dayOrdinal % 7) + 1
        let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let shortText = "\(day)"
        if isZh {
            let weekdaysZh = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
            let inlineText = "\(month)月\(day)日"
            let rectangularText = "\(inlineText) · \(weekdaysZh[weekdayISO - 1])"
            return DuoyiCalendarAccessoryDateDisplay(
                inline: inlineText,
                short: shortText,
                rectangular: rectangularText
            )
        } else {
            let weekdaysEn = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            let inlineText = "\(monthNames[month - 1]) \(day)"
            let rectangularText = "\(inlineText) · \(weekdaysEn[weekdayISO - 1])"
            return DuoyiCalendarAccessoryDateDisplay(
                inline: inlineText,
                short: shortText,
                rectangular: rectangularText
            )
        }
    }

    static func calendarAccessoryDates(
        grid: DuoyiMonthGridModel? = nil,
        anchorDate: Date? = nil,
        timeZone: TimeZone = .current,
        isZh: Bool
    ) -> DuoyiCalendarAccessoryDateDisplay {
        if let grid = grid,
           let formatted = calendarAccessoryDates(year: grid.year, month: grid.month, day: grid.todayDay, isZh: isZh) {
            return formatted
        }
        if let anchor = anchorDate {
            let grid = buildMonthGrid(anchorDate: anchor, timeZone: timeZone, isZh: isZh)
            if let formatted = calendarAccessoryDates(year: grid.year, month: grid.month, day: grid.todayDay, isZh: isZh) {
                return formatted
            }
        }
        return unavailableCalendarAccessoryDates(isZh: isZh)
    }

    static func calendarAccessoryDates(
        anchorDate: Date,
        timeZone: TimeZone,
        isZh: Bool
    ) -> DuoyiCalendarAccessoryDateDisplay {
        calendarAccessoryDates(grid: nil, anchorDate: anchorDate, timeZone: timeZone, isZh: isZh)
    }

    static func cellAccessibilityLabel(
        year: Int,
        month: Int,
        day: Int,
        isToday: Bool,
        isZh: Bool
    ) -> String {
        if isZh {
            let base = "\(year)年\(month)月\(day)日"
            return isToday ? "\(base)，今天" : base
        } else {
            let monthNames = [
                "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December"
            ]
            let mName = (1...12).contains(month) ? monthNames[month - 1] : "\(month)"
            let base = "\(mName) \(day), \(year)"
            return isToday ? "Today, \(base)" : base
        }
    }

    static func budgetedVisibleWeekRange(
        familyKind: String,
        displayMode: String,
        currentWeek: Int,
        totalWeeks: Int = 6,
        hasEventSummary: Bool = false,
        availableHeight: Double = 0,
        monthTitleHeight: Double = 16,
        weekdayHeaderHeight: Double = 14,
        eventSummaryHeight: Double = 16,
        cellHeight: Double = 15,
        rowSpacing: Double = 2,
        contentSpacing: Double = 4
    ) -> ClosedRange<Int> {
        let maxWeekIndex = max(0, totalWeeks - 1)
        let clampedCurrent = min(max(0, currentWeek), maxWeekIndex)

        let maxAllowedWeeks: Int = {
            if displayMode == "compact" {
                return 1
            }
            switch familyKind {
            case "systemSmall":
                if hasEventSummary { return 1 }
                return displayMode == "detailed" ? 3 : 2
            case "systemMedium":
                if displayMode == "compact" { return 1 }
                if displayMode == "detailed" {
                    return hasEventSummary ? 2 : 3
                }
                return hasEventSummary ? 2 : 2
            default: // systemLarge, systemExtraLarge
                if displayMode == "compact" { return 1 }
                return totalWeeks
            }
        }()

        let targetWeeks: Int
        if availableHeight > 0 {
            var overhead = monthTitleHeight + weekdayHeaderHeight + (2 * contentSpacing)
            if hasEventSummary {
                overhead += eventSummaryHeight + contentSpacing
            }
            let remainingForGrid = availableHeight - overhead
            if remainingForGrid < cellHeight {
                targetWeeks = 1
            } else {
                let pitch = cellHeight + rowSpacing
                let fitting = Int((remainingForGrid + rowSpacing) / pitch)
                let fittingClamped = max(1, min(fitting, totalWeeks))
                targetWeeks = min(fittingClamped, maxAllowedWeeks)
            }
        } else {
            targetWeeks = maxAllowedWeeks
        }

        if targetWeeks >= totalWeeks {
            return 0...maxWeekIndex
        }
        if targetWeeks <= 1 {
            return clampedCurrent...clampedCurrent
        }

        var start = max(0, clampedCurrent - (targetWeeks - 1) / 2)
        var end = start + targetWeeks - 1
        if end > maxWeekIndex {
            end = maxWeekIndex
            start = max(0, end - targetWeeks + 1)
        }
        return start...end
    }

    // Publication values are non-negative int32s; malformed values stay unavailable.
    static func decodeTodoCount(_ raw: Any?) -> Int? {
        guard let raw = raw, !(raw is String),
              let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"].contains(String(cString: number.objCType)),
              let value = Int64(number.stringValue),
              (0...2_147_483_647).contains(value),
              number.compare(NSNumber(value: value)) == .orderedSame else {
            return nil
        }
        return Int(value)
    }

    static func todoCountLabel(_ count: Int, isZh: Bool) -> String {
        isZh ? "\(count) 项" : (count == 1 ? "1 task" : "\(count) tasks")
    }
    private static let goalPercentRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#,
        options: []
    )

    static func extractGoalProgressPercent(_ raw: String?) -> Int? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let regex = goalPercentRegex else {
            return nil
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: raw),
              let parsed = Double(raw[valueRange]) else {
            return nil
        }
        let rounded = Int(parsed.rounded())
        return min(max(rounded, 0), 100)
    }

    static func formattedDateKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let grid = buildMonthGrid(anchorDate: date, timeZone: timeZone, isZh: true)
        guard grid.year > 0, grid.month > 0, grid.todayDay > 0 else { return "" }
        return String(
            format: "%04d-%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            grid.year, grid.month, grid.todayDay
        )
    }
}
/// Shared ARGB decoding keeps invalid stored colors on their own role fallback.
private enum DuoyiWidgetThemeColorCore {
    static func parse(_ raw: String) -> UInt32? {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        let digits = clean.utf8
        guard (digits.count == 6 || digits.count == 8),
              digits.allSatisfy({
                  ($0 >= 48 && $0 <= 57) ||
                  ($0 >= 65 && $0 <= 70) ||
                  ($0 >= 97 && $0 <= 102)
              }),
              let value = UInt32(clean, radix: 16) else { return nil }
        return digits.count == 6 ? value | 0xFF000000 : value
    }

    static func resolve(_ raw: Any?, fallback: String) -> UInt32 {
        if let text = raw as? String, let value = parse(text) { return value }
        return parse(fallback) ?? 0xFF0066D6
    }

    static func contrast(_ foreground: UInt32, _ background: UInt32) -> Double {
        let alpha = Double((foreground >> 24) & 255) / 255
        func luminance(_ color: UInt32, alpha: Double) -> Double {
            func linear(_ shift: UInt32) -> Double {
                let channel = (Double((color >> shift) & 255) * alpha +
                    Double((background >> shift) & 255) * (1 - alpha)) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
        }
        let front = luminance(foreground, alpha: alpha)
        let back = luminance(background, alpha: 1)
        return (max(front, back) + 0.05) / (min(front, back) + 0.05)
    }

    static func readable(_ preferred: UInt32, backgrounds: [UInt32]) -> UInt32 {
        guard !backgrounds.isEmpty else { return preferred }
        func minimumContrast(_ color: UInt32) -> Double {
            backgrounds.map { contrast(color, $0) }.min() ?? 0
        }
        if minimumContrast(preferred) >= 4.5 { return preferred }
        return minimumContrast(0xFF000000) >= minimumContrast(0xFFFFFFFF) ? 0xFF000000 : 0xFFFFFFFF
    }

}

enum DuoyiWidgetTypographyLayoutCore {
    struct RowPlan {
        let showsPrimary: Bool
        let visibleSecondaryIndices: [Int]
        let showsFooter: Bool
        let usesFallback: Bool
        let usedHeight: Double
    }

    struct CalendarPlan {
        let visibleWeeks: [Int]
        let showsDateFallback: Bool
        let showsEventSummary: Bool
        let usedHeight: Double
    }

    static func rows(
        familyKind: String,
        displayMode: String,
        primaryKind: String,
        availableWidth: Double,
        availableHeight: Double,
        headerHeight: Double,
        primaryHeight: Double,
        secondaryHeights: [Double],
        contentSpacing: Double,
        secondarySpacing: Double,
        footerLabelWidths: [Double],
        footerHeight: Double,
        footerHorizontalPadding: Double,
        footerSpacing: Double,
        fallbackHeight: Double
    ) -> RowPlan? {
        guard availableWidth.isFinite, availableWidth >= 0,
              availableHeight.isFinite, availableHeight >= 0,
              headerHeight.isFinite, headerHeight >= 0,
              primaryHeight.isFinite, primaryHeight >= 0,
              secondaryHeights.allSatisfy({ $0.isFinite && $0 >= 0 }),
              contentSpacing.isFinite, contentSpacing >= 0,
              secondarySpacing.isFinite, secondarySpacing >= 0,
              footerLabelWidths.count == 4,
              footerLabelWidths.allSatisfy({ $0.isFinite && $0 >= 0 }),
              footerHeight.isFinite, footerHeight >= 0,
              footerHorizontalPadding.isFinite, footerHorizontalPadding >= 0,
              footerSpacing.isFinite, footerSpacing >= 0,
              fallbackHeight.isFinite, fallbackHeight >= 0 else {
            return nil
        }

        let fallbackUsedHeight = availableHeight >= fallbackHeight ? fallbackHeight : 0.0

        guard availableWidth > 0, availableHeight > 0 else {
            return RowPlan(
                showsPrimary: false,
                visibleSecondaryIndices: [],
                showsFooter: false,
                usesFallback: true,
                usedHeight: fallbackUsedHeight
            )
        }

        let primaryBlockHeight = headerHeight + contentSpacing + primaryHeight
        guard primaryBlockHeight <= availableHeight else {
            return RowPlan(
                showsPrimary: false,
                visibleSecondaryIndices: [],
                showsFooter: false,
                usesFallback: true,
                usedHeight: fallbackUsedHeight
            )
        }

        var usedHeight = primaryBlockHeight

        let maxSecondaryLimit: Int = {
            if primaryKind == "DuoyiTodoWidget" {
                switch familyKind {
                case "systemSmall":
                    return 0
                case "systemMedium":
                    return displayMode == "compact" ? 1 : 2
                default:
                    return displayMode == "compact" ? 2 : 2
                }
            } else {
                if familyKind == "systemSmall" && [
                    "DuoyiNoteWidget", "DuoyiGoalWidget", "DuoyiDiaryWidget",
                    "DuoyiAnniversaryWidget", "DuoyiCourseWidget", "DuoyiScheduleWidget"
                ].contains(primaryKind) {
                    return 0
                }
                switch familyKind {
                case "systemSmall":
                    return displayMode == "detailed" ? 2 : 1
                case "systemMedium":
                    return displayMode == "compact" ? 2 : 3
                default:
                    return displayMode == "compact" ? 3 : 5
                }
            }
        }()

        let candidateCount = min(maxSecondaryLimit, secondaryHeights.count)
        var admittedIndices: [Int] = []
        for i in 0..<candidateCount {
            let rowCost = secondaryHeights[i] + secondarySpacing
            if usedHeight + rowCost <= availableHeight {
                admittedIndices.append(i)
                usedHeight += rowCost
            } else {
                break
            }
        }

        var showsFooter = false
        if familyKind != "systemSmall" {
            let maxFooterCellWidth = (availableWidth - 2 * footerHorizontalPadding - 3 * footerSpacing) / 4.0
            if maxFooterCellWidth > 0 && footerLabelWidths.allSatisfy({ $0 <= maxFooterCellWidth }) {
                let footerCost = contentSpacing + footerHeight
                if usedHeight + footerCost <= availableHeight {
                    showsFooter = true
                    usedHeight += footerCost
                }
            }
        }

        return RowPlan(
            showsPrimary: true,
            visibleSecondaryIndices: admittedIndices,
            showsFooter: showsFooter,
            usesFallback: false,
            usedHeight: usedHeight
        )
    }

    static func calendar(
        familyKind: String,
        displayMode: String,
        currentWeek: Int,
        totalWeeks: Int,
        availableWidth: Double,
        availableHeight: Double,
        monthTitleHeight: Double,
        weekdayHeaderHeight: Double,
        eventSummaryHeight: Double,
        hasEventSummary: Bool,
        cellHeight: Double,
        maximumCellWidth: Double,
        rowSpacing: Double,
        contentSpacing: Double,
        fallbackHeight: Double
    ) -> CalendarPlan? {
        guard availableWidth.isFinite, availableWidth >= 0,
              availableHeight.isFinite, availableHeight >= 0,
              monthTitleHeight.isFinite, monthTitleHeight >= 0,
              weekdayHeaderHeight.isFinite, weekdayHeaderHeight >= 0,
              eventSummaryHeight.isFinite, eventSummaryHeight >= 0,
              cellHeight.isFinite, cellHeight > 0,
              maximumCellWidth.isFinite, maximumCellWidth >= 0,
              rowSpacing.isFinite, rowSpacing >= 0,
              contentSpacing.isFinite, contentSpacing >= 0,
              fallbackHeight.isFinite, fallbackHeight >= 0,
              totalWeeks >= 1, totalWeeks <= 6 else {
            return nil
        }

        let fallbackUsedHeight = availableHeight >= fallbackHeight ? fallbackHeight : 0.0

        guard availableWidth > 0, availableHeight > 0 else {
            return CalendarPlan(
                visibleWeeks: [],
                showsDateFallback: true,
                showsEventSummary: false,
                usedHeight: fallbackUsedHeight
            )
        }

        guard availableWidth >= 7.0 * maximumCellWidth else {
            return CalendarPlan(
                visibleWeeks: [],
                showsDateFallback: true,
                showsEventSummary: false,
                usedHeight: fallbackUsedHeight
            )
        }

        let baseOverhead = monthTitleHeight + weekdayHeaderHeight + (2 * contentSpacing)
        let minFirstWeekHeight = baseOverhead + cellHeight
        guard availableHeight >= minFirstWeekHeight else {
            return CalendarPlan(
                visibleWeeks: [],
                showsDateFallback: true,
                showsEventSummary: false,
                usedHeight: fallbackUsedHeight
            )
        }

        let summaryCost = eventSummaryHeight + contentSpacing
        let canAdmitSummary = hasEventSummary && (availableHeight >= minFirstWeekHeight + summaryCost)

        let completeMonthHeight = baseOverhead + (canAdmitSummary ? summaryCost : 0) + Double(totalWeeks) * cellHeight + Double(totalWeeks - 1) * rowSpacing
        let effectiveHeight = min(availableHeight, completeMonthHeight)

        let weekRange = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
            familyKind: familyKind,
            displayMode: displayMode,
            currentWeek: currentWeek,
            totalWeeks: totalWeeks,
            hasEventSummary: canAdmitSummary,
            availableHeight: effectiveHeight,
            monthTitleHeight: monthTitleHeight,
            weekdayHeaderHeight: weekdayHeaderHeight,
            eventSummaryHeight: eventSummaryHeight,
            cellHeight: cellHeight,
            rowSpacing: rowSpacing,
            contentSpacing: contentSpacing
        )

        let visibleWeeks = Array(weekRange)
        let k = visibleWeeks.count
        let gridHeight = Double(k) * cellHeight + Double(max(0, k - 1)) * rowSpacing
        let usedHeight = baseOverhead + (canAdmitSummary ? summaryCost : 0) + gridHeight

        return CalendarPlan(
            visibleWeeks: visibleWeeks,
            showsDateFallback: false,
            showsEventSummary: canAdmitSummary,
            usedHeight: usedHeight
        )
    }
}
// END DUOYI_WIDGET_DISPLAY_CORE

#if canImport(UIKit)
private enum DuoyiWidgetTypographyMetrics {
    static func contentSizeCategory(_ value: ContentSizeCategory) -> UIContentSizeCategory {
        switch value {
        case .extraSmall:
            return .extraSmall
        case .small:
            return .small
        case .medium:
            return .medium
        case .large:
            return .large
        case .extraLarge:
            return .extraLarge
        case .extraExtraLarge:
            return .extraExtraLarge
        case .extraExtraExtraLarge:
            return .extraExtraExtraLarge
        case .accessibilityMedium:
            return .accessibilityMedium
        case .accessibilityLarge:
            return .accessibilityLarge
        case .accessibilityExtraLarge:
            return .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge:
            return .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge:
            return .accessibilityExtraExtraExtraLarge
        @unknown default:
            let current = UITraitCollection.current.preferredContentSizeCategory
            return current != .unspecified ? current : .large
        }
    }

    static func font(
        baseSize: CGFloat,
        weight: UIFont.Weight = .regular,
        textStyle: UIFont.TextStyle,
        category: UIContentSizeCategory,
        rounded: Bool = false,
        monospacedDigits: Bool = false
    ) -> UIFont {
        let base: UIFont
        if monospacedDigits {
            base = UIFont.monospacedDigitSystemFont(ofSize: baseSize, weight: weight)
        } else {
            base = UIFont.systemFont(ofSize: baseSize, weight: weight)
        }
        let descriptor: UIFontDescriptor
        if rounded, let r = base.fontDescriptor.withDesign(.rounded) {
            descriptor = r
        } else {
            descriptor = base.fontDescriptor
        }
        let baseFont = UIFont(descriptor: descriptor, size: baseSize)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: baseFont, compatibleWith: traits)
    }

    static func roundUp(_ points: Double, scale: Double) -> Double {
        guard points.isFinite, points > 0, scale.isFinite, scale > 0 else {
            return (points.isFinite && points > 0) ? ceil(points) : 0.0
        }
        return ceil(points * scale) / scale
    }

    static func lineHeight(_ font: UIFont, pixelScale: Double) -> Double {
        let raw = Double(font.lineHeight)
        guard raw.isFinite, raw > 0 else { return 0.0 }
        return roundUp(raw, scale: pixelScale)
    }

    static func width(_ text: String, font: UIFont, pixelScale: Double) -> Double {
        guard !text.isEmpty, pixelScale.isFinite, pixelScale > 0 else { return 0.0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        let w = Double(size.width)
        guard w.isFinite, w > 0 else { return 0.0 }
        return roundUp(w, scale: pixelScale)
    }

    static func wrappedHeight(
        _ text: String,
        font: UIFont,
        availableWidth: Double,
        pixelScale: Double
    ) -> Double? {
        guard availableWidth.isFinite, availableWidth > 0, !text.isEmpty,
              pixelScale.isFinite, pixelScale > 0 else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: CGFloat(availableWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let h = Double(rect.height)
        guard h.isFinite, h > 0 else { return nil }
        return roundUp(h, scale: pixelScale)
    }

    static func symbolActionSize(font: UIFont, pixelScale: Double) -> CGSize {
        let config = UIImage.SymbolConfiguration(font: font)
        let image = UIImage(systemName: "checkmark.circle", withConfiguration: config)
        let rawSize = image?.size ?? CGSize(width: 18, height: 18)
        let w = roundUp(Double(rawSize.width), scale: pixelScale)
        let h = roundUp(Double(rawSize.height), scale: pixelScale)
        return CGSize(width: max(w, 18.0), height: max(h, 18.0))
    }
}
#endif

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
    let brandId: String
    let cardSkinId: String
    private(set) var isDark: Bool
    private(set) var primary: Color
    private(set) var background: Color
    private(set) var surface: Color
    private(set) var navBackground: Color
    private(set) var border: Color
    private(set) var text: Color
    private(set) var mutedText: Color
    private(set) var onPrimary: Color
    private(set) var readablePrimary: Color
    private(set) var readableMutedText: Color
    private(set) var readableOnPrimary: Color
    private(set) var accentStart: Color
    private(set) var accentEnd: Color
    let backgroundAssetKey: String
    let cornerRadius: CGFloat
    let controlRadius: CGFloat
    private(set) var borderWidth: CGFloat

    var isDefaultBrand: Bool {
        brandId == "defaultBrand" || brandId == "default"
    }

    var isPlainCard: Bool {
        cardSkinId == "plain_card"
    }

    var isDefaultIosStyle: Bool {
        isDefaultBrand && isPlainCard
    }

    var isGlassStyle: Bool {
        brandId == "liquidGlass" && isPlainCard
    }

    static let fallback = DuoyiWidgetTheme(
        brandId: "defaultBrand",
        cardSkinId: "plain_card",
        isDark: false,
        primary: color("#FF0066D6"),
        background: color("#FFF6F7F9"),
        surface: color("#FFFFFFFF"),
        navBackground: color("#FFF1F3F6"),
        border: color("#000066D6"),
        text: color("#FF1F2933"),
        mutedText: color("#FF667085"),
        onPrimary: color("#FFFFFFFF"),
        readablePrimary: color("#FF0066D6"),
        readableMutedText: color("#FF667085"),
        readableOnPrimary: color("#FFFFFFFF"),
        accentStart: color("#FF0066D6"),
        accentEnd: color("#FF2F8F83"),
        backgroundAssetKey: "",
        cornerRadius: 16,
        controlRadius: 12,
        borderWidth: 0
    )

    init(values: [String: Any]) {
        let rawBrandId = Self.readString(values, key: "widget_theme_brand_id", fallback: "defaultBrand")
        switch rawBrandId {
        case "liquid_glass":
            self.brandId = "liquidGlass"
        case "default":
            self.brandId = "defaultBrand"
        default:
            self.brandId = rawBrandId
        }
        self.cardSkinId = Self.readString(values, key: "widget_theme_card_skin_id", fallback: "plain_card")
        self.isDark = Self.readBool(values, key: "widget_theme_dark", fallback: false)
        self.primary = Self.read(values, key: "widget_theme_primary", fallback: "#FF0066D6")
        self.background = Self.read(values, key: "widget_theme_background", fallback: "#FFF6F7F9")
        self.surface = Self.read(values, key: "widget_theme_surface", fallback: "#FFFFFFFF")
        self.navBackground = Self.read(values, key: "widget_theme_nav_background", fallback: "#FFF1F3F6")
        self.border = Self.read(values, key: "widget_theme_border", fallback: "#000066D6")
        self.text = Self.read(values, key: "widget_theme_text", fallback: "#FF1F2933")
        self.mutedText = Self.read(values, key: "widget_theme_muted_text", fallback: "#FF667085")
        self.onPrimary = Self.read(values, key: "widget_theme_on_primary", fallback: "#FFFFFFFF")
        self.accentStart = Self.read(values, key: "widget_theme_accent_start", fallback: "#FF0066D6")
        self.accentEnd = Self.read(values, key: "widget_theme_accent_end", fallback: "#FF2F8F83")
        self.backgroundAssetKey = Self.readString(values, key: "widget_theme_background_asset_key", fallback: "")
        self.cornerRadius = Self.readClampedCGFloat(
            values, key: "widget_theme_corner_radius_dp", fallback: 16, min: 0, max: 32
        )
        self.controlRadius = Self.readClampedCGFloat(
            values, key: "widget_theme_control_radius_dp", fallback: 12, min: 0, max: 24
        )
        self.borderWidth = Self.readClampedCGFloat(
            values, key: "widget_theme_border_width_dp", fallback: 0, min: 0, max: 8
        )
        let backgrounds = [
            DuoyiWidgetThemeColorCore.resolve(values["widget_theme_background"], fallback: "#FFF6F7F9"),
            DuoyiWidgetThemeColorCore.resolve(values["widget_theme_surface"], fallback: "#FFFFFFFF"),
            DuoyiWidgetThemeColorCore.resolve(values["widget_theme_nav_background"], fallback: "#FFF1F3F6"),
        ]
        // Full-color foregrounds on known opaque plain surfaces only. Image
        // skins keep their own colors. Host-accented/vibrant output needs separate validation.
        let readablePlain = cardSkinId == "plain_card" &&
            (brandId == "defaultBrand" || brandId == "liquidGlass") &&
            backgroundAssetKey.isEmpty && backgrounds.allSatisfy { ($0 >> 24) == 255 }
        self.readablePrimary = Self.readableColor(values, key: "widget_theme_primary", fallback: "#FF0066D6", backgrounds: readablePlain ? backgrounds : [])
        self.readableMutedText = Self.readableColor(values, key: "widget_theme_muted_text", fallback: "#FF667085", backgrounds: readablePlain ? backgrounds : [])
        let primaryArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_primary"], fallback: "#FF0066D6")
        self.readableOnPrimary = Self.readableColor(values, key: "widget_theme_on_primary", fallback: "#FFFFFFFF", backgrounds: readablePlain && (primaryArgb >> 24) == 255 ? [primaryArgb] : [])

        let autoDarkBrand = (brandId == "defaultBrand" || brandId == "liquidGlass" || brandId == "default" || brandId == "liquid_glass") &&
            backgroundAssetKey.isEmpty
        if autoDarkBrand {
            let darkPrimaryArgb: UInt32 = 0xFF0A84FF
            let darkBackgroundArgb: UInt32 = 0xFF14171F
            let darkSurfaceArgb: UInt32 = 0xFF1C212B
            let darkNavBackgroundArgb: UInt32 = 0xFF242A36
            let darkBorderArgb: UInt32 = 0xFF2F3847
            let darkTextArgb: UInt32 = 0xFFF2F5FA
            let darkMutedTextArgb: UInt32 = 0xFFA5B0C2
            let darkOnPrimaryArgb: UInt32 = 0xFFFFFFFF
            let darkAccentEndArgb: UInt32 = 0xFF3898FF
            let darkReadablePrimaryArgb: UInt32 = DuoyiWidgetThemeColorCore.readable(
                darkAccentEndArgb,
                backgrounds: [darkBackgroundArgb, darkSurfaceArgb, darkNavBackgroundArgb]
            )
            let darkReadableMutedArgb: UInt32 = DuoyiWidgetThemeColorCore.readable(
                darkMutedTextArgb,
                backgrounds: [darkBackgroundArgb, darkSurfaceArgb, darkNavBackgroundArgb]
            )
            let darkReadableOnPrimaryArgb: UInt32 = DuoyiWidgetThemeColorCore.readable(
                darkOnPrimaryArgb,
                backgrounds: [darkPrimaryArgb]
            )

            if self.isDark {
                self.primary = Self.color(value: darkPrimaryArgb)
                self.background = Self.color(value: darkBackgroundArgb)
                self.surface = Self.color(value: darkSurfaceArgb)
                self.navBackground = Self.color(value: darkNavBackgroundArgb)
                self.border = Self.color(value: darkBorderArgb)
                self.text = Self.color(value: darkTextArgb)
                self.mutedText = Self.color(value: darkMutedTextArgb)
                self.onPrimary = Self.color(value: darkOnPrimaryArgb)
                self.readablePrimary = Self.color(value: darkReadablePrimaryArgb)
                self.readableMutedText = Self.color(value: darkReadableMutedArgb)
                self.readableOnPrimary = Self.color(value: darkReadableOnPrimaryArgb)
                self.accentStart = Self.color(value: darkPrimaryArgb)
                self.accentEnd = Self.color(value: darkAccentEndArgb)
                self.borderWidth = max(self.borderWidth, 1)
            } else {
                let lightPrimaryArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_primary"], fallback: "#FF0066D6")
                let lightBackgroundArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_background"], fallback: "#FFF6F7F9")
                let lightSurfaceArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_surface"], fallback: "#FFFFFFFF")
                let lightNavBackgroundArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_nav_background"], fallback: "#FFF1F3F6")
                let lightBorderArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_border"], fallback: "#000066D6")
                let lightTextArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_text"], fallback: "#FF1F2933")
                let lightMutedArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_muted_text"], fallback: "#FF667085")
                let lightOnPrimaryArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_on_primary"], fallback: "#FFFFFFFF")
                let lightAccentStartArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_accent_start"], fallback: "#FF0066D6")
                let lightAccentEndArgb = DuoyiWidgetThemeColorCore.resolve(values["widget_theme_accent_end"], fallback: "#FF2F8F83")
                let lightReadablePrimaryArgb = readablePlain ? DuoyiWidgetThemeColorCore.readable(lightPrimaryArgb, backgrounds: backgrounds) : lightPrimaryArgb
                let lightReadableMutedArgb = readablePlain ? DuoyiWidgetThemeColorCore.readable(lightMutedArgb, backgrounds: backgrounds) : lightMutedArgb
                let lightReadableOnPrimaryArgb = (readablePlain && (lightPrimaryArgb >> 24) == 255)
                    ? DuoyiWidgetThemeColorCore.readable(lightOnPrimaryArgb, backgrounds: [lightPrimaryArgb])
                    : lightOnPrimaryArgb

                self.primary = Self.adaptiveColor(light: lightPrimaryArgb, dark: darkPrimaryArgb)
                self.background = Self.adaptiveColor(light: lightBackgroundArgb, dark: darkBackgroundArgb)
                self.surface = Self.adaptiveColor(light: lightSurfaceArgb, dark: darkSurfaceArgb)
                self.navBackground = Self.adaptiveColor(light: lightNavBackgroundArgb, dark: darkNavBackgroundArgb)
                self.border = Self.adaptiveColor(light: lightBorderArgb, dark: darkBorderArgb)
                self.text = Self.adaptiveColor(light: lightTextArgb, dark: darkTextArgb)
                self.mutedText = Self.adaptiveColor(light: lightMutedArgb, dark: darkMutedTextArgb)
                self.onPrimary = Self.adaptiveColor(light: lightOnPrimaryArgb, dark: darkOnPrimaryArgb)
                self.readablePrimary = Self.adaptiveColor(light: lightReadablePrimaryArgb, dark: darkReadablePrimaryArgb)
                self.readableMutedText = Self.adaptiveColor(light: lightReadableMutedArgb, dark: darkReadableMutedArgb)
                self.readableOnPrimary = Self.adaptiveColor(light: lightReadableOnPrimaryArgb, dark: darkReadableOnPrimaryArgb)
                self.accentStart = Self.adaptiveColor(light: lightAccentStartArgb, dark: darkPrimaryArgb)
                self.accentEnd = Self.adaptiveColor(light: lightAccentEndArgb, dark: darkAccentEndArgb)
                self.borderWidth = max(self.borderWidth, 1)
            }
        }
    }

    private init(
        brandId: String,
        cardSkinId: String,
        isDark: Bool,
        primary: Color,
        background: Color,
        surface: Color,
        navBackground: Color,
        border: Color,
        text: Color,
        mutedText: Color,
        onPrimary: Color,
        readablePrimary: Color,
        readableMutedText: Color,
        readableOnPrimary: Color,
        accentStart: Color,
        accentEnd: Color,
        backgroundAssetKey: String,
        cornerRadius: CGFloat,
        controlRadius: CGFloat,
        borderWidth: CGFloat
    ) {
        self.brandId = brandId
        self.cardSkinId = cardSkinId
        self.isDark = isDark
        self.primary = primary
        self.background = background
        self.surface = surface
        self.navBackground = navBackground
        self.border = border
        self.text = text
        self.mutedText = mutedText
        self.onPrimary = onPrimary
        self.readablePrimary = readablePrimary
        self.readableMutedText = readableMutedText
        self.readableOnPrimary = readableOnPrimary
        self.accentStart = accentStart
        self.accentEnd = accentEnd
        self.backgroundAssetKey = backgroundAssetKey
        self.cornerRadius = cornerRadius
        self.controlRadius = controlRadius
        self.borderWidth = borderWidth
    }

    static func normalizeAssetKey(_ key: String) -> String {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "re0", "assets/backgrounds/re0.png": return "re0"
        case "genshin", "assets/backgrounds/genshin.png": return "genshin"
        case "star_rail", "starrail", "assets/backgrounds/star_rail.png": return "star_rail"
        case "wuthering", "wutheringwaves", "assets/backgrounds/wuthering.png": return "wuthering"
        case "zzz", "assets/backgrounds/zzz.png": return "zzz"
        case "yanyun", "assets/backgrounds/yanyun.png": return "yanyun"
        case "botw", "assets/backgrounds/botw.png": return "botw"
        default: return clean
        }
    }

    #if canImport(UIKit)
    var backgroundImage: UIImage? {
        guard !backgroundAssetKey.isEmpty else { return nil }
        let key = Self.normalizeAssetKey(backgroundAssetKey)
        guard !key.isEmpty else { return nil }
        return UIImage(named: key, in: Bundle.main, compatibleWith: nil) ?? UIImage(named: key)
    }
    #endif

    private static func readString(_ values: [String: Any], key: String, fallback: String) -> String {
        guard let value = values[key] as? String else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func readBool(_ values: [String: Any], key: String, fallback: Bool) -> Bool {
        guard let value = values[key] else { return fallback }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let text = value as? String {
            let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower == "true" || lower == "1" { return true }
            if lower == "false" || lower == "0" { return false }
        }
        return fallback
    }

    private static func readClampedCGFloat(
        _ values: [String: Any],
        key: String,
        fallback: CGFloat,
        min: CGFloat,
        max: CGFloat
    ) -> CGFloat {
        guard let value = values[key] else { return fallback }
        let raw: Double?
        if let number = value as? NSNumber {
            raw = number.doubleValue
        } else if let text = value as? String,
                  let parsed = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            raw = parsed
        } else {
            raw = nil
        }
        guard let resolved = raw, resolved.isFinite else { return fallback }
        return Swift.min(Swift.max(CGFloat(resolved), min), max)
    }

    private static func read(_ values: [String: Any], key: String, fallback: String) -> Color {
        color(values[key], fallback: fallback)
    }

    private static func color(_ raw: Any?, fallback: String = "#FF0066D6") -> Color {
        let value = DuoyiWidgetThemeColorCore.resolve(raw, fallback: fallback)
        return color(value: value)
    }

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { trait in
            let argb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((argb >> 16) & 0xFF) / 255.0,
                green: CGFloat((argb >> 8) & 0xFF) / 255.0,
                blue: CGFloat(argb & 0xFF) / 255.0,
                alpha: CGFloat((argb >> 24) & 0xFF) / 255.0
            )
        })
        #else
        return color(value: light)
        #endif
    }

    private static func readableColor(_ values: [String: Any], key: String, fallback: String, backgrounds: [UInt32]) -> Color {
        let preferred = DuoyiWidgetThemeColorCore.resolve(values[key], fallback: fallback)
        return color(value: DuoyiWidgetThemeColorCore.readable(preferred, backgrounds: backgrounds))
    }

    private static func color(value: UInt32) -> Color {
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
        return snapshot.actionURL(URLComponents(string: "duoyi://todo/\(encodedId)"))
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

/// Normalize only labels produced by Duoyi's built-in locale strings. A user
/// supplied navigation name must remain unchanged when the widget locale
/// changes.
private func localizedNavigationLabel(
    _ raw: String,
    zh: String,
    en: String,
    locale: DuoyiWidgetLocale
) -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return locale == .en ? en : zh }
    let generated = value == zh || value == en || (zh == "待办" && value == "To-Do")
    return generated ? (locale == .en ? en : zh) : raw
}

private func isAnniversaryFallback(_ text: String) -> Bool {
    DuoyiWidgetDisplayCore.isKnownAnniversaryEmptyPlaceholder(text)
}

private func localizedFocusTimerLabel(_ raw: String, locale: DuoyiWidgetLocale) -> String {
    switch raw {
    case "专注倒计时", "倒计时", "Focus countdown":
        return locale == .en ? "Focus countdown" : "专注倒计时"
    case "专注正计时", "正计时", "正计时专注中", "Focus count-up", "Focus counting up":
        return locale == .en ? "Focus counting up" : "正计时专注中"
    case "短休息倒计时", "Short break countdown":
        return locale == .en ? "Short break countdown" : "短休息倒计时"
    case "长休息倒计时", "Long break countdown":
        return locale == .en ? "Long break countdown" : "长休息倒计时"
    default:
        return raw
    }
}

private func isScheduleFallback(_ text: String) -> Bool {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmed = value.hasPrefix("· ")
        ? String(value.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        : value
    return trimmed.isEmpty || trimmed == "今日没有日程" || trimmed == "No events today"
}

private struct DuoyiWidgetEntry: TimelineEntry {
    let date: Date
    let config: DuoyiWidgetConfig
    let locale: DuoyiWidgetLocale
    let snapshot: DuoyiWidgetSnapshot
    let isDailyFresh: Bool
    let primary: String
    let primaryTarget: String
    let rows: [DuoyiWidgetRow]
    let todoRows: [DuoyiTodoRow]
    let todoCount: Int?
    let brandTitle: String
    let navTodo: String
    let navHabit: String
    let navCalendar: String
    let navFocus: String
    let displayMode: String
    let habitQuickCheckId: String
    let focusTimer: DuoyiFocusTimerState
    let focusTimerLabel: String
    let calendarEventSummary: String?
    let calendarEventTarget: String
    let firstDayOfWeek: Int
    let habitPercent: Int?
    let goalProgressPercent: Int?
    let theme: DuoyiWidgetTheme

    var focusTimerRunning: Bool { focusTimer.isRunning }
    var focusTimerRemainingSeconds: Int { focusTimer.seconds }
    var focusTimerTotalSeconds: Int { focusTimer.totalSeconds }
    var focusTimerEndDate: Date? { focusTimer.endDate }

    var focusProgressPercent: Int? {
        guard isDailyFresh, focusTimerTotalSeconds > 0,
              (focusTimerRunning || focusActionIntent == .resume) else {
            return nil
        }
        if focusTimer.isCountUp {
            let pct = Int((Double(min(max(focusTimerRemainingSeconds, 0), focusTimerTotalSeconds)) * 100.0 / Double(focusTimerTotalSeconds)).rounded())
            return min(max(pct, 0), 100)
        } else {
            let elapsed = min(max(focusTimerTotalSeconds - focusTimerRemainingSeconds, 0), focusTimerTotalSeconds)
            let pct = Int((Double(elapsed) * 100.0 / Double(focusTimerTotalSeconds)).rounded())
            return min(max(pct, 0), 100)
        }
    }

    var focusActionIntent: DuoyiFocusActionIntent {
        focusTimer.actionIntent(isDailyFresh: isDailyFresh)
    }
}

private struct DuoyiWidgetProvider: TimelineProvider {
    let config: DuoyiWidgetConfig

    func placeholder(in context: Context) -> DuoyiWidgetEntry {
        let values = publicationCapture().values
        let locale = DuoyiWidgetLocale.resolve(saved: values["widget_locale"] as? String)
        let localizedConfig = config.localized(for: locale)
        return DuoyiWidgetEntry(
            date: Date(),
            config: localizedConfig,
            locale: locale,
            snapshot: .empty,
            isDailyFresh: false,
            primary: localizedConfig.fallback,
            primaryTarget: localizedConfig.deepLink,
            rows: localizedConfig.rowKeys.enumerated().map {
                DuoyiWidgetRow(index: $0.offset + 2, title: localizedConfig.fallback, target: localizedConfig.deepLink)
            },
            todoRows: [],
            todoCount: nil,
            brandTitle: locale == .en ? "Duoyi" : "多仪",
            navTodo: locale == .en ? "Tasks" : "待办",
            navHabit: locale == .en ? "Habits" : "习惯",
            navCalendar: locale == .en ? "Calendar" : "日历",
            navFocus: locale == .en ? "Focus" : "专注",
            displayMode: "standard",
            habitQuickCheckId: "",
            focusTimer: .unavailable,
            focusTimerLabel: locale == .en ? "Focus countdown" : "专注倒计时",
            calendarEventSummary: nil,
            calendarEventTarget: localizedConfig.deepLink,
            firstDayOfWeek: 1,
            habitPercent: nil,
            goalProgressPercent: nil,
            theme: .fallback
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DuoyiWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DuoyiWidgetEntry>) -> Void) {
        // All scheduled transitions retain this publication and account identity.
        let capture = publicationCapture()
        let now = Date()
        let current = entry(capture: capture, at: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dates = DuoyiFocusTimerTimeline.dates(now: now, timer: current.focusTimer, calendar: calendar)
        let entries = dates.map { entry(capture: capture, at: $0) }
        let nextRefresh = capture.timelineRefreshDate(
            now: now,
            focusTimerRunning: current.focusTimerRunning,
            nextTransition: dates.dropFirst().first
        )
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func entry() -> DuoyiWidgetEntry {
        // One immutable read avoids mixing item IDs and account metadata.
        let capture = publicationCapture()
        return entry(capture: capture, at: Date())
    }

    private func publicationCapture() -> DuoyiWidgetPublicationCapture {
        DuoyiWidgetPublicationCapture.capture(
            read: { DuoyiWidgetPublicationStore.shared.read() },
            displayMode: { UserDefaults(suiteName: appGroupId)?.object(forKey: "widget_display_mode") }
        )
    }

    private func entry(capture: DuoyiWidgetPublicationCapture, at now: Date) -> DuoyiWidgetEntry {
        let defaults = capture.values
        let snapshot = DuoyiWidgetSnapshot(values: defaults)
        let fresh = snapshot.isFresh(at: now)
        let locale = DuoyiWidgetLocale.resolve(saved: defaults["widget_locale"] as? String)
        let localizedConfig = config.localized(for: locale)
        let todoRows = fresh ? readTodoRows(defaults, locale: locale, snapshot: snapshot) : []
        let todoCount = readTodoCount(defaults, snapshot: snapshot, at: now)
        let primary: String
        let primaryTarget: String
        let rows: [DuoyiWidgetRow]

        let calendarEventSummary: String?
        let calendarEventTarget: String
        if localizedConfig.kind == "DuoyiCalendarWidget" {
            let rawSummary = defaults["today_event_summary"] as? String
            let rawSchedule1Id = defaults["schedule_highlight_1_id"] as? String
            let summaryResult = DuoyiWidgetDisplayCore.resolveCalendarSummaryAndTarget(
                rawSummary: rawSummary,
                rawSchedule1Id: rawSchedule1Id,
                isFresh: fresh,
                isZh: locale == .zh
            )
            calendarEventSummary = summaryResult.summary
            calendarEventTarget = summaryResult.target
        } else {
            calendarEventSummary = nil
            calendarEventTarget = ""
        }

        if !fresh {
            if localizedConfig.kind == "DuoyiAnniversaryWidget" {
                primary = locale == .zh ? "日期数据待刷新" : "Dates pending refresh"
            } else {
                primary = locale == .en ? "Open Duoyi to refresh" : "打开多仪刷新数据"
            }
            primaryTarget = localizedConfig.deepLink
            rows = []
        } else if localizedConfig.kind == "DuoyiTodoWidget" {
            primary = todoRows.first?.title ?? localizedConfig.fallback
            primaryTarget = todoRows.first?.detailURL?.absoluteString ?? localizedConfig.deepLink
            rows = []
        } else if localizedConfig.kind == "DuoyiAnniversaryWidget" {
            let rawSlots = [
                DuoyiAnniversaryRawSlot(sourceKey: "anniversary_highlight_1", text: defaults["anniversary_highlight_1"] as? String, target: defaults["anniversary_highlight_1_id"] as? String),
                DuoyiAnniversaryRawSlot(sourceKey: "anniversary_highlight_2", text: defaults["anniversary_highlight_2"] as? String, target: defaults["anniversary_highlight_2_id"] as? String),
                DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_1", text: defaults["memorial_highlight_1"] as? String, target: defaults["memorial_highlight_1_id"] as? String),
                DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_2", text: defaults["memorial_highlight_2"] as? String, target: defaults["memorial_highlight_2_id"] as? String),
                DuoyiAnniversaryRawSlot(sourceKey: "memorial_highlight_3", text: defaults["memorial_highlight_3"] as? String, target: defaults["memorial_highlight_3_id"] as? String),
            ]
            let resolved = DuoyiWidgetDisplayCore.resolveAnniversaryItems(slots: rawSlots, isFresh: true, isZh: locale == .zh)
            if let first = resolved.first {
                primary = first.text
                primaryTarget = first.target
                rows = resolved.dropFirst().enumerated().map { offset, item in
                    DuoyiWidgetRow(index: offset + 2, title: item.text, target: item.target)
                }
            } else {
                primary = localizedConfig.fallback
                primaryTarget = localizedConfig.deepLink
                rows = []
            }
        } else {
            let primarySource = readPrimary(defaults, config: localizedConfig, locale: locale)
            primary = primarySource.title
            primaryTarget = primarySource.target
            rows = readRows(defaults, config: localizedConfig, locale: locale, excluding: primarySource.sourceKey)
        }
        let brandFallback = locale == .en ? "Duoyi" : "多仪"
        let rawBrand = readString(defaults, key: "brand_app_title", fallback: brandFallback)
        let brandTitle = (locale == .en && rawBrand == "多仪") ? "Duoyi" : (locale == .zh && rawBrand == "Duoyi" ? "多仪" : rawBrand)

        let navTodo = localizedNavigationLabel(
            readString(defaults, key: "nav_todo", fallback: locale == .en ? "Tasks" : "待办"),
            zh: "待办", en: "Tasks", locale: locale
        )
        let navHabit = localizedNavigationLabel(
            readString(defaults, key: "nav_habit", fallback: locale == .en ? "Habits" : "习惯"),
            zh: "习惯", en: "Habits", locale: locale
        )
        let navCalendar = localizedNavigationLabel(
            readString(defaults, key: "nav_calendar", fallback: locale == .en ? "Calendar" : "日历"),
            zh: "日历", en: "Calendar", locale: locale
        )
        let navFocus = localizedNavigationLabel(
            readString(defaults, key: "nav_focus", fallback: locale == .en ? "Focus" : "专注"),
            zh: "专注", en: "Focus", locale: locale
        )

        let focusTimerLabelFallback = locale == .en ? "Focus countdown" : "专注倒计时"
        let rawTimerLabel = readString(defaults, key: "focus_timer_label", fallback: focusTimerLabelFallback)
        let focusTimerLabel = localizedFocusTimerLabel(rawTimerLabel, locale: locale)

        let habitPercent: Int? = {
            guard fresh, localizedConfig.kind == "DuoyiHabitWidget" else { return nil }
            let activeCount = (defaults["habit_active_count"] as? NSNumber)?.intValue ?? -1
            guard activeCount != 0 else { return nil }
            if let num = defaults["habit_percent"] as? NSNumber {
                return min(max(num.intValue, 0), 100)
            }
            return nil
        }()
        let goalProgressPercent: Int? = {
            guard fresh, localizedConfig.kind == "DuoyiGoalWidget" else { return nil }
            return ([primary] + rows.map(\.title)).compactMap {
                DuoyiWidgetDisplayCore.extractGoalProgressPercent($0)
            }.first
        }()

        return DuoyiWidgetEntry(
            date: now,
            config: localizedConfig,
            locale: locale,
            snapshot: snapshot,
            isDailyFresh: fresh,
            primary: primary,
            primaryTarget: primaryTarget,
            rows: rows,
            todoRows: todoRows,
            todoCount: todoCount,
            brandTitle: brandTitle,
            navTodo: navTodo,
            navHabit: navHabit,
            navCalendar: navCalendar,
            navFocus: navFocus,
            displayMode: readString(defaults, key: "widget_display_mode", fallback: "standard"),
            habitQuickCheckId: fresh ? readString(defaults, key: "habit_quick_check_id", fallback: "") : "",
            focusTimer: DuoyiFocusTimerState.resolve(values: defaults, sessionPublished: snapshot.hasPublishedSession, at: now),
            focusTimerLabel: focusTimerLabel,
            calendarEventSummary: calendarEventSummary,
            calendarEventTarget: calendarEventTarget,
            firstDayOfWeek: DuoyiWidgetDisplayCore.resolveFirstDayOfWeek(defaults["widget_first_day_of_week"]),
            habitPercent: habitPercent,
            goalProgressPercent: goalProgressPercent,
            theme: DuoyiWidgetTheme(values: defaults)
        )
    }

    private func readTodoCount(_ defaults: [String: Any], snapshot: DuoyiWidgetSnapshot, at now: Date) -> Int? {
        guard snapshot.isFresh(at: now) else { return nil }
        return DuoyiWidgetDisplayCore.decodeTodoCount(defaults["todo_count"])
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

        if config.kind == "DuoyiScheduleWidget" {
            let highlight1Title = readString(defaults, key: "schedule_highlight_1", fallback: "")
            let highlight1Target = readString(defaults, key: "schedule_highlight_1_id", fallback: "")
            let summaryTitle = readString(defaults, key: "today_event_summary", fallback: config.fallback)
            let summaryTarget = readString(defaults, key: "today_event_summary_id", fallback: "")
            let hasHighlightTarget = !highlight1Target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasSummaryTarget = !summaryTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if !highlight1Title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (hasHighlightTarget || !isScheduleFallback(highlight1Title)) {
                title = highlight1Title
                target = hasHighlightTarget ? highlight1Target : config.deepLink
                sourceKey = "schedule_highlight_1"
            } else if !summaryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (hasHighlightTarget || hasSummaryTarget || !isScheduleFallback(summaryTitle)) {
                title = summaryTitle
                let resolvedTarget = hasHighlightTarget ? highlight1Target : (hasSummaryTarget ? summaryTarget : config.deepLink)
                target = resolvedTarget
                sourceKey = "schedule_highlight_1"
            } else {
                title = localizedFallbackString(config.fallback, kind: config.kind, locale: locale)
                target = config.deepLink
                sourceKey = config.primaryKey
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
            // The service mirrors the empty schedule summary into highlight 1
            // for schema compatibility. Do not render that placeholder as a
            // second row; a real event with a detail target remains literal.
            if config.kind == "DuoyiScheduleWidget" &&
                itemTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                isScheduleFallback(title) {
                return nil
            }
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
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    let entry: DuoyiWidgetEntry

    private var uiCategory: UIContentSizeCategory {
        #if canImport(UIKit)
        return DuoyiWidgetTypographyMetrics.contentSizeCategory(sizeCategory)
        #else
        return .large
        #endif
    }

    private var pixelScale: Double {
        let s = Double(displayScale)
        return (s.isFinite && s > 0) ? s : 2.0
    }

    @ViewBuilder
    var body: some View {
        if isAccessoryFamily {
            accessoryContent
                .widgetURL(widgetRootURL)
        } else if entry.config.kind == "DuoyiCalendarWidget" {
            calendarBody
        } else {
            GeometryReader { proxy in
                plannedHomeBody(availableWidth: Double(proxy.size.width), availableHeight: Double(proxy.size.height))
            }
            .padding(padding)
            .duoyiWidgetBackground(entry.theme)
            .widgetURL(widgetRootURL)
        }
    }

    private var calendarBody: some View {
        GeometryReader { proxy in
            plannedCalendarBody(availableWidth: Double(proxy.size.width), availableHeight: Double(proxy.size.height))
        }
        .padding(padding)
        .duoyiWidgetBackground(entry.theme)
        .widgetURL(URL(string: entry.config.deepLink))
    }

    private struct HeaderFonts {
        let title: UIFont
        let count: UIFont
        let brand: UIFont
        let quickAction: UIFont
    }

    private enum HeaderReflowMode {
        case horizontal(showsBrand: Bool)
        case stacked
        case overflow
    }

    private func measureHeader(availableWidth: Double, fonts: HeaderFonts) -> (mode: HeaderReflowMode, height: Double) {
        guard availableWidth.isFinite, availableWidth > 0 else {
            return (.overflow, 0)
        }

        let dotWidth = 8.0
        let gap = 6.0
        let titleW = DuoyiWidgetTypographyMetrics.width(entry.config.title, font: fonts.title, pixelScale: pixelScale)
        let titleH = DuoyiWidgetTypographyMetrics.lineHeight(fonts.title, pixelScale: pixelScale)

        let hasCount = entry.config.kind == "DuoyiTodoWidget" && entry.todoCount != nil
        let countLabel = hasCount ? DuoyiWidgetDisplayCore.todoCountLabel(entry.todoCount!, isZh: entry.locale == .zh) : ""
        let countW = hasCount ? DuoyiWidgetTypographyMetrics.width(countLabel, font: fonts.count, pixelScale: pixelScale) : 0.0
        let countH = hasCount ? DuoyiWidgetTypographyMetrics.lineHeight(fonts.count, pixelScale: pixelScale) : 0.0

        let brandW = DuoyiWidgetTypographyMetrics.width(entry.brandTitle, font: fonts.brand, pixelScale: pixelScale)
        let brandH = DuoyiWidgetTypographyMetrics.lineHeight(fonts.brand, pixelScale: pixelScale)

        let hasQuickAction = supportsItemLinks && (quickURL != nil)
        let quickTitleW = hasQuickAction ? DuoyiWidgetTypographyMetrics.width(quickActionTitle, font: fonts.quickAction, pixelScale: pixelScale) : 0.0
        let quickActionW = hasQuickAction ? quickTitleW + 12.0 : 0.0
        let quickActionH = hasQuickAction ? DuoyiWidgetTypographyMetrics.lineHeight(fonts.quickAction, pixelScale: pixelScale) + 5.0 : 0.0

        let leftW = dotWidth + gap + titleW + (hasCount ? gap + countW : 0.0)
        let rightWithBrandW = brandW + (hasQuickAction ? gap + quickActionW : 0.0)
        let totalWithBrand = leftW + (rightWithBrandW > 0 ? gap + rightWithBrandW : 0.0)

        if totalWithBrand <= availableWidth {
            let h = max(titleH, countH, brandH, hasQuickAction ? quickActionH : 0.0, 8.0)
            return (.horizontal(showsBrand: true), h)
        }

        let rightNoBrandW = hasQuickAction ? quickActionW : 0.0
        let totalNoBrand = leftW + (rightNoBrandW > 0 ? gap + rightNoBrandW : 0.0)

        if totalNoBrand <= availableWidth {
            let h = max(titleH, countH, hasQuickAction ? quickActionH : 0.0, 8.0)
            return (.horizontal(showsBrand: false), h)
        }

        if hasQuickAction {
            let row1H: Double
            if leftW <= availableWidth {
                row1H = max(titleH, countH, 8.0)
            } else {
                let titleUsableW = availableWidth - dotWidth - gap - (hasCount ? gap + countW : 0.0)
                guard titleUsableW > 0,
                      let wrappedTitleH = DuoyiWidgetTypographyMetrics.wrappedHeight(entry.config.title, font: fonts.title, availableWidth: titleUsableW, pixelScale: pixelScale) else {
                    return (.overflow, 0)
                }
                row1H = max(wrappedTitleH, countH, 8.0 + 4.0)
            }

            let row2H: Double
            if quickActionW <= availableWidth {
                row2H = quickActionH
            } else {
                let quickUsableW = availableWidth - 12.0
                guard quickUsableW > 0,
                      let wrappedQuickH = DuoyiWidgetTypographyMetrics.wrappedHeight(quickActionTitle, font: fonts.quickAction, availableWidth: quickUsableW, pixelScale: pixelScale) else {
                    return (.overflow, 0)
                }
                row2H = wrappedQuickH + 5.0
            }

            let totalStackedH = row1H + 6.0 + row2H
            return (.stacked, totalStackedH)
        } else {
            let titleUsableW = availableWidth - dotWidth - gap - (hasCount ? gap + countW : 0.0)
            guard titleUsableW > 0,
                  let wrappedTitleH = DuoyiWidgetTypographyMetrics.wrappedHeight(entry.config.title, font: fonts.title, availableWidth: titleUsableW, pixelScale: pixelScale) else {
                return (.overflow, 0)
            }
            let h = max(wrappedTitleH, countH, 8.0 + 4.0)
            return (.horizontal(showsBrand: false), h)
        }
    }

    @ViewBuilder
    private func plannedHeaderView(mode: HeaderReflowMode, fonts: HeaderFonts) -> some View {
        let titleFont = Font(fonts.title)
        let countFont = Font(fonts.count)
        let brandFont = Font(fonts.brand)
        let quickActionFont = Font(fonts.quickAction)
        let gap: CGFloat = 6.0

        switch mode {
        case .horizontal(let showsBrand):
            HStack(spacing: 0) {
                Circle()
                    .fill(entry.theme.primary)
                    .frame(width: 8, height: 8)
                Spacer().frame(width: gap)
                Text(entry.config.title)
                    .font(titleFont)
                    .foregroundColor(entry.theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.config.kind == "DuoyiTodoWidget", let count = entry.todoCount {
                    Spacer().frame(width: gap)
                    Text(DuoyiWidgetDisplayCore.todoCountLabel(count, isZh: entry.locale == .zh))
                        .font(countFont)
                        .foregroundColor(entry.theme.readablePrimary)
                }
                Spacer(minLength: 0)
                if showsBrand {
                    Text(entry.brandTitle)
                        .font(brandFont)
                        .foregroundColor(entry.theme.readableMutedText)
                    if supportsItemLinks, let quickURL {
                        Spacer().frame(width: gap)
                        plannedQuickActionButton(font: quickActionFont, quickURL: quickURL)
                    }
                } else if supportsItemLinks, let quickURL {
                    plannedQuickActionButton(font: quickActionFont, quickURL: quickURL)
                }
            }
        case .stacked:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Circle()
                        .fill(entry.theme.primary)
                        .frame(width: 8, height: 8)
                        .padding(.top, 4)
                    Spacer().frame(width: gap)
                    Text(entry.config.title)
                        .font(titleFont)
                        .foregroundColor(entry.theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.config.kind == "DuoyiTodoWidget", let count = entry.todoCount {
                        Spacer().frame(width: gap)
                        Text(DuoyiWidgetDisplayCore.todoCountLabel(count, isZh: entry.locale == .zh))
                            .font(countFont)
                            .foregroundColor(entry.theme.readablePrimary)
                    }
                    Spacer(minLength: 0)
                }
                if supportsItemLinks, let quickURL {
                    Spacer().frame(height: 6.0)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        plannedQuickActionButton(font: quickActionFont, quickURL: quickURL)
                    }
                }
            }
        case .overflow:
            EmptyView()
        }
    }

    private func plannedQuickActionButton(font: Font, quickURL: URL) -> some View {
        Link(destination: quickURL) {
            Text(quickActionTitle)
                .font(font)
                .foregroundColor(entry.theme.readablePrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                        .fill(entry.theme.navBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                        .strokeBorder(entry.theme.border, lineWidth: entry.theme.borderWidth > 0 ? entry.theme.borderWidth : 0)
                )
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func plannedFooterView(footerFont: UIFont) -> some View {
        HStack(spacing: 8) {
            plannedNavLink(entry.navTodo, "duoyi://todo", font: footerFont)
            plannedNavLink(entry.navHabit, "duoyi://habit", font: footerFont)
            plannedNavLink(entry.navCalendar, "duoyi://calendar", font: footerFont)
            plannedNavLink(entry.navFocus, "duoyi://focus", font: footerFont)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                .fill(entry.theme.navBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                .strokeBorder(entry.theme.border, lineWidth: entry.theme.borderWidth > 0 ? entry.theme.borderWidth : 0)
        )
    }

    private func plannedNavLink(_ text: String, _ urlString: String, font: UIFont) -> some View {
        Group {
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Text(text)
                        .font(Font(font))
                        .foregroundColor(entry.theme.readableMutedText)
                }
            } else {
                Text(text)
                    .font(Font(font))
                    .foregroundColor(entry.theme.readableMutedText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func plannedStandaloneFallbackView(
        font: UIFont,
        availableWidth: Double,
        availableHeight: Double,
        fits: Bool,
        staleHint: String = ""
    ) -> some View {
        let labelText = entry.locale == .en ? "Open in app" : "在应用中打开"
        let baseDescription = entry.locale == .en
            ? "Content cannot fit at current text size. Open in app"
            : "当前字体大小无法完整显示内容，在应用中打开"
        let accessibleDescription: String = {
            guard !staleHint.isEmpty else { return baseDescription }
            return entry.locale == .en ? "\(staleHint). \(baseDescription)" : "\(staleHint)，\(baseDescription)"
        }()
        let destinationURL: URL? = {
            if family == .systemSmall {
                return widgetRootURL
            }
            if entry.config.kind == "DuoyiTodoWidget" {
                return entry.todoRows.first?.detailURL ?? widgetRootURL
            }
            if let actionURL = entry.snapshot.actionURL(URLComponents(string: entry.primaryTarget)) {
                return actionURL
            }
            return widgetRootURL
        }()

        if fits {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if supportsItemLinks, let url = destinationURL {
                        Link(destination: url) {
                            Text(labelText)
                                .font(Font(font))
                                .foregroundColor(entry.theme.readablePrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(labelText)
                            .font(Font(font))
                            .foregroundColor(entry.theme.readablePrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibleDescription)
                .accessibilityHint(staleHint)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityHint(staleHint)
        } else {
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibleDescription)
                .accessibilityHint(staleHint)
        }
    }

    private func plannedTodoRow(
        _ row: DuoyiTodoRow,
        primary: Bool,
        primaryFont: UIFont,
        secondaryFont: UIFont,
        completionFont: UIFont,
        completionActionSize: CGSize
    ) -> some View {
        let font = primary ? primaryFont : secondaryFont
        let color = primary ? entry.theme.text : entry.theme.readableMutedText
        let hasCompletion = supportsItemLinks && (row.completeURL != nil)

        return HStack(spacing: 0) {
            if supportsItemLinks, let detailURL = row.detailURL {
                Link(destination: detailURL) {
                    Text(cleanRow(row.title))
                        .font(Font(font))
                        .foregroundColor(color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(cleanRow(row.title))
                    .font(Font(font))
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if hasCompletion, let completeURL = row.completeURL {
                Spacer().frame(width: 6.0)
                Link(destination: completeURL) {
                    Image(systemName: "checkmark.circle")
                        .font(Font(completionFont))
                        .foregroundColor(entry.theme.readablePrimary)
                        .frame(width: completionActionSize.width, height: completionActionSize.height)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(entry.locale == .en
                    ? "Complete task: \(cleanRow(row.title))"
                    : "完成待办：\(cleanRow(row.title))")
            }
        }
    }

    private func plannedLinkedText(_ title: String, target: String, font: UIFont, isPrimary: Bool) -> some View {
        let color = isPrimary ? entry.theme.text : entry.theme.readableMutedText
        return Group {
            if supportsItemLinks, let url = entry.snapshot.actionURL(URLComponents(string: target)), !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Link(destination: url) {
                    Text(title)
                        .font(Font(font))
                        .foregroundColor(color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(title)
                    .font(Font(font))
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func plannedHomeBody(availableWidth: Double, availableHeight: Double) -> some View {
        let pSize: CGFloat = family == .systemSmall ? 15 : 17
        let sSize: CGFloat = family == .systemSmall ? 11 : 12

        let primaryFont = DuoyiWidgetTypographyMetrics.font(baseSize: pSize, weight: .regular, textStyle: .body, category: uiCategory)
        let secondaryFont = DuoyiWidgetTypographyMetrics.font(baseSize: sSize, weight: .regular, textStyle: .subheadline, category: uiCategory)
        let completionFont = DuoyiWidgetTypographyMetrics.font(baseSize: 18, weight: .regular, textStyle: .body, category: uiCategory)
        let footerFont = DuoyiWidgetTypographyMetrics.font(baseSize: 10, weight: .regular, textStyle: .caption2, category: uiCategory)
        let focusClockFont = DuoyiWidgetTypographyMetrics.font(baseSize: pSize, weight: .regular, textStyle: .body, category: uiCategory, rounded: true, monospacedDigits: true)
        let focusStatusFont = DuoyiWidgetTypographyMetrics.font(baseSize: sSize, weight: .regular, textStyle: .subheadline, category: uiCategory)

        let headerFonts = HeaderFonts(
            title: DuoyiWidgetTypographyMetrics.font(baseSize: 13, weight: .regular, textStyle: .headline, category: uiCategory),
            count: DuoyiWidgetTypographyMetrics.font(baseSize: 11, weight: .regular, textStyle: .caption1, category: uiCategory),
            brand: DuoyiWidgetTypographyMetrics.font(baseSize: 10, weight: .regular, textStyle: .caption2, category: uiCategory),
            quickAction: DuoyiWidgetTypographyMetrics.font(baseSize: 10, weight: .regular, textStyle: .caption1, category: uiCategory)
        )

        let isValidGeometry = availableWidth.isFinite && availableWidth > 0 &&
                              availableHeight.isFinite && availableHeight > 0 &&
                              pixelScale.isFinite && pixelScale > 0

        if !isValidGeometry {
            plannedStandaloneFallbackView(font: primaryFont, availableWidth: 0, availableHeight: 0, fits: false)
        } else {
            let fallbackText = entry.locale == .en ? "Open in app" : "在应用中打开"
            let fallbackH: Double? = {
                let singleW = DuoyiWidgetTypographyMetrics.width(fallbackText, font: primaryFont, pixelScale: pixelScale)
                if singleW <= availableWidth {
                    return DuoyiWidgetTypographyMetrics.lineHeight(primaryFont, pixelScale: pixelScale)
                } else {
                    return DuoyiWidgetTypographyMetrics.wrappedHeight(fallbackText, font: primaryFont, availableWidth: availableWidth, pixelScale: pixelScale)
                }
            }()
            let fallbackHeight = fallbackH ?? (availableHeight + 1000)
            let fallbackFits = fallbackH != nil && fallbackH! <= availableHeight

            let (headerMode, headerH) = measureHeader(availableWidth: availableWidth, fonts: headerFonts)
            let contentGap: Double = Double(spacing)

            #if canImport(UIKit)
            let completionActionSize = DuoyiWidgetTypographyMetrics.symbolActionSize(font: completionFont, pixelScale: pixelScale)
            #else
            let completionActionSize = CGSize(width: 18, height: 18)
            #endif
            let completionActionWidth = Double(completionActionSize.width)
            let completionActionHeight = Double(completionActionSize.height)
            let completionGap = 6.0

            let widgetProgressPercent: Int? = {
                guard family != .systemSmall && entry.displayMode != "compact" else { return nil }
                switch entry.config.kind {
                case "DuoyiGoalWidget": return entry.goalProgressPercent
                case "DuoyiHabitWidget": return entry.habitPercent
                case "DuoyiFocusWidget": return entry.focusProgressPercent
                default: return nil
                }
            }()

            let basePrimaryH: Double = {
                if entry.config.kind == "DuoyiTodoWidget" {
                    if let first = entry.todoRows.first {
                        let hasCompletion = supportsItemLinks && (first.completeURL != nil)
                        let usableW = hasCompletion ? max(0, availableWidth - completionActionWidth - completionGap) : availableWidth
                        guard usableW > 0 else { return availableHeight + 1000 }
                        let clean = cleanRow(first.title)
                        guard let textH = DuoyiWidgetTypographyMetrics.wrappedHeight(clean, font: primaryFont, availableWidth: usableW, pixelScale: pixelScale) else {
                            return availableHeight + 1000
                        }
                        return max(textH, hasCompletion ? completionActionHeight : 0.0)
                    } else {
                        let clean = cleanRow(entry.primary)
                        return DuoyiWidgetTypographyMetrics.wrappedHeight(clean, font: primaryFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? (availableHeight + 1000)
                    }
                } else if entry.config.kind == "DuoyiFocusWidget" {
                    if let clockSample = entry.focusTimer.conservativeClockSample(at: entry.date, locale: DuoyiFocusTimerState.timerClockLocale) {
                        let clockW = DuoyiWidgetTypographyMetrics.width(clockSample, font: focusClockFont, pixelScale: pixelScale)
                        guard clockW <= availableWidth else { return availableHeight + 1000 }
                        let clockH = DuoyiWidgetTypographyMetrics.lineHeight(focusClockFont, pixelScale: pixelScale)
                        let statusH = DuoyiWidgetTypographyMetrics.wrappedHeight(focusStatusLabel, font: focusStatusFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? DuoyiWidgetTypographyMetrics.lineHeight(focusStatusFont, pixelScale: pixelScale)
                        return clockH + 4.0 + statusH
                    } else {
                        let clean = cleanRow(entry.primary)
                        return DuoyiWidgetTypographyMetrics.wrappedHeight(clean, font: primaryFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? (availableHeight + 1000)
                    }
                } else {
                    let clean = cleanRow(entry.primary)
                    return DuoyiWidgetTypographyMetrics.wrappedHeight(clean, font: primaryFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? (availableHeight + 1000)
                }
            }()
            let primaryH = basePrimaryH + (widgetProgressPercent != nil ? 8.0 : 0.0)

            let secondaryH: [Double] = {
                if entry.config.kind == "DuoyiTodoWidget" {
                    return entry.todoRows.dropFirst().map { row in
                        let hasCompletion = supportsItemLinks && (row.completeURL != nil)
                        let usableW = hasCompletion ? max(0, availableWidth - completionActionWidth - completionGap) : availableWidth
                        guard usableW > 0 else { return availableHeight + 1000 }
                        let clean = cleanRow(row.title)
                        guard let textH = DuoyiWidgetTypographyMetrics.wrappedHeight(clean, font: secondaryFont, availableWidth: usableW, pixelScale: pixelScale) else {
                            return availableHeight + 1000
                        }
                        return max(textH, hasCompletion ? completionActionHeight : 0.0)
                    }
                } else {
                    return entry.rows.map { row in
                        let clean = cleanRow(row.title)
                        return DuoyiWidgetTypographyMetrics.wrappedHeight(clean, font: secondaryFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? 0.0
                    }
                }
            }()

            let secondaryGap: Double = entry.config.kind == "DuoyiTodoWidget" ? 5.0 : 4.0

            let footerLabels = [entry.navTodo, entry.navHabit, entry.navCalendar, entry.navFocus]
            let footerWidths = footerLabels.map { DuoyiWidgetTypographyMetrics.width($0, font: footerFont, pixelScale: pixelScale) }
            let footerH = DuoyiWidgetTypographyMetrics.lineHeight(footerFont, pixelScale: pixelScale) + 6.0

            let familyKind: String = {
                if family == .systemSmall { return "systemSmall" }
                if family == .systemMedium { return "systemMedium" }
                if family == .systemLarge { return "systemLarge" }
                if #available(iOSApplicationExtension 15.0, *), family == .systemExtraLarge { return "systemExtraLarge" }
                return "other"
            }()

            if case .overflow = headerMode {
                plannedStandaloneFallbackView(font: primaryFont, availableWidth: availableWidth, availableHeight: availableHeight, fits: fallbackFits)
            } else if let plan = DuoyiWidgetTypographyLayoutCore.rows(
                familyKind: familyKind,
                displayMode: entry.displayMode,
                primaryKind: entry.config.kind,
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                headerHeight: headerH,
                primaryHeight: primaryH,
                secondaryHeights: secondaryH,
                contentSpacing: contentGap,
                secondarySpacing: secondaryGap,
                footerLabelWidths: footerWidths,
                footerHeight: footerH,
                footerHorizontalPadding: 6.0,
                footerSpacing: 8.0,
                fallbackHeight: fallbackHeight
            ) {
                if plan.usesFallback {
                    plannedStandaloneFallbackView(font: primaryFont, availableWidth: availableWidth, availableHeight: availableHeight, fits: plan.usedHeight > 0)
                } else if plan.showsPrimary {
                    VStack(alignment: .leading, spacing: 0) {
                        plannedHeaderView(mode: headerMode, fonts: headerFonts)
                        Spacer().frame(height: CGFloat(contentGap))

                        VStack(alignment: .leading, spacing: 0) {
                            if entry.config.kind == "DuoyiTodoWidget" {
                                if let first = entry.todoRows.first {
                                    plannedTodoRow(first, primary: true, primaryFont: primaryFont, secondaryFont: secondaryFont, completionFont: completionFont, completionActionSize: completionActionSize)
                                } else {
                                    Text(cleanRow(entry.primary))
                                        .font(Font(primaryFont))
                                        .foregroundColor(entry.theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                ForEach(plan.visibleSecondaryIndices, id: \.self) { idx in
                                    Spacer().frame(height: CGFloat(secondaryGap))
                                    let row = Array(entry.todoRows.dropFirst())[idx]
                                    plannedTodoRow(row, primary: false, primaryFont: primaryFont, secondaryFont: secondaryFont, completionFont: completionFont, completionActionSize: completionActionSize)
                                }
                            } else if entry.config.kind == "DuoyiFocusWidget" {
                                if entry.focusTimer.display(at: entry.date) != .fallback {
                                    focusClock(entry.focusTimer.display(at: entry.date))
                                        .font(Font(focusClockFont))
                                        .foregroundColor(entry.theme.readablePrimary)
                                    Spacer().frame(height: 4.0)
                                    Text(focusStatusLabel)
                                        .font(Font(focusStatusFont))
                                        .foregroundColor(entry.theme.readableMutedText)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    plannedLinkedText(cleanRow(entry.primary), target: entry.primaryTarget, font: primaryFont, isPrimary: true)
                                }
                                if let progressPercent = widgetProgressPercent {
                                    plannedProgressCapsule(percent: progressPercent)
                                }
                                ForEach(plan.visibleSecondaryIndices, id: \.self) { idx in
                                    Spacer().frame(height: CGFloat(secondaryGap))
                                    let row = entry.rows[idx]
                                    plannedLinkedText(cleanRow(row.title), target: row.target, font: secondaryFont, isPrimary: false)
                                }
                            } else {
                                plannedLinkedText(cleanRow(entry.primary), target: entry.primaryTarget, font: primaryFont, isPrimary: true)
                                if let progressPercent = widgetProgressPercent {
                                    plannedProgressCapsule(percent: progressPercent)
                                }
                                ForEach(plan.visibleSecondaryIndices, id: \.self) { idx in
                                    Spacer().frame(height: CGFloat(secondaryGap))
                                    let row = entry.rows[idx]
                                    plannedLinkedText(cleanRow(row.title), target: row.target, font: secondaryFont, isPrimary: false)
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        if plan.showsFooter {
                            Spacer().frame(height: CGFloat(contentGap))
                            plannedFooterView(footerFont: footerFont)
                        }
                    }
                } else {
                    plannedStandaloneFallbackView(font: primaryFont, availableWidth: availableWidth, availableHeight: availableHeight, fits: fallbackFits)
                }
            } else {
                plannedStandaloneFallbackView(font: primaryFont, availableWidth: availableWidth, availableHeight: availableHeight, fits: fallbackFits)
            }
        }
    }

    @ViewBuilder
    private func plannedCalendarBody(availableWidth: Double, availableHeight: Double) -> some View {
        let mSize: CGFloat = family == .systemSmall ? 11 : 12
        let wSize: CGFloat = family == .systemSmall ? 8 : 9.5
        let dSize: CGFloat = family == .systemSmall ? 9 : 10.5
        let sumSize: CGFloat = family == .systemSmall ? 11 : 12
        let pSize: CGFloat = family == .systemSmall ? 15 : 17

        let monthFont = DuoyiWidgetTypographyMetrics.font(baseSize: mSize, weight: .regular, textStyle: .headline, category: uiCategory)
        let weekdayFont = DuoyiWidgetTypographyMetrics.font(baseSize: wSize, weight: .regular, textStyle: .caption2, category: uiCategory)
        let dayFont = DuoyiWidgetTypographyMetrics.font(baseSize: dSize, weight: .regular, textStyle: .caption1, category: uiCategory)
        let summaryFont = DuoyiWidgetTypographyMetrics.font(baseSize: sumSize, weight: .regular, textStyle: .subheadline, category: uiCategory)
        let primaryFont = DuoyiWidgetTypographyMetrics.font(baseSize: pSize, weight: .regular, textStyle: .body, category: uiCategory)
        let footerFont = DuoyiWidgetTypographyMetrics.font(baseSize: 10, weight: .regular, textStyle: .caption2, category: uiCategory)

        let headerFonts = HeaderFonts(
            title: DuoyiWidgetTypographyMetrics.font(baseSize: 13, weight: .regular, textStyle: .headline, category: uiCategory),
            count: DuoyiWidgetTypographyMetrics.font(baseSize: 11, weight: .regular, textStyle: .caption1, category: uiCategory),
            brand: DuoyiWidgetTypographyMetrics.font(baseSize: 10, weight: .regular, textStyle: .caption2, category: uiCategory),
            quickAction: DuoyiWidgetTypographyMetrics.font(baseSize: 10, weight: .regular, textStyle: .caption1, category: uiCategory)
        )

        let staleHint = !entry.isDailyFresh ? (entry.locale == .zh ? "今日数据待刷新" : "Today’s data pending refresh") : ""

        let isValidGeometry = availableWidth.isFinite && availableWidth > 0 &&
                              availableHeight.isFinite && availableHeight > 0 &&
                              pixelScale.isFinite && pixelScale > 0

        if !isValidGeometry {
            plannedStandaloneFallbackView(
                font: primaryFont,
                availableWidth: 0,
                availableHeight: 0,
                fits: false,
                staleHint: staleHint
            )
        } else {
            let fallbackText = entry.locale == .en ? "Open in app" : "在应用中打开"
            let fallbackH: Double? = {
                let singleW = DuoyiWidgetTypographyMetrics.width(fallbackText, font: primaryFont, pixelScale: pixelScale)
                if singleW <= availableWidth {
                    return DuoyiWidgetTypographyMetrics.lineHeight(primaryFont, pixelScale: pixelScale)
                } else {
                    return DuoyiWidgetTypographyMetrics.wrappedHeight(fallbackText, font: primaryFont, availableWidth: availableWidth, pixelScale: pixelScale)
                }
            }()
            let fallbackHeight = fallbackH ?? (availableHeight + 1000)
            let fallbackFits = fallbackH != nil && fallbackH! <= availableHeight

            let (headerMode, headerH) = measureHeader(availableWidth: availableWidth, fonts: headerFonts)
            let contentGap: Double = Double(spacing)

            let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
                anchorDate: entry.date,
                timeZone: .current,
                isZh: entry.locale == .zh,
                firstDayOfWeek: entry.firstDayOfWeek
            )
            let currentWeek = min(max(0, (grid.firstWeekdayOffset + grid.todayDay - 1) / 7), 5)
            let totalWeeks = min(6, (grid.firstWeekdayOffset + grid.daysInMonth - 1) / 7 + 1)

            let lunarSummary: String? = {
                guard family != .systemSmall && entry.isDailyFresh else { return nil }
                let clean = cleanRow(entry.primary)
                if clean.isEmpty ||
                    clean == grid.monthTitle ||
                    clean == "本月日期 · 今日已标记" ||
                    clean == "Month view · today is marked" ||
                    clean == "Monthly view · Today marked" {
                    return nil
                }
                return clean
            }()
            let baseMonthTitleH = DuoyiWidgetTypographyMetrics.wrappedHeight(grid.monthTitle, font: monthFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? DuoyiWidgetTypographyMetrics.lineHeight(monthFont, pixelScale: pixelScale)
            let lunarSummaryH = lunarSummary.map {
                (DuoyiWidgetTypographyMetrics.wrappedHeight($0, font: weekdayFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? DuoyiWidgetTypographyMetrics.lineHeight(weekdayFont, pixelScale: pixelScale)) + 2.0
            } ?? 0.0
            let monthTitleH = baseMonthTitleH + lunarSummaryH
            let weekdayHeaderH = DuoyiWidgetTypographyMetrics.lineHeight(weekdayFont, pixelScale: pixelScale)
            let dayLineH = DuoyiWidgetTypographyMetrics.lineHeight(dayFont, pixelScale: pixelScale)
            let maxDayW = (1...31).map { DuoyiWidgetTypographyMetrics.width("\($0)", font: dayFont, pixelScale: pixelScale) }.max() ?? 0.0
            let maxWeekdayW = grid.weekdayHeaders.map { DuoyiWidgetTypographyMetrics.width($0, font: weekdayFont, pixelScale: pixelScale) }.max() ?? 0.0

            let daySquare = max(family == .systemSmall ? 13.0 : 15.0, dayLineH, maxDayW)
            let cellH = daySquare
            let widestCell = max(maxWeekdayW, daySquare)

            let hasEventSummary: Bool = {
                if !entry.isDailyFresh { return true }
                if family == .systemSmall { return false }
                return entry.calendarEventSummary != nil && !entry.calendarEventSummary!.isEmpty
            }()
            let rawSummaryText: String = {
                if let s = entry.calendarEventSummary, !s.isEmpty { return s }
                return entry.locale == .zh ? "今日数据待刷新" : "Today’s data pending refresh"
            }()
            let cleanSummaryText = cleanRow(rawSummaryText)
            let summaryH: Double = hasEventSummary ? (DuoyiWidgetTypographyMetrics.wrappedHeight(cleanSummaryText, font: summaryFont, availableWidth: availableWidth, pixelScale: pixelScale) ?? DuoyiWidgetTypographyMetrics.lineHeight(summaryFont, pixelScale: pixelScale)) : 0.0

            let rowSpacing: Double = family == .systemSmall ? 1.0 : 2.0
            let calendarContentSpacing: Double = family == .systemSmall ? 2.0 : 4.0

            let familyKind: String = {
                if family == .systemSmall { return "systemSmall" }
                if family == .systemMedium { return "systemMedium" }
                if family == .systemLarge { return "systemLarge" }
                if #available(iOSApplicationExtension 15.0, *), family == .systemExtraLarge { return "systemExtraLarge" }
                return "other"
            }()

            let calendarBodyAvailableH = max(0, availableHeight - headerH - contentGap)

            let calendarPlan = DuoyiWidgetTypographyLayoutCore.calendar(
                familyKind: familyKind,
                displayMode: entry.displayMode,
                currentWeek: currentWeek,
                totalWeeks: totalWeeks,
                availableWidth: availableWidth,
                availableHeight: calendarBodyAvailableH,
                monthTitleHeight: monthTitleH,
                weekdayHeaderHeight: weekdayHeaderH,
                eventSummaryHeight: summaryH,
                hasEventSummary: hasEventSummary,
                cellHeight: cellH,
                maximumCellWidth: widestCell,
                rowSpacing: rowSpacing,
                contentSpacing: calendarContentSpacing,
                fallbackHeight: fallbackHeight
            )

            let footerLabels = [entry.navTodo, entry.navHabit, entry.navCalendar, entry.navFocus]
            let footerWidths = footerLabels.map { DuoyiWidgetTypographyMetrics.width($0, font: footerFont, pixelScale: pixelScale) }
            let footerH = DuoyiWidgetTypographyMetrics.lineHeight(footerFont, pixelScale: pixelScale) + 6.0

            let rowPlan = DuoyiWidgetTypographyLayoutCore.rows(
                familyKind: familyKind,
                displayMode: entry.displayMode,
                primaryKind: "DuoyiCalendarWidget",
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                headerHeight: headerH,
                primaryHeight: calendarPlan?.usedHeight ?? (availableHeight + 1000),
                secondaryHeights: [],
                contentSpacing: contentGap,
                secondarySpacing: 0,
                footerLabelWidths: footerWidths,
                footerHeight: footerH,
                footerHorizontalPadding: 6.0,
                footerSpacing: 8.0,
                fallbackHeight: fallbackHeight
            )

            if case .overflow = headerMode {
                plannedStandaloneFallbackView(
                    font: primaryFont,
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    fits: fallbackFits,
                    staleHint: staleHint
                )
            } else if rowPlan == nil || rowPlan?.usesFallback == true {
                plannedStandaloneFallbackView(
                    font: primaryFont,
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    fits: (rowPlan?.usedHeight ?? 0) > 0,
                    staleHint: staleHint
                )
            } else if let cPlan = calendarPlan, !cPlan.showsDateFallback {
                VStack(alignment: .leading, spacing: 0) {
                    plannedHeaderView(mode: headerMode, fonts: headerFonts)
                    Spacer().frame(height: CGFloat(contentGap))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(grid.monthTitle)
                            .font(Font(monthFont))
                            .foregroundColor(entry.theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let lunarSummary = lunarSummary {
                            Text(lunarSummary)
                                .font(Font(weekdayFont))
                                .foregroundColor(entry.theme.readablePrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2.0)
                        }

                        Spacer().frame(height: CGFloat(calendarContentSpacing))

                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                Text(grid.weekdayHeaders[col])
                                    .accessibilityLabel(DuoyiWidgetDisplayCore.calendarWeekdayHeaders(
                                        isZh: entry.locale == .zh, firstDayOfWeek: entry.firstDayOfWeek, full: true
                                    )[col])
                                    .font(Font(weekdayFont))
                                    .foregroundColor(entry.theme.readableMutedText)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        Spacer().frame(height: CGFloat(calendarContentSpacing))

                        VStack(spacing: CGFloat(rowSpacing)) {
                            ForEach(cPlan.visibleWeeks, id: \.self) { week in
                                HStack(spacing: 0) {
                                    ForEach(0..<7, id: \.self) { col in
                                        let cell = grid.cells[week * 7 + col]
                                        plannedCalendarDayCell(
                                            cell: cell,
                                            grid: grid,
                                            cellFont: dayFont,
                                            cellHeight: cellH
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }

                        if cPlan.showsEventSummary {
                            Spacer().frame(height: CGFloat(calendarContentSpacing))
                            plannedLinkedText(cleanSummaryText, target: entry.calendarEventTarget, font: summaryFont, isPrimary: false)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityHint(staleHint)

                    Spacer(minLength: 0)

                    if rowPlan?.showsFooter == true {
                        Spacer().frame(height: CGFloat(contentGap))
                        plannedFooterView(footerFont: footerFont)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    plannedHeaderView(mode: headerMode, fonts: headerFonts)
                    Spacer().frame(height: CGFloat(contentGap))
                    plannedStandaloneFallbackView(
                        font: primaryFont,
                        availableWidth: availableWidth,
                        availableHeight: calendarBodyAvailableH,
                        fits: (calendarPlan?.usedHeight ?? 0) > 0,
                        staleHint: staleHint
                    )
                    Spacer(minLength: 0)
                    if rowPlan?.showsFooter == true {
                        Spacer().frame(height: CGFloat(contentGap))
                        plannedFooterView(footerFont: footerFont)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityHint(staleHint)
            }
        }
    }

    private func plannedCalendarDayCell(
        cell: DuoyiMonthCell,
        grid: DuoyiMonthGridModel,
        cellFont: UIFont,
        cellHeight: Double
    ) -> some View {
        Group {
            if cell.dayNumber > 0 {
                let label = DuoyiWidgetDisplayCore.cellAccessibilityLabel(
                    year: grid.year,
                    month: grid.month,
                    day: cell.dayNumber,
                    isToday: cell.isToday,
                    isZh: entry.locale == .zh
                )
                let dayLabel = Group {
                    if cell.isToday {
                        Text("\(cell.dayNumber)")
                            .font(Font(cellFont))
                            .foregroundColor(entry.theme.readableOnPrimary)
                            .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                            .background(Circle().fill(entry.theme.primary))
                            .accessibilityLabel(label)
                            .accessibilityAddTraits(.isSelected)
                    } else {
                        Text("\(cell.dayNumber)")
                            .font(Font(cellFont))
                            .foregroundColor(entry.theme.text)
                            .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                            .accessibilityLabel(label)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(cellHeight))
                .contentShape(Rectangle())

                if supportsItemLinks, let target = cell.target,
                   let url = entry.snapshot.actionURL(URLComponents(string: target)) {
                    Link(destination: url) {
                        dayLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    dayLabel
                }
            } else {
                Text("")
                    .font(Font(cellFont))
                    .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                    .accessibilityHidden(true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.theme.primary)
                .frame(width: 8, height: 8)
            Text(entry.config.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(entry.theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if entry.config.kind == "DuoyiTodoWidget", let count = entry.todoCount {
                Text(DuoyiWidgetDisplayCore.todoCountLabel(count, isZh: entry.locale == .zh))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(entry.theme.readablePrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
            Text(entry.brandTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(entry.theme.readableMutedText)
                .lineLimit(1)
                .truncationMode(.tail)
            if supportsItemLinks, let quickURL {
                Link(destination: quickURL) {
                    Text(quickActionTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(entry.theme.readablePrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                                .fill(entry.theme.navBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                                .strokeBorder(entry.theme.border, lineWidth: entry.theme.borderWidth > 0 ? entry.theme.borderWidth : 0)
                        )
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

    private func calendarContent(availableHeight: Double) -> some View {
        let grid = DuoyiWidgetDisplayCore.buildMonthGrid(
            anchorDate: entry.date,
            timeZone: .current,
            isZh: entry.locale == .zh,
            firstDayOfWeek: entry.firstDayOfWeek
        )
        let currentWeek = min(max(0, (grid.firstWeekdayOffset + grid.todayDay - 1) / 7), 5)
        let totalWeeks = min(6, (grid.firstWeekdayOffset + grid.daysInMonth - 1) / 7 + 1)
        let showEventSummary: Bool = {
            if !entry.isDailyFresh {
                return true
            }
            if family == .systemSmall {
                return false
            }
            return entry.calendarEventSummary != nil && !entry.calendarEventSummary!.isEmpty
        }()
        let familyKind: String = {
            if family == .systemSmall { return "systemSmall" }
            if family == .systemMedium { return "systemMedium" }
            if family == .systemLarge { return "systemLarge" }
            return "other"
        }()

        let cellHeight: Double = family == .systemSmall ? 13 : 15
        let cellFontSize: CGFloat = family == .systemSmall ? 9 : 10.5
        let headerFontSize: CGFloat = family == .systemSmall ? 8 : 9.5
        let monthTitleHeight: Double = family == .systemSmall ? 14 : 16
        let weekdayHeaderHeight: Double = family == .systemSmall ? 12 : 14
        let eventSummaryHeight: Double = family == .systemSmall ? 13 : 15
        let rowSpacing: Double = family == .systemSmall ? 1 : 2
        let contentSpacing: Double = family == .systemSmall ? 2 : 4

        let visibleWeekRange = DuoyiWidgetDisplayCore.budgetedVisibleWeekRange(
            familyKind: familyKind,
            displayMode: entry.displayMode,
            currentWeek: currentWeek,
            totalWeeks: totalWeeks,
            hasEventSummary: showEventSummary,
            availableHeight: availableHeight,
            monthTitleHeight: monthTitleHeight,
            weekdayHeaderHeight: weekdayHeaderHeight,
            eventSummaryHeight: eventSummaryHeight,
            cellHeight: cellHeight,
            rowSpacing: rowSpacing,
            contentSpacing: contentSpacing
        )

        return VStack(alignment: .leading, spacing: CGFloat(contentSpacing)) {
            Text(grid.monthTitle)
                .font(.system(size: family == .systemSmall ? 11 : 12, weight: .semibold))
                .foregroundColor(entry.theme.text)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { col in
                    Text(grid.weekdayHeaders[col])
                        .accessibilityLabel(DuoyiWidgetDisplayCore.calendarWeekdayHeaders(
                            isZh: entry.locale == .zh, firstDayOfWeek: entry.firstDayOfWeek, full: true
                        )[col])
                        .font(.system(size: headerFontSize, weight: .regular))
                        .foregroundColor(entry.theme.readableMutedText)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: CGFloat(rowSpacing)) {
                ForEach(visibleWeekRange, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let cell = grid.cells[week * 7 + col]
                            calendarDayCell(
                                cell: cell,
                                grid: grid,
                                cellFontSize: cellFontSize,
                                cellHeight: cellHeight
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            if showEventSummary {
                if let summary = entry.calendarEventSummary, !summary.isEmpty {
                    linkedText(summary, target: entry.calendarEventTarget, primary: false)
                } else if !entry.isDailyFresh {
                    linkedText(
                        entry.locale == .zh ? "今日数据待刷新" : "Today’s data pending refresh",
                        target: entry.calendarEventTarget,
                        primary: false
                    )
                }
            }
        }
    }

    private func calendarDayCell(
        cell: DuoyiMonthCell,
        grid: DuoyiMonthGridModel,
        cellFontSize: CGFloat,
        cellHeight: Double
    ) -> some View {
        Group {
            if cell.dayNumber > 0 {
                let label = DuoyiWidgetDisplayCore.cellAccessibilityLabel(
                    year: grid.year,
                    month: grid.month,
                    day: cell.dayNumber,
                    isToday: cell.isToday,
                    isZh: entry.locale == .zh
                )
                let dayLabel = Group {
                    if cell.isToday {
                        Text("\(cell.dayNumber)")
                            .font(.system(size: cellFontSize, weight: .medium))
                            .foregroundColor(entry.theme.readableOnPrimary)
                            .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                            .background(Circle().fill(entry.theme.primary))
                            .accessibilityLabel(label)
                            .accessibilityAddTraits(.isSelected)
                    } else {
                        Text("\(cell.dayNumber)")
                            .font(.system(size: cellFontSize, weight: .regular))
                            .foregroundColor(entry.theme.text)
                            .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                            .accessibilityLabel(label)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(cellHeight))
                .contentShape(Rectangle())

                if supportsItemLinks, let target = cell.target,
                   let url = entry.snapshot.actionURL(URLComponents(string: target)) {
                    Link(destination: url) {
                        dayLabel
                    }
                    .buttonStyle(.plain)
                } else {
                    dayLabel
                }
            } else {
                Text("")
                    .font(.system(size: cellFontSize))
                    .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                    .accessibilityHidden(true)
            }
        }
    }

    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.focusTimer.display(at: entry.date) != .fallback {
                focusClock(entry.focusTimer.display(at: entry.date))
                    .font(.system(size: primarySize, weight: .semibold, design: .rounded))
                    .duoyiMonospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                    .foregroundColor(entry.theme.readablePrimary)
                Text(focusStatusLabel)
                    .font(.system(size: rowSize, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(entry.theme.readableMutedText)
            } else {
                linkedText(entry.primary, target: entry.primaryTarget, primary: true)
            }
            ForEach(visibleRows) { row in
                linkedText(row.title, target: row.target, primary: false)
            }
        }
    }

    @ViewBuilder
    private func focusClock(_ display: DuoyiFocusTimerDisplay) -> some View {
        switch display {
        case .fallback:
            EmptyView()
        case .fixed(let clock):
            Text(clock)
                .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        case .countdown(let end):
            if #available(iOSApplicationExtension 16.0, *) {
                Text(timerInterval: entry.date...end, countsDown: true)
                    .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
            } else {
                Text(end, style: .timer)
                    .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
            }
        case .countUp(let start, let cap):
            if #available(iOSApplicationExtension 16.0, *) {
                Text(timerInterval: start...cap, countsDown: false)
                    .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
            } else {
                Text(start, style: .timer)
                    .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
            }
        }
    }

    private var focusStatusLabel: String {
        switch entry.focusTimer.phase {
        case .pausedCountdown, .pausedCountUp:
            return (entry.locale == .en ? "Paused · " : "已暂停 · ") + entry.focusTimerLabel
        case .ended:
            return (entry.locale == .en ? "Finished · " : "已结束 · ") + entry.focusTimerLabel
        default:
            return entry.focusTimerLabel
        }
    }

    private var widgetRootURL: URL? {
        let moduleURL = URL(string: entry.config.deepLink)
        guard family == .systemSmall || isAccessoryFamily else {
            return moduleURL
        }
        if entry.config.kind == "DuoyiTodoWidget" {
            guard entry.isDailyFresh,
                  let first = entry.todoRows.first else {
                return moduleURL
            }
            return first.detailURL ?? moduleURL
        }
        if entry.config.kind == "DuoyiNoteWidget" {
            guard entry.isDailyFresh,
                  let components = URLComponents(string: entry.primaryTarget),
                  components.scheme?.lowercased() == "duoyi",
                  components.host?.lowercased() == "note",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.query == nil else {
                return moduleURL
            }
            let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 2,
                  segments[0].isEmpty,
                  !segments[1].isEmpty,
                  let decodedId = String(segments[1]).removingPercentEncoding,
                  !decodedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return moduleURL
            }
            return entry.snapshot.actionURL(components) ?? moduleURL
        }
        if entry.config.kind == "DuoyiGoalWidget" {
            guard entry.isDailyFresh,
                  let components = URLComponents(string: entry.primaryTarget),
                  components.scheme?.lowercased() == "duoyi",
                  components.host?.lowercased() == "goal",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.query == nil else {
                return moduleURL
            }
            let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 2,
                  segments[0].isEmpty,
                  !segments[1].isEmpty,
                  let decodedId = String(segments[1]).removingPercentEncoding,
                  !decodedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return moduleURL
            }
            return entry.snapshot.actionURL(components) ?? moduleURL
        }
        if entry.config.kind == "DuoyiDiaryWidget" {
            guard entry.isDailyFresh,
                  let components = URLComponents(string: entry.primaryTarget),
                  components.scheme?.lowercased() == "duoyi",
                  components.host?.lowercased() == "diary",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.query == nil else {
                return moduleURL
            }
            let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 2,
                  segments[0].isEmpty,
                  !segments[1].isEmpty,
                  let decodedId = String(segments[1]).removingPercentEncoding,
                  !decodedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return moduleURL
            }
            return entry.snapshot.actionURL(components) ?? moduleURL
        }
        if entry.config.kind == "DuoyiAnniversaryWidget" {
            guard entry.isDailyFresh,
                  let components = URLComponents(string: entry.primaryTarget),
                  components.scheme?.lowercased() == "duoyi",
                  components.host?.lowercased() == "anniversary",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.query == nil else {
                return moduleURL
            }
            let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 2,
                  segments[0].isEmpty,
                  !segments[1].isEmpty,
                  let decodedId = String(segments[1]).removingPercentEncoding,
                  !decodedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return moduleURL
            }
            return entry.snapshot.actionURL(components) ?? moduleURL
        }
        if entry.config.kind == "DuoyiScheduleWidget" {
            guard entry.isDailyFresh,
                  entry.snapshot.isFresh(at: Date()),
                  let components = URLComponents(string: entry.primaryTarget),
                  components.scheme?.lowercased() == "duoyi",
                  let host = components.host?.lowercased(),
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.query == nil else {
                return moduleURL
            }
            if host == "calendar" || host == "focus" {
                return components.percentEncodedPath.isEmpty ? components.url : moduleURL
            }
            guard ["todo", "habit", "anniversary", "course", "diary", "goal", "countdown", "time-entry", "event", "pomodoro"].contains(host) else {
                return moduleURL
            }
            let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 2,
                  segments[0].isEmpty,
                  !segments[1].isEmpty,
                  let decodedId = String(segments[1]).removingPercentEncoding,
                  !decodedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return moduleURL
            }
            return entry.snapshot.actionURL(components) ?? moduleURL
        }
        if entry.config.kind == "DuoyiCourseWidget" {
            guard entry.isDailyFresh,
                  let components = URLComponents(string: entry.primaryTarget),
                  components.scheme?.lowercased() == "duoyi",
                  components.host?.lowercased() == "course",
                  components.user == nil,
                  components.password == nil,
                  components.port == nil,
                  components.fragment == nil,
                  components.query == nil else {
                return moduleURL
            }
            let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard segments.count == 2,
                  segments[0].isEmpty,
                  !segments[1].isEmpty,
                  let decodedId = String(segments[1]).removingPercentEncoding,
                  !decodedId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return moduleURL
            }
            return entry.snapshot.actionURL(components) ?? moduleURL
        }
        return moduleURL
    }

    private var supportsItemLinks: Bool {
        if family == .systemMedium || family == .systemLarge { return true }
        if #available(iOSApplicationExtension 15.0, *), family == .systemExtraLarge { return true }
        return false
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
            if supportsItemLinks, let url = entry.snapshot.actionURL(URLComponents(string: target)), !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            .foregroundColor(primary ? entry.theme.text : entry.theme.readableMutedText)
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
            if supportsItemLinks, let detailURL = row.detailURL {
                Link(destination: detailURL) {
                    todoText(row.title, primary: primary)
                }
            } else {
                todoText(row.title, primary: primary)
            }
            Spacer(minLength: 0)
            if supportsItemLinks, let completeURL = row.completeURL {
                Link(destination: completeURL) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(entry.theme.readablePrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityLabel(entry.locale == .en
                    ? "Complete task: \(cleanRow(row.title))"
                    : "完成待办：\(cleanRow(row.title))")
            }
        }
    }

    private func todoText(_ title: String, primary: Bool) -> some View {
        Text(cleanRow(title))
            .font(.system(size: primary ? primarySize : rowSize, weight: primary ? .semibold : .regular))
            .lineLimit(primary ? primaryLines : 1)
            .truncationMode(.tail)
            .foregroundColor(primary ? entry.theme.text : entry.theme.readableMutedText)
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if #available(iOSApplicationExtension 16.0, *) {
            switch family {
            case .accessoryInline:
                if let focusDisplay = accessoryFocusDisplay {
                    accessoryFocusInlineView(focusDisplay)
                } else if entry.config.kind == "DuoyiTodoWidget", let count = entry.todoCount {
                    let label = DuoyiWidgetDisplayCore.todoCountLabel(count, isZh: entry.locale == .zh)
                    Text(isKnownFallback(accessoryPrimaryText)
                         ? "\(entry.config.title) · \(label)"
                         : "\(entry.config.title) · \(label) · \(accessoryPrimaryText)")
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("\(entry.config.title) \(accessoryPrimaryText)")
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            case .accessoryCircular:
                if let focusDisplay = accessoryFocusDisplay {
                    ZStack {
                        AccessoryWidgetBackground()
                        GeometryReader { proxy in
                            accessoryFocusCircularBody(
                                display: focusDisplay,
                                availableWidth: Double(proxy.size.width),
                                availableHeight: Double(proxy.size.height)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }
                } else {
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
                }
            case .accessoryRectangular:
                if let focusDisplay = accessoryFocusDisplay {
                    GeometryReader { proxy in
                        accessoryFocusRectangularBody(
                            display: focusDisplay,
                            availableWidth: Double(proxy.size.width),
                            availableHeight: Double(proxy.size.height)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        if entry.config.kind == "DuoyiTodoWidget", let count = entry.todoCount {
                            Text("\(entry.config.title) · \(DuoyiWidgetDisplayCore.todoCountLabel(count, isZh: entry.locale == .zh))")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(entry.config.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
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

    private var accessoryFocusDisplay: DuoyiFocusTimerDisplay? {
        guard entry.config.kind == "DuoyiFocusWidget" else { return nil }
        let display = entry.focusTimer.display(at: entry.date)
        return display == .fallback ? nil : display
    }

    private var accessoryFocusSFSymbol: String {
        switch entry.focusTimer.phase {
        case .pausedCountdown, .pausedCountUp:
            return "pause.circle"
        case .ended:
            return "checkmark.circle"
        case .runningCountUp:
            return "stopwatch"
        case .runningCountdown, .unavailable, .idle:
            return "timer"
        }
    }

    private var accessoryFocusDirectionStatus: String {
        switch entry.focusTimer.phase {
        case .runningCountdown:
            return entry.locale == .en ? "Countdown remaining" : "倒计时剩余"
        case .runningCountUp:
            if entry.focusTimer.isAtCountUpCap {
                return entry.locale == .en ? "Count-up elapsed · 24h cap reached" : "正计时已用 · 已达24小时上限"
            }
            return entry.locale == .en ? "Count-up elapsed" : "正计时已用"
        case .pausedCountdown:
            return entry.locale == .en ? "Paused · Saved remaining" : "已暂停 · 已保存剩余"
        case .pausedCountUp:
            if entry.focusTimer.isAtCountUpCap {
                return entry.locale == .en ? "Paused · Saved elapsed · 24h cap" : "已暂停 · 已保存已用 · 24小时上限"
            }
            return entry.locale == .en ? "Paused · Saved elapsed" : "已暂停 · 已保存已用"
        case .ended:
            return entry.locale == .en ? "Finished · Countdown ended" : "已结束 · 倒计时结束"
        case .unavailable, .idle:
            return entry.locale == .en ? "Ready" : "未开始"
        }
    }

    private var accessoryFocusIsBuiltInLabel: Bool {
        switch entry.focusTimerLabel {
        case "专注倒计时", "Focus countdown",
             "正计时专注中", "Focus counting up",
             "短休息倒计时", "Short break countdown",
             "长休息倒计时", "Long break countdown":
            return true
        default:
            return false
        }
    }

    private var accessoryFocusRectangularStatusText: String {
        if accessoryFocusIsBuiltInLabel {
            switch entry.focusTimer.phase {
            case .pausedCountdown, .pausedCountUp:
                if entry.focusTimer.isAtCountUpCap {
                    return entry.locale == .en
                        ? "Paused · 24h cap · \(entry.focusTimerLabel)"
                        : "已暂停 · 24小时上限 · \(entry.focusTimerLabel)"
                }
                return focusStatusLabel
            case .ended:
                return focusStatusLabel
            case .runningCountUp:
                if entry.focusTimer.isAtCountUpCap {
                    return entry.locale == .en
                        ? "24h cap · \(entry.focusTimerLabel)"
                        : "已达24小时上限 · \(entry.focusTimerLabel)"
                }
                return entry.focusTimerLabel
            case .runningCountdown, .unavailable, .idle:
                return entry.focusTimerLabel
            }
        }
        switch entry.focusTimer.phase {
        case .runningCountdown:
            return (entry.locale == .en ? "Countdown · " : "倒计时 · ") + entry.focusTimerLabel
        case .runningCountUp:
            if entry.focusTimer.isAtCountUpCap {
                return (entry.locale == .en ? "24h cap · " : "24小时上限 · ") + entry.focusTimerLabel
            }
            return (entry.locale == .en ? "Count-up · " : "正计时 · ") + entry.focusTimerLabel
        case .pausedCountdown:
            return (entry.locale == .en ? "Paused · " : "已暂停 · ") + entry.focusTimerLabel
        case .pausedCountUp:
            if entry.focusTimer.isAtCountUpCap {
                return (entry.locale == .en ? "Paused · 24h cap · " : "已暂停 · 24小时上限 · ") + entry.focusTimerLabel
            }
            return (entry.locale == .en ? "Paused · Count-up · " : "已暂停 · 正计时 · ") + entry.focusTimerLabel
        case .ended:
            return (entry.locale == .en ? "Finished · " : "已结束 · ") + entry.focusTimerLabel
        case .unavailable, .idle:
            return entry.focusTimerLabel
        }
    }

    private var accessoryFocusShortStatus: String {
        switch entry.focusTimer.phase {
        case .pausedCountdown, .pausedCountUp:
            return entry.locale == .en ? "Paused" : "已暂停"
        case .ended:
            return entry.locale == .en ? "Finished" : "已结束"
        case .runningCountUp:
            if entry.focusTimer.isAtCountUpCap {
                return entry.locale == .en ? "24h cap" : "24h上限"
            }
            return entry.locale == .en ? "Count-up" : "正计时"
        case .runningCountdown:
            if entry.focusTimerLabel == "短休息倒计时" || entry.focusTimerLabel == "Short break countdown" {
                return entry.locale == .en ? "Break" : "短休息"
            }
            if entry.focusTimerLabel == "长休息倒计时" || entry.focusTimerLabel == "Long break countdown" {
                return entry.locale == .en ? "Break" : "长休息"
            }
            return entry.locale == .en ? "Focus" : "专注"
        case .unavailable, .idle:
            return entry.locale == .en ? "Ready" : "未开始"
        }
    }

    private var accessoryFocusCompactCue: String {
        switch entry.focusTimer.phase {
        case .pausedCountdown, .pausedCountUp:
            return entry.locale == .en ? "Paused" : "暂停"
        case .ended:
            return entry.locale == .en ? "Done" : "结束"
        case .runningCountUp:
            if entry.focusTimer.isAtCountUpCap {
                return "24h"
            }
            return entry.locale == .en ? "Up" : "正计时"
        case .runningCountdown, .unavailable, .idle:
            return entry.locale == .en ? "Focus" : "专注"
        }
    }

    private var accessoryFocusCircularStatusText: String {
        switch entry.focusTimer.phase {
        case .ended:
            return entry.locale == .en ? "Done" : "已结束"
        default:
            return accessoryFocusShortStatus
        }
    }

    private var accessoryFocusRecoveryTitle: String {
        entry.locale == .en ? "Open in app" : "在应用中打开"
    }

    private var accessoryFocusRecoveryCompactTitle: String {
        entry.locale == .en ? "Open" : "打开"
    }

    private var accessoryFocusRecoveryHint: String {
        entry.locale == .en
            ? "Clock cannot fit at current text size. Open Duoyi to view full focus timer."
            : "当前字体大小无法完整显示计时，打开多仪查看完整专注计时。"
    }

    private var accessoryFocusAccessibleDescriptionPrefix: String {
        "\(entry.config.title) · \(accessoryFocusDirectionStatus) · \(entry.focusTimerLabel)"
    }

    @available(iOSApplicationExtension 16.0, *)
    private func accessoryFocusAccessibilityText(
        _ display: DuoyiFocusTimerDisplay,
        recoveryNote: String? = nil
    ) -> Text {
        let status = accessoryFocusAccessibleDescriptionPrefix
        let suffix = recoveryNote.map { " · \($0)" } ?? ""
        switch display {
        case .fallback:
            return Text(verbatim: "\(status)\(suffix)")
        case .fixed(let clock):
            return Text(verbatim: "\(status) \(clock)\(suffix)")
        case .countdown(let end):
            return Text("\(status) \(Text(timerInterval: entry.date...end, countsDown: true))\(suffix)")
        case .countUp(let start, let cap):
            return Text("\(status) \(Text(timerInterval: start...cap, countsDown: false))\(suffix)")
        }
    }

    private func accessoryMeasuredSymbolSize(name: String, font: UIFont) -> CGSize? {
        let config = UIImage.SymbolConfiguration(font: font)
        guard let image = UIImage(systemName: name, withConfiguration: config) else {
            return nil
        }
        let w = DuoyiWidgetTypographyMetrics.roundUp(Double(image.size.width), scale: pixelScale)
        let h = DuoyiWidgetTypographyMetrics.roundUp(Double(image.size.height), scale: pixelScale)
        guard w.isFinite, h.isFinite, w > 0, h > 0 else {
            return nil
        }
        return CGSize(width: w, height: h)
    }

    private static func accessoryFitsInCircle(
        diameter: Double,
        inset: Double = 2.5,
        topWidth: Double,
        bottomWidth: Double = 0,
        totalHeight: Double
    ) -> Bool {
        guard diameter.isFinite, inset.isFinite,
              topWidth.isFinite, bottomWidth.isFinite, totalHeight.isFinite,
              diameter > 2.0 * inset,
              topWidth >= 0, bottomWidth >= 0, totalHeight > 0 else {
            return false
        }
        let safeDiameter = diameter - 2.0 * inset
        let maxDiameterSq = safeDiameter * safeDiameter
        return (topWidth * topWidth + totalHeight * totalHeight) <= maxDiameterSq &&
               (bottomWidth * bottomWidth + totalHeight * totalHeight) <= maxDiameterSq
    }

    // WidgetKit accessoryInline renders a single Text view rather than multi-Text stacks,
    // so live states interpolate the bounded timerInterval inside one Text under timerClockLocale.
    // Provisional nominal 148-point budget: admission only proves the measured complete conservative
    // sample (or an admitted recovery label) fits this nominal typography budget; narrower host
    // widths, actual inline height, and Apple WidgetKit fitting remain unverified.
    @available(iOSApplicationExtension 16.0, *)
    @ViewBuilder
    private func accessoryFocusInlineView(_ display: DuoyiFocusTimerDisplay) -> some View {
        let inlineMaxWidth: Double = 148.0
        let inlineFont = DuoyiWidgetTypographyMetrics.font(
            baseSize: 12.0,
            weight: .semibold,
            textStyle: .caption2,
            category: uiCategory,
            rounded: false,
            monospacedDigits: true
        )
        let clockSample = entry.focusTimer.conservativeClockSample(
            at: entry.date,
            locale: DuoyiFocusTimerState.timerClockLocale
        )
        let fullPrefix = accessoryFocusShortStatus
        let compactCue = accessoryFocusCompactCue

        let fitsFullClockAndStatus: Bool = {
            guard let sample = clockSample else { return false }
            let w = DuoyiWidgetTypographyMetrics.width("\(sample) · \(fullPrefix)", font: inlineFont, pixelScale: pixelScale)
            return w.isFinite && w > 0 && w <= inlineMaxWidth
        }()
        let fitsCompactClockAndCue: Bool = {
            guard let sample = clockSample else { return false }
            let w = DuoyiWidgetTypographyMetrics.width("\(sample) · \(compactCue)", font: inlineFont, pixelScale: pixelScale)
            return w.isFinite && w > 0 && w <= inlineMaxWidth
        }()
        let fitsClockOnly: Bool = {
            guard let sample = clockSample else { return false }
            let w = DuoyiWidgetTypographyMetrics.width(sample, font: inlineFont, pixelScale: pixelScale)
            return w.isFinite && w > 0 && w <= inlineMaxWidth
        }()

        let fullRecoveryLabel = "\(fullPrefix) · \(accessoryFocusRecoveryTitle)"
        let compactRecoveryLabel = "\(compactCue) · \(accessoryFocusRecoveryCompactTitle)"
        let recoveryLabel: String? = {
            for candidate in [
                fullRecoveryLabel,
                accessoryFocusRecoveryTitle,
                compactRecoveryLabel,
                accessoryFocusRecoveryCompactTitle
            ] {
                let w = DuoyiWidgetTypographyMetrics.width(candidate, font: inlineFont, pixelScale: pixelScale)
                if w.isFinite && w > 0 && w <= inlineMaxWidth {
                    return candidate
                }
            }
            return nil
        }()

        if fitsFullClockAndStatus || fitsCompactClockAndCue || fitsClockOnly {
            let trailingStatus = fitsFullClockAndStatus ? fullPrefix : (fitsCompactClockAndCue ? compactCue : "")
            Group {
                switch display {
                case .fallback:
                    Text(verbatim: "\(entry.config.title) \(accessoryPrimaryText)")
                case .fixed(let clock):
                    Text(verbatim: trailingStatus.isEmpty ? clock : "\(clock) · \(trailingStatus)")
                case .countdown(let end):
                    if trailingStatus.isEmpty {
                        Text(timerInterval: entry.date...end, countsDown: true)
                    } else {
                        Text("\(Text(timerInterval: entry.date...end, countsDown: true)) · \(trailingStatus)")
                    }
                case .countUp(let start, let cap):
                    if trailingStatus.isEmpty {
                        Text(timerInterval: start...cap, countsDown: false)
                    } else {
                        Text("\(Text(timerInterval: start...cap, countsDown: false)) · \(trailingStatus)")
                    }
                }
            }
            .font(Font(inlineFont))
            .lineLimit(1)
            .accessibilityLabel(accessoryFocusAccessibilityText(display))
            .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        } else if let admittedRecovery = recoveryLabel {
            Text(verbatim: admittedRecovery)
                .font(Font(inlineFont))
                .lineLimit(1)
                .accessibilityLabel(accessoryFocusAccessibilityText(display, recoveryNote: accessoryFocusRecoveryTitle))
                .accessibilityHint(accessoryFocusRecoveryHint)
                .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        } else {
            Text(verbatim: "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessoryFocusAccessibilityText(display, recoveryNote: accessoryFocusRecoveryTitle))
                .accessibilityHint(accessoryFocusRecoveryHint)
                .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        }
    }

    @available(iOSApplicationExtension 16.0, *)
    @ViewBuilder
    private func accessoryFocusRectangularBody(
        display: DuoyiFocusTimerDisplay,
        availableWidth: Double,
        availableHeight: Double
    ) -> some View {
        let isValidGeometry = availableWidth.isFinite && availableHeight.isFinite &&
            availableWidth > 0 && availableHeight > 0
        let clockSample = entry.focusTimer.conservativeClockSample(
            at: entry.date,
            locale: DuoyiFocusTimerState.timerClockLocale
        )
        let rowSpacing: Double = 1.5

        let headerFont = DuoyiWidgetTypographyMetrics.font(
            baseSize: 12.0,
            weight: .semibold,
            textStyle: .caption1,
            category: uiCategory
        )
        let headerSymbolFont = DuoyiWidgetTypographyMetrics.font(
            baseSize: 11.0,
            weight: .semibold,
            textStyle: .caption1,
            category: uiCategory
        )
        let statusFont = DuoyiWidgetTypographyMetrics.font(
            baseSize: 11.0,
            weight: .regular,
            textStyle: .caption2,
            category: uiCategory
        )

        let headerTitleW = DuoyiWidgetTypographyMetrics.width(entry.config.title, font: headerFont, pixelScale: pixelScale)
        let headerTitleH = DuoyiWidgetTypographyMetrics.lineHeight(headerFont, pixelScale: pixelScale)
        let headerSymbolSize = accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: headerSymbolFont)
        let headerShowsSymbol: Bool = {
            guard isValidGeometry, let s = headerSymbolSize else { return false }
            return (Double(s.width) + 4.0 + headerTitleW) <= availableWidth
        }()
        let headerH = max(headerTitleH, headerShowsSymbol ? Double(headerSymbolSize?.height ?? 0) : 0)
        let statusH = DuoyiWidgetTypographyMetrics.lineHeight(statusFont, pixelScale: pixelScale)

        let selectedClockFont: UIFont? = {
            guard isValidGeometry,
                  let sample = clockSample,
                  headerTitleW > 0,
                  headerTitleW <= availableWidth,
                  headerH > 0,
                  statusH > 0 else {
                return nil
            }
            for baseSize in [16.0, 14.0, 12.0, 11.0] as [CGFloat] {
                let font = DuoyiWidgetTypographyMetrics.font(
                    baseSize: baseSize,
                    weight: .semibold,
                    textStyle: .subheadline,
                    category: uiCategory,
                    rounded: true,
                    monospacedDigits: true
                )
                let clockW = DuoyiWidgetTypographyMetrics.width(sample, font: font, pixelScale: pixelScale)
                let clockH = DuoyiWidgetTypographyMetrics.lineHeight(font, pixelScale: pixelScale)
                let totalH = headerH + rowSpacing + clockH + rowSpacing + statusH
                if clockW > 0, clockH > 0,
                   clockW <= availableWidth,
                   totalH <= availableHeight {
                    return font
                }
            }
            return nil
        }()

        let recoveryFullText = "\(accessoryFocusShortStatus) · \(accessoryFocusRecoveryTitle)"
        let recoveryCandidates: [(font: UIFont, text: String)] = {
            guard isValidGeometry else { return [] }
            var candidates: [(UIFont, String)] = []
            for baseSize in [12.0, 11.0, 10.0] as [CGFloat] {
                let f = DuoyiWidgetTypographyMetrics.font(
                    baseSize: baseSize,
                    weight: .medium,
                    textStyle: .caption2,
                    category: uiCategory
                )
                candidates.append((f, recoveryFullText))
                candidates.append((f, accessoryFocusRecoveryTitle))
                candidates.append((f, accessoryFocusRecoveryCompactTitle))
            }
            return candidates
        }()

        let admittedHeaderAndRecovery: (headerFits: Bool, font: UIFont, text: String)? = {
            guard isValidGeometry else { return nil }
            for candidate in recoveryCandidates {
                let w = DuoyiWidgetTypographyMetrics.width(candidate.text, font: candidate.font, pixelScale: pixelScale)
                let h = DuoyiWidgetTypographyMetrics.lineHeight(candidate.font, pixelScale: pixelScale)
                if w > 0, h > 0, w <= availableWidth {
                    if headerTitleW > 0, headerTitleW <= availableWidth,
                       (headerH + 2.0 + h) <= availableHeight {
                        return (true, candidate.font, candidate.text)
                    }
                    if h <= availableHeight {
                        return (false, candidate.font, candidate.text)
                    }
                }
            }
            return nil
        }()

        let admittedSymbolRecovery: (font: UIFont, size: CGSize)? = {
            guard isValidGeometry else { return nil }
            for baseSize in [16.0, 14.0, 12.0] as [CGFloat] {
                let f = UIFont.systemFont(ofSize: baseSize, weight: .semibold)
                if let size = accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: f),
                   Double(size.width) <= availableWidth,
                   Double(size.height) <= availableHeight {
                    return (f, size)
                }
            }
            return nil
        }()

        if let clockFont = selectedClockFont {
            VStack(alignment: .leading, spacing: CGFloat(rowSpacing)) {
                HStack(spacing: 4) {
                    if headerShowsSymbol {
                        Image(systemName: accessoryFocusSFSymbol)
                            .font(Font(headerSymbolFont))
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: entry.config.title)
                        .font(Font(headerFont))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                focusClock(display)
                    .font(Font(clockFont))
                    .lineLimit(1)
                Text(verbatim: accessoryFocusRectangularStatusText)
                    .font(Font(statusFont))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessoryFocusAccessibilityText(display))
            .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        } else if let recovery = admittedHeaderAndRecovery {
            VStack(alignment: .leading, spacing: 2) {
                if recovery.headerFits {
                    HStack(spacing: 4) {
                        if headerShowsSymbol {
                            Image(systemName: accessoryFocusSFSymbol)
                                .font(Font(headerSymbolFont))
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: entry.config.title)
                            .font(Font(headerFont))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Text(verbatim: recovery.text)
                    .font(Font(recovery.font))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessoryFocusAccessibilityText(display, recoveryNote: accessoryFocusRecoveryTitle))
            .accessibilityHint(accessoryFocusRecoveryHint)
            .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        } else if let symbolRecovery = admittedSymbolRecovery {
            Image(systemName: accessoryFocusSFSymbol)
                .font(Font(symbolRecovery.font))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessoryFocusAccessibilityText(display, recoveryNote: accessoryFocusRecoveryTitle))
                .accessibilityHint(accessoryFocusRecoveryHint)
                .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        } else {
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessoryFocusAccessibilityText(display, recoveryNote: accessoryFocusRecoveryTitle))
                .accessibilityHint(accessoryFocusRecoveryHint)
                .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        }
    }

    @available(iOSApplicationExtension 16.0, *)
    @ViewBuilder
    private func accessoryFocusCircularBody(
        display: DuoyiFocusTimerDisplay,
        availableWidth: Double,
        availableHeight: Double
    ) -> some View {
        let diameter = min(availableWidth, availableHeight)
        let isValidGeometry = availableWidth.isFinite && availableHeight.isFinite && diameter > 0
        let clockSample = entry.focusTimer.conservativeClockSample(
            at: entry.date,
            locale: DuoyiFocusTimerState.timerClockLocale
        )
        let statusText = accessoryFocusCircularStatusText
        let statusFont = DuoyiWidgetTypographyMetrics.font(
            baseSize: 8.5,
            weight: .semibold,
            textStyle: .caption2,
            category: uiCategory
        )
        let statusW = DuoyiWidgetTypographyMetrics.width(statusText, font: statusFont, pixelScale: pixelScale)
        let statusH = DuoyiWidgetTypographyMetrics.lineHeight(statusFont, pixelScale: pixelScale)
        let statusSymbolSize = accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: statusFont)
        let clockSpacing: Double = 1.5

        enum CircularAdmittedClockLayout {
            case textAndClock(clockFont: UIFont)
            case symbolAndClock(clockFont: UIFont)
        }

        let admittedClockLayout: CircularAdmittedClockLayout? = {
            guard isValidGeometry, let sample = clockSample else { return nil }
            for baseSize in [12.0, 11.0, 10.0, 9.5, 9.0] as [CGFloat] {
                let clockFont = DuoyiWidgetTypographyMetrics.font(
                    baseSize: baseSize,
                    weight: .semibold,
                    textStyle: .caption2,
                    category: uiCategory,
                    rounded: true,
                    monospacedDigits: true
                )
                let clockW = DuoyiWidgetTypographyMetrics.width(sample, font: clockFont, pixelScale: pixelScale)
                let clockH = DuoyiWidgetTypographyMetrics.lineHeight(clockFont, pixelScale: pixelScale)
                guard clockW > 0, clockH > 0 else { continue }

                if statusW > 0, statusH > 0,
                   Self.accessoryFitsInCircle(
                       diameter: diameter,
                       topWidth: statusW,
                       bottomWidth: clockW,
                       totalHeight: statusH + clockSpacing + clockH
                   ) {
                    return .textAndClock(clockFont: clockFont)
                }

                if let symSize = statusSymbolSize,
                   Self.accessoryFitsInCircle(
                       diameter: diameter,
                       topWidth: Double(symSize.width),
                       bottomWidth: clockW,
                       totalHeight: Double(symSize.height) + clockSpacing + clockH
                   ) {
                    return .symbolAndClock(clockFont: clockFont)
                }
            }
            return nil
        }()

        let recoveryFont = DuoyiWidgetTypographyMetrics.font(
            baseSize: 8.5,
            weight: .semibold,
            textStyle: .caption2,
            category: uiCategory
        )
        let recoveryTextCandidates = [accessoryFocusRecoveryTitle, accessoryFocusRecoveryCompactTitle]

        let admittedCompositeRecovery: String? = {
            guard isValidGeometry, let symSize = statusSymbolSize else { return nil }
            for candidate in recoveryTextCandidates {
                let textW = DuoyiWidgetTypographyMetrics.width(candidate, font: recoveryFont, pixelScale: pixelScale)
                let textH = DuoyiWidgetTypographyMetrics.lineHeight(recoveryFont, pixelScale: pixelScale)
                if textW > 0, textH > 0,
                   Self.accessoryFitsInCircle(
                       diameter: diameter,
                       topWidth: Double(symSize.width),
                       bottomWidth: textW,
                       totalHeight: Double(symSize.height) + 1.5 + textH
                   ) {
                    return candidate
                }
            }
            return nil
        }()

        let admittedTextOnlyRecovery: String? = {
            guard isValidGeometry else { return nil }
            for candidate in recoveryTextCandidates {
                let textW = DuoyiWidgetTypographyMetrics.width(candidate, font: recoveryFont, pixelScale: pixelScale)
                let textH = DuoyiWidgetTypographyMetrics.lineHeight(recoveryFont, pixelScale: pixelScale)
                if textW > 0, textH > 0,
                   Self.accessoryFitsInCircle(
                       diameter: diameter,
                       topWidth: textW,
                       totalHeight: textH
                   ) {
                    return candidate
                }
            }
            return nil
        }()

        let admittedSymbolOnlyRecovery: UIFont? = {
            guard isValidGeometry else { return nil }
            for size in [16.0, 14.0, 12.0, 10.0] as [CGFloat] {
                let f = UIFont.systemFont(ofSize: size, weight: .semibold)
                if let symSize = accessoryMeasuredSymbolSize(name: accessoryFocusSFSymbol, font: f),
                   Self.accessoryFitsInCircle(
                       diameter: diameter,
                       topWidth: Double(symSize.width),
                       totalHeight: Double(symSize.height)
                   ) {
                    return f
                }
            }
            return nil
        }()

        if let clockLayout = admittedClockLayout {
            Group {
                switch clockLayout {
                case .textAndClock(let clockFont):
                    VStack(spacing: CGFloat(clockSpacing)) {
                        Text(verbatim: statusText)
                            .font(Font(statusFont))
                            .lineLimit(1)
                        focusClock(display)
                            .font(Font(clockFont))
                            .lineLimit(1)
                    }
                case .symbolAndClock(let clockFont):
                    VStack(spacing: CGFloat(clockSpacing)) {
                        Image(systemName: accessoryFocusSFSymbol)
                            .font(Font(statusFont))
                        focusClock(display)
                            .font(Font(clockFont))
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessoryFocusAccessibilityText(display))
            .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        } else {
            Group {
                if let recoveryText = admittedCompositeRecovery {
                    VStack(spacing: 1.5) {
                        Image(systemName: accessoryFocusSFSymbol)
                            .font(Font(statusFont))
                        Text(verbatim: recoveryText)
                            .font(Font(recoveryFont))
                            .lineLimit(1)
                    }
                } else if let recoveryText = admittedTextOnlyRecovery {
                    Text(verbatim: recoveryText)
                        .font(Font(recoveryFont))
                        .lineLimit(1)
                } else if let symbolFont = admittedSymbolOnlyRecovery {
                    Image(systemName: accessoryFocusSFSymbol)
                        .font(Font(symbolFont))
                } else {
                    Color.clear
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessoryFocusAccessibilityText(display, recoveryNote: accessoryFocusRecoveryTitle))
            .accessibilityHint(accessoryFocusRecoveryHint)
            .environment(\.locale, DuoyiFocusTimerState.timerClockLocale)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            navLink(entry.navTodo, "duoyi://todo")
            navLink(entry.navHabit, "duoyi://habit")
            navLink(entry.navCalendar, "duoyi://calendar")
            navLink(entry.navFocus, "duoyi://focus")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                .fill(entry.theme.navBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: entry.theme.controlRadius)
                .strokeBorder(entry.theme.border, lineWidth: entry.theme.borderWidth > 0 ? entry.theme.borderWidth : 0)
        )
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
        .frame(maxWidth: .infinity)
    }

    private func navText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(entry.theme.readableMutedText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var visibleRows: [DuoyiWidgetRow] {
        if family == .systemSmall && (entry.config.kind == "DuoyiNoteWidget" || entry.config.kind == "DuoyiGoalWidget" || entry.config.kind == "DuoyiDiaryWidget" || entry.config.kind == "DuoyiAnniversaryWidget" || entry.config.kind == "DuoyiCourseWidget" || entry.config.kind == "DuoyiScheduleWidget") {
            return []
        }
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
            limit = 0
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

    private var calendarAccessoryDates: DuoyiCalendarAccessoryDateDisplay {
        DuoyiWidgetDisplayCore.calendarAccessoryDates(
            anchorDate: entry.date,
            timeZone: .current,
            isZh: entry.locale == .zh
        )
    }

    private var accessoryPrimaryText: String {
        if entry.config.kind == "DuoyiCalendarWidget" {
            if #available(iOSApplicationExtension 16.0, *),
               family == .accessoryInline {
                return calendarAccessoryDates.inline
            }
            return calendarAccessoryDates.rectangular
        }
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
        if isAccessoryFamily && [
            "DuoyiTodoWidget", "DuoyiNoteWidget", "DuoyiGoalWidget",
            "DuoyiDiaryWidget", "DuoyiAnniversaryWidget", "DuoyiCourseWidget",
            "DuoyiScheduleWidget"
        ].contains(entry.config.kind) {
            return nil
        }
        if entry.config.kind == "DuoyiTodoWidget" {
            return entry.todoRows.dropFirst().first.map { cleanRow($0.title) }
        }
        return visibleRows.first.map { cleanRow($0.title) }
    }

    private var accessoryShortText: String {
        if entry.config.kind == "DuoyiCalendarWidget" {
            return calendarAccessoryDates.short
        }
        if entry.config.kind == "DuoyiFocusWidget",
           entry.focusTimerRunning,
           entry.focusTimerRemainingSeconds > 0 {
            let minutes = max(1, (entry.focusTimerRemainingSeconds + 59) / 60)
            return entry.locale == .en ? "\(minutes)m" : "\(minutes)分"
        }
        if entry.config.kind == "DuoyiTodoWidget", let count = entry.todoCount {
            return "\(count)"
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

    private func plannedProgressCapsule(percent: Int) -> some View {
        let clamped = min(max(percent, 0), 100)
        return GeometryReader { geo in
            let fillWidth = geo.size.width * CGFloat(clamped) / 100.0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(entry.theme.readableMutedText.opacity(0.22))
                    .frame(height: 4.0)
                if clamped > 0 {
                    Capsule()
                        .fill(entry.theme.primary)
                        .frame(width: max(4.0, fillWidth), height: 4.0)
                }
            }
        }
        .frame(height: 4.0)
        .padding(.top, 4.0)
    }

    private func formatMinutes(_ seconds: Int) -> String {
        let minutes = max(1, (seconds + 59) / 60)
        return entry.locale == .en ? "\(minutes) min" : "\(minutes)分"
    }

    private var quickActionTitle: String {
        if entry.config.kind == "DuoyiFocusWidget" {
            if entry.focusActionIntent == .start {
                return entry.locale == .en ? "Start" : "开始"
            } else if entry.focusActionIntent == .resume {
                return entry.locale == .en ? "Resume" : "继续"
            } else if entry.focusTimerRunning && entry.isDailyFresh {
                return entry.locale == .en ? "Pause" : "暂停"
            } else {
                return entry.locale == .en ? "Open" : "打开"
            }
        }
        if entry.config.kind == "DuoyiHabitWidget" {
            let id = entry.habitQuickCheckId
            if entry.isDailyFresh && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return entry.locale == .en ? "Check In" : "打卡"
            } else {
                return entry.locale == .en ? "View" : "查看"
            }
        }
        if entry.config.kind == "DuoyiCalendarWidget" && entry.isDailyFresh {
            return entry.locale == .en ? "Today" : "今天"
        }
        if entry.isDailyFresh {
            switch entry.config.kind {
            case "DuoyiGoalWidget": return entry.locale == .en ? "+ Add" : "+ 目标"
            case "DuoyiScheduleWidget": return entry.locale == .en ? "+ Event" : "+ 日程"
            case "DuoyiNoteWidget": return entry.locale == .en ? "+ Note" : "+ 笔记"
            case "DuoyiDiaryWidget": return entry.locale == .en ? "+ Write" : "+ 日记"
            default: break
            }
        }
        return entry.config.quickActionTitle
    }

    private var quickURL: URL? {
        if entry.config.kind == "DuoyiFocusWidget" {
            if entry.focusActionIntent == .start {
                return entry.snapshot.actionURL(URLComponents(string: "duoyi://action/start_pomodoro"))
            } else if entry.focusActionIntent == .resume || (entry.focusTimerRunning && entry.isDailyFresh) {
                return entry.snapshot.actionURL(URLComponents(string: "duoyi://action/toggle_pomodoro"))
            } else {
                return entry.snapshot.actionURL(URLComponents(string: "duoyi://focus"))
            }
        }
        if entry.config.kind == "DuoyiHabitWidget" {
            let id = entry.habitQuickCheckId
            if entry.isDailyFresh && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var components = URLComponents(string: "duoyi://action/checkin_habit")
                components?.queryItems = [URLQueryItem(name: "id", value: id)]
                return entry.snapshot.actionURL(components)
            } else {
                return entry.snapshot.actionURL(URLComponents(string: "duoyi://habit"))
            }
        }
        if entry.config.kind == "DuoyiCalendarWidget" && entry.isDailyFresh {
            let dateKey = DuoyiWidgetDisplayCore.formattedDateKey(entry.date)
            if !dateKey.isEmpty {
                var components = URLComponents(string: "duoyi://calendar")
                components?.queryItems = [URLQueryItem(name: "date", value: dateKey)]
                if let dated = entry.snapshot.actionURL(components) {
                    return dated
                }
            }
        }
        if entry.isDailyFresh {
            let quickPath: String?
            switch entry.config.kind {
            case "DuoyiGoalWidget": quickPath = "duoyi://action/quick_goal"
            case "DuoyiScheduleWidget": quickPath = "duoyi://action/quick_schedule"
            case "DuoyiNoteWidget": quickPath = "duoyi://action/quick_note"
            case "DuoyiDiaryWidget": quickPath = "duoyi://action/quick_diary"
            default: quickPath = nil
            }
            if let quickPath = quickPath {
                return entry.snapshot.actionURL(URLComponents(string: quickPath))
            }
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
        let capture = DuoyiWidgetPublicationCapture.capture(
            read: { DuoyiWidgetPublicationStore.shared.read() }, displayMode: { nil }
        )
        let locale = DuoyiWidgetLocale.resolve(saved: capture.values["widget_locale"] as? String)
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
    func duoyiMonospacedDigit() -> some View {
        if #available(iOSApplicationExtension 15.0, *) {
            self.monospacedDigit()
        } else {
            self
        }
    }

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

    @ViewBuilder
    private func duoyiWidgetBackgroundView(_ theme: DuoyiWidgetTheme) -> some View {
        ZStack {
            duoyiWidgetBaseBackground(theme)

            #if canImport(UIKit)
            if let image = theme.backgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(theme.background.opacity(theme.isDark ? 0.72 : 0.65))
            }
            #endif

            if theme.borderWidth > 0 {
                // The system ContainerRelativeShape is authoritative for the outer widget boundary
                // and stroke on iOS Home Screen, ensuring concentric alignment with device masks.
                // theme.cornerRadius stores the Flutter/theme card skin radius token for internal metrics.
                ContainerRelativeShape()
                    .strokeBorder(theme.border, lineWidth: theme.borderWidth)
            }
        }
    }

    @ViewBuilder
    private func duoyiWidgetBaseBackground(_ theme: DuoyiWidgetTheme) -> some View {
        if theme.isGlassStyle {
            // The shared payload already composites glass onto a known base.
            // An accent with reduced opacity would expose arbitrary host color.
            theme.background
        } else if theme.isDefaultIosStyle {
            LinearGradient(
                colors: [theme.background, theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if !theme.isPlainCard {
            LinearGradient(
                colors: [theme.background, theme.surface, theme.accentEnd.opacity(theme.isDark ? 0.28 : 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [theme.background, theme.surface, theme.accentEnd.opacity(theme.isDark ? 0.20 : 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
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
