package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin

open class DuoyiStyledWidgetProvider : AppWidgetProvider() {
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused(
            context,
            ComponentName(context, this::class.java),
        )
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

        val resizedStyle = DuoyiWidgetPinStyle.fromWidgetOptions(newOptions)?.id
        val rawOptionStyle = newOptions.getString("duoyi_widget_style")
        val optionStyle = when (rawOptionStyle) {
            "compact", "standard", "detailed" -> rawOptionStyle
            else -> null
        }
        val receiverStyle = DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)
        val lockedVariantStyle = when (receiverStyle) {
            "compact", "detailed" -> receiverStyle
            else -> null
        }
        val normalizedStyle = optionStyle
            ?: lockedVariantStyle
            ?: resizedStyle
            ?: receiverStyle
            ?: DuoyiWidgetPinStyle.fromId(null).id
        Log.i(
            "DuoyiWidgetPin",
            "options_changed widgetId=$appWidgetId provider=${this::class.java.name} rawOptionStyle=${rawOptionStyle.orEmpty()} resizedStyle=${resizedStyle.orEmpty()} receiverStyle=${receiverStyle.orEmpty()} normalizedStyle=$normalizedStyle",
        )
        DuoyiWidgetDisplayMode.saveForWidget(
            HomeWidgetPlugin.getData(context),
            appWidgetId,
            normalizedStyle,
        )
        DuoyiWidgetProviderRegistry.markVariantProviderActive(
            context,
            ComponentName(context, this::class.java),
        )
        DuoyiWidgetProviderRegistry.requestUpdateForProvider(context, this::class.java.name)
    }
}
