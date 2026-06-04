package com.duoyi.duoyi

import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.view.View
import android.widget.RemoteViews

data class DuoyiWidgetThemePalette(
    val brandId: String,
    val cardSkinId: String,
    val dark: Boolean,
    val primary: Int,
    val background: Int,
    val surface: Int,
    val navBackground: Int,
    val border: Int,
    val text: Int,
    val mutedText: Int,
    val onPrimary: Int,
    val accentStart: Int,
    val accentEnd: Int,
    val backgroundAssetKey: String,
    val cornerRadiusDp: Int,
    val controlRadiusDp: Int,
    val borderWidthDp: Int,
)

object DuoyiWidgetTheme {
    private const val defaultPrimary = "#FFFF6B6B"
    private const val defaultBackground = "#FFFFFFFF"
    private const val defaultSurface = "#FFFFFFFF"
    private const val defaultNavBackground = "#FFFFF6F2"
    private const val defaultBorder = "#22FF6B6B"
    private const val defaultText = "#FF333333"
    private const val defaultMutedText = "#FF666666"
    private const val defaultOnPrimary = "#FFFFFFFF"
    private const val defaultAccentStart = "#FFFF6B6B"
    private const val defaultAccentEnd = "#FFFFB088"

    fun read(prefs: SharedPreferences): DuoyiWidgetThemePalette {
        return DuoyiWidgetThemePalette(
            brandId = prefs.getString("widget_theme_brand_id", "defaultBrand") ?: "defaultBrand",
            cardSkinId = prefs.getString("widget_theme_card_skin_id", "plain_card") ?: "plain_card",
            dark = prefs.getBoolean("widget_theme_dark", false),
            primary = readColor(prefs, "widget_theme_primary", defaultPrimary),
            background = readColor(prefs, "widget_theme_background", defaultBackground),
            surface = readColor(prefs, "widget_theme_surface", defaultSurface),
            navBackground = readColor(prefs, "widget_theme_nav_background", defaultNavBackground),
            border = readColor(prefs, "widget_theme_border", defaultBorder),
            text = readColor(prefs, "widget_theme_text", defaultText),
            mutedText = readColor(prefs, "widget_theme_muted_text", defaultMutedText),
            onPrimary = readColor(prefs, "widget_theme_on_primary", defaultOnPrimary),
            accentStart = readColor(prefs, "widget_theme_accent_start", defaultAccentStart),
            accentEnd = readColor(prefs, "widget_theme_accent_end", defaultAccentEnd),
            backgroundAssetKey = prefs.getString("widget_theme_background_asset_key", "") ?: "",
            cornerRadiusDp = readInt(prefs, "widget_theme_corner_radius_dp", 13),
            controlRadiusDp = readInt(prefs, "widget_theme_control_radius_dp", 8),
            borderWidthDp = readInt(prefs, "widget_theme_border_width_dp", 0),
        )
    }

    fun applyContainer(
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        navId: Int = 0,
    ) {
        val theme = read(prefs)
        val imageResource = backgroundImageResource(theme.backgroundAssetKey)
        if (imageResource != 0) {
            applyImageBackedSurface(
                views,
                rootId = rootId,
                imageResource = imageResource,
                overlayColor = imageOverlayColor(theme),
                radiusDp = theme.cornerRadiusDp,
            )
        } else {
            views.setViewVisibility(R.id.widget_theme_background, View.GONE)
            views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
            applyRoundedSurface(
                views,
                rootId,
                fill = theme.background,
                stroke = theme.border,
                radiusDp = theme.cornerRadiusDp,
                strokeWidthDp = theme.borderWidthDp,
            )
        }
        if (navId != 0) {
            applyRoundedSurface(
                views,
                navId,
                fill = theme.navBackground,
                stroke = blend(theme.border, theme.navBackground, 0.45f),
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = if (theme.borderWidthDp > 0) 1 else 0,
            )
        }
    }

