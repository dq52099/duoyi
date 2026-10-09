package com.duoyi.duoyi

import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class ReminderNativeCopyTest {
    @Test
    fun selectsEnglishOnlyForExactEnglishLanguageCode() {
        assertEnglishCopy(ReminderNativeCopy("en"))

        listOf(null, "", "en-US", "EN", "zh", "fr").forEach { language ->
            assertChineseCopy(ReminderNativeCopy(language))
        }
    }

    @Test
    fun englishCopyContainsExpectedNativeStrings() {
        assertEnglishCopy(ReminderNativeCopy("en"))
    }

    @Test
    fun chineseCopyContainsExpectedNativeStrings() {
        assertChineseCopy(ReminderNativeCopy("zh"))
    }

    @Test
    fun displayBodyPreservesNonBlankInputAndAvoidsRepeatingMatchingText() {
        val english = ReminderNativeCopy("en")
        assertEquals(
            "  Meeting  :   Bring notes\n",
            english.displayBody("  Meeting  ", "  Bring notes\n"),
        )
        assertEquals("  Custom reminder  ", english.displayBody("  Custom reminder  ", "  Custom reminder  "))
        assertEquals("Duoyi reminder: Custom body", english.displayBody("  ", "Custom body"))
        assertEquals("Custom title: It's time for your reminder", english.displayBody("Custom title", "\t"))

        val chinese = ReminderNativeCopy("zh")
        assertEquals(
            "  会议  ：  带上笔记\n",
            chinese.displayBody("  会议  ", "  带上笔记\n"),
        )
        assertEquals("  自定义提醒  ", chinese.displayBody("  自定义提醒  ", "  自定义提醒  "))
        assertEquals("多仪提醒：自定义内容", chinese.displayBody("\n", "自定义内容"))
        assertEquals("自定义标题：提醒时间到了", chinese.displayBody("自定义标题", " "))
    }

    @Test
    fun displayBodyUsesLocalizedFallbacksWhenBothInputsAreBlank() {
        assertEquals(
            "Duoyi reminder: It's time for your reminder",
            ReminderNativeCopy("en").displayBody("\t", "\n"),
        )
        assertEquals(
            "多仪提醒：提醒时间到了",
            ReminderNativeCopy("zh").displayBody("\t", "\n"),
        )
    }

    @Test
    fun dateFormattingUsesCopyLocaleRegardlessOfJvmDefaultLocale() {
        val previousDefault = Locale.getDefault()
        val date = Date.from(Instant.parse("2024-01-02T12:00:00Z"))
        val english = ReminderNativeCopy("en")
        val chinese = ReminderNativeCopy("zh")

        try {
            listOf(Locale.FRANCE, Locale.JAPAN, Locale.forLanguageTag("ar-EG")).forEach { defaultLocale ->
                Locale.setDefault(defaultLocale)
                assertEquals("Tuesday, Jan 2", formatDate(english, date))
                assertEquals("1月2日 星期二", formatDate(chinese, date))
            }
        } finally {
            Locale.setDefault(previousDefault)
        }
    }

    private fun formatDate(copy: ReminderNativeCopy, date: Date): String =
        SimpleDateFormat(copy.datePattern, copy.javaLocale).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(date)

    private fun assertEnglishCopy(copy: ReminderNativeCopy) {
        assertEquals("en", copy.locale)
        assertEquals(Locale.ENGLISH, copy.javaLocale)
        assertEquals("EEEE, MMM d", copy.datePattern)
        assertEquals("Duoyi reminder", copy.reminderTitle)
        assertEquals("It's time for your reminder", copy.reminderBody)
        assertEquals("Duoyi · Reminder ringing", copy.ringing)
        assertEquals("Stop alarm", copy.stopAlarm)
        assertEquals("Open details", copy.openDetails)
        assertEquals("Reminder", copy.bodyLabel)
        assertEquals("Snooze for 15 min", copy.snooze(15))
    }

    private fun assertChineseCopy(copy: ReminderNativeCopy) {
        assertEquals("zh", copy.locale)
        assertEquals(Locale.SIMPLIFIED_CHINESE, copy.javaLocale)
        assertEquals("M月d日 EEEE", copy.datePattern)
        assertEquals("多仪提醒", copy.reminderTitle)
        assertEquals("提醒时间到了", copy.reminderBody)
        assertEquals("多仪 · 强提醒正在响铃", copy.ringing)
        assertEquals("停止闹钟", copy.stopAlarm)
        assertEquals("打开详情", copy.openDetails)
        assertEquals("提醒内容", copy.bodyLabel)
        assertEquals("稍后提醒 15 分钟", copy.snooze(15))
    }
}
