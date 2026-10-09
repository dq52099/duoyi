package com.duoyi.duoyi

import java.util.Collections

/** Strict complete publication facts; validity alone never authorizes a store write. */
class DuoyiWidgetPublicationDocument private constructor(
    val ownerEpoch: String,
    val publicationRevision: Long,
    val presentationRevision: Long,
    val state: State,
    val locale: String,
    val snapshotDay: String,
    val snapshotUtcOffsetMinutes: Int,
    val capturedAtMillis: Long,
    values: Map<String, Any>,
) {
    enum class State(val wire: String) {
        PUBLISHED("published"), CLEARED("cleared"), BLOCKED("blocked")
    }

    val values: Map<String, Any> = Collections.unmodifiableMap(LinkedHashMap(values))

    fun toMap(): Map<String, Any> = linkedMapOf(
        "schemaVersion" to SCHEMA_VERSION,
        "ownerEpoch" to ownerEpoch,
        "publicationRevision" to publicationRevision,
        "localeRevision" to presentationRevision,
        "state" to state.wire,
        "locale" to locale,
        "snapshotDay" to snapshotDay,
        "snapshotUtcOffsetMinutes" to snapshotUtcOffsetMinutes,
        "capturedAtMillis" to capturedAtMillis,
        "values" to LinkedHashMap(values),
    )

    /** Counters/offset stay Int; timer millis stay Long even when their value is zero. */
    fun toFlatValues(): Map<String, Any> = LinkedHashMap(values).apply {
        put("widget_account_nonce", ownerEpoch)
        put("widget_locale", locale)
        put("widget_snapshot_day", snapshotDay)
        put("widget_snapshot_utc_offset_minutes", snapshotUtcOffsetMinutes)
    }

    companion object {
        const val SCHEMA_VERSION = 1
        const val MAX_EXACT_INTEGER = 9007199254740991L
        private enum class ValueType { STRING, INT32, INT64, BOOLEAN }
        private val documentKeys = setOf(
            "schemaVersion", "ownerEpoch", "publicationRevision", "localeRevision", "state",
            "locale", "snapshotDay", "snapshotUtcOffsetMinutes", "capturedAtMillis", "values",
        )
        // Keep this complete manifest aligned with the versioned Dart DTO, never residual prefs.
        private val valueTypes = linkedMapOf(
            "todo_count" to ValueType.INT32,
            "habit_percent" to ValueType.INT32,
            "habit_active_count" to ValueType.INT32,
            "pomodoro_today" to ValueType.INT32,
            "focus_minutes_today" to ValueType.INT32,
            "brand_app_title" to ValueType.STRING,
            "nav_todo" to ValueType.STRING,
            "nav_habit" to ValueType.STRING,
            "nav_calendar" to ValueType.STRING,
            "nav_focus" to ValueType.STRING,
            "todo_top3_count" to ValueType.INT32,
            "todo_top3_1" to ValueType.STRING,
            "todo_top3_1_id" to ValueType.STRING,
            "todo_top3_2" to ValueType.STRING,
            "todo_top3_2_id" to ValueType.STRING,
            "todo_top3_3" to ValueType.STRING,
            "todo_top3_3_id" to ValueType.STRING,
            "goal_highlight_1" to ValueType.STRING,
            "goal_highlight_1_id" to ValueType.STRING,
            "goal_highlight_2" to ValueType.STRING,
            "goal_highlight_2_id" to ValueType.STRING,
            "goal_highlight_3" to ValueType.STRING,
            "goal_highlight_3_id" to ValueType.STRING,
            "anniversary_highlight_1" to ValueType.STRING,
            "anniversary_highlight_1_id" to ValueType.STRING,
            "anniversary_highlight_2" to ValueType.STRING,
            "anniversary_highlight_2_id" to ValueType.STRING,
            "course_highlight_1" to ValueType.STRING,
            "course_highlight_1_id" to ValueType.STRING,
            "course_highlight_2" to ValueType.STRING,
            "course_highlight_2_id" to ValueType.STRING,
            "course_highlight_3" to ValueType.STRING,
            "course_highlight_3_id" to ValueType.STRING,
            "note_highlight_1" to ValueType.STRING,
            "note_highlight_1_id" to ValueType.STRING,
            "note_highlight_2" to ValueType.STRING,
            "note_highlight_2_id" to ValueType.STRING,
            "note_highlight_3" to ValueType.STRING,
            "note_highlight_3_id" to ValueType.STRING,
            "memorial_highlight_1" to ValueType.STRING,
            "memorial_highlight_1_id" to ValueType.STRING,
            "memorial_highlight_2" to ValueType.STRING,
            "memorial_highlight_2_id" to ValueType.STRING,
            "memorial_highlight_3" to ValueType.STRING,
            "memorial_highlight_3_id" to ValueType.STRING,
            "diary_highlight_1" to ValueType.STRING,
            "diary_highlight_1_id" to ValueType.STRING,
            "diary_highlight_2" to ValueType.STRING,
            "diary_highlight_2_id" to ValueType.STRING,
            "diary_highlight_3" to ValueType.STRING,
            "diary_highlight_3_id" to ValueType.STRING,
            "today_event_summary" to ValueType.STRING,
            "schedule_highlight_1" to ValueType.STRING,
            "schedule_highlight_1_id" to ValueType.STRING,
            "schedule_highlight_2" to ValueType.STRING,
            "schedule_highlight_2_id" to ValueType.STRING,
            "schedule_highlight_3" to ValueType.STRING,
            "schedule_highlight_3_id" to ValueType.STRING,
            "calendar_month_summary" to ValueType.STRING,
            "focus_summary" to ValueType.STRING,
            "habit_summary" to ValueType.STRING,
            "streak_summary" to ValueType.STRING,
            "next_focus_label" to ValueType.STRING,
            "focus_timer_count_up" to ValueType.BOOLEAN,
            "focus_timer_started_at_millis" to ValueType.INT64,
            "focus_timer_running" to ValueType.BOOLEAN,
            "focus_timer_remaining_seconds" to ValueType.INT32,
            "focus_timer_total_seconds" to ValueType.INT32,
            "focus_timer_ends_at_millis" to ValueType.INT64,
            "focus_timer_label" to ValueType.STRING,
            "habit_quick_check_id" to ValueType.STRING,
            "habit_quick_check_label" to ValueType.STRING,
            "widget_theme_brand_id" to ValueType.STRING,
            "widget_theme_card_skin_id" to ValueType.STRING,
            "widget_theme_dark" to ValueType.BOOLEAN,
            "widget_theme_primary" to ValueType.STRING,
            "widget_theme_background" to ValueType.STRING,
            "widget_theme_surface" to ValueType.STRING,
            "widget_theme_nav_background" to ValueType.STRING,
            "widget_theme_border" to ValueType.STRING,
            "widget_theme_text" to ValueType.STRING,
            "widget_theme_muted_text" to ValueType.STRING,
            "widget_theme_on_primary" to ValueType.STRING,
            "widget_theme_accent_start" to ValueType.STRING,
            "widget_theme_accent_end" to ValueType.STRING,
            "widget_theme_background_asset_key" to ValueType.STRING,
            "widget_theme_corner_radius_dp" to ValueType.INT32,
            "widget_theme_control_radius_dp" to ValueType.INT32,
            "widget_theme_border_width_dp" to ValueType.INT32,
        )
        val valueKeys: Set<String> = Collections.unmodifiableSet(LinkedHashSet(valueTypes.keys))

        private fun businessKey(key: String): Boolean =
            !key.startsWith("widget_theme_") && key != "brand_app_title" && !key.startsWith("nav_")

        /** Input must be the same complete presentation snapshot, never a patch. */
        fun clearedValuesFrom(completeValues: Map<String, *>): Map<String, Any>? {
            if (completeValues.keys != valueKeys) return null
            val clean = LinkedHashMap<String, Any>()
            for ((key, type) in valueTypes) {
                val value = completeValues[key]
                val parsed = parseValue(key, type, value) ?: return null
                clean[key] = if (!businessKey(key)) parsed else when (type) {
                    ValueType.STRING -> ""
                    ValueType.BOOLEAN -> false
                    ValueType.INT32 -> 0
                    ValueType.INT64 -> 0L
                }
            }
            return Collections.unmodifiableMap(clean)
        }

        fun tryFromMap(raw: Any?): DuoyiWidgetPublicationDocument? {
            if (raw !is Map<*, *> || raw.keys != documentKeys) return null
            if (exactInteger(raw["schemaVersion"]) != SCHEMA_VERSION.toLong()) return null
            val epoch = raw["ownerEpoch"] as? String ?: return null
            if (wireBlank(epoch)) return null
            val revision = nonnegativeExact(raw["publicationRevision"]) ?: return null
            val presentation = nonnegativeExact(raw["localeRevision"]) ?: return null
            val captured = nonnegativeExact(raw["capturedAtMillis"]) ?: return null
            val state = State.entries.firstOrNull { it.wire == raw["state"] } ?: return null
            val locale = raw["locale"] as? String ?: return null
            if (locale != "zh" && locale != "en") return null
            val day = raw["snapshotDay"] as? String ?: return null
            val offset = exactInteger(raw["snapshotUtcOffsetMinutes"]) ?: return null
            if (offset !in -1080L..1080L) return null
            if (state == State.PUBLISHED) {
                if (revision == 0L || !validDay(day)) return null
            } else if (day.isNotEmpty() || offset != 0L) return null
            val rawValues = raw["values"] as? Map<*, *> ?: return null
            if (rawValues.keys != valueKeys) return null
            val values = LinkedHashMap<String, Any>()
            for ((key, type) in valueTypes) {
                val parsed = parseValue(key, type, rawValues[key]) ?: return null
                if (state != State.PUBLISHED && businessKey(key)) {
                    val empty = when (type) {
                        ValueType.STRING -> parsed == ""
                        ValueType.BOOLEAN -> parsed == false
                        ValueType.INT32 -> parsed == 0
                        ValueType.INT64 -> parsed == 0L
                    }
                    if (!empty) return null
                }
                values[key] = parsed
            }
            if (values["todo_count"] != values["todo_top3_count"]) return null
            return DuoyiWidgetPublicationDocument(
                epoch, revision, presentation, state, locale, day, offset.toInt(), captured, values,
            )
        }

        private fun parseValue(key: String, type: ValueType, value: Any?): Any? = when (type) {
            ValueType.STRING -> value as? String
            ValueType.BOOLEAN -> value as? Boolean
            ValueType.INT64 -> nonnegativeExact(value)
            ValueType.INT32 -> {
                val integer = exactInteger(value)
                val minimum = if (key == "habit_active_count") -1L else 0L
                val maximum = if (key == "habit_percent") 100L else Int.MAX_VALUE.toLong()
                integer?.takeIf { it in minimum..maximum }?.toInt()
            }
        }

        /** JSON/MethodChannel integer representations only; no strings, floats or booleans. */
        fun exactInteger(value: Any?): Long? = when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> null
        }

        fun nonnegativeExact(value: Any?): Long? =
            exactInteger(value)?.takeIf { it in 0L..MAX_EXACT_INTEGER }

        /** Matches the current Dart SDK trim predicate without changing literal code units. */
        fun wireBlank(value: String): Boolean = value.all { character ->
            val code = character.code
            code in 0x0009..0x000D || code == 0x0020 || code == 0x0085 ||
                code == 0x00A0 || code == 0x1680 || code in 0x2000..0x200A ||
                code == 0x2028 || code == 0x2029 || code == 0x202F ||
                code == 0x205F || code == 0x3000 || code == 0xFEFF
        }

        private fun validDay(day: String): Boolean {
            if (day.length != 10 || !Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(day)) return false
            val year = day.substring(0, 4).toInt()
            val month = day.substring(5, 7).toInt()
            val date = day.substring(8, 10).toInt()
            if (year !in 1..9999 || month !in 1..12) return false
            val leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            val maximum = when (month) {
                2 -> if (leap) 29 else 28
                4, 6, 9, 11 -> 30
                else -> 31
            }
            return date in 1..maximum
        }
    }
}
