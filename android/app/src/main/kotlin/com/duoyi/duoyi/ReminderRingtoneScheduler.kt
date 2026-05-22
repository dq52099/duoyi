package com.duoyi.duoyi

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

object ReminderRingtoneScheduler {
    private const val actionRing = "com.duoyi.duoyi.REMINDER_RING"
    private const val prefsName = "duoyi_native_reminder_ringtone"
    private const val idsKey = "ids"
    private const val entryPrefix = "entry_"

    fun showNow(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: String?,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ) {
        val intent = ReminderRingtoneService.intent(context, id, title, body, payload, vibrate, snoozeMinutes, repeatCount)
        startRingtoneService(context, intent)
    }

    fun scheduleOnce(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long,
        payload: String?,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ) {
        val intent = baseIntent(context, id, title, body, payload, vibrate, snoozeMinutes, repeatCount)
        schedule(context, id, triggerAtMillis, intent)
        rememberSchedule(context, id, triggerAtMillis, intent)
    }

    fun scheduleDaily(
        context: Context,
        id: Int,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        weekdays: IntArray,
        timezoneId: String?,
        payload: String?,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ) {
        val normalized = weekdays.filter { it in 1..7 }.distinct().toIntArray()
        val zoneId = normalizeTimeZone(timezoneId)
        val triggerAtMillis = nextWallClockMillis(hour, minute, normalized, zoneId)
        val intent = baseIntent(context, id, title, body, payload, vibrate, snoozeMinutes, repeatCount)
            .putExtra("repeat", true)
            .putExtra("hour", hour)
            .putExtra("minute", minute)
            .putExtra("weekdays", normalized)
            .putExtra("timezoneId", zoneId)
        schedule(context, id, triggerAtMillis, intent)
        rememberSchedule(context, id, triggerAtMillis, intent)
    }

    fun rescheduleFromReceiver(context: Context, source: Intent) {
        val id = source.getIntExtra("id", 0)
        if (id == 0) return
        scheduleDaily(
            context = context,
            id = id,
            title = source.getStringExtra("title") ?: "多仪提醒",
            body = source.getStringExtra("body") ?: "提醒时间到了",
            hour = source.getIntExtra("hour", 9),
            minute = source.getIntExtra("minute", 0),
            weekdays = source.getIntArrayExtra("weekdays") ?: intArrayOf(),
            timezoneId = source.getStringExtra("timezoneId"),
            payload = source.getStringExtra("payload"),
            vibrate = source.getBooleanExtra("vibrate", true),
            snoozeMinutes = source.getIntExtra("snoozeMinutes", 0),
            repeatCount = source.getIntExtra("repeatCount", 0),
        )
    }

    fun cancel(context: Context, id: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(pendingIntent(context, id, baseIntent(context, id, "", "", null)))
        forgetId(context, id)
    }

    fun cancelAll(context: Context) {
        val ids = prefs(context).getStringSet(idsKey, emptySet()).orEmpty()
        ids.mapNotNull { it.toIntOrNull() }.forEach { cancel(context, it) }
        prefs(context).edit().remove(idsKey).apply()
    }

    fun restoreAll(context: Context) {
        val ids = prefs(context).getStringSet(idsKey, emptySet()).orEmpty()
        ids.mapNotNull { it.toIntOrNull() }.forEach { id ->
            restoreOne(context, id)
        }
    }

