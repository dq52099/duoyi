package com.duoyi.duoyi

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val platformInfoChannel = "duoyi/platform_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformInfoChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidDeviceInfo" -> {
                        result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "brand" to Build.BRAND,
                                "model" to Build.MODEL,
                                "sdkInt" to Build.VERSION.SDK_INT,
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
