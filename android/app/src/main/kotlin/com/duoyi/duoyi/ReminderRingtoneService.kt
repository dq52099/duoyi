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
    private val stopRunnable = Runnable { stopSelf() }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop) {
            stopSelf()
            return START_NOT_STICKY
        }

        val id = intent?.getIntExtra("id", 0) ?: 0
        val title = intent?.getStringExtra("title") ?: "多仪提醒"
        val body = intent?.getStringExtra("body") ?: "提醒时间到了"
        val payload = intent?.getStringExtra("payload")

        startForeground(notificationId(id), buildNotification(id, title, body, payload))
        playRingtone()
        vibrate()
        handler.removeCallbacks(stopRunnable)
        handler.postDelayed(stopRunnable, 30_000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopRunnable)
        player?.run {
            runCatching { stop() }
            release()
        }
        player = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun playRingtone() {
        player?.release()
        val afd = resources.openRawResourceFd(R.raw.duoyi_alarm) ?: return
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            isLooping = true
            setOnPreparedListener { it.start() }
            prepareAsync()
        }
        afd.close()
    }

    private fun vibrate() {
        val pattern = longArrayOf(0, 600, 350, 600, 350, 900)
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
    ): android.app.Notification {
        ensureChannel()
        val openIntent = if (!payload.isNullOrBlank()) {
            Intent(Intent.ACTION_VIEW, Uri.parse(payload), this, MainActivity::class.java)
        } else {
            packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val contentIntent = PendingIntent.getActivity(this, id, openIntent, flags)
        val stopIntent = PendingIntent.getService(
            this,
            id + 1_000_000,
            Intent(this, ReminderRingtoneService::class.java).setAction(actionStop),
            flags,
        )

        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setContentIntent(contentIntent)
            .addAction(0, "停止响铃", stopIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
            "多仪 · 内置提醒铃声",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "用于 HyperOS 等系统通知静音时播放应用内置提醒铃声"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun notificationId(id: Int) = 940_000 + kotlin.math.abs(id % 10_000)

    companion object {
        private const val channelId = "duoyi_builtin_ringtone_status_v1"
        private const val actionStop = "com.duoyi.duoyi.REMINDER_RING_STOP"

        fun intent(
            context: Context,
            id: Int,
            title: String,
            body: String,
            payload: String?,
        ): Intent {
            return Intent(context, ReminderRingtoneService::class.java)
                .putExtra("id", id)
                .putExtra("title", title)
                .putExtra("body", body)
                .putExtra("payload", payload)
        }
    }
}
