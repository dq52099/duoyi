import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('QuickCaptureFab exposes AI conversational commands', () {
    final fab = File('lib/widgets/quick_capture_fab.dart').readAsStringSync();
    final command = File('lib/core/ai_command.dart').readAsStringSync();

    expect(command, contains('enum AiCommandType'));
    expect(command, contains('AiCommandType.addTodo'));
    expect(command, contains('AiCommandType.addNote'));
    expect(command, contains('AiCommandType.addDiary'));
    expect(command, contains('AiCommandType.startFocus'));
    expect(command, contains('SmartTodoDraftBuilder.fromText'));
    expect(command, contains('class AiCommandBatch'));
    expect(command, contains('parseBatch'));

    expect(fab, contains("import '../core/ai_command.dart';"));
    expect(fab, contains('Future<void> _quickAiCommand()'));
    expect(fab, contains('AiCommandParser.parseBatch(value)'));
    expect(fab, contains('Future<void> _executeAiCommands'));
    expect(fab, contains('QuickCaptureUiCopy.aiCommandsExecuted'));
    expect(fab, contains('QuickCaptureUiCopy.commandExecuted'));
    expect(fab, contains('String _localSaveSyncMessage('));
    expect(fab, contains('localSaveSyncMessage('));
    expect(fab, contains('Future<_AiCommandOutcome> _executeAiCommand('));
    expect(fab, contains('class _AiCommandOutcome'));
    expect(fab, contains('String? reminderSyncIssue'));
    expect(fab, contains('reminderFailures'));
    expect(fab, contains('QuickCaptureUiCopy.aiReminderFailures'));
    expect(fab, contains('const _AiCommandOutcome.skipped()'));
    expect(fab, contains('AiCommand command,'));
    expect(fab, contains('bool showSnackBar = true'));
    expect(fab, contains('addTodoWithResult'));
    expect(fab, contains('await provider.addOrUpdateNotePersisted(note)'));
    expect(fab, contains('await provider.addOrUpdate(diary)'));
    expect(fab, contains('final pomodoro = operation.pomodoro'));
    expect(fab, contains('QuickCaptureUiCopy.aiCommandTitle'));
  });
}
