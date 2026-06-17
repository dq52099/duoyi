package com.duoyi.duoyi

import android.app.Activity
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
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ReminderFullScreenActivity : Activity() {
    private var clockView: TextView? = null
    private var dateView: TextView? = null
    private val clockHandler = Handler(Looper.getMainLooper())
    // 时钟每秒刷新一次，格式化器复用以避免每次 tick 重新分配。
    private val clockFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
    private val dateFormat = SimpleDateFormat("M月d日 EEEE", Locale.getDefault())
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
            getSystemService(KeyguardManager::class.java)?.requestDismissKeyguard(this, null)
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
        val reminderTitle = intent.getStringExtra(extraTitle)
            ?.takeIf { it.isNotBlank() }
            ?: "多仪提醒"
        val reminderBody = intent.getStringExtra(extraBody)
            ?.takeIf { it.isNotBlank() }
            ?: "提醒时间到了"

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(40), dp(28), dp(40))
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.rgb(26, 32, 44), Color.rgb(15, 23, 42)),
            )
        }
        // 锁屏闹钟样式：顶部大号实时时钟 + 日期，强化“闹钟”语义与即时感。
        val clock = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 64f
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            gravity = Gravity.CENTER
            letterSpacing = 0.02f
        }
        clockView = clock
        val date = TextView(this).apply {
            setTextColor(Color.rgb(148, 163, 184))
            textSize = 15f
            gravity = Gravity.CENTER
        }
        dateView = date
        updateClock()

        val badge = TextView(this).apply {
            text = "🔔  闹钟提醒"
            setTextColor(Color.rgb(56, 189, 164))
            textSize = 14f
            gravity = Gravity.CENTER
        }
        val title = TextView(this).apply {
            text = reminderTitle
            setTextColor(Color.WHITE)
            textSize = 26f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 3
            ellipsize = TextUtils.TruncateAt.END
        }
        val body = TextView(this).apply {
            text = reminderBody
            setTextColor(Color.rgb(226, 232, 240))
            textSize = 17f
            gravity = Gravity.CENTER
            maxLines = 4
            ellipsize = TextUtils.TruncateAt.END
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val stopButton = actionButton("停止响铃", filled = false).apply {
            setOnClickListener { stopRingtoneAndFinish() }
        }
        val openButton = actionButton("打开多仪", filled = true).apply {
            setOnClickListener { openMainActivityAndFinish() }
        }

        root.addView(clock, matchWidth(height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(date, matchWidth(topMargin = dp(4), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(badge, matchWidth(topMargin = dp(28), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(title, matchWidth(topMargin = dp(12), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(body, matchWidth(topMargin = dp(12), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        actions.addView(stopButton, weightedButton(endMargin = dp(10)))
        actions.addView(openButton, weightedButton(startMargin = dp(10)))
        root.addView(actions, matchWidth(topMargin = dp(40), height = ViewGroup.LayoutParams.WRAP_CONTENT))
        setContentView(root)
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
        val payload = intent.getStringExtra(extraPayload)
        startActivity(mainActivityIntent(this, payload, stopRingtone = true))
        finish()
    }

    private fun actionButton(label: String, filled: Boolean): Button {
        val backgroundColor = if (filled) Color.rgb(56, 189, 164) else Color.TRANSPARENT
        val strokeColor = if (filled) backgroundColor else Color.rgb(148, 163, 184)
        val textColor = if (filled) Color.rgb(15, 23, 42) else Color.WHITE
        return Button(this).apply {
            text = label
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(textColor)
            setAllCaps(false)
            minHeight = dp(52)
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
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

    private fun weightedButton(
        startMargin: Int = 0,
        endMargin: Int = 0,
    ): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = startMargin
            marginEnd = endMargin
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

        fun intent(
            context: Context,
            id: Int,
            rootId: Int,
            title: String,
            body: String,
            payload: String?,
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
        }

        fun launch(
            context: Context,
            id: Int,
            rootId: Int,
            title: String,
            body: String,
            payload: String?,
        ): Boolean {
            return runCatching {
                context.startActivity(intent(context, id, rootId, title, body, payload))
            }.isSuccess
        }

        fun mainActivityIntent(
            context: Context,
            payload: String?,
            stopRingtone: Boolean,
        ): Intent {
            val normalizedPayload = payload?.takeIf { it.isNotBlank() }
            val intent = if (normalizedPayload != null) {
                Intent(Intent.ACTION_VIEW, Uri.parse(normalizedPayload), context, MainActivity::class.java)
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
