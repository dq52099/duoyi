import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
  });

  test('CalendarEventType.label 跟随当前语言', () {
    expect(CalendarEventType.event.label, '日程');
    expect(CalendarEventType.todo.label, '待办');
    expect(CalendarEventType.timeEntry.label, '时间足迹');

    I18n.setLocale(AppLocale.en);
    expect(CalendarEventType.event.label, 'Event');
    expect(CalendarEventType.todo.label, 'Task');
    expect(CalendarEventType.timeEntry.label, 'Time log');
  });

  test('TimeEntrySource.label 跟随当前语言', () {
    expect(TimeEntrySource.manual.label, '手动');
    expect(TimeEntrySource.pomodoro.label, '番茄钟');

    I18n.setLocale(AppLocale.en);
    expect(TimeEntrySource.manual.label, 'Manual');
    expect(TimeEntrySource.pomodoro.label, 'Pomodoro');
  });

  test('TimeEntryCategory.label 跟随当前语言', () {
    expect(TimeEntryCategory.focus.label, '专注');
    expect(TimeEntryCategory.other.label, '其他');

    I18n.setLocale(AppLocale.en);
    expect(TimeEntryCategory.focus.label, 'Focus');
    expect(TimeEntryCategory.other.label, 'Other');
  });

  test('TodoPriority.label 跟随当前语言', () {
    expect(TodoPriority.none.label, '无');
    expect(TodoPriority.urgent.label, '紧急');

    I18n.setLocale(AppLocale.en);
    expect(TodoPriority.none.label, 'None');
    expect(TodoPriority.urgent.label, 'Urgent');
  });
}
