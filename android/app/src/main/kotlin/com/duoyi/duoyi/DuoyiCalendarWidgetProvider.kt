package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlin.math.roundToInt

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
        val backing = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetSnapshot.renderWidget(context, appWidgetManager, backing, id,
                DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)) { frame ->
                val prefs = frame.prefs
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
                        R.id.widget_calendar_event_summary,
                        R.id.widget_calendar_date_fallback,
                        R.id.widget_calendar_recovery,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_calendar_month,
                        R.id.widget_calendar_nav_todo,
                        R.id.widget_calendar_nav_habit,
                        R.id.widget_calendar_nav_focus,
                        *WEEKDAY_IDS,
                    ),
                    context = context,
                    appWidgetId = id,
                )
                DuoyiWidgetTheme.applyButtonSurfaces(
                    views,
                    prefs,
                    secondaryIds = intArrayOf(R.id.widget_calendar_today_button),
                    context = context,
                    appWidgetId = id,
                )
                val isZh = DuoyiWidgetCopy.isZh(prefs)
                val now = frame.calendar()
                val width = frame.core.options.minWidth
                val height = frame.core.options.minHeight
                val displayMetrics = context.resources.displayMetrics
                val density = if (displayMetrics.density > 0f) displayMetrics.density else 1f
                val measure = DuoyiWidgetTextMetrics(displayMetrics)
                val compact = frame.core.requestedMode == "compact"
                val detailed = frame.core.requestedMode == "detailed"
                val effectiveWidth = width.takeIf { it > 0 } ?: 140
                val contentWidth = (effectiveWidth - 16).coerceAtLeast(1)
                fun visible(shown: Boolean) = if (shown) View.VISIBLE else View.GONE

                val monthTitle = DuoyiWidgetCopy.calendarMonthTitle(now, compact, isZh)
                val todayButtonText = DuoyiWidgetCopy.calendarTodayButton(isZh)
                val titleText = DuoyiWidgetCopy.appTitle(prefs, isZh)
                val monthSingle = measure.measureSingleLine(monthTitle, 11f, contentWidth)
                val todayMeasure = measure.measureSingleLine(
                    todayButtonText, 10f, contentWidth,
                    minWidthDp = 36, minHeightDp = 22, horizontalPaddingDp = 12, verticalPaddingDp = 4,
                )
                val todayWidth = todayMeasure.width + 6
                val refreshMeasure = measure.measureSingleLine(
                    "↻", 12f, contentWidth,
                    minWidthDp = 22, minHeightDp = 22, horizontalPaddingDp = 4, verticalPaddingDp = 4,
                )
                val refreshWidth = refreshMeasure.width + 4
                val showToday = monthSingle.fits && todayMeasure.fits &&
                    monthSingle.width + todayWidth + 2 <= contentWidth
                val showRefresh = effectiveWidth >= 140 && monthSingle.fits && refreshMeasure.fits &&
                    monthSingle.width + (if (showToday) todayWidth else 0) + refreshWidth + 2 <= contentWidth
                val titleAvailableWidth = contentWidth - monthSingle.width -
                    (if (showToday) todayWidth else 0) - (if (showRefresh) refreshWidth else 0) - 8
                val titleMeasure = if (!compact && monthSingle.fits && titleAvailableWidth > 0) {
                    measure.measureSingleLine(titleText, 13f, titleAvailableWidth)
                } else {
                    null
                }
                val isTitleVisible = titleMeasure?.fits == true
                val monthWrapped = if (!monthSingle.fits) measure.measureWrapped(monthTitle, 11f, contentWidth) else null
                val headerFits = contentWidth > 0 && (monthSingle.fits || monthWrapped?.fits == true)
                views.setTextViewText(R.id.widget_calendar_title, titleText)
                views.setTextViewText(R.id.widget_calendar_month, monthTitle)
                views.setContentDescription(R.id.widget_calendar_month,
                    DuoyiWidgetCopy.calendarMonthTitle(now, false, isZh))
                views.setTextViewText(R.id.widget_calendar_today_button, todayButtonText)
                views.setTextViewText(R.id.widget_refresh, "↻")
                val headerHeight = maxOf(
                    24,
                    if (monthSingle.fits) monthSingle.height else (monthWrapped?.height ?: 0),
                    if (isTitleVisible) titleMeasure!!.height else 0,
                    if (showToday) todayMeasure.height else 0,
                    if (showRefresh) refreshMeasure.height else 0,
                )

                // Labels, dates, actions and fallback all share this frozen frame.
                val firstDayOfWeek = prefs.getInt("widget_first_day_of_week", 1)
                    .takeIf { it in 1..7 } ?: 1
                val weekdays = DuoyiWidgetContent.calendarWeekdayLabels(isZh, firstDayOfWeek)
                val weekdayContentDescriptions = DuoyiWidgetContent.calendarWeekdayLabels(
                    isZh, firstDayOfWeek, full = true,
                )
                val model = DuoyiWidgetContent.buildMonthGrid(
                    now.time, now.timeZone, isZh, firstDayOfWeek,
                )
                val currentWeek = ((model.firstWeekdayOffset + model.todayDay - 1) / 7).coerceIn(0, 5)
                val dateSizeSp = if (detailed) 12f else 11f
                val cellWidth = contentWidth / 7
                // Check every real label and date, rather than a single sample such as "28".
                val gridFitsWidth = cellWidth > 2 &&
                    weekdays.all { measure.measureSingleLine(it, 9.5f, cellWidth - 2).fits } &&
                    model.cells.filter { it.dayNumber > 0 }.all {
                        measure.measureSingleLine(it.dayNumber.toString(), dateSizeSp, cellWidth - 2).fits
                    }
                val fullDate = frame.formatTime(if (isZh) "M月d日 · EEEE" else "MMM d · EEEE")
                val shortDate = frame.formatTime(if (isZh) "M月d日" else "MMM d")
                val numericDate = frame.formatTime("M/d")
                val fallbackDate = listOf(fullDate, shortDate, numericDate)
                    .firstOrNull { measure.measureSingleLine(it, 11f, contentWidth - 2).fits }
                    ?: listOf(shortDate, numericDate).firstOrNull {
                        measure.measureWrapped(it, 11f, contentWidth).fits
                    }
                    ?: shortDate
                val fallbackMeasure = measure.measureWrapped(fallbackDate, 11f, contentWidth)
                val fallbackDescription = frame.formatTime(
                    if (isZh) "yyyy年M月d日 EEEE" else "EEEE, MMMM d, yyyy")
                val monthSummaryText = DuoyiWidgetCopy.calendarMonthSummary(
                    prefs.getString("calendar_month_summary", null), isZh)
                val summaryResult = DuoyiWidgetContent.resolveCalendarSummaryAndTarget(
                    rawSummary = prefs.getString("today_event_summary", null),
                    rawSchedule1Id = prefs.getString("schedule_highlight_1_id", null),
                    isFresh = frame.fresh,
                    isZh = isZh,
                    publicationState = frame.core.publicationState,
                )
                val monthSummaryMeasure = measure.measureWrapped(monthSummaryText, 10f, contentWidth)
                val eventSummaryMeasure = summaryResult.summary?.let {
                    measure.measureWrapped(it, 10f, contentWidth)
                }
                val tabLabels = listOf(DuoyiWidgetCopy.navTodo(prefs, isZh),
                    DuoyiWidgetCopy.navHabit(prefs, isZh), DuoyiWidgetCopy.navCalendar(prefs, isZh),
                    DuoyiWidgetCopy.navFocus(prefs, isZh))
                val navigationCellWidth = (contentWidth - 8) / 4
                val plan = DuoyiWidgetLayoutPolicy.calendarMeasured(
                    mode = frame.core.requestedMode,
                    height = height,
                    currentWeek = currentWeek,
                    headerFits = headerFits,
                    headerHeight = headerHeight,
                    weekdayHeight = maxOf(12, measure.line(9.5f, false)),
                    dateHeight = maxOf(24, measure.line(dateSizeSp, false) + 4),
                    gridFitsWidth = gridFitsWidth,
                    fallbackHeight = fallbackMeasure.height,
                    fallbackFitsWidth = fallbackMeasure.fits,
                    monthSummaryHeight = monthSummaryMeasure.height,
                    monthSummaryFitsWidth = monthSummaryMeasure.fits,
                    hasEventSummary = summaryResult.summary != null,
                    eventSummaryHeight = eventSummaryMeasure?.height ?: 0,
                    eventSummaryFitsWidth = eventSummaryMeasure?.fits ?: false,
                    navigationHeight = maxOf(24, measure.line(9.5f, false)),
                    navigationFitsWidth = navigationCellWidth > 2 && tabLabels.all {
                        measure.measureSingleLine(it, 9.5f, navigationCellWidth - 2).fits
                    },
                    weekCount = (model.firstWeekdayOffset + model.daysInMonth + 6) / 7,
                )
                val hasPrimaryDateContent = plan.weeks.isNotEmpty() || plan.showDateFallback
                val requiresEventSummary = !compact && summaryResult.summary != null
                val requiredContentFits = hasPrimaryDateContent && (!requiresEventSummary || plan.showEventSummary)
                val visibleWeeks = if (requiredContentFits) plan.weeks else emptyList()
                for (col in 0 until 7) {
                    views.setTextViewText(WEEKDAY_IDS[col], weekdays[col])
                    views.setContentDescription(WEEKDAY_IDS[col], weekdayContentDescriptions[col])
                }
                views.setTextViewText(R.id.widget_calendar_date_fallback, fallbackDate)
                views.setContentDescription(R.id.widget_calendar_date_fallback, fallbackDescription)
                val todayTarget = model.cells.firstOrNull { it.isToday }?.target
                val fallbackTarget = DuoyiWidgetSnapshot.entityUri(frame,
                    Uri.parse(todayTarget ?: "duoyi://calendar"), Uri.parse("duoyi://calendar"))
                views.setOnClickPendingIntent(R.id.widget_calendar_date_fallback,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, fallbackTarget))

                views.setTextViewText(R.id.widget_calendar_summary, monthSummaryText)
                views.setContentDescription(R.id.widget_calendar_summary, monthSummaryText)
                views.setTextViewText(R.id.widget_calendar_event_summary, summaryResult.summary)
                views.setContentDescription(R.id.widget_calendar_event_summary, summaryResult.summary)
                val openEvent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java,
                    DuoyiWidgetSnapshot.entityUri(frame, Uri.parse(summaryResult.target), Uri.parse("duoyi://calendar")))
                views.setOnClickPendingIntent(R.id.widget_calendar_event_summary, openEvent)
                intArrayOf(R.id.widget_calendar_nav_todo, R.id.widget_calendar_nav_habit,
                    R.id.widget_calendar_nav_calendar, R.id.widget_calendar_nav_focus)
                    .forEachIndexed { index, viewId -> views.setTextViewText(viewId, tabLabels[index]) }

                val recoveryText = DuoyiWidgetCopy.calendarRecoveryText(isZh)
                views.setTextViewText(R.id.widget_calendar_recovery, recoveryText)
                if (!requiredContentFits) {
                    val availableHeight = DuoyiWidgetLayoutPolicy.heightOrDefault(height, frame.core.requestedMode)
                    val recoveryMeasure = measure.measureWrapped(recoveryText, 12f, contentWidth)
                    val recoveryFits = contentWidth > 0 && recoveryMeasure.fits &&
                        availableHeight >= 16 + recoveryMeasure.height
                    val recoveryDesc = DuoyiWidgetCopy.calendarNoFitContentDescription(
                        frame.fresh, isZh, frame.core.publicationState, recoveryVisible = recoveryFits,
                    )
                    views.setViewVisibility(R.id.widget_calendar_header, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_title, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_today_button, View.GONE)
                    views.setViewVisibility(R.id.widget_refresh, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_weekday_header, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_date_fallback, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_grid, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_info_row, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_summary, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_event_summary, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_spacer, View.GONE)
                    views.setViewVisibility(R.id.widget_calendar_bottom_nav, View.GONE)
                    if (recoveryFits) {
                        views.setViewVisibility(R.id.widget_calendar_recovery, View.VISIBLE)
                        views.setContentDescription(R.id.widget_calendar_recovery, recoveryDesc)
                    } else {
                        views.setViewVisibility(R.id.widget_calendar_recovery, View.GONE)
                    }
                    views.setContentDescription(R.id.widget_calendar_root, recoveryDesc)
                } else {
                    val showEventSummary = plan.showEventSummary && summaryResult.summary != null
                    val showInfoRow = plan.showMonthSummary || showEventSummary
                    views.setViewVisibility(R.id.widget_calendar_recovery, View.GONE)
                    views.setContentDescription(R.id.widget_calendar_root, null)
                    views.setViewVisibility(R.id.widget_calendar_header, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_calendar_title, visible(isTitleVisible))
                    views.setViewVisibility(R.id.widget_calendar_today_button, visible(showToday))
                    views.setViewVisibility(R.id.widget_refresh, visible(showRefresh))
                    views.setViewVisibility(R.id.widget_calendar_grid, visible(visibleWeeks.isNotEmpty()))
                    views.setViewVisibility(R.id.widget_calendar_weekday_header, visible(visibleWeeks.isNotEmpty()))
                    views.setViewVisibility(R.id.widget_calendar_date_fallback, visible(plan.showDateFallback))
                    views.setViewVisibility(R.id.widget_calendar_summary, visible(plan.showMonthSummary))
                    views.setViewVisibility(R.id.widget_calendar_event_summary, visible(showEventSummary))
                    views.setViewVisibility(R.id.widget_calendar_info_row, visible(showInfoRow))
                    views.setViewVisibility(
                        R.id.widget_calendar_spacer,
                        visible(visibleWeeks.isEmpty() && plan.showNavigation),
                    )
                    views.setViewVisibility(R.id.widget_calendar_bottom_nav, visible(plan.showNavigation))
                    if (!DuoyiWidgetTheme.isBottomNavEnabled(context, prefs, id)) {
                        views.setViewVisibility(R.id.widget_calendar_bottom_nav, View.GONE)
                    }
                }

                val theme = DuoyiWidgetTheme.read(prefs)
                val circleSizePx = (24f * density).roundToInt().coerceIn(32, 96)
                val todayBitmap = createTodayCircleBitmap(theme.primary, circleSizePx)

                val fallbackCalendarUri = Uri.parse("duoyi://calendar")
                val monthNames = arrayOf(
                    "January", "February", "March", "April", "May", "June",
                    "July", "August", "September", "October", "November", "December"
                )
                val monthName = monthNames.getOrElse(model.month - 1) { "" }

                for (week in 0..5) {
                    val rowId = ROW_IDS[week]
                    views.removeAllViews(rowId)

                    if (week in visibleWeeks) {
                        views.setViewVisibility(rowId, View.VISIBLE)

                        for (col in 0 until 7) {
                            val cellIndex = week * 7 + col
                            val cell = model.cells[cellIndex]
                            val cellViews = RemoteViews(context.packageName, R.layout.duoyi_calendar_day_cell)

                            if (cell.dayNumber > 0) {
                                val dayDesc = if (isZh) {
                                    "${model.year}年${model.month}月${cell.dayNumber}日" + if (cell.isToday) " 今天" else ""
                                } else {
                                    "$monthName ${cell.dayNumber}, ${model.year}" + if (cell.isToday) ", Today" else ""
                                }
                                cellViews.setContentDescription(R.id.widget_calendar_day_text, dayDesc)

                                cellViews.setTextViewText(R.id.widget_calendar_day_text, cell.dayNumber.toString())
                                cellViews.setTextViewTextSize(R.id.widget_calendar_day_text, TypedValue.COMPLEX_UNIT_SP, dateSizeSp)
                                cellViews.setViewVisibility(R.id.widget_calendar_day_text, View.VISIBLE)
                                cellViews.setViewVisibility(R.id.widget_calendar_day_today, visible(cell.isToday))
                                if (cell.isToday) {
                                    cellViews.setImageViewBitmap(R.id.widget_calendar_day_today, todayBitmap)
                                }
                                cellViews.setTextColor(R.id.widget_calendar_day_text,
                                    if (cell.isToday) theme.readableOnPrimary else theme.text)

                                val rawTarget = cell.target
                                val targetUri = if (!rawTarget.isNullOrBlank()) Uri.parse(rawTarget) else fallbackCalendarUri
                                val launchUri = DuoyiWidgetSnapshot.entityUri(frame, targetUri, fallbackCalendarUri)
                                val cellIntent = HomeWidgetLaunchIntent.getActivity(
                                    context,
                                    MainActivity::class.java,
                                    launchUri,
                                )
                                cellViews.setOnClickPendingIntent(R.id.widget_calendar_day_text, cellIntent)
                            } else {
                                cellViews.setViewVisibility(R.id.widget_calendar_day_today, View.GONE)
                                cellViews.setViewVisibility(R.id.widget_calendar_day_text, View.INVISIBLE)
                                cellViews.setTextViewText(R.id.widget_calendar_day_text, "")
                                cellViews.setContentDescription(R.id.widget_calendar_day_text, null)
                                cellViews.setOnClickPendingIntent(R.id.widget_calendar_day_text, null)
                            }

                            views.addView(rowId, cellViews)
                        }
                    } else {
                        views.setViewVisibility(rowId, View.GONE)
                    }
                }

                val openCalendarTab = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
                )
                val todayDateUri = Uri.parse(
                    todayTarget ?: DuoyiWidgetContent.calendarTodayTarget(
                        frame.wallMillis,
                        java.util.TimeZone.getTimeZone(frame.core.clock.zone),
                    )
                )
                val openCalendar = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    DuoyiWidgetSnapshot.entityUri(frame, todayDateUri, Uri.parse("duoyi://calendar")),
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

                views.setOnClickPendingIntent(R.id.widget_calendar_root, openCalendarTab)
                views.setOnClickPendingIntent(R.id.widget_calendar_recovery, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_calendar_title, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_calendar_month, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_calendar_today_button, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_calendar_weekday_header, openCalendarTab)
                for (col in 0 until 7) {
                    views.setOnClickPendingIntent(WEEKDAY_IDS[col], openCalendarTab)
                }
                views.setOnClickPendingIntent(R.id.widget_calendar_grid, openCalendarTab)
                views.setOnClickPendingIntent(R.id.widget_calendar_summary, openCalendarTab)
                views.setOnClickPendingIntent(R.id.widget_calendar_nav_todo, openTodo)
                views.setOnClickPendingIntent(R.id.widget_calendar_nav_habit, openHabit)
                views.setOnClickPendingIntent(R.id.widget_calendar_nav_calendar, openCalendarTab)
                views.setOnClickPendingIntent(R.id.widget_calendar_nav_focus, openFocus)

                DuoyiWidgetBuiltViews(views)
            }
        }
    }

    companion object {
        private val WEEKDAY_IDS = intArrayOf(
            R.id.widget_calendar_weekday_0,
            R.id.widget_calendar_weekday_1,
            R.id.widget_calendar_weekday_2,
            R.id.widget_calendar_weekday_3,
            R.id.widget_calendar_weekday_4,
            R.id.widget_calendar_weekday_5,
            R.id.widget_calendar_weekday_6,
        )

        private val ROW_IDS = intArrayOf(
            R.id.widget_calendar_row_0,
            R.id.widget_calendar_row_1,
            R.id.widget_calendar_row_2,
            R.id.widget_calendar_row_3,
            R.id.widget_calendar_row_4,
            R.id.widget_calendar_row_5,
        )

        private fun createTodayCircleBitmap(color: Int, sizePx: Int): Bitmap {
            val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                style = Paint.Style.FILL
            }
            val radius = sizePx / 2f
            canvas.drawCircle(radius, radius, radius, paint)
            return bitmap
        }

        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "calendar")
        }
    }
}
