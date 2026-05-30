package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin

class DuoyiTodoCompactWidgetProvider : DuoyiTodoWidgetProvider()
class DuoyiTodoDetailedWidgetProvider : DuoyiTodoWidgetProvider()

class DuoyiFocusHabitCompactWidgetProvider : DuoyiFocusHabitWidgetProvider()
class DuoyiFocusHabitDetailedWidgetProvider : DuoyiFocusHabitWidgetProvider()

class DuoyiHabitCompactWidgetProvider : DuoyiHabitWidgetProvider()
class DuoyiHabitDetailedWidgetProvider : DuoyiHabitWidgetProvider()

class DuoyiCalendarCompactWidgetProvider : DuoyiCalendarWidgetProvider()
class DuoyiCalendarDetailedWidgetProvider : DuoyiCalendarWidgetProvider()

class DuoyiScheduleCompactWidgetProvider : DuoyiScheduleWidgetProvider()
class DuoyiScheduleDetailedWidgetProvider : DuoyiScheduleWidgetProvider()

class DuoyiGoalCompactWidgetProvider : DuoyiGoalWidgetProvider()
class DuoyiGoalDetailedWidgetProvider : DuoyiGoalWidgetProvider()

class DuoyiCourseCompactWidgetProvider : DuoyiCourseWidgetProvider()
class DuoyiCourseDetailedWidgetProvider : DuoyiCourseWidgetProvider()

class DuoyiNoteCompactWidgetProvider : DuoyiNoteWidgetProvider()
class DuoyiNoteDetailedWidgetProvider : DuoyiNoteWidgetProvider()

class DuoyiAnniversaryCompactWidgetProvider : DuoyiAnniversaryWidgetProvider()
class DuoyiAnniversaryDetailedWidgetProvider : DuoyiAnniversaryWidgetProvider()

class DuoyiDiaryCompactWidgetProvider : DuoyiDiaryWidgetProvider()
class DuoyiDiaryDetailedWidgetProvider : DuoyiDiaryWidgetProvider()

object DuoyiWidgetProviderRegistry {
    private const val tag = "DuoyiWidgetPin"
    private const val pendingPrefsName = "duoyi_widget_pin_state"
    private const val pendingVariantProvidersKey = "pending_variant_providers"
    private const val pendingEntrySeparator = "|"
    private const val pendingFieldSeparator = "||"
    private const val pendingVariantProviderTtlMillis = 60 * 1000L

    fun componentFor(context: Context, kind: String, style: String): ComponentName? {
        val family = widgetFamilies.firstOrNull { it.kind == kind } ?: return null
        val provider = when (style) {
            "compact" -> family.compact
            "detailed" -> family.detailed
            else -> family.standard
        }
        return ComponentName(context, provider)
    }

    fun rememberPendingVariantProvider(
        context: Context,
        requestId: String,
        component: ComponentName,
    ) {
        if (!isVariantProvider(component.className)) return
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        pending.add(pendingEntry(requestId, component, System.currentTimeMillis()))
        Log.i(
            tag,
            "remember_pending requestId=$requestId provider=${component.className} pendingCount=${pending.size}",
        )
        prefs.edit()
            .putStringSet(pendingVariantProvidersKey, pending)
            .apply()
    }

    fun clearPendingVariantProvider(context: Context, requestId: String, component: ComponentName) {
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        val removed = pending.removeAll {
            pendingRequestId(it) == requestId && pendingComponent(it) == component
        } || pending.remove(component.flattenToString())
        if (removed) {
            Log.i(
                tag,
                "clear_pending requestId=$requestId provider=${component.className} pendingCount=${pending.size}",
            )
            prefs.edit()
                .putStringSet(pendingVariantProvidersKey, pending)
                .apply()
        }
    }

    fun cleanupPendingVariantProvider(context: Context, requestId: String) {
        if (requestId.isBlank()) return
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        val match = pending.firstOrNull { pendingRequestId(it) == requestId } ?: return
        val component = pendingComponent(match)
        if (component != null && isVariantProvider(component.className)) {
            disableVariantProviderIfUnused(context, component)
        }
        pending.remove(match)
        Log.i(
            tag,
            "cleanup_pending requestId=$requestId provider=${component?.className.orEmpty()} pendingCount=${pending.size}",
        )
        prefs.edit()
            .putStringSet(pendingVariantProvidersKey, pending)
            .apply()
    }

