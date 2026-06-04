import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'daily weekly monthly and yearly report notifications are configurable and routable',
    () {
      final prefs = File(
        'lib/providers/preferences_provider.dart',
      ).readAsStringSync();
      final screen = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync();
      final preferencesScreen = File(
        'lib/screens/preferences_screen.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      expect(prefs, contains('_kDailyReportReminder'));
      expect(prefs, contains('_kWeeklyReportReminder'));
      expect(prefs, contains('_kMonthlyReportReminder'));
      expect(prefs, contains('_kYearlyReportReminder'));
      expect(prefs, contains('bool get dailyReportReminder'));
      expect(prefs, contains('bool get weeklyReportReminder'));
      expect(prefs, contains('bool get monthlyReportReminder'));
      expect(prefs, contains('bool get yearlyReportReminder'));
      expect(prefs, contains('dailyReportReminderConfig'));
      expect(prefs, contains('weeklyReportReminderConfig'));
      expect(prefs, contains('monthlyReportReminderConfig'));
      expect(prefs, contains('yearlyReportReminderConfig'));
      expect(prefs, contains('setDailyReportReminder'));
      expect(prefs, contains('setWeeklyReportReminder'));
      expect(prefs, contains('setMonthlyReportReminder'));
      expect(prefs, contains('setYearlyReportReminder'));
      expect(prefs, contains('setDailyReportReminderConfig'));
      expect(prefs, contains('setWeeklyReportReminderConfig'));
      expect(prefs, contains('_kDailyReportReminderHour'));
      expect(prefs, contains('_kDailyReportReminderMinute'));
      expect(prefs, contains('setMonthlyReportReminderConfig'));
      expect(prefs, contains('setYearlyReportReminderConfig'));
      expect(prefs, contains('_kWeeklyReportReminderWeekday'));
      expect(prefs, contains('_kWeeklyReportReminderHour'));
      expect(prefs, contains('_kWeeklyReportReminderMinute'));
      expect(prefs, contains('_kMonthlyReportReminderDay'));
      expect(prefs, contains('_kMonthlyReportReminderHour'));
      expect(prefs, contains('_kMonthlyReportReminderMinute'));
      expect(prefs, contains('_kYearlyReportReminderMonth'));
      expect(prefs, contains('_kYearlyReportReminderDay'));
      expect(prefs, contains('_kYearlyReportReminderHour'));
      expect(prefs, contains('_kYearlyReportReminderMinute'));

      expect(screen, contains('class _ReportReminderSection'));
      expect(screen, contains('class _ReportReminderTile'));
      expect(screen, contains('enum _ReportReminderCadence'));
      expect(screen, contains('报告推送'));
      expect(screen, contains('按你的节奏提醒查看每日复盘、周报、月报和年报'));
      expect(screen, contains('每日效率复盘'));
      expect(screen, contains('每周效率周报'));
      expect(screen, contains('每月成长月报'));
      expect(screen, contains('每年成长年报'));
      expect(screen, contains('setDailyReportReminderConfig'));
      expect(screen, contains('setWeeklyReportReminderConfig'));
      expect(screen, contains('setMonthlyReportReminderConfig'));
      expect(screen, contains('setYearlyReportReminderConfig'));
      expect(screen, contains('AppTimePicker.show'));
      expect(screen, contains('config.copyWith(weekday: day)'));
      expect(screen, contains('config.copyWith(month: month)'));
      expect(screen, contains('config.copyWith(monthDay: day)'));
      expect(
        preferencesScreen,
        isNot(contains('class _ReportReminderSection')),
      );
      expect(preferencesScreen, isNot(contains('报告推送')));

      expect(main, contains('Future<void> _syncReportDigestReminders'));
      expect(main, contains('Future<bool> _cancelDailyDigestReminderIds'));
      expect(main, contains('await _cancelDailyDigestReminderIds('));
      expect(
        main,
        contains('final cancelled = await _cancelDailyDigestReminderIds('),
      );
      expect(main, contains('skip scheduling to avoid duplicate delivery'));
      expect(main, contains('baseId: baseId'));
      expect(main, contains('slotCount: 3'));
      expect(
        main,
        contains(
          'for (var derived = 0; derived < _dailyDigestHolidayWindowDays; derived++)',
        ),
      );
      expect(
        main,
        contains(
          'await _cancelDailyDigestChannelId(notification, id * 100 + derived)',
        ),
      );
      expect(main, contains('Future<bool> _cancelDailyDigestChannelId'));
      expect(main, contains('Future<void> cancelSafely('));
      expect(main, contains('const dailyId = 880023'));
      expect(main, contains('const weeklyId = 880020'));
      expect(main, contains('const monthlyId = 880021'));
      expect(main, contains('const yearlyId = 880022'));
      expect(main, contains('required TodoProvider todos'));
      expect(main, contains('required HabitProvider habits'));
      expect(main, contains('required PomodoroProvider pomodoros'));
      expect(main, contains('required TimeAuditProvider timeAudit'));
      expect(main, contains('dailyConfig.nextDailyReminderTime(now)'));
      expect(main, contains('weeklyConfig.nextWeeklyReminderTime(now)'));
      expect(main, contains('monthlyConfig.nextMonthlyReminderTime(now)'));
      expect(main, contains('yearlyConfig.nextYearlyReminderTime(now)'));
      expect(main, isNot(contains('_nextWeeklyReportReminderTime')));
      expect(main, isNot(contains('_nextMonthlyReportReminderTime')));
      expect(main, isNot(contains('_monthlyReportReminderDate')));
      expect(main, contains('_reportDigestNotificationBody'));
      expect(main, contains('PeriodReportKind.daily'));
      expect(main, contains('PeriodReportKind.weekly'));
      expect(main, contains('PeriodReportKind.monthly'));
      expect(main, contains('PeriodReportKind.yearly'));
      expect(main, contains('ReportEngine.buildReport'));
      expect(main, contains('ReportEngine.compare'));
      expect(main, contains("payload: 'duoyi://report/daily'"));
      expect(main, contains("payload: 'duoyi://report/weekly'"));
      expect(main, contains("payload: 'duoyi://report/monthly'"));
      expect(main, contains("payload: 'duoyi://report/yearly'"));
      final reportSyncStart = main.indexOf(
        'Future<void> _syncReportDigestReminders',
      );
      final reportBodyStart = main.indexOf(
        'String _reportDigestNotificationBody',
        reportSyncStart,
      );
      expect(reportSyncStart, greaterThanOrEqualTo(0));
      expect(reportBodyStart, greaterThan(reportSyncStart));
      final reportSync = main.substring(reportSyncStart, reportBodyStart);
      expect(reportSync, contains('await notification.scheduleOnce('));
      expect(reportSync, isNot(contains('AlarmService')));
      expect(reportSync, isNot(contains('scheduleFullScreen')));
      expect(reportSync, isNot(contains('scheduleDailyFullScreen')));
      expect(reportSync, isNot(contains('NativeReminderRingtone')));
      expect(main, isNot(contains('查看上一周的效率分、待办、习惯、专注和时间投入趋势')));
      expect(main, isNot(contains('查看上月成长轨迹、效率对比、专注投入和活跃热力图')));
      expect(main, contains("uri.host == 'report'"));
      expect(
        main,
        contains('const BrandRouteSurface(child: StatisticsScreen())'),
      );
      expect(main, contains('Future<void> runPostFrameStartupTasks()'));
      expect(main, contains("'report digest reminders'"));
      expect(main, contains('syncReportDigestReminders'));
      expect(
        main,
        contains(
          "_startupGuard('daily digest reminder', syncDailyDigestReminder)",
        ),
      );
      expect(
        main,
        contains(
          'preferencesProvider.addListener(queueReportDigestReminderSync)',
        ),
      );
      expect(
        main,
        contains(
          'preferencesProvider.addListener(queueDailyDigestReminderSync)',
        ),
      );
      expect(main, contains('void queueDailyDigestReminderSync()'));
      expect(
        main,
        contains('todoProvider.addListener(queueReportDigestReminderSync)'),
      );
      expect(
        main,
        contains('habitProvider.addListener(queueReportDigestReminderSync)'),
      );
      expect(
        main,
        contains('void queueReportDigestReminderSyncOnPomodoroSummaryChange()'),
      );
      expect(
        main,
        contains(
          'pomodoroProvider.addListener(\n'
          '    queueReportDigestReminderSyncOnPomodoroSummaryChange,\n'
          '  )',
        ),
      );
      expect(
        main,
        contains(
          'timeAuditProvider.addListener(queueReportDigestReminderSync)',
        ),
      );
      expect(main, contains('todos: todoProvider'));
      expect(main, contains('habits: habitProvider'));
      expect(main, contains('pomodoros: pomodoroProvider'));
      expect(main, contains('timeAudit: timeAuditProvider'));
    },
  );
}
