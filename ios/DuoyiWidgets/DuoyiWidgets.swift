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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dateDay, hour: 12)) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == dateDay
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
                               "anniversary", "countdown", "time-entry"])
        let host = components.host?.lowercased() ?? ""
        let isEntity = entityHosts.contains(host) &&
            components.percentEncodedPath.split(separator: "/").first != nil
        guard host == "action" || isEntity else { return components.url }
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
        // Opening quick entry and requesting refresh are recoverable navigation.
        let mutates = isEntity || ["complete_todo", "checkin_habit", "start_pomodoro"].contains(action) ||
            (action == "quick_todo" && hasQuickText)
        guard mutates else { return components.url }
        guard isFresh(at: date, calendar: calendar), let offset = utcOffsetMinutes else { return nil }
        let bindingKeys = Set(["source", "widget_day", "widget_offset", "widget_account", "widget_delivery"])
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
            "todo", "habit", "anniversary", "course", "diary", "goal", "countdown", "time-entry"
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
        isZh: Bool
    ) -> DuoyiMonthGridModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let comps = calendar.dateComponents([.year, .month, .day], from: anchorDate)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let todayDay = comps.day ?? 1

        var firstDayComps = DateComponents()
        firstDayComps.year = year
        firstDayComps.month = month
        firstDayComps.day = 1
        firstDayComps.hour = 12

        let firstDayDate = calendar.date(from: firstDayComps) ?? anchorDate
        let weekday = calendar.component(.weekday, from: firstDayDate)
        // In Gregorian: Sunday=1, Monday=2 ... Saturday=7. Monday-first offset:
        let firstWeekdayOffset = (weekday + 5) % 7

        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDayDate)?.count ?? 30

        var cells: [DuoyiMonthCell] = []
        cells.reserveCapacity(42)

        for index in 0..<42 {
            if index < firstWeekdayOffset || index >= firstWeekdayOffset + daysInMonth {
                cells.append(DuoyiMonthCell(dayNumber: 0, isToday: false, text: "  "))
            } else {
                let day = index - firstWeekdayOffset + 1
                let isToday = (day == todayDay)
                let text = day < 10 ? " \(day)" : "\(day)"
                cells.append(DuoyiMonthCell(dayNumber: day, isToday: isToday, text: text))
            }
        }

        let weekdayHeaders = isZh
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

        let monthTitle: String
        if isZh {
            monthTitle = "\(year)年\(month)月"
        } else {
            let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let mName = (1...12).contains(month) ? monthNames[month - 1] : "Month"
            monthTitle = "\(mName) \(year)"
        }

        return DuoyiMonthGridModel(
            year: year,
            month: month,
            todayDay: todayDay,
            firstWeekdayOffset: firstWeekdayOffset,
            daysInMonth: daysInMonth,
            cells: cells,
            weekdayHeaders: weekdayHeaders,
            monthTitle: monthTitle
        )
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
}
// END DUOYI_WIDGET_DISPLAY_CORE

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
    let isDark: Bool
    let primary: Color
    let background: Color
    let surface: Color
    let navBackground: Color
    let border: Color
    let text: Color
    let mutedText: Color
    let onPrimary: Color
    let accentStart: Color
    let accentEnd: Color
    let backgroundAssetKey: String
    let cornerRadius: CGFloat
    let controlRadius: CGFloat
    let borderWidth: CGFloat

    var isDefaultBrand: Bool {
        brandId == "defaultBrand"
    }

    var isPlainCard: Bool {
        cardSkinId == "plain_card"
    }

    var isDefaultIosStyle: Bool {
        isDefaultBrand && isPlainCard
    }

    static let fallback = DuoyiWidgetTheme(
        brandId: "defaultBrand",
        cardSkinId: "plain_card",
        isDark: false,
        primary: color("#FFC85656"),
        background: color("#FFF6F7F9"),
        surface: color("#FFFFFFFF"),
        navBackground: color("#FFF1F3F6"),
        border: color("#00C85656"),
        text: color("#FF1F2933"),
        mutedText: color("#FF667085"),
        onPrimary: color("#FFFFFFFF"),
        accentStart: color("#FFC85656"),
        accentEnd: color("#FF2F8F83"),
        backgroundAssetKey: "",
        cornerRadius: 16,
        controlRadius: 12,
        borderWidth: 0
    )

    init(values: [String: Any]) {
        self.brandId = Self.readString(values, key: "widget_theme_brand_id", fallback: "defaultBrand")
        self.cardSkinId = Self.readString(values, key: "widget_theme_card_skin_id", fallback: "plain_card")
        self.isDark = Self.readBool(values, key: "widget_theme_dark", fallback: false)
        self.primary = Self.read(values, key: "widget_theme_primary", fallback: "#FFC85656")
        self.background = Self.read(values, key: "widget_theme_background", fallback: "#FFF6F7F9")
        self.surface = Self.read(values, key: "widget_theme_surface", fallback: "#FFFFFFFF")
        self.navBackground = Self.read(values, key: "widget_theme_nav_background", fallback: "#FFF1F3F6")
        self.border = Self.read(values, key: "widget_theme_border", fallback: "#00C85656")
        self.text = Self.read(values, key: "widget_theme_text", fallback: "#FF1F2933")
        self.mutedText = Self.read(values, key: "widget_theme_muted_text", fallback: "#FF667085")
        self.onPrimary = Self.read(values, key: "widget_theme_on_primary", fallback: "#FFFFFFFF")
        self.accentStart = Self.read(values, key: "widget_theme_accent_start", fallback: "#FFC85656")
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
            normalized = "FFC85656"
        }
        guard let value = UInt64(normalized, radix: 16) else {
            return Color(red: 0.784, green: 0.337, blue: 0.337)
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

private func isAnniversaryFallback(_ text: String) -> Bool {
    DuoyiWidgetDisplayCore.isKnownAnniversaryEmptyPlaceholder(text)
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
    let theme: DuoyiWidgetTheme

    var focusTimerRunning: Bool { focusTimer.isRunning }
    var focusTimerRemainingSeconds: Int { focusTimer.seconds }
    var focusTimerTotalSeconds: Int { focusTimer.totalSeconds }
    var focusTimerEndDate: Date? { focusTimer.endDate }

    var focusActionIntent: DuoyiFocusActionIntent {
        focusTimer.actionIntent(isDailyFresh: isDailyFresh)
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
            isDailyFresh: false,
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
            focusTimer: .unavailable,
            focusTimerLabel: locale == .en ? "Focus countdown" : "专注倒计时",
            calendarEventSummary: nil,
            calendarEventTarget: localizedConfig.deepLink,
            theme: .fallback
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DuoyiWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DuoyiWidgetEntry>) -> Void) {
        // All scheduled transitions retain this publication and account identity.
        let defaults = UserDefaults(suiteName: appGroupId)?.dictionaryRepresentation() ?? [:]
        let now = Date()
        let current = entry(values: defaults, at: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dates = DuoyiFocusTimerTimeline.dates(now: now, timer: current.focusTimer, calendar: calendar)
        let entries = dates.map { entry(values: defaults, at: $0) }
        let refreshMinutes = current.focusTimerRunning ? 1 : 15
        var nextRefresh = now.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        if let nextTransition = dates.dropFirst().first {
            nextRefresh = min(nextRefresh, nextTransition)
        }
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    private func entry() -> DuoyiWidgetEntry {
        // One immutable read avoids mixing item IDs and account metadata.
        let defaults = UserDefaults(suiteName: appGroupId)?.dictionaryRepresentation() ?? [:]
        return entry(values: defaults, at: Date())
    }

    private func entry(values defaults: [String: Any], at now: Date) -> DuoyiWidgetEntry {
        let snapshot = DuoyiWidgetSnapshot(values: defaults)
        let fresh = snapshot.isFresh(at: now)
        let locale = DuoyiWidgetLocale.resolve(saved: defaults["widget_locale"] as? String)
        let localizedConfig = config.localized(for: locale)
        let todoRows = fresh ? readTodoRows(defaults, locale: locale, snapshot: snapshot) : []
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
            isDailyFresh: fresh,
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
            focusTimer: DuoyiFocusTimerState.resolve(values: defaults, sessionPublished: snapshot.hasPublishedSession, at: now),
            focusTimerLabel: focusTimerLabel,
            calendarEventSummary: calendarEventSummary,
            calendarEventTarget: calendarEventTarget,
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
        } else if entry.config.kind == "DuoyiCalendarWidget" {
            calendarBody
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

    private var calendarBody: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            GeometryReader { proxy in
                calendarContent(availableHeight: Double(proxy.size.height))
            }
            if family != .systemSmall {
                footer
            }
        }
        .padding(padding)
        .duoyiWidgetBackground(entry.theme)
        .widgetURL(URL(string: entry.config.deepLink))
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
            isZh: entry.locale == .zh
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
                        .font(.system(size: headerFontSize, weight: .regular))
                        .foregroundColor(entry.theme.mutedText)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: CGFloat(rowSpacing)) {
                ForEach(visibleWeekRange, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let cell = grid.cells[week * 7 + col]
                            Group {
                                if cell.dayNumber > 0 {
                                    let label = DuoyiWidgetDisplayCore.cellAccessibilityLabel(
                                        year: grid.year,
                                        month: grid.month,
                                        day: cell.dayNumber,
                                        isToday: cell.isToday,
                                        isZh: entry.locale == .zh
                                    )
                                    if cell.isToday {
                                        Text("\(cell.dayNumber)")
                                            .font(.system(size: cellFontSize, weight: .medium))
                                            .foregroundColor(entry.theme.onPrimary)
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
                                } else {
                                    Text("")
                                        .font(.system(size: cellFontSize))
                                        .frame(width: CGFloat(cellHeight), height: CGFloat(cellHeight))
                                        .accessibilityHidden(true)
                                }
                            }
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

    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.focusTimerRunning, let endDate = entry.focusTimerEndDate, endDate > Date() {
                Text(endDate, style: .timer)
                    .font(.system(size: primarySize, weight: .semibold, design: .rounded))
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
        if theme.isDefaultIosStyle {
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
