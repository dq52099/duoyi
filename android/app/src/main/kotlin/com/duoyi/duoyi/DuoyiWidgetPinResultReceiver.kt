package com.duoyi.duoyi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DuoyiWidgetPinResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getStringExtra(extraKind)) {
            "todo" -> DuoyiTodoWidgetProvider.requestUpdate(context)
            "focus" -> DuoyiFocusHabitWidgetProvider.requestUpdate(context)
            "habit" -> DuoyiHabitWidgetProvider.requestUpdate(context)
            "calendar" -> DuoyiCalendarWidgetProvider.requestUpdate(context)
            "schedule" -> DuoyiScheduleWidgetProvider.requestUpdate(context)
            "goal" -> DuoyiGoalWidgetProvider.requestUpdate(context)
            "course" -> DuoyiCourseWidgetProvider.requestUpdate(context)
            "note" -> DuoyiNoteWidgetProvider.requestUpdate(context)
            "anniversary" -> DuoyiAnniversaryWidgetProvider.requestUpdate(context)
            "diary" -> DuoyiDiaryWidgetProvider.requestUpdate(context)
        }
    }

    companion object {
        const val extraKind = "duoyi_widget_kind"
    }
}
