import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('calendar quick time entry captures a real time segment', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('Text(CalendarUiCopy.quickAddTimeEntryTitle)'));
    expect(source, contains('Future<void> _showQuickAddTimeEntry'));
    expect(source, contains('labelText: CalendarUiCopy.timeEntryTitleLabel'));
    expect(
      source,
      contains('labelText: CalendarUiCopy.timeEntryCategoryLabel'),
    );
    expect(
      source,
      contains('title: Text(CalendarUiCopy.timeEntryStartTimeLabel)'),
    );
    expect(
      source,
      contains('labelText: CalendarUiCopy.timeEntryDurationLabel'),
    );
    expect(source, contains('labelText: CalendarUiCopy.timeEntryNoteLabel'));
    expect(source, contains('AppDropdownField<TimeEntryCategory>'));
    expect(source, contains('for (final c in TimeEntryCategory.values)'));
    expect(source, contains('AppTimePicker.show'));
    expect(source, contains('AppTimePicker.format(_startTime)'));
    expect(source, contains('_startTime.hour'));
    expect(source, contains('_startTime.minute'));
    expect(source, contains('category: _category'));
    expect(source, contains('source: TimeEntrySource.manual'));
    expect(source, contains('note: _noteController.text.trim()'));
    expect(source, contains('_isSameDay(widget.origin.selectedDay, now)'));

    expect(source, isNot(contains('category: TimeEntryCategory.other')));
    expect(source, isNot(contains('DateTime.now().hour')));
    expect(source, isNot(contains('DateTime.now().minute')));
  });
}
