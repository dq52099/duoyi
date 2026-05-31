import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;

void main() {
  group('Anniversary reminderKind', () {
    test('默认值为 ReminderKind.push', () {
      final a = Anniversary(title: '测试', originDate: DateTime(2026, 6, 1));
      expect(a.reminderKind, ReminderKind.push);
    });

    test('toJson 包含 reminderKind 字段', () {
      final a = Anniversary(
        title: '测试',
        originDate: DateTime(2026, 6, 1),
        reminderKind: ReminderKind.alarm,
      );
      final json = a.toJson();
      expect(json['reminderKind'], ReminderKind.alarm.index);
    });

    test('fromJson 兼容缺少 reminderKind 的旧 JSON', () {
      final json = {
        'id': 'test-id',
        'title': '老纪念日',
        'originDate': '2026-06-01T00:00:00.000',
        'type': 0,
        'calendarType': 0,
        'colorValue': 0xFFE91E63,
        'isPinned': false,
        'remind': true,
        'remindDaysBefore': 1,
        'remindHour': 9,
        'remindMinute': 0,
        'lunarIsLeap': false,
        'createdAt': '2026-01-01T00:00:00.000',
      };
      final a = Anniversary.fromJson(json);
      expect(a.reminderKind, ReminderKind.push);
    });

    test('fromJson 正确解析 reminderKind alarm', () {
      final json = {
        'id': 'test-id',
        'title': '强提醒纪念日',
        'originDate': '2026-06-01T00:00:00.000',
        'type': 0,
        'calendarType': 0,
        'colorValue': 0xFFE91E63,
        'isPinned': false,
        'remind': true,
        'remindDaysBefore': 1,
        'remindHour': 9,
        'remindMinute': 0,
        'reminderKind': ReminderKind.alarm.index,
        'lunarIsLeap': false,
        'createdAt': '2026-01-01T00:00:00.000',
      };
      final a = Anniversary.fromJson(json);
      expect(a.reminderKind, ReminderKind.alarm);
    });

    test('fromJson 遇到越界 reminderKind 回退到 push', () {
      final json = {
        'id': 'test-id',
        'title': '异常提醒方式纪念日',
        'originDate': '2026-06-01T00:00:00.000',
        'type': 0,
        'calendarType': 0,
        'colorValue': 0xFFE91E63,
        'isPinned': false,
        'remind': true,
        'remindDaysBefore': 1,
        'remindHour': 9,
        'remindMinute': 0,
        'reminderKind': 999,
        'lunarIsLeap': false,
        'createdAt': '2026-01-01T00:00:00.000',
      };
      final a = Anniversary.fromJson(json);
      expect(a.reminderKind, ReminderKind.push);
    });

    test('roundtrip toJson → fromJson 保留 reminderKind 和 updatedAt', () {
      final updatedAt = DateTime(2026, 6, 1, 10, 30);
      final original = Anniversary(
        title: '强提醒',
        originDate: DateTime(2026, 6, 1),
        reminderKind: ReminderKind.alarm,
        updatedAt: updatedAt,
      );
      final decoded = Anniversary.fromJson(original.toJson());
      expect(decoded.reminderKind, ReminderKind.alarm);
      expect(decoded.updatedAt, updatedAt);
    });
  });

  group('Anniversary birthday ignoreYear', () {
    test('默认不忽略年份', () {
      final a = Anniversary(
        title: '生日',
        originDate: DateTime(2026, 6, 1),
        type: AnniversaryType.birthday,
      );

      expect((a as dynamic).ignoreYear, isFalse);
      expect(a.toJson()['ignoreYear'], isFalse);
    });

    test('fromJson 和 toJson 保留生日忽略年份开关', () {
      final json = {
        'id': 'birthday-id',
        'title': '生日',
        'originDate': '2026-06-01T00:00:00.000',
        'type': AnniversaryType.birthday.index,
        'calendarType': AnniversaryCalendarType.solar.index,
        'colorValue': 0xFFE91E63,
        'isPinned': false,
        'remind': true,
        'remindDaysBefore': 1,
        'remindHour': 9,
        'remindMinute': 0,
        'reminderKind': ReminderKind.push.index,
        'ignoreYear': true,
        'lunarIsLeap': false,
        'createdAt': '2026-01-01T00:00:00.000',
      };

      final a = Anniversary.fromJson(json);
      expect((a as dynamic).ignoreYear, isTrue);
      expect(a.toJson()['ignoreYear'], isTrue);

      final decoded = Anniversary.fromJson(a.toJson());
      expect((decoded as dynamic).ignoreYear, isTrue);
    });
  });
}
