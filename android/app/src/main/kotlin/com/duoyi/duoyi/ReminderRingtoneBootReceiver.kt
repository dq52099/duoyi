package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class ReminderRingtoneBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            actionScheduleExactAlarmPermissionStateChanged,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                ReminderRingtoneScheduler.cleanupFlutterPluginOwners(context)
                val deliverExpired = intent.action != Intent.ACTION_MY_PACKAGE_REPLACED &&
                    shouldDeliverExpiredOnRestore(action)
                ReminderRingtoneScheduler.restoreAll(context, deliverExpired = deliverExpired)
                scheduleFlutterPluginOwnerCleanup(context)
            }
            ReminderRingtoneScheduler.actionCleanupFlutterPluginOwners -> {
                ReminderRingtoneScheduler.cleanupFlutterPluginOwners(context)
            }
            ReminderRingtoneScheduler.actionCleanupFlutterPluginNotification -> {
                val targetId = intent.getIntExtra(ReminderRingtoneScheduler.extraCleanupNotificationId, 0)
                if (targetId != 0) {
                    ReminderRingtoneService.cancelFlutterPluginNotificationTree(context, targetId)
                }
            }
        }
    }

    private fun scheduleFlutterPluginOwnerCleanup(context: Context) {
        val appContext = context.applicationContext
        val handler = Handler(Looper.getMainLooper())
        flutterPluginBootCleanupDelays.forEachIndexed { index, delayMillis ->
            if (delayMillis <= maxInProcessCleanupDelayMillis) {
                handler.postDelayed({
                    ReminderRingtoneScheduler.cleanupFlutterPluginOwners(appContext)
                }, delayMillis)
            } else {
                ReminderRingtoneScheduler.scheduleBootCleanupAlarm(appContext, index, delayMillis)
            }
        }
    }

    companion object {
        internal const val actionScheduleExactAlarmPermissionStateChanged =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
        private const val maxInProcessCleanupDelayMillis = 2_500L
        private val flutterPluginBootCleanupDelays = longArrayOf(
            500L,
            2_500L,
            10_000L,
            30_000L,
            60_000L,
        )

        internal fun isSupportedRestoreAction(action: String?): Boolean {
            return when (action) {
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_TIMEZONE_CHANGED,
                Intent.ACTION_TIME_CHANGED,
                "android.intent.action.TIME_SET",
                actionScheduleExactAlarmPermissionStateChanged,
                "android.intent.action.QUICKBOOT_POWERON",
                "com.htc.intent.action.QUICKBOOT_POWERON" -> true
                else -> false
            }
        }

        internal fun shouldDeliverExpiredOnRestore(action: String?): Boolean {
            return action != Intent.ACTION_MY_PACKAGE_REPLACED &&
                action != actionScheduleExactAlarmPermissionStateChanged
        }

        internal fun usesAlarmCleanupForDelay(delayMillis: Long): Boolean {
            return delayMillis > maxInProcessCleanupDelayMillis
        }
    }
}
