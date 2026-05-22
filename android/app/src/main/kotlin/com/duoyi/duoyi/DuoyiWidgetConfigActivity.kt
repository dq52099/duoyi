package com.duoyi.duoyi

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle

/**
 * Configuration activity referenced by Android widget provider XML.
 * MIUI requires a configurable widget to declare this activity even if
 * it does nothing more than acknowledge placement.
 */
class DuoyiWidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        val widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        // Ask the actual provider to render the initial state immediately.
        val manager = AppWidgetManager.getInstance(applicationContext)
        val providerClassName = manager.getAppWidgetInfo(widgetId)?.provider?.className
        requestInitialUpdate(providerClassName)

        val resultValue = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        setResult(RESULT_OK, resultValue)
        finish()
    }

    private fun requestInitialUpdate(providerClassName: String?) {
        when (providerClassName) {
            DuoyiTodoWidgetProvider::class.java.name ->
                DuoyiTodoWidgetProvider.requestUpdate(applicationContext)
            DuoyiFocusHabitWidgetProvider::class.java.name ->
                DuoyiFocusHabitWidgetProvider.requestUpdate(applicationContext)
            DuoyiHabitWidgetProvider::class.java.name ->
                DuoyiHabitWidgetProvider.requestUpdate(applicationContext)
            DuoyiCalendarWidgetProvider::class.java.name ->
                DuoyiCalendarWidgetProvider.requestUpdate(applicationContext)
            DuoyiScheduleWidgetProvider::class.java.name ->
                DuoyiScheduleWidgetProvider.requestUpdate(applicationContext)
            DuoyiGoalWidgetProvider::class.java.name ->
                DuoyiGoalWidgetProvider.requestUpdate(applicationContext)
            DuoyiCourseWidgetProvider::class.java.name ->
                DuoyiCourseWidgetProvider.requestUpdate(applicationContext)
            DuoyiNoteWidgetProvider::class.java.name ->
                DuoyiNoteWidgetProvider.requestUpdate(applicationContext)
            DuoyiAnniversaryWidgetProvider::class.java.name ->
                DuoyiAnniversaryWidgetProvider.requestUpdate(applicationContext)
            DuoyiDiaryWidgetProvider::class.java.name ->
                DuoyiDiaryWidgetProvider.requestUpdate(applicationContext)
        }
    }
}
