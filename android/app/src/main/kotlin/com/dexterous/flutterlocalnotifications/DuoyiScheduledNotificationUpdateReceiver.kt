package com.dexterous.flutterlocalnotifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONArray
import java.time.LocalDateTime
import java.time.ZoneId

class DuoyiScheduledNotificationUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        pruneExpiredOneShotNotifications(context)
        FlutterLocalNotificationsPlugin.rescheduleNotifications(context)
    }

    private fun pruneExpiredOneShotNotifications(context: Context) {
        runCatching {
            val store = context.getSharedPreferences(
                scheduledNotificationsPrefsName,
                Context.MODE_PRIVATE,
            )
            val raw = store.getString(scheduledNotificationsPrefsKey, null)
                ?: return
            val source = JSONArray(raw)
            val kept = JSONArray()
            val now = System.currentTimeMillis()
            for (index in 0 until source.length()) {
                val item = source.optJSONObject(index)
                if (item == null || shouldKeep(item = item, now = now)) {
                    kept.put(source.get(index))
                }
            }
            store.edit().putString(scheduledNotificationsPrefsKey, kept.toString()).commit()
        }.onFailure { error ->
            Log.w(tag, "failed to prune expired scheduled notifications after update", error)
        }
    }

    private fun shouldKeep(item: org.json.JSONObject, now: Long): Boolean {
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

    companion object {
        private const val tag = "DuoyiNotifUpdate"
        private const val scheduledNotificationsPrefsName = "scheduled_notifications"
        private const val scheduledNotificationsPrefsKey = "scheduled_notifications"
    }
}
