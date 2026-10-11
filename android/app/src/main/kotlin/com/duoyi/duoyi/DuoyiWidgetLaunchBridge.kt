package com.duoyi.duoyi

import android.content.Intent
import android.net.Uri
import android.util.Log
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** App-owned widget transport. All methods run on Android's main thread. */
object DuoyiWidgetLaunchBridge {
    private val queue = DuoyiWidgetLaunchQueue()
    private var channel: MethodChannel? = null
    private var subscribed = false
    private val supportedHosts = setOf(
        "tab", "todo", "habit", "calendar", "focus", "widget", "course", "note",
        "diary", "goal", "anniversary", "countdown", "time-entry", "report", "action",
    )

    fun capture(intent: Intent?) {
        if (intent?.action != HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) return
        val uri = intent.data ?: return
        if (uri.scheme != "duoyi" || !uri.isHierarchical ||
            uri.host !in supportedHosts || uri.toString().length > 8192) return
        val delivery = runCatching { queue.receive { id ->
            // Transport origin is not account authorization. Keep the original
            // snapshot binding, including its absence on legacy widget links.
            val builder = uri.buildUpon().clearQuery()
            for (name in uri.queryParameterNames) {
                if (name == "source" || name == "widget_delivery") continue
                for (value in uri.getQueryParameters(name)) builder.appendQueryParameter(name, value)
            }
            builder.appendQueryParameter("source", "widget")
                .appendQueryParameter("widget_delivery", id)
                .build().toString()
        } }.getOrElse {
            Log.w("DuoyiWidgetLaunch", "Ignoring malformed widget launch URI")
            return
        } ?: run {
            Log.w("DuoyiWidgetLaunch", "Widget launch backlog full; ignoring new launch")
            return
        }
        intent.data = Uri.parse(delivery.uri)
        if (subscribed) channel?.invokeMethod("onLaunch", delivery.payload())
    }

    fun attach(messenger: BinaryMessenger): MethodChannel {
        channel?.setMethodCallHandler(null)
        subscribed = false
        val next = MethodChannel(messenger, "duoyi/widget_launch")
        channel = next
        next.setMethodCallHandler { call, result ->
            if (channel !== next) {
                result.error("STALE_WIDGET_ENGINE", "Widget launch engine changed", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "subscribe" -> {
                    subscribed = true
                    result.success(queue.snapshot().map { it.payload() })
                }
                "unsubscribe" -> {
                    subscribed = false
                    result.success(null)
                }
                "ack" -> {
                    val id = call.arguments as? String
                    if (id != null) queue.acknowledge(id)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        return next
    }

    fun detach(expectedChannel: MethodChannel?) {
        if (channel !== expectedChannel) return
        subscribed = false
        channel?.setMethodCallHandler(null)
        channel = null
    }
}

/** Keeps a retained Flutter engine subscribed across Activity recreation. */
class DuoyiWidgetLaunchPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = DuoyiWidgetLaunchBridge.attach(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DuoyiWidgetLaunchBridge.detach(channel)
        channel = null
    }
}
