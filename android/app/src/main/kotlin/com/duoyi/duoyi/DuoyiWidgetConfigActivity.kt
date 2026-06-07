package com.duoyi.duoyi

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Configuration activity referenced by Android widget provider XML.
 * MIUI requires a configurable widget to declare this activity even if
 * it does nothing more than acknowledge placement.
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
        if (!providerStyle.isNullOrBlank()) {
            finishWithStyle(widgetId, providerStyle)
            return
        }

        finishWithStyle(widgetId, "standard")
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
        manager.updateAppWidgetOptions(widgetId, normalizedStyle.toOptions())
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
