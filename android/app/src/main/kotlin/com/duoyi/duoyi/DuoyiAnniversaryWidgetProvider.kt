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
        val backing = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetSnapshot.renderWidget(context, appWidgetManager, backing, id,
                DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)) { frame ->
                val prefs = frame.prefs
                val views = RemoteViews(context.packageName, R.layout.duoyi_anniversary_widget)
                DuoyiWidgetTheme.applyContainer(
                    context = context,
                    views = views,
                    prefs = prefs,
                    rootId = R.id.widget_anniversary_root,
                    navId = R.id.widget_anniversary_bottom_nav,
                    appWidgetId = id,
                )
                DuoyiWidgetTheme.applyTextColors(
                    views,
                    prefs,
                    primaryIds = intArrayOf(
                        R.id.widget_anniversary_title,
                        R.id.widget_anniversary_nav_calendar,
                    ),
                    bodyIds = intArrayOf(
                        R.id.widget_anniversary_1,
                        R.id.widget_anniversary_2,
                        R.id.widget_anniversary_3,
                    ),
                    mutedIds = intArrayOf(
                        R.id.widget_anniversary_subtitle,
                        R.id.widget_anniversary_nav_todo,
                        R.id.widget_anniversary_nav_habit,
                        R.id.widget_anniversary_nav_focus,
                    ),
                    context = context,
                    appWidgetId = id,
                )

                val isZh = DuoyiWidgetCopy.isZh(prefs)
                views.setTextViewText(
                    R.id.widget_anniversary_title,
                    DuoyiWidgetCopy.appTitle(prefs, isZh)
                )
                views.setTextViewText(R.id.widget_anniversary_subtitle, DuoyiWidgetCopy.anniversarySubtitle(isZh))

                val isFresh = frame.fresh
                val rawSlots = listOf(
                    DuoyiAnniversaryRawSlot("anniversary_highlight_1", prefs.getString("anniversary_highlight_1", null), prefs.getString("anniversary_highlight_1_id", null)),
                    DuoyiAnniversaryRawSlot("anniversary_highlight_2", prefs.getString("anniversary_highlight_2", null), prefs.getString("anniversary_highlight_2_id", null)),
                    DuoyiAnniversaryRawSlot("memorial_highlight_1", prefs.getString("memorial_highlight_1", null), prefs.getString("memorial_highlight_1_id", null)),
                    DuoyiAnniversaryRawSlot("memorial_highlight_2", prefs.getString("memorial_highlight_2", null), prefs.getString("memorial_highlight_2_id", null)),
                    DuoyiAnniversaryRawSlot("memorial_highlight_3", prefs.getString("memorial_highlight_3", null), prefs.getString("memorial_highlight_3_id", null)),
                )
                val selectedItems = DuoyiWidgetContent.resolveAnniversaryItems(
                    rawSlots,
                    isFresh,
                    isZh,
                    frame.core.publicationState,
                )

                val item1 = selectedItems.getOrNull(0)
                val item2 = selectedItems.getOrNull(1)
                val item3 = selectedItems.getOrNull(2)

                val measure = DuoyiWidgetTextMetrics(context.resources.displayMetrics)
                val contentWidth = ((frame.core.options.minWidth.takeIf { it > 0 } ?: 140) - 16)
                    .coerceAtLeast(1)
                val title = DuoyiWidgetCopy.appTitle(prefs, isZh)
                val refreshWidth = maxOf(36, measure.width("↻", 14f))
                val showRefresh = measure.width(title, 14f) + refreshWidth + 2 <= contentWidth
                val navigationLabels = listOf(
                    DuoyiWidgetCopy.navTodo(prefs, isZh), DuoyiWidgetCopy.navHabit(prefs, isZh),
                    DuoyiWidgetCopy.navCalendar(prefs, isZh), DuoyiWidgetCopy.navFocus(prefs, isZh),
                )
                val plan = DuoyiWidgetLayoutPolicy.textList(
                    mode = frame.core.requestedMode,
                    width = frame.core.options.minWidth,
                    height = frame.core.options.minHeight,
                    secondaryRows = listOf(item2 != null, item3 != null),
                    titleLineHeight = measure.line(14f),
                    bodyLineHeight = measure.line(12f),
                    smallLineHeight = measure.line(11f),
                    thirdLineIsSmall = false,
                    headerHeight = maxOf(measure.line(14f), if (showRefresh) maxOf(36, measure.line(14f)) else 0),
                    navigationHeight = maxOf(30, measure.line(10f)),
                    navigationFitsWidth = navigationLabels.all {
                        measure.width(it, 10f) + 2 <= (contentWidth - 8) / 4
                    },
                )
                fun visible(shown: Boolean) = if (shown) View.VISIBLE else View.GONE
                views.setViewVisibility(R.id.widget_refresh, visible(showRefresh))
                views.setViewVisibility(R.id.widget_anniversary_subtitle, visible(plan.showSubtitle))
                views.setViewVisibility(R.id.widget_anniversary_1, visible(plan.rows[0]))
                views.setViewVisibility(R.id.widget_anniversary_2, visible(plan.rows[1]))
                views.setViewVisibility(R.id.widget_anniversary_3, visible(plan.rows[2]))
                views.setViewVisibility(
                    R.id.widget_anniversary_bottom_nav,
                    visible(plan.showNavigation),
                )
                if (!DuoyiWidgetTheme.isBottomNavEnabled(context, prefs, id)) {
                    views.setViewVisibility(R.id.widget_anniversary_bottom_nav, View.GONE)
                }
                listOf(item1, item2, item3).forEachIndexed { index, item ->
                    views.setContentDescription(
                        intArrayOf(R.id.widget_anniversary_1, R.id.widget_anniversary_2, R.id.widget_anniversary_3)[index],
                        item?.text,
                    )
                }

                views.setTextViewText(
                    R.id.widget_anniversary_1,
                    item1?.text.orEmpty()
                )
                views.setTextViewText(
                    R.id.widget_anniversary_2,
                    item2?.text.orEmpty()
                )
                views.setTextViewText(
                    R.id.widget_anniversary_3,
                    item3?.text.orEmpty()
                )
                intArrayOf(R.id.widget_anniversary_nav_todo, R.id.widget_anniversary_nav_habit,
                    R.id.widget_anniversary_nav_calendar, R.id.widget_anniversary_nav_focus)
                    .forEachIndexed { index, viewId -> views.setTextViewText(viewId, navigationLabels[index]) }

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
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        DuoyiWidgetSnapshot.entityUri(frame,
                            Uri.parse(item1?.target ?: "duoyi://anniversary"), Uri.parse("duoyi://anniversary"))
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.widget_anniversary_2,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        DuoyiWidgetSnapshot.entityUri(frame,
                            Uri.parse(item2?.target ?: "duoyi://anniversary"), Uri.parse("duoyi://anniversary"))
                    )
                )
                views.setOnClickPendingIntent(
                    R.id.widget_anniversary_3,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        DuoyiWidgetSnapshot.entityUri(frame,
                            Uri.parse(item3?.target ?: "duoyi://anniversary"), Uri.parse("duoyi://anniversary"))
                    )
                )
                views.setOnClickPendingIntent(R.id.widget_anniversary_nav_todo, openTodo)
                views.setOnClickPendingIntent(R.id.widget_anniversary_nav_habit, openHabit)
                views.setOnClickPendingIntent(R.id.widget_anniversary_nav_calendar, openCalendar)
                views.setOnClickPendingIntent(R.id.widget_anniversary_nav_focus, openFocus)

                DuoyiWidgetBuiltViews(views)
            }
        }
    }

    companion object {
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "anniversary")
        }
    }
}
