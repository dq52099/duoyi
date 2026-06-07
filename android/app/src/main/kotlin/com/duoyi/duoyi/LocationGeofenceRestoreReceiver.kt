package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class LocationGeofenceRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                LocationGeofenceScheduler.restoreRemembered(context.applicationContext)
            }
        }
    }
}
