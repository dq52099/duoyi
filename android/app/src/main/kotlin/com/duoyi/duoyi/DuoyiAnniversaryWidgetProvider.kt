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
                val selectedItems = DuoyiWidgetContent.resolveAnniversaryItems(rawSlots, isFresh, isZh)

                val item1 = selectedItems.getOrNull(0)
                val item2 = selectedItems.getOrNull(1)
                val item3 = selectedItems.getOrNull(2)

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
                views.setViewVisibility(
                    R.id.widget_anniversary_2,
                    if (item2 != null) DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id) else View.GONE
                )
                views.setViewVisibility(
                    R.id.widget_anniversary_3,
                    if (item3 != null) DuoyiWidgetDisplayMode.detailedVisibility(prefs, id) else View.GONE
                )
                views.setViewVisibility(
                    R.id.widget_anniversary_bottom_nav,
                    DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
                )

                views.setTextViewText(R.id.widget_anniversary_nav_todo, DuoyiWidgetCopy.navTodo(prefs, isZh))
                views.setTextViewText(R.id.widget_anniversary_nav_habit, DuoyiWidgetCopy.navHabit(prefs, isZh))
                views.setTextViewText(R.id.widget_anniversary_nav_calendar, DuoyiWidgetCopy.navCalendar(prefs, isZh))
                views.setTextViewText(R.id.widget_anniversary_nav_focus, DuoyiWidgetCopy.navFocus(prefs, isZh))

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
