import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日历提供一等三日视图入口和导航', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('TabController(length: 5'));
    expect(source, contains("value: 'three_day'"));
    expect(source, contains("AppSecondaryMenuText('三日视图')"));
    expect(source, contains("const Tab(height: 34, text: '三日')"));
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
    expect(source, contains('width: constraints.maxWidth < 390'));
    expect(source, contains('? constraints.maxWidth'));
    expect(source, contains(': 380'));
    expect(source, contains('horizontalPadding: 8'));
    expect(source, contains('withValues(alpha: 0.16)'));
    expect(source, contains('withValues(alpha: 0.34)'));
    expect(source, contains('withValues(alpha: 0.18)'));
  });

  test('日历聚合不在 build 同步执行', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
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
    expect(source, contains('item.ignoreYear'));
    expect(providerSource, contains('a.ignoreYear'));
    expect(providerSource, contains('a.updatedAt.millisecondsSinceEpoch'));
  });

  test('日历日期导航头避免窄屏固定最小宽度溢出', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final headerSource = source.substring(
      source.indexOf('class _CalendarNavigationHeader'),
      source.indexOf('class _NavIconButton'),
    );

    expect(
      headerSource,
      contains('final compact = constraints.maxWidth < 390'),
    );
    expect(headerSource, contains('? const Size(0, 52)'));
    expect(headerSource, contains(': const Size(double.infinity, 56)'));
    expect(headerSource, contains('height: compact ? 62 : 68'));
    expect(
      headerSource,
      contains("key: const ValueKey('calendar_navigation_header_bar')"),
    );
    expect(headerSource, contains('dimension: 48'));
    expect(headerSource, contains('Icons.calendar_month_outlined'));
    expect(headerSource, contains('if (!compact) ...['));
    expect(headerSource, contains('child: Text('));
    expect(headerSource, contains('textAlign: TextAlign.center'));
    expect(headerSource, contains('TextOverflow.ellipsis'));
    expect(headerSource, isNot(contains('minWidth: 180')));
  });

  test('月视图使用整页滚动并保留月格任务标记', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final monthViewSource = source.substring(
      source.indexOf('// Month'),
      source.indexOf('// Week'),
    );

    expect(source, contains('double _monthGridHeightFor('));
    expect(source, contains('bool _monthGridShowsLunar('));
    expect(
      source,
      matches(
        RegExp(
          r'final minGridHeight = rows >= 6\s*\?\s*288\.0\s*:\s*\(rows == 5 \?\s*260\.0\s*:\s*236\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'final preferredGridHeight = rows >= 6\s*\?\s*318\.0\s*:\s*\(rows == 5 \?\s*292\.0\s*:\s*268\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(source, isNot(contains('if (availableHeight <= 120)')));
    expect(source, contains('final viewportTarget = availableHeight * 0.46'));
    expect(
      source,
      contains('viewportTarget.clamp(minGridHeight, preferredGridHeight)'),
    );
    expect(source, contains("const ValueKey('calendar_fixed_month_grid')"));
    expect(
      source,
      contains("const ValueKey('calendar_month_global_scrollbar')"),
    );
    expect(source, contains("'calendar_month_global_scroll_view'"));
    expect(source, contains('height: monthGridHeight'));
    expect(monthViewSource, contains('SizedBox('));
    expect(monthViewSource, contains('ListView('));
    expect(monthViewSource, contains('CalendarMonthGrid('));
    expect(
      monthViewSource,
      contains("key: const ValueKey('calendar_month_detail_agenda')"),
    );
    expect(
      monthViewSource,
      isNot(contains("'calendar_month_detail_scroll_region'")),
    );
    expect(monthViewSource, contains('horizontalPadding: 8'));
    expect(monthViewSource, contains('CalendarDayAgenda('));
    expect(monthViewSource, contains('scrollable: false'));
  });

  test('日历详情弹层扩大内容宽高并让详情列表独立滚动', () {
    final source = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();

    expect(source, contains('maxWidth: 860'));
    expect(
      source,
      contains('maxHeight: MediaQuery.sizeOf(context).height * 0.68'),
    );
    expect(source, contains('scrollable: false'));
    expect(
      source,
      contains("key: const ValueKey('calendar_event_detail_scroll_region')"),
    );
  });

  test('日历二级筛选和表单使用小号控件样式', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('Widget _calendarFilterChip({'));
    expect(
      source,
      contains('materialTapTargetSize: MaterialTapTargetSize.padded'),
    );
    expect(source, contains('width: 0.45'));
    expect(source, contains('alpha: 0.16'));
    expect(source, contains('appSecondaryControlLabelStyle(context)'));
    expect(source, contains('Tab(height: 34'));
    expect(source, contains('height: 48'));
    expect(source, contains('AppSecondaryControlTheme('));
    expect(source, contains('AppSecondaryMenuText('));
    expect(source, contains('AppDropdownField<TimeEntryCategory>'));
  });
}
