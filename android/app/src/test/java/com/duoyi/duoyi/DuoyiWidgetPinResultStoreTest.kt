package com.duoyi.duoyi

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetPinResultStoreTest {
    @Test
    fun acceptedReceiptsStayRequestScopedUntilEachIsPolledAndCleared() {
        val preferences = MemorySharedPreferences(mapOf("unrelated_pref" to "keep"))
        val store = DuoyiWidgetPinResultStore(preferences)
        val first = pin("pin-a", kind = "todo", style = "compact", widgetId = 41)
        val second = pin("pin-b", kind = "habit", style = "detailed", widgetId = 42)

        // Both callbacks can be recorded before either caller's next poll.
        store.record(first)
        store.record(second)

        assertEquals(first.toPayload(), store.read(first.requestId))
        assertEquals(second.toPayload(), store.read(second.requestId))

        store.clear(first.requestId)

        assertNull(store.read(first.requestId))
        assertEquals(second.toPayload(), store.read(second.requestId))
        val persisted = preferences.snapshot()
        val firstKeys = DuoyiWidgetPinResultCore.keysFor(first.requestId)
        val secondKeys = DuoyiWidgetPinResultCore.keysFor(second.requestId)
        assertTrue(firstKeys.values.none(persisted::containsKey))
        assertTrue(secondKeys.values.all(persisted::containsKey))
        assertEquals("keep", persisted["unrelated_pref"])
    }

    @Test
    fun lateOlderCallbackAfterClearDoesNotReplaceNewerReceiptOrItsStyle() {
        val preferences = MemorySharedPreferences()
        val store = DuoyiWidgetPinResultStore(preferences)
        val olderLate = pin(
            "older-request",
            kind = "todo",
            style = "compact",
            widgetId = 51,
            confirmedAt = 100L,
        )
        val newer = pin(
            "newer-request",
            kind = "calendar",
            style = "detailed",
            widgetId = 52,
            confirmedAt = 200L,
        )

        store.record(olderLate)
        store.clear(olderLate.requestId)
        store.record(newer)
        store.record(olderLate)

        assertEquals(olderLate.toPayload(), store.read(olderLate.requestId))
        assertEquals(newer.toPayload(), store.read(newer.requestId))
        assertEquals("compact", store.read(olderLate.requestId)?.get("style"))
        assertEquals("detailed", store.read(newer.requestId)?.get("style"))
    }

    @Test
    fun legacySingleSlotIsReadableOnlyByItsRequestAndUsesHistoricalDefaults() {
        val requestId = "legacy-request"
        val preferences = MemorySharedPreferences(
            mapOf(
                "request_id" to requestId,
                "kind" to "todo",
            ),
        )
        val store = DuoyiWidgetPinResultStore(preferences)

        assertEquals(
            mapOf(
                "requestId" to requestId,
                "kind" to "todo",
                "style" to "",
                "widgetId" to 0,
                "status" to "",
                "confirmedAt" to 0L,
            ),
            store.read(requestId),
        )
        assertNull(store.read("another-request"))
    }

    @Test
    fun completeNamespacedRecordWinsAndWritingItLeavesLegacySlotUntouched() {
        val requestId = "same-request"
        val legacy = legacyValues(
            requestId = requestId,
            kind = "legacy-kind",
            style = "standard",
            widgetId = 61,
            status = "confirmed",
            confirmedAt = 600L,
        )
        val preferences = MemorySharedPreferences(legacy)
        val store = DuoyiWidgetPinResultStore(preferences)
        val namespaced = pin(
            requestId,
            kind = "new-kind",
            style = "compact",
            widgetId = 62,
            status = "confirmed_unverified",
            confirmedAt = 700L,
        )

        store.record(namespaced)

        assertEquals(namespaced.toPayload(), store.read(requestId))
        assertEquals(legacy, legacyValuesFrom(preferences.snapshot()))
    }

    @Test
    fun clearingMatchingLegacyReceiptRemovesItButClearingAnotherIdPreservesIt() {
        val requestId = "legacy-clear-target"
        val legacy = legacyValues(requestId = requestId, kind = "note")
        val initial = legacy.toMutableMap().apply { put("unrelated_pref", "keep") }
        val preferences = MemorySharedPreferences(initial)
        val store = DuoyiWidgetPinResultStore(preferences)

        store.clear("not-the-legacy-request")
        assertEquals(legacy, legacyValuesFrom(preferences.snapshot()))
        assertEquals("keep", preferences.snapshot()["unrelated_pref"])
        assertEquals(requestId, store.read(requestId)?.get("requestId"))

        store.clear(requestId)
        val afterClear = preferences.snapshot()
        assertTrue(legacy.keys.none(afterClear::containsKey))
        assertEquals("keep", afterClear["unrelated_pref"])
        assertNull(store.read(requestId))
    }

    @Test
    fun incompleteOrWrongTypedNamespacedRecordFallsBackToMatchingLegacyWithoutAffectingNeighbor() {
        val requestId = "damaged-request"
        val neighborId = "healthy-neighbor"
        val legacy = legacyValues(
            requestId = requestId,
            kind = "legacy-fallback",
            style = "standard",
            widgetId = 71,
            status = "confirmed",
            confirmedAt = 710L,
        )
        val healthy = pin(
            neighborId,
            kind = "calendar",
            style = "detailed",
            widgetId = 72,
        )

        val completeNewPayload = linkedMapOf<String, Any>(
            "requestId" to requestId,
            "kind" to "todo",
            "style" to "compact",
            "widgetId" to 73,
            "status" to "confirmed",
            "confirmedAt" to 730L,
        )
        val malformedNewRecords = mutableListOf<Map<String, Any>>()
        for (field in completeNewPayload.keys) {
            malformedNewRecords += completeNewPayload - field
        }
        for (field in completeNewPayload.keys) {
            val wrongTyped = completeNewPayload.toMutableMap()
            wrongTyped[field] = when (field) {
                "requestId", "kind", "style", "status" -> 123
                "widgetId" -> "73"
                "confirmedAt" -> 730 // Int instead of Long.
                else -> error("Unexpected pin receipt field: $field")
            }
            malformedNewRecords += wrongTyped
        }
        malformedNewRecords += completeNewPayload.toMutableMap().apply {
            put("requestId", "different-request-id")
        }
        for (malformedPayload in malformedNewRecords) {
            val malformedNamespacedValues = linkedMapOf<String, Any>()
            val namespacedKeys = DuoyiWidgetPinResultCore.keysFor(requestId)
            for ((payloadKey, value) in malformedPayload) {
                malformedNamespacedValues[namespacedKeys.getValue(payloadKey)] = value
            }
            val withLegacyPreferences = MemorySharedPreferences(
                legacy.toMutableMap().apply { putAll(malformedNamespacedValues) },
            )
            val withLegacyStore = DuoyiWidgetPinResultStore(withLegacyPreferences)
            withLegacyStore.record(healthy)

            assertEquals(legacyPayload(legacy), withLegacyStore.read(requestId))
            assertEquals(healthy.toPayload(), withLegacyStore.read(neighborId))

            val withoutLegacyStore = DuoyiWidgetPinResultStore(
                MemorySharedPreferences(malformedNamespacedValues),
            )
            withoutLegacyStore.record(healthy)

            assertNull(withoutLegacyStore.read(requestId))
            assertEquals(healthy.toPayload(), withoutLegacyStore.read(neighborId))
        }
    }

    @Test
    fun recreatedStoreReadsPersistedRequestScopedReceipt() {
        val originalPreferences = MemorySharedPreferences()
        val originalStore = DuoyiWidgetPinResultStore(originalPreferences)
        val expected = pin(
            "survives-recreation",
            kind = "schedule",
            style = "compact",
            widgetId = 81,
            confirmedAt = 810L,
        )
        originalStore.record(expected)

        // Model process recreation by constructing a fresh adapter and store over the
        // persisted snapshot, rather than retaining the first store's in-memory state.
        val restartedPreferences = MemorySharedPreferences(originalPreferences.snapshot())
        val restartedStore = DuoyiWidgetPinResultStore(restartedPreferences)

        assertEquals(expected.toPayload(), restartedStore.read(expected.requestId))
    }

    @Test
    fun blankRequestIdsNeverReadWriteOrClearAnyReceipt() {
        val existing = legacyValues(requestId = "kept-request", kind = "diary")
        val preferences = MemorySharedPreferences(existing)
        val store = DuoyiWidgetPinResultStore(preferences)
        val before = preferences.snapshot()

        store.record(pin("   ", kind = "todo", style = "compact", widgetId = 91))
        store.clear("")
        store.clear("   ")

        assertTrue(DuoyiWidgetPinResultCore.keysFor("").isEmpty())
        assertTrue(DuoyiWidgetPinResultCore.keysFor("   ").isEmpty())
        assertNull(store.read(""))
        assertNull(store.read("   "))
        assertEquals(before, preferences.snapshot())
        assertEquals("kept-request", store.read("kept-request")?.get("requestId"))
    }

    @Test
    fun confirmedUnverifiedStatusRoundTripsAsAConfirmationReceipt() {
        val preferences = MemorySharedPreferences()
        val store = DuoyiWidgetPinResultStore(preferences)
        val expected = pin(
            "launcher-without-widget-id",
            kind = "anniversary",
            style = "standard",
            widgetId = 0,
            status = "confirmed_unverified",
            confirmedAt = 920L,
        )

        store.record(expected)

        assertEquals(expected.toPayload(), store.read(expected.requestId))
    }

    @Test
    fun requestKeyNamespaceUsesTheCompleteRequestIdAndSixDistinctFields() {
        val first = DuoyiWidgetPinResultCore.keysFor("request:with:separators")
        val second = DuoyiWidgetPinResultCore.keysFor("request:with")

        assertEquals(
            setOf("requestId", "kind", "style", "widgetId", "status", "confirmedAt"),
            first.keys,
        )
        assertEquals(6, first.values.toSet().size)
        assertFalse(first.values.toSet().intersect(second.values.toSet()).isNotEmpty())
    }

    @Test
    fun javaHashCollidingRequestIdsRemainIndependentlyReadableAndClearable() {
        val firstId = "Aa"
        val secondId = "BB"
        assertEquals(firstId.hashCode(), secondId.hashCode())

        val preferences = MemorySharedPreferences()
        val store = DuoyiWidgetPinResultStore(preferences)
        val first = pin(firstId, kind = "todo", style = "compact", widgetId = 45)
        val second = pin(secondId, kind = "todo", style = "detailed", widgetId = 46)

        store.record(first)
        store.record(second)

        assertEquals(first.toPayload(), store.read(firstId))
        assertEquals(second.toPayload(), store.read(secondId))
        store.clear(firstId)
        assertNull(store.read(firstId))
        assertEquals(second.toPayload(), store.read(secondId))
        store.clear(secondId)
        assertNull(store.read(secondId))
    }

    @Test
    fun orphanBudgetKeeps64AndEvictsOldestArrivalInsteadOfIncomingAfterWallClockRollback() {
        val preferences = MemorySharedPreferences()
        val clock = FakeMonotonicClock()
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 64, nowMillis = clock::now),
        )
        val receipts = (0..64).map { index ->
            // Simulate a wall-clock rollback: arrival order, not confirmedAt, owns retention order.
            pin(
                "orphan-$index",
                kind = "todo",
                style = "standard",
                widgetId = index,
                confirmedAt = 10_000L - index,
            )
        }

        receipts.forEach(store::record)

        assertNull(store.read(receipts.first().requestId))
        receipts.drop(1).forEach { receipt ->
            assertEquals(receipt.toPayload(), store.read(receipt.requestId))
        }
    }

    @Test
    fun handoffProtectsReceiptUntilMonotonicExpiryThenPruneRestoresOrphanBudget() {
        val preferences = MemorySharedPreferences()
        val clock = FakeMonotonicClock(startMillis = 1_000L)
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1, nowMillis = clock::now),
        )
        val protected = pin("handoff-old", "todo", "compact", 101, confirmedAt = 100L)
        val orphan = pin("handoff-new", "habit", "detailed", 102, confirmedAt = 200L)

        store.record(protected)
        store.reserveHandoff(protected.requestId, durationMillis = 100L)
        store.record(orphan)

        assertEquals(protected.toPayload(), store.read(protected.requestId))
        assertEquals(orphan.toPayload(), store.read(orphan.requestId))
        assertEquals(100L, store.nextCleanupDelayMillis())

        clock.advanceBy(99L)
        assertEquals(1L, store.nextCleanupDelayMillis())
        store.prune()
        assertEquals(protected.toPayload(), store.read(protected.requestId))

        clock.advanceBy(1L)
        store.prune()

        assertNull(store.read(protected.requestId))
        assertEquals(orphan.toPayload(), store.read(orphan.requestId))
        assertNull(store.nextCleanupDelayMillis())
    }

    @Test
    fun monotonicRollbackDoesNotExpireHandoffOrEvictItsReceiptEarly() {
        val preferences = MemorySharedPreferences()
        val clock = FakeMonotonicClock(startMillis = 50_000L)
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1, nowMillis = clock::now),
        )
        val protected = pin("rollback-protected", "calendar", "standard", 111)
        val incoming = pin(
            "rollback-incoming",
            "note",
            "compact",
            112,
            confirmedAt = Long.MIN_VALUE,
        )

        store.record(protected)
        store.reserveHandoff(protected.requestId, durationMillis = 200L)
        clock.set(10L)
        store.prune()
        store.record(incoming)

        assertEquals(200L, store.nextCleanupDelayMillis())
        assertEquals(protected.toPayload(), store.read(protected.requestId))
        assertEquals(incoming.toPayload(), store.read(incoming.requestId))

        clock.set(50_199L)
        assertEquals(1L, store.nextCleanupDelayMillis())
        clock.set(50_200L)
        store.prune()

        assertNull(store.read(protected.requestId))
        assertEquals(incoming.toPayload(), store.read(incoming.requestId))
    }

    @Test
    fun releaseHandoffRemovesProtectionAndPrunesOnlyAfterExplicitRelease() {
        val preferences = MemorySharedPreferences()
        val clock = FakeMonotonicClock()
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1, nowMillis = clock::now),
        )
        val handedOff = pin("released-handoff", "note", "compact", 116, confirmedAt = 10L)
        val neighbor = pin("handoff-neighbor", "todo", "standard", 117, confirmedAt = 20L)

        store.record(handedOff)
        store.reserveHandoff(handedOff.requestId, durationMillis = 1_000L)
        store.record(neighbor)
        assertEquals(handedOff.toPayload(), store.read(handedOff.requestId))
        assertEquals(1_000L, store.nextCleanupDelayMillis())

        store.releaseHandoff(handedOff.requestId)

        assertNull(store.read(handedOff.requestId))
        assertEquals(neighbor.toPayload(), store.read(neighbor.requestId))
        assertNull(store.nextCleanupDelayMillis())
    }

    @Test
    fun activeWaitTokensDoNotTimeoutAndOldOrMismatchedEndCannotReleaseNewWait() {
        val preferences = MemorySharedPreferences()
        val clock = FakeMonotonicClock()
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1, nowMillis = clock::now),
        )
        val waiting = pin("active-wait", "diary", "standard", 121)
        val firstOrphan = pin("active-orphan-1", "todo", "compact", 122)
        val secondOrphan = pin("active-orphan-2", "todo", "compact", 123)
        val finalOrphan = pin("active-orphan-3", "todo", "compact", 124)

        store.record(waiting)
        store.reserveHandoff(waiting.requestId, durationMillis = 10L)
        val firstToken = store.beginWait(waiting.requestId, "screen-owner", timeoutMillis = 1L)
        assertTrue(firstToken != null)
        assertNull(store.nextCleanupDelayMillis()) // beginWait transfers and removes the handoff.

        clock.advanceBy(1_000L) // The accepted wait is engine-owned and has no timeout deadline.
        store.prune()
        store.record(firstOrphan)
        store.record(secondOrphan)
        assertEquals(waiting.toPayload(), store.read(waiting.requestId))

        val secondToken = requireNotNull(
            store.beginWait(waiting.requestId, "screen-owner", timeoutMillis = 1L),
        )
        assertFalse(firstToken == secondToken)
        store.endWait(waiting.requestId, "screen-owner", firstToken!!)
        store.endWait(waiting.requestId, "different-owner", secondToken)
        store.endWait("different-request", "screen-owner", secondToken)
        store.record(finalOrphan)

        assertEquals(waiting.toPayload(), store.read(waiting.requestId))
        store.endWait(waiting.requestId, "screen-owner", secondToken)
        store.prune()
        assertNull(store.read(waiting.requestId))
        assertEquals(finalOrphan.toPayload(), store.read(finalOrphan.requestId))
    }

    @Test
    fun releaseOwnerReleasesOnlyItsWaitsAndInvalidWaitRequestsAreRejected() {
        val preferences = MemorySharedPreferences()
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1),
        )
        val first = pin("owner-a", "todo", "compact", 131, confirmedAt = 10L)
        val second = pin("owner-b", "habit", "standard", 132, confirmedAt = 20L)
        val later = pin("owner-later", "calendar", "detailed", 133, confirmedAt = 30L)

        store.record(first)
        assertNull(store.beginWait("", "owner-a", timeoutMillis = 1L))
        assertNull(store.beginWait("nonblank", " ", timeoutMillis = 1L))
        assertNull(store.beginWait("nonblank", "owner-a", timeoutMillis = 0L))
        assertNull(store.beginWait("nonblank", "owner-a", timeoutMillis = -1L))
        val firstToken = store.beginWait(first.requestId, "owner-a", timeoutMillis = 10L)
        val secondToken = store.beginWait(second.requestId, "owner-b", timeoutMillis = 10L)
        assertTrue(firstToken != null)
        assertTrue(secondToken != null)
        store.record(second)

        store.releaseOwner("owner-a")
        store.record(later)

        assertNull(store.read(first.requestId))
        assertEquals(second.toPayload(), store.read(second.requestId))
        assertEquals(later.toPayload(), store.read(later.requestId))
        store.releaseOwner("owner-b")
        store.prune()
        assertNull(store.read(second.requestId))
    }

    @Test
    fun recreatedStoreSharesRetentionOnlyWhenStateIsSharedAndRestartPrunesExpiredLeases() {
        val preferences = MemorySharedPreferences()
        val clock = FakeMonotonicClock()
        val sameProcessRetention = DuoyiWidgetPinResultRetention(
            orphanLimit = 1,
            nowMillis = clock::now,
        )
        val originalStore = DuoyiWidgetPinResultStore(preferences, sameProcessRetention)
        val protected = pin("volatile-wait", "todo", "compact", 141, confirmedAt = 100L)
        val newer = pin("persisted-neighbor", "habit", "detailed", 142, confirmedAt = 200L)

        originalStore.record(protected)
        val token = originalStore.beginWait(protected.requestId, "owner", timeoutMillis = 1L)
        assertTrue(token != null)
        originalStore.record(newer)

        val sameProcessStore = DuoyiWidgetPinResultStore(preferences, sameProcessRetention)
        assertEquals(protected.toPayload(), sameProcessStore.read(protected.requestId))
        assertEquals(newer.toPayload(), sameProcessStore.read(newer.requestId))

        // A new process has persisted receipts but no live wait token; startup pruning reclaims it.
        val restartedStore = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1, nowMillis = clock::now),
        )
        restartedStore.prune()

        assertNull(restartedStore.read(protected.requestId))
        assertEquals(newer.toPayload(), restartedStore.read(newer.requestId))
    }

    @Test
    fun malformedOwnedNamespaceCountsTowardBudgetWhileUnknownAndLegacyKeysSurvive() {
        val malformedId = "malformed-owned"
        val malformedKeys = DuoyiWidgetPinResultCore.keysFor(malformedId)
        val legacyId = "legacy-protected"
        val legacy = legacyValues(legacyId, kind = "diary", style = "standard", widgetId = 151)
        val unknownKey = "receipt:unparseable:keep-this"
        val initial = linkedMapOf<String, Any>().apply {
            put(malformedKeys.getValue("requestId"), 999) // Wrong marker type still counts as owned.
            put(malformedKeys.getValue("kind"), "todo")
            put(malformedKeys.getValue("confirmedAt"), 10L)
            putAll(legacy)
            put(unknownKey, "unowned")
        }
        val preferences = MemorySharedPreferences(initial)
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1),
        )
        val incoming = pin("malformed-incoming", "calendar", "compact", 152, confirmedAt = 20L)

        assertNull(store.read(malformedId))
        assertEquals(legacyPayload(legacy), store.read(legacyId))
        store.record(incoming)

        val persisted = preferences.snapshot()
        assertTrue(malformedKeys.values.none(persisted::containsKey))
        assertEquals("unowned", persisted[unknownKey])
        assertEquals(legacy, legacyValuesFrom(persisted))
        assertEquals(legacyPayload(legacy), store.read(legacyId))
        assertEquals(incoming.toPayload(), store.read(incoming.requestId))
    }

    @Test
    fun incomingRecordAndOldestEvictionShareOneApplyAndKeepNativeSixFieldPayload() {
        val preferences = MemorySharedPreferences()
        val store = DuoyiWidgetPinResultStore(
            preferences,
            DuoyiWidgetPinResultRetention(orphanLimit = 1),
        )
        val oldest = pin("atomic-oldest", "todo", "standard", 161, confirmedAt = 1L)
        val incoming = pin(
            "atomic-incoming",
            "focus",
            "detailed",
            162,
            status = "confirmed_unverified",
            confirmedAt = 2L,
        )
        store.record(oldest)
        val appliesBeforeOverflow = preferences.applyCount

        store.record(incoming)

        assertEquals(appliesBeforeOverflow + 1, preferences.applyCount)
        assertNull(store.read(oldest.requestId))
        assertEquals(incoming.toPayload(), store.read(incoming.requestId))
        val values = preferences.snapshot()
        val keys = DuoyiWidgetPinResultCore.keysFor(incoming.requestId)
        assertEquals(
            setOf("requestId", "kind", "style", "widgetId", "status", "confirmedAt"),
            keys.keys,
        )
        assertEquals(6, keys.values.count(values::containsKey))
        assertEquals(incoming.requestId, values[keys.getValue("requestId")])
        assertEquals(incoming.kind, values[keys.getValue("kind")])
        assertEquals(incoming.style, values[keys.getValue("style")])
        assertEquals(incoming.widgetId, values[keys.getValue("widgetId")])
        assertEquals(incoming.status, values[keys.getValue("status")])
        assertEquals(incoming.confirmedAt, values[keys.getValue("confirmedAt")])
        assertTrue(values[keys.getValue("widgetId")] is Int)
        assertTrue(values[keys.getValue("confirmedAt")] is Long)
    }

    private fun pin(
        requestId: String,
        kind: String,
        style: String,
        widgetId: Int,
        status: String = "confirmed",
        confirmedAt: Long = 123L,
    ) = DuoyiWidgetPinResultCore.Record(
        requestId = requestId,
        kind = kind,
        style = style,
        widgetId = widgetId,
        status = status,
        confirmedAt = confirmedAt,
    )

    private fun legacyValues(
        requestId: String,
        kind: String = "",
        style: String = "",
        widgetId: Int = 0,
        status: String = "",
        confirmedAt: Long = 0L,
    ): Map<String, Any> = mapOf(
        "request_id" to requestId,
        "kind" to kind,
        "style" to style,
        "widget_id" to widgetId,
        "status" to status,
        "confirmed_at" to confirmedAt,
    )

    private fun legacyValuesFrom(values: Map<String, Any>): Map<String, Any> =
        values.filterKeys { key ->
            key in setOf("request_id", "kind", "style", "widget_id", "status", "confirmed_at")
        }

    private fun legacyPayload(values: Map<String, Any>): Map<String, Any> = mapOf(
        "requestId" to values.getValue("request_id"),
        "kind" to values.getValue("kind"),
        "style" to values.getValue("style"),
        "widgetId" to values.getValue("widget_id"),
        "status" to values.getValue("status"),
        "confirmedAt" to values.getValue("confirmed_at"),
    )

    private class FakeMonotonicClock(startMillis: Long = 0L) {
        private var currentMillis = startMillis

        fun now(): Long = currentMillis

        fun advanceBy(deltaMillis: Long) {
            currentMillis += deltaMillis
        }

        fun set(value: Long) {
            currentMillis = value
        }
    }

    /** Writable SharedPreferences fake with apply() updates visible in memory immediately. */
    private class MemorySharedPreferences(initialValues: Map<String, Any> = emptyMap()) : SharedPreferences {
        private val lock = Any()
        var applyCount: Int = 0
            private set
        private val values = linkedMapOf<String, Any>().apply {
            initialValues.forEach { (key, value) -> put(key, copyValue(value)) }
        }

        override fun getAll(): Map<String, *> = snapshot()

        override fun getString(key: String?, defValue: String?): String? =
            synchronized(lock) { (values[key] as String?) ?: defValue }

        @Suppress("UNCHECKED_CAST")
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
            synchronized(lock) {
                (values[key] as MutableSet<String>?)?.toMutableSet() ?: defValues?.toMutableSet()
            }

        override fun getInt(key: String?, defValue: Int): Int =
            synchronized(lock) { (values[key] as Int?) ?: defValue }

        override fun getLong(key: String?, defValue: Long): Long =
            synchronized(lock) { (values[key] as Long?) ?: defValue }

        override fun getFloat(key: String?, defValue: Float): Float =
            synchronized(lock) { (values[key] as Float?) ?: defValue }

        override fun getBoolean(key: String?, defValue: Boolean): Boolean =
            synchronized(lock) { (values[key] as Boolean?) ?: defValue }

        override fun contains(key: String?): Boolean = synchronized(lock) { values.containsKey(key) }

        override fun edit(): SharedPreferences.Editor = MemoryEditor()

        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?,
        ) = Unit

        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?,
        ) = Unit

        fun snapshot(): Map<String, Any> = synchronized(lock) {
            values.mapValues { (_, value) -> copyValue(value) }
        }

        private inner class MemoryEditor : SharedPreferences.Editor {
            private val writes = linkedMapOf<String, Any>()
            private val removals = linkedSetOf<String>()
            private var clearRequested = false

            override fun putString(key: String?, value: String?): SharedPreferences.Editor =
                if (value == null) remove(key) else put(key, value)

            override fun putStringSet(
                key: String?,
                values: MutableSet<String>?,
            ): SharedPreferences.Editor =
                if (values == null) remove(key) else put(key, values.toMutableSet())

            override fun putInt(key: String?, value: Int): SharedPreferences.Editor = put(key, value)
            override fun putLong(key: String?, value: Long): SharedPreferences.Editor = put(key, value)
            override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = put(key, value)
            override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = put(key, value)

            override fun remove(key: String?): SharedPreferences.Editor {
                val resolved = requireNotNull(key)
                writes.remove(resolved)
                removals += resolved
                return this
            }

            override fun clear(): SharedPreferences.Editor {
                clearRequested = true
                return this
            }

            override fun commit(): Boolean {
                applyWrites()
                return true
            }

            override fun apply() {
                applyWrites()
                applyCount++
            }

            private fun put(key: String?, value: Any): SharedPreferences.Editor {
                val resolved = requireNotNull(key)
                removals.remove(resolved)
                writes[resolved] = copyValue(value)
                return this
            }

            private fun applyWrites() {
                synchronized(lock) {
                    if (clearRequested) values.clear()
                    removals.forEach(values::remove)
                    writes.forEach { (key, value) -> values[key] = copyValue(value) }
                }
            }
        }

        private fun copyValue(value: Any): Any =
            if (value is Set<*>) LinkedHashSet(value) else value
    }
}
