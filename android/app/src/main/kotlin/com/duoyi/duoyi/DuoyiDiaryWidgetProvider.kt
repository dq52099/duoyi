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

/** "日记" 小组件。 */
open class DuoyiDiaryWidgetProvider : DuoyiStyledWidgetProvider() {
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
        val prefs: SharedPreferences = DuoyiWidgetSnapshot.forDisplay(context, HomeWidgetPlugin.getData(context))

        appWidgetIds.forEach { id ->
            DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)?.let { style ->
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)
            }
            val views = RemoteViews(context.packageName, R.layout.duoyi_diary_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_diary_root,
                navId = R.id.widget_diary_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_diary_title,
                    R.id.widget_diary_nav_calendar,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_diary_1,
                    R.id.widget_diary_2,
                    R.id.widget_diary_3,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_diary_subtitle,
                    R.id.widget_diary_nav_todo,
                    R.id.widget_diary_nav_habit,
                    R.id.widget_diary_nav_focus,
                ),
            )

            val isZh = DuoyiWidgetCopy.isZh(prefs)
            views.setTextViewText(
                R.id.widget_diary_title,
                DuoyiWidgetCopy.appTitle(prefs, isZh)
            )
            views.setTextViewText(R.id.widget_diary_subtitle, DuoyiWidgetCopy.diarySubtitle(isZh))
            views.setTextViewText(
                R.id.widget_diary_1,
                DuoyiWidgetCopy.diaryHighlight1(prefs.getString("diary_highlight_1", null), isZh)
            )
            views.setTextViewText(
                R.id.widget_diary_2,
                prefs.getString("diary_highlight_2", "") ?: ""
            )
            views.setTextViewText(
                R.id.widget_diary_3,
                prefs.getString("diary_highlight_3", "") ?: ""
            )
            views.setViewVisibility(
                R.id.widget_diary_2,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_diary_3,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_diary_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            views.setTextViewText(R.id.widget_diary_nav_todo, DuoyiWidgetCopy.navTodo(prefs, isZh))
            views.setTextViewText(R.id.widget_diary_nav_habit, DuoyiWidgetCopy.navHabit(prefs, isZh))
            views.setTextViewText(R.id.widget_diary_nav_calendar, DuoyiWidgetCopy.navCalendar(prefs, isZh))
            views.setTextViewText(R.id.widget_diary_nav_focus, DuoyiWidgetCopy.navFocus(prefs, isZh))

            val openDiary = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://diary")
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

            views.setOnClickPendingIntent(R.id.widget_diary_root, openDiary)
            views.setOnClickPendingIntent(R.id.widget_diary_title, openDiary)
            views.setOnClickPendingIntent(R.id.widget_diary_subtitle, openDiary)
            views.setOnClickPendingIntent(
                R.id.widget_diary_1,
                itemIntent(context, prefs, "diary_highlight_1_id", "duoyi://diary")
            )
            views.setOnClickPendingIntent(
                R.id.widget_diary_2,
                itemIntent(context, prefs, "diary_highlight_2_id", "duoyi://diary")
            )
            views.setOnClickPendingIntent(
                R.id.widget_diary_3,
                itemIntent(context, prefs, "diary_highlight_3_id", "duoyi://diary")
            )
            views.setOnClickPendingIntent(R.id.widget_diary_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_diary_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_diary_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_diary_nav_focus, openFocus)

            DuoyiWidgetSnapshot.finishRender(context, views, prefs, id)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        private fun itemIntent(context: Context, prefs: SharedPreferences, key: String, fallback: String) =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                detailUri(prefs, key, fallback)
            )

        private fun detailUri(prefs: SharedPreferences, key: String, fallback: String): Uri {
            val rawId = prefs.getString(key, "")?.trim().orEmpty()
            if (rawId.isBlank()) return Uri.parse(fallback)
            if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)
            return Uri.parse("$fallback/${Uri.encode(rawId)}")
        }

        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "diary")
        }
    }
}
