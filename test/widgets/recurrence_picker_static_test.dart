import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('RecurrencePicker exposes manual max occurrence editing', () {
    final source = File(
      'lib/widgets/recurrence_picker.dart',
    ).readAsStringSync();

    for (final snippet in [
      'final bool supportMaxOccurrences',
      'this.supportMaxOccurrences = true',
      'bool supportMaxOccurrences = true',
      'late final TextEditingController _maxOccurrencesCtrl',
      '_maxOccurrences = widget.initial.maxOccurrences',
      'subtitle: widget.supportMaxOccurrences',
      'final controlText = appSecondaryControlTextStyle(context)',
      'final labelText = appSecondaryControlLabelStyle(context)',
      'child: AppSecondaryControlTheme(',
      'labelStyle: controlText',
      'style: controlText',
      'ReminderEditorUiCopy.weeklyDaysLabel',
      'ReminderEditorUiCopy.recurrenceSubtitleWithMax',
      'ReminderEditorUiCopy.recurrenceSubtitleWithoutMax',
      '!widget.supportMaxOccurrences',
      'ReminderEditorUiCopy.maxOccurrencesLabel',
      'ReminderEditorUiCopy.maxOccurrencesHelper',
      'ReminderEditorUiCopy.clearMaxOccurrencesTooltip',
      '_maxOccurrencesCtrl.clear()',
    ]) {
      expect(source, contains(snippet));
    }
  });

  test('Todo detail recurrence subtitle uses the complete rule label', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('subtitle: Text(_todo.recurrence.label)'));
  });

  test('Goal edit hides max occurrences because goal engine is date-based', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();

    expect(source, contains('supportMaxOccurrences: false'));
  });
}
