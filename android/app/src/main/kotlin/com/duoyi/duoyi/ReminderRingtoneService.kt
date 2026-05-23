package com.duoyi.duoyi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

class ReminderRingtoneService : Service() {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop) {
            intent.getIntExtra("id", 0).takeIf { it != 0 }?.let { cancelStatusNotification(it) }
            stopSelf()
            return START_NOT_STICKY
        }

        val id = intent?.getIntExtra("id", 0) ?: 0
        val title = intent?.getStringExtra("title") ?: "多仪提醒"
        val body = intent?.getStringExtra("body") ?: "提醒时间到了"
        val payload = intent?.getStringExtra("payload")
        val shouldVibrate = intent?.getBooleanExtra("vibrate", true) ?: true
        val snoozeMinutes = intent?.getIntExtra("snoozeMinutes", 0)?.coerceIn(0, 120) ?: 0
        val repeatRemaining = intent?.getIntExtra("repeatRemaining", 0)?.coerceIn(0, 10) ?: 0
        if (intent?.action == actionSnooze) {
            val delayMinutes = intent.getIntExtra("delayMinutes", 5).coerceIn(1, 120)
            ReminderRingtoneScheduler.scheduleOnce(
                context = this,
                id = id,
                title = title,
                body = body,
                triggerAtMillis = System.currentTimeMillis() + delayMinutes * 60_000L,
                payload = payload,
                vibrate = shouldVibrate,
                snoozeMinutes = snoozeMinutes,
                repeatCount = repeatRemaining,
            )
            stopSelf()
            return START_NOT_STICKY
        }

        activeReminderId = id
        startForeground(
            notificationId(id),
            buildNotification(
                id = id,
                title = title,
                body = body,
                payload = payload,
                shouldVibrate = shouldVibrate,
                snoozeMinutes = snoozeMinutes,
                repeatRemaining = repeatRemaining,
            ),
        )
        playRingtone()
        if (shouldVibrate) vibrate()
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = Runnable {
            scheduleAutoRepeat(id, title, body, payload, shouldVibrate, snoozeMinutes, repeatRemaining)
            stopSelf()
        }
        handler.postDelayed(stopRunnable!!, 30_000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = null
        player?.run {
            runCatching { stop() }
            release()
        }
        player = null
        activeReminderId = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun playRingtone() {
        player?.release()
        val afd = resources.openRawResourceFd(soundResId(this)) ?: return
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            isLooping = true
            val volume = volumePercent(this@ReminderRingtoneService) / 100f
            setVolume(volume, volume)
            setOnPreparedListener { it.start() }
            prepareAsync()
        }
        afd.close()
    }

    private fun vibrate() {
        val pattern = longArrayOf(0, 220, 420, 220)
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    private fun buildNotification(
        id: Int,
        title: String,
        body: String,
        payload: String?,
        shouldVibrate: Boolean,
        snoozeMinutes: Int,
        repeatRemaining: Int,
    ): android.app.Notification {
        ensureChannel()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentIntent = PendingIntent.getActivity(
            this,
            id,
            openAppIntent(payload, stopRingtone = true),
            flags,
        )
        val fullScreenIntent = PendingIntent.getActivity(
            this,
            id + 3_000_000,
            openAppIntent(payload, stopRingtone = true),
            flags,
        )
        val stopIntent = PendingIntent.getService(
            this,
            id + 1_000_000,
            Intent(this, ReminderRingtoneService::class.java)
                .setAction(actionStop)
                .putExtra("id", id),
            flags,
        )
        val snoozeIntent = if (snoozeMinutes > 0) {
            PendingIntent.getService(
                this,
                id + 2_000_000,
                Intent(this, ReminderRingtoneService::class.java)
                    .setAction(actionSnooze)
                    .putExtra("id", id)
                    .putExtra("title", title)
                    .putExtra("body", body)
                    .putExtra("payload", payload)
                    .putExtra("vibrate", shouldVibrate)
                    .putExtra("snoozeMinutes", snoozeMinutes)
                    .putExtra("delayMinutes", snoozeMinutes)
                    .putExtra("repeatRemaining", repeatRemaining),
                flags,
            )
        } else {
            null
        }

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(false)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(contentIntent)
            .setDeleteIntent(stopIntent)
            .setFullScreenIntent(fullScreenIntent, false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .addAction(0, "停止响铃", stopIntent)
        if (snoozeIntent != null) {
            builder.addAction(0, "稍后 $snoozeMinutes 分钟", snoozeIntent)
        }
        return builder.build()
    }

    private fun scheduleAutoRepeat(
        id: Int,
        title: String,
        body: String,
        payload: String?,
        shouldVibrate: Boolean,
        snoozeMinutes: Int,
        repeatRemaining: Int,
    ) {
        if (repeatRemaining <= 0) return
        val delayMinutes = if (snoozeMinutes > 0) snoozeMinutes else 5
        ReminderRingtoneScheduler.scheduleOnce(
            context = this,
            id = id,
            title = title,
            body = body,
            triggerAtMillis = System.currentTimeMillis() + delayMinutes * 60_000L,
            payload = payload,
            vibrate = shouldVibrate,
            snoozeMinutes = snoozeMinutes,
            repeatCount = repeatRemaining - 1,
        )
    }

    private fun openAppIntent(payload: String?, stopRingtone: Boolean): Intent {
        val intent = if (!payload.isNullOrBlank()) {
            Intent(Intent.ACTION_VIEW, Uri.parse(payload), this, MainActivity::class.java)
        } else {
            packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        }
        return intent
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(extraStopRingtone, stopRingtone)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
                "多仪 · 内置柔和提醒铃声",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "播放苹果/小米风格轻铃，并可在通知上手动停止"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun notificationId(id: Int) = 940_000 + kotlin.math.abs(id % 10_000)

    private fun cancelStatusNotification(id: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId(id))
    }

    companion object {
        private const val channelId = "duoyi_builtin_ringtone_status_v2"
        private const val actionStop = "com.duoyi.duoyi.REMINDER_RING_STOP"
        private const val actionSnooze = "com.duoyi.duoyi.REMINDER_RING_SNOOZE"
        const val extraStopRingtone = "duoyi.extra.STOP_REMINDER_RINGTONE"
        private const val prefsName = "FlutterSharedPreferences"
        private const val volumeKey = "flutter.pref_reminder_ringtone_volume_percent"
        private const val soundKey = "flutter.pref_reminder_ringtone_sound"
        @Volatile
        private var activeReminderId: Int? = null

        fun stopActive(context: Context) {
            context.stopService(Intent(context, ReminderRingtoneService::class.java))
        }

        fun stopIfActive(context: Context, id: Int) {
            if (activeReminderId == id) stopActive(context)
        }

        fun setVolumePercent(context: Context, value: Int) {
            val normalized = value.coerceIn(40, 100)
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putInt(volumeKey, normalized)
                .apply()
        }

        fun setSoundName(context: Context, value: String) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putString(soundKey, normalizeSoundName(value))
                .apply()
        }

        private fun volumePercent(context: Context): Int {
            return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getInt(volumeKey, 60)
                .coerceIn(40, 80)
        }

        private fun soundResId(context: Context): Int {
            val name = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getString(soundKey, "chime") ?: "chime"
            return when (normalizeSoundName(name)) {
                "chime" -> R.raw.duoyi_chime
                "bell" -> R.raw.duoyi_bell
                "beep" -> R.raw.duoyi_beep
                "classic" -> R.raw.duoyi_classic
                "alarm" -> R.raw.duoyi_alarm
                else -> R.raw.duoyi_chime
            }
        }

        private fun normalizeSoundName(value: String): String {
            return when (value) {
                "chime", "bell", "beep", "classic", "alarm" -> value
                else -> "chime"
            }
        }

        fun intent(
            context: Context,
            id: Int,
            title: String,
            body: String,
            payload: String?,
            vibrate: Boolean = true,
            snoozeMinutes: Int = 0,
            repeatCount: Int = 0,
        ): Intent {
            return Intent(context, ReminderRingtoneService::class.java)
                .putExtra("id", id)
                .putExtra("title", title)
                .putExtra("body", body)
                .putExtra("payload", payload)
                .putExtra("vibrate", vibrate)
                .putExtra("snoozeMinutes", snoozeMinutes.coerceIn(0, 120))
                .putExtra("repeatCount", repeatCount.coerceIn(0, 10))
                .putExtra("repeatRemaining", repeatCount.coerceIn(0, 10))
        }
    }
}
