package com.duoyi.duoyi

import android.content.Context
import android.database.Cursor
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseCorruptException
import android.database.sqlite.SQLiteDatabaseLockedException
import android.database.sqlite.SQLiteTableLockedException
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.channels.OverlappingFileLockException
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock

/**
 * Canonical store only. No preference cache/mirror participates in acceptance.
 * Gate -> fixed file lock -> SQLite is the order for all host-owned readers/writers.
 */
class DuoyiWidgetPublicationStore private constructor(private val directory: File) {
    private val databaseFile = File(directory, "duoyi_widget_store_v1.sqlite")
    private val lockFile = File(directory, "duoyi_widget_store_v1.lock")
    private val gate = ReentrantLock()
    @Volatile private var quarantined = false
    private data class FileIdentity(val device: Long, val inode: Long)
    private var observedLock: FileIdentity? = null // accessed under gate

    fun read(nonBlocking: Boolean = false): DuoyiWidgetPublicationRead {
        if (quarantined) return DuoyiWidgetPublicationRead("durabilityUnknown")
        return try { locked(exclusive = false, nonBlocking = nonBlocking) {
            if (quarantined) return@locked DuoyiWidgetPublicationRead("durabilityUnknown")
            if (!databaseFile.exists()) return@locked DuoyiWidgetPublicationRead("absent")
            open(writable = false, nonBlocking = nonBlocking).use { db -> readEnvelope(db) }
        } ?: DuoyiWidgetPublicationRead("busy")
        } catch (error: StoreFailure) { DuoyiWidgetPublicationRead(error.status) }
        catch (_: SQLiteDatabaseCorruptException) { DuoyiWidgetPublicationRead("corrupt") }
        catch (error: Exception) {
            DuoyiWidgetPublicationRead(if (error is SQLiteDatabaseLockedException || error is SQLiteTableLockedException) "busy" else "unavailable")
        }
    }

    /** The callback must not call store mutation; the lock spans final UI acceptance. */
    fun acceptSnapshot(expected: DuoyiWidgetPublicationEnvelope, accept: () -> Boolean): Boolean =
        try { locked(exclusive = false, nonBlocking = true) {
            if (quarantined || !databaseFile.exists()) return@locked false
            val latest = open(writable = false, nonBlocking = true).use { readEnvelope(it) }
            if (latest.envelope?.toMap() != expected.toMap()) return@locked false
            accept()
        } ?: false } catch (_: Exception) { false }

    /** Facts only, including while quarantined. This never grants readiness or a lease. */
    fun inspectRecovery(): Map<String, Any?> = try {
        locked(exclusive = true, nonBlocking = false) {
            if (kind(databaseFile) != 1) throw StoreFailure("unavailable")
            // Existing READWRITE permits SQLite's own journal recovery. Do not
            // change journal policy or create authority merely to inspect it.
            open(writable = true, configureWriter = false).use { db ->
                db.beginTransaction()
                try {
                    val read = readEnvelope(db)
                    val envelope = read.envelope ?: throw StoreFailure(read.status)
                    val result = linkedMapOf<String, Any?>("status" to "inspected", "facts" to linkedMapOf(
                        "storeRevision" to envelope.storeRevision, "ownerEpoch" to envelope.ownerEpoch,
                        "binding" to envelope.binding?.toMap(), "desiredPresentation" to envelope.desiredPresentation.toMap(),
                        "appliedPresentationRevision" to envelope.document.presentationRevision,
                        "lastOperationId" to envelope.lastReceipt.operationId, "lastRequestDigest" to envelope.lastReceipt.requestDigest))
                    db.setTransactionSuccessful()
                    result
                } finally { db.endTransaction() }
            }
        } ?: mapOf("status" to "busy")
    } catch (error: Exception) { mapOf("status" to failureStatus(error)) }

