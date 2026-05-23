package com.duoyi.duoyi

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

class DuoyiFocusBlockerAccessibilityService : AccessibilityService() {
    private var lastBouncePackage: String? = null
    private var lastBounceAt: Long = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event?.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            return
        }
        val blockedPackage = event?.packageName?.toString() ?: return
        if (blockedPackage == packageName) return
        if (!FocusBlockerStore.isBlocked(this, blockedPackage)) return
        if (isDuplicateBounce(blockedPackage)) return
        FocusBlockerStore.recordBlockedPackage(this, blockedPackage)
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("duoyi_focus_blocked_package", blockedPackage)
            .setData(
                Uri.Builder()
                    .scheme("duoyi")
                    .authority("tab")
                    .appendPath("focus")
                    .appendQueryParameter("blocked", blockedPackage)
                    .build(),
            )
        runCatching { startActivity(intent) }
    }

    override fun onInterrupt() = Unit

    private fun isDuplicateBounce(blockedPackage: String): Boolean {
        val now = SystemClock.elapsedRealtime()
        val duplicate = blockedPackage == lastBouncePackage &&
            now - lastBounceAt < bounceDebounceMillis
        lastBouncePackage = blockedPackage
        lastBounceAt = now
        return duplicate
    }

    companion object {
        private const val bounceDebounceMillis = 1500L
    }
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
