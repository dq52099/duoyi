package com.duoyi.duoyi

import android.content.SharedPreferences
import android.content.res.Configuration
import java.time.Instant
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DuoyiWidgetUpgradeTest {

    @Test
    fun defaultPaletteUsesIosSystemBlueAndPassesWcagReadability() {
        val prefs = InMemoryPrefs()
        val theme = DuoyiWidgetTheme.read(prefs)

        assertFalse(theme.isDark)
        assertEquals(0xFF0066D6.toInt(), theme.primary)
        assertEquals(0xFFF6F7F9.toInt(), theme.background)
        assertEquals(0xFFFFFFFF.toInt(), theme.surface)
        assertEquals(0xFFF1F3F6.toInt(), theme.navBackground)
        assertEquals(0x000066D6, theme.border)
        assertEquals(0xFF1F2933.toInt(), theme.text)
        assertEquals(0xFF667085.toInt(), theme.mutedText)
        assertEquals(0xFFFFFFFF.toInt(), theme.onPrimary)
        assertEquals(0xFF0066D6.toInt(), theme.accentStart)
        assertEquals(0xFF3898FF.toInt(), theme.accentEnd)
        assertEquals(theme.primary, theme.readablePrimary)
        assertEquals(theme.onPrimary, theme.readableOnPrimary)
    }

    @Test
    fun systemNightModeAdaptsDefaultAndLiquidGlassToDarkPalette() {
        for (brand in listOf("defaultBrand", "liquidGlass", "default", "liquid_glass")) {
            val prefs = InMemoryPrefs(mapOf("widget_theme_brand_id" to brand))
            val light = DuoyiWidgetTheme.read(prefs, Configuration.UI_MODE_NIGHT_NO)
            assertFalse("brand=$brand should stay light in day mode", light.isDark)
            assertEquals(0xFF0066D6.toInt(), light.primary)

            val dark = DuoyiWidgetTheme.read(prefs, Configuration.UI_MODE_NIGHT_YES)
            assertTrue("brand=$brand should resolve dark in UI_MODE_NIGHT_YES", dark.isDark)
            assertEquals(0xFF0A84FF.toInt(), dark.primary)
            assertEquals(0xFF14171F.toInt(), dark.background)
            assertEquals(0xFF1C212B.toInt(), dark.surface)
            assertEquals(0xFF242A36.toInt(), dark.navBackground)
            assertEquals(0xFF2F3847.toInt(), dark.border)
            assertEquals(0xFFF2F5FA.toInt(), dark.text)
            assertEquals(0xFFA5B0C2.toInt(), dark.mutedText)
            assertEquals(0xFFFFFFFF.toInt(), dark.onPrimary)
            assertTrue(dark.borderWidthDp >= 1)
        }

        val explicitDark = DuoyiWidgetTheme.read(
            InMemoryPrefs(mapOf("widget_theme_dark" to true)),
            Configuration.UI_MODE_NIGHT_NO,
        )
        assertTrue(explicitDark.isDark)
        assertEquals(0xFF0A84FF.toInt(), explicitDark.primary)
        assertEquals(0xFF14171F.toInt(), explicitDark.background)

        val customBrand = InMemoryPrefs(
            mapOf(
                "widget_theme_brand_id" to "re0",
                "widget_theme_primary" to "#FFAA2233",
                "widget_theme_background" to "#FFFFF0F2",
            ),
        )
        val customNight = DuoyiWidgetTheme.read(customBrand, Configuration.UI_MODE_NIGHT_YES)
        assertFalse(customNight.isDark)
        assertEquals(0xFFAA2233.toInt(), customNight.primary)
        assertEquals(0xFFFFF0F2.toInt(), customNight.background)
    }

    @Test
    fun goalPercentageParserExtractsAndClampsPercentages() {
        assertEquals(68, DuoyiWidgetContent.extractGoalProgressPercent("阅读计划 · 68%"))
        assertEquals(0, DuoyiWidgetContent.extractGoalProgressPercent("New goal 0%"))
        assertEquals(100, DuoyiWidgetContent.extractGoalProgressPercent("Completed 100%"))
        assertEquals(43, DuoyiWidgetContent.extractGoalProgressPercent("Milestone 42.6%"))
        assertEquals(100, DuoyiWidgetContent.extractGoalProgressPercent("Over 145%"))
        assertNull(DuoyiWidgetContent.extractGoalProgressPercent("10/24 due date"))
        assertNull(DuoyiWidgetContent.extractGoalProgressPercent("No percentage"))
        assertNull(DuoyiWidgetContent.extractGoalProgressPercent(null))

        assertEquals(
            68,
            DuoyiWidgetContent.resolveGoalProgressPercent(
                listOf("Keep going", "阅读计划 · 68%", "Done 90%"),
                isFresh = true,
            ),
        )
        assertNull(
            DuoyiWidgetContent.resolveGoalProgressPercent(
                listOf("阅读计划 · 68%"),
                isFresh = false,
            ),
        )
    }

    @Test
    fun focusToggleAndStartActionsAndCalendarTodayDateTarget() {
        assertEquals(
            "duoyi://action/start_pomodoro",
            DuoyiWidgetContent.resolveFocusActionPath(isFresh = true, storedRunning = false, timerRunning = false),
        )
        assertEquals(
            "duoyi://action/toggle_pomodoro",
            DuoyiWidgetContent.resolveFocusActionPath(isFresh = true, storedRunning = true, timerRunning = true),
        )
        assertEquals(
            "duoyi://tab/focus",
            DuoyiWidgetContent.resolveFocusActionPath(isFresh = false, storedRunning = true, timerRunning = true),
        )

        assertEquals(
            "暂停专注",
            DuoyiWidgetCopy.focusControlText(
                sessionTrusted = true,
                expired = false,
                paused = false,
                timerRunning = true,
                countUp = false,
                nextFocusLabel = "25 分钟专注",
                isZh = true,
            ),
        )
        assertEquals(
            "Pause focus",
            DuoyiWidgetCopy.focusControlText(
                sessionTrusted = true,
                expired = false,
                paused = false,
                timerRunning = true,
                countUp = false,
                nextFocusLabel = "25-min focus",
                isZh = false,
            ),
        )
        assertEquals(
            "Resume focus",
            DuoyiWidgetCopy.focusControlText(
                sessionTrusted = true,
                expired = false,
                paused = true,
                timerRunning = false,
                countUp = false,
                nextFocusLabel = "25-min focus",
                isZh = false,
            ),
        )

        val fixedMillis = Instant.parse("2026-11-24T12:00:00Z").toEpochMilli()
        assertEquals(
            "duoyi://calendar?date=2026-11-24",
            DuoyiWidgetContent.calendarTodayTarget(fixedMillis, TimeZone.getTimeZone("UTC")),
        )

        var queue = ""
        queue = DuoyiWidgetContent.appendPendingBgAction(queue, "duoyi://action/complete_todo?id=t1")
        queue = DuoyiWidgetContent.appendPendingBgAction(queue, "duoyi://action/complete_todo?id=t1")
        queue = DuoyiWidgetContent.appendPendingBgAction(queue, "duoyi://action/checkin_habit?id=h1")
        assertEquals(
            "duoyi://action/complete_todo?id=t1\nduoyi://action/checkin_habit?id=h1",
            queue,
        )
    }

    @Test
    fun perWidgetConfigPreferencesPersistModeFooterAndThemeOverrides() {
        val prefs = InMemoryPrefs()
        val widgetId = 1042

        assertTrue(DuoyiWidgetTheme.isBottomNavEnabled(prefs, widgetId))
        assertEquals(DuoyiWidgetTheme.THEME_MODE_SYSTEM, DuoyiWidgetTheme.readThemeMode(null, prefs, widgetId))

        DuoyiWidgetTheme.saveWidgetConfigToPrefs(
            prefs = prefs,
            appWidgetId = widgetId,
            displayMode = "detailed",
            showBottomNav = false,
            themeMode = DuoyiWidgetTheme.THEME_MODE_DARK,
        )

        assertEquals("detailed", prefs.getString("widget_display_mode_$widgetId", null))
        assertFalse(DuoyiWidgetTheme.isBottomNavEnabled(prefs, widgetId))
        assertEquals(DuoyiWidgetTheme.THEME_MODE_DARK, DuoyiWidgetTheme.readThemeMode(null, prefs, widgetId))

        val forcedDark = DuoyiWidgetTheme.read(prefs, Configuration.UI_MODE_NIGHT_NO, appWidgetId = widgetId)
        assertTrue(forcedDark.isDark)
        assertEquals(0xFF0A84FF.toInt(), forcedDark.primary)

        DuoyiWidgetTheme.saveWidgetConfigToPrefs(
            prefs = prefs,
            appWidgetId = widgetId,
            displayMode = "compact",
            showBottomNav = true,
            themeMode = DuoyiWidgetTheme.THEME_MODE_LIGHT,
        )
        assertEquals("compact", prefs.getString("widget_display_mode_$widgetId", null))
        assertTrue(DuoyiWidgetTheme.isBottomNavEnabled(prefs, widgetId))
        val forcedLight = DuoyiWidgetTheme.read(prefs, Configuration.UI_MODE_NIGHT_YES, appWidgetId = widgetId)
        assertFalse(forcedLight.isDark)
        assertEquals(0xFF0066D6.toInt(), forcedLight.primary)
    }

    private class InMemoryPrefs(initial: Map<String, Any?> = emptyMap()) : SharedPreferences {
        private val map = LinkedHashMap<String, Any?>(initial)

        override fun getAll(): MutableMap<String, *> = LinkedHashMap(map)
        override fun getString(key: String?, defValue: String?): String? =
            if (key != null && map.containsKey(key)) map[key] as? String ?: defValue else defValue

        @Suppress("UNCHECKED_CAST")
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
            (map[key] as? Set<String>)?.let { LinkedHashSet(it) } ?: defValues

        override fun getInt(key: String?, defValue: Int): Int = (map[key] as? Int) ?: defValue
        override fun getLong(key: String?, defValue: Long): Long = (map[key] as? Long) ?: defValue
        override fun getFloat(key: String?, defValue: Float): Float = (map[key] as? Float) ?: defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = (map[key] as? Boolean) ?: defValue
        override fun contains(key: String?): Boolean = key != null && map.containsKey(key)
        override fun edit(): SharedPreferences.Editor = EditorImpl(map)
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}

        private class EditorImpl(private val target: MutableMap<String, Any?>) : SharedPreferences.Editor {
            private val pending = LinkedHashMap<String, Any?>()
            private val removals = LinkedHashSet<String>()
            private var clearAll = false

            override fun putString(key: String?, value: String?) = apply { if (key != null) pending[key] = value }
            override fun putStringSet(key: String?, values: MutableSet<String>?) = apply {
                if (key != null) pending[key] = values?.let { LinkedHashSet(it) }
            }
            override fun putInt(key: String?, value: Int) = apply { if (key != null) pending[key] = value }
            override fun putLong(key: String?, value: Long) = apply { if (key != null) pending[key] = value }
            override fun putFloat(key: String?, value: Float) = apply { if (key != null) pending[key] = value }
            override fun putBoolean(key: String?, value: Boolean) = apply { if (key != null) pending[key] = value }
            override fun remove(key: String?) = apply { if (key != null) removals.add(key) }
            override fun clear() = apply { clearAll = true }
            override fun commit(): Boolean {
                apply()
                return true
            }
            override fun apply() {
                if (clearAll) target.clear()
                removals.forEach { target.remove(it) }
                target.putAll(pending)
                pending.clear()
                removals.clear()
                clearAll = false
            }
        }
    }
}