    /** Call on a worker queue. Plans acquire applied status only after commit + fresh readback. */
    fun mutate(request: DuoyiWidgetPublicationRequest): Map<String, Any?> {
        val recovering = request.method == DuoyiWidgetPublicationRequest.RECOVER
        if (quarantined && !recovering) return failure(request, "durabilityUnknown")
        val initialize = request.method == DuoyiWidgetPublicationRequest.OPEN && request.mode == "initialize"
        return try { withGate(nonBlocking = false) {
            if (quarantined && !recovering) return@withGate failure(request, "durabilityUnknown")
            if (recovering) quarantined = true
            var attemptedCommit = false
            try {
                val acknowledgement = withFileLock(exclusive = true, nonBlocking = false, permitCreate = initialize,
                    requireDatabaseAfter = { attemptedCommit }) {
                    val absent = kind(databaseFile) == 0
                    if (absent && (!initialize || request.expectedStoreRevision != null)) return@withFileLock failure(request, "revisionConflict")
                    if (absent) {
                        // Observe the entry itself, including dangling links.
                        val artifacts = directory.list() ?: return@withFileLock failure(request, "unavailable")
                        if ("${databaseFile.name}-journal" in artifacts) return@withFileLock failure(request, "unavailable")
                    }
                    // Reject an absent plan before CREATE can leave an empty DB.
                    val initialPlan = if (absent) DuoyiWidgetPublicationTransition.plan(null, request, System.currentTimeMillis(), ZoneId.systemDefault()) else null
                    if (initialPlan != null && initialPlan.replacement == null) return@withFileLock failure(request, initialPlan.status)
                    var planned: DuoyiWidgetPublicationPlan? = null
                    open(writable = true, create = absent).use { db ->
                        db.beginTransaction()
                        try {
                            val current = if (absent) null else {
                                val read = readEnvelope(db)
                                if (read.envelope == null) return@withFileLock failure(request, read.status)
                                read.envelope
                            }
                            val plan = initialPlan ?: DuoyiWidgetPublicationTransition.plan(current, request, System.currentTimeMillis(), ZoneId.systemDefault())
                            if (plan.status == "alreadyApplied") return@withFileLock receiptAck(request, plan.replay!!, "alreadyApplied")
                            if (plan.replacement == null) return@withFileLock failure(request, plan.status)
                            if (absent) {
                                db.execSQL("CREATE TABLE publication (id INTEGER PRIMARY KEY CHECK(id = 1), envelope TEXT NOT NULL)")
                                db.version = DATABASE_VERSION
                            }
                            val encoded = DuoyiWidgetPublicationJson.encode(plan.replacement.toMap())
                            db.execSQL("INSERT OR REPLACE INTO publication (id, envelope) VALUES (1, ?)", arrayOf(encoded))
                            planned = plan
                            db.setTransactionSuccessful()
                            // endTransaction performs COMMIT; marking successful is not an acknowledgement.
                            attemptedCommit = true
                        } finally { db.endTransaction() }
                    }
                    val replacement = planned!!.replacement!!
                    // Close the committed connection; retain gate/exclusive file lock throughout.
                    val persisted = open(writable = false).use { readEnvelope(it) }
                    if (persisted.envelope?.toMap() != replacement.toMap()) {
                        quarantined = true
                        return@withFileLock failure(request, "durabilityUnknown")
                    }
                    receiptAck(request, persisted.envelope.lastReceipt, "applied")
                } ?: failure(request, "busy")
                // withFileLock has completed its final name/inode validation.
                // Keep the gate until quarantine release and result construction.
                if (recovering && acknowledgement["status"] == "applied") quarantined = false
                acknowledgement
            } catch (error: Exception) {
                if (attemptedCommit) {
                    quarantined = true
                    failure(request, "durabilityUnknown")
                } else failure(request, failureStatus(error))
            }
        } ?: failure(request, "busy")
        } catch (error: Exception) { failure(request, failureStatus(error)) }
    }

    private fun failureStatus(error: Exception): String = when (error) {
        is StoreFailure -> error.status
        is SQLiteDatabaseCorruptException -> "corrupt"
        is SQLiteDatabaseLockedException, is SQLiteTableLockedException -> "busy"
        else -> "unavailable"
    }

    private fun receiptAck(request: DuoyiWidgetPublicationRequest, receipt: DuoyiWidgetPublicationReceipt, status: String): Map<String, Any?> =
        linkedMapOf<String, Any?>("operationId" to receipt.operationId, "status" to status,
            "committedStoreRevision" to receipt.committedStoreRevision).apply {
            putAll(receipt.resultMetadata())
            if (request.method != DuoyiWidgetPublicationRequest.OPEN) remove("writerLeaseId")
        }

