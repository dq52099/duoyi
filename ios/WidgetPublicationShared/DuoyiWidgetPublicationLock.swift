import Foundation
import DuoyiWidgetStoreC

// All store instances in a process share this gate. Nonblocking acquisition also
// rejects callback reentry; the order is always process gate -> flock -> SQLite.
enum DuoyiWidgetPublicationLock {
    private static let processGate = NSLock()
    // Fixed locks must not be replaced, including between an uncertain commit
    // and later recovery. Retain each observed identity under the process gate.
    // This is process-local evidence, not a persistent provenance marker.
    private static var observedIdentities: [String: (UInt64, UInt64)] = [:]

    static func withGate<T>(_ body: () throws -> T) throws -> T {
        guard processGate.try() else { throw DuoyiWidgetDatabaseFailure("busy") }
        defer { processGate.unlock() }
        return try body()
    }

    // Caller already holds the process gate. Only explicit initialize may pass
    // create=true, after checking the DB is absent. Never unlink/replace this file.
    static func withFileLock<T>(path: URL, exclusive: Bool, create: Bool = false,
                                _ body: () throws -> T) throws -> T {
        let kind = path.withUnsafeFileSystemRepresentation { $0.map { duoyi_store_path_kind($0) } ?? -1 }
        guard kind == 1 || (create && exclusive && kind == 0) else {
            throw DuoyiWidgetDatabaseFailure("unavailable")
        }
        let fd = path.withUnsafeFileSystemRepresentation { $0.map { duoyi_store_open_lock($0, create ? 1 : 0, exclusive ? 1 : 0) } ?? -1 }
        guard fd >= 0 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        defer { _ = duoyi_store_close_fd(fd) }
        let result = duoyi_store_try_lock(fd, exclusive ? 1 : 0)
        guard result == 0 else {
            let code = duoyi_store_last_errno()
            throw DuoyiWidgetDatabaseFailure(code == EWOULDBLOCK || code == EAGAIN ? "busy" : "unavailable")
        }
        defer { _ = duoyi_store_unlock(fd) }
        func verifyName() throws {
            guard path.withUnsafeFileSystemRepresentation({ $0.map { duoyi_store_lock_still_named(fd, $0) } ?? 0 }) == 1 else {
                throw DuoyiWidgetDatabaseFailure("unavailable")
            }
            var device: UInt64 = 0, inode: UInt64 = 0
            guard duoyi_store_lock_identity(fd, &device, &inode) == 1 else {
                throw DuoyiWidgetDatabaseFailure("unavailable")
            }
            let key = path.standardizedFileURL.path
            if let observed = observedIdentities[key], observed != (device, inode) {
                throw DuoyiWidgetDatabaseFailure("unavailable")
            }
            observedIdentities[key] = (device, inode)
        }
        try verifyName()
        let value = try body()
        try verifyName()
        return value
    }
}