    fun cleanupPendingVariantProviders(context: Context) {
        cleanupExpiredPendingVariantProviders(context)
    }

    fun cleanupExpiredPendingVariantProviders(context: Context) {
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        if (pending.isEmpty()) return

        val now = System.currentTimeMillis()
        for (flattened in pending.toList()) {
            val component = pendingComponent(flattened)
            if (component == null || !isVariantProvider(component.className)) {
                pending.remove(flattened)
                continue
            }
            val createdAt = pendingCreatedAt(flattened)
            if (createdAt != null && now - createdAt < pendingVariantProviderTtlMillis) {
                continue
            }
            Log.i(
                tag,
                "cleanup_expired_pending requestId=${pendingRequestId(flattened)} provider=${component.className} ageMs=${createdAt?.let { now - it } ?: -1}",
            )
            disableVariantProviderIfUnused(context, component)
            pending.remove(flattened)
        }
        prefs.edit()
            .putStringSet(pendingVariantProvidersKey, pending)
            .apply()
    }

    private fun pendingEntry(requestId: String, component: ComponentName): String {
        return pendingEntry(requestId, component, null)
    }

    private fun pendingEntry(requestId: String, component: ComponentName, createdAt: Long?): String {
        val base = "$requestId$pendingEntrySeparator${component.flattenToString()}"
        return if (createdAt == null) base else "$base$pendingFieldSeparator$createdAt"
    }

    private fun pendingRequestId(entry: String): String {
        return entry.substringBefore(pendingEntrySeparator, "")
    }

    private fun pendingComponent(entry: String): ComponentName? {
        val withoutMetadata = entry.substringBefore(pendingFieldSeparator)
        val flattened = if (entry.contains(pendingEntrySeparator)) {
            withoutMetadata.substringAfter(pendingEntrySeparator)
        } else {
            withoutMetadata
        }
        return ComponentName.unflattenFromString(flattened)
    }

    private fun pendingCreatedAt(entry: String): Long? {
        return entry.substringAfter(pendingFieldSeparator, "").toLongOrNull()
    }

    fun kindForProvider(providerClassName: String?): String? {
        return widgetFamilies.firstOrNull { family ->
            family.providerClasses.any { it.name == providerClassName }
        }?.kind
    }

    fun styleForProvider(providerClassName: String?): String? {
        val family = widgetFamilies.firstOrNull { widgetFamily ->
            widgetFamily.providerClasses.any { it.name == providerClassName }
        } ?: return null
        return when (providerClassName) {
            family.compact.name -> "compact"
            family.standard.name -> "standard"
            family.detailed.name -> "detailed"
            else -> null
        }
    }

    fun isVariantProvider(providerClassName: String?): Boolean {
        val family = widgetFamilies.firstOrNull { widgetFamily ->
            widgetFamily.providerClasses.any { it.name == providerClassName }
        } ?: return false
        return providerClassName == family.compact.name ||
            providerClassName == family.detailed.name
    }

