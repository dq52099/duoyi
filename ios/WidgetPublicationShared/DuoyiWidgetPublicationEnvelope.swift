import Foundation
import CoreFoundation

// Staged shared core. Decoding complete facts never grants authority to write.
enum DuoyiWidgetWire {
    static let maxExactInteger: Int64 = 9_007_199_254_740_991

    static func object(_ raw: Any?, keys: Set<String>) -> [String: Any]? {
        guard let map = raw as? [String: Any], Set(map.keys) == keys else { return nil }
        return map
    }

    static func integer(_ raw: Any?) -> Int64? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"].contains(String(cString: number.objCType)) else {
            return nil
        }
        // int64Value wraps UInt64 values. Parse the integer representation first.
        // A Double conversion would lose precision and accept floating inputs.
        return Int64(number.stringValue)
    }

    static func nonnegative(_ raw: Any?) -> Int64? {
        guard let value = integer(raw), (0...maxExactInteger).contains(value) else { return nil }
        return value
    }

    static func boolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func blank(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            let c = scalar.value
            return (0x0009...0x000D).contains(c) || c == 0x0020 || c == 0x0085 ||
                c == 0x00A0 || c == 0x1680 || (0x2000...0x200A).contains(c) ||
                c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F ||
                c == 0x3000 || c == 0xFEFF
        }
    }

    static func token(_ raw: Any?) -> String? {
        guard let value = raw as? String, !blank(value) else { return nil }
        return value
    }

    // Swift String equality normalizes Unicode. Protocol identities and user
    // content must retain the literal sequence, matching Dart/Kotlin equality.
    static func literalEqual(_ left: String?, _ right: String?) -> Bool {
        switch (left, right) {
        case (.none, .none): return true
        case (.some(let left), .some(let right)): return left.utf8.elementsEqual(right.utf8)
        default: return false
        }
    }

    static func validDay(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return false }
        let indexes = [0, 1, 2, 3, 5, 6, 8, 9]
        guard indexes.allSatisfy({ (48...57).contains(bytes[$0]) }) else { return false }
        let year = indexes.prefix(4).reduce(0) { $0 * 10 + Int(bytes[$1] - 48) }
        let month = Int(bytes[5] - 48) * 10 + Int(bytes[6] - 48)
        let day = Int(bytes[8] - 48) * 10 + Int(bytes[9] - 48)
        guard (1...9999).contains(year), (1...12).contains(month) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...lengths[month - 1]).contains(day)
    }
}

struct DuoyiWidgetPublicationDocument {
    enum State: String { case published, cleared, blocked }
    enum ValueType { case string, int32, int64, boolean }
    enum Value: Equatable {
        case string(String), int32(Int32), int64(Int64), boolean(Bool)

        static func == (left: Self, right: Self) -> Bool {
            switch (left, right) {
            case (.string(let left), .string(let right)): return DuoyiWidgetWire.literalEqual(left, right)
            case (.int32(let left), .int32(let right)): return left == right
            case (.int64(let left), .int64(let right)): return left == right
            case (.boolean(let left), .boolean(let right)): return left == right
            default: return false
            }
        }

        var object: Any {
            switch self {
            case .string(let value): return value
            case .int32(let value): return NSNumber(value: value)
            case .int64(let value): return NSNumber(value: value)
            case .boolean(let value): return NSNumber(value: value)
            }
        }

        var empty: Bool {
            switch self {
            case .string(let value): return value.isEmpty
            case .int32(let value): return value == 0
            case .int64(let value): return value == 0
            case .boolean(let value): return !value
            }
        }
    }

