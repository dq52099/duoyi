package com.duoyi.duoyi

import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetFrameCoreTest {

    @Test
    fun immutableSnapshotCopiesMapAndStringSetAndExposesUnmodifiableViews() {
        val sourceSet = linkedSetOf("zh", "en")
        val source = linkedMapOf<String, Any?>(
            "payload" to "before",
            "allowed_locales" to sourceSet,
        )
        val snapshot = DuoyiWidgetFrameCore.immutableValues(source)

        source["payload"] = "after"
        source["added"] = true
        sourceSet += "fr"

        assertEquals("before", snapshot["payload"])
        assertFalse(snapshot.containsKey("added"))
        assertEquals(linkedSetOf("zh", "en"), snapshot["allowed_locales"])

        assertThrows(UnsupportedOperationException::class.java) {
            mutableMap(snapshot)["another"] = "value"
        }
        assertThrows(UnsupportedOperationException::class.java) {
            mutableStringSet(snapshot["allowed_locales"]).add("fr")
        }
        assertEquals(linkedSetOf("zh", "en"), snapshot["allowed_locales"])
    }

    @Test
    fun sessionTrustRequiresCanonicalDayStringIntOffsetAndNonblankStringNonce() {
        assertTrue(core().sessionTrusted)

        val invalidDays = listOf<Any?>(
            "2024-6-15",
            "2024/06/15",
            "2024-06-15T00:00:00",
            "2024-02-30",
            20240615,
            null,
        )
        invalidDays.forEach { value ->
            val values = baseValues().apply { put("widget_snapshot_day", value) }
            assertFalse("day should be rejected: $value", core(values).sessionTrusted)
        }

        val invalidOffsets = listOf<Any?>(0L, "0", 1081, -1081, false, null)
        invalidOffsets.forEach { value ->
            val values = baseValues().apply { put("widget_snapshot_utc_offset_minutes", value) }
            assertFalse("offset should be rejected: $value", core(values).sessionTrusted)
        }

        val invalidNonces = listOf<Any?>(42, "", "   ", null)
        invalidNonces.forEach { value ->
            val values = baseValues().apply { put("widget_account_nonce", value) }
            assertFalse("nonce should be rejected: $value", core(values).sessionTrusted)
        }
    }

    @Test
    fun sessionOffsetAcceptsOnlyItsInclusiveMinuteBounds() {
        listOf(-1080, 0, 1080).forEach { offset ->
            val values = baseValues().apply {
                put("widget_snapshot_utc_offset_minutes", offset)
            }
            assertTrue("valid Int offset should be trusted: $offset", core(values).sessionTrusted)
        }
    }

    @Test
    fun nonceRemainsByteForByteUnmodifiedInTheFrameSnapshot() {
        val nonce = "  session/雪 + caf\u00e9  "
        val values = baseValues().apply { put("widget_account_nonce", nonce) }
        val frame = core(values)

        assertEquals(nonce, frame.nonce)
        assertEquals(nonce, frame.rawValues["widget_account_nonce"])
        assertArrayEquals(
            nonce.toByteArray(StandardCharsets.UTF_8),
            frame.nonce!!.toByteArray(StandardCharsets.UTF_8),
        )
    }

    @Test
    fun staleValidSessionRemainsTrustedWhileMissingSessionIsUntrusted() {
        val staleValues = baseValues().apply { put("widget_snapshot_day", "2024-06-14") }
        val stale = core(staleValues)

        assertTrue(stale.sessionTrusted)
        assertFalse(stale.fresh)
        assertNull(reason(stale))

        val missing = core(mapOf("widget_locale" to "en"))
        assertFalse(missing.sessionTrusted)
        assertFalse(missing.fresh)
    }

    @Test
    fun onlyAnExactPublishedStateCanTrustAnOtherwiseValidSession() {
        val published = core()
        assertEquals(DuoyiWidgetPublicationDocument.State.PUBLISHED, published.publicationState)
        assertTrue(published.sessionTrusted)
        assertTrue(published.fresh)
        listOf<Any?>("cleared", "blocked", "PUBLISHED", " published ", "unknown", 1, null)
            .forEach { state ->
                val values = baseValues().apply { put("widget_publication_state", state) }
                val frame = core(values)
                assertFalse("unpublished state must not trust the session: $state", frame.sessionTrusted)
                assertFalse(frame.fresh)
                if (state != "cleared" && state != "blocked") assertNull(frame.publicationState)
            }
        assertFalse(core(baseValues().apply { remove("widget_publication_state") }).sessionTrusted)
    }

    @Test
    fun publicationStateOnlyChangeRejectsTheCapturedFrame() {
        val frame = core()
        val changed = baseValues().apply { put("widget_publication_state", "cleared") }
        assertEquals("data_changed", reason(frame, currentValues = changed))
    }

    @Test
    fun capturedLocalDayChangeAcrossMidnightRejectsTheFrame() {
        val start = clockAt("2024-06-15T23:59:59Z", elapsedMillis = 10_000L)
        val frame = core(
            values = baseValues(day = "2024-06-15"),
            clock = start,
        )
        val afterMidnight = clockAt("2024-06-16T00:00:01Z", elapsedMillis = 12_000L)

        assertEquals("day_changed", reason(frame, currentClock = afterMidnight))
    }

    @Test
    fun zoneChangeRejectsEvenWhenBothZonesHaveTheSameOffset() {
        val frame = core(clock = clockAt("2024-06-15T12:00:00Z", "UTC", 10_000L))
        val sameOffsetDifferentZone = clockAt("2024-06-15T12:00:00Z", "Africa/Abidjan", 10_000L)

        assertEquals(0, frame.clock.offsetMinutes)
        assertEquals(0, sameOffsetDifferentZone.offsetMinutes)
        assertEquals("zone_changed", reason(frame, currentClock = sameOffsetDifferentZone))
    }

    @Test
    fun daylightSavingOffsetChangeRejectsWithinTheSameZoneAndLocalDay() {
        val beforeTransition = clockAt("2024-03-10T06:59:59Z", "America/New_York", 20_000L)
        val values = baseValues(day = beforeTransition.day, offset = beforeTransition.offsetMinutes)
        val frame = core(values = values, clock = beforeTransition)
        val afterTransition = clockAt("2024-03-10T07:00:01Z", "America/New_York", 22_000L)

        assertEquals(beforeTransition.day, afterTransition.day)
        assertEquals(-300, beforeTransition.offsetMinutes)
        assertEquals(-240, afterTransition.offsetMinutes)
        assertEquals("offset_changed", reason(frame, currentClock = afterTransition))
    }

    @Test
    fun rawPayloadChangeRejectsDespiteAnUnchangedPublicationTuple() {
        val capturedValues = baseValues().apply {
            put("widget_publication_id", "publication-7")
            put("widget_published_at_millis", 123456L)
            put("anniversary_payload", "A")
        }
        val frame = core(capturedValues)
        val changedValues = capturedValues.toMutableMap().apply {
            put("anniversary_payload", "B")
        }

        assertEquals("publication-7", changedValues["widget_publication_id"])
        assertEquals(123456L, changedValues["widget_published_at_millis"])
        assertEquals("data_changed", reason(frame, currentValues = changedValues))
    }

    @Test
    fun changedWidgetOptionsRejectTheCapturedFrame() {
        val options = DuoyiWidgetFrameOptions(minWidth = 220, minHeight = 120, style = "ios")
        val frame = core(options = options)

        assertEquals(
            "options_changed",
            reason(frame, currentOptions = options.copy(minWidth = 221)),
        )
    }

    @Test
    fun changedSystemLocaleRejectsEvenWhenWidgetLanguageWouldMatch() {
        val frame = core(systemLocaleTag = "en-US")

        assertEquals(
            "locale_changed",
            reason(frame, currentSystemLocaleTag = "en-GB"),
        )
    }

    @Test
    fun languageSelectionSupportsChineseEnglishAndSystemFallback() {
        val chinesePreference = baseValues().apply { put("widget_locale", " zh-CN ") }
        val invalidPreference = baseValues().apply { put("widget_locale", "fr") }
        val invalidBoth = baseValues().apply { put("widget_locale", "fr") }

        assertEquals("zh", core(chinesePreference, systemLocaleTag = "en-US").language)
        assertEquals("en", core(invalidPreference, systemLocaleTag = "EN_gb").language)
        assertEquals("zh", core(invalidBoth, systemLocaleTag = "fr-FR").language)
    }

    @Test
    fun ordinaryWallAndElapsedProgressionIsAccepted() {
        val frame = core(clock = clockAt("2024-06-15T12:00:00Z", elapsedMillis = 10_000L))
        val progressed = clockAt("2024-06-15T12:00:05Z", elapsedMillis = 14_500L)

        assertNull(reason(frame, currentClock = progressed))
    }

    @Test
    fun wallAndElapsedClockJumpsAreRejected() {
        val frame = core(clock = clockAt("2024-06-15T12:00:00Z", elapsedMillis = 10_000L))

        assertEquals(
            "clock_changed",
            reason(frame, currentClock = clockAt("2024-06-15T12:00:05Z", elapsedMillis = 12_000L)),
        )
        assertEquals(
            "clock_changed",
            reason(frame, currentClock = clockAt("2024-06-15T11:59:55Z", elapsedMillis = 15_000L)),
        )
        assertEquals(
            "clock_changed",
            reason(frame, currentClock = clockAt("2024-06-15T12:00:01Z", elapsedMillis = 9_999L)),
        )
    }

    @Test
    fun runningCountdownCrossingItsEndRejectsTheFrame() {
        val startMillis = Instant.parse("2024-06-15T12:00:00Z").toEpochMilli()
        val values = baseValues().apply {
            put("focus_timer_running", true)
            put("focus_timer_count_up", false)
            put("focus_timer_ends_at_millis", startMillis + 5_000L)
        }
        val frame = core(
            values = values,
            clock = clockAt("2024-06-15T12:00:00Z", elapsedMillis = 10_000L),
        )
        val atEnd = clockAt("2024-06-15T12:00:05Z", elapsedMillis = 15_000L)

        assertEquals("timer_expired", reason(frame, currentClock = atEnd))
    }

    @Test
    fun effectiveModeRespectsMinimumSizeThresholdsAndModeBounds() {
        fun mode(width: Int, height: Int, preferred: String = "detailed"): String {
            val values = baseValues().apply { put("widget_display_mode_9", preferred) }
            return core(
                values = values,
                options = DuoyiWidgetFrameOptions(minWidth = width, minHeight = height),
            ).effectiveMode
        }

        assertEquals("compact", mode(179, 170))
        assertEquals("compact", mode(250, 99))
        assertEquals("standard", mode(249, 170))
        assertEquals("standard", mode(250, 169))
        assertEquals("detailed", mode(250, 170))
        assertEquals("compact", mode(300, 200, preferred = "compact"))
        assertEquals(
            "detailed",
            core(
                values = baseValues().apply { put("widget_display_mode_9", "detailed") },
                options = DuoyiWidgetFrameOptions(),
            ).effectiveMode,
        )
    }

    @Test
    fun frameAttemptsRejectFirstCaptureThenCommitSecondMatchingBuildBeforeEffect() {
        var captures = 0
        var builds = 0
        val events = mutableListOf<String>()
        val rejected = mutableListOf<String>()
        val committed = mutableListOf<String>()
        val effects = mutableListOf<Pair<Int, String>>()

        val accepted = DuoyiWidgetFrameAttempts.run(
            capture = {
                (++captures).also { events += "capture:$it" }
            },
            build = { frame ->
                (++builds).let { "views:$frame" }.also { events += "build:$frame" }
            },
            rejectionReason = { frame ->
                events += "check:$frame"
                if (frame == 1) "data_changed" else null
            },
            commit = { views ->
                events += "commit:$views"
                committed += views
            },
            acceptedEffect = { frame, views ->
                events += "effect:$frame:$views"
                effects += frame to views
            },
            rejected = { rejection ->
                events += "rejected:$rejection"
                rejected += rejection
            },
        )

        assertTrue(accepted)
        assertEquals(2, captures)
        assertEquals(2, builds)
        assertEquals(listOf("data_changed"), rejected)
        assertEquals(listOf("views:2"), committed)
        assertEquals(listOf(2 to "views:2"), effects)
        assertEquals(
            listOf(
                "capture:1", "build:1", "check:1", "rejected:data_changed",
                "capture:2", "build:2", "check:2", "commit:views:2", "effect:2:views:2",
            ),
            events,
        )
    }

    @Test
    fun frameAttemptsStopAfterTwoRejectedCapturesWithoutCommitOrEffect() {
        var captures = 0
        var builds = 0
        val rejected = mutableListOf<String>()
        val committed = mutableListOf<Int>()
        val effects = mutableListOf<Int>()

        val accepted = DuoyiWidgetFrameAttempts.run(
            capture = { ++captures },
            build = { frame -> ++builds; frame * 10 },
            rejectionReason = { frame -> "reject-$frame" },
            commit = { committed += it },
            acceptedEffect = { frame, _ -> effects += frame },
            rejected = { rejected += it },
        )

        assertFalse(accepted)
        assertEquals(2, captures)
        assertEquals(2, builds)
        assertEquals(listOf("reject-1", "reject-2"), rejected)
        assertTrue(committed.isEmpty())
        assertTrue(effects.isEmpty())
    }

    @Test
    fun throwingCommitDoesNotRunAcceptedEffect() {
        var captures = 0
        var builds = 0
        var commits = 0
        var effects = 0

        assertThrows(IllegalStateException::class.java) {
            DuoyiWidgetFrameAttempts.run(
                capture = { ++captures },
                build = { ++builds },
                rejectionReason = { null },
                commit = { commits++; throw IllegalStateException("commit failed") },
                acceptedEffect = { _, _ -> effects++ },
                rejected = { throw AssertionError("unexpected rejection: $it") },
            )
        }

        assertEquals(1, captures)
        assertEquals(1, builds)
        assertEquals(1, commits)
        assertEquals(0, effects)
    }

    private fun core(
        values: Map<String, *> = baseValues(),
        instant: String = "2024-06-15T12:00:00Z",
        zone: String = "UTC",
        elapsedMillis: Long = 10_000L,
        clock: DuoyiWidgetFrameClock = clockAt(instant, zone, elapsedMillis),
        options: DuoyiWidgetFrameOptions = DuoyiWidgetFrameOptions(),
        widgetId: Int = 9,
        systemLocaleTag: String = "en-US",
    ): DuoyiWidgetFrameCore = DuoyiWidgetFrameCore(
        values = values,
        clock = clock,
        options = options,
        widgetId = widgetId,
        systemLocaleTag = systemLocaleTag,
    )

    private fun baseValues(
        day: String = "2024-06-15",
        offset: Int = 0,
        nonce: String = "session-nonce",
    ): LinkedHashMap<String, Any?> = linkedMapOf(
        "widget_publication_state" to "published",
        "widget_snapshot_day" to day,
        "widget_snapshot_utc_offset_minutes" to offset,
        "widget_account_nonce" to nonce,
        "widget_locale" to "en",
    )

    private fun clockAt(
        instant: String,
        zone: String = "UTC",
        elapsedMillis: Long = 10_000L,
    ): DuoyiWidgetFrameClock = DuoyiWidgetFrameClock(
        wallMillis = Instant.parse(instant).toEpochMilli(),
        elapsedMillis = elapsedMillis,
        zone = ZoneId.of(zone),
    )

    private fun reason(
        frame: DuoyiWidgetFrameCore,
        currentValues: Map<String, *> = frame.rawValues,
        currentClock: DuoyiWidgetFrameClock = frame.clock,
        currentOptions: DuoyiWidgetFrameOptions = frame.options,
        currentSystemLocaleTag: String = frame.systemLocaleTag,
    ): String? = frame.rejectionReason(
        currentValues = currentValues,
        currentClock = currentClock,
        currentOptions = currentOptions,
        currentSystemLocaleTag = currentSystemLocaleTag,
    )

    @Suppress("UNCHECKED_CAST")
    private fun mutableMap(values: Map<String, *>): MutableMap<String, Any?> =
        values as MutableMap<String, Any?>

    @Suppress("UNCHECKED_CAST")
    private fun mutableStringSet(value: Any?): MutableSet<String> =
        value as MutableSet<String>
}
