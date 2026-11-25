import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/todo_ui_copy.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/app_lock_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_update_service.dart';
import 'surface_components.dart';

final Set<(int, String)> _completionFlowInFlightTodoKeys = <(int, String)>{};

Future<void> completeTodoWithOptionalTimeRecord(
  BuildContext context,
  TodoItem todo, {
  bool Function()? isAccessAvailable,
  bool Function()? isFeedbackAvailable,
  VoidCallback? onActionStarted,
}) async {
  if (!context.mounted) return;
  final lock = context.read<AppLockProvider?>();
  final updater = context.read<AppUpdateService?>();
  bool accessAllowed() =>
      (isAccessAvailable?.call() ?? true) &&
      lock?.isLocked != true &&
      updater?.mustUpdate != true;
  final originGeneration = AccountLocalDataCleaner.accountDataGeneration;
  final key = (originGeneration, todo.id);
  if (!_completionFlowInFlightTodoKeys.add(key)) return;
  try {
    await _completeTodoWithOptionalTimeRecord(
      context,
      todo,
      originGeneration,
      isAccessAvailable: accessAllowed,
      isFeedbackAvailable: isFeedbackAvailable ?? accessAllowed,
      onActionStarted: onActionStarted,
    );
  } catch (error, stack) {
    debugPrint('[TodoCompletionFlow] save failed: $error\n$stack');
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          originGeneration,
        ) ||
        !(isFeedbackAvailable ?? accessAllowed)()) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (_, _, _) => Text(TodoUiCopy.completionFailedFeedback),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } finally {
    _completionFlowInFlightTodoKeys.remove(key);
  }
}

Future<void> _completeTodoWithOptionalTimeRecord(
  BuildContext context,
  TodoItem todo,
  int originGeneration, {
  required bool Function() isAccessAvailable,
  required bool Function() isFeedbackAvailable,
  VoidCallback? onActionStarted,
}) async {
  bool isOriginValid() {
    return context.mounted &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          originGeneration,
        );
  }

  bool canInteract() => isOriginValid() && isAccessAvailable();
  if (!canInteract()) return;

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
            style: TextButton.styleFrom(
              foregroundColor: _dialogActionColor(context),
            ),
            onPressed: () {
              if (dialogCtx.mounted &&
                  ModalRoute.of(dialogCtx)?.isCurrent == true) {
                Navigator.of(dialogCtx).pop(false);
              }
            },
            child: Text(TodoUiCopy.actionCancel),
          ),
          FilledButton(
            onPressed: () {
              if (dialogCtx.mounted &&
                  ModalRoute.of(dialogCtx)?.isCurrent == true &&
                  canInteract()) {
                Navigator.of(dialogCtx).pop(true);
              }
            },
            child: Text(TodoUiCopy.actionContinue),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted || !canInteract()) return;

  final recordMinutes = await _showRecordPrompt(
    context,
    currentTodo.title,
    initialMinutes: _initialMinutes(currentTodo),
    canSubmit: canInteract,
  );
  if (!canInteract()) return;

  onActionStarted?.call();
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

  if (!isOriginValid() || !isFeedbackAvailable() || !messenger.mounted) return;

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
  required bool Function() canSubmit,
}) {
  return showDialog<int?>(
    context: context,
    builder: (dialogCtx) => _RecordDurationDialog(
      todoTitle: todoTitle,
      initialMinutes: initialMinutes,
      canSubmit: canSubmit,
    ),
  );
}

class _RecordDurationDialog extends StatefulWidget {
  final String todoTitle;
  final int initialMinutes;
  final bool Function() canSubmit;

  const _RecordDurationDialog({
    required this.todoTitle,
    required this.initialMinutes,
    required this.canSubmit,
  });

  @override
  State<_RecordDurationDialog> createState() => _RecordDurationDialogState();
}

class _RecordDurationDialogState extends State<_RecordDurationDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  void _finish(int? minutes) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !widget.canSubmit()) {
      return;
    }
    Navigator.of(context).pop(minutes);
  }

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
                hintMaxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _dialogActionColor(context),
            ),
            onPressed: () => _finish(null),
            child: Text(TodoUiCopy.actionSkip),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(_controller.text.trim());
              if (parsed == null || parsed <= 0) {
                _finish(null);
              } else {
                _finish(parsed.clamp(1, 1440));
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

Color _dialogActionColor(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final dialogSurface = theme.dialogTheme.backgroundColor ?? cs.surface;
  final effectiveSurface = dialogSurface.a < 1.0
      ? Color.alphaBlend(dialogSurface, cs.surface)
      : dialogSurface;
  return appReadableForeground(effectiveSurface, cs.primary);
}
