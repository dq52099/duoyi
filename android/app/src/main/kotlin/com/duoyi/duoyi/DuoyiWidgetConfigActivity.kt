package com.duoyi.duoyi

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Configuration activity referenced by Android widget provider XML.
 * Honors explicit requested pin styles immediately and otherwise shows a
 * lightweight native configuration sheet for per-widget mode, footer, and theme.
 */
class DuoyiWidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        val widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val manager = AppWidgetManager.getInstance(applicationContext)
        val requestedStyle = requestedStyleFromIntent() ?: manager
            .getAppWidgetOptions(widgetId)
            ?.getString("duoyi_widget_style")
        if (!requestedStyle.isNullOrBlank()) {
            finishWithStyle(widgetId, requestedStyle)
            return
        }

        val providerClassName = manager.getAppWidgetInfo(widgetId)?.provider?.className
        val providerStyle = DuoyiWidgetProviderRegistry.styleForProvider(providerClassName)
        try {
            showConfigSheet(widgetId, providerStyle)
        } catch (_: Throwable) {
            if (!providerStyle.isNullOrBlank()) {
                finishWithStyle(widgetId, providerStyle)
            } else {
                finishWithStyle(widgetId, "standard")
            }
        }
    }

    private fun showConfigSheet(widgetId: Int, providerStyle: String?) {
        setContentView(R.layout.duoyi_widget_config_activity)
        val prefs = HomeWidgetPlugin.getData(applicationContext)
        val isZh = DuoyiWidgetCopy.isZh(prefs)
        val theme = DuoyiWidgetTheme.read(prefs, this, widgetId)
        val density = resources.displayMetrics.density

        val initialMode = prefs.getString("widget_display_mode_$widgetId", null)
            ?.takeIf { it == "compact" || it == "standard" || it == "detailed" }
            ?: providerStyle?.takeIf { it == "compact" || it == "standard" || it == "detailed" }
            ?: prefs.getString("widget_display_mode", null)
                ?.takeIf { it == "compact" || it == "standard" || it == "detailed" }
            ?: "standard"
        val initialShowNav = DuoyiWidgetTheme.isBottomNavEnabled(applicationContext, prefs, widgetId)
        val initialThemeMode = DuoyiWidgetTheme.readThemeMode(applicationContext, prefs, widgetId)

        val card = findViewById<LinearLayout>(R.id.widget_config_card)
        val titleView = findViewById<TextView>(R.id.widget_config_title)
        val subtitleView = findViewById<TextView>(R.id.widget_config_subtitle)
        val modeLabel = findViewById<TextView>(R.id.widget_config_mode_label)
        val modeGroup = findViewById<RadioGroup>(R.id.widget_config_mode_group)
        val modeCompact = findViewById<RadioButton>(R.id.widget_config_mode_compact)
        val modeStandard = findViewById<RadioButton>(R.id.widget_config_mode_standard)
        val modeDetailed = findViewById<RadioButton>(R.id.widget_config_mode_detailed)
        val showNavBox = findViewById<CheckBox>(R.id.widget_config_show_nav_checkbox)
        val themeLabel = findViewById<TextView>(R.id.widget_config_theme_label)
        val themeGroup = findViewById<RadioGroup>(R.id.widget_config_theme_group)
        val themeSystem = findViewById<RadioButton>(R.id.widget_config_theme_system)
        val themeLight = findViewById<RadioButton>(R.id.widget_config_theme_light)
        val themeDark = findViewById<RadioButton>(R.id.widget_config_theme_dark)
        val cancelBtn = findViewById<Button>(R.id.widget_config_cancel_btn)
        val saveBtn = findViewById<Button>(R.id.widget_config_save_btn)

        titleView.text = if (isZh) "小组件设置" else "Widget Settings"
        subtitleView.text = if (isZh) "为当前小组件选择布局尺寸与外观风格" else "Customize size mode, footer bar, and appearance"
        modeLabel.text = if (isZh) "显示尺寸" else "Display Mode"
        modeCompact.text = if (isZh) "紧凑 (2×2)" else "Compact (2×2)"
        modeStandard.text = if (isZh) "标准 (3×2)" else "Standard (3×2)"
        modeDetailed.text = if (isZh) "详细 (4×3)" else "Detailed (4×3)"
        showNavBox.text = if (isZh) "显示底部快捷导航栏" else "Show bottom quick navigation"
        themeLabel.text = if (isZh) "外观主题" else "Appearance"
        themeSystem.text = if (isZh) "跟随系统" else "Follow System"
        themeLight.text = if (isZh) "浅色" else "Light"
        themeDark.text = if (isZh) "深色" else "Dark"
        cancelBtn.text = if (isZh) "取消" else "Cancel"
        saveBtn.text = if (isZh) "保存" else "Save"

        card.background = GradientDrawable().apply {
            cornerRadius = 18f * density
            setColor(theme.background)
            setStroke(
                (1f * density).toInt().coerceAtLeast(1),
                if (theme.dark) theme.border else Color.parseColor("#FFE2E8F0"),
            )
        }
        titleView.setTextColor(theme.text)
        subtitleView.setTextColor(theme.readableMutedText)
        modeLabel.setTextColor(theme.text)
        themeLabel.setTextColor(theme.text)
        val accentTint = ColorStateList.valueOf(theme.primary)
        listOf(modeCompact, modeStandard, modeDetailed, showNavBox, themeSystem, themeLight, themeDark).forEach {
            it.setTextColor(theme.text)
            it.buttonTintList = accentTint
        }
        cancelBtn.background = GradientDrawable().apply {
            cornerRadius = 10f * density
            setColor(theme.navBackground)
        }
        cancelBtn.setTextColor(theme.readablePrimary)
        saveBtn.background = GradientDrawable().apply {
            cornerRadius = 10f * density
            setColor(theme.primary)
        }
        saveBtn.setTextColor(theme.readableOnPrimary)

        when (initialMode) {
            "compact" -> modeCompact.isChecked = true
            "detailed" -> modeDetailed.isChecked = true
            else -> modeStandard.isChecked = true
        }
        showNavBox.isChecked = initialShowNav
        when (initialThemeMode) {
            DuoyiWidgetTheme.THEME_MODE_DARK -> themeDark.isChecked = true
            DuoyiWidgetTheme.THEME_MODE_LIGHT -> themeLight.isChecked = true
            else -> themeSystem.isChecked = true
        }

        cancelBtn.setOnClickListener {
            setResult(RESULT_CANCELED)
            finish()
        }
        saveBtn.setOnClickListener {
            val selectedMode = when (modeGroup.checkedRadioButtonId) {
                R.id.widget_config_mode_compact -> "compact"
                R.id.widget_config_mode_detailed -> "detailed"
                else -> "standard"
            }
            val selectedThemeMode = when (themeGroup.checkedRadioButtonId) {
                R.id.widget_config_theme_dark -> DuoyiWidgetTheme.THEME_MODE_DARK
                R.id.widget_config_theme_light -> DuoyiWidgetTheme.THEME_MODE_LIGHT
                else -> DuoyiWidgetTheme.THEME_MODE_SYSTEM
            }
            DuoyiWidgetTheme.saveWidgetConfigPreferences(
                context = applicationContext,
                appWidgetId = widgetId,
                displayMode = selectedMode,
                showBottomNav = showNavBox.isChecked,
                themeMode = selectedThemeMode,
            )
            when (selectedMode) {
                "compact" -> finishWithStyle(widgetId, "compact")
                "detailed" -> finishWithStyle(widgetId, "detailed")
                else -> finishWithStyle(widgetId, "standard")
            }
        }
    }

    private fun requestedStyleFromIntent(): String? {
        val direct = intent?.extras?.getString("duoyi_widget_style")
        if (!direct.isNullOrBlank()) return direct
        val extras = intent?.extras?.getBundle(AppWidgetManager.EXTRA_APPWIDGET_OPTIONS)
        return extras?.getString("duoyi_widget_style")
    }

    private fun finishWithStyle(widgetId: Int, style: String) {
        val normalizedStyle = DuoyiWidgetPinStyle.fromId(style)
        DuoyiWidgetDisplayMode.saveForWidget(
            HomeWidgetPlugin.getData(applicationContext),
            widgetId,
            normalizedStyle.id,
        )
        val manager = AppWidgetManager.getInstance(applicationContext)
        manager.updateAppWidgetOptions(widgetId, normalizedStyle.toDisplayModeOptions())
        // Ask the actual provider to render the initial state immediately.
        val providerClassName = manager.getAppWidgetInfo(widgetId)?.provider?.className
        val provider = manager.getAppWidgetInfo(widgetId)?.provider
        if (provider != null) {
            DuoyiWidgetProviderRegistry.markVariantProviderActive(applicationContext, provider)
        }
        DuoyiWidgetProviderRegistry.requestUpdateForProvider(applicationContext, providerClassName)
        DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(applicationContext)

        val resultValue = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        setResult(RESULT_OK, resultValue)
        finish()
    }
}
