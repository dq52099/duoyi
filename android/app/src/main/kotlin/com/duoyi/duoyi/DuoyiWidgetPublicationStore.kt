package com.duoyi.duoyi

import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteDatabaseCorruptException
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock

/** Explicit read state. A failed decoder is never permission to initialize. */
class DuoyiWidgetPublicationRead(val status: String, val envelope: DuoyiWidgetPublicationEnvelope? = null) {
    fun metadata(): Map<String, Any?> = linkedMapOf<String, Any?>("status" to status).apply {
        envelope?.let { putAll(it.readMetadata()) }
    }
}

/**
 * Canonical store only. No preference cache/mirror participates in acceptance.
 * Gate -> fixed file lock -> SQLite is the order for all host-owned readers/writers.
 */
class DuoyiWidgetPublicationStore private constructor(private val directory: File) {
    private val databaseFile = File(directory, "duoyi_widget_store_v1.sqlite")
    private val lockFile = File(directory, "duoyi_widget_store_v1.lock")
    private val gate = ReentrantLock()
    @Volatile private var quarantined = false

    fun read(nonBlocking: Boolean = false): DuoyiWidgetPublicationRead {
        if (quarantined) return DuoyiWidgetPublicationRead("durabilityUnknown")
        return try { locked(exclusive = false, nonBlocking = nonBlocking) {
            if (quarantined) return@locked DuoyiWidgetPublicationRead("durabilityUnknown")
            if (!databaseFile.exists()) return@locked DuoyiWidgetPublicationRead("absent")
            open(writable = false, nonBlocking = nonBlocking).use { db -> readEnvelope(db) }
        } ?: DuoyiWidgetPublicationRead("busy")
        } catch (error: StoreFailure) { DuoyiWidgetPublicationRead(error.status) }
        catch (_: SQLiteDatabaseCorruptException) { DuoyiWidgetPublicationRead("corrupt") }
        catch (_: Exception) { DuoyiWidgetPublicationRead("unavailable") }
    }

    /** The callback must not call store mutation; the lock spans final UI acceptance. */
    fun acceptSnapshot(expected: DuoyiWidgetPublicationEnvelope, accept: () -> Boolean): Boolean =
        try { locked(exclusive = false, nonBlocking = true) {
            if (quarantined || !databaseFile.exists()) return@locked false
            val latest = open(writable = false, nonBlocking = true).use { readEnvelope(it) }
            if (latest.envelope?.toMap() != expected.toMap()) return@locked false
            accept()
        } ?: false } catch (_: Exception) { false }

    /** Call on a worker queue. Plans acquire applied status only after commit + fresh readback. */
    fun mutate(request: DuoyiWidgetPublicationRequest): Map<String, Any?> {
        if (quarantined) return failure(request, "durabilityUnknown")
        val initialize = request.method == DuoyiWidgetPublicationRequest.OPEN && request.mode == "initialize"
        return try { locked(exclusive = true, nonBlocking = false, permitCreate = initialize) {
            if (quarantined) return@locked failure(request, "durabilityUnknown")
            val absent = !databaseFile.exists()
            if (absent && (!initialize || request.expectedStoreRevision != null)) return@locked failure(request, "revisionConflict")
            var attemptedCommit = false
            try {
                var planned: DuoyiWidgetPublicationPlan? = null
                open(writable = true, create = absent).use { db ->
                    db.beginTransaction()
                    try {
                        val current = if (absent) null else {
                            val read = readEnvelope(db)
                            if (read.envelope == null) return@locked failure(request, read.status)
                            read.envelope
                        }
                        val plan = DuoyiWidgetPublicationTransition.plan(current, request, System.currentTimeMillis(), ZoneId.systemDefault())
                        if (plan.status == "alreadyApplied") return@locked receiptAck(request, plan.replay!!, "alreadyApplied")
                        if (plan.replacement == null) return@locked failure(request, plan.status)
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
                    } finally {
                        db.endTransaction()
                    }
                }
                val replacement = planned!!.replacement!!
                // Close the committed connection; retain gate/exclusive file lock throughout.
                val persisted = open(writable = false).use { readEnvelope(it) }
                if (persisted.envelope?.toMap() != replacement.toMap()) {
                    quarantined = true
                    return@locked failure(request, "durabilityUnknown")
                }
                receiptAck(request, persisted.envelope.lastReceipt, "applied")
            } catch (error: StoreFailure) {
                if (attemptedCommit) { quarantined = true; failure(request, "durabilityUnknown") }
                else failure(request, error.status)
            } catch (_: SQLiteDatabaseCorruptException) {
                if (attemptedCommit) { quarantined = true; failure(request, "durabilityUnknown") }
                else failure(request, "corrupt")
            } catch (_: RuntimeException) {
                if (attemptedCommit) { quarantined = true; failure(request, "durabilityUnknown") }
                else failure(request, "unavailable")
            }
        } ?: failure(request, "busy")
        } catch (error: StoreFailure) { failure(request, error.status) }
        catch (_: Exception) { failure(request, "unavailable") }
    }

