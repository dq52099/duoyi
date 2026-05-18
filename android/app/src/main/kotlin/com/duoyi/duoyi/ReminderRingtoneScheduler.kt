package com.duoyi.duoyi

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar
import java.util.TimeZone

object ReminderRingtoneScheduler {
    private const val actionRing = "com.duoyi.duoyi.REMINDER_RING"
    private const val prefsName = "duoyi_native_reminder_ringtone"
    private const val idsKey = "ids"

    fun showNow(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: String?,
    ) {
        val intent = ReminderRingtoneService.intent(context, id, title, body, payload)
        context.startService(intent)
    }

    fun scheduleOnce(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long,
        payload: String?,
    ) {
        val intent = baseIntent(context, id, title, body, payload)
        schedule(context, id, triggerAtMillis, intent)
        rememberId(context, id)
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
    ) {
        val normalized = weekdays.filter { it in 1..7 }.distinct().toIntArray()
        val zoneId = normalizeTimeZone(timezoneId)
        val triggerAtMillis = nextWallClockMillis(hour, minute, normalized, zoneId)
        val intent = baseIntent(context, id, title, body, payload)
            .putExtra("repeat", true)
            .putExtra("hour", hour)
            .putExtra("minute", minute)
            .putExtra("weekdays", normalized)
            .putExtra("timezoneId", zoneId)
        schedule(context, id, triggerAtMillis, intent)
        rememberId(context, id)
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

    private fun baseIntent(
        context: Context,
        id: Int,
        title: String,
        body: String,
        payload: String?,
    ): Intent {
        return Intent(context, ReminderRingtoneReceiver::class.java)
            .setAction(actionRing)
            .putExtra("id", id)
            .putExtra("title", title)
            .putExtra("body", body)
            .putExtra("payload", payload)
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
        if (timezoneId.isNullOrBlank() || timezoneId == "UTC") return "Asia/Shanghai"
        return timezoneId
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun rememberId(context: Context, id: Int) {
        val next = prefs(context).getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        next.add(id.toString())
        prefs(context).edit().putStringSet(idsKey, next).apply()
    }

    private fun forgetId(context: Context, id: Int) {
        val next = prefs(context).getStringSet(idsKey, emptySet()).orEmpty().toMutableSet()
        next.remove(id.toString())
        prefs(context).edit().putStringSet(idsKey, next).apply()
    }
}