    static let valueTypes: [String: ValueType] = [
        "todo_count": .int32,
        "habit_percent": .int32,
        "habit_active_count": .int32,
        "pomodoro_today": .int32,
        "focus_minutes_today": .int32,
        "brand_app_title": .string,
        "nav_todo": .string,
        "nav_habit": .string,
        "nav_calendar": .string,
        "nav_focus": .string,
        "widget_first_day_of_week": .int32,
        "todo_top3_count": .int32,
        "todo_top3_1": .string,
        "todo_top3_1_id": .string,
        "todo_top3_2": .string,
        "todo_top3_2_id": .string,
        "todo_top3_3": .string,
        "todo_top3_3_id": .string,
        "goal_highlight_1": .string,
        "goal_highlight_1_id": .string,
        "goal_highlight_2": .string,
        "goal_highlight_2_id": .string,
        "goal_highlight_3": .string,
        "goal_highlight_3_id": .string,
        "anniversary_highlight_1": .string,
        "anniversary_highlight_1_id": .string,
        "anniversary_highlight_2": .string,
        "anniversary_highlight_2_id": .string,
        "course_highlight_1": .string,
        "course_highlight_1_id": .string,
        "course_highlight_2": .string,
        "course_highlight_2_id": .string,
        "course_highlight_3": .string,
        "course_highlight_3_id": .string,
        "note_highlight_1": .string,
        "note_highlight_1_id": .string,
        "note_highlight_2": .string,
        "note_highlight_2_id": .string,
        "note_highlight_3": .string,
        "note_highlight_3_id": .string,
        "memorial_highlight_1": .string,
        "memorial_highlight_1_id": .string,
        "memorial_highlight_2": .string,
        "memorial_highlight_2_id": .string,
        "memorial_highlight_3": .string,
        "memorial_highlight_3_id": .string,
        "diary_highlight_1": .string,
        "diary_highlight_1_id": .string,
        "diary_highlight_2": .string,
        "diary_highlight_2_id": .string,
        "diary_highlight_3": .string,
        "diary_highlight_3_id": .string,
        "today_event_summary": .string,
        "schedule_highlight_1": .string,
        "schedule_highlight_1_id": .string,
        "schedule_highlight_2": .string,
        "schedule_highlight_2_id": .string,
        "schedule_highlight_3": .string,
        "schedule_highlight_3_id": .string,
        "calendar_month_summary": .string,
        "focus_summary": .string,
        "habit_summary": .string,
        "streak_summary": .string,
        "next_focus_label": .string,
        "focus_timer_count_up": .boolean,
        "focus_timer_started_at_millis": .int64,
        "focus_timer_running": .boolean,
        "focus_timer_remaining_seconds": .int32,
        "focus_timer_total_seconds": .int32,
        "focus_timer_ends_at_millis": .int64,
        "focus_timer_label": .string,
        "habit_quick_check_id": .string,
        "habit_quick_check_label": .string,
        "widget_theme_brand_id": .string,
        "widget_theme_card_skin_id": .string,
        "widget_theme_dark": .boolean,
        "widget_theme_primary": .string,
        "widget_theme_background": .string,
        "widget_theme_surface": .string,
        "widget_theme_nav_background": .string,
        "widget_theme_border": .string,
        "widget_theme_text": .string,
        "widget_theme_muted_text": .string,
        "widget_theme_on_primary": .string,
        "widget_theme_accent_start": .string,
        "widget_theme_accent_end": .string,
        "widget_theme_background_asset_key": .string,
        "widget_theme_corner_radius_dp": .int32,
        "widget_theme_control_radius_dp": .int32,
        "widget_theme_border_width_dp": .int32,
    ]
    static let valueKeys = Set(valueTypes.keys)
    private static let documentKeys: Set<String> = [
        "schemaVersion", "ownerEpoch", "publicationRevision", "localeRevision", "state",
        "locale", "snapshotDay", "snapshotUtcOffsetMinutes", "capturedAtMillis", "values",
    ]

    let ownerEpoch: String
    let publicationRevision: Int64
    let presentationRevision: Int64
    let state: State
    let locale: String
    let snapshotDay: String
    let snapshotUtcOffsetMinutes: Int32
    let capturedAtMillis: Int64
    let values: [String: Value]

    private init(ownerEpoch: String, publicationRevision: Int64, presentationRevision: Int64,
                 state: State, locale: String, snapshotDay: String, snapshotUtcOffsetMinutes: Int32,
                 capturedAtMillis: Int64, values: [String: Value]) {
        self.ownerEpoch = ownerEpoch
        self.publicationRevision = publicationRevision
        self.presentationRevision = presentationRevision
        self.state = state
        self.locale = locale
        self.snapshotDay = snapshotDay
        self.snapshotUtcOffsetMinutes = snapshotUtcOffsetMinutes
        self.capturedAtMillis = capturedAtMillis
        self.values = values
    }

    static func businessKey(_ key: String) -> Bool {
        !key.hasPrefix("widget_theme_") && key != "widget_first_day_of_week" &&
            key != "brand_app_title" && !key.hasPrefix("nav_")
    }

