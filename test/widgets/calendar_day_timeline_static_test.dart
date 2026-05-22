import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日视图按时间线和全天无时间事件分区展示', () {
    final source = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(source, contains("import 'dart:math' as math;"));
    expect(source, contains('final timedEvents = events.where'));
    expect(source, contains('final untimedEvents = events.where'));
    expect(source, contains('_sectionTitle(\'🕘 时间线\')'));
    expect(source, contains('_sectionTitle(\'📝 全天/无时间\')'));
    expect(source, contains('_CalendarDayTimeGrid(date: date'));
    expect(source, contains('..._buildTimeline(context, untimedEvents)'));
  });

  test('日视图时间线提供 24 小时刻度和按分钟定位的事件块', () {
    final source = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(source, contains('class _CalendarDayTimeGrid'));
    expect(source, contains('static const double _hourHeight'));
    expect(source, contains('static const double _timeColumnWidth'));
    expect(source, contains('for (var hour = 0; hour < 24; hour++)'));
    expect(source, contains('class _TimelineHourRow'));
    expect(source, contains('Positioned('));
    expect(source, contains('top: clampedTop'));
    expect(source, contains('height: clampedHeight'));
    expect(source, contains('_minutesFromDayStart(start) / 60 * _hourHeight'));
    expect(source, contains('_overlapLane(event, index)'));
    expect(source, contains('overlapLane * 10.0'));
  });

  test('时间线事件支持跨日边界裁剪和短块紧凑卡片', () {
    final source = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(source, contains('DateTime _eventStartOnDay('));
    expect(source, contains('DateTime _eventEndOnDay('));
    expect(source, contains('int _minutesFromDayStart(DateTime value)'));
    expect(source, contains('final dayEnd = _dateOnly(day).add'));
    expect(source, contains('math.max(30, end.difference(start).inMinutes)'));
    expect(source, contains('compact: clampedHeight < 88'));
    expect(source, contains('final bool compact'));
    expect(source, contains('_buildCompactContent(context, e)'));
    expect(source, contains('_buildRegularContent(context, e)'));
    expect(source, contains('_DraggableEventCard(event: event'));
  });
}
