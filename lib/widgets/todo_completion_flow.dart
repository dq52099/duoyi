import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/todo_ui_copy.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../services/account_local_data_cleaner.dart';
import 'surface_components.dart';

final Set<(int, String)> _completionFlowInFlightTodoKeys = <(int, String)>{};

Future<void> completeTodoWithOptionalTimeRecord(
  BuildContext context,
  TodoItem todo,
) async {
  if (!context.mounted) return;
  final originGeneration = AccountLocalDataCleaner.accountDataGeneration;
  final key = (originGeneration, todo.id);
  if (!_completionFlowInFlightTodoKeys.add(key)) return;
  try {
    await _completeTodoWithOptionalTimeRecord(context, todo, originGeneration);
  } finally {
    _completionFlowInFlightTodoKeys.remove(key);
  }
}

Future<void> _completeTodoWithOptionalTimeRecord(
  BuildContext context,
  TodoItem todo,
  int originGeneration,
) async {
  bool isOriginValid() {
    return context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          originGeneration,
        );
  }

  if (!isOriginValid()) return;

  final todoProvider = context.read<TodoProvider>();
  final timeAuditProvider = context.read<TimeAuditProvider?>();
  final messenger = ScaffoldMessenger.of(context);
  TodoItem currentTodo;
  try {
    currentTodo = todoProvider.todos.firstWhere((t) => t.id == todo.id);
  } on StateError {
    currentTodo = todo;
  }

  if (currentTodo.isCompleted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => AppDialog(
        icon: const Icon(Icons.task_alt_outlined),
        title: Text(TodoUiCopy.confirmCompleteTitle),
        content: Text(TodoUiCopy.confirmCompleteContent(currentTodo.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(TodoUiCopy.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(TodoUiCopy.actionContinue),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted || !isOriginValid()) return;

  final recordMinutes = await _showRecordPrompt(
    context,
    currentTodo.title,
    initialMinutes: _initialMinutes(currentTodo),
  );
  if (!isOriginValid()) return;

  final changed = await todoProvider.completeTodos([
    todo.id,
  ], recordCompletionTime: false);
  if (changed == 0 || !isOriginValid()) return;

  if (recordMinutes != null && recordMinutes > 0 && timeAuditProvider != null) {
    final completedTodo = todoProvider.todos.firstWhere(
      (t) => t.id == todo.id,
      orElse: () => currentTodo,
    );
    final completedAt = completedTodo.completedAt ?? DateTime.now();
    await timeAuditProvider.add(
      TimeEntry(
        title: completedTodo.title,
        startAt: completedAt.subtract(Duration(minutes: recordMinutes)),
        endAt: completedAt,
        category: TimeEntryCategory.todo,
        source: TimeEntrySource.todo,
        sourceId: todo.id,
        dedupeKey: TimeAuditProvider.todoCompletionDedupeKey(
          todo.id,
          completedAt,
        ),
        note: TodoUiCopy.manualDurationNote(recordMinutes),
      ),
    );
  } else if (timeAuditProvider != null) {
    final completedTodo = todoProvider.todos.firstWhere(
      (t) => t.id == todo.id,
      orElse: () => currentTodo,
    );
    await timeAuditProvider.recordTodoCompletion(
      completedTodo,
      completedAt: completedTodo.completedAt,
    );
  }

  if (!isOriginValid() || !messenger.mounted) return;

  messenger.showSnackBar(
    SnackBar(
      content: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) =>
            Text(TodoUiCopy.completedFeedback(currentTodo.title)),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<int?> _showRecordPrompt(
  BuildContext context,
  String todoTitle, {
  required int initialMinutes,
}) {
  return showDialog<int?>(
    context: context,
    builder: (dialogCtx) => _RecordDurationDialog(
      todoTitle: todoTitle,
      initialMinutes: initialMinutes,
    ),
  );
}

class _RecordDurationDialog extends StatefulWidget {
  final String todoTitle;
  final int initialMinutes;

  const _RecordDurationDialog({
    required this.todoTitle,
    required this.initialMinutes,
  });

  @override
  State<_RecordDurationDialog> createState() => _RecordDurationDialogState();
}

class _RecordDurationDialogState extends State<_RecordDurationDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialMinutes.clamp(1, 1440).toString(),
    );
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => AppDialog(
        icon: const Icon(Icons.schedule_outlined),
        title: Text(TodoUiCopy.recordDurationTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TodoUiCopy.recordDurationContent(widget.todoTitle)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: TodoUiCopy.durationLabel,
                suffixText: TodoUiCopy.durationMinutesSuffix,
                hintText: TodoUiCopy.durationHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(TodoUiCopy.actionSkip),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(_controller.text.trim());
              if (parsed == null || parsed <= 0) {
                Navigator.of(context).pop(null);
              } else {
                Navigator.of(context).pop(parsed);
              }
            },
            child: Text(TodoUiCopy.actionRecord),
          ),
        ],
      ),
    );
  }
}

int _initialMinutes(TodoItem todo) {
  final sec = todo.timeTargetSeconds;
  if (sec != null && sec > 0) {
    return (sec / 60).round().clamp(1, 1440);
  }
  return 30;
}