    private static func parseValue(_ key: String, _ type: ValueType, _ raw: Any?) -> Value? {
        switch type {
        case .string:
            guard let value = raw as? String else { return nil }
            return .string(value)
        case .boolean:
            guard let value = DuoyiWidgetWire.boolean(raw) else { return nil }
            return .boolean(value)
        case .int64:
            guard let value = DuoyiWidgetWire.nonnegative(raw) else { return nil }
            return .int64(value)
        case .int32:
            let minimum: Int64 = key == "habit_active_count" ? -1 : key == "widget_first_day_of_week" ? 1 : 0
            let maximum: Int64 = key == "habit_percent" ? 100 : key == "widget_first_day_of_week" ? 7 : Int64(Int32.max)
            guard let value = DuoyiWidgetWire.integer(raw), (minimum...maximum).contains(value) else { return nil }
            return .int32(Int32(value))
        }
    }

    static func clearedValuesFrom(_ raw: [String: Any]) -> [String: Any]? {
        guard Set(raw.keys) == valueKeys else { return nil }
        var result: [String: Any] = [:]
        for (key, type) in valueTypes {
            guard let parsed = parseValue(key, type, raw[key]) else { return nil }
            if !businessKey(key) { result[key] = parsed.object; continue }
            switch type {
            case .string: result[key] = ""
            case .boolean: result[key] = NSNumber(value: false)
            case .int32: result[key] = NSNumber(value: Int32(0))
            case .int64: result[key] = NSNumber(value: Int64(0))
            }
        }
        return result
    }

    static func tryFromMap(_ raw: Any?, allowLegacyWeekStart: Bool = false) -> Self? {
        guard let map = DuoyiWidgetWire.object(raw, keys: documentKeys),
              DuoyiWidgetWire.integer(map["schemaVersion"]) == 1,
              let epoch = DuoyiWidgetWire.token(map["ownerEpoch"]),
              let revision = DuoyiWidgetWire.nonnegative(map["publicationRevision"]),
              let presentation = DuoyiWidgetWire.nonnegative(map["localeRevision"]),
              let captured = DuoyiWidgetWire.nonnegative(map["capturedAtMillis"]),
              let stateRaw = map["state"] as? String, let state = State(rawValue: stateRaw),
              let locale = map["locale"] as? String, ["zh", "en"].contains(locale),
              let day = map["snapshotDay"] as? String,
              let offset = DuoyiWidgetWire.integer(map["snapshotUtcOffsetMinutes"]),
              (-1080...1080).contains(offset), let rawValues = map["values"] as? [String: Any] else { return nil }
        if state == .published {
            guard revision > 0, DuoyiWidgetWire.validDay(day) else { return nil }
        } else if !day.isEmpty || offset != 0 { return nil }
        let legacy = allowLegacyWeekStart && Set(rawValues.keys) == valueKeys.subtracting(["widget_first_day_of_week"])
        guard Set(rawValues.keys) == valueKeys || legacy else { return nil }
        var values: [String: Value] = [:]
        for (key, type) in valueTypes {
            let input: Any? = legacy && key == "widget_first_day_of_week" ? NSNumber(value: 1) : rawValues[key]
            guard let parsed = parseValue(key, type, input) else { return nil }
            if state != .published && businessKey(key) && !parsed.empty { return nil }
            values[key] = parsed
        }
        guard values["todo_count"] == values["todo_top3_count"] else { return nil }
        return Self(ownerEpoch: epoch, publicationRevision: revision, presentationRevision: presentation,
                    state: state, locale: locale, snapshotDay: day, snapshotUtcOffsetMinutes: Int32(offset),
                    capturedAtMillis: captured, values: values)
    }

    var toMap: [String: Any] {
        ["schemaVersion": NSNumber(value: 1), "ownerEpoch": ownerEpoch,
         "publicationRevision": NSNumber(value: publicationRevision), "localeRevision": NSNumber(value: presentationRevision),
         "state": state.rawValue, "locale": locale, "snapshotDay": snapshotDay,
         "snapshotUtcOffsetMinutes": NSNumber(value: snapshotUtcOffsetMinutes),
         "capturedAtMillis": NSNumber(value: capturedAtMillis), "values": values.mapValues(\.object)]
    }

    var toFlatValues: [String: Any] {
        var flat = values.mapValues(\.object)
        flat["widget_publication_state"] = state.rawValue
        flat["widget_account_nonce"] = ownerEpoch
        flat["widget_locale"] = locale
        flat["widget_snapshot_day"] = snapshotDay
        flat["widget_snapshot_utc_offset_minutes"] = NSNumber(value: snapshotUtcOffsetMinutes)
        return flat
    }
}

