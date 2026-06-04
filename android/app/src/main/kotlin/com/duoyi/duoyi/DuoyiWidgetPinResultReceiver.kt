package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin

class DuoyiWidgetPinResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestId = intent.getStringExtra(extraRequestId)
        val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        val manager = AppWidgetManager.getInstance(context)
        val actualProvider = if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            null
        } else {
            manager.getAppWidgetInfo(widgetId)?.provider
        }
        val providerStyle = DuoyiWidgetProviderRegistry.styleForProvider(actualProvider?.className)
        val pinStyle = DuoyiWidgetPinStyle.fromId(
            intent.getStringExtra(extraStyle) ?: providerStyle,
        )
        val kind = intent.getStringExtra(extraKind)
            ?: DuoyiWidgetProviderRegistry.kindForProvider(actualProvider?.className)
        val provider = actualProvider ?: kind?.let {
            DuoyiWidgetProviderRegistry.componentFor(context, it, pinStyle.id)
        }
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            Log.w(
                tag,
                "invalid_widget_id requestId=${requestId.orEmpty()} kind=${kind.orEmpty()} style=${pinStyle.id} provider=${provider?.className.orEmpty()}",
            )
            if (provider != null) {
                DuoyiWidgetProviderRegistry.clearPendingVariantProvider(
                    context,
                    requestId.orEmpty(),
                    provider,
                )
                DuoyiWidgetProviderRegistry.disableVariantProviderIfUnused(context, provider)
            }
            if (provider != null) {
                DuoyiWidgetProviderRegistry.requestUpdateForComponent(context, provider)
            } else if (!kind.isNullOrBlank()) {
                DuoyiWidgetProviderRegistry.requestUpdateForKind(context, kind)
            }
            recordResult(context, requestId, kind, pinStyle.id, widgetId, "invalid_widget_id")
            return
        }
        Log.i(
            tag,
            "confirmed requestId=${requestId.orEmpty()} kind=${kind.orEmpty()} style=${pinStyle.id} widgetId=$widgetId provider=${provider?.className.orEmpty()}",
        )
        DuoyiWidgetDisplayMode.saveForWidget(
            HomeWidgetPlugin.getData(context),
            widgetId,
            pinStyle.id,
        )
        manager.updateAppWidgetOptions(
            widgetId,
            pinStyle.toOptions(),
        )
        if (provider != null) {
            DuoyiWidgetProviderRegistry.markVariantProviderActive(context, provider)
            DuoyiWidgetProviderRegistry.clearPendingVariantProvider(
                context,
                requestId.orEmpty(),
                provider,
            )
            DuoyiWidgetProviderRegistry.scheduleDisableVariantProviderIfUnused(
                context,
                provider,
            )
        }
        if (provider != null) {
            DuoyiWidgetProviderRegistry.requestUpdateForComponent(context, provider)
        } else if (!kind.isNullOrBlank()) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, kind)
        }
        recordResult(context, requestId, kind, pinStyle.id, widgetId, "confirmed")
    }

    private fun recordResult(
        context: Context,
        requestId: String?,
        kind: String?,
        style: String,
        widgetId: Int,
        status: String,
    ) {
        if (requestId.isNullOrBlank()) return
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(keyRequestId, requestId)
            .putString(keyKind, kind.orEmpty())
            .putString(keyStyle, style)
            .putInt(keyWidgetId, widgetId)
            .putString(keyStatus, status)
            .putLong(keyConfirmedAt, System.currentTimeMillis())
            .apply()
    }

    companion object {
        private const val tag = "DuoyiWidgetPin"
        const val prefsName = "duoyi_widget_pin_result"
        const val extraKind = "duoyi_widget_kind"
        const val extraStyle = "duoyi_widget_style"
        const val extraRequestId = "duoyi_widget_request_id"
        const val keyRequestId = "request_id"
        const val keyKind = "kind"
        const val keyStyle = "style"
        const val keyWidgetId = "widget_id"
        const val keyStatus = "status"
        const val keyConfirmedAt = "confirmed_at"
    }
}