    private fun failure(request: DuoyiWidgetPublicationRequest, status: String): Map<String, Any?> =
        linkedMapOf("operationId" to request.operationId, "status" to status)

    private fun open(writable: Boolean, create: Boolean = false, nonBlocking: Boolean = false, configureWriter: Boolean = true): SQLiteDatabase {
        val flags = (if (writable) SQLiteDatabase.OPEN_READWRITE else SQLiteDatabase.OPEN_READONLY) or
            SQLiteDatabase.NO_LOCALIZED_COLLATORS
        // Android's default corruption handler may delete the authoritative DB.
        // Explicit recovery owns that decision; opening a corrupt store never does.
        val db = SQLiteDatabase.openDatabase(databaseFile.path, null,
            flags or (if (create) SQLiteDatabase.CREATE_IF_NECESSARY else 0), DatabaseErrorHandler { })
        try {
            val timeout = if (nonBlocking) 0 else 250
            // This PRAGMA returns the configured timeout even when assigning it.
            // Android's non-query execution API rejects statements returning rows.
            db.rawQuery("PRAGMA busy_timeout=$timeout", null).use {
                if (!it.moveToFirst() || it.getInt(0) != timeout) throw StoreFailure("unavailable")
            }
            if (writable && configureWriter) {
                if (!create) {
                    val previous = readEnvelope(db)
                    if (previous.envelope == null) throw StoreFailure(previous.status)
                }
                db.rawQuery("PRAGMA journal_mode=PERSIST", null).use {
                    if (!it.moveToFirst() || !it.getString(0).equals("persist", ignoreCase = true)) throw StoreFailure("unavailable")
                }
                db.execSQL("PRAGMA synchronous=FULL")
                db.rawQuery("PRAGMA synchronous", null).use {
                    if (!it.moveToFirst() || it.getInt(0) != 2) throw StoreFailure("unavailable")
                }
            }
            return db
        } catch (error: Throwable) { db.close(); throw error }
    }

    private fun readEnvelope(db: SQLiteDatabase): DuoyiWidgetPublicationRead {
        if (db.version > DATABASE_VERSION) return DuoyiWidgetPublicationRead("unsupported")
        if (db.version != DATABASE_VERSION) return DuoyiWidgetPublicationRead("corrupt")
        db.rawQuery("SELECT id, envelope FROM publication", null).use { rows ->
            // Getter coercion (or Int32 truncation) cannot establish the
            // singleton row's storage types or full identity.
            if (rows.count != 1 || !rows.moveToFirst() ||
                rows.getType(0) != Cursor.FIELD_TYPE_INTEGER || rows.getLong(0) != 1L ||
                rows.getType(1) != Cursor.FIELD_TYPE_STRING) return DuoyiWidgetPublicationRead("corrupt")
            return DuoyiWidgetPublicationRow.decode(rows.getString(1))
        }
    }

    private fun stat(file: File): StructStat? = try { Os.lstat(file.path) }
        catch (error: ErrnoException) { if (error.errno == OsConstants.ENOENT) null else throw StoreFailure("unavailable") }

    private fun kind(file: File): Int = stat(file)?.let {
        if (OsConstants.S_ISREG(it.st_mode)) 1 else if (OsConstants.S_ISDIR(it.st_mode)) 2 else 3
    } ?: 0

    private fun identity(stat: StructStat) = FileIdentity(stat.st_dev, stat.st_ino)

    private fun prepareDirectory(permitCreate: Boolean): Boolean {
        var prefix: File? = directory.absoluteFile
        while (prefix != null) {
            val currentKind = kind(prefix)
            if (currentKind != 0 && currentKind != 2) throw StoreFailure("unavailable")
            prefix = prefix.parentFile
        }
        if (directory.canonicalFile != directory.absoluteFile) throw StoreFailure("unavailable")
        if (kind(directory) == 0) {
            if (!permitCreate) return false
            if (!directory.mkdirs()) throw StoreFailure("unavailable")
        }
        if (kind(directory) != 2 || directory.canonicalFile != directory.absoluteFile) throw StoreFailure("unavailable")
        return true
    }

