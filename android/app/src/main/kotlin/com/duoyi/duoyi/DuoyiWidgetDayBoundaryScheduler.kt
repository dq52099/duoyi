package com.duoyi.duoyi

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.time.ZoneId

/** One content-free, inexact wakeup shared by all installed widget families. */
object DuoyiWidgetDayBoundaryScheduler {
    const val action = "com.duoyi.duoyi.WIDGET_DAY_BOUNDARY"
    private const val requestCode = 14102
    private const val tag = "DuoyiWidgetRefresh"
    private val controller = DuoyiWidgetBoundaryController()

    fun isWidgetLifecycleAction(action: String?): Boolean = action in setOf(
        AppWidgetManager.ACTION_APPWIDGET_ENABLED,
        AppWidgetManager.ACTION_APPWIDGET_UPDATE,
        AppWidgetManager.ACTION_APPWIDGET_OPTIONS_CHANGED,
        AppWidgetManager.ACTION_APPWIDGET_RESTORED,
        AppWidgetManager.ACTION_APPWIDGET_DELETED,
        AppWidgetManager.ACTION_APPWIDGET_DISABLED,
    )

    @Synchronized
    fun invalidate() {
        controller.invalidate()
    }

    @Synchronized
    fun reconcile(context: Context, force: Boolean = false): DuoyiWidgetBoundaryResult? {
        val appContext = context.applicationContext
        return try {
            val count = DuoyiWidgetProviderRegistry.installedWidgetCount(appContext)
            val result = controller.reconcile(
                nowMillis = System.currentTimeMillis(),
                zone = ZoneId.systemDefault(),
                installedWidgetCount = count,
                alarm = AndroidAlarmPort(appContext),
                force = force,
            )
            if (result.outcome == DuoyiWidgetBoundaryOutcome.FAILED) {
                Log.w(tag, "boundary scheduling unavailable; retry on next lifecycle event")
            }
            result
        } catch (error: RuntimeException) {
            // Query failure is not proof that no widgets exist. Keep the old alarm.
            controller.invalidate()
            Log.w(tag, "boundary reconcile failed; retry on next lifecycle event", error)
            null
        }
    }

    private class AndroidAlarmPort(private val context: Context) : DuoyiWidgetBoundaryAlarmPort {
        private val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

        private fun pendingIntent(create: Boolean): PendingIntent? {
            val intent = Intent(context, DuoyiWidgetDayBoundaryReceiver::class.java).apply {
                action = DuoyiWidgetDayBoundaryScheduler.action
            }
            val mutability = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            val lookup = if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
            return PendingIntent.getBroadcast(context, requestCode, intent, lookup or mutability)
        }

        override fun schedule(atMillis: Long): Boolean {
            val alarmManager = manager ?: return false
            val pending = pendingIntent(create = true) ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, atMillis, pending)
            }
            return true
        }

        override fun cancel(): Boolean {
            val alarmManager = manager ?: return false
            val pending = pendingIntent(create = false) ?: return true
            alarmManager.cancel(pending)
            pending.cancel()
            return true
        }
    }
}
