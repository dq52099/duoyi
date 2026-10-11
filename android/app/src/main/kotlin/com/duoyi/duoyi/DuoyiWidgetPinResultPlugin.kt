package com.duoyi.duoyi

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Wait protection belongs to the consumer engine, and survives Activity recreation. */
class DuoyiWidgetPinResultPlugin(private val engine: FlutterEngine) :
    FlutterPlugin, MethodChannel.MethodCallHandler {
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var owner: String? = null
    private val lifecycle = object : FlutterEngine.EngineLifecycleListener {
        override fun onPreEngineRestart() {
            releaseOwner()
            if (context != null) owner = UUID.randomUUID().toString()
        }

        override fun onEngineWillDestroy() {
            releaseOwner()
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        owner = UUID.randomUUID().toString()
        engine.addEngineLifecycleListener(lifecycle)
        DuoyiWidgetPinResults.prune(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "duoyi/widget_pin_results").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine.removeEngineLifecycleListener(lifecycle)
        releaseOwner()
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("beginWait", "endWait")) {
            result.notImplemented()
            return
        }
        val capturedContext = context
        val capturedOwner = owner
        if (capturedContext == null || capturedOwner == null) {
            result.success(null)
            return
        }
        val requestId = call.argument<String>("requestId").orEmpty()
        if (call.method == "beginWait") {
            val timeout = call.argument<Number>("timeoutMillis")?.toLong() ?: 0L
            result.success(DuoyiWidgetPinResults.beginWait(capturedContext, requestId, capturedOwner, timeout))
        } else {
            val token = call.argument<String>("token").orEmpty()
            DuoyiWidgetPinResults.endWait(capturedContext, requestId, capturedOwner, token)
            result.success(null)
        }
    }

    private fun releaseOwner() {
        val capturedContext = context
        val capturedOwner = owner
        owner = null
        if (capturedContext != null && capturedOwner != null) {
            DuoyiWidgetPinResults.releaseOwner(capturedContext, capturedOwner)
        }
    }
}
