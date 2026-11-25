package com.duoyi.duoyi

import com.dexterous.flutterlocalnotifications.DuoyiScheduledNotificationUpdateReceiver
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderNativeReliabilityTest {
    @Test
    fun resolveTimeZoneForRescheduleFollowsCurrentSystemZoneAndIgnoresStalePersistedZone() {
        val originalDefault = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            assertEquals(
                "America/New_York",
                ReminderRingtoneScheduler.resolveTimeZoneForReschedule(
                    appTimezoneMode = null,
                    fixedTimezoneId = null,
                    persistedTimezoneId = "Asia/Shanghai",
                ),
            )
            assertEquals(
                "Europe/London",
                ReminderRingtoneScheduler.resolveTimeZoneForReschedule(
                    appTimezoneMode = "system",
                    fixedTimezoneId = "Asia/Tokyo",
                    persistedTimezoneId = "Asia/Shanghai",
                    systemDefault = "Europe/London",
                ),
            )
        } finally {
            TimeZone.setDefault(originalDefault)
        }
    }

    @Test
    fun resolveTimeZoneForRescheduleHonorsFixedZoneAndRejectsUtcOrUnknownZones() {
        assertEquals(
            "Asia/Tokyo",
            ReminderRingtoneScheduler.resolveTimeZoneForReschedule(
                appTimezoneMode = "fixed",
                fixedTimezoneId = "Asia/Tokyo",
                persistedTimezoneId = "Asia/Shanghai",
                systemDefault = "America/Los_Angeles",
            ),
        )
        assertEquals(
            "America/Los_Angeles",
            ReminderRingtoneScheduler.resolveTimeZoneForReschedule(
                appTimezoneMode = "fixed",
                fixedTimezoneId = "UTC",
                persistedTimezoneId = "Etc/UTC",
                systemDefault = "America/Los_Angeles",
            ),
        )
        assertEquals(
            "America/Los_Angeles",
            ReminderRingtoneScheduler.normalizeTimeZoneFor(
                timezoneId = "Mars/Olympus_Mons",
                systemDefault = "America/Los_Angeles",
            ),
        )
    }

    @Test
    fun computeNextWallClockMillisRecomputesWallClockAcrossTimezoneShiftAndWeekdays() {
        // 2026-11-24 is a Tuesday (Dart weekday = 2).
        // 12:00Z = 07:00 in America/New_York (UTC-5), whereas in Asia/Shanghai (UTC+8) it is 20:00.
        val nowMillis = Instant.parse("2026-11-24T12:00:00Z").toEpochMilli()

        val nyTrigger = ReminderRingtoneScheduler.computeNextWallClockMillis(
            hour = 8,
            minute = 30,
            weekdays = intArrayOf(),
            timezoneId = "America/New_York",
            nowMillis = nowMillis,
        )
        assertEquals(
            ZonedDateTime.of(2026, 11, 24, 8, 30, 0, 0, ZoneId.of("America/New_York"))
                .toInstant()
                .toEpochMilli(),
            nyTrigger,
        )

        val shanghaiTrigger = ReminderRingtoneScheduler.computeNextWallClockMillis(
            hour = 8,
            minute = 30,
            weekdays = intArrayOf(),
            timezoneId = "Asia/Shanghai",
            nowMillis = nowMillis,
        )
        assertEquals(
            ZonedDateTime.of(2026, 11, 25, 8, 30, 0, 0, ZoneId.of("Asia/Shanghai"))
                .toInstant()
                .toEpochMilli(),
            shanghaiTrigger,
        )
        assertNotEquals(shanghaiTrigger, nyTrigger)

        // Friday-only reminder (weekday = 5 -> 2026-11-27) skips Tue/Wed/Thu.
        val fridayTrigger = ReminderRingtoneScheduler.computeNextWallClockMillis(
            hour = 9,
            minute = 15,
            weekdays = intArrayOf(5),
            timezoneId = "America/New_York",
            nowMillis = nowMillis,
        )
        assertEquals(
            ZonedDateTime.of(2026, 11, 27, 9, 15, 0, 0, ZoneId.of("America/New_York"))
                .toInstant()
                .toEpochMilli(),
            fridayTrigger,
        )
    }

    @Test
    fun bootReceiverHandlesTimeSetAndExactAlarmPermissionStateWithoutFiringStaleAlarmsOnGrant() {
        val supported = listOf(
            "android.intent.action.BOOT_COMPLETED",
            "android.intent.action.MY_PACKAGE_REPLACED",
            "android.intent.action.TIMEZONE_CHANGED",
            "android.intent.action.TIME_SET",
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
        supported.forEach { action ->
            assertTrue("Expected supported boot action: $action", ReminderRingtoneBootReceiver.isSupportedRestoreAction(action))
        }
        assertFalse(ReminderRingtoneBootReceiver.isSupportedRestoreAction("android.intent.action.AIRPLANE_MODE"))
        assertFalse(ReminderRingtoneBootReceiver.isSupportedRestoreAction(null))

        assertTrue(ReminderRingtoneBootReceiver.shouldDeliverExpiredOnRestore("android.intent.action.BOOT_COMPLETED"))
        assertTrue(ReminderRingtoneBootReceiver.shouldDeliverExpiredOnRestore("android.intent.action.TIME_SET"))
        assertTrue(ReminderRingtoneBootReceiver.shouldDeliverExpiredOnRestore("android.intent.action.TIMEZONE_CHANGED"))
        assertFalse(ReminderRingtoneBootReceiver.shouldDeliverExpiredOnRestore("android.intent.action.MY_PACKAGE_REPLACED"))
        assertFalse(
            ReminderRingtoneBootReceiver.shouldDeliverExpiredOnRestore(
                "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            ),
        )
    }

    @Test
    fun bootAndServiceCleanupDelaysMoveLongWaitsOffHandlerPostDelayed() {
        assertFalse(ReminderRingtoneBootReceiver.usesAlarmCleanupForDelay(500L))
        assertFalse(ReminderRingtoneBootReceiver.usesAlarmCleanupForDelay(2_500L))
        assertTrue(ReminderRingtoneBootReceiver.usesAlarmCleanupForDelay(10_000L))
        assertTrue(ReminderRingtoneBootReceiver.usesAlarmCleanupForDelay(30_000L))
        assertTrue(ReminderRingtoneBootReceiver.usesAlarmCleanupForDelay(60_000L))

        assertFalse(ReminderRingtoneService.usesAlarmCleanupForRaceDelay(0L))
        assertFalse(ReminderRingtoneService.usesAlarmCleanupForRaceDelay(750L))
        assertTrue(ReminderRingtoneService.usesAlarmCleanupForRaceDelay(2_500L))
        assertTrue(ReminderRingtoneService.usesAlarmCleanupForRaceDelay(10_000L))
    }

    @Test
    fun scheduledNotificationUpdateReceiverFiltersActionsCorrectly() {
        assertTrue(DuoyiScheduledNotificationUpdateReceiver.isSupportedAction("android.intent.action.MY_PACKAGE_REPLACED"))
        assertTrue(
            DuoyiScheduledNotificationUpdateReceiver.isSupportedAction(
                "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED",
            ),
        )
        assertTrue(DuoyiScheduledNotificationUpdateReceiver.isSupportedAction("android.intent.action.TIME_SET"))
        assertTrue(DuoyiScheduledNotificationUpdateReceiver.isSupportedAction("android.intent.action.TIMEZONE_CHANGED"))
        assertFalse(DuoyiScheduledNotificationUpdateReceiver.isSupportedAction("android.intent.action.BOOT_COMPLETED"))
        assertFalse(DuoyiScheduledNotificationUpdateReceiver.isSupportedAction(null))
    }

    @Test
    fun scheduledNotificationUpdateReceiverPrunesExpiredUpgradesExactAndRecomputesTimezone() {
        val nowMillis = ZonedDateTime.of(2026, 11, 24, 8, 0, 0, 0, ZoneId.of("America/New_York"))
            .toInstant()
            .toEpochMilli()

        val expiredOneShot = JSONObject()
            .put("id", 101)
            .put("scheduledDateTime", "2026-11-24T07:00:00")
            .put("timeZoneName", "America/New_York")
            .put("scheduleMode", "inexactAllowWhileIdle")

        val futureOneShot = JSONObject()
            .put("id", 102)
            .put("scheduledDateTime", "2026-11-24T10:30:00")
            .put("timeZoneName", "America/New_York")
            .put("scheduleMode", "inexact")

        val staleTimezoneDaily = JSONObject()
            .put("id", 103)
            .put("matchDateTimeComponents", "Time")
            .put("scheduledDateTime", "2026-11-24T09:00:00")
            .put("timeZoneName", "Asia/Shanghai")
            .put("scheduleMode", "inexactAllowWhileIdle")

        val passedWeeklyToday = JSONObject()
            .put("id", 104)
            .put("matchDateTimeComponents", "DayOfWeekAndTime")
            .put("scheduledDateTime", "2026-11-24T07:30:00") // Tuesday 07:30, already past 08:00 -> next Tuesday 2026-12-01
            .put("timeZoneName", "America/New_York")
            .put("scheduleMode", "exactAllowWhileIdle")

        val input = JSONArray(listOf(expiredOneShot, futureOneShot, staleTimezoneDaily, passedWeeklyToday)).toString()
        val output = DuoyiScheduledNotificationUpdateReceiver.transformScheduledNotificationsJson(
            raw = input,
            now = nowMillis,
            upgradeExactAlarms = true,
            resolvedTimeZoneId = "America/New_York",
        )
        assertNotNull(output)
        val result = JSONArray(output)
        assertEquals(3, result.length())

        val keptFuture = result.getJSONObject(0)
        assertEquals(102, keptFuture.getInt("id"))
        assertEquals("exact", keptFuture.getString("scheduleMode"))

        val updatedDaily = result.getJSONObject(1)
        assertEquals(103, updatedDaily.getInt("id"))
        assertEquals("exactAllowWhileIdle", updatedDaily.getString("scheduleMode"))
        assertEquals("America/New_York", updatedDaily.getString("timeZoneName"))
        assertEquals("2026-11-24T09:00:00", updatedDaily.getString("scheduledDateTime"))

        val updatedWeekly = result.getJSONObject(2)
        assertEquals(104, updatedWeekly.getInt("id"))
        assertEquals(
            DateTimeFormatter.ISO_LOCAL_DATE_TIME.format(LocalDateTime.of(2026, 12, 1, 7, 30, 0)),
            updatedWeekly.getString("scheduledDateTime"),
        )
    }

    @Test
    fun fullScreenActivityRespectsAndroid10To16BackgroundActivityLaunchGuard() {
        assertTrue(
            ReminderFullScreenActivity.isDirectLaunchAllowed(
                sdkInt = 28,
                isActivityContext = false,
                isAppInForeground = false,
                canDrawOverlays = false,
            ),
        )
        for (sdk in listOf(29, 34, 35, 36)) {
            assertFalse(
                "Expected BAL guard to block silent background startActivity on API $sdk",
                ReminderFullScreenActivity.isDirectLaunchAllowed(
                    sdkInt = sdk,
                    isActivityContext = false,
                    isAppInForeground = false,
                    canDrawOverlays = false,
                ),
            )
            assertTrue(
                ReminderFullScreenActivity.isDirectLaunchAllowed(
                    sdkInt = sdk,
                    isActivityContext = false,
                    isAppInForeground = true,
                    canDrawOverlays = false,
                ),
            )
            assertTrue(
                ReminderFullScreenActivity.isDirectLaunchAllowed(
                    sdkInt = sdk,
                    isActivityContext = false,
                    isAppInForeground = false,
                    canDrawOverlays = true,
                ),
            )
            assertTrue(
                ReminderFullScreenActivity.isDirectLaunchAllowed(
                    sdkInt = sdk,
                    isActivityContext = true,
                    isAppInForeground = false,
                    canDrawOverlays = false,
                ),
            )
        }
    }

    @Test
    fun snoozeReschedulingMathNormalizesBoundsAndSeparatesCleanupRequestCodes() {
        assertEquals(10, ReminderRingtoneScheduler.defaultSnoozeMinutes)
        assertEquals(10, ReminderRingtoneScheduler.normalizeSnoozeMinutes(0))
        assertEquals(10, ReminderRingtoneScheduler.normalizeSnoozeMinutes(-5))
        assertEquals(5, ReminderRingtoneScheduler.normalizeSnoozeMinutes(5))
        assertEquals(120, ReminderRingtoneScheduler.normalizeSnoozeMinutes(240))

        val base = 1_700_000_000_000L
        assertEquals(
            base + 10 * 60_000L,
            ReminderRingtoneScheduler.computeSnoozeTriggerAtMillis(base, 10),
        )
        assertEquals(
            base + 10 * 60_000L,
            ReminderRingtoneScheduler.computeSnoozeTriggerAtMillis(base, 0),
        )

        val requestCodes = (0 until 8).map { slot ->
            ReminderRingtoneScheduler.pluginNotificationCleanupRequestCode(42, slot)
        }.toSet()
        assertEquals(8, requestCodes.size)
        assertNotEquals(
            ReminderRingtoneScheduler.pluginNotificationCleanupRequestCode(42, 0),
            ReminderRingtoneScheduler.pluginNotificationCleanupRequestCode(43, 0),
        )
    }
}
