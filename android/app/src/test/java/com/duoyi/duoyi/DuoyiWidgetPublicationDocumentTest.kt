package com.duoyi.duoyi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetPublicationDocumentTest {

    @Test
    fun completePublishedFixtureMatchesIndependentTenFieldAndEightyNineValueManifest() {
        val rawValues = completeRawValues()
        val raw = rawDocument(values = rawValues)
        val document = requireDocument(raw, "complete published fixture should parse")

        assertEquals(10, EXPECTED_DOCUMENT_KEYS.size)
        assertEquals(89, EXPECTED_VALUE_KEYS.size)
        assertEquals(73, EXPECTED_STRING_KEYS.size)
        assertEquals(11, INT32_BOUNDS.size)
        assertEquals(2, LONG_VALUE_KEYS.size)
        assertEquals(3, BOOLEAN_KEYS.size)
        assertEquals(EXPECTED_DOCUMENT_KEYS, document.toMap().keys)
        assertEquals(EXPECTED_VALUE_KEYS, document.values.keys)
        assertEquals(EXPECTED_VALUE_KEYS, DuoyiWidgetPublicationDocument.valueKeys)
        assertEquals(expectedParsedValues(rawValues), document.values)
        assertEquals("  epoch/雪 + %2F  ", document.ownerEpoch)
        assertEquals("2024-02-29", document.snapshotDay)
        assertEquals(-480, document.snapshotUtcOffsetMinutes)
        assertEquals("zh", document.locale)

        assertEquals(
            "  todo / 雪 + cafe\u0301 %2F \t",
            document.values["todo_top3_1"],
        )
        assertEquals("  A/雪 + %2F  ", document.values["todo_top3_1_id"])
        assertEquals("  Duoyi / 应用  ", document.values["brand_app_title"])
        assertEquals(3, document.values["todo_count"])
        assertEquals(document.values["todo_count"], document.values["todo_top3_count"])
    }

    @Test
    fun inputAndDocumentMapsAreDefensiveAndProjectionsKeepAndroidTypes() {
        val raw = rawDocument(values = completeRawValues())
        val parserInputValues = rawValuesInPlace(raw)
        val literal = parserInputValues["todo_top3_1"]
        val document = requireDocument(raw, "complete published fixture should parse")

        parserInputValues["todo_top3_1"] = "changed after parse"
        parserInputValues["unmanifested_key"] = "must not enter the document"
        raw["ownerEpoch"] = "changed top-level input"
        assertEquals(literal, document.values["todo_top3_1"])
        assertFalse(document.values.containsKey("unmanifested_key"))
        assertEquals("  epoch/雪 + %2F  ", document.ownerEpoch)
        assertThrows(UnsupportedOperationException::class.java) {
            mutableValues(document.values)["todo_count"] = 99
        }

        val wireMap = document.toMap()
        assertEquals(EXPECTED_DOCUMENT_KEYS, wireMap.keys)
        assertEquals(1, wireMap["schemaVersion"])
        assertTrue(wireMap["schemaVersion"] is Int)
        assertTrue(wireMap["publicationRevision"] is Long)
        assertTrue(wireMap["localeRevision"] is Long)
        assertTrue(wireMap["capturedAtMillis"] is Long)
        assertEquals(-480, wireMap["snapshotUtcOffsetMinutes"])
        assertTrue(wireMap["snapshotUtcOffsetMinutes"] is Int)

        val copiedWireValues = mutableValues(wireMap["values"] as Map<String, Any>)
        copiedWireValues["todo_top3_1"] = "wire copy changed"
        assertEquals(literal, document.values["todo_top3_1"])

        val flat = document.toFlatValues()
        assertEquals(EXPECTED_FLAT_KEYS, flat.keys)
        assertEquals("published", flat["widget_publication_state"])
        assertFalse(document.values.containsKey("widget_publication_state"))
        assertEquals("  epoch/雪 + %2F  ", flat["widget_account_nonce"])
        assertEquals("zh", flat["widget_locale"])
        assertEquals("2024-02-29", flat["widget_snapshot_day"])
        assertEquals(-480, flat["widget_snapshot_utc_offset_minutes"])
        assertTrue(flat["widget_snapshot_utc_offset_minutes"] is Int)
        INT32_BOUNDS.keys.forEach { key ->
            assertTrue("$key flat projection must be Int", flat[key] is Int)
        }
        LONG_VALUE_KEYS.forEach { key ->
            assertTrue("$key flat projection must be Long", flat[key] is Long)
        }
        assertEquals(0L, flat["focus_timer_started_at_millis"])
        assertEquals(0L, flat["focus_timer_ends_at_millis"])
        assertTrue(flat["focus_timer_started_at_millis"] is Long)
        assertTrue(flat["focus_timer_ends_at_millis"] is Long)
        assertFalse(flat.containsKey("schemaVersion"))
        assertFalse(flat.containsKey("publicationRevision"))

        mutableValues(flat)["todo_count"] = 77
        mutableValues(flat)["widget_locale"] = "fr"
        assertEquals(3, document.values["todo_count"])
        assertEquals("zh", document.locale)
    }

    @Test
    fun stringAndBooleanFieldsRejectPrimitiveTypeCoercion() {
        EXPECTED_STRING_KEYS.forEach { key ->
            assertNull(
                "$key must reject a numeric value instead of coercing it to String",
                DuoyiWidgetPublicationDocument.tryFromMap(
                    changedValue(rawDocument(), key, 7),
                ),
            )
        }
        BOOLEAN_KEYS.forEach { key ->
            listOf<Any?>(0, 1L, 1.0, 1.0f, "true").forEach { invalid ->
                assertNull(
                    "$key must reject $invalid (${invalid?.javaClass?.simpleName})",
                    DuoyiWidgetPublicationDocument.tryFromMap(
                        changedValue(rawDocument(), key, invalid),
                    ),
                )
            }
        }
    }

    @Test
    fun everyInt32FieldAcceptsItsInclusiveBoundsAndRejectsOverflowAndNonIntegerTypes() {
        INT32_BOUNDS.forEach { (key, bounds) ->
            listOf(bounds.first, bounds.last).forEach { boundary ->
                val document = requireDocument(
                    rawWithInt32Value(key, boundary),
                    "$key should accept boundary $boundary",
                )
                assertEquals(boundary.toInt(), document.values[key])
                assertTrue("$key must parse as Int", document.values[key] is Int)
            }

            val invalidValues = listOf<Any?>(
                bounds.first - 1L,
                bounds.last + 1L,
                bounds.first.toDouble(),
                bounds.first.toFloat(),
                bounds.first.toString(),
                true,
                false,
            )
            invalidValues.forEach { invalid ->
                assertNull(
                    "$key must reject $invalid (${invalid?.javaClass?.simpleName})",
                    DuoyiWidgetPublicationDocument.tryFromMap(
                        rawWithInt32Value(key, invalid),
                    ),
                )
            }
        }
    }

    @Test
    fun timerMillisRemainLongAtZeroAndAtExactIntegerLimit() {
        LONG_VALUE_KEYS.forEach { key ->
            listOf(0L, DuoyiWidgetPublicationDocument.MAX_EXACT_INTEGER).forEach { value ->
                val document = requireDocument(
                    changedValue(rawDocument(), key, value),
                    "$key should accept $value",
                )
                assertEquals(value, document.values[key])
                assertTrue("$key must parse as Long", document.values[key] is Long)
                val flatValue = document.toFlatValues()[key]
                assertEquals(value, flatValue)
                assertTrue("$key flat projection must be Long", flatValue is Long)
            }

            listOf<Any?>(
                -1L,
                DuoyiWidgetPublicationDocument.MAX_EXACT_INTEGER + 1L,
                0.0,
                0.0f,
                "0",
                true,
            ).forEach { invalid ->
                assertNull(
                    "$key must reject $invalid (${invalid?.javaClass?.simpleName})",
                    DuoyiWidgetPublicationDocument.tryFromMap(
                        changedValue(rawDocument(), key, invalid),
                    ),
                )
            }
        }

        LONG_VALUE_KEYS.forEach { key ->
            val parsedFromSmallInt = requireDocument(
                changedValue(rawDocument(), key, 0),
                "$key should accept exact Int zero input",
            )
            assertEquals(0L, parsedFromSmallInt.values[key])
            assertTrue(parsedFromSmallInt.toFlatValues()[key] is Long)
        }
    }

    @Test
    fun metadataRevisionsCaptureTimeAndOffsetUseExactBoundsAndTypedProjection() {
        val exactLimit = DuoyiWidgetPublicationDocument.MAX_EXACT_INTEGER
        val longMetadata = listOf(
            "publicationRevision" to 1L,
            "localeRevision" to 0L,
            "capturedAtMillis" to 0L,
        )
        longMetadata.forEach { (key, minimum) ->
            requireDocument(
                changedTop(rawDocument(), key, minimum),
                "$key should accept its minimum $minimum",
            )
            val acceptedFromSmallInt = requireDocument(
                changedTop(rawDocument(), key, minimum.toInt()),
                "$key should accept exact Int input",
            )
            assertTrue(acceptedFromSmallInt.toMap()[key] is Long)
            val acceptedMaximum = requireDocument(
                changedTop(rawDocument(), key, exactLimit),
                "$key should accept exact maximum",
            )
            assertTrue(acceptedMaximum.toMap()[key] is Long)

            listOf<Any?>(
                -1L,
                exactLimit + 1L,
                minimum.toDouble(),
                minimum.toFloat(),
                minimum.toString(),
                true,
            ).forEach { invalid ->
                assertNull(
                    "$key must reject $invalid (${invalid?.javaClass?.simpleName})",
                    DuoyiWidgetPublicationDocument.tryFromMap(
                        changedTop(rawDocument(), key, invalid),
                    ),
                )
            }
        }
        assertNull(
            "published publicationRevision must be positive",
            DuoyiWidgetPublicationDocument.tryFromMap(
                changedTop(rawDocument(), "publicationRevision", 0L),
            ),
        )

        listOf(-1080L, 1080L).forEach { offset ->
            val document = requireDocument(
                changedTop(rawDocument(), "snapshotUtcOffsetMinutes", offset),
                "offset should accept boundary $offset",
            )
            assertEquals(offset.toInt(), document.snapshotUtcOffsetMinutes)
            assertTrue(document.toMap()["snapshotUtcOffsetMinutes"] is Int)
            assertTrue(document.toFlatValues()["widget_snapshot_utc_offset_minutes"] is Int)
        }
        listOf<Any?>(
            -1081L,
            1081L,
            0.0,
            0.0f,
            "0",
            true,
        ).forEach { invalid ->
            assertNull(
                "offset must reject $invalid (${invalid?.javaClass?.simpleName})",
                DuoyiWidgetPublicationDocument.tryFromMap(
                    changedTop(rawDocument(), "snapshotUtcOffsetMinutes", invalid),
                ),
            )
        }

        val schemaAsLong = requireDocument(
            changedTop(rawDocument(), "schemaVersion", 1L),
            "schema version 1 should accept exact Long input",
        )
        assertEquals(1, schemaAsLong.toMap()["schemaVersion"])
        assertTrue(schemaAsLong.toMap()["schemaVersion"] is Int)
        listOf<Any?>(0, 2, 1.0, 1.0f, "1", true).forEach { invalid ->
            assertNull(
                "schemaVersion must be exact integer 1: $invalid",
                DuoyiWidgetPublicationDocument.tryFromMap(
                    changedTop(rawDocument(), "schemaVersion", invalid),
                ),
            )
        }
    }

    @Test
    fun publishedDayUsesGregorianYearsOneThrough9999AndKeepsHistoricalDays() {
        listOf(
            "0001-01-01",
            "1900-02-28",
            "2000-02-29",
            "2024-02-29",
            "9999-12-31",
        ).forEach { day ->
            val document = requireDocument(
                changedTop(rawDocument(), "snapshotDay", day),
                "valid Gregorian day should parse: $day",
            )
            assertEquals(day, document.snapshotDay)
        }

        listOf<Any?>(
            "0000-12-31",
            "10000-01-01",
            "2024-00-01",
            "2024-13-01",
            "2024-01-00",
            "2024-02-30",
            "1900-02-29",
            "2024-2-09",
            "2024/02/29",
            20240229,
        ).forEach { day ->
            assertNull(
                "invalid published day must be rejected: $day",
                DuoyiWidgetPublicationDocument.tryFromMap(
                    changedTop(rawDocument(), "snapshotDay", day),
                ),
            )
        }
    }

    @Test
    fun schemaStateLocaleOwnerAndTodoCountInvariantsAreExact() {
        val unknownTopKey = rawDocument().apply { put("extra", "not in v1") }
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(unknownTopKey))
        val missingTopKey = rawDocument().apply { remove("locale") }
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(missingTopKey))

        val unknownValueKey = rawDocument().apply {
            mutableRawValues(this)["not_in_v1"] = "extra"
        }
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(unknownValueKey))
        val missingValueKey = rawDocument().apply {
            mutableRawValues(this).remove("focus_summary")
        }
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(missingValueKey))

        assertNull(
            DuoyiWidgetPublicationDocument.tryFromMap(
                changedTop(rawDocument(), "state", "PUBLISHED"),
            ),
        )
        assertNull(
            DuoyiWidgetPublicationDocument.tryFromMap(
                changedTop(rawDocument(), "locale", "en-US"),
            ),
        )
        assertNull(
            DuoyiWidgetPublicationDocument.tryFromMap(
                changedTop(rawDocument(), "locale", " zh "),
            ),
        )
        listOf("zh", "en").forEach { locale ->
            assertEquals(
                locale,
                requireDocument(
                    changedTop(rawDocument(), "locale", locale),
                    "supported locale should parse: $locale",
                ).locale,
            )
        }
        assertNull(
            DuoyiWidgetPublicationDocument.tryFromMap(
                changedTop(rawDocument(), "ownerEpoch", "  \t "),
            ),
        )
        listOf(
            "ownerEpoch" to 17,
            "state" to true,
            "locale" to false,
            "snapshotDay" to 20240229,
        ).forEach { (key, invalid) ->
            assertNull(
                "$key must reject the wrong primitive type",
                DuoyiWidgetPublicationDocument.tryFromMap(
                    changedTop(rawDocument(), key, invalid),
                ),
            )
        }

        val opaqueOwner = "  account/雪 + %2F  "
        val parsedOwner = requireDocument(
            changedTop(rawDocument(), "ownerEpoch", opaqueOwner),
            "nonblank opaque owner epoch should parse",
        )
        assertEquals(opaqueOwner, parsedOwner.ownerEpoch)
        assertEquals(opaqueOwner, parsedOwner.toFlatValues()["widget_account_nonce"])

        val unequalCounts = rawDocument()
        mutableRawValues(unequalCounts)["todo_top3_count"] = 4L
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(unequalCounts))
    }

    @Test
    fun ownerEpochUsesDartTrimWhitespaceForBlankChecksAndPreservesOpaqueCodeUnits() {
        val whitespaceOnlyEpochs = listOf(
            "\u0009", "\u000A", "\u000B", "\u000C", "\u000D", "\u0020",
            "\u0085", "\u00A0", "\u1680",
        ) + (0x2000..0x200A).map { it.toChar().toString() } + listOf(
            "\u2028", "\u2029", "\u202F", "\u205F", "\u3000", "\uFEFF",
        )

        whitespaceOnlyEpochs.forEach { ownerEpoch ->
            assertTrue(
                "Dart-trim whitespace must be blank: U+${ownerEpoch[0].code.toString(16)}",
                DuoyiWidgetPublicationDocument.wireBlank(ownerEpoch),
            )
            assertNull(
                "document must reject a whitespace-only ownerEpoch",
                DuoyiWidgetPublicationDocument.tryFromMap(
                    changedTop(rawDocument(), "ownerEpoch", ownerEpoch),
                ),
            )
            assertNull(
                "envelope must reject a whitespace-only ownerEpoch",
                DuoyiWidgetPublicationEnvelope.tryFromMap(rawEnvelope(ownerEpoch)),
            )
        }

        val opaqueOwners = listOf(
            "\u200B",
            "\u200Baccount/雪 + %2F\u200B",
            "\uFEFFaccount/雪 + %2F",
        )
        opaqueOwners.forEach { ownerEpoch ->
            assertFalse(
                "nonblank ownerEpoch must not be normalized: $ownerEpoch",
                DuoyiWidgetPublicationDocument.wireBlank(ownerEpoch),
            )

            val document = requireDocument(
                changedTop(rawDocument(), "ownerEpoch", ownerEpoch),
                "nonblank ownerEpoch should parse without normalization",
            )
            assertEquals(ownerEpoch, document.ownerEpoch)
            assertEquals(ownerEpoch, document.toMap()["ownerEpoch"])
            assertEquals(ownerEpoch, document.toFlatValues()["widget_account_nonce"])

            val envelope = requireEnvelope(
                rawEnvelope(ownerEpoch),
                "nonblank envelope ownerEpoch should parse without normalization",
            )
            assertEquals(ownerEpoch, envelope.ownerEpoch)
            assertEquals(ownerEpoch, envelope.document.ownerEpoch)
            assertEquals(ownerEpoch, envelope.lastReceipt.ownerEpoch)
            assertEquals(ownerEpoch, envelope.toMap()["ownerEpoch"])
            val metadataDocument = envelope.readMetadata()["document"] as Map<*, *>
            assertEquals(ownerEpoch, metadataDocument["ownerEpoch"])
            assertEquals(ownerEpoch, envelope.document.toFlatValues()["widget_account_nonce"])
        }
    }

    @Test
    fun clearedAndBlockedDocumentsRetainTwentyTwoPresentationValuesAndRejectEveryBusinessTamper() {
        assertEquals(22, PRESENTATION_KEYS.size)
        assertEquals(67, BUSINESS_VALUE_KEYS.size)
        assertEquals(EXPECTED_VALUE_KEYS, PRESENTATION_KEYS + BUSINESS_VALUE_KEYS)

        val complete = completeRawValues()
        val expectedTombstone = canonicalTombstoneValues()
        val cleared = DuoyiWidgetPublicationDocument.clearedValuesFrom(complete)
        val clearedValues = cleared ?: throw AssertionError("complete values should clear")
        assertEquals(expectedTombstone, clearedValues)
        PRESENTATION_KEYS.forEach { key ->
            assertEquals(
                "clear builder must preserve presentation field $key",
                expectedParsedValues(complete)[key],
                clearedValues[key],
            )
        }
        assertThrows(UnsupportedOperationException::class.java) {
            mutableValues(clearedValues)["todo_count"] = 1
        }

        val missing = completeRawValues().apply { remove("todo_count") }
        assertNull(DuoyiWidgetPublicationDocument.clearedValuesFrom(missing))
        val extra = completeRawValues().apply { put("unknown", "extra") }
        assertNull(DuoyiWidgetPublicationDocument.clearedValuesFrom(extra))
        val wrongType = completeRawValues().apply { put("todo_count", "3") }
        assertNull(DuoyiWidgetPublicationDocument.clearedValuesFrom(wrongType))

        listOf("cleared", "blocked").forEach { state ->
            val publicationRevision = if (state == "cleared") 0L else 9L
            val canonical = tombstoneDocument(state, publicationRevision, expectedTombstone)
            val parsed = requireDocument(canonical, "canonical $state document should parse")
            assertEquals(expectedTombstone, parsed.values)
            assertEquals(state, parsed.state.wire)
            assertEquals(state, parsed.toFlatValues()["widget_publication_state"])
            PRESENTATION_KEYS.forEach { key ->
                assertEquals(expectedParsedValues(complete)[key], parsed.values[key])
            }

            BUSINESS_VALUE_KEYS.forEach { key ->
                assertNull(
                    "$state must reject noncanonical business field $key",
                    DuoyiWidgetPublicationDocument.tryFromMap(
                        changedValue(canonical, key, noncanonicalBusinessValue(key)),
                    ),
                )
            }
        }

        val unequalTombstoneCounts = tombstoneDocument(
            "cleared",
            publicationRevision = 0L,
            values = expectedTombstone,
        )
        mutableRawValues(unequalTombstoneCounts)["todo_count"] = 1
        mutableRawValues(unequalTombstoneCounts)["todo_top3_count"] = 1
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(unequalTombstoneCounts))

        val nonemptyTombstoneDay = tombstoneDocument("blocked", 2L, expectedTombstone)
            .apply { put("snapshotDay", "2024-02-29") }
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(nonemptyTombstoneDay))
        val nonzeroTombstoneOffset = tombstoneDocument("cleared", 0L, expectedTombstone)
            .apply { put("snapshotUtcOffsetMinutes", 1) }
        assertNull(DuoyiWidgetPublicationDocument.tryFromMap(nonzeroTombstoneOffset))
    }

    private fun completeRawValues(): LinkedHashMap<String, Any?> =
        linkedMapOf<String, Any?>().apply {
            EXPECTED_STRING_KEYS.forEachIndexed { index, key ->
                put(key, "  literal-$index:$key/雪 + cafe\u0301 %2F  ")
            }
            put("todo_top3_1", "  todo / 雪 + cafe\u0301 %2F \t")
            put("todo_top3_1_id", "  A/雪 + %2F  ")
            put("brand_app_title", "  Duoyi / 应用  ")
            INT32_BOUNDS.keys.forEach { key -> put(key, defaultIntValue(key)) }
            LONG_VALUE_KEYS.forEach { key -> put(key, 0L) }
            BOOLEAN_KEYS.forEach { key -> put(key, key != "focus_timer_running") }
        }

    private fun expectedParsedValues(rawValues: Map<String, Any?>): LinkedHashMap<String, Any> =
        linkedMapOf<String, Any>().apply {
            EXPECTED_STRING_KEYS.forEach { key -> put(key, rawValues[key] as String) }
            INT32_BOUNDS.keys.forEach { key -> put(key, (rawValues[key] as Long).toInt()) }
            LONG_VALUE_KEYS.forEach { key -> put(key, rawValues[key] as Long) }
            BOOLEAN_KEYS.forEach { key -> put(key, rawValues[key] as Boolean) }
        }

    private fun canonicalTombstoneValues(): LinkedHashMap<String, Any> =
        expectedParsedValues(completeRawValues()).apply {
            BUSINESS_STRING_KEYS.forEach { put(it, "") }
            BUSINESS_INT32_KEYS.forEach { put(it, 0) }
            BUSINESS_LONG_KEYS.forEach { put(it, 0L) }
            BUSINESS_BOOLEAN_KEYS.forEach { put(it, false) }
        }

    private fun rawDocument(
        state: Any? = "published",
        ownerEpoch: Any? = "  epoch/雪 + %2F  ",
        publicationRevision: Any? = 7L,
        localeRevision: Any? = 4L,
        locale: Any? = "zh",
        snapshotDay: Any? = "2024-02-29",
        snapshotUtcOffsetMinutes: Any? = -480L,
        capturedAtMillis: Any? = 1709164800123L,
        values: Map<String, Any?> = completeRawValues(),
        schemaVersion: Any? = 1,
    ): LinkedHashMap<String, Any?> = linkedMapOf(
        "schemaVersion" to schemaVersion,
        "ownerEpoch" to ownerEpoch,
        "publicationRevision" to publicationRevision,
        "localeRevision" to localeRevision,
        "state" to state,
        "locale" to locale,
        "snapshotDay" to snapshotDay,
        "snapshotUtcOffsetMinutes" to snapshotUtcOffsetMinutes,
        "capturedAtMillis" to capturedAtMillis,
        "values" to LinkedHashMap(values),
    )

    private fun tombstoneDocument(
        state: String,
        publicationRevision: Long,
        values: Map<String, Any>,
    ): LinkedHashMap<String, Any?> = rawDocument(
        state = state,
        publicationRevision = publicationRevision,
        localeRevision = 4L,
        snapshotDay = "",
        snapshotUtcOffsetMinutes = 0L,
        capturedAtMillis = 123L,
        values = values,
    )

    private fun rawEnvelope(ownerEpoch: String): LinkedHashMap<String, Any?> {
        val storeRevision = 9L
        val publicationRevision = 7L
        val presentationRevision = 4L
        val leaseId = "lease-1"
        return linkedMapOf(
            "storeSchemaVersion" to DuoyiWidgetPublicationEnvelope.STORE_SCHEMA_VERSION,
            "storeRevision" to storeRevision,
            "binding" to linkedMapOf("kind" to "account", "key" to "workspace-key"),
            "ownerEpoch" to ownerEpoch,
            "writerLeaseId" to leaseId,
            "leaseState" to "active",
            "desiredPresentation" to linkedMapOf(
                "revision" to presentationRevision,
                "locale" to "zh",
            ),
            "document" to rawDocument(
                ownerEpoch = ownerEpoch,
                publicationRevision = publicationRevision,
                localeRevision = presentationRevision,
            ),
            "lastReceipt" to linkedMapOf(
                "operationId" to "operation-1",
                "requestDigest" to "a".repeat(64),
                "committedStoreRevision" to storeRevision,
                "resultMetadata" to linkedMapOf(
                    "ownerEpoch" to ownerEpoch,
                    "publicationRevision" to publicationRevision,
                    "desiredPresentationRevision" to presentationRevision,
                    "appliedPresentationRevision" to presentationRevision,
                    "documentState" to "published",
                    "writerLeaseId" to leaseId,
                ),
            ),
        )
    }

    private fun rawWithInt32Value(key: String, value: Any?): LinkedHashMap<String, Any?> {
        val raw = rawDocument()
        val values = mutableRawValues(raw)
        values[key] = value
        if (key == "todo_count") values["todo_top3_count"] = value
        if (key == "todo_top3_count") values["todo_count"] = value
        return raw
    }

    private fun changedTop(
        raw: Map<String, Any?>,
        key: String,
        value: Any?,
    ): LinkedHashMap<String, Any?> = LinkedHashMap(raw).apply { put(key, value) }

    private fun changedValue(
        raw: Map<String, Any?>,
        key: String,
        value: Any?,
    ): LinkedHashMap<String, Any?> = LinkedHashMap(raw).apply {
        mutableRawValues(this)[key] = value
    }

    private fun requireDocument(
        raw: Any?,
        reason: String,
    ): DuoyiWidgetPublicationDocument =
        DuoyiWidgetPublicationDocument.tryFromMap(raw) ?: throw AssertionError(reason)

    private fun requireEnvelope(
        raw: Any?,
        reason: String,
    ): DuoyiWidgetPublicationEnvelope =
        DuoyiWidgetPublicationEnvelope.tryFromMap(raw) ?: throw AssertionError(reason)

    private fun noncanonicalBusinessValue(key: String): Any = when (key) {
        in BUSINESS_STRING_KEYS -> "must-be-empty"
        in BUSINESS_INT32_KEYS -> 1
        in BUSINESS_LONG_KEYS -> 1L
        in BUSINESS_BOOLEAN_KEYS -> true
        else -> error("Unclassified business key: $key")
    }

    @Suppress("UNCHECKED_CAST")
    private fun mutableRawValues(raw: MutableMap<String, Any?>): MutableMap<String, Any?> {
        val current = raw["values"] as Map<String, Any?>
        val copy = LinkedHashMap(current)
        raw["values"] = copy
        return copy
    }

    @Suppress("UNCHECKED_CAST")
    private fun rawValuesInPlace(raw: Map<String, Any?>): MutableMap<String, Any?> =
        raw["values"] as MutableMap<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun mutableValues(values: Map<String, Any>): MutableMap<String, Any> =
        values as MutableMap<String, Any>

    private fun defaultIntValue(key: String): Long = when (key) {
        "todo_count", "todo_top3_count" -> 3L
        "habit_percent" -> 73L
        "habit_active_count" -> 6L
        "pomodoro_today" -> 2L
        "focus_minutes_today" -> 47L
        "focus_timer_remaining_seconds" -> 300L
        "focus_timer_total_seconds" -> 1500L
        "widget_theme_corner_radius_dp" -> 18L
        "widget_theme_control_radius_dp" -> 12L
        "widget_theme_border_width_dp" -> 1L
        else -> error("Unclassified Int32 key: $key")
    }

    companion object {
        private const val MAX_INT32 = 2_147_483_647L

        private val EXPECTED_DOCUMENT_KEYS = setOf(
            "schemaVersion",
            "ownerEpoch",
            "publicationRevision",
            "localeRevision",
            "state",
            "locale",
            "snapshotDay",
            "snapshotUtcOffsetMinutes",
            "capturedAtMillis",
            "values",
        )

        // This fixture is the curated cross-platform v1 manifest, independent of parser.valueKeys.
        private val EXPECTED_STRING_KEYS = listOf(
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

        private val INT32_BOUNDS = linkedMapOf(
            "todo_count" to (0L..MAX_INT32),
            "habit_percent" to (0L..100L),
            "habit_active_count" to (-1L..MAX_INT32),
            "pomodoro_today" to (0L..MAX_INT32),
            "focus_minutes_today" to (0L..MAX_INT32),
            "todo_top3_count" to (0L..MAX_INT32),
            "focus_timer_remaining_seconds" to (0L..MAX_INT32),
            "focus_timer_total_seconds" to (0L..MAX_INT32),
            "widget_theme_corner_radius_dp" to (0L..MAX_INT32),
            "widget_theme_control_radius_dp" to (0L..MAX_INT32),
            "widget_theme_border_width_dp" to (0L..MAX_INT32),
        )

        private val LONG_VALUE_KEYS = listOf(
            "focus_timer_started_at_millis",
            "focus_timer_ends_at_millis",
        )

        private val BOOLEAN_KEYS = listOf(
            "focus_timer_count_up",
            "focus_timer_running",
            "widget_theme_dark",
        )

        private val PRESENTATION_STRING_KEYS = listOf(
            "brand_app_title",
            "nav_todo",
            "nav_habit",
            "nav_calendar",
            "nav_focus",
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

        private val PRESENTATION_INT32_KEYS = listOf(
            "widget_theme_corner_radius_dp",
            "widget_theme_control_radius_dp",
            "widget_theme_border_width_dp",
        )

        private val PRESENTATION_BOOLEAN_KEYS = listOf("widget_theme_dark")
        private val BUSINESS_STRING_KEYS = EXPECTED_STRING_KEYS.filterNot {
            it in PRESENTATION_STRING_KEYS
        }
        private val BUSINESS_INT32_KEYS = INT32_BOUNDS.keys.filterNot {
            it in PRESENTATION_INT32_KEYS
        }
        private val BUSINESS_LONG_KEYS = LONG_VALUE_KEYS
        private val BUSINESS_BOOLEAN_KEYS = BOOLEAN_KEYS.filterNot {
            it in PRESENTATION_BOOLEAN_KEYS
        }
        private val PRESENTATION_KEYS = linkedSetOf<String>().apply {
            addAll(PRESENTATION_STRING_KEYS)
            addAll(PRESENTATION_INT32_KEYS)
            addAll(PRESENTATION_BOOLEAN_KEYS)
        }
        private val BUSINESS_VALUE_KEYS = linkedSetOf<String>().apply {
            addAll(BUSINESS_STRING_KEYS)
            addAll(BUSINESS_INT32_KEYS)
            addAll(BUSINESS_LONG_KEYS)
            addAll(BUSINESS_BOOLEAN_KEYS)
        }
        private val EXPECTED_VALUE_KEYS = linkedSetOf<String>().apply {
            addAll(EXPECTED_STRING_KEYS)
            addAll(INT32_BOUNDS.keys)
            addAll(LONG_VALUE_KEYS)
            addAll(BOOLEAN_KEYS)
        }
        private val EXPECTED_FLAT_KEYS = linkedSetOf<String>().apply {
            addAll(EXPECTED_VALUE_KEYS)
            addAll(
                listOf(
                    "widget_publication_state",
                    "widget_account_nonce",
                    "widget_locale",
                    "widget_snapshot_day",
                    "widget_snapshot_utc_offset_minutes",
                ),
            )
        }
    }
}
