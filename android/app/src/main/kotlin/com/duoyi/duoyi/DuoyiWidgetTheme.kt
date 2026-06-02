package com.duoyi.duoyi

import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews

data class DuoyiWidgetThemePalette(
    val primary: Int,
    val background: Int,
    val surface: Int,
    val navBackground: Int,
    val text: Int,
    val mutedText: Int,
    val onPrimary: Int,
)

object DuoyiWidgetTheme {
    private const val defaultPrimary = "#FFFF6B6B"
    private const val defaultBackground = "#FFFFFFFF"
    private const val defaultSurface = "#FFFFFFFF"
    private const val defaultNavBackground = "#FFFFF6F2"
    private const val defaultText = "#FF333333"
    private const val defaultMutedText = "#FF666666"
    private const val defaultOnPrimary = "#FFFFFFFF"

    fun read(prefs: SharedPreferences): DuoyiWidgetThemePalette {
        return DuoyiWidgetThemePalette(
            primary = readColor(prefs, "widget_theme_primary", defaultPrimary),
            background = readColor(prefs, "widget_theme_background", defaultBackground),
            surface = readColor(prefs, "widget_theme_surface", defaultSurface),
            navBackground = readColor(prefs, "widget_theme_nav_background", defaultNavBackground),
            text = readColor(prefs, "widget_theme_text", defaultText),
            mutedText = readColor(prefs, "widget_theme_muted_text", defaultMutedText),
            onPrimary = readColor(prefs, "widget_theme_on_primary", defaultOnPrimary),
        )
    }

    fun applyContainer(
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        navId: Int = 0,
    ) {
        val theme = read(prefs)
        tintRoundedBackground(views, rootId, theme.background)
        if (navId != 0) {
            tintRoundedBackground(views, navId, theme.navBackground)
        }
    }

    fun applyButtonSurfaces(
        views: RemoteViews,
        prefs: SharedPreferences,
        primaryIds: IntArray = intArrayOf(),
        secondaryIds: IntArray = intArrayOf(),
    ) {
        val theme = read(prefs)
        primaryIds.forEach { tintRoundedBackground(views, it, theme.primary) }
        secondaryIds.forEach { tintRoundedBackground(views, it, theme.navBackground) }
    }

    fun applyTextColors(
        views: RemoteViews,
        prefs: SharedPreferences,
        primaryIds: IntArray = intArrayOf(),
        bodyIds: IntArray = intArrayOf(),
        mutedIds: IntArray = intArrayOf(),
        onPrimaryIds: IntArray = intArrayOf(),
    ) {
        val theme = read(prefs)
        primaryIds.forEach { views.setTextColor(it, theme.primary) }
        bodyIds.forEach { views.setTextColor(it, theme.text) }
        mutedIds.forEach { views.setTextColor(it, theme.mutedText) }
        onPrimaryIds.forEach { views.setTextColor(it, theme.onPrimary) }
    }

    private fun readColor(
        prefs: SharedPreferences,
        key: String,
        fallback: String,
    ): Int {
        val raw = prefs.getString(key, null)?.trim()
        return try {
            Color.parseColor(if (raw.isNullOrEmpty()) fallback else raw)
        } catch (_: IllegalArgumentException) {
            Color.parseColor(fallback)
        }
    }

    private fun tintRoundedBackground(views: RemoteViews, viewId: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            views.setColorStateList(viewId, "setBackgroundTintList", ColorStateList.valueOf(color))
        } else {
            views.setInt(viewId, "setBackgroundColor", color)
        }
    }
}
