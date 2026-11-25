import Foundation
import DuoyiWidgetStoreC

// Coordinator only: no Flutter, provider callbacks, refresh or UI acceptance.
// The extension calls read(); only the host bridge may submit parsed requests.
final class DuoyiWidgetPublicationStore {
    static let databaseName = "duoyi_widget_store_v1.sqlite"
    static let lockName = "duoyi_widget_store_v1.lock"
    private static var quarantinedPaths = Set<String>() // accessed under process gate
    static let shared = DuoyiWidgetPublicationStore(directory: appGroupDirectory, secure: nativeProtection)

    private let directory: () throws -> URL
    private let secure: (URL, Bool) throws -> Void
    init(directory: @escaping () throws -> URL, secure: @escaping (URL, Bool) throws -> Void) {
        self.directory = directory; self.secure = secure
    }

    private static func appGroupDirectory() throws -> URL {
        #if os(iOS)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.duoyi.duoyi") else {
            throw DuoyiWidgetDatabaseFailure("unavailable")
        }
        return container.resolvingSymlinksInPath()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("WidgetPublicationStore", isDirectory: true)
        #else
        throw DuoyiWidgetDatabaseFailure("unavailable")
        #endif
    }

    private static func nativeProtection(_ path: URL, _ maySet: Bool) throws {
        #if os(iOS)
        let manager = FileManager.default
        let protection = FileProtectionType.completeUntilFirstUserAuthentication
        var target = path
        if maySet {
            try manager.setAttributes([.protectionKey: protection], ofItemAtPath: target.path)
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            try target.setResourceValues(resource)
        }
        let attributes = try manager.attributesOfItem(atPath: target.path)
        let actual = attributes[.protectionKey] as? FileProtectionType
        let excluded = try target.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        guard actual == protection, excluded == true else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        #else
        // Linux transport tests inject a synthetic policy explicitly. They do
        // not attest to Apple file protection or backup exclusion.
        throw DuoyiWidgetDatabaseFailure("unavailable")
        #endif
    }

    private func kind(_ url: URL) -> Int32 {
        url.withUnsafeFileSystemRepresentation { $0.map { duoyi_store_path_kind($0) } ?? -1 }
    }

    private func prepareDirectory(_ path: URL, create: Bool) throws -> Bool {
        // Resolving a nonexistent leaf can leave its symlinked ancestor
        // unresolved in Foundation. Check each prefix before creating anything.
        var prefix = path
        while prefix.path != "/" {
            let prefixKind = kind(prefix)
            guard prefixKind == 0 || prefixKind == 2 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
            let parent = prefix.deletingLastPathComponent()
            guard parent.path != prefix.path else { throw DuoyiWidgetDatabaseFailure("unavailable") }
            prefix = parent
        }
        guard path.standardizedFileURL.path.utf8.elementsEqual(path.resolvingSymlinksInPath().standardizedFileURL.path.utf8) else {
            throw DuoyiWidgetDatabaseFailure("unavailable")
        }
        let existing = kind(path)
        if existing == 0 {
            guard create else { return false }
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        } else if existing != 2 { throw DuoyiWidgetDatabaseFailure("unavailable") }
        // Reject a directory reached via a symlink as well as a final symlink.
        guard path.standardizedFileURL.path.utf8.elementsEqual(path.resolvingSymlinksInPath().standardizedFileURL.path.utf8),
              kind(path) == 2 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        try secure(path, create)
        return true
    }

    private func secureArtifacts(_ path: URL, maySet: Bool, requireDatabase: Bool) throws {
        try secure(path, maySet)
        for (name, required) in [(Self.lockName, true), (Self.databaseName, requireDatabase), (Self.databaseName + "-journal", false)] {
            let file = path.appendingPathComponent(name)
            let existing = kind(file)
            if existing == 0 && !required { continue }
            guard existing == 1 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
            try secure(file, maySet)
        }
    }

    private func freshRead(_ path: URL) throws -> DuoyiWidgetPublicationRead {
        let database = try DuoyiWidgetPublicationDatabase(path: path.appendingPathComponent(Self.databaseName), writable: false, nonBlocking: true)
        defer { try? database.rollback(); try? database.close() }
        try database.beginRead()
        let result = try database.readEnvelope()
        try database.commit(); try database.close()
        return result
    }

    func read() -> DuoyiWidgetPublicationRead {
        do {
            return try DuoyiWidgetPublicationLock.withGate {
                let path = try directory().standardizedFileURL
                if Self.quarantinedPaths.contains(path.path) { return DuoyiWidgetPublicationRead("durabilityUnknown") }
                guard try prepareDirectory(path, create: false) else { return DuoyiWidgetPublicationRead("absent") }
                let databaseKind = kind(path.appendingPathComponent(Self.databaseName))
                if databaseKind == 0 { return DuoyiWidgetPublicationRead("absent") }
                guard databaseKind == 1 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
                return try DuoyiWidgetPublicationLock.withFileLock(path: path.appendingPathComponent(Self.lockName), exclusive: false) {
                    try secureArtifacts(path, maySet: false, requireDatabase: true)
                    return try freshRead(path)
                }
            }
        } catch let failure as DuoyiWidgetDatabaseFailure { return DuoyiWidgetPublicationRead(failure.status) }
        catch { return DuoyiWidgetPublicationRead("unavailable") }
    }

    // Host-only inspection, including while quarantined. These are unconfirmed
    // recovery facts, never normal ready/read authority or a writer capability.
    // An existing writable connection permits SQLite's own journal recovery;
    // neither this operation nor a healthy-looking row clears quarantine.
    func inspectRecovery() -> [String: Any] {
        do {
            return try DuoyiWidgetPublicationLock.withGate {
                let path = try directory().standardizedFileURL
                guard try prepareDirectory(path, create: false),
                      kind(path.appendingPathComponent(Self.databaseName)) == 1 else {
                    throw DuoyiWidgetDatabaseFailure("unavailable")
                }
                return try DuoyiWidgetPublicationLock.withFileLock(path: path.appendingPathComponent(Self.lockName), exclusive: true) {
                    try secureArtifacts(path, maySet: false, requireDatabase: true)
                    let database = try DuoyiWidgetPublicationDatabase(path: path.appendingPathComponent(Self.databaseName), writable: true, nonBlocking: true)
                    defer { try? database.rollback(); try? database.close() }
                    try database.beginRead()
                    let result = try database.readEnvelope()
                    guard let envelope = result.envelope else { throw DuoyiWidgetDatabaseFailure(result.status) }
                    try database.commit(); try database.close()
                    try secureArtifacts(path, maySet: false, requireDatabase: true)
                    return ["status": "inspected", "facts": [
                        "storeRevision": NSNumber(value: envelope.storeRevision), "ownerEpoch": envelope.ownerEpoch,
                        "binding": envelope.binding?.toMap as Any? ?? NSNull(),
                        "desiredPresentation": envelope.desiredPresentation.toMap,
                        "appliedPresentationRevision": NSNumber(value: envelope.document.presentationRevision),
                        "lastOperationId": envelope.lastReceipt.operationId,
                        "lastRequestDigest": envelope.lastReceipt.requestDigest]]
                }
            }
        } catch let failure as DuoyiWidgetDatabaseFailure { return ["status": failure.status] }
        catch { return ["status": "unavailable"] }
    }

    func mutate(_ request: DuoyiWidgetPublicationRequest, nowMillis: Int64, zone: TimeZone,
                newToken: () -> String = { UUID().uuidString }) -> [String: Any] {
        func failure(_ status: String) -> [String: Any] { ["operationId": request.operationId, "status": status] }
        do {
            return try DuoyiWidgetPublicationLock.withGate {
                let path = try directory().standardizedFileURL
                let recovering = request.method == DuoyiWidgetPublicationRequest.recover
                if Self.quarantinedPaths.contains(path.path) && !recovering { return failure("durabilityUnknown") }
                // Recovery is fail-closed even on precommit rejection. Only the
                // complete proof below may release this process's quarantine.
                if recovering { Self.quarantinedPaths.insert(path.path) }
                let mayInitialize = request.method == DuoyiWidgetPublicationRequest.open && request.mode == "initialize" &&
                    request.expectedOwnerEpoch == nil && request.expectedStoreRevision == nil
                var attemptedCommit = false
                do {
                    guard try prepareDirectory(path, create: mayInitialize) else { return failure("revisionConflict") }
                    let beforeKind = kind(path.appendingPathComponent(Self.databaseName))
                    guard beforeKind == 0 || beforeKind == 1 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
                    if beforeKind == 0 && !mayInitialize { return failure("revisionConflict") }
                    let acknowledgement = try DuoyiWidgetPublicationLock.withFileLock(path: path.appendingPathComponent(Self.lockName),
                        exclusive: true, create: beforeKind == 0 && mayInitialize) {
                        // Recheck absence after taking the fixed lock, since a
                        // different process may just have completed initialize.
                        let currentKind = kind(path.appendingPathComponent(Self.databaseName))
                        guard currentKind == 0 || currentKind == 1 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
                        let absent = currentKind == 0
                        if absent && !mayInitialize { return failure("revisionConflict") }
                        if absent && kind(path.appendingPathComponent(Self.databaseName + "-journal")) != 0 {
                            throw DuoyiWidgetDatabaseFailure("unavailable")
                        }
                        try secureArtifacts(path, maySet: mayInitialize, requireDatabase: !absent)
                        // Plan before CREATE so a rejected absent request cannot
                        // leave an empty authoritative file behind.
                        let initialPlan = absent ? DuoyiWidgetPublicationTransition.plan(nil, request, nowMillis: nowMillis, zone: zone, newToken: newToken) : nil
                        if let initialPlan, initialPlan.replacement == nil { return failure(initialPlan.status) }
                        let database = try DuoyiWidgetPublicationDatabase(path: path.appendingPathComponent(Self.databaseName), writable: true, create: absent, nonBlocking: true)
                        defer { try? database.rollback(); try? database.close() }
                        try database.configureWriter(); try database.beginWrite()
                        let plan: DuoyiWidgetPublicationPlan
                        if let initialPlan { plan = initialPlan }
                        else {
                            let current = try database.readEnvelope()
                            guard let envelope = current.envelope else { throw DuoyiWidgetDatabaseFailure(current.status) }
                            plan = DuoyiWidgetPublicationTransition.plan(envelope, request, nowMillis: nowMillis, zone: zone, newToken: newToken)
                        }
                        if let receipt = plan.replay {
                            try database.rollback(); try database.close()
                            return receiptAcknowledgement(receipt, request: request, status: "alreadyApplied")
                        }
                        guard let replacement = plan.replacement else {
                            try database.rollback(); try database.close(); return failure(plan.status)
                        }
                        if absent { try database.initializeSchema() }
                        try database.writeReplacement(replacement)
                        try secureArtifacts(path, maySet: true, requireDatabase: true)
                        attemptedCommit = true
                        try database.commit(); try database.close()
                        // Keep gate and exclusive flock through both the new
                        // connection's read and final result construction.
                        try secureArtifacts(path, maySet: true, requireDatabase: true)
                        let persisted = try freshRead(path)
                        guard let envelope = persisted.envelope,
                              let expected = DuoyiWidgetPublicationJSON.encode(replacement.toMap),
                              let actual = DuoyiWidgetPublicationJSON.encode(envelope.toMap),
                              expected.utf8.elementsEqual(actual.utf8) else { throw DuoyiWidgetDatabaseFailure("durabilityUnknown") }
                        return receiptAcknowledgement(envelope.lastReceipt, request: request, status: "applied")
                    }
                    // withFileLock has also verified its inode is still named.
                    // Keep the process gate while releasing quarantine, so no
                    // other local reader/writer can observe premature success.
                    if recovering, acknowledgement["status"] as? String == "applied" {
                        Self.quarantinedPaths.remove(path.path)
                    }
                    return acknowledgement
                } catch {
                    // This catch is inside the process gate: no other local
                    // caller can slip between a failed commit and quarantine.
                    if attemptedCommit {
                        Self.quarantinedPaths.insert(path.path)
                        return failure("durabilityUnknown")
                    }
                    return failure((error as? DuoyiWidgetDatabaseFailure)?.status ?? "unavailable")
                }
            }
        } catch let error as DuoyiWidgetDatabaseFailure { return failure(error.status) }
        catch { return failure("unavailable") }
    }

    private func receiptAcknowledgement(_ receipt: DuoyiWidgetPublicationReceipt, request: DuoyiWidgetPublicationRequest,
                                        status: String) -> [String: Any] {
        var result = receipt.resultMetadata
        if request.method != DuoyiWidgetPublicationRequest.open { result.removeValue(forKey: "writerLeaseId") }
        result["operationId"] = receipt.operationId; result["status"] = status
        result["committedStoreRevision"] = NSNumber(value: receipt.committedStoreRevision)
        return result
    }
}
