package com.duoyi.duoyi

import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Exercises the real Store only on paths that must stop before Android SQLite. */
class DuoyiWidgetPublicationStoreAdmissionTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test(timeout = 5_000L)
    fun heldFixedFileLockRejectsReadsMutationAndAcceptanceWithoutChangingFiles() {
        val directory = temporaryFolder.newFolder("locked-store")
        val databaseFile = File(directory, DATABASE_NAME)
        val lockFile = File(directory, LOCK_NAME)
        // Deliberately not SQLite: reaching its open path must fail this test's busy assertion.
        val databaseBytes = "Store admission placeholder; never open as SQLite".toByteArray()
        val lockBytes = "fixed lock sentinel".toByteArray()
        databaseFile.writeBytes(databaseBytes)
        lockFile.writeBytes(lockBytes)
        val expectedFiles = mapOf(DATABASE_NAME to databaseBytes, LOCK_NAME to lockBytes)
        val (expected, request) = publicationFixture()
        val store = newStore(directory)
        var callbackCount = 0

        // A separate channel holds the actual OS file lock; no fake lock or Store gate is used.
        RandomAccessFile(lockFile, "rw").use { holder ->
            holder.channel.lock().use { heldLock ->
                assertTrue(heldLock.isValid)
                for (nonBlocking in listOf(true, false)) {
                    val read = store.read(nonBlocking = nonBlocking)
                    assertEquals("nonBlocking=$nonBlocking", "busy", read.status)
                    assertNull(read.envelope)
                }
                assertEquals(
                    mapOf("operationId" to request.operationId, "status" to "busy"),
                    store.mutate(request),
                )
                assertFalse(store.acceptSnapshot(expected) { callbackCount++; true })
                assertEquals(0, callbackCount)
                assertTrue("Store must not release the holder's lock", heldLock.isValid)
                assertDirectoryUnchanged(directory, expectedFiles)
            }
        }
        // Never call Store again after releasing the lock on this placeholder database.
        assertDirectoryUnchanged(directory, expectedFiles)
    }

    @Test(timeout = 5_000L)
    fun readingAbsentDirectoryReturnsAbsentWithoutCreatingIt() {
        val directory = File(temporaryFolder.root, "absent-store")
        assertFalse(directory.exists())
        val store = newStore(directory)

        for (nonBlocking in listOf(true, false)) {
            val read = store.read(nonBlocking = nonBlocking)
            assertEquals("nonBlocking=$nonBlocking", "absent", read.status)
            assertNull(read.envelope)
            assertFalse("read must not create the directory", directory.exists())
        }
        assertDirectoryUnchanged(temporaryFolder.root, emptyMap())
    }

    @Test(timeout = 5_000L)
    fun existingDatabaseWithoutFixedLockIsUnavailableAndDoesNotCreateALock() {
        val directory = temporaryFolder.newFolder("missing-lock-store")
        val databaseBytes = "Existing authoritative DB placeholder; do not repair".toByteArray()
        File(directory, DATABASE_NAME).writeBytes(databaseBytes)
        val expectedFiles = mapOf(DATABASE_NAME to databaseBytes)
        val (_, request) = publicationFixture()
        val store = newStore(directory)

        for (nonBlocking in listOf(true, false)) {
            val read = store.read(nonBlocking = nonBlocking)
            assertEquals("nonBlocking=$nonBlocking", "unavailable", read.status)
            assertNull(read.envelope)
            assertDirectoryUnchanged(directory, expectedFiles)
        }
        assertEquals(
            mapOf("operationId" to request.operationId, "status" to "unavailable"),
            store.mutate(request),
        )
        assertFalse(File(directory, LOCK_NAME).exists())
        assertDirectoryUnchanged(directory, expectedFiles)
    }

    @Test(timeout = 5_000L)
    fun absentDatabaseWithOrphanJournalCannotInitializeOrAlterArtifacts() {
        val directory = temporaryFolder.newFolder("orphan-journal-store")
        val lockBytes = "fixed lock sentinel".toByteArray()
        val journalBytes = "Uncertain old transaction; never reuse or remove".toByteArray()
        File(directory, LOCK_NAME).writeBytes(lockBytes)
        File(directory, "$DATABASE_NAME-journal").writeBytes(journalBytes)
        val expectedFiles = mapOf(LOCK_NAME to lockBytes, "$DATABASE_NAME-journal" to journalBytes)
        val store = newStore(directory)
        val request = initializeFixture()

        // A missing DB is observable as absent, but is not permission to reuse its journal.
        assertEquals("absent", store.read().status)
        assertDirectoryUnchanged(directory, expectedFiles)
        assertEquals(
            mapOf("operationId" to request.operationId, "status" to "unavailable"),
            store.mutate(request),
        )
        assertDirectoryUnchanged(directory, expectedFiles)
    }

    @Test(timeout = 5_000L)
    fun journalDirectoryAlsoBlocksInitializeWithoutChangingArtifacts() {
        val directory = temporaryFolder.newFolder("journal-directory-store")
        val lockBytes = "fixed lock sentinel".toByteArray()
        File(directory, LOCK_NAME).writeBytes(lockBytes)
        val journal = File(directory, "$DATABASE_NAME-journal").apply { mkdir() }
        val sentinel = File(journal, "preserve-me").apply { writeText("unrecognized artifact") }
        val store = newStore(directory)
        val request = initializeFixture()

        assertEquals(
            mapOf("operationId" to request.operationId, "status" to "unavailable"),
            store.mutate(request),
        )
        assertEquals(setOf(LOCK_NAME, journal.name), directory.list()!!.toSet())
        assertArrayEquals(lockBytes, File(directory, LOCK_NAME).readBytes())
        assertTrue(journal.isDirectory)
        assertEquals(setOf(sentinel.name), journal.list()!!.toSet())
        assertEquals("unrecognized artifact", sentinel.readText())
    }

    @Test(timeout = 5_000L)
    fun danglingJournalLinkIsAnArtifactAndCannotAuthorizeInitialize() {
        val directory = temporaryFolder.newFolder("dangling-journal-store")
        val lockBytes = "fixed lock sentinel".toByteArray()
        File(directory, LOCK_NAME).writeBytes(lockBytes)
        val journal = File(directory, "$DATABASE_NAME-journal").toPath()
        val missingTarget = File(directory, "missing-journal-target").toPath()
        Files.createSymbolicLink(journal, missingTarget.fileName)
        assertFalse("File.exists follows a dangling link", journal.toFile().exists())
        assertTrue(Files.isSymbolicLink(journal))
        val request = initializeFixture()

        assertEquals(
            mapOf("operationId" to request.operationId, "status" to "unavailable"),
            newStore(directory).mutate(request),
        )
        assertEquals(setOf(LOCK_NAME, journal.fileName.toString()), directory.list()!!.toSet())
        assertArrayEquals(lockBytes, File(directory, LOCK_NAME).readBytes())
        assertTrue(Files.isSymbolicLink(journal))
        assertEquals(missingTarget.fileName, Files.readSymbolicLink(journal))
        assertFalse(Files.exists(missingTarget))
    }

    @Test(timeout = 5_000L)
    fun orphanJournalAdmissionStillHonorsTheFixedFileLock() {
        val directory = temporaryFolder.newFolder("locked-orphan-journal-store")
        val lockBytes = "fixed lock sentinel".toByteArray()
        val journalBytes = "orphan journal sentinel".toByteArray()
        val lockFile = File(directory, LOCK_NAME).apply { writeBytes(lockBytes) }
        File(directory, "$DATABASE_NAME-journal").writeBytes(journalBytes)
        val request = initializeFixture()
        val store = newStore(directory)

        RandomAccessFile(lockFile, "rw").use { holder ->
            holder.channel.lock().use { heldLock ->
                assertEquals(
                    mapOf("operationId" to request.operationId, "status" to "busy"),
                    store.mutate(request),
                )
                assertTrue(heldLock.isValid)
                assertDirectoryUnchanged(directory, mapOf(LOCK_NAME to lockBytes, "$DATABASE_NAME-journal" to journalBytes))
            }
        }
    }

    private fun initializeFixture(): DuoyiWidgetPublicationRequest {
        val (expected, _) = publicationFixture()
        return DuoyiWidgetPublicationRequest.tryFromMap(
            DuoyiWidgetPublicationRequest.OPEN,
            linkedMapOf(
                "protocolVersion" to 1,
                "operationId" to "admission-initialize",
                "expectedStoreRevision" to null,
                "expectedOwnerEpoch" to null,
                "mode" to "initialize",
                "binding" to linkedMapOf("kind" to "account", "key" to "validated-workspace"),
                "presentation" to linkedMapOf(
                    "revision" to 4L,
                    "locale" to "zh",
                    "values" to DuoyiWidgetPublicationDocument.clearedValuesFrom(expected.document.values),
                ),
            ),
        ) ?: throw AssertionError("Independent initialize request must parse")
    }

    private fun newStore(directory: File): DuoyiWidgetPublicationStore =
        DuoyiWidgetPublicationStore::class.java.getDeclaredConstructor(File::class.java).let {
            it.isAccessible = true
            it.newInstance(directory)
        }

    private fun assertDirectoryUnchanged(directory: File, expected: Map<String, ByteArray>) {
        val names = directory.list() ?: throw AssertionError("Cannot list fixture directory")
        assertEquals("No DB, journal or lock file may be created or removed", expected.keys, names.toSet())
        expected.forEach { (name, bytes) ->
            val file = File(directory, name)
            assertTrue("$name must remain a regular file", file.isFile)
            assertArrayEquals("$name contents must remain unchanged", bytes, file.readBytes())
        }
    }

    private fun publicationFixture(): Pair<DuoyiWidgetPublicationEnvelope, DuoyiWidgetPublicationRequest> {
        // Copy the independent published-envelope fixture from PublicationDocumentTest.
        // Its private helpers stay untouched; never derive this manifest from production valueKeys.
        val values = linkedMapOf<String, Any?>().apply {
            FIXTURE_STRING_KEYS.forEachIndexed { index, key ->
                put(key, "  literal-$index:$key/雪 + cafe\u0301 %2F  ")
            }
            put("todo_top3_1", "  todo / 雪 + cafe\u0301 %2F \t")
            put("todo_top3_1_id", "  A/雪 + %2F  ")
            put("brand_app_title", "  Duoyi / 应用  ")
            putAll(mapOf(
                "todo_count" to 3L,
                "habit_percent" to 73L,
                "habit_active_count" to 6L,
                "pomodoro_today" to 2L,
                "focus_minutes_today" to 47L,
                "todo_top3_count" to 3L,
                "focus_timer_remaining_seconds" to 300L,
                "focus_timer_total_seconds" to 1500L,
                "widget_theme_corner_radius_dp" to 18L,
                "widget_theme_control_radius_dp" to 12L,
                "widget_theme_border_width_dp" to 1L,
                "widget_first_day_of_week" to 1L,
                "focus_timer_started_at_millis" to 0L,
                "focus_timer_ends_at_millis" to 0L,
                "focus_timer_count_up" to true,
                "focus_timer_running" to false,
                "widget_theme_dark" to true,
            ))
        }
        assertEquals("Independent complete fixture", 90, values.size)
        val document = linkedMapOf<String, Any?>(
            "schemaVersion" to 1,
            "ownerEpoch" to "  epoch/雪 + %2F  ",
            "publicationRevision" to 7L,
            "localeRevision" to 4L,
            "state" to "published",
            "locale" to "zh",
            "snapshotDay" to "2024-02-29",
            "snapshotUtcOffsetMinutes" to -480L,
            "capturedAtMillis" to 1709164800123L,
            "values" to values,
        )
        val expected = DuoyiWidgetPublicationEnvelope.tryFromMap(linkedMapOf(
            "storeSchemaVersion" to 1,
            "storeRevision" to 9L,
            "binding" to linkedMapOf("kind" to "account", "key" to "workspace-key"),
            "ownerEpoch" to "  epoch/雪 + %2F  ",
            "writerLeaseId" to "lease-1",
            "leaseState" to "active",
            "desiredPresentation" to linkedMapOf("revision" to 4L, "locale" to "zh"),
            "document" to document,
            "lastReceipt" to linkedMapOf(
                "operationId" to "operation-1",
                "requestDigest" to "a".repeat(64),
                "committedStoreRevision" to 9L,
                "resultMetadata" to linkedMapOf(
                    "ownerEpoch" to "  epoch/雪 + %2F  ",
                    "publicationRevision" to 7L,
                    "desiredPresentationRevision" to 4L,
                    "appliedPresentationRevision" to 4L,
                    "documentState" to "published",
                    "writerLeaseId" to "lease-1",
                ),
            ),
        )) ?: throw AssertionError("Independent expected envelope must parse")
        // Advancing presentation uses a valid lease/CAS and does not depend on today's capture.
        val request = DuoyiWidgetPublicationRequest.tryFromMap(
            DuoyiWidgetPublicationRequest.ADVANCE,
            linkedMapOf(
                "protocolVersion" to 1,
                "operationId" to "admission-advance",
                "expectedStoreRevision" to 9L,
                "expectedOwnerEpoch" to "  epoch/雪 + %2F  ",
                "writerLeaseId" to "lease-1",
                "desiredPresentation" to linkedMapOf("revision" to 5L, "locale" to "zh"),
            ),
        ) ?: throw AssertionError("Independent admission request must parse")
        return expected to request
    }

    companion object {
        private const val DATABASE_NAME = "duoyi_widget_store_v1.sqlite"
        private const val LOCK_NAME = "duoyi_widget_store_v1.lock"

        // Curated v1 strings, copied from the existing independent DocumentTest fixture.
        private val FIXTURE_STRING_KEYS = listOf(
            "brand_app_title",
            "nav_todo",
            "nav_habit",
            "nav_calendar",
            "nav_focus",
            "todo_top3_1",
            "todo_top3_1_id",
            "todo_top3_2",
            "todo_top3_2_id",
            "todo_top3_3",
            "todo_top3_3_id",
            "goal_highlight_1",
            "goal_highlight_1_id",
            "goal_highlight_2",
            "goal_highlight_2_id",
            "goal_highlight_3",
            "goal_highlight_3_id",
            "anniversary_highlight_1",
            "anniversary_highlight_1_id",
            "anniversary_highlight_2",
            "anniversary_highlight_2_id",
            "course_highlight_1",
            "course_highlight_1_id",
            "course_highlight_2",
            "course_highlight_2_id",
            "course_highlight_3",
            "course_highlight_3_id",
            "note_highlight_1",
            "note_highlight_1_id",
            "note_highlight_2",
            "note_highlight_2_id",
            "note_highlight_3",
            "note_highlight_3_id",
            "memorial_highlight_1",
            "memorial_highlight_1_id",
            "memorial_highlight_2",
            "memorial_highlight_2_id",
            "memorial_highlight_3",
            "memorial_highlight_3_id",
            "diary_highlight_1",
            "diary_highlight_1_id",
            "diary_highlight_2",
            "diary_highlight_2_id",
            "diary_highlight_3",
            "diary_highlight_3_id",
            "today_event_summary",
            "schedule_highlight_1",
            "schedule_highlight_1_id",
            "schedule_highlight_2",
            "schedule_highlight_2_id",
            "schedule_highlight_3",
            "schedule_highlight_3_id",
            "calendar_month_summary",
            "focus_summary",
            "habit_summary",
            "streak_summary",
            "next_focus_label",
            "focus_timer_label",
            "habit_quick_check_id",
            "habit_quick_check_label",
            "widget_theme_brand_id",
            "widget_theme_card_skin_id",
            "widget_theme_primary",
            "widget_theme_background",
            "widget_theme_surface",
            "widget_theme_nav_background",
            "widget_theme_border",
            "widget_theme_text",
            "widget_theme_muted_text",
            "widget_theme_on_primary",
            "widget_theme_accent_start",
            "widget_theme_accent_end",
            "widget_theme_background_asset_key",
        )
    }
}
