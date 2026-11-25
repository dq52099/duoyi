package com.dexterous.flutterlocalnotifications

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.duoyi.duoyi.ReminderRingtoneScheduler
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

class DuoyiScheduledNotificationUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (!isSupportedAction(action)) return
        val canScheduleExactAlarms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            manager?.canScheduleExactAlarms() == true
        } else {
            true
        }
        if (action == actionScheduleExactAlarmPermissionStateChanged && canScheduleExactAlarms) {
            applyScheduledNotificationsTransform(
                context = context,
                upgradeExactAlarms = true,
                resolvedTimeZoneId = ReminderRingtoneScheduler.resolveRescheduleTimeZone(context),
            )
        } else {
            pruneExpiredOneShotNotifications(context)
        }
        runCatching {
            FlutterLocalNotificationsPlugin.rescheduleNotifications(context)
        }.onFailure { error ->
            Log.w(tag, "failed to reschedule scheduled notifications after update", error)
        }
    }

    private fun pruneExpiredOneShotNotifications(context: Context) {
        applyScheduledNotificationsTransform(
            context = context,
            upgradeExactAlarms = false,
            resolvedTimeZoneId = ReminderRingtoneScheduler.resolveRescheduleTimeZone(context),
        )
    }

    private fun applyScheduledNotificationsTransform(
        context: Context,
        upgradeExactAlarms: Boolean,
        resolvedTimeZoneId: String?,
    ) {
        runCatching {
            val store = context.getSharedPreferences(
                scheduledNotificationsPrefsName,
                Context.MODE_PRIVATE,
            )
            val raw = store.getString(scheduledNotificationsPrefsKey, null)
                ?: return
            val updated = transformScheduledNotificationsJson(
                raw = raw,
                now = System.currentTimeMillis(),
                upgradeExactAlarms = upgradeExactAlarms,
                resolvedTimeZoneId = resolvedTimeZoneId,
            ) ?: return
            store.edit().putString(scheduledNotificationsPrefsKey, updated).commit()
        }.onFailure { error ->
            Log.w(tag, "failed to prune expired scheduled notifications after update", error)
        }
    }

    companion object {
        private const val tag = "DuoyiNotifUpdate"
        private const val scheduledNotificationsPrefsName = "scheduled_notifications"
        private const val scheduledNotificationsPrefsKey = "scheduled_notifications"
        internal const val actionScheduleExactAlarmPermissionStateChanged =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"

        internal fun isSupportedAction(action: String?): Boolean {
            return when (action) {
                Intent.ACTION_MY_PACKAGE_REPLACED,
                actionScheduleExactAlarmPermissionStateChanged,
                Intent.ACTION_TIME_CHANGED,
                "android.intent.action.TIME_SET",
                Intent.ACTION_TIMEZONE_CHANGED -> true
                else -> false
            }
        }

        internal fun transformScheduledNotificationsJson(
            raw: String,
            now: Long,
            upgradeExactAlarms: Boolean = false,
            resolvedTimeZoneId: String? = null,
        ): String? {
            val source = JSONArray(raw)
            val kept = JSONArray()
            for (index in 0 until source.length()) {
                val item = source.optJSONObject(index)
                if (item == null) {
                    kept.put(source.get(index))
                    continue
                }
                if (!shouldKeep(item = item, now = now)) {
                    continue
                }
                val copy = JSONObject(item.toString())
                if (upgradeExactAlarms) {
                    upgradeScheduleModeIfNeeded(copy)
                }
                if (!resolvedTimeZoneId.isNullOrBlank()) {
                    refreshRepeatingZonedSchedule(copy, now, resolvedTimeZoneId)
                }
                kept.put(copy)
            }
            return kept.toString()
        }

        private fun upgradeScheduleModeIfNeeded(item: JSONObject) {
            when (item.optString("scheduleMode")) {
                "inexactAllowWhileIdle" -> item.put("scheduleMode", "exactAllowWhileIdle")
                "inexact" -> item.put("scheduleMode", "exact")
            }
        }

        private fun refreshRepeatingZonedSchedule(
            item: JSONObject,
            nowMillis: Long,
            resolvedTimeZoneId: String,
        ) {
            if (item.isNull("matchDateTimeComponents")) return
            val components = item.optString("matchDateTimeComponents").takeIf { it.isNotBlank() }
                ?: return
            val rawDateTime = item.optString("scheduledDateTime").takeIf { it.isNotBlank() }
                ?: return
            val rawZone = item.optString("timeZoneName").takeIf { it.isNotBlank() }
                ?: resolvedTimeZoneId
            val targetZone = runCatching { ZoneId.of(resolvedTimeZoneId) }.getOrElse {
                runCatching { ZoneId.of(rawZone) }.getOrNull() ?: return
            }
            val parsedLocal = runCatching { LocalDateTime.parse(rawDateTime) }.getOrNull() ?: return
            val existingZone = runCatching { ZoneId.of(rawZone) }.getOrNull()
            val existingEpoch = existingZone?.let { zone ->
                runCatching { parsedLocal.atZone(zone).toInstant().toEpochMilli() }.getOrNull()
            }
            val needsRecompute = existingZone != targetZone ||
                existingEpoch == null ||
                existingEpoch <= nowMillis
            if (!needsRecompute) return

            val now = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(nowMillis), targetZone)
            var nextFire = ZonedDateTime.of(
                now.year,
                now.monthValue,
                now.dayOfMonth,
                parsedLocal.hour,
                parsedLocal.minute,
                parsedLocal.second,
                parsedLocal.nano,
                targetZone,
            )
            if (nextFire.isBefore(now) || !nextFire.toInstant().toEpochMilli().let { it > nowMillis }) {
                nextFire = nextFire.plusDays(1)
            }
            when (components) {
                "Time" -> Unit
                "DayOfWeekAndTime" -> {
                    var guard = 0
                    while (nextFire.dayOfWeek != parsedLocal.dayOfWeek && guard < 14) {
                        nextFire = nextFire.plusDays(1)
                        guard++
                    }
                }
                "DayOfMonthAndTime" -> {
                    var guard = 0
                    while (nextFire.dayOfMonth != parsedLocal.dayOfMonth && guard < 400) {
                        nextFire = nextFire.plusDays(1)
                        guard++
                    }
                }
                "DateAndTime" -> {
                    var guard = 0
                    while ((nextFire.monthValue != parsedLocal.monthValue ||
                            nextFire.dayOfMonth != parsedLocal.dayOfMonth) &&
                        guard < 1500
                    ) {
                        nextFire = nextFire.plusDays(1)
                        guard++
                    }
                }
            }
            item.put("scheduledDateTime", DateTimeFormatter.ISO_LOCAL_DATE_TIME.format(nextFire))
            item.put("timeZoneName", targetZone.id)
        }

        internal fun shouldKeep(item: JSONObject, now: Long): Boolean {
            if (!item.isNull("repeatInterval") ||
                !item.isNull("repeatIntervalMilliseconds") ||
                !item.isNull("scheduledNotificationRepeatFrequency") ||
                !item.isNull("matchDateTimeComponents")
            ) {
                return true
            }
            if (!item.isNull("millisecondsSinceEpoch")) {
                return item.optLong("millisecondsSinceEpoch", Long.MAX_VALUE) > now
            }
            val scheduledDateTime = item.optString("scheduledDateTime").takeIf { it.isNotBlank() }
                ?: return true
            val timeZoneName = item.optString("timeZoneName").takeIf { it.isNotBlank() }
                ?: return true
            val epochMillis = runCatching {
                LocalDateTime.parse(scheduledDateTime)
                    .atZone(ZoneId.of(timeZoneName))
                    .toInstant()
                    .toEpochMilli()
            }.getOrElse {
                return true
            }
            return epochMillis > now
        }
    }
}
