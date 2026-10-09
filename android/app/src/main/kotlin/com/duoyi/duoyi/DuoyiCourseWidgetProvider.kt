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

/** "课程表" 小组件。 */
open class DuoyiCourseWidgetProvider : DuoyiStyledWidgetProvider() {
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
                val views = RemoteViews(context.packageName, R.layout.duoyi_course_widget)
                DuoyiWidgetTheme.applyContainer(
                    context = context,
                    views = views,
                    prefs = prefs,
                    rootId = R.id.widget_course_root,
                    navId = R.id.widget_course_bottom_nav,
                    appWidgetId = id,
                )
                DuoyiWidgetTheme.applyTextColors(
                    views,
                    prefs,
                    primaryIds = intArrayOf(
                        R.id.widget_course_title,
                        R.id.widget_course_nav_calendar,
                    ),
                    bodyIds = intArrayOf(
                        R.id.widget_course_1,
                        R.id.widget_course_2,
                        R.id.widget_course_3,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_course_subtitle,
                        R.id.widget_course_nav_todo,
                        R.id.widget_course_nav_habit,
                        R.id.widget_course_nav_focus,
                    ),
                )

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                views.setTextViewText(
                    R.id.widget_course_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                views.setTextViewText(R.id.widget_course_subtitle, DuoyiWidgetCopy.courseSubtitle(isZh))
                views.setTextViewText(
                    R.id.widget_course_1,
                    DuoyiWidgetCopy.courseHighlight1(prefs.getString("course_highlight_1", null), isZh)
                )
                views.setTextViewText(
                    R.id.widget_course_2,
                    prefs.getString("course_highlight_2", "") ?: ""
                )
                views.setTextViewText(
                    R.id.widget_course_3,
                    prefs.getString("course_highlight_3", "") ?: ""
                )
                views.setViewVisibility(
                    R.id.widget_course_2,
                    DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
                )
                views.setViewVisibility(
                    R.id.widget_course_3,
                    DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
                )
                views.setViewVisibility(
                    R.id.widget_course_bottom_nav,
                    DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
                )

                val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
                val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
                val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
                val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
                views.setTextViewText(R.id.widget_course_nav_todo, tabTodo)
                views.setTextViewText(R.id.widget_course_nav_habit, tabHabit)
                views.setTextViewText(R.id.widget_course_nav_calendar, tabCalendar)
                views.setTextViewText(R.id.widget_course_nav_focus, tabFocus)

                val openCalendar = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
                )
                val openTodo = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
                )
                val openHabit = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
                )
                val openFocus = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
                )

                val openCourse = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://course")
                )

                views.setOnClickPendingIntent(R.id.widget_course_root, openCourse)
                views.setOnClickPendingIntent(R.id.widget_course_title, openCourse)
                views.setOnClickPendingIntent(R.id.widget_course_subtitle, openCourse)
                views.setOnClickPendingIntent(
                    R.id.widget_course_1,
                    itemIntent(context, prefs, "course_highlight_1_id", "duoyi://course")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_course_2,
                    itemIntent(context, prefs, "course_highlight_2_id", "duoyi://course")
                )
                views.setOnClickPendingIntent(
                    R.id.widget_course_3,
                    itemIntent(context, prefs, "course_highlight_3_id", "duoyi://course")
                )
                views.setOnClickPendingIntent(R.id.widget_course_nav_todo, openTodo)
                views.setOnClickPendingIntent(R.id.widget_course_nav_habit, openHabit)
                views.setOnClickPendingIntent(R.id.widget_course_nav_calendar, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_course_nav_focus, openFocus)

                DuoyiWidgetBuiltViews(views)
            }
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
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "course")
        }
    }
}
