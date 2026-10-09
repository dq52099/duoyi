package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.Calendar

/** "月历" 小组件。 */
open class DuoyiCalendarWidgetProvider : DuoyiStyledWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_calendar_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_calendar_root,
                navId = R.id.widget_calendar_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_calendar_title,
                    R.id.widget_calendar_summary,
                    R.id.widget_calendar_today_button,
                    R.id.widget_calendar_nav_calendar,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_calendar_grid,
                    R.id.widget_calendar_event_summary,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_calendar_month,
                    R.id.widget_calendar_nav_todo,
                    R.id.widget_calendar_nav_habit,
                    R.id.widget_calendar_nav_focus,
                ),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                secondaryIds = intArrayOf(R.id.widget_calendar_today_button),
            )
            val isZh = DuoyiWidgetCopy.isZh(prefs)
            val now = Calendar.getInstance()
            val height = appWidgetManager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val compact = DuoyiWidgetDisplayMode.isCompact(prefs, id) || height in 1..129
            val detailed = DuoyiWidgetDisplayMode.isDetailed(prefs, id) && (height == 0 || height >= 180)
            val monthTitle = DuoyiWidgetCopy.calendarMonthTitle(now, compact, isZh)

            views.setViewVisibility(
                R.id.widget_calendar_title,
                if (compact) View.GONE else View.VISIBLE
            )
            views.setTextViewText(
                R.id.widget_calendar_title,
                DuoyiWidgetCopy.appTitle(prefs, isZh)
            )
            views.setTextViewText(R.id.widget_calendar_month, monthTitle)
            views.setTextViewText(R.id.widget_calendar_today_button, DuoyiWidgetCopy.calendarTodayButton(isZh))
            views.setTextViewText(
                R.id.widget_calendar_grid,
                buildMonthGridSpan(prefs, now, compact, detailed, isZh)
            )
            views.setTextViewTextSize(
                R.id.widget_calendar_grid,
                TypedValue.COMPLEX_UNIT_SP,
                if (compact) 8.5f else if (detailed) 12f else 11f
            )
            views.setTextViewText(
                R.id.widget_calendar_summary,
                DuoyiWidgetCopy.calendarMonthSummary(prefs.getString("calendar_month_summary", null), isZh)
            )
            views.setViewVisibility(
                R.id.widget_calendar_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )

            val rawEventSummary = prefs.getString("today_event_summary", null)
            val rawSchedule1Id = prefs.getString("schedule_highlight_1_id", null)
            val isFresh = DuoyiWidgetSnapshot.isFresh(prefs)
            val summaryResult = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                rawSummary = rawEventSummary,
                rawSchedule1Id = rawSchedule1Id,
                isFresh = isFresh,
                isZh = isZh,
            )
            val canFitEventSummary = !compact && (height == 0 || height >= 140)

            if (summaryResult.summary != null && canFitEventSummary) {
                views.setTextViewText(R.id.widget_calendar_event_summary, summaryResult.summary)
                views.setViewVisibility(R.id.widget_calendar_event_summary, View.VISIBLE)
                val openEvent = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse(summaryResult.target)
                )
                views.setOnClickPendingIntent(R.id.widget_calendar_event_summary, openEvent)
            } else {
                views.setViewVisibility(R.id.widget_calendar_event_summary, View.GONE)
            }

            views.setViewVisibility(
                R.id.widget_calendar_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            val tabTodo = DuoyiWidgetCopy.navTodo(prefs, isZh)
            val tabHabit = DuoyiWidgetCopy.navHabit(prefs, isZh)
            val tabCalendar = DuoyiWidgetCopy.navCalendar(prefs, isZh)
            val tabFocus = DuoyiWidgetCopy.navFocus(prefs, isZh)
            views.setTextViewText(R.id.widget_calendar_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_calendar_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_calendar_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_calendar_nav_focus, tabFocus)

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

            views.setOnClickPendingIntent(R.id.widget_calendar_root, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_title, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_month, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_today_button, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_grid, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_summary, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_calendar_nav_focus, openFocus)

            DuoyiWidgetSnapshot.finishRender(context, views, prefs, id)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildMonthGridSpan(
        prefs: SharedPreferences,
        now: Calendar,
        compact: Boolean,
        detailed: Boolean,
        isZh: Boolean
    ): CharSequence {
        val model = DuoyiWidgetContent.buildMonthGrid(now.time, now.timeZone, isZh)
        val currentWeek = ((model.firstWeekdayOffset + model.todayDay - 1) / 7).coerceIn(0, 5)
        val visibleWeeks = when {
            compact -> currentWeek..currentWeek
            detailed -> 0..5
            else -> maxOf(0, currentWeek - 1)..minOf(5, currentWeek + 2)
        }
        val theme = DuoyiWidgetTheme.read(prefs)
        val builder = SpannableStringBuilder()
        builder.append(model.weekdayHeader)

        for (week in visibleWeeks) {
            builder.append("\n")
            val weekCells = model.cells.subList(week * 7, week * 7 + 7)
            for (col in 0 until 7) {
                val cell = weekCells[col]
                val cellStart = builder.length
                builder.append(cell.text)
                val cellEnd = builder.length
                if (cell.dayNumber > 0 && cell.dayNumber == model.todayDay) {
                    builder.setSpan(
                        BackgroundColorSpan(theme.primary),
                        cellStart,
                        cellEnd,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    builder.setSpan(
                        ForegroundColorSpan(theme.onPrimary),
                        cellStart,
                        cellEnd,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                if (col < 6) {
                    builder.append(" ")
                }
            }
        }
        return builder
    }


    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "calendar")
        }
    }
}
