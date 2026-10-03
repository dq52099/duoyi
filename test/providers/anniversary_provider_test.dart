import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'AnniversaryProvider syncs reminders immediately after add update delete',
    () async {
      final scheduler = RecordingReminderScheduler();
      final provider = AnniversaryProvider()..scheduler = scheduler;
      final item = Anniversary(
        id: 'anniversary-sync',
        title: '生日',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.birthday,
        remind: true,
      );

      await provider.add(item);
      expect(scheduler.anniversarySyncs, [
        ['anniversary-sync'],
      ]);

      item.title = '生日提醒';
      await provider.update(item);
      expect(scheduler.anniversarySyncs, [
        ['anniversary-sync'],
        ['anniversary-sync'],
      ]);

      await provider.delete(item.id);
      expect(scheduler.anniversarySyncs.last, isEmpty);
    },
  );

  test(
    'AnniversaryProvider exposes reminder sync failures after local save',
    () async {
      final scheduler = RecordingReminderScheduler()
        ..anniversarySyncError = const ReminderScheduleSyncException([
          '纪念日提醒注册失败：闹钟提醒未注册成功',
        ]);
      final provider = AnniversaryProvider()..scheduler = scheduler;
      final item = Anniversary(
        id: 'anniversary-sync-failure',
        title: '纪念日',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.memorial,
        remind: true,
      );

      final issue = await provider.add(item);

      expect(provider.items.map((item) => item.id), contains(item.id));
      expect(issue, contains('纪念日提醒注册失败'));
      expect(provider.lastReminderSyncIssue, issue);
    },
  );

  test(
    'AnniversaryProvider reports enabled reminders when scheduler is missing',
    () async {
      final provider = AnniversaryProvider();
      final disabled = Anniversary(
        id: 'anniversary-no-reminder',
        title: '不提醒生日',
        originDate: DateTime.now().add(const Duration(days: 30)),
        type: AnniversaryType.birthday,
        remind: false,
      );

      final disabledIssue = await provider.add(disabled);

      expect(disabledIssue, isNull);
      expect(provider.lastReminderSyncIssue, isNull);

      final enabled = Anniversary(
        id: 'anniversary-missing-scheduler',
        title: '提醒生日',
        originDate: DateTime.now().add(const Duration(days: 31)),
        type: AnniversaryType.birthday,
        remind: true,
      );

      final addIssue = await provider.add(enabled);

      expect(addIssue, contains('提醒服务未初始化'));
      expect(provider.lastReminderSyncIssue, addIssue);

      enabled.title = '更新提醒生日';
      final updateIssue = await provider.update(enabled);

      expect(updateIssue, contains('提醒服务未初始化'));
      expect(provider.lastReminderSyncIssue, updateIssue);
    },
  );

  test(
    'AnniversaryProvider import reports enabled reminders when scheduler is missing',
    () async {
      final provider = AnniversaryProvider();

      final summary = await provider.importAnniversaries([
        Anniversary(
          id: 'anniversary-import-missing-scheduler',
          title: '导入提醒纪念日',
          originDate: DateTime.now().add(const Duration(days: 40)),
          type: AnniversaryType.memorial,
          remind: true,
        ),
      ]);

      expect(summary.inserted, 1);
      expect(summary.reminderSyncIssue, contains('提醒服务未初始化'));
      expect(provider.lastReminderSyncIssue, summary.reminderSyncIssue);
    },
  );

  test(
    'AnniversaryProvider keeps birthday memorial and countdown types distinct',
    () async {
      final provider = AnniversaryProvider();
      await provider.loadFromStorage();

      await provider.add(
        Anniversary(
          id: 'birthday-1',
          title: '生日',
          originDate: DateTime(2026, 7, 1),
          type: AnniversaryType.birthday,
        ),
      );
      await provider.add(
        Anniversary(
          id: 'memorial-1',
          title: '纪念日',
          originDate: DateTime(2026, 8, 1),
          type: AnniversaryType.memorial,
        ),
      );
      await provider.add(
        Anniversary(
          id: 'normal-1',
          title: '单次倒数',
          originDate: DateTime(2026, 9, 1),
          type: AnniversaryType.normal,
        ),
      );

      expect(provider.birthdays.map((item) => item.id), ['birthday-1']);
      expect(provider.memorials.map((item) => item.id), ['memorial-1']);
      expect(provider.countdowns.map((item) => item.id), ['normal-1']);
    },
  );

  test(
    'AnniversaryProvider bulk import rejects countdown type records',
    () async {
      final provider = AnniversaryProvider();
      await provider.loadFromStorage();

      final summary = await provider.importAnniversaries([
        Anniversary(
          id: 'import-birthday',
          title: '生日',
          originDate: DateTime(2026, 7, 1),
          type: AnniversaryType.birthday,
        ),
        Anniversary(
          id: 'import-countdown',
          title: '不应导入的倒数日',
          originDate: DateTime(2026, 8, 1),
          type: AnniversaryType.normal,
        ),
      ]);

      expect(summary.inserted, 1);
      expect(summary.skippedDuplicates, 1);
      expect(provider.birthdays.map((item) => item.id), ['import-birthday']);
      expect(provider.countdowns, isEmpty);
    },
  );

  test('AnniversaryProvider does not migrate legacy countdown storage', () async {
    SharedPreferences.setMockInitialValues({
      'duoyi_countdowns': [
        '{"id":"legacy-countdown","title":"旧倒数","targetDate":"2026-09-01T00:00:00.000"}',
      ],
    });
    final provider = AnniversaryProvider();

    await provider.loadFromStorage();

    expect(provider.countdowns, isEmpty);
    expect(provider.items, isEmpty);
  });
}
