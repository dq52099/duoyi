package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Private alarm entry point; no incoming data is used to choose content or targets. */
class DuoyiWidgetDayBoundaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DuoyiWidgetDayBoundaryScheduler.action) return
        val appContext = context.applicationContext
        DuoyiWidgetDayBoundaryScheduler.invalidate()
        try {
            DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(appContext)
        } catch (error: RuntimeException) {
            Log.w("DuoyiWidgetRefresh", "boundary refresh dispatch failed", error)
        } finally {
            // Recompute from delivery time, including delayed alarms and zone changes.
            DuoyiWidgetDayBoundaryScheduler.reconcile(appContext)
        }
    }
}
