import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日历提供一等三日视图入口和导航', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('TabController(length: 5'));
    expect(source, contains("PopupMenuItem(value: 'three_day'"));
    expect(source, contains("const Tab(text: '三日')"));
    expect(source, contains('_previousThreeDays'));
    expect(source, contains('_nextThreeDays'));
    expect(source, contains("3 => '前三天'"));
    expect(source, contains("3 => '后三天'"));
    expect(source, contains('threeDayLabel'));
    expect(source, contains("const ValueKey('calendar_three_day_view')"));
  });

  test('三日视图复用日程聚合筛选和日视图详情能力', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('class _CalendarThreeDayView'));
    expect(source, contains('List.generate('));
    expect(source, contains('3,'));
    expect(source, contains('class _ThreeDayLane'));
    expect(source, contains('calendarProvider.getEventsForDate('));
    expect(source, contains('activeTypes: activeTypes'));
    expect(source, contains('projectKey: projectKey'));
    expect(source, contains('CalendarDayAgenda('));
  });

  test('三日视图桌面并列展示窄屏横向滚动', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('LayoutBuilder('));
    expect(source, contains('constraints.maxWidth >= 900'));
    expect(source, contains('Expanded('));
    expect(source, contains('VerticalDivider('));
    expect(source, contains('SingleChildScrollView('));
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('width: 380'));
  });

  test('日历聚合不在 build 同步执行', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final projectOptionsStart = source.indexOf(
      'List<_CalendarProjectOption> _projectOptions',
      buildStart,
    );
    expect(buildStart, greaterThanOrEqualTo(0));
    expect(projectOptionsStart, greaterThan(buildStart));
    final buildBody = source.substring(buildStart, projectOptionsStart);

    expect(source, contains('void _scheduleCalendarRebuild({'));
    expect(source, contains('Object? _lastCalendarInputSignature;'));
    expect(source, contains('Object _calendarInputSignature({'));
    expect(source, contains('calendarProvider.sourceRevision'));
    expect(
      source,
      contains('if (_lastCalendarInputSignature == signature) return;'),
    );
    expect(source, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(source, contains('if (!mounted) return;'));
    expect(buildBody, contains('_scheduleCalendarRebuild('));
    expect(buildBody, contains('todoProvider: todoProvider'));
    expect(buildBody, contains('timeAuditProvider: timeAuditProvider'));
    expect(buildBody, isNot(contains('calendarProvider.rebuild(')));
  });

  test('日历日期导航头避免窄屏固定最小宽度溢出', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final headerSource = source.substring(
      source.indexOf('class _CalendarNavigationHeader'),
      source.indexOf('class _NavIconButton'),
    );

    expect(
      headerSource,
      contains('final compact = constraints.maxWidth < 360'),
    );
    expect(headerSource, contains('? const Size(0, 46)'));
    expect(headerSource, contains(': const Size(double.infinity, 54)'));
    expect(headerSource, contains('dimension: compact ? 40 : 44'));
    expect(headerSource, contains('label: Text('));
    expect(headerSource, contains('TextOverflow.ellipsis'));
    expect(headerSource, isNot(contains('minWidth: 180')));
  });
}
