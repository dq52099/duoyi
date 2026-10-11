package com.duoyi.duoyi

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Collections
import java.util.Locale
import kotlin.math.abs

/** Immutable inputs used by one widget build and its immediate commit check. */
data class DuoyiWidgetFrameClock(
    val wallMillis: Long,
    val elapsedMillis: Long,
    val zone: ZoneId,
) {
    private val local = Instant.ofEpochMilli(wallMillis).atZone(zone)
    val day: String = local.toLocalDate().toString()
    val offsetMinutes: Int = local.offset.totalSeconds / 60
}

data class DuoyiWidgetFrameOptions(
    val minWidth: Int = 0,
    val minHeight: Int = 0,
    val maxWidth: Int = 0,
    val maxHeight: Int = 0,
    val style: String? = null,
)

class DuoyiWidgetFrameCore(
    values: Map<String, *>,
    val clock: DuoyiWidgetFrameClock,
    val options: DuoyiWidgetFrameOptions,
    val widgetId: Int,
    val systemLocaleTag: String,
) {
    val rawValues: Map<String, *> = immutableValues(values)
    val publicationState: DuoyiWidgetPublicationDocument.State? =
        DuoyiWidgetPublicationDocument.State.entries.firstOrNull {
            it.wire == rawValues["widget_publication_state"]
        }
    val day: String? = rawValues["widget_snapshot_day"] as? String
    val offset: Int? = rawValues["widget_snapshot_utc_offset_minutes"] as? Int
    val nonce: String? = rawValues["widget_account_nonce"] as? String
    val sessionTrusted: Boolean = publicationState == DuoyiWidgetPublicationDocument.State.PUBLISHED &&
        validDay(day) && offset != null &&
        offset in -1080..1080 && !nonce.isNullOrBlank()
    val fresh: Boolean = sessionTrusted && day == clock.day && offset == clock.offsetMinutes
    val language: String = language(rawValues["widget_locale"] as? String)
        ?: language(systemLocaleTag) ?: "zh"
    val effectiveMode: String = effectiveMode()

    /** Compare raw values, never the display projection's placeholders. */
    fun rejectionReason(
        currentValues: Map<String, *>,
        currentClock: DuoyiWidgetFrameClock,
        currentOptions: DuoyiWidgetFrameOptions,
        currentSystemLocaleTag: String,
    ): String? {
        if (rawValues != currentValues) return "data_changed"
        if (options != currentOptions) return "options_changed"
        if (clock.zone != currentClock.zone) return "zone_changed"
        if (clock.day != currentClock.day) return "day_changed"
        if (clock.offsetMinutes != currentClock.offsetMinutes) return "offset_changed"
        if (systemLocaleTag != currentSystemLocaleTag) return "locale_changed"
        val wallDelta = currentClock.wallMillis - clock.wallMillis
        val elapsedDelta = currentClock.elapsedMillis - clock.elapsedMillis
        if (elapsedDelta < 0 || abs(wallDelta - elapsedDelta) > 1000L) return "clock_changed"
        val running = booleanCompat(rawValues["focus_timer_running"])
        val countUp = booleanCompat(rawValues["focus_timer_count_up"])
        val endsAt = longCompat(rawValues["focus_timer_ends_at_millis"])
        if (sessionTrusted && running && !countUp && endsAt > clock.wallMillis &&
            endsAt <= currentClock.wallMillis) return "timer_expired"
        val startedAt = longCompat(rawValues["focus_timer_started_at_millis"])
        if (sessionTrusted && running && countUp &&
            DuoyiWidgetCountUpCapCore.isCrossingCap(startedAt, clock.wallMillis, currentClock.wallMillis)) {
            return "timer_capped"
        }
        return null
    }

    private fun effectiveMode(): String {
        val instance = rawValues["widget_display_mode_$widgetId"] as? String
        val global = rawValues["widget_display_mode"] as? String
        val preferred = normalizeMode(instance) ?: normalizeMode(global) ?: "standard"
        if (options.minWidth <= 0 || options.minHeight <= 0) return preferred
        if (options.minWidth < 180 || options.minHeight < 100 || preferred == "compact") return "compact"
        if (preferred == "detailed" && options.minWidth >= 250 && options.minHeight >= 170) return "detailed"
        return "standard"
    }

    companion object {
        /** Only validated device-owned layout choices may accompany publication facts. */
        fun deviceDisplayValues(values: Map<String, *>, widgetId: Int): Map<String, String> {
            val display = LinkedHashMap<String, String>()
            val keys = if (widgetId > 0) {
                listOf("widget_display_mode", "widget_display_mode_$widgetId")
            } else listOf("widget_display_mode")
            for (key in keys) {
                normalizeMode(values[key] as? String)?.let { display[key] = it }
            }
            return Collections.unmodifiableMap(display)
        }

        fun immutableValues(values: Map<String, *>): Map<String, *> {
            val copy = LinkedHashMap<String, Any?>()
            values.forEach { (key, value) ->
                copy[key] = if (value is Set<*>) {
                    Collections.unmodifiableSet(LinkedHashSet(value))
                } else value
            }
            return Collections.unmodifiableMap(copy)
        }

        private fun validDay(day: String?): Boolean {
            if (day == null || !Regex("\\d{4}-\\d{2}-\\d{2}").matches(day)) return false
            return try { LocalDate.parse(day).toString() == day } catch (_: RuntimeException) { false }
        }

        private fun language(value: String?): String? = value?.trim()?.lowercase(Locale.ROOT)
            ?.replace('-', '_')?.substringBefore('_')?.takeIf { it == "en" || it == "zh" }

        private fun normalizeMode(value: String?): String? =
            value?.takeIf { it == "compact" || it == "standard" || it == "detailed" }

        private fun booleanCompat(value: Any?): Boolean = when (value) {
            is Boolean -> value
            is String -> value == "true"
            is Number -> value.toInt() != 0
            else -> false
        }

        private fun longCompat(value: Any?): Long = when (value) {
            is Long -> value
            is Int -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }
}

/** Each rejected frame gets one new capture/build; effects follow accepted UI only. */
object DuoyiWidgetFrameAttempts {
    fun <F, V> run(
        capture: () -> F,
        build: (F) -> V,
        rejectionReason: (F) -> String?,
        commit: (V) -> Unit,
        acceptedEffect: (F, V) -> Unit,
        rejected: (String) -> Unit,
    ): Boolean {
        repeat(2) {
            val frame = capture()
            val views = build(frame)
            val reason = rejectionReason(frame)
            if (reason != null) {
                rejected(reason)
            } else {
                commit(views)
                acceptedEffect(frame, views)
                return true
            }
        }
        return false
    }
}
