package com.duoyi.duoyi

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetDeviceDisplayValuesTest {
    @Test
    fun malformedRawGlobalModeReproducesTheTypedReadFailure() {
        val raw = publication("cleared").toFlatValues().toMutableMap()
        raw["widget_display_mode"] = 2
        val frame = frame(raw)
        assertThrows(ClassCastException::class.java) {
            DuoyiWidgetDisplayMode.isCompact(frame.prefs, 3)
        }
    }

    @Test
    fun onlyExactSupportedStringModesAreAdmitted() {
        val malformed = listOf<Any?>(null, 2, 2L, true, 0.5f, setOf("compact"),
            "", "COMPACT", " compact ", "unknown")
        for (value in malformed) {
            assertTrue(DuoyiWidgetFrameCore.deviceDisplayValues(mapOf(
                "widget_display_mode" to value,
                "widget_display_mode_3" to value,
            ), 3).isEmpty())
        }
        for (mode in listOf("compact", "standard", "detailed")) {
            assertEquals(mapOf("widget_display_mode" to mode, "widget_display_mode_3" to mode),
                DuoyiWidgetFrameCore.deviceDisplayValues(mapOf(
                    "widget_display_mode" to mode, "widget_display_mode_3" to mode), 3))
        }
    }

    @Test
    fun preferencesCannotSupplyPublicationOrOtherWidgetsValues() {
        val input = linkedMapOf<String, Any?>(
            "widget_display_mode" to "detailed",
            "widget_display_mode_3" to "compact",
            "widget_display_mode_4" to "standard",
            "widget_display_mode_0" to "compact",
            "widget_publication_state" to "published",
            "widget_account_nonce" to "previous-account",
            "todo_top3_1_id" to "previous-task",
            "focus_timer_running" to true,
        )
        val selected = DuoyiWidgetFrameCore.deviceDisplayValues(input, 3)
        assertEquals(mapOf("widget_display_mode" to "detailed", "widget_display_mode_3" to "compact"), selected)
        input["widget_display_mode"] = "standard"
        assertEquals("detailed", selected["widget_display_mode"])
        assertEquals(mapOf("widget_display_mode" to "standard"),
            DuoyiWidgetFrameCore.deviceDisplayValues(input, 0))
    }

    @Test
    fun weekStartIsAnIntegerPublicationValueAndCannotBeOverriddenByDevicePreferences() {
        val publication = publication("published").toFlatValues()
        assertEquals(1, publication["widget_first_day_of_week"])
        assertTrue(publication["widget_first_day_of_week"] is Int)

        val deviceValue = mapOf("widget_first_day_of_week" to 7)
        assertTrue(DuoyiWidgetFrameCore.deviceDisplayValues(deviceValue, 3).isEmpty())

        val captured = captured(
            "published",
            deviceValue + ("widget_display_mode" to "compact"),
        )
        assertEquals(1, captured.prefs.getInt("widget_first_day_of_week", -1))
        assertTrue(DuoyiWidgetDisplayMode.isCompact(captured.prefs, 3))
    }

    @Test
    fun validInstancePrecedesGlobalAndInvalidInstanceFallsBackSafely() {
        fun rendered(global: Any?, instance: Any?) = captured("published", mapOf(
            "widget_display_mode" to global, "widget_display_mode_3" to instance))
        assertTrue(DuoyiWidgetDisplayMode.isCompact(rendered("detailed", "compact").prefs, 3))
        assertTrue(DuoyiWidgetDisplayMode.isDetailed(rendered("detailed", true).prefs, 3))
        assertTrue(DuoyiWidgetDisplayMode.isCompact(rendered(2, "compact").prefs, 3))
        val standard = rendered(2, true)
        assertEquals("standard", standard.core.effectiveMode)
        assertFalse(DuoyiWidgetDisplayMode.isCompact(standard.prefs, 3))
        assertFalse(DuoyiWidgetDisplayMode.isDetailed(standard.prefs, 3))
    }

    @Test
    fun everyCanonicalStateRendersWithMalformedDeviceModesAndNoLegacyContent() {
        val malformed = listOf<Any?>(null, 2, 2L, true, 0.5f, setOf("compact"), "unknown")
        for (state in listOf("published", "cleared", "blocked")) {
            for (value in malformed) {
                val frame = captured(state, mapOf(
                    "widget_display_mode" to value,
                    "widget_display_mode_3" to value,
                    "todo_top3_1_id" to "previous-account-task",
                    "focus_timer_running" to true,
                    "widget_publication_state" to "published",
                ))
                assertEquals("standard", frame.core.effectiveMode)
                assertFalse(DuoyiWidgetDisplayMode.isCompact(frame.prefs, 3))
                assertFalse(DuoyiWidgetDisplayMode.isDetailed(frame.prefs, 3))
                assertEquals(state == "published", frame.sessionTrusted)
                assertEquals(state == "published", frame.fresh)
                assertEquals("", frame.prefs.getString("todo_top3_1_id", "fallback"))
                assertFalse(frame.prefs.getBoolean("focus_timer_running", false))
                assertEquals(0, frame.prefs.getInt("todo_count", -1))
            }
        }
    }

    @Test
    fun absentPublicationCanRenderAndValidModeChangesRejectCapturedFrames() {
        val absent = frame(DuoyiWidgetFrameCore.deviceDisplayValues(mapOf(
            "widget_display_mode" to 2, "widget_account_nonce" to "old-account"), 3))
        assertFalse(absent.sessionTrusted)
        assertEquals("standard", absent.core.effectiveMode)
        assertFalse(DuoyiWidgetDisplayMode.isDetailed(absent.prefs, 3))
        val initial = captured("published", mapOf("widget_display_mode" to "compact"))
        val changed = publication("published").toFlatValues().toMutableMap().apply {
            putAll(DuoyiWidgetFrameCore.deviceDisplayValues(mapOf("widget_display_mode" to "detailed"), 3))
        }
        assertEquals("data_changed", initial.core.rejectionReason(changed, initial.core.clock,
            initial.core.options, initial.core.systemLocaleTag))
    }

    private fun captured(state: String, preferences: Map<String, *>): DuoyiWidgetRenderFrame {
        val values = publication(state).toFlatValues().toMutableMap()
        values.putAll(DuoyiWidgetFrameCore.deviceDisplayValues(preferences, 3))
        return frame(values)
    }

    private fun frame(values: Map<String, *>) = DuoyiWidgetRenderFrame(DuoyiWidgetFrameCore(
        values, DuoyiWidgetFrameClock(Instant.parse("2024-06-15T12:00:00Z").toEpochMilli(),
            10_000L, ZoneId.of("UTC")), DuoyiWidgetFrameOptions(), 3, "en-US"))

    private fun publication(state: String): DuoyiWidgetPublicationDocument {
        val integers = setOf("todo_count", "habit_percent", "habit_active_count", "pomodoro_today",
            "focus_minutes_today", "todo_top3_count", "focus_timer_remaining_seconds",
            "focus_timer_total_seconds", "widget_theme_corner_radius_dp",
            "widget_theme_control_radius_dp", "widget_theme_border_width_dp",
            "widget_first_day_of_week")
        val longs = setOf("focus_timer_started_at_millis", "focus_timer_ends_at_millis")
        val booleans = setOf("focus_timer_count_up", "focus_timer_running", "widget_theme_dark")
        val values = DuoyiWidgetPublicationDocument.valueKeys.associateWith { key ->
            when (key) { in integers -> 0; in longs -> 0L; in booleans -> false; else -> "" }
        }.toMutableMap().apply { put("widget_first_day_of_week", 1) }
        return requireNotNull(DuoyiWidgetPublicationDocument.tryFromMap(mapOf(
            "schemaVersion" to 1, "ownerEpoch" to "current-account", "publicationRevision" to 1L,
            "localeRevision" to 1L, "state" to state, "locale" to "en",
            "snapshotDay" to if (state == "published") "2024-06-15" else "",
            "snapshotUtcOffsetMinutes" to 0, "capturedAtMillis" to 0L, "values" to values)))
    }
}
