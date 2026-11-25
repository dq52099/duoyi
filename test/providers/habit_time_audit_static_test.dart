import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('时间单位习惯按剩余目标量写入时间足迹并可完整撤销', () {
    final habitProvider = File(
      'lib/providers/habit_provider.dart',
    ).readAsStringSync();
    final timeAuditProvider = File(
      'lib/providers/time_audit_provider.dart',
    ).readAsStringSync();
    final habitScreen = File(
      'lib/screens/habit_screen.dart',
    ).readAsStringSync();

    expect(
      habitProvider,
      matches(RegExp(r'Future<void>\s+incrementHabitForDate\(\s*String id,')),
    );
    expect(habitProvider, matches(RegExp(r'\{\s*int\? amount\s*,?\s*\}')));
    expect(
      habitProvider,
      contains('final previousCount = habit.completions[key] ?? 0;'),
    );
    expect(
      habitProvider,
      contains('final increment = amount ?? _defaultCheckInAmount('),
    );
    expect(habitProvider, contains("'amount': increment"));
    expect(habitProvider, contains('amount: increment,'));
    expect(
      habitProvider,
      contains('TimeAuditProvider.habitUnitSeconds(habit) == null'),
    );
    expect(
      habitProvider,
      contains('final remaining = habit.targetCount - currentCount;'),
    );
    expect(habitProvider, contains('return remaining > 0 ? remaining : 1;'));

    expect(
      habitProvider,
      matches(RegExp(r'habitCheckInRecordedAmount\(\s*habit,')),
    );
    expect(
      habitProvider,
      matches(RegExp(r'\?\?\s*_defaultUndoAmount\(habit, v\)')),
    );
    expect(habitProvider, contains('final nextHabits = _snapshot();'));
    expect(habitProvider, contains('final habit = nextHabits[idx];'));
    expect(habitProvider, contains('if (next <= 0)'));

    expect(timeAuditProvider, contains('static int? habitUnitSeconds('));
    expect(timeAuditProvider, contains('int? habitCheckInRecordedAmount('));
    expect(
      timeAuditProvider,
      contains('final amount = entry.durationSeconds ~/ unitSeconds;'),
    );
    expect(
      timeAuditProvider,
      contains('return unitSeconds == null ? null : count * unitSeconds;'),
    );

    expect(habitScreen, contains('_defaultDisplayCheckInAmount('));
    expect(
      habitScreen,
      contains('TimeAuditProvider.habitUnitSeconds(habit) == null'),
    );
  });
}
