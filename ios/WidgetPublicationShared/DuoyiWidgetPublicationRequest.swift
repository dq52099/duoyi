import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

enum DuoyiWidgetRequestDigest {
    // The production iOS deployment target supports CryptoKit. An unsupported
    // host cannot silently substitute an unhashed request or grant authority.
    static func sha256(_ bytes: Data) -> String? {
        #if canImport(CryptoKit)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }

    static func taggedBytes(method: String, fields: [String: Any]) -> Data? {
        var bytes = Data()
        func count(_ value: Int) -> Bool {
            guard value <= Int(Int32.max) else { return false }
            var big = UInt32(value).bigEndian
            withUnsafeBytes(of: &big) { bytes.append(contentsOf: $0) }
            return true
        }
        func write(_ raw: Any) -> Bool {
            if raw is NSNull { bytes.append(0); return true }
            if let value = raw as? String {
                bytes.append(1)
                guard count(value.utf16.count) else { return false }
                for unit in value.utf16 {
                    var big = unit.bigEndian
                    withUnsafeBytes(of: &big) { bytes.append(contentsOf: $0) }
                }
                return true
            }
            if let value = DuoyiWidgetWire.boolean(raw) {
                bytes.append(contentsOf: [2, value ? 1 : 0]); return true
            }
            if let value = DuoyiWidgetWire.integer(raw) {
                bytes.append(3)
                var big = value.bigEndian
                withUnsafeBytes(of: &big) { bytes.append(contentsOf: $0) }
                return true
            }
            guard let map = raw as? [String: Any] else { return false }
            bytes.append(4)
            guard count(map.count) else { return false }
            for key in map.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
                guard write(key), write(map[key]!) else { return false }
            }
            return true
        }
        guard write("duoyi-widget-request-v1"), write(method), write(fields) else { return nil }
        return bytes
    }
}

// The host must bind this intent to its current authorization/cleanup generation.
// Parsing the context does not authenticate a user or grant a writer capability.
struct DuoyiWidgetRecoveryContext {
    let kind: String
    let scopeToken: String
    let binding: DuoyiWidgetWorkspaceBinding?

    static func tryFromMap(_ raw: Any?) -> Self? {
        guard let map = DuoyiWidgetWire.object(raw, keys: ["kind", "scopeToken", "binding"]),
              let kind = map["kind"] as? String, ["workspace", "cleanup"].contains(kind),
              let scope = DuoyiWidgetWire.token(map["scopeToken"]) else { return nil }
        let binding: DuoyiWidgetWorkspaceBinding?
        if kind == "workspace" {
            guard let parsed = DuoyiWidgetWorkspaceBinding.tryFromMap(map["binding"]) else { return nil }
            binding = parsed
        } else {
            guard map["binding"] is NSNull else { return nil }
            binding = nil
        }
        return Self(kind: kind, scopeToken: scope, binding: binding)
    }

    var toMap: [String: Any] {
        ["kind": kind, "scopeToken": scopeToken, "binding": binding?.toMap as Any? ?? NSNull()]
    }
}

// A parsed immutable request is intent, not a durable acknowledgement or a
// permission to write. The bridge must keep the digest provider native-owned.
struct DuoyiWidgetPublicationRequest {
    static let open = "openWidgetWorkspace"
    static let invalidate = "invalidateWidgetWorkspace"
    static let advance = "advanceDesiredWidgetPresentation"
    static let publish = "publishWidgetPublication"
    static let recover = "recoverWidgetStore"

    let method: String
    let operationId: String
    let expectedStoreRevision: Int64?
    let expectedOwnerEpoch: String?
    let writerLeaseId: String?
    let expectedPublicationRevision: Int64?
    let mode: String?
    let binding: DuoyiWidgetWorkspaceBinding?
    let presentation: DuoyiWidgetDesiredPresentation?
    let presentationValues: [String: DuoyiWidgetPublicationDocument.Value]?
    let document: DuoyiWidgetPublicationDocument?
    let recoveryContext: DuoyiWidgetRecoveryContext?
    let digest: String
    let canonicalRequestBytes: Data

    private init(method: String, operationId: String, expectedStoreRevision: Int64?,
                 expectedOwnerEpoch: String?, writerLeaseId: String?, expectedPublicationRevision: Int64?,
                 mode: String?, binding: DuoyiWidgetWorkspaceBinding?,
                 presentation: DuoyiWidgetDesiredPresentation?,
                 presentationValues: [String: DuoyiWidgetPublicationDocument.Value]?,
                 document: DuoyiWidgetPublicationDocument?, recoveryContext: DuoyiWidgetRecoveryContext?,
                 digest: String, canonicalRequestBytes: Data) {
        self.method = method; self.operationId = operationId
        self.expectedStoreRevision = expectedStoreRevision; self.expectedOwnerEpoch = expectedOwnerEpoch
        self.writerLeaseId = writerLeaseId; self.expectedPublicationRevision = expectedPublicationRevision
        self.mode = mode; self.binding = binding; self.presentation = presentation
        self.presentationValues = presentationValues; self.document = document
        self.recoveryContext = recoveryContext
        self.digest = digest; self.canonicalRequestBytes = canonicalRequestBytes
    }