    fun disableVariantProviderIfUnused(context: Context, component: ComponentName): Boolean {
        if (!isVariantProvider(component.className)) return false
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(component)
        if (ids.isNotEmpty()) {
            Log.i(
                tag,
                "keep_variant_provider provider=${component.className} widgetCount=${ids.size}",
            )
            return false
        }
        context.packageManager.setComponentEnabledSetting(
            component,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
        Log.i(tag, "disable_variant_provider provider=${component.className} widgetCount=0")
        return true
    }

    fun scheduleDisableVariantProviderIfUnused(
        context: Context,
        component: ComponentName,
        delayMillis: Long = 15_000L,
    ) {
        if (!isVariantProvider(component.className)) return
        val appContext = context.applicationContext
        Log.i(
            tag,
            "schedule_disable_variant_provider provider=${component.className} delayMs=$delayMillis",
        )
        Handler(Looper.getMainLooper()).postDelayed({
            disableVariantProviderIfUnused(appContext, component)
        }, delayMillis)
    }

    fun requestUpdateForProvider(context: Context, providerClassName: String?) {
        val kind = kindForProvider(providerClassName) ?: return
        requestUpdateForKind(context, kind)
    }

    fun requestUpdateForKind(context: Context, kind: String) {
        val family = widgetFamilies.firstOrNull { it.kind == kind } ?: return
        requestUpdate(context, family.providerClasses)
    }

    fun requestUpdate(context: Context, providerClasses: List<Class<out AppWidgetProvider>>) {
        val manager = AppWidgetManager.getInstance(context)
        for (providerClass in providerClasses) {
            val component = ComponentName(context, providerClass)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) continue
            val intent = Intent(context, providerClass).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }

    fun applyDisplayModeToExistingWidgets(context: Context, styleId: String?): Int {
        val style = DuoyiWidgetPinStyle.fromId(styleId)
        val manager = AppWidgetManager.getInstance(context)
        val prefs = HomeWidgetPlugin.getData(context)
        var appliedCount = 0
        for (family in widgetFamilies) {
            for (providerClass in family.providerClasses) {
                val component = ComponentName(context, providerClass)
                val ids = manager.getAppWidgetIds(component)
                if (ids.isEmpty()) continue
                for (id in ids) {
                    if (id == AppWidgetManager.INVALID_APPWIDGET_ID) continue
                    DuoyiWidgetDisplayMode.saveForWidget(prefs, id, style.id)
                    manager.updateAppWidgetOptions(id, style.toOptions())
                    appliedCount += 1
                    Log.i(
                        tag,
                        "apply_display_mode widgetId=$id provider=${component.className} normalizedStyle=${style.id}",
                    )
                }
            }
            requestUpdate(context, family.providerClasses)
        }
        return appliedCount
    }

    private data class WidgetFamily(
        val kind: String,
        val standard: Class<out AppWidgetProvider>,
        val compact: Class<out AppWidgetProvider>,
        val detailed: Class<out AppWidgetProvider>,
    ) {
        val providerClasses: List<Class<out AppWidgetProvider>>
            get() = listOf(standard, compact, detailed)
    }

    private val widgetFamilies = listOf(
        WidgetFamily(
            "todo",
            DuoyiTodoWidgetProvider::class.java,
            DuoyiTodoCompactWidgetProvider::class.java,
            DuoyiTodoDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "focus",
            DuoyiFocusHabitWidgetProvider::class.java,
            DuoyiFocusHabitCompactWidgetProvider::class.java,
            DuoyiFocusHabitDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "habit",
            DuoyiHabitWidgetProvider::class.java,
            DuoyiHabitCompactWidgetProvider::class.java,
            DuoyiHabitDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "calendar",
            DuoyiCalendarWidgetProvider::class.java,
            DuoyiCalendarCompactWidgetProvider::class.java,
            DuoyiCalendarDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "schedule",
            DuoyiScheduleWidgetProvider::class.java,
            DuoyiScheduleCompactWidgetProvider::class.java,
            DuoyiScheduleDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "goal",
            DuoyiGoalWidgetProvider::class.java,
            DuoyiGoalCompactWidgetProvider::class.java,
            DuoyiGoalDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "course",
            DuoyiCourseWidgetProvider::class.java,
            DuoyiCourseCompactWidgetProvider::class.java,
            DuoyiCourseDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "note",
            DuoyiNoteWidgetProvider::class.java,
            DuoyiNoteCompactWidgetProvider::class.java,
            DuoyiNoteDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "anniversary",
            DuoyiAnniversaryWidgetProvider::class.java,
            DuoyiAnniversaryCompactWidgetProvider::class.java,
            DuoyiAnniversaryDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "diary",
            DuoyiDiaryWidgetProvider::class.java,
            DuoyiDiaryCompactWidgetProvider::class.java,
            DuoyiDiaryDetailedWidgetProvider::class.java,
        ),
    )
}
