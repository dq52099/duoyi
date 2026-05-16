import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/smart_date_parser.dart';

void main() {
  // 固定 now = 2026-05-15（星期五）便于断言。
  final now = DateTime(2026, 5, 15, 10, 0);

  group('SmartDateParser 基础日期', () {
    test('明天', () {
      final r = SmartDateParser.parse('明天', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime!.year, 2026);
      expect(r.dateTime!.month, 5);
      expect(r.dateTime!.day, 16);
      expect(r.hasTimeOfDay, isFalse);
    });

    test('后天', () {
      final r = SmartDateParser.parse('后天', now: now);
      expect(r.dateTime!.day, 17);
    });

    test('大后天', () {
      final r = SmartDateParser.parse('大后天', now: now);
      expect(r.dateTime!.day, 18);
    });

    test('下周一', () {
      // 2026-05-15 是周五；下周一是 2026-05-18
      final r = SmartDateParser.parse('下周一', now: now);
      expect(r.dateTime!.day, 18);
    });

    test('本周三', () {
      // 2026-05-15 周五；本周三是 5-13（已过），按当前算法返回过往的"本周三"是
      // 不合理的，但解析器按字面计算 → 返回过去的日期。这里只验证落点。
      final r = SmartDateParser.parse('本周三', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime!.weekday, DateTime.wednesday);
    });
  });

  group('SmartDateParser 时间', () {
    test('明天下午3点', () {
      final r = SmartDateParser.parse('明天下午3点', now: now);
      expect(r.isSuccess, isTrue);
      expect(r.dateTime!.day, 16);
      expect(r.dateTime!.hour, 15);
      expect(r.dateTime!.minute, 0);
      expect(r.hasTimeOfDay, isTrue);
    });

    test('今晚8点', () {
      final r = SmartDateParser.parse('今天晚上8点', now: now);
      expect(r.dateTime!.day, 15);
      expect(r.dateTime!.hour, 20);
    });

    test('后天上午9点半', () {
      final r = SmartDateParser.parse('后天上午9点半', now: now);
      expect(r.dateTime!.day, 17);
      expect(r.dateTime!.hour, 9);
      expect(r.dateTime!.minute, 30);
    });

    test('下午3点30分', () {
      final r = SmartDateParser.parse('下午3点30分', now: now);
      expect(r.dateTime!.day, 15);
      expect(r.dateTime!.hour, 15);
      expect(r.dateTime!.minute, 30);
    });

    test('14:30 时间格式', () {
      final r = SmartDateParser.parse('14:30', now: now);
      expect(r.dateTime!.hour, 14);
      expect(r.dateTime!.minute, 30);
    });
  });

  group('SmartDateParser 失败回退', () {
    test('空字符串', () {
      expect(SmartDateParser.parse('').isSuccess, isFalse);
    });

    test('无法识别', () {
      expect(SmartDateParser.parse('完全没有日期信息的句子').isSuccess, isFalse);
    });

    test('非法小时', () {
      expect(SmartDateParser.parse('明天99点').isSuccess, isFalse);
    });
  });
}
