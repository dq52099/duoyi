import Foundation

// A prepared replacement is not an applied response. Only a later store's
// successful COMMIT and fresh-connection readback may acknowledge durability.
struct DuoyiWidgetPublicationPlan {
    let status: String
    let replacement: DuoyiWidgetPublicationEnvelope?
    let replay: DuoyiWidgetPublicationReceipt?
    init(_ status: String, replacement: DuoyiWidgetPublicationEnvelope? = nil,
         replay: DuoyiWidgetPublicationReceipt? = nil) {
        self.status = status; self.replacement = replacement; self.replay = replay
    }
}

enum DuoyiWidgetPublicationTransition {
    static func plan(_ current: DuoyiWidgetPublicationEnvelope?, _ request: DuoyiWidgetPublicationRequest,
                     nowMillis: Int64, zone: TimeZone, newToken: () -> String = { UUID().uuidString }) -> DuoyiWidgetPublicationPlan {
        func reject(_ status: String) -> DuoyiWidgetPublicationPlan { DuoyiWidgetPublicationPlan(status) }
        if let current, DuoyiWidgetWire.literalEqual(current.lastReceipt.operationId, request.operationId) {
            // A stored recovery receipt cannot prove that its COMMIT/readback
            // was confirmed. Require new inspection and a new immutable ID.
            if request.method == DuoyiWidgetPublicationRequest.recover {
                return reject(current.lastReceipt.requestDigest == request.digest ? "durabilityUnknown" : "invalid")
            }
            return current.lastReceipt.requestDigest == request.digest
                ? DuoyiWidgetPublicationPlan("alreadyApplied", replay: current.lastReceipt) : reject("invalid")
        }
        guard (0...DuoyiWidgetWire.maxExactInteger).contains(nowMillis) else { return reject("invalid") }
        if let current {
            guard DuoyiWidgetWire.literalEqual(request.expectedOwnerEpoch, current.ownerEpoch) else { return reject("ownerMismatch") }
            guard request.expectedStoreRevision == current.storeRevision,
                  current.storeRevision != DuoyiWidgetWire.maxExactInteger else { return reject("revisionConflict") }
        } else if request.method != DuoyiWidgetPublicationRequest.open || request.mode != "initialize" ||
                    request.expectedStoreRevision != nil || request.expectedOwnerEpoch != nil {
            return reject("revisionConflict")
        }
        let storeRevision = (current?.storeRevision ?? 0) + 1
        var epoch = current?.ownerEpoch
        var lease = current?.writerLeaseId
        var binding = current?.binding
        var state = current?.leaseState
        var desired = current?.desiredPresentation
        var document = current?.document

        func accepts(_ p: DuoyiWidgetDesiredPresentation) -> Bool {
            guard let current else { return true }
            let floor = current.desiredPresentation
            if p.revision < floor.revision || (p.revision == floor.revision && p.locale != floor.locale) { return false }
            if let incoming = request.presentationValues, p.revision == current.document.presentationRevision {
                guard let cleared = clearedDocumentValues(current.document), incoming == cleared else { return false }
            }
            return true
        }
        func issued(_ previous: String?) -> String? {
            let next = newToken()
            return DuoyiWidgetWire.blank(next) || DuoyiWidgetWire.literalEqual(next, previous) ? nil : next
        }

        switch request.method {
        case DuoyiWidgetPublicationRequest.open:
            let p = request.presentation!
            guard accepts(p) else { return reject("supersededPresentation") }
            if request.mode == "resume" {
                guard let current, current.active else { return reject("sealed") }
                guard request.binding == current.binding else { return reject("ownerMismatch") }
                binding = current.binding; desired = p
            } else {
                if let current, current.active {
                    return reject(current.binding != request.binding ? "ownerMismatch" : "revisionConflict")
                }
                guard let token = issued(current?.ownerEpoch) else { return reject("invalid") }
                epoch = token; binding = request.binding; desired = p
                document = tombstone(token, p, request.presentationValues!, nowMillis)
                guard document != nil else { return reject("invalid") }
            }
            guard let token = issued(current?.writerLeaseId), !DuoyiWidgetWire.literalEqual(token, epoch) else { return reject("invalid") }
            lease = token; state = "active"
        case DuoyiWidgetPublicationRequest.invalidate, DuoyiWidgetPublicationRequest.recover:
            let p = request.presentation!
            guard accepts(p) else { return reject("supersededPresentation") }
            guard let token = issued(current!.ownerEpoch) else { return reject("invalid") }
            epoch = token; binding = nil; lease = nil; state = "sealed"; desired = p
            document = tombstone(token, p, request.presentationValues!, nowMillis)
            guard document != nil else { return reject("invalid") }
        case DuoyiWidgetPublicationRequest.advance, DuoyiWidgetPublicationRequest.publish:
            guard let current, current.active else { return reject("sealed") }
            guard DuoyiWidgetWire.literalEqual(request.writerLeaseId, current.writerLeaseId) else { return reject("ownerMismatch") }
            if request.method == DuoyiWidgetPublicationRequest.advance {
                let p = request.presentation!
                guard accepts(p), p.revision != current.desiredPresentation.revision else { return reject("supersededPresentation") }
                desired = p
            } else {
                let next = request.document!
                let previous = current.document.publicationRevision
                guard DuoyiWidgetWire.literalEqual(next.ownerEpoch, current.ownerEpoch) else { return reject("ownerMismatch") }
                guard request.expectedPublicationRevision == previous, previous != DuoyiWidgetWire.maxExactInteger,
                      next.publicationRevision == previous + 1 else { return reject("revisionConflict") }
                guard next.presentationRevision == current.desiredPresentation.revision,
                      next.locale == current.desiredPresentation.locale else { return reject("supersededPresentation") }
                if next.presentationRevision == current.document.presentationRevision,
                   clearedDocumentValues(next) != clearedDocumentValues(current.document) { return reject("supersededPresentation") }
                if next.state == .published && !eligibleCapture(next, nowMillis, zone) { return reject("invalid") }
                document = next
            }
        default: return reject("invalid")
        }
        guard let document, let desired, let epoch, let state else { return reject("invalid") }
        let receipt: [String: Any] = ["operationId": request.operationId, "requestDigest": request.digest,
                                     "committedStoreRevision": NSNumber(value: storeRevision), "resultMetadata": [
                                        "ownerEpoch": epoch, "publicationRevision": NSNumber(value: document.publicationRevision),
                                        "desiredPresentationRevision": NSNumber(value: desired.revision),
                                        "appliedPresentationRevision": NSNumber(value: document.presentationRevision),
                                        "documentState": document.state.rawValue, "writerLeaseId": lease as Any? ?? NSNull()]]
        guard let envelope = DuoyiWidgetPublicationEnvelope.tryFromMap([
            "storeSchemaVersion": NSNumber(value: 1), "storeRevision": NSNumber(value: storeRevision),
            "binding": binding?.toMap as Any? ?? NSNull(), "ownerEpoch": epoch,
            "writerLeaseId": lease as Any? ?? NSNull(), "leaseState": state,
            "desiredPresentation": desired.toMap, "document": document.toMap, "lastReceipt": receipt]) else { return reject("invalid") }
        return DuoyiWidgetPublicationPlan("prepared", replacement: envelope)
    }

