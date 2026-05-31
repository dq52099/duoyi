import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test('通知栏今日任务进展开关默认关闭并可持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.notificationTodayProgress, isFalse);

    await provider.setNotificationTodayProgress(true);
    expect(provider.notificationTodayProgress, isTrue);

    final reloaded = PreferencesProvider();
    await reloaded.loadFromStorage();
    expect(reloaded.notificationTodayProgress, isTrue);
  });

  test('通知栏今日任务进展开关与快捷添加互不覆盖', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    await provider.setNotificationQuickAdd(true);
    await provider.setNotificationTodayProgress(true);
    expect(provider.notificationQuickAdd, isTrue);
    expect(provider.notificationTodayProgress, isTrue);

    await provider.setNotificationTodayProgress(false);
    expect(provider.notificationQuickAdd, isTrue);
    expect(provider.notificationTodayProgress, isFalse);

    final reloaded = PreferencesProvider();
    await reloaded.loadFromStorage();
    expect(reloaded.notificationQuickAdd, isTrue);
    expect(reloaded.notificationTodayProgress, isFalse);
  });

  test('通知栏今日任务进展开关只广播自身偏好键', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    final changedKeys = <Set<String>>[];

    final provider = PreferencesProvider();
    provider.onChangedKeys = (keys) => changedKeys.add(keys.toSet());
    await provider.loadFromStorage();

    await provider.setNotificationTodayProgress(true);
    await provider.setNotificationQuickAdd(true);
    await provider.setNotificationTodayProgress(false);

    expect(changedKeys, [
      {'pref_notification_today_progress'},
      {'pref_notification_quick_add'},
      {'pref_notification_today_progress'},
    ]);
  });

  test('通知、弹窗和闹钟日程槽都可切换为关闭', () {
    for (final kind in const [
      ReminderKind.push,
      ReminderKind.popup,
      ReminderKind.alarm,
    ]) {
      final disabled = DailyReminderSlot(
        enabled: true,
        kind: kind,
        hour: 8,
        minute: 30,
      ).copyWith(kind: ReminderKind.off);

      expect(disabled.enabled, isFalse);
      expect(disabled.kind, ReminderKind.off);
      expect(
        effectiveDailyReminderScheduleSlots([disabled]),
        isEmpty,
        reason: '${kind.name} 切到关闭后不能继续参与通知栏/提醒日程同步。',
      );
    }
  });
}