struct DuoyiWidgetWorkspaceBinding: Equatable {
    let kind: String
    let key: String
    private init(kind: String, key: String) { self.kind = kind; self.key = key }
    static func == (left: Self, right: Self) -> Bool {
        left.kind == right.kind && DuoyiWidgetWire.literalEqual(left.key, right.key)
    }
    static func tryFromMap(_ raw: Any?) -> Self? {
        guard let map = DuoyiWidgetWire.object(raw, keys: ["kind", "key"]),
              let kind = map["kind"] as? String, ["account", "guest"].contains(kind),
              let key = DuoyiWidgetWire.token(map["key"]) else { return nil }
        return Self(kind: kind, key: key)
    }
    var toMap: [String: Any] { ["kind": kind, "key": key] }
}

struct DuoyiWidgetDesiredPresentation {
    let revision: Int64
    let locale: String
    private init(revision: Int64, locale: String) { self.revision = revision; self.locale = locale }
    static func tryFromMap(_ raw: Any?) -> Self? {
        guard let map = DuoyiWidgetWire.object(raw, keys: ["revision", "locale"]),
              let revision = DuoyiWidgetWire.nonnegative(map["revision"]),
              let locale = map["locale"] as? String, ["zh", "en"].contains(locale) else { return nil }
        return Self(revision: revision, locale: locale)
    }
    var toMap: [String: Any] { ["revision": NSNumber(value: revision), "locale": locale] }
}

struct DuoyiWidgetPublicationReceipt {
    let operationId: String
    let requestDigest: String
    let committedStoreRevision: Int64
    let ownerEpoch: String
    let publicationRevision: Int64
    let desiredPresentationRevision: Int64
    let appliedPresentationRevision: Int64
    let documentState: String
    let writerLeaseId: String?

    private init(operationId: String, requestDigest: String, committedStoreRevision: Int64,
                 ownerEpoch: String, publicationRevision: Int64, desiredPresentationRevision: Int64,
                 appliedPresentationRevision: Int64, documentState: String, writerLeaseId: String?) {
        self.operationId = operationId; self.requestDigest = requestDigest
        self.committedStoreRevision = committedStoreRevision; self.ownerEpoch = ownerEpoch
        self.publicationRevision = publicationRevision; self.desiredPresentationRevision = desiredPresentationRevision
        self.appliedPresentationRevision = appliedPresentationRevision; self.documentState = documentState
        self.writerLeaseId = writerLeaseId
    }

    static func tryFromMap(_ raw: Any?) -> Self? {
        guard let map = DuoyiWidgetWire.object(raw, keys: ["operationId", "requestDigest", "committedStoreRevision", "resultMetadata"]),
              let operation = DuoyiWidgetWire.token(map["operationId"]),
              let digest = map["requestDigest"] as? String, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let revision = DuoyiWidgetWire.nonnegative(map["committedStoreRevision"]), revision > 0,
              let result = DuoyiWidgetWire.object(map["resultMetadata"], keys: ["ownerEpoch", "publicationRevision", "desiredPresentationRevision", "appliedPresentationRevision", "documentState", "writerLeaseId"]),
              let epoch = DuoyiWidgetWire.token(result["ownerEpoch"]),
              let publication = DuoyiWidgetWire.nonnegative(result["publicationRevision"]),
              let desired = DuoyiWidgetWire.nonnegative(result["desiredPresentationRevision"]),
              let applied = DuoyiWidgetWire.nonnegative(result["appliedPresentationRevision"]), applied <= desired,
              let state = result["documentState"] as? String, ["published", "cleared", "blocked"].contains(state) else { return nil }
        let lease: String?
        if result["writerLeaseId"] is NSNull { lease = nil }
        else { guard let value = DuoyiWidgetWire.token(result["writerLeaseId"]) else { return nil }; lease = value }
        return Self(operationId: operation, requestDigest: digest, committedStoreRevision: revision,
                    ownerEpoch: epoch, publicationRevision: publication, desiredPresentationRevision: desired,
                    appliedPresentationRevision: applied, documentState: state, writerLeaseId: lease)
    }

    var resultMetadata: [String: Any] {
        ["ownerEpoch": ownerEpoch, "publicationRevision": NSNumber(value: publicationRevision),
         "desiredPresentationRevision": NSNumber(value: desiredPresentationRevision),
         "appliedPresentationRevision": NSNumber(value: appliedPresentationRevision), "documentState": documentState,
         "writerLeaseId": writerLeaseId as Any? ?? NSNull()]
    }
    var toMap: [String: Any] {
        ["operationId": operationId, "requestDigest": requestDigest,
         "committedStoreRevision": NSNumber(value: committedStoreRevision), "resultMetadata": resultMetadata]
    }
}

