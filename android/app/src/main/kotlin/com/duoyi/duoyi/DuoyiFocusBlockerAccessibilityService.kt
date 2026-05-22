package com.duoyi.duoyi

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

class DuoyiFocusBlockerAccessibilityService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event?.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            return
        }
        val blockedPackage = event?.packageName?.toString() ?: return
        if (blockedPackage == packageName) return
        if (!FocusBlockerStore.isBlocked(this, blockedPackage)) return
        FocusBlockerStore.recordBlockedPackage(this, blockedPackage)
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("duoyi_focus_blocked_package", blockedPackage)
            .setData(android.net.Uri.parse("duoyi://tab/focus?blocked=$blockedPackage"))
        startActivity(intent)
    }

    override fun onInterrupt() = Unit
}

object FocusBlockerStore {
    private const val prefsName = "duoyi_focus_blocker"
    private const val keyEnabled = "enabled"
    private const val keyPackages = "packages"
    private const val keyLastBlockedPackage = "last_blocked_package"
    private const val keyLastBlockedAt = "last_blocked_at"

    fun setConfig(context: Context, enabled: Boolean, packages: Set<String>) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(keyEnabled, enabled)
            .putStringSet(keyPackages, packages)
            .apply()
    }

    fun isConfigured(context: Context): Boolean {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        return prefs.getBoolean(keyEnabled, false) &&
            !prefs.getStringSet(keyPackages, emptySet()).isNullOrEmpty()
    }

    fun isBlocked(context: Context, packageName: String): Boolean {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(keyEnabled, false)) return false
        return prefs.getStringSet(keyPackages, emptySet())?.contains(packageName) == true
    }

    fun recordBlockedPackage(context: Context, packageName: String) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(keyLastBlockedPackage, packageName)
            .putLong(keyLastBlockedAt, System.currentTimeMillis())
            .apply()
    }

    fun lastBlockedPackage(context: Context): String? {
        return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(keyLastBlockedPackage, null)
    }

    fun lastBlockedAt(context: Context): Long {
        return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getLong(keyLastBlockedAt, 0L)
    }
}
