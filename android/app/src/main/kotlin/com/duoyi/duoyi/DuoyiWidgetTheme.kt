package com.duoyi.duoyi

import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import kotlin.math.roundToInt

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
    private const val maxBackgroundBitmapCacheEntries = 8
    private val backgroundBitmapCache =
        object : LinkedHashMap<BackgroundBitmapCacheKey, Bitmap>(
            maxBackgroundBitmapCacheEntries,
            0.75f,
            true,
        ) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<BackgroundBitmapCacheKey, Bitmap>?,
            ): Boolean = size > maxBackgroundBitmapCacheEntries
        }

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
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        navId: Int = 0,
        appWidgetId: Int? = null,
    ) {
        val theme = read(prefs)
        val imageResource = backgroundImageResource(theme.backgroundAssetKey)
        if (imageResource != 0) {
            applyImageBackedSurface(
                context = context,
                views,
                prefs = prefs,
                rootId = rootId,
                imageResource = imageResource,
                overlayColor = imageOverlayColor(theme),
                radiusDp = theme.cornerRadiusDp,
                appWidgetId = appWidgetId,
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
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        imageResource: Int,
        overlayColor: Int,
        radiusDp: Int,
        appWidgetId: Int?,
    ) {
        views.setInt(
            rootId,
            "setBackgroundResource",
            widgetBackgroundResource(radiusDp, 0),
        )
        val bitmap = roundedBackgroundBitmap(
            context = context,
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            renderSpec = backgroundRenderSpec(prefs, appWidgetId),
        )
        if (bitmap == null) {
            views.setImageViewResource(R.id.widget_theme_background, imageResource)
            views.setInt(R.id.widget_theme_overlay, "setBackgroundColor", overlayColor)
            views.setViewVisibility(R.id.widget_theme_overlay, View.VISIBLE)
        } else {
            views.setImageViewBitmap(R.id.widget_theme_background, bitmap)
            views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
        }
        views.setViewVisibility(R.id.widget_theme_background, View.VISIBLE)
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
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

    private fun roundedBackgroundBitmap(
        context: Context,
        imageResource: Int,
        radiusDp: Int,
        overlayColor: Int,
        renderSpec: BackgroundRenderSpec,
    ): Bitmap? {
        val key = BackgroundBitmapCacheKey(
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            renderSpec = renderSpec,
        )
        synchronized(backgroundBitmapCache) {
            val cached = backgroundBitmapCache[key]
            if (cached != null && !cached.isRecycled) return cached
        }
        val output = renderRoundedBackgroundBitmap(
            context = context,
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            renderSpec = renderSpec,
        ) ?: return null
        synchronized(backgroundBitmapCache) {
            backgroundBitmapCache[key] = output
        }
        return output
    }

    private fun renderRoundedBackgroundBitmap(
        context: Context,
        imageResource: Int,
        radiusDp: Int,
        overlayColor: Int,
        renderSpec: BackgroundRenderSpec,
    ): Bitmap? {
        val source = BitmapFactory.decodeResource(context.resources, imageResource) ?: return null
        return try {
            val width = renderSpec.bitmapWidth
            val height = renderSpec.bitmapHeight
            val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val bounds = RectF(0f, 0f, width.toFloat(), height.toFloat())
            val radius = (radiusDp * renderSpec.radiusScale).toFloat()
            val path = Path().apply {
                addRoundRect(bounds, radius, radius, Path.Direction.CW)
            }
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG or Paint.FILTER_BITMAP_FLAG)
            canvas.clipPath(path)
            canvas.drawBitmap(source, centerCropRect(source, width, height), bounds, paint)
            paint.color = overlayColor
            paint.style = Paint.Style.FILL
            canvas.drawRect(bounds, paint)
            output
        } finally {
            source.recycle()
        }
    }

    private fun centerCropRect(source: Bitmap, targetWidth: Int, targetHeight: Int): Rect {
        val sourceAspect = source.width.toFloat() / source.height.toFloat()
        val targetAspect = targetWidth.toFloat() / targetHeight.toFloat()
        return if (sourceAspect > targetAspect) {
            val cropWidth = (source.height * targetAspect).roundToInt().coerceAtMost(source.width)
            val left = ((source.width - cropWidth) / 2).coerceAtLeast(0)
            Rect(left, 0, left + cropWidth, source.height)
        } else {
            val cropHeight = (source.width / targetAspect).roundToInt().coerceAtMost(source.height)
            val top = ((source.height - cropHeight) / 2).coerceAtLeast(0)
            Rect(0, top, source.width, top + cropHeight)
        }
    }

    private fun backgroundRenderSpec(
        prefs: SharedPreferences,
        appWidgetId: Int?,
    ): BackgroundRenderSpec {
        return when {
            DuoyiWidgetDisplayMode.isCompact(prefs, appWidgetId) -> BackgroundRenderSpec(
                bitmapWidth = 240,
                bitmapHeight = 240,
                logicalWidthDp = 110,
                logicalHeightDp = 110,
            )
            DuoyiWidgetDisplayMode.isDetailed(prefs, appWidgetId) -> BackgroundRenderSpec(
                bitmapWidth = 400,
                bitmapHeight = 288,
                logicalWidthDp = 250,
                logicalHeightDp = 180,
            )
            else -> BackgroundRenderSpec(
                bitmapWidth = 360,
                bitmapHeight = 220,
                logicalWidthDp = 180,
                logicalHeightDp = 110,
            )
        }
    }

    private data class BackgroundRenderSpec(
        val bitmapWidth: Int,
        val bitmapHeight: Int,
        val logicalWidthDp: Int,
        val logicalHeightDp: Int,
    ) {
        val radiusScale: Float
            get() = minOf(
                bitmapWidth.toFloat() / logicalWidthDp.toFloat(),
                bitmapHeight.toFloat() / logicalHeightDp.toFloat(),
            )
    }

    private data class BackgroundBitmapCacheKey(
        val imageResource: Int,
        val radiusDp: Int,
        val overlayColor: Int,
        val renderSpec: BackgroundRenderSpec,
    )

    private fun backgroundImageResource(key: String): Int {
        return when (key.trim().lowercase()) {
            "re0",
            "assets/backgrounds/re0.png" -> R.drawable.widget_theme_re0
            "genshin",
            "assets/backgrounds/genshin.png" -> R.drawable.widget_theme_genshin
            "starrail",
            "star_rail",
            "assets/backgrounds/star_rail.png" -> R.drawable.widget_theme_star_rail
            "wuthering",
            "wutheringwaves",
            "assets/backgrounds/wuthering.png" -> R.drawable.widget_theme_wuthering
            "zzz",
            "assets/backgrounds/zzz.png" -> R.drawable.widget_theme_zzz
            "yanyun",
            "assets/backgrounds/yanyun.png" -> R.drawable.widget_theme_yanyun
            "botw",
            "assets/backgrounds/botw.png" -> R.drawable.widget_theme_botw
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