    private fun applyImageBackedSurface(
        views: RemoteViews,
        rootId: Int,
        imageResource: Int,
        overlayColor: Int,
        radiusDp: Int,
    ) {
        views.setInt(
            rootId,
            "setBackgroundResource",
            widgetBackgroundResource(radiusDp, 0),
        )
        views.setImageViewResource(R.id.widget_theme_background, imageResource)
        views.setViewVisibility(R.id.widget_theme_background, View.VISIBLE)
        views.setInt(R.id.widget_theme_overlay, "setBackgroundColor", overlayColor)
        views.setViewVisibility(R.id.widget_theme_overlay, View.VISIBLE)
    }

    fun applyButtonSurfaces(
        views: RemoteViews,
        prefs: SharedPreferences,
        primaryIds: IntArray = intArrayOf(),
        secondaryIds: IntArray = intArrayOf(),
    ) {
        val theme = read(prefs)
        primaryIds.forEach {
            applyRoundedSurface(
                views,
                it,
                fill = theme.primary,
                stroke = theme.primary,
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = 0,
            )
        }
        secondaryIds.forEach {
            applyRoundedSurface(
                views,
                it,
                fill = theme.navBackground,
                stroke = blend(theme.border, theme.navBackground, 0.35f),
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = if (theme.borderWidthDp > 0) 1 else 0,
            )
        }
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

    private fun readInt(prefs: SharedPreferences, key: String, fallback: Int): Int {
        return try {
            prefs.getInt(key, fallback)
        } catch (_: ClassCastException) {
            prefs.getString(key, null)?.toIntOrNull() ?: fallback
        }
    }

    private fun applyRoundedSurface(
        views: RemoteViews,
        viewId: Int,
        fill: Int,
        stroke: Int,
        radiusDp: Int,
        strokeWidthDp: Int,
    ) {
        views.setInt(
            viewId,
            "setBackgroundResource",
            widgetBackgroundResource(radiusDp, strokeWidthDp),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            views.setColorStateList(viewId, "setBackgroundTintList", ColorStateList.valueOf(fill))
        } else {
            views.setInt(viewId, "setBackgroundColor", fill)
        }
    }

    private fun widgetBackgroundResource(radiusDp: Int, strokeWidthDp: Int): Int {
        if (radiusDp >= 16) return R.drawable.widget_bg_round_16
        if (radiusDp >= 15) return R.drawable.widget_bg_round_15
        if (radiusDp >= 14) return R.drawable.widget_bg_round_14
        if (strokeWidthDp <= 0) return R.drawable.widget_bg_plain
        return R.drawable.widget_bg
    }

    private fun backgroundImageResource(key: String): Int {
        return when (key.trim().lowercase()) {
            "re0" -> R.drawable.widget_theme_re0
            "genshin" -> R.drawable.widget_theme_genshin
            "star_rail" -> R.drawable.widget_theme_star_rail
            "wuthering" -> R.drawable.widget_theme_wuthering
            "zzz" -> R.drawable.widget_theme_zzz
            "yanyun" -> R.drawable.widget_theme_yanyun
            "botw" -> R.drawable.widget_theme_botw
            else -> 0
        }
    }

    private fun imageOverlayColor(theme: DuoyiWidgetThemePalette): Int {
        return if (theme.dark) {
            Color.argb(92, 0, 0, 0)
        } else {
            Color.argb(78, 255, 255, 255)
        }
    }

    private fun blend(foreground: Int, background: Int, alpha: Float): Int {
        val a = alpha.coerceIn(0f, 1f)
        val inv = 1f - a
        return Color.argb(
            255,
            (Color.red(foreground) * a + Color.red(background) * inv).toInt(),
            (Color.green(foreground) * a + Color.green(background) * inv).toInt(),
            (Color.blue(foreground) * a + Color.blue(background) * inv).toInt(),
        )
    }
}
