package com.duoyi.duoyi

import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.WeakHashMap
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
) {
    val isDark: Boolean
        get() = dark

    private val usesReadableColors: Boolean
        get() = cardSkinId in supportedColorSkins &&
            (brandId == "defaultBrand" || brandId == "liquidGlass") &&
            backgroundAssetKey.isEmpty() &&
            listOf(background, surface, navBackground).all { (it ushr 24) == 255 }

    val readablePrimary: Int
        get() = if (usesReadableColors) DuoyiWidgetReadableColors.foreground(
            primary, intArrayOf(background, surface, navBackground),
        ) else primary

    val readableMutedText: Int
        get() = if (usesReadableColors) DuoyiWidgetReadableColors.foreground(
            mutedText, intArrayOf(background, surface, navBackground),
        ) else mutedText

    val readableOnPrimary: Int
        get() = if (usesReadableColors && (primary ushr 24) == 255) DuoyiWidgetReadableColors.foreground(
            onPrimary, intArrayOf(primary),
        ) else onPrimary

    companion object {
        private val supportedColorSkins = setOf("plain_card", "paper_card", "mint_card", "starlight_card")
    }
}

object DuoyiWidgetTheme {
    const val THEME_MODE_SYSTEM = "system"
    const val THEME_MODE_DARK = "dark"
    const val THEME_MODE_LIGHT = "light"

    private const val defaultPrimary = "#FF0066D6"
    private const val defaultBackground = "#FFF6F7F9"
    private const val defaultSurface = "#FFFFFFFF"
    private const val defaultNavBackground = "#FFF1F3F6"
    private const val defaultBorder = "#000066D6"
    private const val defaultText = "#FF1F2933"
    private const val defaultMutedText = "#FF667085"
    private const val defaultOnPrimary = "#FFFFFFFF"
    private const val defaultAccentStart = "#FF0066D6"
    private const val defaultAccentEnd = "#FF3898FF"

    private const val darkPrimary = "#FF0A84FF"
    private const val darkBackground = "#FF14171F"
    private const val darkSurface = "#FF1C212B"
    private const val darkNavBackground = "#FF242A36"
    private const val darkBorder = "#FF2F3847"
    private const val darkText = "#FFF2F5FA"
    private const val darkMutedText = "#FFA5B0C2"
    private const val darkOnPrimary = "#FFFFFFFF"
    private const val darkAccentStart = "#FF0A84FF"
    private const val darkAccentEnd = "#FF3898FF"

    private val autoDarkBrands = setOf("defaultBrand", "liquidGlass", "default", "liquid_glass")
    private data class FrameThemeContext(
        val systemNight: Boolean,
        val appWidgetId: Int?,
        val themeModeOverride: String?,
    )
    private val frameContextCache = WeakHashMap<SharedPreferences, FrameThemeContext>()

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

    fun widgetShowBottomNavKey(appWidgetId: Int): String = "widget_show_bottom_nav_$appWidgetId"

    fun widgetThemeModeKey(appWidgetId: Int): String = "widget_theme_mode_$appWidgetId"

    fun isBottomNavEnabled(context: Context, prefs: SharedPreferences, appWidgetId: Int?): Boolean =
        isBottomNavEnabled(prefs, appWidgetId, context)

    fun isBottomNavEnabled(
        prefs: SharedPreferences,
        appWidgetId: Int?,
        context: Context? = null,
    ): Boolean {
        if (appWidgetId == null || appWidgetId <= 0) return true
        val key = widgetShowBottomNavKey(appWidgetId)
        val devicePrefs = if (context != null) safeDevicePrefs(context, prefs) else prefs
        return when {
            devicePrefs.contains(key) -> readBooleanCompat(devicePrefs, key, true)
            prefs.contains(key) -> readBooleanCompat(prefs, key, true)
            else -> true
        }
    }

    fun readThemeMode(context: Context?, prefs: SharedPreferences, appWidgetId: Int?): String {
        if (appWidgetId == null || appWidgetId <= 0) return THEME_MODE_SYSTEM
        val key = widgetThemeModeKey(appWidgetId)
        val devicePrefs = if (context != null) safeDevicePrefs(context, prefs) else prefs
        return normalizeThemeMode(devicePrefs.getString(key, null))
            ?: normalizeThemeMode(prefs.getString(key, null))
            ?: THEME_MODE_SYSTEM
    }

