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

    /** Writable SharedPreferences fake with apply() updates visible in memory immediately. */
    private class MemorySharedPreferences(initialValues: Map<String, Any> = emptyMap()) : SharedPreferences {
        private val lock = Any()
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

            override fun apply() = applyWrites()

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