    private static func clearedDocumentValues(_ document: DuoyiWidgetPublicationDocument) -> [String: DuoyiWidgetPublicationDocument.Value]? {
        guard let values = DuoyiWidgetPublicationDocument.clearedValuesFrom(document.values.mapValues(\.object)),
              let cleared = DuoyiWidgetPublicationDocument.tryFromMap([
                "schemaVersion": NSNumber(value: 1), "ownerEpoch": "clear-projection",
                "publicationRevision": NSNumber(value: 0), "localeRevision": NSNumber(value: document.presentationRevision),
                "state": "cleared", "locale": document.locale, "snapshotDay": "",
                "snapshotUtcOffsetMinutes": NSNumber(value: 0), "capturedAtMillis": NSNumber(value: 0),
                "values": values]) else { return nil }
        return cleared.values
    }

    private static func tombstone(_ epoch: String, _ p: DuoyiWidgetDesiredPresentation,
                                  _ values: [String: DuoyiWidgetPublicationDocument.Value],
                                  _ now: Int64) -> DuoyiWidgetPublicationDocument? {
        DuoyiWidgetPublicationDocument.tryFromMap([
            "schemaVersion": NSNumber(value: 1), "ownerEpoch": epoch, "publicationRevision": NSNumber(value: 0),
            "localeRevision": NSNumber(value: p.revision), "state": "cleared", "locale": p.locale,
            "snapshotDay": "", "snapshotUtcOffsetMinutes": NSNumber(value: 0),
            "capturedAtMillis": NSNumber(value: now), "values": values.mapValues(\.object)])
    }

    private static func eligibleCapture(_ document: DuoyiWidgetPublicationDocument, _ now: Int64, _ zone: TimeZone) -> Bool {
        guard document.capturedAtMillis <= now else { return false }
        let accepted = Date(timeIntervalSince1970: Double(now) / 1000)
        let captured = Date(timeIntervalSince1970: Double(document.capturedAtMillis) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        func day(_ date: Date) -> String? {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, (1...9999).contains(year),
                  let month = components.month, let day = components.day else { return nil }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        return document.snapshotDay == day(accepted) && document.snapshotDay == day(captured) &&
            Int(document.snapshotUtcOffsetMinutes) == zone.secondsFromGMT(for: accepted) / 60 &&
            Int(document.snapshotUtcOffsetMinutes) == zone.secondsFromGMT(for: captured) / 60
    }
}
