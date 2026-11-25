package com.duoyi.duoyi

import android.database.sqlite.SQLiteDatabase
import android.system.Os
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.RandomAccessFile
import java.util.UUID
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android Os/SQLite tests. Never opens the application's publication directory. */
@RunWith(AndroidJUnit4::class)
class DuoyiWidgetPublicationStoreDeviceTest {
    private lateinit var root: File
    private lateinit var fixture: Map<String, Any?>
    private lateinit var published: DuoyiWidgetPublicationEnvelope

    @Before fun createIsolatedStore() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        // canonicalFile avoids /data/data aliases rejected by the production no-follow policy.
        root = File(instrumentation.targetContext.cacheDir.canonicalFile,
            "widget-store-instrumented-${UUID.randomUUID()}")
        check(root.mkdir())
        fixture = instrumentation.context.assets.open("widget-store-v1.json").bufferedReader().use {
            requireNotNull(DuoyiWidgetPublicationJson.decode(it.readText()))
        }
        published = requireNotNull(DuoyiWidgetPublicationEnvelope.tryFromMap(fixture["current"]))
    }

    @After fun removeOnlyOwnedFixture() {
        if (::root.isInitialized) {
            check(root.name.startsWith("widget-store-instrumented-"))
            check(root.deleteRecursively())
        }
    }

    @Test fun absentReadDoesNotCreateDirectoryOrLock() {
        val directory = File(root, "absent")
        for (nonBlocking in listOf(false, true)) {
            assertEquals("absent", store(directory).read(nonBlocking).status)
            assertFalse(directory.exists())
        }
        assertTrue(root.list()!!.isEmpty())
    }

    @Test fun absentOperationalMutationDoesNotCreateAuthority() {
        for (existingDirectory in listOf(false, true)) {
            val directory = File(root, "absent-mutate-$existingDirectory")
            if (existingDirectory) check(directory.mkdir())
            val ack = store(directory).mutate(advance(published))
            assertEquals("revisionConflict", ack["status"])
            assertEquals(existingDirectory, directory.exists())
            if (existingDirectory) assertTrue(directory.list()!!.isEmpty())
            assertFalse(File(directory, LOCK).exists())
            assertFalse(File(directory, DB).exists())
        }
    }

    @Test fun initializeCommitsAndFreshInstanceReadsTheExactReceipt() {
        val directory = File(root, "initialize")
        val request = initialize()
        val ack = store(directory).mutate(request)
        assertEquals("applied", ack["status"])
        assertNotNull(ack["writerLeaseId"])
        val actual = store(directory).read()
        assertEquals("ready", actual.status)
        val envelope = requireNotNull(actual.envelope)
        assertEquals(1L, envelope.storeRevision)
        assertEquals(request.operationId, envelope.lastReceipt.operationId)
        assertEquals(request.digest, envelope.lastReceipt.requestDigest)
        assertEquals(ack["ownerEpoch"], envelope.ownerEpoch)
        assertEquals(ack["writerLeaseId"], envelope.writerLeaseId)
        assertEquals(DuoyiWidgetPublicationDocument.State.CLEARED, envelope.document.state)
        assertEquals(envelope.toMap(), directRead(directory).toMap())
        // Receipt retry must not initialize a second workspace or advance its revision.
        assertEquals("alreadyApplied", store(directory).mutate(request)["status"])
        assertEquals(envelope.toMap(), directRead(directory).toMap())
    }

    @Test fun contextProvidedNoBackupPathSupportsTheProductionDirectoryPolicy() {
        // Exercise Context's unnormalized path as forContext does, without ever
        // touching the actual widget_publication_store or its cached instance.
        val base = InstrumentationRegistry.getInstrumentation().targetContext.noBackupFilesDir
        val owned = File(base, "widget-store-instrumented-${UUID.randomUUID()}")
        assertFalse(owned.exists())
        try {
            assertEquals("applied", store(owned).mutate(initialize())["status"])
            assertEquals("ready", store(owned).read().status)
        } finally {
            check(owned.deleteRecursively())
        }
    }

    @Test fun heldFixedLockRejectsReadMutationAndFinalAcceptance() {
        val directory = seeded("held-lock")
        val before = snapshot(directory)
        val target = store(directory)
        var accepted = 0
        RandomAccessFile(File(directory, LOCK), "rw").use { holder ->
            holder.channel.lock().use { lock ->
                assertEquals("busy", target.read(nonBlocking = true).status)
                assertEquals("busy", target.read(nonBlocking = false).status)
                assertEquals("busy", target.mutate(advance(published))["status"])
                assertFalse(target.acceptSnapshot(published) { accepted++; true })
                assertEquals(0, accepted)
                assertTrue(lock.isValid)
            }
        }
        assertEquals(before, snapshot(directory))
        assertEquals("ready", target.read().status)
    }

    @Test fun missingFixedLockCannotBeRecreatedForExistingDatabase() {
        val directory = seeded("missing-lock")
        assertTrue(File(directory, LOCK).delete())
        val before = snapshot(directory)
        val target = store(directory)
        assertEquals("unavailable", target.read().status)
        assertEquals("unavailable", target.mutate(advance(published))["status"])
        assertEquals("unavailable", target.inspectRecovery()["status"])
        assertFalse(target.acceptSnapshot(published) { fail("Missing lock accepted"); true })
        assertEquals(before, snapshot(directory))
    }

    @Test fun replacedFixedLockIsRejectedByAnAlreadyObservingStore() {
        val directory = seeded("replaced-lock")
        val target = store(directory)
        assertEquals("ready", target.read().status)
        val lock = File(directory, LOCK)
        // Keep the original inode alive, so its replacement cannot reuse that inode.
        assertTrue(lock.renameTo(File(directory, "old-lock")))
        lock.writeText("replacement lock")
        val before = snapshot(directory)
        assertEquals("unavailable", target.read().status)
        assertEquals("unavailable", target.mutate(advance(published))["status"])
        assertEquals(before, snapshot(directory))
    }

    @Test fun symlinkedFixedLockCannotAuthorizeReadOrWrite() {
        val directory = seeded("symlink-lock")
        val lock = File(directory, LOCK)
        val original = File(directory, "original-lock")
        assertTrue(lock.renameTo(original))
        Os.symlink(original.name, lock.path)
        val before = snapshot(directory)
        assertEquals("unavailable", store(directory).read().status)
        assertEquals("unavailable", store(directory).mutate(advance(published))["status"])
        assertEquals(original.name, Os.readlink(lock.path))
        assertEquals(before, snapshot(directory))
    }

    @Test fun orphanRegularJournalDoesNotAuthorizeInitialization() {
        val directory = emptyDirectory("orphan-journal")
        File(directory, LOCK).writeText("fixed lock")
        File(directory, "$DB-journal").writeText("uncertain transaction")
        val before = snapshot(directory)
        assertEquals("absent", store(directory).read().status)
        assertEquals("unavailable", store(directory).mutate(initialize())["status"])
        assertEquals(before, snapshot(directory))
        assertFalse(File(directory, DB).exists())
    }

    @Test fun danglingJournalSymlinkIsRetainedAndBlocksInitialization() {
        val directory = emptyDirectory("dangling-journal")
        File(directory, LOCK).writeText("fixed lock")
        val journal = File(directory, "$DB-journal")
        Os.symlink("nonexistent-transaction", journal.path)
        val before = snapshot(directory)
        assertEquals("unavailable", store(directory).mutate(initialize())["status"])
        assertEquals("nonexistent-transaction", Os.readlink(journal.path))
        assertFalse(File(directory, DB).exists())
        assertEquals(before, snapshot(directory))
    }

    @Test fun corruptDatabaseIsRetainedInsteadOfDeletedByAndroidErrorHandler() {
        val directory = emptyDirectory("corrupt")
        File(directory, LOCK).writeText("fixed lock")
        File(directory, DB).writeText("This is deliberately not a SQLite database.")
        val before = snapshot(directory)
        assertEquals("corrupt", store(directory).read().status)
        assertEquals(before, snapshot(directory))
    }

    @Test fun futureSchemaIsUnavailableForMutationAndPreservesTheRow() {
        val directory = seeded("future-schema")
        database(directory).use { it.version = 2 }
        val before = snapshot(directory)
        assertEquals("unsupported", store(directory).read().status)
        assertEquals("unsupported", store(directory).mutate(advance(published))["status"])
        assertEquals(before, snapshot(directory))
    }

    @Test fun textSingletonIdIsRejectedWithoutCursorCoercion() {
        val directory = seeded("text-id", typedId = false)
        assertEquals("corrupt", store(directory).read().status)
    }

    @Test fun fullWidthSingletonIdCannotBeTruncatedToOne() {
        val directory = seeded("wide-id", typedId = false)
        database(directory).use { it.execSQL("UPDATE publication SET id = 4294967297") }
        assertEquals("corrupt", store(directory).read().status)
    }

    @Test fun emptyPublicationTableCannotGrantSnapshotAcceptance() {
        val directory = seeded("empty-publication")
        database(directory).use { it.execSQL("DELETE FROM publication") }
        val before = snapshot(directory)
        val target = store(directory)
        var accepted = 0
        assertEquals("corrupt", target.read().status)
        assertFalse(target.acceptSnapshot(published) { accepted++; true })
        assertEquals(0, accepted)
        assertEquals(before, snapshot(directory))
    }

    @Test fun blobEnvelopeIsRejectedWithoutCursorStringCoercion() {
        val directory = seeded("blob-envelope")
        database(directory).use {
            it.execSQL("UPDATE publication SET envelope = ?", arrayOf(
                DuoyiWidgetPublicationJson.encode(published.toMap()).toByteArray()))
        }
        assertEquals("corrupt", store(directory).read().status)
    }

    @Test fun oldSnapshotCannotRenderAfterPresentationAdvances() {
        val directory = seeded("stale-render")
        val target = store(directory)
        var accepted = 0
        assertTrue(target.acceptSnapshot(published) { accepted++; true })
        assertEquals("applied", target.mutate(advance(published))["status"])
        assertFalse(target.acceptSnapshot(published) { accepted++; true })
        assertEquals(1, accepted)
        val current = requireNotNull(target.read().envelope)
        assertEquals(published.storeRevision + 1L, current.storeRevision)
        assertEquals(current.toMap(), directRead(directory).toMap())
    }

    @Test fun explicitRecoverySealsAndRequiresAFreshOperationAfterUncertainty() {
        val directory = seeded("recovery")
        val target = store(directory)
        assertEquals("inspected", target.inspectRecovery()["status"])
        val request = recover(published, "recovery-one")
        val ack = target.mutate(request)
        assertEquals("applied", ack["status"])
        assertFalse(ack.containsKey("writerLeaseId"))
        val sealed = requireNotNull(target.read().envelope)
        assertEquals("sealed", target.read().status)
        assertFalse(sealed.active)
        assertNull(sealed.binding)
        assertNull(sealed.writerLeaseId)
        assertNotEquals(published.ownerEpoch, sealed.ownerEpoch)
        assertEquals(DuoyiWidgetPublicationDocument.State.CLEARED, sealed.document.state)
        // A visible receipt alone must not release an uncertain recovery quarantine.
        assertEquals("durabilityUnknown", target.mutate(request)["status"])
        assertEquals("durabilityUnknown", target.read().status)
        // A syntactically valid old writer request must stop at quarantine,
        // before stale-owner/revision checks can select another status.
        assertEquals("durabilityUnknown", target.mutate(advance(published))["status"])
        var accepted = 0
        assertFalse(target.acceptSnapshot(sealed) { accepted++; true })
        assertEquals(0, accepted)
        assertEquals(sealed.toMap(), directRead(directory).toMap())
        assertEquals("inspected", target.inspectRecovery()["status"])
        assertEquals("applied", target.mutate(recover(sealed, "recovery-two"))["status"])
        assertEquals("sealed", target.read().status)
    }

    private fun store(directory: File): DuoyiWidgetPublicationStore =
        DuoyiWidgetPublicationStore::class.java.getDeclaredConstructor(File::class.java).let {
            it.isAccessible = true
            it.newInstance(directory)
        }

    private fun emptyDirectory(name: String) = File(root, name).apply { check(mkdir()) }

    private fun seeded(name: String, typedId: Boolean = true): File = emptyDirectory(name).also { directory ->
        File(directory, LOCK).writeText("fixed lock sentinel")
        SQLiteDatabase.openDatabase(File(directory, DB).path, null,
            SQLiteDatabase.CREATE_IF_NECESSARY).use { db ->
            db.rawQuery("PRAGMA journal_mode=PERSIST", null).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("persist", cursor.getString(0).lowercase())
            }
            db.execSQL("PRAGMA synchronous=FULL")
            db.version = 1
            db.execSQL(if (typedId) "CREATE TABLE publication (id INTEGER PRIMARY KEY CHECK(id=1), envelope TEXT NOT NULL)"
                else "CREATE TABLE publication (id, envelope)")
            db.execSQL("INSERT INTO publication VALUES (?, ?)", arrayOf(
                if (typedId) 1L else "1", DuoyiWidgetPublicationJson.encode(published.toMap())))
        }
    }

    private fun database(directory: File) = SQLiteDatabase.openDatabase(
        File(directory, DB).path, null, SQLiteDatabase.OPEN_READWRITE)

    private fun directRead(directory: File): DuoyiWidgetPublicationEnvelope =
        SQLiteDatabase.openDatabase(File(directory, DB).path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            assertEquals(1, db.version)
            db.rawQuery("SELECT id, envelope FROM publication", null).use { cursor ->
                assertEquals(1, cursor.count)
                assertTrue(cursor.moveToFirst())
                assertEquals(1L, cursor.getLong(0))
                requireNotNull(DuoyiWidgetPublicationEnvelope.tryFromMap(
                    DuoyiWidgetPublicationJson.decode(cursor.getString(1))))
            }
        }

    @Suppress("UNCHECKED_CAST")
    private fun presentation(): Map<String, Any?> = fixture["presentation"] as Map<String, Any?>

    private fun initialize() = request(DuoyiWidgetPublicationRequest.OPEN, linkedMapOf(
        "protocolVersion" to 1, "operationId" to "device-initialize",
        "expectedStoreRevision" to null, "expectedOwnerEpoch" to null,
        "mode" to "initialize", "binding" to published.binding!!.toMap(),
        "presentation" to presentation()))

    private fun advance(envelope: DuoyiWidgetPublicationEnvelope) = request(
        DuoyiWidgetPublicationRequest.ADVANCE, linkedMapOf(
            "protocolVersion" to 1, "operationId" to "device-advance",
            "expectedStoreRevision" to envelope.storeRevision, "expectedOwnerEpoch" to envelope.ownerEpoch,
            "writerLeaseId" to envelope.writerLeaseId,
            "desiredPresentation" to mapOf("revision" to envelope.desiredPresentation.revision + 1L,
                "locale" to envelope.desiredPresentation.locale)))

    private fun recover(envelope: DuoyiWidgetPublicationEnvelope, id: String) = request(
        DuoyiWidgetPublicationRequest.RECOVER, linkedMapOf(
            "protocolVersion" to 1, "operationId" to id,
            "expectedStoreRevision" to envelope.storeRevision, "expectedOwnerEpoch" to envelope.ownerEpoch,
            "presentation" to presentation(), "recoveryContext" to mapOf(
                "kind" to "cleanup", "scopeToken" to "isolated-device-test", "binding" to null)))

    private fun request(method: String, fields: Map<String, Any?>) =
        requireNotNull(DuoyiWidgetPublicationRequest.tryFromMap(method, fields))

    private fun snapshot(directory: File): Map<String, String> = directory.listFiles()!!.associate {
        it.name to if (android.system.OsConstants.S_ISLNK(Os.lstat(it.path).st_mode))
            "link:${Os.readlink(it.path)}" else it.readBytes().joinToString("") { b -> "%02x".format(b.toInt() and 255) }
    }

    companion object {
        private const val DB = "duoyi_widget_store_v1.sqlite"
        private const val LOCK = "duoyi_widget_store_v1.lock"
    }
}
