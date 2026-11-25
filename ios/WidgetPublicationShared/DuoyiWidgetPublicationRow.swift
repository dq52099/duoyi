import Foundation

struct DuoyiWidgetPublicationRead {
    let status: String
    let envelope: DuoyiWidgetPublicationEnvelope?

    init(_ status: String, _ envelope: DuoyiWidgetPublicationEnvelope? = nil) {
        self.status = status
        self.envelope = envelope
    }

    var metadata: [String: Any] {
        var result = envelope?.readMetadata ?? [:]
        result["status"] = status
        return result
    }
}

// Match the existing Kotlin row contract: ASCII canonical JSON, sorted UTF-16
// keys, literal string code units and integer primitives. This is storage
// validation; it is not a JSON patch, a preference fallback or a write grant.
enum DuoyiWidgetPublicationJSON {
    private static let hex = Array("0123456789abcdef".utf8)

    private static func quoted(_ value: String) -> String {
        var bytes: [UInt8] = [34]
        for unit in value.utf16 {
            if unit == 34 || unit == 92 {
                bytes.append(92)
                bytes.append(UInt8(unit))
            } else if unit < 32 || unit > 126 {
                bytes.append(contentsOf: [92, 117])
                for shift: UInt16 in [12, 8, 4, 0] {
                    bytes.append(hex[Int((unit >> shift) & 15)])
                }
            } else {
                bytes.append(UInt8(unit))
            }
        }
        bytes.append(34)
        return String(decoding: bytes, as: UTF8.self)
    }

    static func encode(_ raw: Any?) -> String? {
        guard let raw else { return "null" }
        if raw is NSNull { return "null" }
        if let value = raw as? String { return quoted(value) }
        if let value = DuoyiWidgetWire.boolean(raw) { return value ? "true" : "false" }
        if let value = DuoyiWidgetWire.integer(raw) { return String(value) }
        guard let map = raw as? [String: Any] else { return nil }
        let keys = map.keys.sorted { left, right in left.utf16.lexicographicallyPrecedes(right.utf16) }
        var members: [String] = []
        for key in keys {
            guard let value = encode(map[key]) else { return nil }
            members.append(quoted(key) + ":" + value)
        }
        return "{" + members.joined(separator: ",") + "}"
    }
}

enum DuoyiWidgetPublicationRow {
    static func decode(_ encoded: String) -> DuoyiWidgetPublicationRead {
        guard let raw = try? JSONSerialization.jsonObject(with: Data(encoded.utf8)),
              let map = raw as? [String: Any] else { return DuoyiWidgetPublicationRead("corrupt") }
        if let schema = DuoyiWidgetWire.integer(map["storeSchemaVersion"]), schema != 1 {
            return DuoyiWidgetPublicationRead("unsupported")
        }
        guard let envelope = DuoyiWidgetPublicationEnvelope.tryFromMap(map),
              let canonical = DuoyiWidgetPublicationJSON.encode(map),
              encoded.utf8.elementsEqual(canonical.utf8) else { return DuoyiWidgetPublicationRead("corrupt") }
        // Validate the original stored shape before exposing the old-89 Monday
        // default. Re-encoding the normalized envelope would reject that row.
        return DuoyiWidgetPublicationRead(envelope.active ? "ready" : "sealed", envelope)
    }
}
