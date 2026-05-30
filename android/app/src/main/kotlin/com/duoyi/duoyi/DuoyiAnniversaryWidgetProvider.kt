package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/** "纪念日" 小组件。 */
open class DuoyiAnniversaryWidgetProvider : DuoyiStyledWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            requestUpdate(context)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = HomeWidgetPlugin.getData(context)
        appWidgetIds.forEach { DuoyiWidgetDisplayMode.clearForWidget(prefs, it) }
        super.onDeleted(context, appWidgetIds)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)?.let { style ->
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)
            }
            val views = RemoteViews(context.packageName, R.layout.duoyi_anniversary_widget)

            views.setTextViewText(
                R.id.widget_anniversary_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_anniversary_subtitle, "纪念日")
            views.setTextViewText(
                R.id.widget_anniversary_1,
                highlightText(
                    prefs,
                    "anniversary_highlight_1",
                    "memorial_highlight_1",
                    "· 暂无近期纪念日"
                )
            )
            views.setTextViewText(
                R.id.widget_anniversary_2,
                highlightText(prefs, "anniversary_highlight_2", "memorial_highlight_2", "")
            )
            views.setTextViewText(
                R.id.widget_anniversary_3,
                highlightText(prefs, "anniversary_highlight_3", "memorial_highlight_3", "")
            )
            views.setViewVisibility(
                R.id.widget_anniversary_2,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_anniversary_3,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_anniversary_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_anniversary_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_anniversary_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_anniversary_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_anniversary_nav_focus, tabFocus)

            val openAnniversary = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://anniversary")
            )
            val openTodo = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
            )
            val openHabit = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
            )
            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            val openFocus = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
            )

            views.setOnClickPendingIntent(R.id.widget_anniversary_root, openAnniversary)
            views.setOnClickPendingIntent(R.id.widget_anniversary_title, openAnniversary)
            views.setOnClickPendingIntent(R.id.widget_anniversary_subtitle, openAnniversary)
            views.setOnClickPendingIntent(
                R.id.widget_anniversary_1,
                itemIntent(context, prefs, "memorial_highlight_1_id", "duoyi://anniversary")
            )
            views.setOnClickPendingIntent(
                R.id.widget_anniversary_2,
                itemIntent(context, prefs, "memorial_highlight_2_id", "duoyi://anniversary")
            )
            views.setOnClickPendingIntent(
                R.id.widget_anniversary_3,
                itemIntent(context, prefs, "memorial_highlight_3_id", "duoyi://anniversary")
            )
            views.setOnClickPendingIntent(R.id.widget_anniversary_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_anniversary_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_anniversary_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_anniversary_nav_focus, openFocus)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        private fun highlightText(
            prefs: SharedPreferences,
            primaryKey: String,
            fallbackKey: String,
            fallback: String
        ): String {
            return prefs.getString(primaryKey, null)
                ?: prefs.getString(fallbackKey, fallback)
                ?: fallback
        }

        private fun itemIntent(
            context: Context,
            prefs: SharedPreferences,
            key: String,
            fallback: String
        ) =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                detailUri(prefs, key, fallback)
            )

        private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
            val primaryKey = anniversaryPrimaryKey(key)
            val fallbackKey = key
            return detailUri(prefs, primaryKey, fallbackKey, fallback)
        }

        private fun detailUri(
            prefs: SharedPreferences,
            primaryKey: String,
            fallbackKey: String,
            fallback: String
        ): Uri {
            val rawId = (
                prefs.getString(primaryKey, null)
                    ?: prefs.getString(fallbackKey, "")
                )?.trim().orEmpty()
            if (rawId.isBlank()) return Uri.parse(fallback)
            if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)
            return Uri.parse("$fallback/${Uri.encode(rawId)}")
        }

        private fun anniversaryPrimaryKey(key: String): String {
            return when (key) {
                "memorial_highlight_1_id" -> "anniversary_highlight_1_id"
                "memorial_highlight_2_id" -> "anniversary_highlight_2_id"
                "memorial_highlight_3_id" -> "anniversary_highlight_3_id"
                else -> key.replace("memorial_", "anniversary_")
            }
        }

        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "anniversary")
        }
    }
}