struct DuoyiWidgetPublicationEnvelope {
    let storeRevision: Int64
    let binding: DuoyiWidgetWorkspaceBinding?
    let ownerEpoch: String
    let writerLeaseId: String?
    let leaseState: String
    let desiredPresentation: DuoyiWidgetDesiredPresentation
    let document: DuoyiWidgetPublicationDocument
    let lastReceipt: DuoyiWidgetPublicationReceipt
    var active: Bool { leaseState == "active" }

    private init(storeRevision: Int64, binding: DuoyiWidgetWorkspaceBinding?, ownerEpoch: String,
                 writerLeaseId: String?, leaseState: String, desiredPresentation: DuoyiWidgetDesiredPresentation,
                 document: DuoyiWidgetPublicationDocument, lastReceipt: DuoyiWidgetPublicationReceipt) {
        self.storeRevision = storeRevision; self.binding = binding; self.ownerEpoch = ownerEpoch
        self.writerLeaseId = writerLeaseId; self.leaseState = leaseState
        self.desiredPresentation = desiredPresentation; self.document = document; self.lastReceipt = lastReceipt
    }

    static func tryFromMap(_ raw: Any?) -> Self? {
        guard let map = DuoyiWidgetWire.object(raw, keys: ["storeSchemaVersion", "storeRevision", "binding", "ownerEpoch", "writerLeaseId", "leaseState", "desiredPresentation", "document", "lastReceipt"]),
              DuoyiWidgetWire.integer(map["storeSchemaVersion"]) == 1,
              let revision = DuoyiWidgetWire.nonnegative(map["storeRevision"]), revision > 0,
              let epoch = DuoyiWidgetWire.token(map["ownerEpoch"]),
              let state = map["leaseState"] as? String, ["active", "sealed"].contains(state) else { return nil }
        let binding: DuoyiWidgetWorkspaceBinding?
        if map["binding"] is NSNull { binding = nil }
        else { guard let parsed = DuoyiWidgetWorkspaceBinding.tryFromMap(map["binding"]) else { return nil }; binding = parsed }
        let lease: String?
        if map["writerLeaseId"] is NSNull { lease = nil }
        else { guard let parsed = DuoyiWidgetWire.token(map["writerLeaseId"]) else { return nil }; lease = parsed }
        if state == "active" { guard binding != nil, lease != nil else { return nil } }
        else if binding != nil || lease != nil { return nil }
        guard let presentation = DuoyiWidgetDesiredPresentation.tryFromMap(map["desiredPresentation"]),
              let document = DuoyiWidgetPublicationDocument.tryFromMap(map["document"], allowLegacyWeekStart: true),
              DuoyiWidgetWire.literalEqual(document.ownerEpoch, epoch),
              document.presentationRevision <= presentation.revision else { return nil }
        if document.presentationRevision == presentation.revision && document.locale != presentation.locale { return nil }
        if state == "sealed" && (document.state == .published || document.presentationRevision != presentation.revision) { return nil }
        guard let receipt = DuoyiWidgetPublicationReceipt.tryFromMap(map["lastReceipt"]),
              receipt.committedStoreRevision == revision, DuoyiWidgetWire.literalEqual(receipt.ownerEpoch, epoch),
              DuoyiWidgetWire.literalEqual(receipt.writerLeaseId, lease),
              receipt.publicationRevision == document.publicationRevision,
              receipt.desiredPresentationRevision == presentation.revision,
              receipt.appliedPresentationRevision == document.presentationRevision,
              receipt.documentState == document.state.rawValue else { return nil }
        return Self(storeRevision: revision, binding: binding, ownerEpoch: epoch, writerLeaseId: lease,
                    leaseState: state, desiredPresentation: presentation, document: document, lastReceipt: receipt)
    }

    var toMap: [String: Any] {
        ["storeSchemaVersion": NSNumber(value: 1), "storeRevision": NSNumber(value: storeRevision),
         "binding": binding?.toMap as Any? ?? NSNull(), "ownerEpoch": ownerEpoch,
         "writerLeaseId": writerLeaseId as Any? ?? NSNull(), "leaseState": leaseState,
         "desiredPresentation": desiredPresentation.toMap, "document": document.toMap, "lastReceipt": lastReceipt.toMap]
    }

    // Reading storage exposes facts, never the active writer capability.
    var readMetadata: [String: Any] {
        ["storeRevision": NSNumber(value: storeRevision), "binding": binding?.toMap as Any? ?? NSNull(),
         "ownerEpoch": ownerEpoch, "leaseState": leaseState, "desiredPresentation": desiredPresentation.toMap,
         "document": document.toMap, "lastOperationId": lastReceipt.operationId, "lastRequestDigest": lastReceipt.requestDigest]
    }
}
