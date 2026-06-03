package com.duoyi.duoyi

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

class ReminderRingtoneService : Service() {
    private var player: MediaPlayer? = null
    private var toneGenerator: ToneGenerator? = null
    private var toneRunnable: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == actionStop) {
            val id = intent.getIntExtra("id", 0)
            val rootId = intent.getIntExtra("rootId", id)
            cancelPendingAutoRepeat(rootId)
            id.takeIf { it != 0 }?.let { cancelStatusNotification(it) }
            stopSelf()
            return START_NOT_STICKY
        }

        val id = intent?.getIntExtra("id", 0) ?: 0
        val title = intent?.getStringExtra("title") ?: "多仪提醒"
        val body = intent?.getStringExtra("body") ?: "提醒时间到了"
        val payload = intent?.getStringExtra("payload")
        val fullScreen = intent?.getBooleanExtra("fullScreen", false) ?: false
        val shouldVibrate = intent?.getBooleanExtra("vibrate", true) ?: true
        val snoozeMinutes = intent?.getIntExtra("snoozeMinutes", 0)?.coerceIn(0, 120) ?: 0
        val repeatRemaining = intent?.getIntExtra("repeatRemaining", 0)?.coerceIn(0, 10) ?: 0
        val rootId = intent?.getIntExtra("rootId", id) ?: id
        if (intent?.action == actionSnooze) {
            cancelPendingAutoRepeat(rootId)
            val delayMinutes = intent.getIntExtra("delayMinutes", 5).coerceIn(1, 120)
            ReminderRingtoneScheduler.scheduleFollowUpOnce(
                context = this,
                rootId = rootId,
                followUpKind = ReminderRingtoneScheduler.FOLLOW_UP_SNOOZE,
                title = title,
                body = body,
                triggerAtMillis = System.currentTimeMillis() + delayMinutes * 60_000L,
                payload = payload,
                fullScreen = fullScreen,
                vibrate = shouldVibrate,
                snoozeMinutes = snoozeMinutes,
                repeatCount = repeatRemaining,
            )
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            activeReminderId = id
            cancelFlutterPluginNotification(this, id)
            cancelStatusNotification(id)
            if (rootId != id) cancelStatusNotification(rootId)
            startForeground(
                notificationId(id),
                buildNotification(
                    id = id,
                    title = title,
                    body = body,
                    payload = payload,
                    fullScreen = fullScreen,
                    shouldVibrate = shouldVibrate,
                    snoozeMinutes = snoozeMinutes,
                    repeatRemaining = repeatRemaining,
                    rootId = rootId,
                ),
            )
            cancelFlutterPluginNotificationSoon(this, id)
            if (rootId != id) cancelFlutterPluginNotificationSoon(this, rootId)
            if (!playRingtone(id)) {
                throw IllegalStateException("ringtone playback failed")
            }
            if (shouldVibrate) vibrate()
        } catch (error: Exception) {
            Log.e("ReminderRingtoneService", "start ringtone playback failed", error)
            ReminderRingtoneScheduler.recordDeliveryIssue(
                this,
                id = id,
                reason = "ringtone_service_failed",
                message = "内置提醒铃声服务启动或播放失败，请检查系统闹钟音量、通知权限、勿扰模式或后台限制。",
            )
            cancelStatusNotification(id)
            cancelFlutterPluginNotification(this, id)
            if (rootId != id) {
                cancelStatusNotification(rootId)
                cancelFlutterPluginNotification(this, rootId)
            }
            activeReminderId = null
            ReminderRingtoneReceiver.showFallbackNotification(this, id, title, body, payload, fullScreen)
            cancelFlutterPluginNotificationSoon(this, id)
            if (rootId != id) cancelFlutterPluginNotificationSoon(this, rootId)
            stopSelf()
            return START_NOT_STICKY
        }
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = Runnable {
            scheduleAutoRepeat(rootId, title, body, payload, fullScreen, shouldVibrate, snoozeMinutes, repeatRemaining)
            stopSelf()
        }
        handler.postDelayed(stopRunnable!!, 30_000L)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        activeReminderId?.let { cancelStatusNotification(it) }
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = null
        releasePlayer()
        activeReminderId = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun playRingtone(id: Int): Boolean {
        releasePlayer()
        val volume = volumePercent(this) / 100f
        val selectedResId = soundResId(this)
        if (playRawRingtone(selectedResId, volume, id, "raw_selected")) return true
        if (selectedResId != R.raw.duoyi_soft && playRawRingtone(R.raw.duoyi_soft, volume, id, "raw_soft_fallback")) {
            Log.w("ReminderRingtoneService", "selected ringtone failed, fell back to built-in soft morning chime")
            return true
        }
        return playToneFallback(volume, id)
    }

    private fun playRawRingtone(resId: Int, volume: Float, id: Int, source: String): Boolean {
        val afd = runCatching { resources.openRawResourceFd(resId) }.getOrNull()
        if (afd == null) {
            return false
        }
        if (afd.length <= minAudibleRawBytes) {
            Log.w("ReminderRingtoneService", "raw ringtone resource is too small, trying soft fallback")
            afd.close()
            return false
        }
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(alarmAudioAttributes())
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                isLooping = true
                setVolume(volume, volume)
                setOnPreparedListener { preparedPlayer ->
                    runCatching {
                        preparedPlayer.start()
                        ReminderRingtoneScheduler.recordPlaybackStarted(
                            this@ReminderRingtoneService,
                            id,
                            source,
                        )
                    }.onFailure { error ->
                        Log.w("ReminderRingtoneService", "raw ringtone start failed, trying fallback", error)
                        if (player === preparedPlayer) player = null
                        runCatching { preparedPlayer.release() }
                        if (resId != R.raw.duoyi_soft) {
                            playRawRingtone(R.raw.duoyi_soft, volume, id, "raw_soft_fallback")
                        } else {
                            playToneFallback(volume, id)
                        }
                    }
                }
                setOnErrorListener { mp, _, _ ->
                    if (player === mp) player = null
                    runCatching { mp.release() }
                    if (resId != R.raw.duoyi_soft) {
                        playRawRingtone(R.raw.duoyi_soft, volume, id, "raw_soft_fallback")
                    } else {
                        playToneFallback(volume, id)
                    }
                    true
                }
                prepareAsync()
            }
            return true
        } catch (error: Exception) {
            Log.w("ReminderRingtoneService", "raw ringtone playback failed, trying soft fallback", error)
            return false
        } finally {
            afd.close()
        }
    }

    private fun playToneFallback(volume: Float, id: Int): Boolean {
        releaseToneFallback()
        val toneVolume = (volume * 100).toInt().coerceIn(40, 100)
        return runCatching {
            toneGenerator = ToneGenerator(AudioManager.STREAM_NOTIFICATION, toneVolume)
            val initialStarted = toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 260) == true
            if (!initialStarted) {
                ReminderRingtoneScheduler.recordDeliveryIssue(
                    this,
                    id = id,
                    reason = "tone_fallback_failed",
                    message = "兜底提示音播放失败，请检查系统音量、勿扰模式或音频焦点限制。",
                )
                releaseToneFallback()
                return@runCatching false
            }
            toneRunnable = object : Runnable {
                override fun run() {
                    val started = toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 260) == true
                    if (!started) {
                        ReminderRingtoneScheduler.recordDeliveryIssue(
                            this@ReminderRingtoneService,
                            id = id,
                            reason = "tone_fallback_failed",
                            message = "兜底提示音播放失败，请检查系统音量、勿扰模式或音频焦点限制。",
                        )
                        return
                    }
                    handler.postDelayed(this, 1800L)
                }
            }
            handler.postDelayed(toneRunnable!!, 1800L)
            ReminderRingtoneScheduler.recordPlaybackStarted(
                this,
                id,
                "tone_fallback",
            )
            true
        }.onFailure {
            Log.e("ReminderRingtoneService", "tone fallback playback failed", it)
            ReminderRingtoneScheduler.recordDeliveryIssue(
                this,
                id = id,
                reason = "ringtone_playback_failed",
                message = "内置柔和铃声和兜底提示音都播放失败，请检查系统闹钟音量、通知/铃声音量、勿扰模式或系统后台限制。",
            )
            releaseToneFallback()
        }.getOrDefault(false)
    }

    private fun alarmAudioAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }

    private fun releasePlayer() {
        player?.run {
            runCatching { stop() }
            release()
        }
        player = null
        releaseToneFallback()
    }

    private fun releaseToneFallback() {
        toneRunnable?.let { handler.removeCallbacks(it) }
        toneRunnable = null
        toneGenerator?.release()
        toneGenerator = null
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
        fullScreen: Boolean,
        shouldVibrate: Boolean,
        snoozeMinutes: Int,
        repeatRemaining: Int,
        rootId: Int,
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
                .putExtra("id", id)
                .putExtra("rootId", rootId),
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
                    .putExtra("fullScreen", fullScreen)
                    .putExtra("vibrate", shouldVibrate)
                    .putExtra("snoozeMinutes", snoozeMinutes)
                    .putExtra("delayMinutes", snoozeMinutes)
                    .putExtra("repeatRemaining", repeatRemaining)
                    .putExtra("rootId", rootId),
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
            .setFullScreenIntent(fullScreenIntent, fullScreen)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, "停止响铃", stopIntent)
        if (snoozeIntent != null) {
            builder.addAction(0, "稍后 $snoozeMinutes 分钟", snoozeIntent)
        }
        return builder.build()
    }

    private fun scheduleAutoRepeat(
        rootId: Int,
        title: String,
        body: String,
        payload: String?,
        fullScreen: Boolean,
        shouldVibrate: Boolean,
        snoozeMinutes: Int,
        repeatRemaining: Int,
    ) {
        if (repeatRemaining <= 0) return
        val delayMinutes = if (snoozeMinutes > 0) snoozeMinutes else 5
        ReminderRingtoneScheduler.scheduleFollowUpOnce(
            context = this,
            rootId = rootId,
            followUpKind = ReminderRingtoneScheduler.FOLLOW_UP_AUTO_REPEAT,
            title = title,
            body = body,
            triggerAtMillis = System.currentTimeMillis() + delayMinutes * 60_000L,
            payload = payload,
            fullScreen = fullScreen,
            vibrate = shouldVibrate,
            snoozeMinutes = snoozeMinutes,
            repeatCount = repeatRemaining - 1,
        )
    }

    private fun cancelPendingAutoRepeat(rootId: Int) {
        stopRunnable?.let { handler.removeCallbacks(it) }
        stopRunnable = null
        ReminderRingtoneScheduler.cancelFollowUps(this, rootId)
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
        legacyChannelIds.forEach { manager.deleteNotificationChannel(it) }
    }

    private fun notificationId(id: Int) = notificationIdForReminder(id)

    private fun cancelStatusNotification(id: Int) {
        cancelNotification(this, id)
    }

    companion object {
        private const val channelId = "duoyi_builtin_ringtone_status_v4"
        private val legacyChannelIds = arrayOf(
            "duoyi_builtin_ringtone_status_v1",
            "duoyi_builtin_ringtone_status_v2",
            "duoyi_builtin_ringtone_status_v3",
        )
        private const val actionStop = "com.duoyi.duoyi.REMINDER_RING_STOP"
        private const val actionSnooze = "com.duoyi.duoyi.REMINDER_RING_SNOOZE"
        const val extraStopRingtone = "duoyi.extra.STOP_REMINDER_RINGTONE"
        private const val prefsName = "FlutterSharedPreferences"
        private const val volumeKey = "flutter.pref_reminder_ringtone_volume_percent"
        private const val soundKey = "flutter.pref_reminder_ringtone_sound"
        private const val legacyAlarmMigrationKey = "flutter.pref_reminder_ringtone_alarm_migrated_to_soft"
        private const val minAudibleRawBytes = 4096L
        private val flutterPluginRaceCleanupDelays = longArrayOf(0L, 30L, 80L, 120L, 750L, 2_500L, 5_000L, 10_000L)
        private val previewHandler = Handler(Looper.getMainLooper())
        private var previewPlayer: MediaPlayer? = null
        private var previewStopRunnable: Runnable? = null
        @Volatile
        private var activeReminderId: Int? = null

        fun notificationIdForReminder(id: Int): Int {
            return id or Int.MIN_VALUE
        }

        fun cancelNotification(context: Context, id: Int) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationIdForReminder(id))
        }

        fun cancelFlutterPluginNotification(context: Context, id: Int) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(id)
        }

        fun cancelFlutterPluginNotificationSoon(context: Context, id: Int) {
            val appContext = context.applicationContext
            val mainHandler = Handler(Looper.getMainLooper())
            val pluginIds = flutterPluginNotificationIds(id)
            flutterPluginRaceCleanupDelays.forEach { delayMillis ->
                mainHandler.postDelayed({
                    pluginIds.forEach { pluginId ->
                        cancelFlutterPluginNotification(appContext, pluginId)
                    }
                }, delayMillis)
            }
        }

        private fun flutterPluginNotificationIds(id: Int): Set<Int> {
            val ids = mutableSetOf(id)
            for (weekday in 1..7) {
                ids.add(subId(id, weekday))
                ids.add(legacySubId(id, weekday))
            }
            return ids
        }

        private fun subId(base: Int, weekday: Int): Int {
            var hash = 0x811c9dc5.toInt()
            val key = "$base:$weekday"
            key.forEach { ch ->
                hash = hash xor ch.code
                hash = (hash * 0x01000193) and 0x7fffffff
            }
            return if (hash == 0) weekday else hash
        }

        private fun legacySubId(base: Int, weekday: Int): Int {
            return base * 10 + weekday
        }

        fun stopActive(context: Context) {
            stopPreview()
            context.stopService(Intent(context, ReminderRingtoneService::class.java))
        }

        fun stopIfActive(context: Context, id: Int) {
            if (activeReminderId == id) stopActive(context)
        }

        fun setVolumePercent(context: Context, value: Int) {
            val normalized = value.coerceIn(40, 80)
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putInt(volumeKey, normalized)
                .apply()
        }

        fun setSoundName(context: Context, value: String) {
            val normalized = normalizeSoundName(value)
            val editor = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                .putString(soundKey, normalized)
            if (normalized == "alarm") {
                editor.putBoolean(legacyAlarmMigrationKey, true)
            }
            editor.apply()
        }

        @Synchronized
        fun previewCurrentSound(context: Context, durationMillis: Long): Map<String, Any> {
            val appContext = context.applicationContext
            stopPreview()

            val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val alarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            if (alarmVolume <= 0) {
                return previewResult(
                    started = false,
                    reason = "alarm_volume_zero",
                    message = "系统闹钟音量为 0，请调高闹钟/铃声音量后再试听。",
                )
            }

            val soundName = selectedSoundName(appContext)
            val resId = soundResId(appContext)
            val afd = runCatching { appContext.resources.openRawResourceFd(resId) }.getOrNull()
                ?: return previewResult(
                    started = false,
                    reason = "audio_resource_missing",
                    message = "内置铃声资源不存在：duoyi_$soundName。",
                )
            if (afd.length <= minAudibleRawBytes) {
                afd.close()
                return previewResult(
                    started = false,
                    reason = "audio_resource_invalid",
                    message = "内置铃声资源不可播放或文件过小：duoyi_$soundName。",
                )
            }

            val volume = volumePercent(appContext) / 100f
            val player = MediaPlayer()
            return try {
                player.setAudioAttributes(previewAudioAttributes())
                player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                player.isLooping = false
                player.setVolume(volume, volume)
                player.setOnCompletionListener { completedPlayer ->
                    synchronized(ReminderRingtoneService::class.java) {
                        if (previewPlayer === completedPlayer) {
                            stopPreview()
                        }
                    }
                }
                player.setOnErrorListener { errorPlayer, _, _ ->
                    synchronized(ReminderRingtoneService::class.java) {
                        if (previewPlayer === errorPlayer) {
                            stopPreview()
                        } else {
                            runCatching { errorPlayer.release() }
                        }
                    }
                    true
                }
                player.prepare()
                previewPlayer = player
                player.start()
                val safeDuration = durationMillis.coerceIn(500L, 30_000L)
                previewStopRunnable = Runnable {
                    synchronized(ReminderRingtoneService::class.java) {
                        if (previewPlayer === player) stopPreview()
                    }
                }.also { previewHandler.postDelayed(it, safeDuration) }
                previewResult(
                    started = true,
                    reason = "started",
                    message = "正在试听当前提醒铃声。",
                )
            } catch (error: Exception) {
                runCatching { player.release() }
                previewPlayer = null
                previewResult(
                    started = false,
                    reason = "player_init_failed",
                    message = "播放器初始化失败：${error.message ?: "未知错误"}。",
                )
            } finally {
                afd.close()
            }
        }

        @Synchronized
        fun stopPreview() {
            previewStopRunnable?.let { previewHandler.removeCallbacks(it) }
            previewStopRunnable = null
            previewPlayer?.run {
                runCatching { stop() }
                runCatching { release() }
            }
            previewPlayer = null
        }

        private fun selectedSoundName(context: Context): String {
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

	        private fun volumePercent(context: Context): Int {
	            return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
	                .getInt(volumeKey, 60)
	                .coerceIn(40, 80)
	        }

	        private fun previewAudioAttributes(): AudioAttributes {
	            return AudioAttributes.Builder()
	                .setUsage(AudioAttributes.USAGE_ALARM)
	                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
	                .build()
	        }

	        private fun previewResult(
	            started: Boolean,
	            reason: String,
	            message: String,
	        ): Map<String, Any> {
	            return mapOf(
	                "started" to started,
	                "reason" to reason,
	                "message" to message,
	            )
	        }

        private fun soundResId(context: Context): Int {
            return when (selectedSoundName(context)) {
                "soft" -> R.raw.duoyi_soft
                "forest" -> R.raw.duoyi_forest
                "silver" -> R.raw.duoyi_silver
                "paper" -> R.raw.duoyi_paper
                "stream" -> R.raw.duoyi_stream
                "star" -> R.raw.duoyi_star
                "marimba" -> R.raw.duoyi_marimba
                "lull" -> R.raw.duoyi_lull
                "glass" -> R.raw.duoyi_glass
                "bamboo" -> R.raw.duoyi_bamboo
                "dawn" -> R.raw.duoyi_dawn
                "wood" -> R.raw.duoyi_wood
                "water" -> R.raw.duoyi_water
                "harp" -> R.raw.duoyi_harp
                "mist" -> R.raw.duoyi_mist
                "pebble" -> R.raw.duoyi_pebble
                "tide" -> R.raw.duoyi_tide
                "chime" -> R.raw.duoyi_chime
                "bell" -> R.raw.duoyi_bell
                "morning" -> R.raw.duoyi_morning
                "pearl" -> R.raw.duoyi_pearl
                "cedar" -> R.raw.duoyi_cedar
                "moon" -> R.raw.duoyi_moon
                "cloud" -> R.raw.duoyi_cloud
                "sakura" -> R.raw.duoyi_sakura
                "beep" -> R.raw.duoyi_beep
                "classic" -> R.raw.duoyi_classic
                "alarm" -> R.raw.duoyi_alarm
                else -> R.raw.duoyi_soft
            }
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

        fun intent(
            context: Context,
            id: Int,
            title: String,
            body: String,
            payload: String?,
            fullScreen: Boolean = false,
            vibrate: Boolean = true,
            snoozeMinutes: Int = 0,
            repeatCount: Int = 0,
            rootId: Int = id,
        ): Intent {
            return Intent(context, ReminderRingtoneService::class.java)
                .putExtra("id", id)
                .putExtra("rootId", rootId)
                .putExtra("title", title)
                .putExtra("body", body)
                .putExtra("payload", payload)
                .putExtra("fullScreen", fullScreen)
                .putExtra("vibrate", vibrate)
                .putExtra("snoozeMinutes", snoozeMinutes.coerceIn(0, 120))
                .putExtra("repeatCount", repeatCount.coerceIn(0, 10))
                .putExtra("repeatRemaining", repeatCount.coerceIn(0, 10))
        }
    }
}
