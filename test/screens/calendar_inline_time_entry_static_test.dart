import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('calendar quick time entry captures a real time segment', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains("title: const Text('记录一段时间')"));
    expect(source, contains('Future<void> _showQuickAddTimeEntry'));
    expect(source, contains("labelText: '事项'"));
    expect(source, contains("labelText: '分类'"));
    expect(source, contains("title: const Text('开始时间')"));
    expect(source, contains("labelText: '时长（分钟）'"));
    expect(source, contains("labelText: '备注'"));
    expect(source, contains('AppDropdownField<TimeEntryCategory>'));
    expect(source, contains('for (final c in TimeEntryCategory.values)'));
    expect(source, contains('AppTimePicker.show'));
    expect(source, contains('AppTimePicker.format(startTime)'));
    expect(source, contains('startTime.hour'));
    expect(source, contains('startTime.minute'));
    expect(source, contains('category: category'));
    expect(source, contains('source: TimeEntrySource.manual'));
    expect(source, contains('note: noteCtrl.text.trim()'));
    expect(source, contains('_isSameDate(_selectedDay, now)'));

    expect(source, isNot(contains('category: TimeEntryCategory.other')));
    expect(source, isNot(contains('DateTime.now().hour')));
    expect(source, isNot(contains('DateTime.now().minute')));
  });
}
