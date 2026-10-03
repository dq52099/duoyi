import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/reminder_sinks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePopupSink implements ReminderInAppOnlyPopupSink {
  final List<Map<String, Object?>> once = [];
  final List<Map<String, Object?>> inAppOnlyOnce = [];
  final List<int> cancelled = [];
  bool failOnce = false;
  bool failInAppOnly = false;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (failOnce) throw StateError('fallback unavailable');
    once.add({
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleInAppOnlyOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (failInAppOnly) throw StateError('popup unavailable');
    inAppOnlyOnce.add({
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
    });
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {}
}

class _FakeAlarmSink implements ReminderAlarmSink {
  final List<Map<String, Object?>> once = [];
  final List<int> cancelled = [];

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {
    once.add({
      'id': id,
      'title': title,
      'body': body,
      'when': when,
      'payload': payload,
      'fullScreen': fullScreen,
      'vibrate': vibrate,
      'snoozeMinutes': snoozeMinutes,
      'repeatCount': repeatCount,
    });
  }

  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('定时诊断提醒', () {
    test('弹出测试注册 popup sink 并写入默认未读历史', () async {
      final service = NotificationService();
      final popup = _FakePopupSink();
      final alarm = _FakeAlarmSink();

      await service.sendScheduledTest(
        delay: const Duration(hours: 1),
        reminderKind: ReminderKind.popup,
        popup: popup,
        alarm: alarm,
        cancelSystemNotification: false,
      );

      expect(popup.cancelled, contains(919005));
      expect(alarm.cancelled, contains(919005));
      expect(popup.once, isEmpty);
      expect(popup.inAppOnlyOnce, hasLength(1));
      expect(popup.inAppOnlyOnce.single['id'], 919005);
      expect(popup.inAppOnlyOnce.single['title'], '多仪 · 弹出提醒测试');
      expect(popup.inAppOnlyOnce.single['payload'], 'duoyi://tab/mine');
      expect(service.history, hasLength(1));
      expect(service.history.single.isRead, isFalse);
      expect(service.history.single.body, contains('应用内弹出提醒'));
      expect(service.unreadCount, 1);
    });

    test('弹出测试失败不会退回普通通知兜底', () async {
      final service = NotificationService();
      final popup = _FakePopupSink()..failInAppOnly = true;
      final alarm = _FakeAlarmSink();

      final scheduled = await service.sendScheduledTest(
        delay: const Duration(hours: 1),
        reminderKind: ReminderKind.popup,
        popup: popup,
        alarm: alarm,
        cancelSystemNotification: false,
      );

      expect(scheduled, isFalse);
      expect(popup.inAppOnlyOnce, isEmpty);
      expect(service.history, isEmpty);
      expect(service.lastScheduleIssue?.title, '定时弹出测试注册失败');
      expect(service.lastScheduleIssue?.message, contains('不会退回普通通知'));
    });

    test('弹出兜底测试注册 popup sink 的普通通知兜底', () async {
      final service = NotificationService();
      final popup = _FakePopupSink();
      final alarm = _FakeAlarmSink();

      await service.sendScheduledTest(
        delay: const Duration(hours: 1),
        reminderKind: ReminderKind.popup,
        popupInAppOnly: false,
        popup: popup,
        alarm: alarm,
        cancelSystemNotification: false,
      );

      expect(popup.cancelled, contains(919005));
      expect(alarm.cancelled, contains(919005));
      expect(popup.inAppOnlyOnce, isEmpty);
      expect(popup.once, hasLength(1));
      expect(popup.once.single['id'], 919005);
      expect(popup.once.single['title'], '多仪 · 弹出兜底测试');
      expect(popup.once.single['payload'], 'duoyi://tab/mine');
      expect(service.history, hasLength(1));
      expect(service.history.single.body, contains('弹出提醒 + 通知兜底'));
      expect(service.unreadCount, 1);
    });

    test('闹钟和全屏闹钟测试分别注册 alarm sink 参数', () async {
      final service = NotificationService();
      final popup = _FakePopupSink();
      final alarm = _FakeAlarmSink();

      await service.sendScheduledTest(
        delay: const Duration(hours: 1),
        reminderKind: ReminderKind.alarm,
        fullScreenAlarm: false,
        popup: popup,
        alarm: alarm,
        cancelSystemNotification: false,
      );
      await service.sendScheduledTest(
        delay: const Duration(hours: 2),
        reminderKind: ReminderKind.alarm,
        popup: popup,
        alarm: alarm,
        cancelSystemNotification: false,
      );

      expect(popup.cancelled, containsAll(<int>[919006, 919007]));
      expect(alarm.cancelled, containsAll(<int>[919006, 919007]));
      expect(alarm.once, hasLength(2));
      expect(alarm.once[0]['id'], 919006);
      expect(alarm.once[0]['title'], '多仪 · 闹钟测试');
      expect(alarm.once[0]['fullScreen'], isFalse);
      expect(alarm.once[0]['snoozeMinutes'], 0);
      expect(alarm.once[1]['id'], 919007);
      expect(alarm.once[1]['title'], '多仪 · 全屏闹钟测试');
      expect(alarm.once[1]['fullScreen'], isTrue);
      expect(alarm.once[1]['snoozeMinutes'], 5);
      expect(service.history.map((item) => item.id), ['919007', '919006']);
      expect(service.history.every((item) => !item.isRead), isTrue);
      expect(service.history.first.body, contains('全屏闹钟提醒'));
      expect(service.history.last.body, contains('闹钟提醒'));
      expect(service.unreadCount, 2);
    });
  });
}