    private fun receiptAck(request: DuoyiWidgetPublicationRequest, receipt: DuoyiWidgetPublicationReceipt, status: String): Map<String, Any?> =
        linkedMapOf<String, Any?>("operationId" to receipt.operationId, "status" to status,
            "committedStoreRevision" to receipt.committedStoreRevision).apply {
            putAll(receipt.resultMetadata())
            if (request.method != DuoyiWidgetPublicationRequest.OPEN) remove("writerLeaseId")
        }

    private fun failure(request: DuoyiWidgetPublicationRequest, status: String): Map<String, Any?> =
        linkedMapOf("operationId" to request.operationId, "status" to status)

    private fun open(writable: Boolean, create: Boolean = false, nonBlocking: Boolean = false): SQLiteDatabase {
        val flags = (if (writable) SQLiteDatabase.OPEN_READWRITE else SQLiteDatabase.OPEN_READONLY) or
            SQLiteDatabase.NO_LOCALIZED_COLLATORS
        // Android's default corruption handler may delete the authoritative DB.
        // Explicit recovery owns that decision; opening a corrupt store never does.
        val db = SQLiteDatabase.openDatabase(databaseFile.path, null,
            flags or (if (create) SQLiteDatabase.CREATE_IF_NECESSARY else 0), DatabaseErrorHandler { })
        try {
            db.execSQL(if (nonBlocking) "PRAGMA busy_timeout=0" else "PRAGMA busy_timeout=250")
            if (writable) {
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
            if (rows.count != 1 || !rows.moveToFirst() || rows.getInt(0) != 1 || rows.isNull(1)) return DuoyiWidgetPublicationRead("corrupt")
            val encoded = rows.getString(1)
            val raw = DuoyiWidgetPublicationJson.decode(encoded) ?: return DuoyiWidgetPublicationRead("corrupt")
            val schema = DuoyiWidgetPublicationDocument.exactInteger(raw["storeSchemaVersion"])
            if (schema != null && schema != 1L) return DuoyiWidgetPublicationRead("unsupported")
            val envelope = DuoyiWidgetPublicationEnvelope.tryFromMap(raw) ?: return DuoyiWidgetPublicationRead("corrupt")
            // The store emits canonical JSON. Duplicate keys, lossy numbers,
            // trailing data or alternate encodings are not a healthy stored row.
            if (encoded != DuoyiWidgetPublicationJson.encode(envelope.toMap())) return DuoyiWidgetPublicationRead("corrupt")
            return DuoyiWidgetPublicationRead(if (envelope.active) "ready" else "sealed", envelope)
        }
    }

    private fun <T> locked(exclusive: Boolean, nonBlocking: Boolean, permitCreate: Boolean = false, block: () -> T): T? {
        if (gate.isHeldByCurrentThread) return null
        val gotGate = if (nonBlocking) gate.tryLock() else gate.tryLock(250, TimeUnit.MILLISECONDS)
        if (!gotGate) return null
        try {
            if (!databaseFile.exists() && !permitCreate) return block()
            if (!lockFile.exists()) {
                if (databaseFile.exists() || !permitCreate) throw StoreFailure("unavailable")
                if (!directory.exists() && !directory.mkdirs()) throw StoreFailure("unavailable")
                lockFile.createNewFile()
            }
            RandomAccessFile(lockFile, "rw").use { file ->
                val deadline = System.nanoTime() + if (nonBlocking) 0L else 250_000_000L
                while (true) {
                    val lock = try { file.channel.tryLock(0L, Long.MAX_VALUE, !exclusive) }
                    catch (_: OverlappingFileLockException) { null }
                    if (lock != null) return lock.use { block() }
                    if (nonBlocking || System.nanoTime() >= deadline) return null
                    Thread.sleep(5)
                }
            }
        } finally { gate.unlock() }
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

/** ASCII canonical JSON preserves every String UTF-16 code unit and exact integer. */
object DuoyiWidgetPublicationJson {
    fun encode(value: Any?): String = when (value) {
        null -> "null"
        is Boolean -> value.toString()
        is Int, is Long -> value.toString()
        is String -> buildString {
            append('"')
            value.forEach { c ->
                when {
                    c == '"' -> append("\\\"")
                    c == '\\' -> append("\\\\")
                    c.code < 32 || c.code > 126 -> append("\\u%04x".format(c.code))
                    else -> append(c)
                }
            }
            append('"')
        }
        is Map<*, *> -> value.keys.map { it as String }.sorted().joinToString(",", "{", "}") { key -> encode(key) + ":" + encode(value[key]) }
        else -> error("Unexpected store primitive")
    }

    fun decode(value: String): Map<String, Any?>? = try {
        fun convert(value: Any?): Any? = when (value) {
            JSONObject.NULL, null -> null
            is JSONObject -> value.keys().asSequence().associateWith { convert(value.get(it)) }
            is String, is Boolean, is Int, is Long -> value
            else -> throw IllegalArgumentException("Invalid store primitive")
        }
        @Suppress("UNCHECKED_CAST")
        (convert(JSONObject(value)) as Map<String, Any?>)
    } catch (_: Exception) { null }
}