    static func tryFromMap(_ method: String, _ raw: Any?,
                          computeDigest: (Data) -> String? = DuoyiWidgetRequestDigest.sha256) -> Self? {
        let common: Set<String> = ["protocolVersion", "operationId", "expectedStoreRevision", "expectedOwnerEpoch"]
        let extra: Set<String>
        switch method {
        case open: extra = ["mode", "binding", "presentation"]
        case invalidate: extra = ["presentation"]
        case advance: extra = ["writerLeaseId", "desiredPresentation"]
        case publish: extra = ["writerLeaseId", "expectedPublicationRevision", "document"]
        case recover: extra = ["presentation", "recoveryContext"]
        default: return nil
        }
        guard let map = DuoyiWidgetWire.object(raw, keys: common.union(extra)),
              DuoyiWidgetWire.integer(map["protocolVersion"]) == 1,
              let operation = DuoyiWidgetWire.token(map["operationId"]) else { return nil }
        let revision: Int64?
        if map["expectedStoreRevision"] is NSNull { revision = nil }
        else {
            guard let parsed = DuoyiWidgetWire.nonnegative(map["expectedStoreRevision"]), parsed > 0 else { return nil }
            revision = parsed
        }
        let epoch: String?
        if map["expectedOwnerEpoch"] is NSNull { epoch = nil }
        else { guard let parsed = DuoyiWidgetWire.token(map["expectedOwnerEpoch"]) else { return nil }; epoch = parsed }
        guard (revision == nil) == (epoch == nil) else { return nil }
        var mode: String?
        if method == open {
            guard let parsed = map["mode"] as? String, ["initialize", "resume"].contains(parsed) else { return nil }
            mode = parsed
        }
        guard revision != nil || (method == open && mode == "initialize") else { return nil }
        var lease: String?
        if method == advance || method == publish {
            guard let parsed = DuoyiWidgetWire.token(map["writerLeaseId"]) else { return nil }; lease = parsed
        }
        var binding: DuoyiWidgetWorkspaceBinding?
        if method == open {
            guard let parsed = DuoyiWidgetWorkspaceBinding.tryFromMap(map["binding"]) else { return nil }; binding = parsed
        }
        var presentation: DuoyiWidgetDesiredPresentation?
        var values: [String: DuoyiWidgetPublicationDocument.Value]?
        if method == open || method == invalidate || method == recover {
            guard let p = DuoyiWidgetWire.object(map["presentation"], keys: ["revision", "locale", "values"]),
                  let parsed = DuoyiWidgetDesiredPresentation.tryFromMap(["revision": p["revision"]!, "locale": p["locale"]!]),
                  let rawValues = p["values"] as? [String: Any],
                  Set(rawValues.keys) == DuoyiWidgetPublicationDocument.valueKeys,
                  let cleared = DuoyiWidgetPublicationDocument.tryFromMap([
                    "schemaVersion": NSNumber(value: 1), "ownerEpoch": "presentation-input",
                    "publicationRevision": NSNumber(value: 0), "localeRevision": NSNumber(value: parsed.revision),
                    "state": "cleared", "locale": parsed.locale, "snapshotDay": "",
                    "snapshotUtcOffsetMinutes": NSNumber(value: 0), "capturedAtMillis": NSNumber(value: 0),
                    "values": rawValues]) else { return nil }
            presentation = parsed; values = cleared.values
        } else if method == advance {
            guard let parsed = DuoyiWidgetDesiredPresentation.tryFromMap(map["desiredPresentation"]) else { return nil }
            presentation = parsed
        }
        var document: DuoyiWidgetPublicationDocument?
        var publication: Int64?
        if method == publish {
            guard let parsed = DuoyiWidgetPublicationDocument.tryFromMap(map["document"]),
                  let previous = DuoyiWidgetWire.nonnegative(map["expectedPublicationRevision"]) else { return nil }
            document = parsed; publication = previous
        }
        let recoveryContext: DuoyiWidgetRecoveryContext?
        if method == recover {
            guard let parsed = DuoyiWidgetRecoveryContext.tryFromMap(map["recoveryContext"]) else { return nil }
            recoveryContext = parsed
        } else { recoveryContext = nil }
        var fields: [String: Any] = ["protocolVersion": NSNumber(value: Int64(1)), "operationId": operation,
                                     "expectedStoreRevision": revision.map { NSNumber(value: $0) } as Any? ?? NSNull(),
                                     "expectedOwnerEpoch": epoch as Any? ?? NSNull()]
        if method == open { fields["mode"] = mode!; fields["binding"] = binding!.toMap }
        if method == advance { fields["desiredPresentation"] = presentation!.toMap }
        if method == publish {
            fields["expectedPublicationRevision"] = NSNumber(value: publication!)
            fields["document"] = document!.toMap
        }
        if let values, let presentation {
            fields["presentation"] = ["revision": NSNumber(value: presentation.revision),
                                      "locale": presentation.locale, "values": values.mapValues(\.object)]
        }
        if let lease { fields["writerLeaseId"] = lease }
        if let recoveryContext { fields["recoveryContext"] = recoveryContext.toMap }
        guard let bytes = DuoyiWidgetRequestDigest.taggedBytes(method: method, fields: fields),
              let digest = computeDigest(bytes), digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return Self(method: method, operationId: operation, expectedStoreRevision: revision,
                    expectedOwnerEpoch: epoch, writerLeaseId: lease, expectedPublicationRevision: publication,
                    mode: mode, binding: binding, presentation: presentation, presentationValues: values,
                    document: document, recoveryContext: recoveryContext, digest: digest, canonicalRequestBytes: bytes)
    }
}