    private fun schedule(context: Context, id: Int, triggerAtMillis: Long, intent: Intent) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val operation = pendingIntent(context, id, intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
            } else {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
            }
        } else {
            manager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
        }
    }

    private fun pendingIntent(context: Context, id: Int, intent: Intent): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, id, intent, flags)
    }

    private fun startRingtoneService(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun baseIntent(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: String?,
        vibrate: Boolean = true,
        snoozeMinutes: Int = 0,
        repeatCount: Int = 0,
    ): Intent {
        return Intent(context, ReminderRingtoneReceiver::class.java)
            .setAction(actionRing)
            .putExtra("id", id)
            .putExtra("title", title)
            .putExtra("body", body)
            .putExtra("payload", payload)
            .putExtra("vibrate", vibrate)
            .putExtra("snoozeMinutes", snoozeMinutes.coerceIn(0, 120))
            .putExtra("repeatCount", repeatCount.coerceIn(0, 10))
            .putExtra("repeatRemaining", repeatCount.coerceIn(0, 10))
    }

    private fun nextWallClockMillis(
        hour: Int,
        minute: Int,
        weekdays: IntArray,
        timezoneId: String,
    ): Long {
        val zone = TimeZone.getTimeZone(timezoneId)
        val now = Calendar.getInstance(zone)
        var best: Long? = null
        for (offset in 0..7) {
            val candidate = Calendar.getInstance(zone).apply {
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
                set(Calendar.MINUTE, minute.coerceIn(0, 59))
                add(Calendar.DAY_OF_YEAR, offset)
            }
            val dartWeekday = when (candidate.get(Calendar.DAY_OF_WEEK)) {
                Calendar.MONDAY -> 1
                Calendar.TUESDAY -> 2
                Calendar.WEDNESDAY -> 3
                Calendar.THURSDAY -> 4
                Calendar.FRIDAY -> 5
                Calendar.SATURDAY -> 6
                else -> 7
            }
            val weekdayAllowed = weekdays.isEmpty() || weekdays.contains(dartWeekday)
            if (weekdayAllowed && candidate.after(now)) {
                val millis = candidate.timeInMillis
                if (best == null || millis < best!!) best = millis
            }
        }
        return best ?: now.timeInMillis + 60_000L
    }

    private fun normalizeTimeZone(timezoneId: String?): String {
        val systemDefault = TimeZone.getDefault().id
        val normalized = timezoneId?.trim().orEmpty()
        if (normalized.isBlank() || normalized == "UTC" || normalized == "Etc/UTC") {
            return systemDefault
        }
        val resolved = TimeZone.getTimeZone(normalized)
        if (resolved.id == "GMT" && normalized != "GMT" && normalized != "Etc/GMT") {
            return systemDefault
        }
        return normalized
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun rememberSchedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        intent: Intent,
    ) {
        val store = prefs(context)
        val next = store.getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        next.add(id.toString())
        store.edit()
            .putStringSet(idsKey, next)
            .putString("${entryPrefix}$id", encodeEntry(triggerAtMillis, intent))
            .apply()
    }

    private fun forgetId(context: Context, id: Int) {
        val store = prefs(context)
        val next = store.getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        next.remove(id.toString())
        store.edit()
            .putStringSet(idsKey, next)
            .remove("${entryPrefix}$id")
            .apply()
    }

    private fun restoreOne(context: Context, id: Int) {
        val raw = prefs(context).getString("${entryPrefix}$id", null) ?: return
        val json = runCatching { JSONObject(raw) }.getOrNull() ?: return
        val title = json.optString("title", "多仪提醒")
        val body = json.optString("body", "提醒时间到了")
        val payload = json.optString("payload").ifBlank { null }
        val vibrate = json.optBoolean("vibrate", true)
        val snoozeMinutes = json.optInt("snoozeMinutes", 0)
        val repeatCount = json.optInt("repeatCount", 0)
        val repeat = json.optBoolean("repeat", false)
        if (repeat) {
            val weekdays = json.optJSONArray("weekdays")?.let { array ->
                IntArray(array.length()) { index -> array.optInt(index) }
            } ?: intArrayOf()
            scheduleDaily(
                context = context,
                id = id,
                title = title,
                body = body,
                hour = json.optInt("hour", 9),
                minute = json.optInt("minute", 0),
                weekdays = weekdays,
                timezoneId = json.optString("timezoneId").ifBlank { null },
                payload = payload,
                vibrate = vibrate,
                snoozeMinutes = snoozeMinutes,
                repeatCount = repeatCount,
            )
            return
        }

        val triggerAtMillis = json.optLong("triggerAtMillis", 0L)
        if (triggerAtMillis > System.currentTimeMillis()) {
            scheduleOnce(context, id, title, body, triggerAtMillis, payload, vibrate, snoozeMinutes, repeatCount)
        } else {
            showNow(context, id, title, body, payload, vibrate, snoozeMinutes, repeatCount)
            forgetId(context, id)
        }
    }

    private fun encodeEntry(triggerAtMillis: Long, intent: Intent): String {
        val weekdays = intent.getIntArrayExtra("weekdays") ?: intArrayOf()
        return JSONObject()
            .put("title", intent.getStringExtra("title") ?: "多仪提醒")
            .put("body", intent.getStringExtra("body") ?: "提醒时间到了")
            .put("payload", intent.getStringExtra("payload") ?: "")
            .put("vibrate", intent.getBooleanExtra("vibrate", true))
            .put("snoozeMinutes", intent.getIntExtra("snoozeMinutes", 0))
            .put("repeatCount", intent.getIntExtra("repeatCount", 0))
            .put("triggerAtMillis", triggerAtMillis)
            .put("repeat", intent.getBooleanExtra("repeat", false))
            .put("hour", intent.getIntExtra("hour", 9))
            .put("minute", intent.getIntExtra("minute", 0))
            .put("weekdays", JSONArray(weekdays.toList()))
            .put("timezoneId", intent.getStringExtra("timezoneId") ?: "")
            .toString()
    }
}
