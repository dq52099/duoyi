package com.duoyi.duoyi

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Engine-owned messenger adapter; the application-scoped store owns committed state. */
class DuoyiWidgetPublicationBridge : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var store: DuoyiWidgetPublicationStore? = null
    @Volatile private var attachment: Any? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        store = DuoyiWidgetPublicationStore.forContext(binding.applicationContext)
        attachment = Any()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attachment = null
        channel?.setMethodCallHandler(null)
        channel = null
        store = null
        // Already queued/committed mutations retain their request and receipt.
        // Detaching a messenger is not permission to undo or replay a commit.
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in METHODS) { result.notImplemented(); return }
        val token = attachment
        val capturedStore = store
        if (token == null || capturedStore == null) {
            result.success(mapOf("status" to "unavailable")); return
        }
        // Codec arguments are an independently decoded message, not a live
        // provider map. Parse/hash/store I/O all run on the bounded worker queue.
        try {
            worker.execute {
                val response = try {
                    if (call.method == READ) {
                        if (call.arguments != null && call.arguments != emptyMap<String, Any>()) mapOf("status" to "invalid")
                        else capturedStore.read().metadata()
                    } else {
                        val request = DuoyiWidgetPublicationRequest.tryFromMap(call.method, call.arguments)
                        if (request == null) mapOf("status" to "invalid")
                        else capturedStore.mutate(request) + mapOf("refreshRequested" to false)
                    }
                } catch (_: Exception) { mapOf("status" to "unavailable") }
                main.post {
                    if (attachment === token) result.success(response)
                }
            }
        } catch (_: RejectedExecutionException) {
            result.success(mapOf("status" to "busy"))
        }
    }

    companion object {
        const val CHANNEL = "duoyi/widget-publication"
        private const val READ = "readWidgetStore"
        private val METHODS = setOf(READ, DuoyiWidgetPublicationRequest.OPEN,
            DuoyiWidgetPublicationRequest.INVALIDATE, DuoyiWidgetPublicationRequest.ADVANCE,
            DuoyiWidgetPublicationRequest.PUBLISH)
        private val worker = ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS,
            ArrayBlockingQueue(128), { runnable -> Thread(runnable, "DuoyiWidgetPublication").apply { isDaemon = true } })
    }
}
