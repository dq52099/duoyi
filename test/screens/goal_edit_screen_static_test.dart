import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('目标编辑页通过 RecurrenceEngine 计算下一派发日并跳过节假日', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();
    final screen = File('lib/screens/goal_screen.dart').readAsStringSync();
    final recurrence = File(
      'lib/services/recurrence_engine.dart',
    ).readAsStringSync();
    final holiday = File(
      'lib/services/holiday_calendar.dart',
    ).readAsStringSync();

    expect(source, contains("import '../services/recurrence_engine.dart';"));
    expect(source, contains('bool _skipHolidays = false;'));
    expect(source, contains('_skipHolidays = g?.skipHolidays ?? false;'));
    expect(source, contains('_SkipHolidaysSection('));
    expect(source, contains('enabled: _skipHolidays'));
    expect(
      source,
      contains('onChange: (v) => setState(() => _skipHolidays = v)'),
    );
    expect(source, contains('nextDispatchLabel: _nextDispatchLabel()'));
    expect(source, contains('RecurrenceEngine.nextOccurrence'));
    expect(source, contains('skipHolidays: _skipHolidays'));
    expect(source, contains("import '../models/workspace.dart';"));
    expect(source, contains("import '../providers/share_provider.dart';"));
    expect(source, contains("String _workspaceId = 'private';"));
    expect(
      source,
      contains('_workspaceId = _normalizeWorkspaceId(g?.workspaceId);'),
    );
    expect(source, contains('workspaceId: _workspaceId,'));
    expect(source, contains('_WorkspaceSection('));
    expect(source, contains('AppDropdownField<String>'));
    expect(source, contains('initialValue: current,'));
    expect(source, contains('enabled: canEdit'));
    expect(
      source,
      contains("canEdit && (option.id == 'private' || optionRole.canEdit)"),
    );
    expect(source, contains('你在这个共享空间中只有查看权限'));
    expect(source, contains('_canEditWorkspace('));
    expect(
      source,
      contains(
        'onPressed: canEditCurrentWorkspace ? _deleteCurrentGoal : null',
      ),
    );
    expect(source, contains('onPressed: canEditCurrentWorkspace'));
    expect(source, contains('_persist(pop: true)'));
    expect(
      source,
      contains('final shareProvider = context.watch<ShareProvider?>();'),
    );
    expect(source, contains('shareProvider?.canEdit(current) ?? true'));
    expect(screen, contains("import '../providers/share_provider.dart';"));
    expect(screen, contains('_SharedGoalBadge('));
    expect(screen, contains('goal.workspaceId.trim()'));
    expect(screen, contains('_workspaceLabel('));

    expect(recurrence, contains('class RecurrenceEngine'));
    expect(recurrence, contains('HolidayCalendar.isHoliday(candidate!)'));
    expect(recurrence, contains('materializeTodayFromRecurring'));
    expect(holiday, contains('class HolidayCalendar'));
    expect(holiday, contains('2026'));
    expect(holiday, contains('workMakeupDays'));
    expect(holiday, contains('updateFrom'));
  });
}
