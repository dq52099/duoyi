package com.duoyi.duoyi

import android.content.SharedPreferences
import android.view.View

object DuoyiWidgetDisplayMode {
    private const val KEY = "widget_display_mode"
    private const val COMPACT = "compact"
    private const val DETAILED = "detailed"

    fun isCompact(prefs: SharedPreferences): Boolean {
        return prefs.getString(KEY, "standard") == COMPACT
    }

    fun isDetailed(prefs: SharedPreferences): Boolean {
        return prefs.getString(KEY, "standard") == DETAILED
    }

    fun standardOrDetailedVisibility(prefs: SharedPreferences): Int {
        return if (isCompact(prefs)) View.GONE else View.VISIBLE
    }

    fun detailedVisibility(prefs: SharedPreferences): Int {
        return if (isDetailed(prefs)) View.VISIBLE else View.GONE
    }
}
