package com.duoyi.duoyi

import android.app.Activity
import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReminderFullScreenActivity : Activity() {
    private var clockView: TextView? = null
    private var dateView: TextView? = null
    private val clockHandler = Handler(Looper.getMainLooper())
    // 时钟每秒刷新一次，格式化器复用以避免每次 tick 重新分配。
    private var clockFormat = SimpleDateFormat("HH:mm", Locale.SIMPLIFIED_CHINESE)
    private var dateFormat = SimpleDateFormat("M月d日 EEEE", Locale.SIMPLIFIED_CHINESE)
    private val clockTicker = object : Runnable {
        override fun run() {
            updateClock()
            clockHandler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureAlarmWindow()
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        configureAlarmWindow()
        render()
    }

    override fun onResume() {
        super.onResume()
        configureAlarmWindow()
        clockHandler.removeCallbacks(clockTicker)
        clockHandler.post(clockTicker)
    }

    override fun onPause() {
        super.onPause()
        clockHandler.removeCallbacks(clockTicker)
    }

    override fun onDestroy() {
        clockHandler.removeCallbacks(clockTicker)
        super.onDestroy()
    }

    private fun configureAlarmWindow() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            runCatching {
                getSystemService(KeyguardManager::class.java)?.requestDismissKeyguard(this, null)
            }
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }
    }

    private fun updateClock() {
        val now = Date()
        clockView?.text = clockFormat.format(now)
        dateView?.text = dateFormat.format(now)
    }

    private fun render() {
        val copy = ReminderNativeCopy(intent.getStringExtra(extraLocale))
        clockFormat = SimpleDateFormat("HH:mm", copy.javaLocale)
        dateFormat = SimpleDateFormat(copy.datePattern, copy.javaLocale)
        val reminderTitle = intent.getStringExtra(extraTitle)
            ?.takeIf { it.isNotBlank() }
            ?: copy.reminderTitle
        val reminderBody = intent.getStringExtra(extraBody)
            ?.takeIf { it.isNotBlank() }
            ?: copy.reminderBody

        val backgroundDrawable = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.rgb(18, 24, 38), Color.rgb(8, 15, 30)),
        )
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            background = backgroundDrawable
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(40), dp(28), dp(40))
        }
        // 锁屏闹钟样式：顶部大号实时时钟 + 日期，强化“闹钟”语义与即时感。
        val clock = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 64f
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            gravity = Gravity.CENTER
            letterSpacing = 0f
        }
        clockView = clock
        val date = TextView(this).apply {
            setTextColor(Color.rgb(203, 213, 225))
            textSize = 15f
            gravity = Gravity.CENTER
        }
        dateView = date
        updateClock()

        val badge = TextView(this).apply {
            text = copy.ringing
            setTextColor(Color.rgb(94, 234, 212))
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            letterSpacing = 0.08f
        }
        val title = TextView(this).apply {
            text = reminderTitle
            setTextColor(Color.WHITE)
            textSize = 28f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 3
            ellipsize = TextUtils.TruncateAt.END
        }
        val bodyLabel = TextView(this).apply {
            text = copy.bodyLabel
            setTextColor(Color.rgb(203, 213, 225))
            textSize = 13f
            gravity = Gravity.CENTER
        }
        val body = TextView(this).apply {
            text = reminderBody
            setTextColor(Color.rgb(241, 245, 249))
            textSize = 18f
            gravity = Gravity.CENTER
            maxLines = 5
            ellipsize = TextUtils.TruncateAt.END
            setLineSpacing(dp(2).toFloat(), 1.1f)
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        val openButton = actionButton(copy.openDetails, filled = true).apply {
            setOnClickListener { openMainActivityAndFinish() }
        }
        val snoozeButton = actionButton(
            copy.snooze(defaultSnoozeMinutes),
            filled = false,
            emphasizedSecondary = true,
        ).apply {
            setOnClickListener { snoozeAndFinish(defaultSnoozeMinutes) }
        }
        val stopButton = actionButton(copy.stopAlarm, filled = false).apply {
            setOnClickListener { stopRingtoneAndFinish() }
        }

        root.addView(clock, matchWidth(height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(date, matchWidth(topMargin = dp(4), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(badge, matchWidth(topMargin = dp(28), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(title, matchWidth(topMargin = dp(12), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(bodyLabel, matchWidth(topMargin = dp(24), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(body, matchWidth(topMargin = dp(8), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        actions.addView(openButton, matchWidth(height = ViewGroup.LayoutParams.WRAP_CONTENT))
        actions.addView(snoozeButton, matchWidth(topMargin = dp(12), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        actions.addView(stopButton, matchWidth(topMargin = dp(12), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(actions, matchWidth(topMargin = dp(36), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        scroll.addView(
            root,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        setContentView(scroll)
    }

    private fun snoozeAndFinish(delayMinutes: Int = defaultSnoozeMinutes) {
        val copy = ReminderNativeCopy(intent.getStringExtra(extraLocale))
        val id = intent.getIntExtra(extraReminderId, 0)
        val rawRootId = intent.getIntExtra(extraRootId, id)
        val effectiveRootId = when {
            rawRootId != 0 -> rawRootId
            id != 0 -> id
            else -> defaultSnoozeRootId
        }
        val title = intent.getStringExtra(extraTitle)
            ?.takeIf { it.isNotBlank() }
            ?: copy.reminderTitle
        val body = intent.getStringExtra(extraBody)
            ?.takeIf { it.isNotBlank() }
            ?: copy.reminderBody
        val payload = intent.getStringExtra(extraPayload)
        val storedMetadata = if (id != 0) ReminderRingtoneScheduler.readScheduleMetadata(this, id) else null
        val vibrate = if (intent.hasExtra(extraVibrate)) {
            intent.getBooleanExtra(extraVibrate, true)
        } else {
            storedMetadata?.vibrate ?: true
        }
        val configuredSnoozeMinutes = if (intent.hasExtra(extraSnoozeMinutes)) {
            intent.getIntExtra(extraSnoozeMinutes, delayMinutes)
        } else {
            storedMetadata?.snoozeMinutes ?: delayMinutes
        }.let { ReminderRingtoneScheduler.normalizeSnoozeMinutes(it, delayMinutes) }
        val repeatCount = if (intent.hasExtra(extraRepeatCount)) {
            intent.getIntExtra(extraRepeatCount, 0)
        } else {
            storedMetadata?.repeatCount ?: 0
        }.coerceIn(0, 10)

        // Stop active audio/notification before scheduling snooze so actionStop cannot cancel follow-ups.
        ReminderRingtoneService.stopActive(this)
        if (id != 0) {
            ReminderRingtoneService.cancelNotification(this, id)
        }
        if (rawRootId != 0 && rawRootId != id) {
            ReminderRingtoneService.cancelNotification(this, rawRootId)
        }

        val triggerAtMillis = ReminderRingtoneScheduler.computeSnoozeTriggerAtMillis(
            System.currentTimeMillis(),
            delayMinutes,
        )
        ReminderRingtoneScheduler.scheduleFollowUpOnce(
            context = this,
            rootId = effectiveRootId,
            followUpKind = ReminderRingtoneScheduler.FOLLOW_UP_SNOOZE,
            title = title,
            body = body,
            triggerAtMillis = triggerAtMillis,
            payload = payload,
            fullScreen = true,
            vibrate = vibrate,
            snoozeMinutes = configuredSnoozeMinutes,
            repeatCount = repeatCount,
            locale = copy.locale,
        )
        finish()
    }

    private fun stopRingtoneAndFinish() {
        val id = intent.getIntExtra(extraReminderId, 0)
        val rootId = intent.getIntExtra(extraRootId, id)
        if (id != 0) {
            runCatching { startService(ReminderRingtoneService.stopServiceIntent(this, id, rootId)) }
            ReminderRingtoneService.cancelNotification(this, id)
            if (rootId != id) ReminderRingtoneService.cancelNotification(this, rootId)
        } else {
            ReminderRingtoneScheduler.stopActiveRingtone(this)
        }
        finish()
    }

    private fun openMainActivityAndFinish() {
        val id = intent.getIntExtra(extraReminderId, 0)
        val rootId = intent.getIntExtra(extraRootId, id)
        val payload = intent.getStringExtra(extraPayload)
        ReminderRingtoneService.stopActive(this)
        if (id != 0) ReminderRingtoneService.cancelNotification(this, id)
        if (rootId != 0 && rootId != id) ReminderRingtoneService.cancelNotification(this, rootId)
        runCatching {
            startActivity(mainActivityIntent(this, payload, stopRingtone = true))
        }.onFailure {
            runCatching {
                startActivity(mainActivityIntent(this, null, stopRingtone = true))
            }
        }
        finish()
    }

    private fun actionButton(
        label: String,
        filled: Boolean,
        emphasizedSecondary: Boolean = false,
    ): Button {
        val backgroundColor = when {
            filled -> Color.rgb(56, 189, 164)
            emphasizedSecondary -> Color.rgb(30, 41, 59)
            else -> Color.TRANSPARENT
        }
        val strokeColor = when {
            filled -> backgroundColor
            emphasizedSecondary -> Color.rgb(94, 234, 212)
            else -> Color.rgb(148, 163, 184)
        }
        val textColor = when {
            filled -> Color.rgb(15, 23, 42)
            else -> Color.WHITE
        }
        return Button(this).apply {
            text = label
            contentDescription = label
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(textColor)
            setAllCaps(false)
            isFocusable = true
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            minHeight = dp(52)
            setPadding(dp(20), dp(12), dp(20), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(backgroundColor)
                setStroke(dp(1), strokeColor)
            }
        }
    }

    private fun matchWidth(
        topMargin: Int = 0,
        height: Int,
    ): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            height,
        ).apply {
            this.topMargin = topMargin
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    companion object {
        private const val extraReminderId = "duoyi.extra.REMINDER_ID"
        private const val extraRootId = "duoyi.extra.REMINDER_ROOT_ID"
        private const val extraTitle = "duoyi.extra.REMINDER_TITLE"
        private const val extraBody = "duoyi.extra.REMINDER_BODY"
        private const val extraPayload = "duoyi.extra.REMINDER_PAYLOAD"
        private const val extraLocale = "duoyi.extra.REMINDER_LOCALE"
        internal const val extraVibrate = "duoyi.extra.REMINDER_VIBRATE"
        internal const val extraSnoozeMinutes = "duoyi.extra.REMINDER_SNOOZE_MINUTES"
        internal const val extraRepeatCount = "duoyi.extra.REMINDER_REPEAT_COUNT"
        private const val defaultSnoozeMinutes = ReminderRingtoneScheduler.defaultSnoozeMinutes
        private const val defaultSnoozeRootId = 919010

        internal fun isDirectLaunchAllowed(
            sdkInt: Int,
            isActivityContext: Boolean,
            isAppInForeground: Boolean,
            canDrawOverlays: Boolean,
        ): Boolean {
            if (sdkInt < Build.VERSION_CODES.Q) return true
            if (isActivityContext) return true
            if (isAppInForeground) return true
            if (canDrawOverlays) return true
            return false
        }

        fun canDirectLaunchFromBackground(context: Context): Boolean {
            val sdkInt = Build.VERSION.SDK_INT
            val isActivityContext = context is Activity
            val canDrawOverlays = sdkInt >= Build.VERSION_CODES.M &&
                runCatching { Settings.canDrawOverlays(context) }.getOrDefault(false)
            val isForeground = runCatching {
                val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    ?: return@runCatching false
                val myPid = Process.myPid()
                activityManager.runningAppProcesses?.any { proc ->
                    proc.pid == myPid &&
                        proc.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                } == true
            }.getOrDefault(false)
            return isDirectLaunchAllowed(sdkInt, isActivityContext, isForeground, canDrawOverlays)
        }

        fun intent(
            context: Context,
            id: Int,
            rootId: Int,
            title: String,
            body: String,
            payload: String?,
            locale: String = "zh",
        ): Intent {
            return Intent(context, ReminderFullScreenActivity::class.java)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                .putExtra(extraReminderId, id)
                .putExtra(extraRootId, rootId)
                .putExtra(extraTitle, title)
                .putExtra(extraBody, body)
                .putExtra(extraPayload, payload)
                .putExtra(extraLocale, ReminderNativeCopy(locale).locale)
        }

        fun launch(
            context: Context,
            id: Int,
            rootId: Int,
            title: String,
            body: String,
            payload: String?,
            locale: String = "zh",
        ): Boolean {
            if (!canDirectLaunchFromBackground(context)) {
                return true
            }
            return runCatching {
                context.startActivity(intent(context, id, rootId, title, body, payload, locale))
                true
            }.getOrDefault(false)
        }

        fun mainActivityIntent(
            context: Context,
            payload: String?,
            stopRingtone: Boolean,
        ): Intent {
            val normalizedPayload = payload?.takeIf { it.isNotBlank() }
            val parsedUri = normalizedPayload?.let { runCatching { Uri.parse(it) }.getOrNull() }
            val intent = if (parsedUri != null) {
                Intent(Intent.ACTION_VIEW, parsedUri, context, MainActivity::class.java)
            } else {
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent(context, MainActivity::class.java)
            }
            return intent
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(ReminderRingtoneService.extraStopRingtone, stopRingtone)
        }
    }
}
