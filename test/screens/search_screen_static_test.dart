import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('全局搜索覆盖日历日程并可跳到对应日期', () {
    final searchScreen = File(
      'lib/screens/search_screen.dart',
    ).readAsStringSync();
    final globalSearch = File('lib/core/global_search.dart').readAsStringSync();
    final calendarScreen = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();

    expect(globalSearch, contains('SearchKind.calendarEvent'));
    expect(globalSearch, contains('List<CalendarEvent> calendarEvents'));
    expect(globalSearch, contains('event.type == CalendarEventType.event'));
    expect(globalSearch, contains('hit(event.title)'));
    expect(globalSearch, contains('hit(event.subtitle)'));
    expect(globalSearch, contains('hit(event.note)'));
    expect(globalSearch, contains('hit(event.projectName)'));
    expect(globalSearch, contains("import 'i18n.dart';"));
    expect(
      globalSearch,
      contains("SearchKind.calendarEvent => I18n.tr('search.kind.event')"),
    );
    expect(
      globalSearch,
      contains("SearchKind.timeEntry => I18n.tr('search.kind.time_entry')"),
    );

    expect(
      searchScreen,
      contains("import '../providers/calendar_provider.dart';"),
    );
    expect(searchScreen, contains("import '../core/i18n.dart';"));
    expect(searchScreen, contains("import 'calendar_screen.dart';"));
    expect(
      searchScreen,
      contains('calendarEvents: context.read<CalendarProvider>().events'),
    );
    expect(
      searchScreen,
      contains('countdowns: context.read<CountdownProvider>().items'),
    );
    expect(searchScreen, contains("import 'countdown_screen.dart';"));
    expect(
      searchScreen,
      contains("import '../providers/countdown_provider.dart';"),
    );
    expect(
      searchScreen,
      contains('CountdownScreen(initialCountdownId: h.sourceId)'),
    );
    expect(
      searchScreen,
      contains('AnniversaryScreen(initialAnniversaryId: h.sourceId)'),
    );
    expect(searchScreen, contains('case SearchKind.calendarEvent:'));
    expect(searchScreen, contains('CalendarScreen(initialDate: h.when)'));
    expect(searchScreen, contains("I18n.tr('search.hint')"));
    expect(searchScreen, contains("I18n.tr('search.empty')"));
    expect(searchScreen, contains("I18n.tr('search.results.title')"));
    expect(searchScreen, contains("I18n.tr('search.clear')"));
    expect(searchScreen, contains('appSecondaryMenuItemTextStyle('));
    expect(searchScreen, contains('fontSize: 13'));
    expect(searchScreen, isNot(contains('style: theme.textTheme.titleMedium')));
    expect(searchScreen, isNot(contains('搜索待办 · 日程 · 习惯 · 笔记 · 日记')));
    expect(searchScreen, isNot(contains('输入关键字，搜索全部内容')));
    expect(searchScreen, isNot(contains('搜索结果')));
    expect(searchScreen, isNot(contains('清空搜索')));

    expect(calendarScreen, contains('final DateTime? initialDate;'));
    expect(calendarScreen, contains('this.initialDate'));
    expect(calendarScreen, contains('final initialDate = widget.initialDate;'));
    expect(calendarScreen, contains('_selectedDay = DateTime('));
    expect(
      calendarScreen,
      contains('_focusedMonth = DateTime(initialDate.year, initialDate.month)'),
    );
  });
}
