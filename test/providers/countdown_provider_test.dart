import 'dart:convert';

import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'CountdownProvider skips invalid stored records and supports new adds',
    () async {
      SharedPreferences.setMockInitialValues({
        'duoyi_countdowns': [
          '{bad json',
          jsonEncode({
            'id': 'legacy-1',
            'name': '旧倒数',
            'date': '2026-06-01T00:00:00.000',
            'remindHour': 99,
            'remindMinute': -3,
          }),
        ],
      });

      final provider = CountdownProvider();
      await provider.loadFromStorage();

      expect(provider.items, hasLength(1));
      expect(provider.items.single.title, '旧倒数');
      expect(provider.items.single.remindHour, 23);
      expect(provider.items.single.remindMinute, 0);

      await provider.addItem(
        CountdownItem(
          id: 'new-1',
          title: '补丁发布日期',
          targetDate: DateTime(2026, 6, 15),
        ),
      );

      expect(provider.items.map((item) => item.title), contains('补丁发布日期'));

      final reloaded = CountdownProvider();
      await reloaded.loadFromStorage();

      expect(reloaded.items.map((item) => item.title), ['旧倒数', '补丁发布日期']);
    },
  );

  test(
    'CountdownProvider syncs reminders after update delete for existing records',
    () async {
      SharedPreferences.setMockInitialValues({
        'duoyi_countdowns': [
          jsonEncode({
            'id': 'countdown-sync',
            'title': '补丁发布日期',
            'targetDate': DateTime.now()
                .add(const Duration(days: 3))
                .toIso8601String(),
            'remind': true,
          }),
        ],
      });
      final scheduler = RecordingReminderScheduler();
      final provider = CountdownProvider()..scheduler = scheduler;
      await provider.loadFromStorage();
      final item = CountdownItem(
        id: 'countdown-sync',
        title: '补丁发布日期',
        targetDate: DateTime.now().add(const Duration(days: 3)),
        remind: true,
      );

      await provider.updateItem(item.copyWith(title: '补丁发布'));
      expect(scheduler.countdownSyncs, [
        ['countdown-sync'],
      ]);

      await provider.deleteItem(item.id);
      expect(scheduler.countdownSyncs.last, isEmpty);
    },
  );

  test('CountdownProvider imports countdowns and skips duplicates', () async {
    final provider = CountdownProvider();
    await provider.loadFromStorage();

    final item = CountdownItem(
      id: 'countdown-add-normal',
      title: '版本补丁发布',
      targetDate: DateTime(2026, 6, 18),
      category: '发布',
      remind: false,
    );

    await provider.addItem(item);

    expect(provider.items.map((item) => item.id), ['countdown-add-normal']);

    final summary = await provider.importCountdowns([item]);
    expect(summary.inserted, 0);
    expect(summary.skippedDuplicates, 1);
    expect(provider.items.map((item) => item.id), ['countdown-add-normal']);

    final second = CountdownItem(
      id: 'countdown-add-second',
      title: '版本发布会',
      targetDate: DateTime(2026, 6, 20),
      category: '发布',
      remind: false,
    );
    final secondSummary = await provider.importCountdowns([second]);
    expect(secondSummary.inserted, 1);
    expect(secondSummary.skippedDuplicates, 0);

    final reloaded = CountdownProvider();
    await reloaded.loadFromStorage();
    expect(reloaded.items.map((item) => item.id), [
      'countdown-add-normal',
      'countdown-add-second',
    ]);
  });
}
