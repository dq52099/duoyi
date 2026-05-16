import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/calendar_sync_service.dart';

const _sampleIcs = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Test//EN
BEGIN:VEVENT
UID:event-001@test
SUMMARY:团队周会
LOCATION:大会议室
DTSTART:20260518T100000
DTEND:20260518T110000
END:VEVENT
BEGIN:VEVENT
UID:event-002@test
SUMMARY:全天活动
DTSTART:20260520
DTEND:20260521
END:VEVENT
BEGIN:VEVENT
UID:event-003@test
SUMMARY:UTC 时间
DTSTART:20260522T060000Z
DTEND:20260522T070000Z
END:VEVENT
END:VCALENDAR
''';

void main() {
  group('IcsParser', () {
    test('解析 VEVENT 列表', () {
      final events = IcsParser.parse(
        _sampleIcs,
        subscriptionId: 'sub1',
        color: Colors.blue,
      );
      expect(events.length, 3);
      expect(events[0].title, '团队周会');
      expect(events[0].subtitle, '大会议室');
      expect(events[0].date, DateTime(2026, 5, 18, 10));
    });

    test('全天事件没有 time', () {
      final events = IcsParser.parse(
        _sampleIcs,
        subscriptionId: 'sub1',
        color: Colors.blue,
      );
      final allDay = events.firstWhere((e) => e.title == '全天活动');
      expect(allDay.date, DateTime(2026, 5, 20));
      expect(allDay.time, isNull);
    });

    test('UTC 时间转换为本地时区', () {
      final events = IcsParser.parse(
        _sampleIcs,
        subscriptionId: 'sub1',
        color: Colors.blue,
      );
      final utcEv = events.firstWhere((e) => e.title == 'UTC 时间');
      expect(utcEv.date.isUtc, isFalse);
    });

    test('行折叠（line folding）正确合并', () {
      const folded = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:fold-001@test
SUMMARY:这是一个被折行
 拆开的标题
DTSTART:20260601T080000
DTEND:20260601T090000
END:VEVENT
END:VCALENDAR
''';
      final events = IcsParser.parse(
        folded,
        subscriptionId: 'sub1',
        color: Colors.blue,
      );
      expect(events.length, 1);
      expect(events.first.title, '这是一个被折行拆开的标题');
    });

    test('转义字符还原', () {
      const escaped = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:esc-001@test
SUMMARY:带换行\\n第二行
DTSTART:20260601T080000
DTEND:20260601T090000
END:VEVENT
END:VCALENDAR
''';
      final events = IcsParser.parse(
        escaped,
        subscriptionId: 'sub1',
        color: Colors.blue,
      );
      expect(events.first.title, contains('\n'));
    });
  });
}
