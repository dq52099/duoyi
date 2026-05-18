package com.duoyi.duoyi

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val platformInfoChannel = "duoyi/platform_info"
    private val updateChannel = "duoyi/update"
    private val notificationSettingsChannel = "duoyi/notification_settings"
    private val reminderRingtoneChannel = "duoyi/reminder_ringtone"

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
                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            result.success(manager.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(canInstall)
                    }
                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "APK 路径为空", null)
                            return@setMethodCallHandler
                        }
                        val source = File(path)
                        if (!source.exists()) {
                            result.error("missing_apk", "APK 文件不存在: $path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = prepareApkForInstall(source)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: IllegalArgumentException) {
                            result.error("file_provider_root", "安装包路径无法授权: ${e.message}", null)
                        } catch (e: IOException) {
                            result.error("prepare_apk_failed", "准备安装包失败: ${e.message}", null)
                        } catch (e: Exception) {
                            result.error("install_failed", "打开安装器失败: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationSettingsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppNotificationSettings" -> {
                        result.success(openAppNotificationSettings())
                    }
                    "openNotificationChannelSettings" -> {
                        val channelId = call.argument<String>("channelId")
                        result.success(openNotificationChannelSettings(channelId))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, reminderRingtoneChannel)
            .setMethodCallHandler { call, result ->
                val id = call.argument<Int>("id") ?: 0
                val title = call.argument<String>("title") ?: "多仪提醒"
                val body = call.argument<String>("body") ?: "提醒时间到了"
                val payload = call.argument<String>("payload")
                when (call.method) {
                    "showNow" -> {
                        ReminderRingtoneScheduler.showNow(this, id, title, body, payload)
                        result.success(null)
                    }
                    "scheduleOnce" -> {
                        val triggerAtMillis = call.argument<Long>("triggerAtMillis")
                            ?: call.argument<Int>("triggerAtMillis")?.toLong()
                            ?: 0L
                        ReminderRingtoneScheduler.scheduleOnce(
                            this,
                            id,
                            title,
                            body,
                            triggerAtMillis,
                            payload,
                        )
                        result.success(null)
                    }
                    "scheduleDaily" -> {
                        val hour = call.argument<Int>("hour") ?: 9
                        val minute = call.argument<Int>("minute") ?: 0
                        val weekdays = call.argument<List<Int>>("weekdays")
                            ?.toIntArray()
                            ?: intArrayOf()
                        val timezoneId = call.argument<String>("timezoneId") ?: "Asia/Shanghai"
                        ReminderRingtoneScheduler.scheduleDaily(
                            this,
                            id,
                            title,
                            body,
                            hour,
                            minute,
                            weekdays,
                            timezoneId,
                            payload,
                        )
                        result.success(null)
                    }
                    "cancel" -> {
                        ReminderRingtoneScheduler.cancel(this, id)
                        result.success(null)
                    }
                    "cancelAll" -> {
                        ReminderRingtoneScheduler.cancelAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openAppNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun openNotificationChannelSettings(channelId: String?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || channelId.isNullOrBlank()) {
            return openAppNotificationSettings()
        }
        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun startSettingsActivity(intent: Intent): Boolean {
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    @Throws(IOException::class)
    private fun prepareApkForInstall(source: File): File {
        val updateDir = File(cacheDir, "updates")
        if (!updateDir.exists() && !updateDir.mkdirs()) {
            throw IOException("无法创建更新缓存目录")
        }

        val safeName = source.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "duoyi-update.apk" }
        val target = File(updateDir, safeName)
        val sourceCanonical = source.canonicalFile
        val targetCanonical = target.canonicalFile
        if (sourceCanonical.path == targetCanonical.path) {
            return targetCanonical
        }

        sourceCanonical.inputStream().use { input ->
            targetCanonical.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        return targetCanonical
    }
}
