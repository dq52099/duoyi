package com.duoyi.duoyi.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.duoyi.duoyi.MainActivity
import com.duoyi.duoyi.R

class FocusSoundForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop) {
            stopRequestCallback?.invoke()
            stopSelf()
            return START_NOT_STICKY
        }
        ensureChannel()
        startForeground(notificationId, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): android.app.Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            flags,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, FocusSoundForegroundService::class.java).setAction(actionStop),
            flags,
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("多仪白噪音")
            .setContentText("专注背景音正在播放")
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openIntent)
            .addAction(0, "停止", stopIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
            "多仪 · 白噪音播放",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "白噪音和专注背景音播放时保持前台服务"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val channelId = "duoyi_focus_sound_playback_v1"
        private const val notificationId = 951_001
        private const val actionStop = "com.duoyi.duoyi.FOCUS_SOUND_STOP"
        var stopRequestCallback: (() -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(context, FocusSoundForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FocusSoundForegroundService::class.java))
        }
    }
}