    fun saveWidgetConfigPreferences(
        context: Context,
        appWidgetId: Int,
        displayMode: String,
        showBottomNav: Boolean,
        themeMode: String,
    ) {
        if (appWidgetId <= 0) return
        saveWidgetConfigToPrefs(
            prefs = HomeWidgetPlugin.getData(context),
            appWidgetId = appWidgetId,
            displayMode = displayMode,
            showBottomNav = showBottomNav,
            themeMode = themeMode,
        )
    }

    fun saveWidgetConfigToPrefs(
        prefs: SharedPreferences,
        appWidgetId: Int,
        displayMode: String,
        showBottomNav: Boolean,
        themeMode: String,
    ) {
        if (appWidgetId <= 0) return
        DuoyiWidgetDisplayMode.saveForWidget(prefs, appWidgetId, displayMode)
        prefs.edit()
            .putBoolean(widgetShowBottomNavKey(appWidgetId), showBottomNav)
            .putString(widgetThemeModeKey(appWidgetId), normalizeThemeMode(themeMode) ?: THEME_MODE_SYSTEM)
            .apply()
    }

    fun isNightUiMode(uiMode: Int): Boolean =
        (uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    fun read(prefs: SharedPreferences): DuoyiWidgetThemePalette = read(prefs, null, null)

    fun read(
        prefs: SharedPreferences,
        uiMode: Int,
        appWidgetId: Int? = null,
    ): DuoyiWidgetThemePalette = read(prefs, isNightUiMode(uiMode), appWidgetId)

    fun read(
        prefs: SharedPreferences,
        systemNight: Boolean,
        appWidgetId: Int? = null,
    ): DuoyiWidgetThemePalette {
        val raw = readRawPalette(prefs)
        return resolveThemePalette(raw, prefs, context = null, appWidgetId = appWidgetId, systemNightOverride = systemNight)
    }

    fun read(
        prefs: SharedPreferences,
        context: Context?,
        appWidgetId: Int? = null,
    ): DuoyiWidgetThemePalette {
        val raw = readRawPalette(prefs)
        return resolveThemePalette(raw, prefs, context = context, appWidgetId = appWidgetId)
    }

    private fun readRawPalette(prefs: SharedPreferences): DuoyiWidgetThemePalette =
        DuoyiWidgetThemePalette(
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
            cornerRadiusDp = readInt(prefs, "widget_theme_corner_radius_dp", 16),
            controlRadiusDp = readInt(prefs, "widget_theme_control_radius_dp", 12),
            borderWidthDp = readInt(prefs, "widget_theme_border_width_dp", 0),
        )

    private fun resolveThemePalette(
        base: DuoyiWidgetThemePalette,
        prefs: SharedPreferences,
        context: Context?,
        appWidgetId: Int?,
        systemNightOverride: Boolean? = null,
    ): DuoyiWidgetThemePalette {
        val cached = synchronized(frameContextCache) { frameContextCache[prefs] }
        val resolvedWidgetId = appWidgetId ?: cached?.appWidgetId
        val modeOverride = readThemeMode(context, prefs, resolvedWidgetId)
            .takeIf { it != THEME_MODE_SYSTEM }
            ?: cached?.themeModeOverride
            ?: THEME_MODE_SYSTEM
        val systemNight = systemNightOverride
            ?: if (context != null) isSystemDark(context) else (cached?.systemNight ?: false)
        val isAutoDarkBrand = base.brandId in autoDarkBrands

        if (modeOverride == THEME_MODE_LIGHT) {
            return if (base.isDark && (isAutoDarkBrand || base.background == parseHexColor(darkBackground))) {
                base.copy(
                    dark = false,
                    primary = parseHexColor(defaultPrimary),
                    background = parseHexColor(defaultBackground),
                    surface = parseHexColor(defaultSurface),
                    navBackground = parseHexColor(defaultNavBackground),
                    border = parseHexColor(defaultBorder),
                    text = parseHexColor(defaultText),
                    mutedText = parseHexColor(defaultMutedText),
                    onPrimary = parseHexColor(defaultOnPrimary),
                    accentStart = parseHexColor(defaultAccentStart),
                    accentEnd = parseHexColor(defaultAccentEnd),
                )
            } else {
                base.copy(dark = false)
            }
        }

        val shouldUseDark = modeOverride == THEME_MODE_DARK ||
            base.isDark ||
            (systemNight && isAutoDarkBrand)
        if (!shouldUseDark) return base

        val shouldApplyDefaultDarkPalette = modeOverride == THEME_MODE_DARK ||
            isAutoDarkBrand ||
            base.background == parseHexColor(defaultBackground)
        if (!shouldApplyDefaultDarkPalette) {
            return base.copy(dark = true)
        }
        return base.copy(
            dark = true,
            primary = parseHexColor(darkPrimary),
            background = parseHexColor(darkBackground),
            surface = parseHexColor(darkSurface),
            navBackground = parseHexColor(darkNavBackground),
            border = parseHexColor(darkBorder),
            text = parseHexColor(darkText),
            mutedText = parseHexColor(darkMutedText),
            onPrimary = parseHexColor(darkOnPrimary),
            accentStart = parseHexColor(darkAccentStart),
            accentEnd = parseHexColor(darkAccentEnd),
            borderWidthDp = maxOf(base.borderWidthDp, 1),
        )
    }

    private fun isSystemDark(context: Context): Boolean =
        isNightUiMode(context.resources.configuration.uiMode)

    private fun safeDevicePrefs(context: Context, fallback: SharedPreferences): SharedPreferences =
        try {
            HomeWidgetPlugin.getData(context)
        } catch (_: Throwable) {
            fallback
        }

    private fun normalizeThemeMode(raw: String?): String? = when (raw?.trim()?.lowercase()) {
        THEME_MODE_DARK -> THEME_MODE_DARK
        THEME_MODE_LIGHT -> THEME_MODE_LIGHT
        THEME_MODE_SYSTEM -> THEME_MODE_SYSTEM
        else -> null
    }

    private fun readBooleanCompat(prefs: SharedPreferences, key: String, fallback: Boolean): Boolean {
        return try {
            prefs.getBoolean(key, fallback)
        } catch (_: ClassCastException) {
            when (prefs.getString(key, null)?.trim()?.lowercase()) {
                "true" -> true
                "false" -> false
                else -> fallback
            }
        }
    }

    fun applyContainer(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        rootId: Int,
        navId: Int = 0,
        appWidgetId: Int? = null,
    ) {
        val themeOverride = readThemeMode(context, prefs, appWidgetId)
        synchronized(frameContextCache) {
            frameContextCache[prefs] = FrameThemeContext(
                systemNight = isSystemDark(context),
                appWidgetId = appWidgetId,
                themeModeOverride = themeOverride,
            )
        }
        val theme = read(prefs, context, appWidgetId)
        val surfaces = if (theme.dark) null else DuoyiWidgetSurfaceResources.forTheme(theme)
        views.setTextColor(R.id.widget_refresh, theme.readableMutedText)
        views.setOnClickPendingIntent(R.id.widget_refresh, HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, Uri.parse("duoyi://action/refresh_widgets")))
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
                fill = theme.background,
                stroke = theme.border,
                strokeWidthDp = theme.borderWidthDp,
                rootResourceId = surfaces?.root,
                borderResourceId = surfaces?.imageBorder,
                appWidgetId = appWidgetId,
            )
        } else {
            views.setViewVisibility(R.id.widget_theme_background, View.GONE)
            views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
            views.setViewVisibility(R.id.widget_theme_border, View.GONE)
            applyRoundedSurface(
                views,
                rootId,
                fill = theme.background,
                stroke = theme.border,
                radiusDp = theme.cornerRadiusDp,
                strokeWidthDp = theme.borderWidthDp,
                resourceId = surfaces?.root,
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
                resourceId = surfaces?.nav,
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
        fill: Int,
        stroke: Int,
        strokeWidthDp: Int,
        rootResourceId: Int?,
        borderResourceId: Int?,
        appWidgetId: Int?,
    ) {
        views.setInt(
            rootId,
            "setBackgroundResource",
            rootResourceId ?: widgetBackgroundResource(radiusDp, 0),
        )
        clearBackgroundTint(views, rootId)
        val bitmap = roundedBackgroundBitmap(
            context = context,
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            fill = fill,
            stroke = stroke,
            // Bundled borders scale with the launcher bounds rather than being
            // cropped with the photo. Unknown palettes retain a bitmap stroke.
            strokeWidthDp = if (borderResourceId == null) strokeWidthDp else 0,
            renderSpec = backgroundRenderSpec(prefs, appWidgetId),
        )
        views.setImageViewBitmap(R.id.widget_theme_background, bitmap)
        views.setViewVisibility(R.id.widget_theme_overlay, View.GONE)
        if (borderResourceId != null && strokeWidthDp > 0) {
            views.setImageViewResource(R.id.widget_theme_border, borderResourceId)
            views.setViewVisibility(R.id.widget_theme_border, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_theme_border, View.GONE)
        }
        views.setViewVisibility(R.id.widget_theme_background, View.VISIBLE)
    }

    fun applyButtonSurfaces(
        views: RemoteViews,
        prefs: SharedPreferences,
        primaryIds: IntArray = intArrayOf(),
        secondaryIds: IntArray = intArrayOf(),
        context: Context? = null,
        appWidgetId: Int? = null,
    ) {
        val theme = read(prefs, context, appWidgetId)
        val surfaces = if (theme.dark) null else DuoyiWidgetSurfaceResources.forTheme(theme)
        primaryIds.forEach {
            applyRoundedSurface(
                views,
                it,
                fill = theme.primary,
                stroke = theme.primary,
                radiusDp = theme.controlRadiusDp,
                strokeWidthDp = 0,
                resourceId = surfaces?.primary,
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
                resourceId = surfaces?.secondary,
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
        context: Context? = null,
        appWidgetId: Int? = null,
    ) {
        val theme = read(prefs, context, appWidgetId)
        primaryIds.forEach { views.setTextColor(it, theme.readablePrimary) }
        bodyIds.forEach { views.setTextColor(it, theme.text) }
        mutedIds.forEach { views.setTextColor(it, theme.readableMutedText) }
        onPrimaryIds.forEach { views.setTextColor(it, theme.readableOnPrimary) }
    }

    fun applyProgressBar(
        views: RemoteViews,
        progressBarId: Int,
        progress: Int,
        prefs: SharedPreferences,
        context: Context? = null,
        appWidgetId: Int? = null,
        max: Int = 100,
    ) {
        val boundedMax = max.coerceAtLeast(1)
        val boundedProgress = progress.coerceIn(0, boundedMax)
        views.setProgressBar(progressBarId, boundedMax, boundedProgress, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val theme = read(prefs, context, appWidgetId)
            views.setColorStateList(
                progressBarId,
                "setProgressTintList",
                ColorStateList.valueOf(theme.primary),
            )
            val trackColor = if (theme.dark) {
                Color.argb(72, 165, 176, 194)
            } else {
                Color.argb(36, 100, 116, 139)
            }
            views.setColorStateList(
                progressBarId,
                "setProgressBackgroundTintList",
                ColorStateList.valueOf(trackColor),
            )
        }
    }

    private fun readColor(
        prefs: SharedPreferences,
        key: String,
        fallback: String,
    ): Int {
        val raw = prefs.getString(key, null)?.trim()
        if (raw.isNullOrEmpty()) return parseHexColor(fallback)
        return tryParseHexColor(raw) ?: try {
            Color.parseColor(raw)
        } catch (_: Throwable) {
            parseHexColor(fallback)
        }
    }

    private fun parseHexColor(raw: String): Int =
        tryParseHexColor(raw) ?: Color.parseColor(raw)

    private fun tryParseHexColor(raw: String): Int? {
        val clean = raw.trim().removePrefix("#")
        if (clean.length != 6 && clean.length != 8) return null
        val parsed = clean.toLongOrNull(16) ?: return null
        return if (clean.length == 6) {
            (0xFF000000L or parsed).toInt()
        } else {
            parsed.toInt()
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
        resourceId: Int? = null,
    ) {
        views.setInt(
            viewId,
            "setBackgroundResource",
            resourceId ?: widgetBackgroundResource(radiusDp, strokeWidthDp),
        )
        // Known brand/skin pairs use exact scalable shape resources on every
        // Android version. Runtime tint would also recolor their border.
        if (resourceId != null) {
            clearBackgroundTint(views, viewId)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(viewId, "setBackgroundTintList", ColorStateList.valueOf(fill))
        } else {
            // RemoteViews on pre-S cannot tint a drawable reliably. Keeping the rounded
            // drawable is preferable to replacing it with a square setBackgroundColor.
            Log.d(
                "DuoyiWidgetTheme",
                "pre-S rounded widget surface uses bundled rounded drawable without runtime tint",
            )
        }
    }

    private fun clearBackgroundTint(views: RemoteViews, viewId: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Launcher reapply can retain tint set by an older widget version.
            views.setColorStateList(viewId, "setBackgroundTintList", null)
        }
    }

    private fun widgetBackgroundResource(radiusDp: Int, strokeWidthDp: Int): Int {
        if (strokeWidthDp <= 0) {
            if (radiusDp >= 16) return R.drawable.widget_bg_round_16_plain
            if (radiusDp >= 15) return R.drawable.widget_bg_round_15_plain
            if (radiusDp >= 14) return R.drawable.widget_bg_round_14_plain
            if (radiusDp >= 13) return R.drawable.widget_bg_round_13_plain
            if (radiusDp >= 12) return R.drawable.widget_bg_round_12_plain
            return R.drawable.widget_bg_plain
        }
        if (radiusDp >= 16) return R.drawable.widget_bg_round_16
        if (radiusDp >= 15) return R.drawable.widget_bg_round_15
        if (radiusDp >= 14) return R.drawable.widget_bg_round_14
        return R.drawable.widget_bg
    }

    private fun roundedBackgroundBitmap(
        context: Context,
        imageResource: Int,
        radiusDp: Int,
        overlayColor: Int,
        fill: Int,
        stroke: Int,
        strokeWidthDp: Int,
        renderSpec: BackgroundRenderSpec,
    ): Bitmap {
        val key = BackgroundBitmapCacheKey(
            imageResource = imageResource,
            radiusDp = radiusDp,
            overlayColor = overlayColor,
            fill = fill,
            stroke = stroke,
            strokeWidthDp = strokeWidthDp,
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
            fill = fill,
            stroke = stroke,
            strokeWidthDp = strokeWidthDp,
            renderSpec = renderSpec,
        )
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
        fill: Int,
        stroke: Int,
        strokeWidthDp: Int,
        renderSpec: BackgroundRenderSpec,
    ): Bitmap {
        val source = BitmapFactory.decodeResource(context.resources, imageResource)
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
            if (source != null) {
                canvas.drawBitmap(source, centerCropRect(source, width, height), bounds, paint)
            } else {
                // Preserve the same radius, overlay and border if decoding fails.
                paint.color = fill
                canvas.drawRect(bounds, paint)
            }
            paint.color = overlayColor
            paint.style = Paint.Style.FILL
            canvas.drawRect(bounds, paint)
            if (strokeWidthDp > 0) {
                val strokeWidth = (strokeWidthDp * renderSpec.radiusScale)
                    .coerceAtMost(minOf(width, height).toFloat())
                val inset = strokeWidth / 2f
                val strokeBounds = RectF(bounds).apply { inset(inset, inset) }
                val strokeRadius = (radius - inset).coerceAtLeast(0f)
                paint.color = stroke
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = strokeWidth
                canvas.drawRoundRect(strokeBounds, strokeRadius, strokeRadius, paint)
            }
            output
        } finally {
            if (source != null) source.recycle()
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
        val fill: Int,
        val stroke: Int,
        val strokeWidthDp: Int,
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
