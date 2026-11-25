import Foundation
import DuoyiWidgetStoreC

struct DuoyiWidgetDatabaseFailure: Error {
    let status: String
    let sqliteCode: Int32?
    init(_ status: String, _ code: Int32? = nil) { self.status = status; self.sqliteCode = code }
}

// Low-level storage transport only. The store coordinator must hold its process
// gate and the fixed file lock for every use, including COMMIT and fresh readback.
// These methods never return an applied acknowledgement or grant a writer lease.
final class DuoyiWidgetPublicationDatabase {
    private var handle: OpaquePointer?
    private let writable: Bool
    private let createdFromAbsence: Bool
    private var writerConfigured = false
    private var writeTransaction = false

    init(path: URL, writable: Bool, create: Bool = false, nonBlocking: Bool = false) throws {
        guard !create || writable else { throw DuoyiWidgetDatabaseFailure("invalid") }
        let kind = path.withUnsafeFileSystemRepresentation { $0.map { duoyi_store_path_kind($0) } ?? -1 }
        guard (create ? kind == 0 : kind == 1) else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        self.writable = writable
        self.createdFromAbsence = create
        var pointer: OpaquePointer?
        let flags = (writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_FULLMUTEX |
            (create ? SQLITE_OPEN_CREATE : 0) | duoyi_store_sqlite_nofollow_flag()
        let code = path.withUnsafeFileSystemRepresentation { sqlite3_open_v2($0, &pointer, flags, nil) }
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close_v2(pointer) }
            throw Self.failure(code)
        }
        handle = pointer
        do {
            try checked(sqlite3_extended_result_codes(pointer, 1))
            try checked(sqlite3_busy_timeout(pointer, nonBlocking ? 0 : 250))
        } catch {
            sqlite3_close_v2(pointer); handle = nil; throw error
        }
    }

    deinit { if let handle { sqlite3_close_v2(handle) } }

    func close() throws {
        guard let handle else { return }
        try checked(sqlite3_close(handle))
        self.handle = nil
        writeTransaction = false
    }

    private static func failure(_ code: Int32, schemaQuery: Bool = false) -> DuoyiWidgetDatabaseFailure {
        switch code & 0xff {
        case SQLITE_BUSY, SQLITE_LOCKED: return DuoyiWidgetDatabaseFailure("busy", code)
        case SQLITE_CORRUPT, SQLITE_NOTADB: return DuoyiWidgetDatabaseFailure("corrupt", code)
        case SQLITE_ERROR where schemaQuery: return DuoyiWidgetDatabaseFailure("corrupt", code)
        default: return DuoyiWidgetDatabaseFailure("unavailable", code)
        }
    }

    private func checked(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw Self.failure(code) }
    }

    private func execute(_ sql: String) throws {
        guard let handle else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        try checked(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    private func statement<T>(_ sql: String, schemaQuery: Bool = false,
                              _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let handle else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw Self.failure(code, schemaQuery: schemaQuery)
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func singleInteger(_ sql: String) throws -> Int64 {
        try statement(sql) { query in
            let first = sqlite3_step(query)
            guard first == SQLITE_ROW else { throw Self.failure(first) }
            guard sqlite3_column_count(query) == 1, sqlite3_column_type(query, 0) == SQLITE_INTEGER else {
                throw DuoyiWidgetDatabaseFailure("corrupt")
            }
            let value = sqlite3_column_int64(query, 0)
            let last = sqlite3_step(query)
            guard last == SQLITE_DONE else { throw Self.failure(last) }
            return value
        }
    }

    private func columnText(_ query: OpaquePointer, _ index: Int32) throws -> String {
        guard sqlite3_column_type(query, index) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(query, index) else { throw DuoyiWidgetDatabaseFailure("corrupt") }
        let bytes = Data(bytes: pointer, count: Int(sqlite3_column_bytes(query, index)))
        guard let string = String(data: bytes, encoding: .utf8) else { throw DuoyiWidgetDatabaseFailure("corrupt") }
        return string
    }

    func configureWriter() throws {
        guard writable, let handle, sqlite3_get_autocommit(handle) != 0 else { throw DuoyiWidgetDatabaseFailure("invalid") }
        if !createdFromAbsence {
            do {
                try beginRead()
                let previous = try readEnvelope()
                try commit()
                guard previous.envelope != nil else { throw DuoyiWidgetDatabaseFailure(previous.status) }
            } catch {
                try? rollback()
                throw error
            }
        }
        let journal: String = try statement("PRAGMA journal_mode=PERSIST") { query in
            let first = sqlite3_step(query)
            guard first == SQLITE_ROW else { throw Self.failure(first) }
            let value = try columnText(query, 0)
            let last = sqlite3_step(query)
            guard last == SQLITE_DONE else { throw Self.failure(last) }
            return value
        }
        guard journal.lowercased() == "persist" else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        try execute("PRAGMA synchronous=FULL")
        try execute("PRAGMA fullfsync=ON")
        guard try singleInteger("PRAGMA synchronous") == 2,
              try singleInteger("PRAGMA fullfsync") == 1 else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        writerConfigured = true
    }

    func beginRead() throws {
        guard let handle, sqlite3_get_autocommit(handle) != 0 else { throw DuoyiWidgetDatabaseFailure("invalid") }
        try execute("BEGIN")
        writeTransaction = false
    }

    func beginWrite() throws {
        guard writable, writerConfigured, let handle, sqlite3_get_autocommit(handle) != 0 else { throw DuoyiWidgetDatabaseFailure("invalid") }
        try execute("BEGIN IMMEDIATE")
        writeTransaction = true
    }

    func commit() throws {
        guard let handle, sqlite3_get_autocommit(handle) == 0 else { throw DuoyiWidgetDatabaseFailure("invalid") }
        try execute("COMMIT")
        writeTransaction = false
    }

    func rollback() throws {
        guard let handle else { throw DuoyiWidgetDatabaseFailure("unavailable") }
        defer { writeTransaction = false }
        if sqlite3_get_autocommit(handle) == 0 { try execute("ROLLBACK") }
    }

    func initializeSchema() throws {
        guard createdFromAbsence, writable, writeTransaction, let handle,
              sqlite3_get_autocommit(handle) == 0 else { throw DuoyiWidgetDatabaseFailure("invalid") }
        guard try singleInteger("PRAGMA user_version") == 0 else { throw DuoyiWidgetDatabaseFailure("corrupt") }
        try execute("CREATE TABLE publication (id INTEGER PRIMARY KEY CHECK(id = 1), envelope TEXT NOT NULL)")
        try execute("PRAGMA user_version=1")
    }

    func readEnvelope() throws -> DuoyiWidgetPublicationRead {
        guard let handle, sqlite3_get_autocommit(handle) == 0 else { throw DuoyiWidgetDatabaseFailure("invalid") }
        let version = try singleInteger("PRAGMA user_version")
        if version > 1 { return DuoyiWidgetPublicationRead("unsupported") }
        if version != 1 { return DuoyiWidgetPublicationRead("corrupt") }
        return try statement("SELECT id, envelope FROM publication", schemaQuery: true) { query in
            let first = sqlite3_step(query)
            if first == SQLITE_DONE { return DuoyiWidgetPublicationRead("corrupt") }
            guard first == SQLITE_ROW else { throw Self.failure(first) }
            guard sqlite3_column_type(query, 0) == SQLITE_INTEGER, sqlite3_column_int64(query, 0) == 1 else {
                return DuoyiWidgetPublicationRead("corrupt")
            }
            let encoded = try columnText(query, 1)
            let last = sqlite3_step(query)
            if last == SQLITE_ROW { return DuoyiWidgetPublicationRead("corrupt") }
            guard last == SQLITE_DONE else { throw Self.failure(last) }
            return DuoyiWidgetPublicationRow.decode(encoded)
        }
    }

    func writeReplacement(_ envelope: DuoyiWidgetPublicationEnvelope) throws {
        guard writable, writeTransaction, let handle, sqlite3_get_autocommit(handle) == 0,
              let encoded = DuoyiWidgetPublicationJSON.encode(envelope.toMap),
              encoded.utf8.count <= Int(Int32.max) else { throw DuoyiWidgetDatabaseFailure("invalid") }
        try statement("INSERT OR REPLACE INTO publication (id, envelope) VALUES (1, ?)") { query in
            let bound = encoded.withCString { duoyi_store_bind_text(query, 1, $0, Int32(encoded.utf8.count)) }
            try checked(bound)
            let result = sqlite3_step(query)
            guard result == SQLITE_DONE else { throw Self.failure(result) }
        }
    }
}
