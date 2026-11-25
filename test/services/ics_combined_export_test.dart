import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/services/ics_exporter.dart';

void main() {
  late AppLocale savedLocale;

  setUp(() {
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(savedLocale));

  test('combined export has one envelope for mixed and empty inputs', () {
    final normalEvent = _event(
      id: 'local-mixed',
      title: 'Mixed event',
      date: DateTime(2026, 3, 7),
      type: CalendarEventType.event,
    );
    final normalAnniversary = _anniversary(
      id: 'countdown-mixed',
      title: 'One time',
      date: DateTime(2099, 4, 9),
      type: AnniversaryType.normal,
    );

    final mixed = IcsExporter.combine(
      events: [normalEvent],
      anniversaries: [normalAnniversary],
    );
    final empty = IcsExporter.combine();

    for (final text in [mixed, empty]) {
      expect(_countLine(text, 'BEGIN:VCALENDAR'), 1);
      expect(_countLine(text, 'END:VCALENDAR'), 1);
      expect(_countLine(text, 'VERSION:2.0'), 1);
      expect(_countLine(text, 'PRODID:-//Duoyi//ZH//CN'), 1);
    }
    expect(_vevents(mixed), hasLength(2));
    expect(_vevents(empty), isEmpty);
    expect(empty, contains('X-WR-CALNAME:多仪 · 日程\n'));
    expect(empty, endsWith('END:VCALENDAR\n'));
  });

  test(
    'combined events preserve protocol fields and authored text in both locales',
    () {
      final event = _event(
        id: 'uid-stable-7',
        title: '事件, 原题; 路径\\名称\n第二行',
        date: DateTime(2026, 3, 7),
        type: CalendarEventType.anniversary,
      );
      final anniversary = _anniversary(
        id: 'birthday-A',
        title: '妈妈生日 原文',
        description: '描述, 第一行;\r\n第二行\\尾',
        date: DateTime(2000, 1, 1),
        type: AnniversaryType.birthday,
      );
      final localNormalAnniversary = _anniversary(
        id: 'countdown-A',
        title: '一次性原文',
        date: DateTime(2099, 4, 9),
        type: AnniversaryType.normal,
      );
      final customAnniversary = _anniversary(
        id: 'custom-A',
        title: '自定义周期原文',
        date: DateTime(2030, 5, 10),
        type: AnniversaryType.custom,
      );

      I18n.setLocale(AppLocale.zh);
      final zh = IcsExporter.combine(
        events: [event],
        anniversaries: [anniversary, localNormalAnniversary, customAnniversary],
      );
      I18n.setLocale(AppLocale.en);
      final en = IcsExporter.combine(
        events: [event],
        anniversaries: [anniversary, localNormalAnniversary, customAnniversary],
      );

      expect(_countLine(zh, 'BEGIN:VCALENDAR'), 1);
      expect(_countLine(en, 'BEGIN:VCALENDAR'), 1);
      expect(zh, contains('X-WR-CALNAME:多仪 · 日程\n'));
      expect(en, contains('X-WR-CALNAME:Duoyi · Calendar\n'));
      expect(zh, contains('PRODID:-//Duoyi//ZH//CN'));
      expect(en, contains('PRODID:-//Duoyi//ZH//CN'));
      expect(zh, contains(r'UID:uid-stable-7@duoyi'));
      expect(en, contains(r'UID:uid-stable-7@duoyi'));
      expect(zh, contains('CATEGORIES:anniversary'));
      expect(en, contains('CATEGORIES:anniversary'));
      expect(zh, contains(r'SUMMARY:事件\, 原题\; 路径\\名称\n第二行'));
      expect(en, contains(r'SUMMARY:事件\, 原题\; 路径\\名称\n第二行'));

      final birthday = _veventByUid(zh, 'anni_birthday-A@duoyi');
      final normal = _veventByUid(zh, 'anni_countdown-A@duoyi');
      final custom = _veventByUid(zh, 'anni_custom-A@duoyi');
      expect(birthday, contains('SUMMARY:妈妈生日 原文'));
      expect(birthday, contains(r'DESCRIPTION:描述\, 第一行\;\n第二行\\尾'));
      expect(birthday, contains('RRULE:FREQ=YEARLY'));
      expect(normal, isNot(contains('RRULE:')));
      expect(custom, contains('RRULE:FREQ=YEARLY'));
      expect(en, contains('SUMMARY:妈妈生日 原文'));
      expect(en, contains(r'DESCRIPTION:描述\, 第一行\;\n第二行\\尾'));
      expect(_vevents(zh), hasLength(4));
      expect(_vevents(en), hasLength(4));

      final eventVevent = _veventByUid(zh, 'uid-stable-7@duoyi');
      expect(eventVevent, contains('DTSTART;VALUE=DATE:20260307'));
      expect(eventVevent, contains('DTEND;VALUE=DATE:20260308'));
      expect(normal, contains('DTSTART;VALUE=DATE:20990409'));
      expect(normal, contains('DTEND;VALUE=DATE:20990410'));
      for (final vevent in _vevents(zh)) {
        final stamp = _lineValue(vevent, 'DTSTAMP:');
        expect(stamp, matches(RegExp(r'^\d{8}T\d{6}Z$')));
      }
    },
  );

  test('explicit empty combined calendar name stays empty', () {
    final text = IcsExporter.combine(
      events: [_event(id: 'named-event', date: DateTime(2026, 1, 2))],
      calendarName: '',
    );

    expect(text, contains('X-WR-CALNAME:\n'));
    expect(text, isNot(contains('X-WR-CALNAME:多仪 · 日程')));
    expect(_countLine(text, 'BEGIN:VCALENDAR'), 1);
    expect(_countLine(text, 'END:VCALENDAR'), 1);
  });

  test(
    'legacy APIs remain independent one-container exports with old defaults',
    () {
      final event = _event(id: 'legacy-event', date: DateTime(2026, 6, 1));
      final anniversary = _anniversary(
        id: 'legacy-anniversary',
        title: 'Legacy birthday',
        date: DateTime(2000, 6, 1),
        type: AnniversaryType.birthday,
      );

      I18n.setLocale(AppLocale.zh);
      final zhEvents = IcsExporter.fromEvents([event]);
      final zhAnniversaries = IcsExporter.fromAnniversaries([anniversary]);
      I18n.setLocale(AppLocale.en);
      final enEvents = IcsExporter.fromEvents([event]);
      final enAnniversaries = IcsExporter.fromAnniversaries([anniversary]);

      for (final text in [
        zhEvents,
        zhAnniversaries,
        enEvents,
        enAnniversaries,
      ]) {
        expect(_countLine(text, 'BEGIN:VCALENDAR'), 1);
        expect(_countLine(text, 'END:VCALENDAR'), 1);
      }
      expect(zhEvents, contains('X-WR-CALNAME:多仪 · 日程\n'));
      expect(zhAnniversaries, contains('X-WR-CALNAME:多仪 · 纪念日\n'));
      expect(enEvents, contains('X-WR-CALNAME:Duoyi · Calendar\n'));
      expect(enAnniversaries, contains('X-WR-CALNAME:Duoyi · Anniversaries\n'));
      expect(_vevents(zhEvents), hasLength(1));
      expect(_vevents(zhAnniversaries), hasLength(1));
      expect(zhEvents, contains('UID:legacy-event@duoyi'));
      expect(zhAnniversaries, contains('UID:anni_legacy-anniversary@duoyi'));
    },
  );
}

CalendarEvent _event({
  required String id,
  String title = 'Event',
  required DateTime date,
  CalendarEventType type = CalendarEventType.event,
}) => CalendarEvent(
  id: id,
  title: title,
  date: date,
  type: type,
  color: Colors.blue,
);

Anniversary _anniversary({
  required String id,
  required String title,
  String? description,
  required DateTime date,
  required AnniversaryType type,
}) => Anniversary(
  id: id,
  title: title,
  description: description,
  originDate: date,
  type: type,
);

int _countLine(String text, String line) =>
    text.split('\n').where((candidate) => candidate == line).length;

List<String> _vevents(String text) {
  final result = <String>[];
  StringBuffer? current;
  for (final line in text.split('\n')) {
    if (line == 'BEGIN:VEVENT') current = StringBuffer();
    final event = current;
    if (event == null) continue;
    event.writeln(line);
    if (line == 'END:VEVENT') {
      result.add(event.toString());
      current = null;
    }
  }
  return result;
}

String _veventByUid(String text, String uid) =>
    _vevents(text).singleWhere((vevent) => vevent.contains('UID:$uid\n'));

String? _lineValue(String text, String prefix) {
  for (final line in text.split('\n')) {
    if (line.startsWith(prefix)) return line.substring(prefix.length);
  }
  return null;
}
