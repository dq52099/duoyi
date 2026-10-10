import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('BackupScreen exposes competitor task and productivity import entries', () {
    final screen = File('lib/screens/backup_screen.dart').readAsStringSync();

    expect(
      screen,
      contains("import '../services/competitor_task_importer.dart';"),
    );
    expect(screen, contains("package:file_selector/file_selector.dart"));
    expect(screen, contains('Future<String?> _pickImportTextFile()'));
    expect(screen, contains('openFile('));
    expect(screen, contains('file?.readAsString()'));
    expect(screen, contains('Future<void> _importTasksFromOtherApps()'));
    expect(
      screen,
      contains('Future<void> _importProductivityDataFromOtherApps()'),
    );
    expect(screen, contains('Future<void> _importProductivityDataFile()'));
    expect(screen, contains('fieldMapping: draft.fieldMapping'));
    expect(screen, contains('final CompetitorFieldMapping fieldMapping;'));
    expect(screen, contains('class _CompetitorImportConfig'));
    expect(screen, contains('const _competitorFieldMappingTargets'));
    expect(
      screen,
      contains('Future<CompetitorFieldMapping?> _editCompetitorFieldMapping'),
    );
    expect(screen, contains('DataSettingsUiCopy.advancedFieldMapping'));
    expect(screen, contains('DataSettingsUiCopy.sourceFieldNameHint'));
    expect(screen, contains('CompetitorFieldMapping({'));
    expect(screen, contains('_fieldMappingSummary(fieldMapping)'));
    expect(screen, contains('_fieldMappingSummary(draft.fieldMapping)'));
    expect(screen, contains('fieldMapping: config.fieldMapping'));
    expect(screen, contains('enum _CompetitorImportSource'));
    expect(screen, contains('_CompetitorImportSource.zhijianTime'));
    expect(screen, contains('_CompetitorImportSource.ticktick'));
    expect(screen, contains('_CompetitorImportSource.todoist'));
    expect(screen, contains('AppDropdownField<_CompetitorImportSource>'));
    expect(screen, contains('initialValue: source'));
    expect(screen, contains('Future<void> _previewAndImportCompetitorData('));
    expect(screen, contains('Future<bool> _confirmCompetitorImportPreview('));
    expect(screen, contains('Future<bool> _showCompetitorImportResult('));
    expect(
      screen,
      contains('final rollbackSnapshot = await BackupService.exportAll();'),
    );
    expect(screen, contains('rollbackSnapshot: rollbackSnapshot'));
    expect(screen, contains('final undo = await _showCompetitorImportResult('));
    expect(
      screen,
      contains('await _rollbackCompetitorImport(rollbackSnapshot)'),
    );
    expect(screen, contains('Future<void> _rollbackCompetitorImport('));
    expect(screen, contains('clearMissing: true'));
    expect(screen, contains('DataSettingsUiCopy.undoImportSuccess'));
    expect(screen, contains('DataSettingsUiCopy.importPreviewTitle'));
    expect(screen, contains('DataSettingsUiCopy.confirmImportPolicyCheckbox'));
    expect(screen, contains('DataSettingsUiCopy.duplicatePolicyNotice'));
    expect(screen, contains('DataSettingsUiCopy.importCompletedTitle'));
    expect(screen, contains('DataSettingsUiCopy.reminderNotFullyRegistered'));
    expect(screen, contains('DataSettingsUiCopy.reminderMoreNeedResaving'));
    expect(screen, contains('DataSettingsUiCopy.undoImport'));
    expect(screen, contains('DataSettingsUiCopy.rollbackHint'));
    expect(
      screen,
      contains('final todoProvider = context.read<TodoProvider>();'),
    );
    expect(
      screen,
      contains('final habitProvider = context.read<HabitProvider>();'),
    );
    expect(
      screen,
      contains('final noteProvider = context.read<NoteProvider>();'),
    );
    expect(
      screen,
      contains('final calendarProvider = context.read<CalendarProvider>();'),
    );
    expect(
      screen,
      contains(
        'final anniversaryProvider = context.read<AnniversaryProvider>();',
      ),
    );
    expect(
      screen,
      contains('final timeAuditProvider = context.read<TimeAuditProvider>();'),
    );
    expect(screen, contains('todoProvider.importTodos(parsed.todos)'));
    expect(screen, contains('habitProvider.importHabits(parsed.habits)'));
    expect(screen, contains('noteProvider.importNotes(parsed.notes)'));
    expect(
      screen,
      contains('calendarProvider.importLocalEvents(parsed.calendarEvents)'),
    );
    expect(
      screen,
      contains('anniversaryProvider.importAnniversaries(parsed.anniversaries)'),
    );
    expect(
      screen,
      contains('final countdownProvider = context.read<CountdownProvider>();'),
    );
    expect(screen, contains('importCountdowns(parsed.countdowns)'));
    expect(screen, contains('DataSettingsUiCopy.moduleCountdown'));
    expect(
      screen,
      contains('timeAuditProvider.importTimeEntries(parsed.timeEntries)'),
    );
    expect(
      screen,
      contains('? const HabitImportSummary(inserted: 0, skippedDuplicates: 0)'),
    );
    expect(
      screen,
      contains(
        '? const CalendarEventImportSummary(inserted: 0, skippedDuplicates: 0)',
      ),
    );
    expect(
      screen,
      contains('DataSettingsUiCopy.importTasksFromOtherAppsButton'),
    );
    expect(screen, contains('importProductivityFromOtherAppsButton'));
    expect(screen, contains('DataSettingsUiCopy.importProductivityFileButton'));
    expect(screen, contains('DataSettingsUiCopy.competitorImportPasteHint'));
    final copy = File('lib/core/data_settings_ui_copy.dart').readAsStringSync();
    expect(
      copy,
      contains(
        'type=task/habit/note/event/birthday/anniversary/countdown/time_entry',
      ),
    );
    expect(screen, contains('DataSettingsUiCopy.moduleTimeEntry'));
    expect(screen, contains('DataSettingsUiCopy.restoreSectionSubtitle'));
  });

  test('TodoProvider exposes duplicate-safe bulk todo import', () {
    final provider = File(
      'lib/providers/todo_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('class TodoImportSummary'));
    expect(provider, contains('final String? reminderSyncIssue'));
    expect(provider, contains('Future<TodoImportSummary> importTodos('));
    expect(
      provider,
      contains('final seen = _todos.map(_importDuplicateKey).toSet();'),
    );
    expect(provider, contains('skippedDuplicates++'));
    expect(provider, contains('todo.copyWith(sortOrder: nextSortOrder++)'));
    expect(provider, contains('DomainEventType.todoCreated'));
    expect(provider, contains('reminderSyncIssue: reminderSyncResult.issue'));
    expect(provider, contains('String _importDuplicateKey(TodoItem todo)'));
  });

  test('HabitProvider and NoteProvider expose duplicate-safe bulk imports', () {
    final habitProvider = File(
      'lib/providers/habit_provider.dart',
    ).readAsStringSync();
    final noteProvider = File(
      'lib/providers/note_provider.dart',
    ).readAsStringSync();

    expect(habitProvider, contains('class HabitImportSummary'));
    expect(habitProvider, contains('final String? reminderSyncIssue'));
    expect(habitProvider, contains('Future<HabitImportSummary> importHabits('));
    expect(habitProvider, contains('habit.name.trim().toLowerCase()'));
    expect(habitProvider, contains('DomainEventType.habitCreated'));

    expect(noteProvider, contains('class NoteImportSummary'));
    expect(noteProvider, contains('Future<NoteImportSummary> importNotes('));
    expect(noteProvider, contains('note.content.trim().toLowerCase()'));
    expect(noteProvider, contains('skippedDuplicates++'));
  });

  test('CalendarProvider exposes duplicate-safe local event import', () {
    final provider = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('class CalendarEventImportSummary'));
    expect(
      provider,
      contains('Future<CalendarEventImportSummary> importLocalEvents('),
    );
    expect(
      provider,
      contains('final seen = _localEvents.map(_importDuplicateKey).toSet();'),
    );
    expect(provider, contains('skippedDuplicates++'));
    expect(provider, contains('_localEvents.add(_asLocalEvent(event));'));
    expect(
      provider,
      contains('String _importDuplicateKey(CalendarEvent event)'),
    );
  });

  test('AnniversaryProvider exposes duplicate-safe imports', () {
    final anniversaryProvider = File(
      'lib/providers/anniversary_provider.dart',
    ).readAsStringSync();

    expect(anniversaryProvider, contains('class AnniversaryImportSummary'));
    expect(anniversaryProvider, contains('final String? reminderSyncIssue'));
    expect(
      anniversaryProvider,
      contains('Future<AnniversaryImportSummary> importAnniversaries('),
    );
    expect(anniversaryProvider, contains('item.originDate.toIso8601String()'));
    expect(anniversaryProvider, contains('skippedDuplicates++'));
    expect(
      anniversaryProvider,
      contains('reminderSyncIssue: reminderSyncIssue'),
    );
  });

  test('competitor import supports countdown creation paths', () {
    final importer = File(
      'lib/services/competitor_task_importer.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/backup_screen.dart').readAsStringSync();
    final countdownProvider = File(
      'lib/providers/countdown_provider.dart',
    ).readAsStringSync();

    expect(importer, contains("import '../models/countdown.dart';"));
    expect(importer, contains('List<CountdownItem>'));
    expect(importer, contains('CountdownItem? _countdownFromMap'));
    expect(importer, isNot(contains('当前版本不支持新增倒数日，已跳过')));
    expect(screen, contains("import '../providers/countdown_provider.dart';"));
    expect(screen, contains('parsed.countdowns'));
    expect(screen, contains('countdownInserted'));
    expect(countdownProvider, contains('class CountdownImportSummary'));
    expect(countdownProvider, contains('final String? reminderSyncIssue'));
    expect(countdownProvider, contains('reminderSyncIssue: reminderSyncIssue'));
  });

  test('TimeAuditProvider exposes duplicate-safe bulk time entry import', () {
    final provider = File(
      'lib/providers/time_audit_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('class TimeEntryImportSummary'));
    expect(
      provider,
      contains('Future<TimeEntryImportSummary> importTimeEntries('),
    );
    expect(
      provider,
      contains('final seen = _entries.map(_importDuplicateKey).toSet();'),
    );
    expect(provider, contains('skippedDuplicates++'));
    expect(provider, contains('String _importDuplicateKey(TimeEntry entry)'));
    expect(provider, contains('entry.startAt.toIso8601String()'));
    expect(provider, contains('entry.endAt.toIso8601String()'));
  });
}
