package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class ReminderRingtoneBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                ReminderRingtoneScheduler.cleanupFlutterPluginOwners(context)
                val deliverExpired = intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
                ReminderRingtoneScheduler.restoreAll(context, deliverExpired = deliverExpired)
                scheduleFlutterPluginOwnerCleanup(context)
            }
        }
    }

    private fun scheduleFlutterPluginOwnerCleanup(context: Context) {
        val appContext = context.applicationContext
        val handler = Handler(Looper.getMainLooper())
        for (delayMillis in flutterPluginBootCleanupDelays) {
            handler.postDelayed({
                ReminderRingtoneScheduler.cleanupFlutterPluginOwners(appContext)
            }, delayMillis)
        }
    }

    companion object {
        private val flutterPluginBootCleanupDelays = longArrayOf(
            500L,
            2_500L,
            10_000L,
            30_000L,
            60_000L,
        )
    }
}
