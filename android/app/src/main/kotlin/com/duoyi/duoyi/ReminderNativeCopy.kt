package com.duoyi.duoyi

import java.util.Locale

/** Copy belongs to the scheduled reminder's app locale, independent of the device locale. */
class ReminderNativeCopy(language: String?) {
    val locale = if (language == "en") "en" else "zh"
    private val english = locale == "en"
    val javaLocale: Locale = if (english) Locale.ENGLISH else Locale.SIMPLIFIED_CHINESE
    val datePattern = if (english) "EEEE, MMM d" else "M月d日 EEEE"
    val reminderTitle = if (english) "Duoyi reminder" else "多仪提醒"
    val reminderBody = if (english) "It's time for your reminder" else "提醒时间到了"
    val ringing = if (english) "Duoyi · Reminder ringing" else "多仪 · 强提醒正在响铃"
    val stopAlarm = if (english) "Stop alarm" else "停止闹钟"
    val openDetails = if (english) "Open details" else "打开详情"
    val bodyLabel = if (english) "Reminder" else "提醒内容"

    fun snooze(minutes: Int): String =
        if (english) "Snooze for $minutes min" else "稍后提醒 $minutes 分钟"

    fun displayBody(title: String, body: String): String {
        val displayTitle = title.ifBlank { reminderTitle }
        val displayBody = body.ifBlank { reminderBody }
        return if (displayBody == displayTitle) displayTitle
        else if (english) "$displayTitle: $displayBody" else "$displayTitle：$displayBody"
    }
}
