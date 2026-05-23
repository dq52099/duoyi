package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.app.Activity
import android.app.AppOpsManager
import android.content.ComponentName
import android.app.NotificationManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.duoyi.duoyi.services.FocusSoundForegroundService
import java.io.File
import java.io.IOException
import java.util.TimeZone
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val platformInfoChannel = "duoyi/platform_info"
    private val updateChannel = "duoyi/update"
    private val notificationSettingsChannel = "duoyi/notification_settings"
    private val reminderRingtoneChannel = "duoyi/reminder_ringtone"
    private val focusSoundForegroundChannel = "duoyi/focus_sound_foreground"
    private val focusDndChannel = "duoyi/focus_dnd"
    private val focusDistractionChannel = "duoyi/focus_distraction"
    private val widgetsChannel = "duoyi/widgets"
    private val locationGeofenceChannel = "duoyi/location_geofence"
    private val noteAttachmentPickerChannel = "duoyi/note_attachment_picker"
    private val deepLinksChannel = "duoyi/deep_links"
    private val pickNoteAttachmentRequest = 7301
    private var pendingNoteAttachmentPick: MethodChannel.Result? = null
    private var deepLinksMethodChannel: MethodChannel? = null
    private var pendingInitialDeepLink: String? = null
    private var pendingInitialOAuthLink: String? = null
    private var pendingInitialSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopReminderRingtoneIfRequested(intent)
        pendingInitialDeepLink = duoyiDeepLinkFrom(intent)
        pendingInitialOAuthLink = oauthDeepLinkFrom(intent)
        pendingInitialSharedText = sharedTextFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        stopReminderRingtoneIfRequested(intent)
        val deepLink = duoyiDeepLinkFrom(intent)
        val link = oauthDeepLinkFrom(intent)
        val sharedText = sharedTextFrom(intent)
        val channel = deepLinksMethodChannel
        if (channel == null) {
            if (deepLink != null) pendingInitialDeepLink = deepLink
            if (link != null) pendingInitialOAuthLink = link
            if (sharedText != null) pendingInitialSharedText = sharedText
        } else {
            if (deepLink != null) channel.invokeMethod("onLink", deepLink)
            if (sharedText != null) channel.invokeMethod("onSharedText", sharedText)
        }
    }

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
                    "getSystemTimeZoneId" -> {
                        result.success(TimeZone.getDefault().id)
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
                val vibrate = call.argument<Boolean>("vibrate") ?: true
                val snoozeMinutes = call.argument<Int>("snoozeMinutes") ?: 0
                val repeatCount = call.argument<Int>("repeatCount") ?: 0
                when (call.method) {
                    "showNow" -> {
                        ReminderRingtoneScheduler.showNow(this, id, title, body, payload, vibrate, snoozeMinutes, repeatCount)
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
                            vibrate,
                            snoozeMinutes,
                            repeatCount,
                        )
                        result.success(null)
                    }
                    "scheduleDaily" -> {
                        val hour = call.argument<Int>("hour") ?: 9
                        val minute = call.argument<Int>("minute") ?: 0
                        val weekdays = call.argument<List<Int>>("weekdays")
                            ?.toIntArray()
                            ?: intArrayOf()
                        val timezoneId = call.argument<String>("timezoneId")
                            ?: TimeZone.getDefault().id
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
                            vibrate,
                            snoozeMinutes,
                            repeatCount,
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
                    "stopActive" -> {
                        ReminderRingtoneScheduler.stopActiveRingtone(this)
                        result.success(null)
                    }
                    "setVolumePercent" -> {
                        val volume = call.argument<Int>("volumePercent") ?: 60
                        ReminderRingtoneService.setVolumePercent(this, volume)
                        result.success(null)
                    }
                    "setSoundName" -> {
                        val soundName = call.argument<String>("soundName") ?: "chime"
                        ReminderRingtoneService.setSoundName(this, soundName)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, focusSoundForegroundChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        FocusSoundForegroundService.start(this)
                        result.success(null)
                    }
                    "stop" -> {
                        FocusSoundForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, focusDndChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(focusDndStatus())
                    "openPolicyAccessSettings" -> {
                        result.success(openNotificationPolicyAccessSettings())
                    }
                    "enableDnd" -> {
                        val filter = call.argument<Int>("filter")
                            ?: NotificationManager.INTERRUPTION_FILTER_PRIORITY
                        result.success(enableFocusDnd(filter))
                    }
                    "restoreDnd" -> {
                        val previousFilter = call.argument<Int>("previousFilter")
                            ?: NotificationManager.INTERRUPTION_FILTER_ALL
                        result.success(restoreFocusDnd(previousFilter))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, focusDistractionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> {
                        result.success(
                            mapOf(
                                "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP),
                                "accessGranted" to hasUsageStatsAccess(),
                                "accessibilityGranted" to hasFocusBlockerAccessibilityAccess(),
                                "blockerConfigured" to FocusBlockerStore.isConfigured(this),
                                "lastBlockedPackage" to FocusBlockerStore.lastBlockedPackage(this),
                                "lastBlockedAt" to FocusBlockerStore.lastBlockedAt(this),
                                "foregroundPackage" to foregroundPackageName(),
                            ),
                        )
                    }
                    "getForegroundApp" -> result.success(foregroundPackageName())
                    "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
                    "openAccessibilitySettings" -> result.success(openAccessibilitySettings())
                    "setFocusBlocker" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val packages = call.argument<List<String>>("packages")
                            ?.map { it.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?.toSet()
                            ?: emptySet()
                        FocusBlockerStore.setConfig(this, enabled, packages)
                        result.success(FocusBlockerStore.isConfigured(this))
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canRequestPinWidget" -> result.success(canRequestPinWidget())
                    "requestPinWidget" -> {
                        val kind = call.argument<String>("kind") ?: "todo"
                        result.success(requestPinWidget(kind))
                    }
                    "openWidgetSettings" -> result.success(openWidgetSettings())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationGeofenceChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncReminders" -> {
                        val args = call.arguments as? Map<*, *>
                        val raw = args?.get("reminders") as? List<*> ?: emptyList<Any>()
                        val reminders = raw.mapNotNull {
                            LocationGeofenceScheduler.parseReminder(it as? Map<*, *> ?: return@mapNotNull null)
                        }
                        LocationGeofenceScheduler.syncReminders(
                            this,
                            reminders,
                            onResult = { result.success(it) },
                            onError = { code, message -> result.error(code, message, null) },
                        )
                    }
                    "clearReminders" -> {
                        LocationGeofenceScheduler.clearReminders(this) {
                            result.success(it)
                        }
                    }
                    "openLocationSettings" -> {
                        result.success(openLocationSettings())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, noteAttachmentPickerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> pickNoteAttachment(result)
                    else -> result.notImplemented()
                }
            }
        deepLinksMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deepLinksChannel,
        )
        deepLinksMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialLink" -> {
                    val link = pendingInitialDeepLink
                    pendingInitialDeepLink = null
                    if (link != null && link == pendingInitialOAuthLink) {
                        pendingInitialOAuthLink = null
                    }
                    result.success(link)
                }
                "takeInitialOAuthLink" -> {
                    val link = pendingInitialOAuthLink
                    pendingInitialOAuthLink = null
                    result.success(link)
                }
                "takeInitialSharedText" -> {
                    val text = pendingInitialSharedText
                    pendingInitialSharedText = null
                    result.success(text)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android framework, kept for FlutterActivity compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickNoteAttachmentRequest) return
        val pending = pendingNoteAttachmentPick ?: return
        pendingNoteAttachmentPick = null
        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            pending.success(null)
            return
        }
        runCatching {
            val flags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (flags != 0) {
                contentResolver.takePersistableUriPermission(uri, flags)
            }
        }
        pending.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to displayNameFor(uri),
                "mimeType" to (contentResolver.getType(uri) ?: ""),
            ),
        )
    }

    private fun stopReminderRingtone() {
        runCatching {
            stopService(Intent(this, ReminderRingtoneService::class.java))
        }
    }

    private fun stopReminderRingtoneIfRequested(intent: Intent?) {
        val explicitStop = intent?.getBooleanExtra(ReminderRingtoneService.extraStopRingtone, false) == true
        val opensDuoyiReminderTarget = duoyiDeepLinkFrom(intent) != null
        if (explicitStop || opensDuoyiReminderTarget) {
            stopReminderRingtone()
        }
    }

    private fun duoyiDeepLinkFrom(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        if (uri.scheme != "duoyi") return null
        return uri.toString()
    }

    private fun oauthDeepLinkFrom(intent: Intent?): String? {
        val raw = duoyiDeepLinkFrom(intent) ?: return null
        val uri = Uri.parse(raw)
        if (uri.host != "oauth") return null
        return uri.toString()
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.trim()
            ?: return null
        return text.ifEmpty { null }
    }

    private fun canRequestPinWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(AppWidgetManager::class.java)
        return manager?.isRequestPinAppWidgetSupported == true
    }

    private fun requestPinWidget(kind: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(AppWidgetManager::class.java) ?: return false
        if (!manager.isRequestPinAppWidgetSupported) return false
        val provider = when (kind) {
            "todo" -> ComponentName(this, DuoyiTodoWidgetProvider::class.java)
            "focus" -> ComponentName(this, DuoyiFocusHabitWidgetProvider::class.java)
            "habit" -> ComponentName(this, DuoyiHabitWidgetProvider::class.java)
            "calendar" -> ComponentName(this, DuoyiCalendarWidgetProvider::class.java)
            "schedule" -> ComponentName(this, DuoyiScheduleWidgetProvider::class.java)
            "goal" -> ComponentName(this, DuoyiGoalWidgetProvider::class.java)
            "course" -> ComponentName(this, DuoyiCourseWidgetProvider::class.java)
            "note" -> ComponentName(this, DuoyiNoteWidgetProvider::class.java)
            "anniversary" -> ComponentName(this, DuoyiAnniversaryWidgetProvider::class.java)
            "diary" -> ComponentName(this, DuoyiDiaryWidgetProvider::class.java)
            else -> return false
        }
        return try {
            manager.requestPinAppWidget(provider, null, null)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openWidgetSettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_SETTINGS),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
        )
        return intents.any { startSettingsActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    private fun openLocationSettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
        )
        return intents.any { startSettingsActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    private fun pickNoteAttachment(result: MethodChannel.Result) {
        if (pendingNoteAttachmentPick != null) {
            result.error("pick_in_progress", "已有文件选择器正在打开", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
            .putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("image/*", "application/pdf", "text/*", "application/*"),
            )
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        pendingNoteAttachmentPick = result
        try {
            startActivityForResult(intent, pickNoteAttachmentRequest)
        } catch (e: Exception) {
            pendingNoteAttachmentPick = null
            result.error("pick_failed", "无法打开系统文件选择器: ${e.message}", null)
        }
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val name = cursor.getString(index)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        return uri.lastPathSegment ?: "附件"
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

    private fun notificationManager(): NotificationManager {
        return getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    private fun hasNotificationPolicyAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return notificationManager().isNotificationPolicyAccessGranted
    }

    private fun focusDndStatus(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "supported" to false,
                "accessGranted" to false,
                "currentFilter" to null,
            )
        }
        val manager = notificationManager()
        return mapOf(
            "supported" to true,
            "accessGranted" to manager.isNotificationPolicyAccessGranted,
            "currentFilter" to manager.currentInterruptionFilter,
        )
    }

    private fun openNotificationPolicyAccessSettings(): Boolean {
        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun enableFocusDnd(filter: Int): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return mapOf(
                "enabled" to false,
                "previousFilter" to null,
                "currentFilter" to null,
            )
        }
        val manager = notificationManager()
        if (!hasNotificationPolicyAccess()) {
            return mapOf(
                "enabled" to false,
                "previousFilter" to manager.currentInterruptionFilter,
                "currentFilter" to manager.currentInterruptionFilter,
            )
        }
        val previousFilter = manager.currentInterruptionFilter
        manager.setInterruptionFilter(filter)
        return mapOf(
            "enabled" to true,
            "previousFilter" to previousFilter,
            "currentFilter" to manager.currentInterruptionFilter,
        )
    }

    private fun restoreFocusDnd(previousFilter: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (!hasNotificationPolicyAccess()) return false
        notificationManager().setInterruptionFilter(previousFilter)
        return true
    }

    private fun hasUsageStatsAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun foregroundPackageName(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return null
        if (!hasUsageStatsAccess()) return null
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val start = end - 10 * 60 * 1000L
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
        return stats
            ?.filter { it.lastTimeUsed > 0 }
            ?.maxByOrNull { it.lastTimeUsed }
            ?.packageName
    }

    private fun openUsageAccessSettings(): Boolean {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun openAccessibilitySettings(): Boolean {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSettingsActivity(intent)
    }

    private fun hasFocusBlockerAccessibilityAccess(): Boolean {
        val expected = ComponentName(
            this,
            DuoyiFocusBlockerAccessibilityService::class.java,
        ).flattenToString()
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabledServices.split(':').any { it.equals(expected, ignoreCase = true) }
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
