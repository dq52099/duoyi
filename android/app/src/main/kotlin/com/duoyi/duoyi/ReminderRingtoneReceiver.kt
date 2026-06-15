package com.duoyi.duoyi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class ReminderRingtoneReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: "多仪提醒"
        val body = intent.getStringExtra("body") ?: "提醒时间到了"
        val payload = intent.getStringExtra("payload")
        val fullScreen = intent.getBooleanExtra("fullScreen", false)
        val vibrate = intent.getBooleanExtra("vibrate", true)
        val snoozeMinutes = intent.getIntExtra("snoozeMinutes", 0)
        val repeatRemaining = intent.getIntExtra("repeatRemaining", 0)
        val rootId = intent.getIntExtra("rootId", id)
        val deliveryToken = ReminderRingtoneScheduler.deliveryTokenFrom(intent)
        ReminderRingtoneScheduler.cancelFlutterPluginOwner(context, id)
        if (rootId != id) {
            ReminderRingtoneScheduler.cancelFlutterPluginOwner(context, rootId)
        }
        if (!ReminderRingtoneScheduler.reserveDelivery(context, id, rootId, deliveryToken)) {
            ReminderRingtoneService.cancelFlutterPluginNotification(context, id)
            ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, id)
            if (rootId != id) {
                ReminderRingtoneService.cancelFlutterPluginNotification(context, rootId)
                ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, rootId)
            }
            return
        }

        ReminderRingtoneService.cancelFlutterPluginNotification(context, id)
        ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, id)
        if (rootId != id) {
            ReminderRingtoneService.cancelNotification(context, rootId)
            ReminderRingtoneService.cancelFlutterPluginNotification(context, rootId)
            ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, rootId)
        }
        ReminderRingtoneScheduler.recordNotificationPermissionIssueIfDenied(context, id)
        val serviceIntent = ReminderRingtoneService.intent(context, id, title, body, payload, fullScreen, vibrate, snoozeMinutes, repeatRemaining, rootId)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, id)
            if (rootId != id) {
                ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, rootId)
            }
        } catch (error: Exception) {
            Log.e("ReminderRingtoneReceiver", "start ringtone service failed", error)
            ReminderRingtoneScheduler.recordDeliveryIssue(
                context,
                id,
                "service_start_failed",
                "系统拦截了前台铃声服务，已尝试发送兜底通知。",
            )
            ReminderRingtoneService.cancelFlutterPluginNotification(context, id)
            if (rootId != id) {
                ReminderRingtoneService.cancelNotification(context, rootId)
                ReminderRingtoneService.cancelFlutterPluginNotification(context, rootId)
            }
            showFallbackNotification(context, id, title, body, payload, fullScreen, rootId)
            if (fullScreen && !ReminderFullScreenActivity.launch(context, id, rootId, title, body, payload)) {
                ReminderRingtoneScheduler.recordDeliveryIssue(
                    context,
                    id,
                    "full_screen_launch_failed",
                    "系统拦截了兜底全屏闹钟弹出，已保留高优先级通知。",
                )
            }
            ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, id)
            if (rootId != id) {
                ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, rootId)
            }
        }

        if (intent.getBooleanExtra("repeat", false)) {
            ReminderRingtoneScheduler.rescheduleFromReceiver(context, intent)
        } else {
            ReminderRingtoneScheduler.markDelivered(context, id, rootId)
        }
    }

    companion object {
        private const val fallbackChannelId = "duoyi_alarm_fallback_v9"
        private const val prefsName = "FlutterSharedPreferences"
        private const val soundKey = "flutter.pref_reminder_ringtone_sound"
        private const val legacyAlarmMigrationKey = "flutter.pref_reminder_ringtone_alarm_migrated_to_soft"
        private const val fallbackChannelSoundSchemaVersion = 2
        private val legacyFallbackChannelIds = arrayOf(
            "duoyi_alarm_fallback_v1",
            "duoyi_alarm_fallback_v2",
            "duoyi_alarm_fallback_v3",
            "duoyi_alarm_fallback_v4",
            "duoyi_alarm_fallback_v5",
            "duoyi_alarm_fallback_v6",
            "duoyi_alarm_fallback_v7",
            "duoyi_alarm_fallback_v8",
        )

        fun showFallbackNotification(
            context: Context,
            id: Int,
            title: String,
            body: String,
            payload: String?,
            fullScreen: Boolean,
            rootId: Int = id,
        ): Boolean {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                Log.w("ReminderRingtoneReceiver", "fallback notification skipped: POST_NOTIFICATIONS denied")
                ReminderRingtoneScheduler.recordDeliveryIssue(
                    context,
                    id,
                    "fallback_notification_permission_denied",
                    "系统通知权限关闭，前台铃声服务失败后无法展示兜底通知。",
                )
                return false
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val fallbackSoundName = selectedFallbackSoundName(context)
            val fallbackSoundUri = fallbackSoundUri(context, fallbackSoundName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (fallbackChannelSoundNeedsRefresh(context, fallbackSoundName)) {
                    manager.deleteNotificationChannel(fallbackChannelId)
                }
                val channel = NotificationChannel(
                    fallbackChannelId,
                    "多仪 · 闹钟兜底通知",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "当前系统限制前台铃声服务时，使用已选择的内置铃声展示高优先级提醒"
                    setSound(
                        fallbackSoundUri,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build(),
                    )
                    enableVibration(true)
                }
                manager.createNotificationChannel(channel)
                markFallbackChannelSoundApplied(context, fallbackSoundName)
                legacyFallbackChannelIds.forEach { manager.deleteNotificationChannel(it) }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val openIntent = ReminderFullScreenActivity.mainActivityIntent(context, payload, stopRingtone = true)
            val contentIntent = PendingIntent.getActivity(context, id, openIntent, flags)
            val fullScreenIntent = PendingIntent.getActivity(
                context,
                id + 4_000_000,
                ReminderFullScreenActivity.intent(context, id, rootId, title, body, payload),
                flags,
            )
            val notification = NotificationCompat.Builder(context, fallbackChannelId)
                .setSmallIcon(R.drawable.ic_stat_duoyi)
                .setContentTitle(title)
                .setContentText(body)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(contentIntent)
                .setFullScreenIntent(fullScreenIntent, fullScreen)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setSound(fallbackSoundUri)
                .setVibrate(longArrayOf(0, 220, 420, 220))
                .setAutoCancel(true)
                .build()
            return runCatching {
                manager.notify(fallbackNotificationId(id), notification)
                true
            }.onFailure {
                Log.e("ReminderRingtoneReceiver", "fallback notification failed", it)
                ReminderRingtoneScheduler.recordDeliveryIssue(
                    context,
                    id,
                    "fallback_notification_failed",
                    "系统未接受闹钟兜底通知，请检查通知权限、后台限制和渠道声音。",
                )
            }.getOrDefault(false)
        }

        private fun fallbackNotificationId(id: Int): Int {
            return ReminderRingtoneService.notificationIdForReminder(id)
        }

        private fun fallbackSoundUri(context: Context, soundName: String): Uri {
            return Uri.parse("${android.content.ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/raw/duoyi_$soundName")
        }

        private fun selectedFallbackSoundName(context: Context): String {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val value = prefs.getString(soundKey, "soft") ?: "soft"
            if (value == "alarm" && !prefs.getBoolean(legacyAlarmMigrationKey, false)) {
                prefs.edit()
                    .putBoolean(legacyAlarmMigrationKey, true)
                    .putString(soundKey, "soft")
                    .apply()
                return "soft"
            }
            return normalizeSoundName(value)
        }

        private fun fallbackChannelSoundNeedsRefresh(
            context: Context,
            soundName: String,
        ): Boolean {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val rawResourceName = "duoyi_$soundName"
            val previous = prefs.getString(
                "flutter.pref_reminder_ringtone_fallback_channel_sound_$fallbackChannelId",
                null,
            )
            val schemaVersion = prefs.getInt(
                "flutter.pref_reminder_ringtone_fallback_channel_sound_schema_$fallbackChannelId",
                0,
            )
            return previous != rawResourceName ||
                schemaVersion != fallbackChannelSoundSchemaVersion
        }

        private fun markFallbackChannelSoundApplied(
            context: Context,
            soundName: String,
        ) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putString(
                    "flutter.pref_reminder_ringtone_fallback_channel_sound_$fallbackChannelId",
                    "duoyi_$soundName",
                )
                .putInt(
                    "flutter.pref_reminder_ringtone_fallback_channel_sound_schema_$fallbackChannelId",
                    fallbackChannelSoundSchemaVersion,
                )
                .apply()
        }

        private fun normalizeSoundName(value: String): String {
            return when (value) {
                "soft",
                "forest",
                "silver",
                "paper",
                "stream",
                "star",
                "marimba",
                "lull",
                "glass",
                "bamboo",
                "dawn",
                "wood",
                "water",
                "harp",
                "mist",
                "pebble",
                "tide",
                "chime",
                "bell",
                "morning",
                "pearl",
                "cedar",
                "moon",
                "cloud",
                "sakura",
                "beep",
                "classic",
                "alarm" -> value
                else -> "soft"
            }
        }
    }
}
