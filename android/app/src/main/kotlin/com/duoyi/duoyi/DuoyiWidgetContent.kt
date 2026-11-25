package com.duoyi.duoyi

import java.io.ByteArrayOutputStream
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class DuoyiAnniversaryRawSlot(
    val sourceKey: String,
    val text: String?,
    val target: String?,
)

data class DuoyiAnniversaryItem(
    val sourceKey: String,
    val text: String,
    val target: String,
    val identity: String?,
)

data class DuoyiMonthCell(
    val dayNumber: Int,
    val isToday: Boolean,
    val text: String,
    val dateKey: String? = null,
) {
    /** A civil navigation target; the producer must still add frame bindings. */
    val target: String?
        get() = dateKey?.let { "duoyi://calendar?date=$it" }
}

data class DuoyiMonthGridModel(
    val year: Int,
    val month: Int,
    val todayDay: Int,
    val firstWeekdayOffset: Int,
    val daysInMonth: Int,
    val cells: List<DuoyiMonthCell>,
    val weekdayHeader: String,
)

data class DuoyiCalendarEventSummaryResult(
    val summary: String?,
    val target: String,
    val isReal: Boolean,
)

/**
 * Pure Kotlin data models and helpers for widget display logic.
 * Free of Android framework dependencies (Context, SharedPreferences, RemoteViews).
 */
object DuoyiWidgetContent {

    fun isKnownAnniversaryEmptyPlaceholder(text: String): Boolean {
        val trimmed = text.trim()
        val clean = if (trimmed.startsWith("· ")) trimmed.removePrefix("· ").trim() else trimmed
        return clean == "暂无近期纪念日" ||
            clean == "No upcoming anniversaries" ||
            clean == "暂无纪念日" ||
            clean == "纪念日 · 暂无近期纪念日" ||
            clean == "Anniversaries · No upcoming anniversaries"
    }

    fun isBareBulletOrEmpty(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return true
        val stripped = trimmed.replace("·", "").replace("•", "").trim()
        return stripped.isEmpty()
    }

    private fun hexValue(c: Char): Int = when (c) {
        in '0'..'9' -> c - '0'
        in 'a'..'f' -> c - 'a' + 10
        in 'A'..'F' -> c - 'A' + 10
        else -> -1
    }

    fun hasIllegalUriCharacters(s: String): Boolean {
        for (i in 0 until s.length) {
            val c = s[i]
            if (c <= ' ' || c.code == 0x7F || c == '\\' ||
                c == '"' || c == '<' || c == '>' ||
                c == '{' || c == '}' || c == '|' ||
                c == '^' || c == '`' ||
                c == '[' || c == ']' ||
                c == '?' || c == '#') {
                return true
            }
        }
        return false
    }

