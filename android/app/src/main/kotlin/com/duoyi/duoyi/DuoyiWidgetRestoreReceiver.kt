package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class DuoyiWidgetRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in supportedActions) return
        val appContext = context.applicationContext
        val restored = DuoyiWidgetProviderRegistry.restoreEnabledProvidersForExistingWidgets(appContext)
        val updated = DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(appContext)
        Log.i(tag, "restore action=$action restoredProviders=$restored updatedWidgets=$updated")
    }

    companion object {
        private const val tag = "DuoyiWidgetRestore"
        private val supportedActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
    }
}
