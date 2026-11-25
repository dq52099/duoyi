package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
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
        val backing = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetSnapshot.renderWidget(context, appWidgetManager, backing, id,
                DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)) { frame ->
                val prefs = frame.prefs
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
                        R.id.widget_diary_quick_add,
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
                    context = context,
                    appWidgetId = id,
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

                val showQuickAdd = !DuoyiWidgetDisplayMode.isCompact(prefs, id) && frame.fresh
                views.setViewVisibility(R.id.widget_diary_quick_add, if (showQuickAdd) View.VISIBLE else View.GONE)
                views.setContentDescription(R.id.widget_diary_quick_add, DuoyiWidgetCopy.quickAddDiaryDescription(isZh))
                views.setOnClickPendingIntent(
                    R.id.widget_diary_quick_add,
                    if (showQuickAdd) HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        DuoyiWidgetSnapshot.actionUri(frame, Uri.parse("duoyi://action/quick_diary")),
                    ) else openDiary,
                )
                views.setOnClickPendingIntent(R.id.widget_diary_root, openDiary)
                views.setOnClickPendingIntent(R.id.widget_diary_title, openDiary)
                views.setOnClickPendingIntent(R.id.widget_diary_subtitle, openDiary)
                views.setOnClickPendingIntent(
                    R.id.widget_diary_1,
                    itemIntent(context, frame, "diary_highlight_1_id", "duoyi://diary")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_diary_2,
                    itemIntent(context, frame, "diary_highlight_2_id", "duoyi://diary")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_diary_3,
                    itemIntent(context, frame, "diary_highlight_3_id", "duoyi://diary")
                )
                views.setOnClickPendingIntent(R.id.widget_diary_nav_todo, openTodo)
                views.setOnClickPendingIntent(R.id.widget_diary_nav_habit, openHabit)
                views.setOnClickPendingIntent(R.id.widget_diary_nav_calendar, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_diary_nav_focus, openFocus)

                DuoyiWidgetBuiltViews(views)
            }
        }
    }

    companion object {
        private fun itemIntent(context: Context, frame: DuoyiWidgetRenderFrame, key: String, fallback: String) =
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                DuoyiWidgetSnapshot.entityUri(frame, detailUri(frame.prefs, key, fallback), Uri.parse(fallback))
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