    fun strictPercentDecode(s: String): String? {
        val bytes = ByteArrayOutputStream()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%') {
                if (i + 2 >= s.length) return null
                val h1 = hexValue(s[i + 1])
                val h2 = hexValue(s[i + 2])
                if (h1 == -1 || h2 == -1) return null
                bytes.write((h1 shl 4) or h2)
                i += 3
            } else {
                val cp = s.codePointAt(i)
                val charCount = Character.charCount(cp)
                val cpChars = Character.toChars(cp)
                val cpString = String(cpChars)
                bytes.write(cpString.toByteArray(Charsets.UTF_8))
                i += charCount
            }
        }
        val byteArray = bytes.toByteArray()
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            val byteBuffer = ByteBuffer.wrap(byteArray)
            decoder.decode(byteBuffer).toString()
        } catch (_: Exception) {
            null
        }
    }

    fun encodePathSegment(raw: String): String {
        val sb = StringBuilder()
        for (b in raw.toByteArray(Charsets.UTF_8)) {
            val unsigned = b.toInt() and 0xFF
            if ((unsigned in 'A'.code..'Z'.code) ||
                (unsigned in 'a'.code..'z'.code) ||
                (unsigned in '0'.code..'9'.code) ||
                unsigned == '-'.code || unsigned == '_'.code ||
                unsigned == '.'.code || unsigned == '~'.code) {
                sb.append(unsigned.toChar())
            } else {
                sb.append(String.format("%%%02X", unsigned))
            }
        }
        return sb.toString()
    }

    fun parseAnniversaryTarget(rawTarget: String?): Pair<String, String?> {
        val raw = rawTarget?.trim().orEmpty()
        if (raw.isEmpty()) {
            return "duoyi://anniversary" to null
        }
        if (raw.startsWith("duoyi://", ignoreCase = true)) {
            if (hasIllegalUriCharacters(raw) || raw.endsWith('/')) {
                return "duoyi://anniversary" to null
            }
            val uri = try {
                URI(raw)
            } catch (_: Exception) {
                return "duoyi://anniversary" to null
            }
            if (!uri.scheme.equals("duoyi", ignoreCase = true)) {
                return "duoyi://anniversary" to null
            }
            if (uri.userInfo != null || uri.port != -1 || uri.query != null || uri.fragment != null) {
                return "duoyi://anniversary" to null
            }
            val authority = uri.authority.orEmpty()
            if (authority.isEmpty() || authority.contains('@') || authority.contains(':')) {
                return "duoyi://anniversary" to null
            }
            val host = (uri.host ?: authority).lowercase(Locale.ROOT)
            if (host != "anniversary") {
                return "duoyi://anniversary" to null
            }
            val rawPath = uri.rawPath.orEmpty()
            if (!rawPath.startsWith('/') || rawPath.length <= 1) {
                return "duoyi://anniversary" to null
            }
            val segment = rawPath.substring(1)
            if (segment.contains('/')) {
                return "duoyi://anniversary" to null
            }
            val decoded = strictPercentDecode(segment) ?: return "duoyi://anniversary" to null
            if (decoded.trim().isEmpty()) {
                return "duoyi://anniversary" to null
            }
            return "duoyi://anniversary/$segment" to decoded
        } else {
            val isForeignUri = raw.contains("://") || raw.startsWith("//") ||
                raw.startsWith("mailto:", ignoreCase = true) ||
                raw.startsWith("tel:", ignoreCase = true) ||
                raw.startsWith("sms:", ignoreCase = true) ||
                raw.startsWith("data:", ignoreCase = true) ||
                raw.startsWith("javascript:", ignoreCase = true) ||
                raw.startsWith("urn:", ignoreCase = true) ||
                raw.startsWith("file:", ignoreCase = true)

            if (isForeignUri) {
                return "duoyi://anniversary" to null
            }
            // Legacy plain ID: preserve full string, encode as a single path segment
            val encoded = encodePathSegment(raw)
            return "duoyi://anniversary/$encoded" to raw
        }
    }

    fun resolveAnniversaryItems(
        slots: List<DuoyiAnniversaryRawSlot>,
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
    ): List<DuoyiAnniversaryItem> {
        if (publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED) {
            val neutralText = DuoyiWidgetCopy.unpublishedMessage(isZh)
            return listOf(
                DuoyiAnniversaryItem(
                    sourceKey = "anniversary_highlight_1",
                    text = neutralText,
                    target = "duoyi://anniversary",
                    identity = null,
                )
            )
        }

        if (!isFresh) {
            val staleText = if (isZh) "日期数据待刷新" else "Dates pending refresh"
            return listOf(
                DuoyiAnniversaryItem(
                    sourceKey = "anniversary_highlight_1",
                    text = staleText,
                    target = "duoyi://anniversary",
                    identity = null,
                )
            )
        }

        val seenIdentities = mutableSetOf<String>()
        val result = mutableListOf<DuoyiAnniversaryItem>()

        for (slot in slots) {
            val rawText = slot.text
            if (rawText.isNullOrBlank()) continue

            val rawTarget = slot.target?.trim().orEmpty()
            if (rawTarget.isEmpty() && (isBareBulletOrEmpty(rawText) || isKnownAnniversaryEmptyPlaceholder(rawText))) {
                continue
            }

            val (targetUrl, identity) = parseAnniversaryTarget(slot.target)

            if (identity != null) {
                if (seenIdentities.contains(identity)) {
                    continue
                }
                seenIdentities.add(identity)
            }

            result.add(
                DuoyiAnniversaryItem(
                    sourceKey = slot.sourceKey,
                    text = rawText,
                    target = targetUrl,
                    identity = identity,
                )
            )
        }

        if (result.isEmpty()) {
            val emptyText = if (isZh) "· 暂无近期纪念日" else "· No upcoming anniversaries"
            return listOf(
                DuoyiAnniversaryItem(
                    sourceKey = "anniversary_highlight_1",
                    text = emptyText,
                    target = "duoyi://anniversary",
                    identity = null,
                )
            )
        }

        return result
    }

    fun resolveCalendarEventTarget(rawTarget: String?): String {
        val raw = rawTarget?.trim().orEmpty()
        if (raw.isEmpty()) return "duoyi://calendar"
        if (!raw.startsWith("duoyi://", ignoreCase = true)) return "duoyi://calendar"
        if (hasIllegalUriCharacters(raw) || raw.endsWith('/')) return "duoyi://calendar"

        val uri = try {
            URI(raw)
        } catch (_: Exception) {
            return "duoyi://calendar"
        }
        if (!uri.scheme.equals("duoyi", ignoreCase = true)) {
            return "duoyi://calendar"
        }
        if (uri.userInfo != null || uri.port != -1 || uri.query != null || uri.fragment != null) {
            return "duoyi://calendar"
        }
        val authority = uri.authority.orEmpty()
        if (authority.isEmpty() || authority.contains('@') || authority.contains(':')) {
            return "duoyi://calendar"
        }
        val host = (uri.host ?: authority).lowercase(Locale.ROOT)

        if (host == "calendar" || host == "focus") {
            val rawPath = uri.rawPath.orEmpty()
            return if (rawPath.isEmpty()) raw else "duoyi://calendar"
        }

        val supportedMutationHosts = setOf(
            "todo", "habit", "anniversary", "course", "diary", "goal", "countdown", "time-entry", "event", "pomodoro"
        )
        if (host in supportedMutationHosts) {
            val rawPath = uri.rawPath.orEmpty()
            if (!rawPath.startsWith('/') || rawPath.length <= 1) {
                return "duoyi://calendar"
            }
            val segment = rawPath.substring(1)
            if (segment.contains('/')) {
                return "duoyi://calendar"
            }
            val decoded = strictPercentDecode(segment) ?: return "duoyi://calendar"
            if (decoded.trim().isEmpty()) {
                return "duoyi://calendar"
            }
            return raw
        }

        return "duoyi://calendar"
    }

    fun resolveCalendarSummaryAndTarget(
        rawSummary: String?,
        rawSchedule1Id: String?,
        isFresh: Boolean,
        isZh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
    ): DuoyiCalendarEventSummaryResult {
        if (publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED) {
            val neutralText = DuoyiWidgetCopy.unpublishedMessage(isZh)
            return DuoyiCalendarEventSummaryResult(
                summary = neutralText,
                target = "duoyi://calendar",
                isReal = false,
            )
        }

        if (!isFresh) {
            val staleText = if (isZh) "今日数据待刷新" else "Today’s data pending refresh"
            return DuoyiCalendarEventSummaryResult(
                summary = staleText,
                target = "duoyi://calendar",
                isReal = false,
            )
        }

        if (rawSummary.isNullOrBlank()) {
            return DuoyiCalendarEventSummaryResult(
                summary = null,
                target = "duoyi://calendar",
                isReal = false,
            )
        }

        val trimmed = rawSummary.trim()
        val clean = if (trimmed.startsWith("· ")) trimmed.removePrefix("· ").trim() else trimmed
        val isNoEventsPlaceholder = clean == "今日没有日程" ||
            clean == "No schedule today" ||
            clean == "No events today" ||
            clean == "今天暂无日程" ||
            clean == "今日日程" ||
            clean == "Today's schedule" ||
            clean == "Today’s schedule"

        if (isNoEventsPlaceholder) {
            val emptyText = if (isZh) "今日没有日程" else "No events today"
            return DuoyiCalendarEventSummaryResult(
                summary = emptyText,
                target = "duoyi://calendar",
                isReal = false,
            )
        }

        val target = resolveCalendarEventTarget(rawSchedule1Id)
        return DuoyiCalendarEventSummaryResult(
            summary = rawSummary,
            target = target,
            isReal = true,
        )
    }

    fun buildMonthGrid(
        anchorDate: Date,
        timeZone: TimeZone,
        isZh: Boolean,
        firstDayOfWeek: Int = 1,
    ): DuoyiMonthGridModel {
        val anchorMillis = anchorDate.time
        // Resolve this instance's offset at the instant, including custom IDs,
        // adjusted raw offsets and DST, without rounding away milliseconds.
        val day = Instant.ofEpochMilli(anchorMillis)
            .plusMillis(timeZone.getOffset(anchorMillis).toLong())
            .atOffset(ZoneOffset.UTC).toLocalDate()
        return buildMonthGrid(day.year, day.monthValue, day.dayOfMonth, isZh, timeZone, firstDayOfWeek)
    }

    // Retain the zone argument for existing callers; a resolved civil month
    // has the same Gregorian weekdays and date keys in every time zone.
    @Suppress("UNUSED_PARAMETER")
    fun buildMonthGrid(
        year: Int,
        month: Int,
        todayDay: Int,
        isZh: Boolean,
        timeZone: TimeZone = TimeZone.getDefault(),
        firstDayOfWeek: Int = 1,
    ): DuoyiMonthGridModel {
        require(year in 1..9999) { "Calendar year must be within 1..9999" }
        require(month in 1..12) { "Calendar month must be within 1..12" }
        val first = LocalDate.of(year, month, 1)
        val weekStart = firstDayOfWeek.takeIf { it in 1..7 } ?: 1
        val firstWeekdayOffset = (first.dayOfWeek.value - weekStart + 7) % 7
        val daysInMonth = first.lengthOfMonth()

        val cells = ArrayList<DuoyiMonthCell>(42)
        for (i in 0 until 42) {
            if (i < firstWeekdayOffset || i >= firstWeekdayOffset + daysInMonth) {
                cells.add(DuoyiMonthCell(dayNumber = 0, isToday = false, text = "  "))
            } else {
                val day = i - firstWeekdayOffset + 1
                val isToday = (day == todayDay)
                val text = day.toString().padStart(2, ' ')
                cells.add(DuoyiMonthCell(
                    dayNumber = day,
                    isToday = isToday,
                    text = text,
                    dateKey = first.withDayOfMonth(day).toString(),
                ))
            }
        }

        val weekdayHeader = calendarWeekdayLabels(isZh, weekStart).joinToString(" ")

        return DuoyiMonthGridModel(
            year = year,
            month = month,
            todayDay = todayDay,
            firstWeekdayOffset = firstWeekdayOffset,
            daysInMonth = daysInMonth,
            cells = cells,
            weekdayHeader = weekdayHeader,
        )
    }

    fun calendarWeekdayLabels(isZh: Boolean, firstDayOfWeek: Int = 1, full: Boolean = false): List<String> {
        val first = firstDayOfWeek.takeIf { it in 1..7 } ?: 1
        val labels = if (isZh) {
            if (full) listOf("星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日")
            else listOf("一", "二", "三", "四", "五", "六", "日")
        } else {
            if (full) listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
            else listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")
        }
        return List(7) { labels[(first - 1 + it) % 7] }
    }

    private val goalPercentRegex = Regex("(\\d{1,3}(?:\\.\\d+)?)\\s*%")

    fun extractGoalProgressPercent(raw: String?): Int? {
        if (raw.isNullOrBlank()) return null
        val match = goalPercentRegex.find(raw) ?: return null
        val value = match.groupValues[1].toDoubleOrNull() ?: return null
        return Math.round(value).toInt().coerceIn(0, 100)
    }

    fun resolveGoalProgressPercent(
        highlights: List<String?>,
        isFresh: Boolean,
        publicationState: DuoyiWidgetPublicationDocument.State? = DuoyiWidgetPublicationDocument.State.PUBLISHED,
    ): Int? {
        if (publicationState != DuoyiWidgetPublicationDocument.State.PUBLISHED || !isFresh) return null
        val percents = highlights.mapNotNull(::extractGoalProgressPercent)
        if (percents.isEmpty()) return null
        return percents.first()
    }

    fun calendarTodayDateKey(
        nowMillis: Long,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): String {
        val date = Instant.ofEpochMilli(nowMillis)
            .plusMillis(timeZone.getOffset(nowMillis).toLong())
            .atOffset(ZoneOffset.UTC)
            .toLocalDate()
        return date.toString()
    }

    fun calendarTodayTarget(
        nowMillis: Long,
        timeZone: TimeZone = TimeZone.getDefault(),
    ): String = "duoyi://calendar?date=${calendarTodayDateKey(nowMillis, timeZone)}"

    fun appendPendingBgAction(existing: String?, actionUri: String, maxEntries: Int = 24): String {
        val trimmed = actionUri.trim()
        if (trimmed.isEmpty()) return existing.orEmpty()
        val items = existing.orEmpty()
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toMutableList()
        if (!items.contains(trimmed)) {
            items.add(trimmed)
        }
        val capped = if (items.size > maxEntries) items.takeLast(maxEntries) else items
        return capped.joinToString("\n")
    }

    fun resolveFocusActionPath(
        isFresh: Boolean,
        storedRunning: Boolean,
        timerRunning: Boolean,
    ): String = when {
        isFresh && !storedRunning -> "duoyi://action/start_pomodoro"
        isFresh && timerRunning -> "duoyi://action/toggle_pomodoro"
        else -> "duoyi://tab/focus"
    }
}
