package com.duoyi.duoyi

import android.content.SharedPreferences
import android.view.View

object DuoyiWidgetDisplayMode {
    private const val KEY = "widget_display_mode"
    private const val PER_WIDGET_KEY_PREFIX = "widget_display_mode_"
    private const val COMPACT = "compact"
    private const val DETAILED = "detailed"
    private const val STANDARD = "standard"

    fun isCompact(prefs: SharedPreferences, appWidgetId: Int? = null): Boolean {
        return modeFor(prefs, appWidgetId) == COMPACT
    }

    fun isDetailed(prefs: SharedPreferences, appWidgetId: Int? = null): Boolean {
        return modeFor(prefs, appWidgetId) == DETAILED
    }

    fun standardOrDetailedVisibility(prefs: SharedPreferences, appWidgetId: Int? = null): Int {
        return if (isCompact(prefs, appWidgetId)) View.GONE else View.VISIBLE
    }

    fun bottomNavVisibility(prefs: SharedPreferences, appWidgetId: Int? = null): Int {
        return standardOrDetailedVisibility(prefs, appWidgetId)
    }

    fun detailedVisibility(prefs: SharedPreferences, appWidgetId: Int? = null): Int {
        return if (isDetailed(prefs, appWidgetId)) View.VISIBLE else View.GONE
    }

    fun saveForWidget(prefs: SharedPreferences, appWidgetId: Int, mode: String?) {
        val normalized = normalize(mode) ?: return
        prefs.edit()
            .putString(perWidgetKey(appWidgetId), normalized)
            .apply()
    }

    fun saveForWidgetIfMissing(prefs: SharedPreferences, appWidgetId: Int, mode: String?) {
        if (appWidgetId <= 0 || prefs.contains(perWidgetKey(appWidgetId))) return
        val normalized = normalize(mode) ?: return
        prefs.edit()
            .putString(perWidgetKey(appWidgetId), normalized)
            .apply()
    }

    fun clearForWidget(prefs: SharedPreferences, appWidgetId: Int) {
        prefs.edit().remove(perWidgetKey(appWidgetId)).apply()
    }

    private fun modeFor(prefs: SharedPreferences, appWidgetId: Int?): String {
        val globalMode = normalize(prefs.getString(KEY, null))
        val instanceMode = appWidgetId
            ?.takeIf { it > 0 }
            ?.let { prefs.getString(perWidgetKey(it), null) }
        return normalize(instanceMode)
            ?: globalMode
            ?: STANDARD
    }

    private fun normalize(mode: String?): String? {
        return when (mode) {
            COMPACT, STANDARD, DETAILED -> mode
            else -> null
        }
    }

    private fun perWidgetKey(appWidgetId: Int): String {
        return "$PER_WIDGET_KEY_PREFIX$appWidgetId"
    }
}