    private fun verifyArtifacts(requireDatabase: Boolean) {
        val databaseKind = kind(databaseFile)
        if (databaseKind !in 0..1 || requireDatabase && databaseKind != 1 ||
            kind(File(directory, "${databaseFile.name}-journal")) !in 0..1) throw StoreFailure("unavailable")
    }

    private fun <T> withGate(nonBlocking: Boolean, block: () -> T): T? {
        if (gate.isHeldByCurrentThread) return null
        val gotGate = if (nonBlocking) gate.tryLock() else gate.tryLock(250, TimeUnit.MILLISECONDS)
        if (!gotGate) return null
        try { return block() } finally { gate.unlock() }
    }

    private fun <T> locked(exclusive: Boolean, nonBlocking: Boolean, permitCreate: Boolean = false, block: () -> T): T? =
        withGate(nonBlocking) { withFileLock(exclusive, nonBlocking, permitCreate, block = block) }

    /** Caller holds the gate. Only explicit initialize may create the fixed lock. */
    private fun <T> withFileLock(exclusive: Boolean, nonBlocking: Boolean, permitCreate: Boolean = false,
                               requireDatabaseAfter: () -> Boolean = { false }, block: () -> T): T? {
        if (!prepareDirectory(permitCreate)) return block()
        val databaseKind = kind(databaseFile)
        if (databaseKind != 0 && databaseKind != 1) throw StoreFailure("unavailable")
        if (databaseKind == 0 && !permitCreate) return block()
        val before = stat(lockFile)
        val create = before == null && databaseKind == 0 && permitCreate && observedLock == null
        if (before == null && !create || before != null && !OsConstants.S_ISREG(before.st_mode)) throw StoreFailure("unavailable")
        val descriptor = Os.open(lockFile.path, OsConstants.O_RDWR or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW or
            (if (create) OsConstants.O_CREAT else 0), 0x180)
        try {
            val opened = Os.fstat(descriptor)
            if (!OsConstants.S_ISREG(opened.st_mode) || before != null && identity(before) != identity(opened)) throw StoreFailure("unavailable")
            // Os.open has no CREATE on recovery/read/mutation of an existing
            // store; stream wrappers provide the same FileChannel lock protocol.
            val channel = if (exclusive) FileOutputStream(descriptor).channel else FileInputStream(descriptor).channel
            channel.use {
                fun verifyName(requireDatabase: Boolean) {
                    val named = stat(lockFile) ?: throw StoreFailure("unavailable")
                    val actual = identity(Os.fstat(descriptor))
                    if (!OsConstants.S_ISREG(named.st_mode) || identity(named) != actual ||
                        observedLock != null && observedLock != actual) throw StoreFailure("unavailable")
                    observedLock = actual
                    verifyArtifacts(requireDatabase)
                }
                val deadline = System.nanoTime() + if (nonBlocking) 0L else 250_000_000L
                while (true) {
                    val lock = try { channel.tryLock(0L, Long.MAX_VALUE, !exclusive) }
                    catch (_: OverlappingFileLockException) { null }
                    if (lock != null) return lock.use {
                        verifyName(requireDatabase = databaseKind == 1)
                        val result = block()
                        verifyName(requireDatabase = databaseKind == 1 || requireDatabaseAfter())
                        result
                    }
                    if (nonBlocking || System.nanoTime() >= deadline) return null
                    Thread.sleep(5)
                }
            }
        } finally { if (descriptor.valid()) Os.close(descriptor) }
    }

    private class StoreFailure(val status: String) : RuntimeException()

    companion object {
        private const val DATABASE_VERSION = 1
        private val instances = mutableMapOf<String, DuoyiWidgetPublicationStore>()
        @Synchronized fun forContext(context: Context): DuoyiWidgetPublicationStore {
            // Supported Flutter Android minimum is >=21; this directory and its
            // DB/journal/fixed lock are excluded from Auto Backup together.
            val directory = File(context.applicationContext.noBackupFilesDir, "widget_publication_store")
            return instances.getOrPut(directory.canonicalPath) { DuoyiWidgetPublicationStore(directory) }
        }
    }
}
