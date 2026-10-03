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
    expect(fab, contains('已执行 \${commands.length} 条 AI 指令，\$syncMessage'));
    expect(fab, contains('\${command.title}已执行，\${_localSaveSyncMessage()}'));
    expect(fab, contains('String _localSaveSyncMessage('));
    expect(fab, contains('localSaveSyncMessage('));
    expect(fab, contains('Future<_AiCommandOutcome> _executeAiCommand('));
    expect(fab, contains('class _AiCommandOutcome'));
    expect(fab, contains('String? reminderSyncIssue'));
    expect(fab, contains('reminderFailures'));
    expect(fab, contains('其中 \$reminderFailures 条提醒未注册'));
    expect(fab, contains('const _AiCommandOutcome.skipped()'));
    expect(fab, contains('AiCommand command,'));
    expect(fab, contains('bool showSnackBar = true'));
    expect(fab, contains('addTodoWithResult'));
    expect(fab, contains('context.read<NoteProvider>().addOrUpdateNote'));
    expect(fab, contains('context.read<DiaryProvider>().addOrUpdate'));
    expect(fab, contains('context.read<PomodoroProvider>()'));
    expect(fab, contains("label: 'AI 指令'"));
  });
}
