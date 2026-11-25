import 'dart:async';
import 'app_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/account_local_data_cleaner.dart';
import 'package:provider/provider.dart';
import '../core/ai_command.dart';
import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../providers/auth_provider.dart';
import '../providers/app_lock_provider.dart';
import '../services/app_update_service.dart';
import '../services/app_access_route_gate.dart';
import '../services/settings_action_origin.dart';
import '../core/i18n.dart';
import '../core/notification_ui_copy.dart';
import '../core/quick_capture_ui_copy.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/habit.dart';
import '../models/note.dart';
import '../models/quick_capture_template.dart';
import '../models/todo.dart';
import '../providers/habit_provider.dart';
import '../providers/cloud_sync_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/quick_capture_template_provider.dart';
import '../providers/todo_provider.dart';
import '../services/ai_service.dart';
import '../services/local_notifications.dart';
import '../providers/notification_service.dart';
import '../services/reminder_scheduler.dart';
import '../screens/ai_schedule_screen.dart';
import '../screens/diary_screen.dart';
import '../screens/goal_edit_screen.dart';
import 'brand_background.dart' show BrandRouteSurface;
import 'surface_components.dart';

/// 展开式快速捕获 FAB：3 个子按钮 + 一个搜索入口。
class QuickCaptureFab extends StatefulWidget {
  const QuickCaptureFab({super.key});

  @override
  State<QuickCaptureFab> createState() => _QuickCaptureFabState();
}

class _QuickCaptureFabState extends State<QuickCaptureFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _open = false;
  _CaptureOperation? _operation;

  _CaptureOperation? _beginCapture() {
    if (!mounted || _operation != null) return null;
    final operation = _CaptureOperation(context);
    if (!mounted || !operation.isCurrent()) {
      operation.dispose();
      return null;
    }
    _operation = operation;
    _closeIfOpen();
    return operation;
  }

  void _endCapture(_CaptureOperation operation) {
    operation.dispose();
    if (identical(_operation, operation)) _operation = null;
  }

  Future<T?> _showCaptureDialog<T>(
    _CaptureOperation operation, {
    required WidgetBuilder builder,
  }) async {
    if (!mounted || !operation.isCurrent()) return null;
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: false,
      themes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, _, _) => builder(ctx),
      ),
    );
    operation.own(route);
    final pending = Navigator.of(context).push(route);
    operation.listenForCover();
    final result = await pending;
    await route.completed;
    operation.release(route);
    return result;
  }

  void _popCapture<T>(
    _CaptureOperation operation,
    BuildContext dialogContext, [
    T? result,
  ]) {
    if (!mounted || !operation.isCurrent() || !dialogContext.mounted) return;
    final route = ModalRoute.of(dialogContext);
    if (!identical(operation.route, route) || route?.isCurrent != true) {
      return;
    }
    Navigator.of(dialogContext).pop(result);
  }

  void _captureFailure(_CaptureOperation operation, {bool keptDraft = false}) {
    if (!mounted || !operation.isCurrent()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          keptDraft
              ? QuickCaptureUiCopy.draftSaveFailed
              : QuickCaptureUiCopy.saveFailed,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _operation?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = _open ? 1 : 0;
    } else if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _closeIfOpen() {
    if (!_open) return;
    setState(() => _open = false);
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 0;
    } else {
      _ctrl.reverse();
    }
  }

  Future<void> _quickTodo() async {
    final operation = _beginCapture();
    if (operation == null) return;
    final ctrl = TextEditingController();
    SmartDateParseResult parsed = SmartDateParseResult.empty;
    var saving = false;
    try {
      await _showCaptureDialog<bool>(
        operation,
        builder: (ctx) => _CaptureStatefulBuilder(
          operation: operation,
          builder: (ctx, setSt) => AppDialog(
            title: Text(I18n.tr('quick.todo.title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  readOnly: saving,
                  decoration: InputDecoration(
                    hintText: I18n.tr('quick.todo.hint'),
                  ),
                  onChanged: (v) => setSt(() {
                    parsed = SmartDateParser.parse(v);
                  }),
                ),
                if (parsed.isSuccess) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${I18n.tr('quick.todo.parsed_prefix')}${AppDateFormat.smartDate(ctx, parsed.dateTime!, includeTime: parsed.hasTimeOfDay)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => _popCapture(operation, ctx),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!operation.isCurrent() ||
                            saving ||
                            ctrl.text.trim().isEmpty) {
                          return;
                        }
                        setSt(() => saving = true);
                        try {
                          final draft = SmartTodoDraftBuilder.fromText(
                            ctrl.text.trim(),
                          );
                          final outcome = await _createTodoWithReminderFeedback(
                            draft.toTodo(),
                            operation: operation,
                            issueTitle:
                                QuickCaptureUiCopy.reminderRegistrationFailed,
                          );
                          if (ctx.mounted &&
                              outcome.created &&
                              operation.isCurrent()) {
                            _popCapture(operation, ctx, true);
                          }
                        } on AccountPreferenceWriteCanceled {
                          // Expired source cannot retry this draft.
                        } catch (_) {
                          _captureFailure(operation, keptDraft: true);
                        } finally {
                          setSt(() => saving = false);
                        }
                      },
                child: Text(I18n.tr('action.add')),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
      _endCapture(operation);
    }
  }

  Future<void> _quickAiTodo() async {
    final operation = _beginCapture();
    if (operation == null) return;
    try {
      final route = MaterialPageRoute(builder: (_) => const AiScheduleScreen());
      operation.own(route);
      await Navigator.of(context).push(route);
      await route.completed;
      operation.release(route);
    } finally {
      _endCapture(operation);
    }
  }

  Future<void> _quickAiCommand() async {
    final operation = _beginCapture();
    if (operation == null) return;
    final ctrl = TextEditingController();
    var batch = const AiCommandBatch(rawText: '', commands: []);
    try {
      final ok = await _showCaptureDialog<bool>(
        operation,
        builder: (ctx) => _CaptureStatefulBuilder(
          operation: operation,
          builder: (ctx, setSt) => AppDialog(
            title: Text(QuickCaptureUiCopy.aiCommandTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: QuickCaptureUiCopy.aiCommandHint,
                    ),
                    onChanged: (value) {
                      setSt(() => batch = AiCommandParser.parseBatch(value));
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      batch.preview,
                      style: TextStyle(
                        fontSize: 12,
                        color: batch.executable
                            ? Theme.of(ctx).colorScheme.onSurface
                            : Theme.of(ctx).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _popCapture(operation, ctx, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton.icon(
                onPressed: batch.executable
                    ? () => _popCapture(operation, ctx, true)
                    : null,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text(QuickCaptureUiCopy.executeAction),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !operation.isCurrent()) return;
      batch = AiCommandParser.parseBatch(ctrl.text);
      await _executeAiCommands(batch.commands, operation);
    } finally {
      ctrl.dispose();
      _endCapture(operation);
    }
  }

  Future<void> _executeAiCommands(
    List<AiCommand> commands,
    _CaptureOperation operation,
  ) async {
    var executed = 0;
    var reminderTodos = 0;
    var reminderFailures = 0;
    for (final command in commands) {
      if (!mounted || !operation.isCurrent()) return;
      final outcome = await _executeAiCommand(
        command,
        operation: operation,
        showSnackBar: false,
      );
      if (!mounted || !operation.isCurrent()) return;
      if (!outcome.executed) continue;
      executed++;
      if (outcome.createdReminderTodo) reminderTodos++;
      if (outcome.reminderSyncIssue != null) reminderFailures++;
    }
    if (!mounted || !operation.isCurrent() || executed == 0) return;
    final syncMessage = _localSaveSyncMessage();
    final baseMessage = executed == 1 && commands.length == 1
        ? QuickCaptureUiCopy.commandExecuted(commands.single.title, syncMessage)
        : QuickCaptureUiCopy.aiCommandsExecuted(
            executed: executed,
            total: commands.length,
            syncMessage: syncMessage,
          );
    final message = reminderFailures > 0
        ? QuickCaptureUiCopy.aiReminderFailures(baseMessage, reminderFailures)
        : reminderTodos == 0
        ? baseMessage
        : QuickCaptureUiCopy.aiReminderStatus(baseMessage, reminderTodos);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: reminderFailures > 0
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
  }

  Future<_AiCommandOutcome> _executeAiCommand(
    AiCommand command, {
    bool showSnackBar = true,
    required _CaptureOperation operation,
  }) async {
    if (!mounted || !operation.isCurrent()) {
      return const _AiCommandOutcome.skipped();
    }
    try {
      switch (command.type) {
        case AiCommandType.addTodo:
          final draft = command.todoDraft;
          if (draft == null) return const _AiCommandOutcome.skipped();
          final outcome = await _createTodoWithReminderFeedback(
            draft.toTodo(),
            operation: operation,
            showSnackBar: showSnackBar,
            issueTitle: QuickCaptureUiCopy.reminderRegistrationFailed,
          );
          return _AiCommandOutcome(
            executed: outcome.created,
            createdReminderTodo: outcome.created && outcome.hasReminder,
            reminderSyncIssue: outcome.reminderSyncIssue,
          );
        case AiCommandType.addNote:
          final note = command.note;
          if (note == null) return const _AiCommandOutcome.skipped();
          final provider = operation.notes;
          if (provider == null) return const _AiCommandOutcome.skipped();
          await provider.addOrUpdateNotePersisted(note);
        case AiCommandType.addDiary:
          final diary = command.diary;
          if (diary == null) return const _AiCommandOutcome.skipped();
          final provider = operation.diary;
          if (provider == null) return const _AiCommandOutcome.skipped();
          await provider.addOrUpdate(diary);
        case AiCommandType.startFocus:
          final pomodoro = operation.pomodoro;
          if (pomodoro == null) return const _AiCommandOutcome.skipped();
          if (!pomodoro.state.isRunning) pomodoro.toggleTimer();
        case AiCommandType.unknown:
          return const _AiCommandOutcome.skipped();
      }
    } on AccountPreferenceWriteCanceled {
      return const _AiCommandOutcome.skipped();
    } catch (_) {
      _captureFailure(operation);
      return const _AiCommandOutcome.skipped();
    }
    if (!mounted || !operation.isCurrent() || !showSnackBar) {
      return const _AiCommandOutcome(executed: true);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          QuickCaptureUiCopy.commandExecuted(
            command.title,
            _localSaveSyncMessage(),
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return const _AiCommandOutcome(executed: true);
  }

  Future<_TodoCreateOutcome> _createTodoWithReminderFeedback(
    TodoItem todo, {
    required _CaptureOperation operation,
    bool showSnackBar = true,
    String? issueTitle,
  }) async {
    final effectiveIssueTitle =
        issueTitle ?? QuickCaptureUiCopy.reminderRegistrationFailed;
    final preflight = preflightTodoReminderPlan(todo);
    final hasReminder = preflight.hasEnabledPlan;
    if (hasReminder &&
        !await _preflightTodoReminder(
          todo,
          preflight,
          effectiveIssueTitle,
          operation,
        )) {
      return _TodoCreateOutcome(created: false, hasReminder: hasReminder);
    }
    if (!mounted || !operation.isCurrent()) {
      return _TodoCreateOutcome(created: false, hasReminder: hasReminder);
    }
    final todoProvider = operation.todos;
    if (todoProvider == null) {
      return _TodoCreateOutcome(created: false, hasReminder: hasReminder);
    }
    late final TodoReminderSyncResult? reminderSyncResult;
    try {
      reminderSyncResult = await todoProvider.addTodoWithResult(
        todo,
        waitForReminderSync: hasReminder,
        canWrite: operation.isCurrent,
      );
    } catch (_) {
      if (mounted && operation.isCurrent()) {
        final message = QuickCaptureUiCopy.saveFailed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return _TodoCreateOutcome(created: false, hasReminder: hasReminder);
    }
    if (!mounted || !operation.isCurrent()) {
      return _TodoCreateOutcome(created: true, hasReminder: hasReminder);
    }
    final reminderSyncIssue = hasReminder ? reminderSyncResult?.issue : null;
    if (reminderSyncIssue != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            QuickCaptureUiCopy.reminderSavedButNotRegistered(
              effectiveIssueTitle,
              reminderSyncIssue,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return _TodoCreateOutcome(
        created: true,
        hasReminder: hasReminder,
        reminderSyncIssue: reminderSyncIssue,
      );
    }
    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_todoCreatedMessage(hasReminder)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return _TodoCreateOutcome(created: true, hasReminder: hasReminder);
  }

  Future<bool> _preflightTodoReminder(
    TodoItem todo,
    TodoReminderPreflightResult preflight,
    String issueTitle,
    _CaptureOperation operation,
  ) async {
    if (!mounted || !operation.isCurrent()) return false;
    final blocking = preflight.blockingIssue;
    if (blocking != null) {
      final title =
          blocking.copy?.title(locale: I18n.current) ?? blocking.title;
      final message =
          blocking.copy?.message(locale: I18n.current) ?? blocking.message;
      _showReminderFailure(QuickCaptureUiCopy.issue(title, message));
      return false;
    }

    final usesPush = preflight.kinds.contains(ReminderKind.push);
    final usesPopup = preflight.kinds.contains(ReminderKind.popup);
    final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);
    if (!usesPush && !usesPopup && !usesAlarm) return true;
    final notification = operation.notifications;
    if (notification != null && (usesPush || usesPopup)) {
      final ready = await notification.ensureReadyForReminder(
        scheduledTime: preflight.firstScheduledTime,
        issueTitle: issueTitle,
        relatedId: todo.id,
        canContinue: operation.isCurrent,
      );
      if (!mounted || !operation.isCurrent()) return false;
      if (ready) return true;
      final issue = notification.lastScheduleIssue;
      _showReminderFailure(
        issue == null
            ? QuickCaptureUiCopy.issue(
                issueTitle,
                QuickCaptureUiCopy.reminderRegistrationHint,
              )
            : NotificationUiCopy.formatScheduleIssue(
                issue,
                fallback: QuickCaptureUiCopy.issue(issue.title, issue.message),
              ),
      );
      return false;
    }
    if (usesAlarm) {
      final granted = await LocalNotifications.instance.ensurePermission();
      if (!mounted || !operation.isCurrent()) return false;
      if (granted) return true;
      _showReminderFailure(
        QuickCaptureUiCopy.issue(
          issueTitle,
          QuickCaptureUiCopy.alarmPermissionHint,
        ),
      );
      return false;
    }
    return true;
  }

  void _showReminderFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _todoCreatedMessage(bool hasReminder) {
    final syncMessage = _localSaveSyncMessage(
      localSavedText: QuickCaptureUiCopy.localSaved,
    );
    return QuickCaptureUiCopy.todoCreatedMessage(
      hasReminder: hasReminder,
      syncMessage: syncMessage,
    );
  }

  String _localSaveSyncMessage({String? localSavedText}) {
    final savedText = localSavedText ?? QuickCaptureUiCopy.localSavedFallback;
    try {
      return context.read<CloudSyncProvider?>()?.localSaveSyncMessage(
            localSavedText: savedText,
          ) ??
          QuickCaptureUiCopy.savedSyncPending(savedText);
    } catch (e, st) {
      debugPrint('[QuickCaptureFab] local sync message unavailable: $e\n$st');
      return QuickCaptureUiCopy.savedSyncPending(savedText);
    }
  }

  Future<void> _quickNote() async {
    final operation = _beginCapture();
    if (operation == null) return;
    final ctrl = TextEditingController();
    var saving = false;
    try {
      await _showCaptureDialog<bool>(
        operation,
        builder: (ctx) => _CaptureStatefulBuilder(
          operation: operation,
          builder: (ctx, setDialogState) => PopScope(
            canPop: !saving,
            child: AppDialog(
              title: Text(I18n.tr('quick.note.title')),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                readOnly: saving,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: I18n.tr('quick.note.hint'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => _popCapture(operation, ctx),
                  child: Text(I18n.tr('action.cancel')),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!operation.isCurrent() ||
                              saving ||
                              ctrl.text.trim().isEmpty) {
                            return;
                          }
                          final notes = operation.notes;
                          if (notes == null) return;
                          setDialogState(() => saving = true);
                          final now = DateTime.now();
                          try {
                            await notes.addOrUpdateNotePersisted(
                              NoteItem(
                                id: now.microsecondsSinceEpoch.toString(),
                                content: ctrl.text.trim(),
                                createdAt: now,
                                updatedAt: now,
                              ),
                            );
                            if (!ctx.mounted || !operation.isCurrent()) return;
                            _popCapture(operation, ctx, true);
                          } on AccountPreferenceWriteCanceled {
                            // Expired account work never reports success or retries.
                          } catch (_) {
                            _captureFailure(operation, keptDraft: true);
                          } finally {
                            if (ctx.mounted && operation.isCurrent()) {
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  child: Text(I18n.tr('action.save')),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      ctrl.dispose();
      _endCapture(operation);
    }
  }

  Future<void> _openNewGoal() async {
    final operation = _beginCapture();
    if (operation == null) return;
    try {
      if (!mounted || !operation.isCurrent()) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const BrandRouteSurface(child: GoalEditScreen()),
        ),
      );
    } finally {
      _endCapture(operation);
    }
  }

  Future<void> _quickDiary() async {
    final operation = _beginCapture();
    if (operation == null) return;
    try {
      final route = MaterialPageRoute(builder: (_) => const DiaryEditScreen());
      operation.own(route);
      await Navigator.of(context).push(route);
      await route.completed;
      operation.release(route);
    } finally {
      _endCapture(operation);
    }
  }

  Future<void> _showTemplateSheet() async {
    final operation = _beginCapture();
    if (operation == null) return;
    final provider = operation.templates;
    var deleting = false;
    try {
      final route = ModalBottomSheetRoute<Object>(
        isScrollControlled: true,
        showDragHandle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Navigator.of(context).context,
        ),
        builder: (ctx) => ListenableBuilder(
          listenable: Listenable.merge([I18n.localeListenable, ?provider]),
          builder: (ctx, _) => _CaptureStatefulBuilder(
            operation: operation,
            builder: (ctx, setSheetState) {
              final templates =
                  provider?.templates ?? QuickCaptureTemplate.builtIns();
              return AppModalSheet(
                title: I18n.tr('quick.template.title'),
                subtitle: I18n.tr('quick.template.subtitle'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: deleting
                              ? null
                              : () => _popCapture(operation, ctx, true),
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(I18n.tr('quick.template.save')),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    ...templates.map(
                      (template) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TemplateTile(
                          template: template,
                          onTap: () {
                            if (!deleting) {
                              _popCapture(operation, ctx, template);
                            }
                          },
                          onDelete:
                              template.builtIn || provider == null || deleting
                              ? null
                              : () async {
                                  if (!operation.isCurrent() || deleting) {
                                    return;
                                  }
                                  setSheetState(() => deleting = true);
                                  try {
                                    await provider.deleteTemplate(template.id);
                                  } on AccountPreferenceWriteCanceled {
                                    // The outgoing account no longer owns this sheet.
                                  } catch (_) {
                                    _captureFailure(operation);
                                  } finally {
                                    if (ctx.mounted && operation.isCurrent()) {
                                      setSheetState(() => deleting = false);
                                    }
                                  }
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      operation.own(route);
      final pending = Navigator.of(context).push(route);
      operation.listenForCover();
      final selected = await pending;
      await route.completed;
      operation.release(route);
      if (!mounted || !operation.isCurrent()) return;
      if (selected == true) {
        await _showSaveTemplateDialog(operation);
      } else if (selected is QuickCaptureTemplate) {
        await _applyTemplate(selected, operation);
      }
    } finally {
      _endCapture(operation);
    }
  }

  Future<void> _showSaveTemplateDialog(_CaptureOperation operation) async {
    final provider = operation.templates;
    if (provider == null || !operation.isCurrent()) return;
    final nameCtrl = TextEditingController();
    final prefixCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    final listCtrl = TextEditingController();
    final habitCategoryCtrl = TextEditingController();
    final habitTargetCtrl = TextEditingController(text: '1');
    final habitUnitCtrl = TextEditingController();
    var kind = QuickCaptureTemplateKind.todo;
    var priority = TodoPriority.none;
    var todoReminder = false;
    var habitReminder = false;

    var saving = false;
    Future<void> save(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (!operation.isCurrent() || saving || nameCtrl.text.trim().isEmpty) {
        return;
      }
      setDialogState(() => saving = true);
      try {
        final reminderPlan = todoReminder
            ? ReminderPlan(
                enabled: true,
                rules: [
                  ReminderRule(
                    type: ReminderRuleType.relativeToDue,
                    kind: ReminderKind.push,
                    offsetMinutes: -15,
                  ),
                ],
              )
            : const ReminderPlan.disabled();
        await provider.saveTemplate(
          QuickCaptureTemplate(
            name: nameCtrl.text.trim(),
            kind: kind,
            titlePrefix: prefixCtrl.text.trim(),
            tags: tagsCtrl.text.split(RegExp(r'[,，\s]+')),
            priority: priority,
            listGroupName: listCtrl.text.trim().isEmpty ? null : listCtrl.text,
            reminderPlan: reminderPlan,
            habitCategory: habitCategoryCtrl.text.trim().isEmpty
                ? null
                : habitCategoryCtrl.text,
            habitTargetCount: int.tryParse(habitTargetCtrl.text) ?? 1,
            habitUnit: habitUnitCtrl.text.trim().isEmpty
                ? null
                : habitUnitCtrl.text,
            habitRemind: habitReminder,
            habitRemindHour: habitReminder ? 21 : null,
            habitRemindMinute: habitReminder ? 0 : null,
          ),
        );
        if (!mounted || !dialogContext.mounted || !operation.isCurrent()) {
          return;
        }
        _popCapture(operation, dialogContext, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${I18n.tr('quick.template.saved')} · ${_localSaveSyncMessage()}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } on AccountPreferenceWriteCanceled {
        // Expired account work cannot be retried by the retained form.
      } catch (_) {
        _captureFailure(operation, keptDraft: true);
      } finally {
        if (dialogContext.mounted && operation.isCurrent()) {
          setDialogState(() => saving = false);
        }
      }
    }

    try {
      await _showCaptureDialog<bool>(
        operation,
        builder: (dialogContext) => _CaptureStatefulBuilder(
          operation: operation,
          builder: (dialogContext, setDialogState) => AppDialog(
            title: Text(I18n.tr('quick.template.save')),
            content: AbsorbPointer(
              absorbing: saving,
              child: SingleChildScrollView(
                child: AppSecondaryControlTheme(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: Text(I18n.tr('quick.template.kind.todo')),
                              selected: kind == QuickCaptureTemplateKind.todo,
                              onSelected: (_) => setDialogState(
                                () => kind = QuickCaptureTemplateKind.todo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: Text(I18n.tr('quick.template.kind.habit')),
                              selected: kind == QuickCaptureTemplateKind.habit,
                              onSelected: (_) => setDialogState(
                                () => kind = QuickCaptureTemplateKind.habit,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: I18n.tr('quick.template.name'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: prefixCtrl,
                        decoration: InputDecoration(
                          labelText: I18n.tr('quick.template.prefix'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tagsCtrl,
                        decoration: InputDecoration(
                          labelText: QuickCaptureUiCopy.templateTagsLabel,
                          hintText: QuickCaptureUiCopy.templateTagsHint,
                        ),
                      ),
                      if (kind == QuickCaptureTemplateKind.todo) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: listCtrl,
                          decoration: InputDecoration(
                            labelText: I18n.tr('quick.template.list'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(I18n.tr('quick.template.priority')),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final item in TodoPriority.values)
                              ChoiceChip(
                                label: Text(item.label),
                                selected: priority == item,
                                onSelected: saving
                                    ? null
                                    : (_) =>
                                          setDialogState(() => priority = item),
                              ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: todoReminder,
                          onChanged: (value) {
                            setDialogState(() => todoReminder = value);
                          },
                          title: Text(I18n.tr('quick.template.reminder15')),
                        ),
                      ] else ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: habitCategoryCtrl,
                          decoration: InputDecoration(
                            labelText: I18n.tr('quick.template.habit_category'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: habitTargetCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  labelText: I18n.tr(
                                    'quick.template.habit_target',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              child: TextField(
                                controller: habitUnitCtrl,
                                decoration: InputDecoration(
                                  labelText: I18n.tr(
                                    'quick.template.habit_unit',
                                  ),
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText: QuickCaptureUiCopy.defaultHabitUnit(
                                    int.tryParse(habitTargetCtrl.text) ?? 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: habitReminder,
                          onChanged: (value) {
                            setDialogState(() => habitReminder = value);
                          },
                          title: Text(I18n.tr('quick.template.habit_reminder')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => _popCapture(operation, dialogContext, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () => save(dialogContext, setDialogState),
                child: Text(I18n.tr('action.save')),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controller in [
        nameCtrl,
        prefixCtrl,
        tagsCtrl,
        listCtrl,
        habitCategoryCtrl,
        habitTargetCtrl,
        habitUnitCtrl,
      ]) {
        controller.dispose();
      }
    }
  }

  Future<void> _applyTemplate(
    QuickCaptureTemplate template,
    _CaptureOperation operation,
  ) async {
    if (!mounted || !operation.isCurrent()) return;
    final ctrl = TextEditingController();
    var saving = false;
    Future<bool> create() async {
      final input = ctrl.text.trim();
      if (input.isEmpty && template.displayTitlePrefix.isEmpty) return false;
      if (template.kind == QuickCaptureTemplateKind.todo) {
        final outcome = await _createTodoWithReminderFeedback(
          template.toTodo(input),
          operation: operation,
          showSnackBar: false,
          issueTitle: QuickCaptureUiCopy.reminderRegistrationFailed,
        );
        if (!outcome.created) return false;
        if (!mounted || !operation.isCurrent()) return false;
        if (outcome.reminderSyncIssue != null) return true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome.hasReminder
                  ? _todoCreatedMessage(true)
                  : _todoCreatedMessage(false),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final habitProvider = operation.habits;
        if (habitProvider == null) return false;
        final habit = template.toHabit(input);
        final hasReminder = _habitHasReminder(habit);
        await habitProvider.addHabit(habit);
        if (!mounted || !operation.isCurrent()) return false;
        final reminderSyncIssue = hasReminder
            ? habitProvider.lastReminderSyncIssue
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reminderSyncIssue == null
                  ? QuickCaptureUiCopy.habitCreatedMessage
                  : QuickCaptureUiCopy.habitReminderFailed(reminderSyncIssue),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: reminderSyncIssue == null
                ? null
                : Theme.of(context).colorScheme.error,
          ),
        );
      }
      return true;
    }

    try {
      await _showCaptureDialog<bool>(
        operation,
        builder: (dialogContext) => _CaptureStatefulBuilder(
          operation: operation,
          builder: (dialogContext, setDialogState) => AppDialog(
            title: Text(QuickCaptureUiCopy.templateName(template)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              readOnly: saving,
              maxLines: template.kind == QuickCaptureTemplateKind.todo ? 2 : 1,
              decoration: InputDecoration(
                hintText: I18n.tr('quick.template.apply_hint'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => _popCapture(operation, dialogContext, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!operation.isCurrent() || saving) return;
                        setDialogState(() => saving = true);
                        try {
                          if (await create() &&
                              dialogContext.mounted &&
                              operation.isCurrent()) {
                            _popCapture(operation, dialogContext, true);
                          }
                        } on AccountPreferenceWriteCanceled {
                          // Expired source cannot retry this draft.
                        } catch (_) {
                          _captureFailure(operation, keptDraft: true);
                        } finally {
                          setDialogState(() => saving = false);
                        }
                      },
                child: Text(I18n.tr('action.create')),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  bool _habitHasReminder(Habit habit) {
    return habit.remind ||
        (habit.remindHour != null && habit.remindMinute != null) ||
        (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty);
  }

  Widget _mini({
    required IconData icon,
    required String label,
    String? heroTag,
    required Color color,
    required VoidCallback onTap,
    required bool compact,
  }) {
    return ScaleTransition(
      scale: _ctrl,
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          button: true,
          label: label,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 180 : 240),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: 8,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                heroTag: heroTag ?? label,
                mini: true,
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 2,
                focusElevation: 3,
                hoverElevation: 3,
                onPressed: onTap,
                tooltip: label,
                child: Icon(icon, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiEnabled = context.watch<AiService>().enabled;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.96),
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                10,
                compact ? 10 : 12,
                2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 2, bottom: 6),
                    child: Text(
                      QuickCaptureUiCopy.quickCreateHeading,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  _mini(
                    icon: Icons.bookmark_add_outlined,
                    label: I18n.tr('quick.menu.template'),
                    color: cs.tertiary,
                    onTap: _showTemplateSheet,
                    compact: compact,
                  ),
                  if (aiEnabled)
                    _mini(
                      icon: Icons.assistant_outlined,
                      label: QuickCaptureUiCopy.aiCommandTitle,
                      color: cs.secondary,
                      onTap: _quickAiCommand,
                      compact: compact,
                    ),
                  if (aiEnabled)
                    _mini(
                      icon: Icons.auto_awesome,
                      label: I18n.tr('quick.menu.ai_schedule'),
                      color: cs.secondary,
                      onTap: _quickAiTodo,
                      compact: compact,
                    ),
                  _mini(
                    icon: Icons.flag_circle_outlined,
                    label: QuickCaptureUiCopy.isEn ? 'New goal' : '新建目标',
                    heroTag: 'quick_capture_goal',
                    color: cs.primary,
                    onTap: _openNewGoal,
                    compact: compact,
                  ),
                  _mini(
                    icon: Icons.book_outlined,
                    label: I18n.tr('quick.menu.diary'),
                    color: cs.primary,
                    onTap: _quickDiary,
                    compact: compact,
                  ),
                  _mini(
                    icon: Icons.edit_note,
                    label: I18n.tr('quick.menu.note'),
                    color: cs.primary,
                    onTap: _quickNote,
                    compact: compact,
                  ),
                  _mini(
                    icon: Icons.check_circle_outline,
                    label: I18n.tr('quick.menu.todo'),
                    color: cs.primary,
                    onTap: _quickTodo,
                    compact: compact,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
        ],
        Semantics(
          button: true,
          label: _open
              ? QuickCaptureUiCopy.fabCloseLabel
              : QuickCaptureUiCopy.fabOpenLabel,
          hint: QuickCaptureUiCopy.fabLongPressHint,
          child: GestureDetector(
            onLongPress: _showTemplateSheet,
            child: Tooltip(
              triggerMode: TooltipTriggerMode.manual,
              message: _open
                  ? QuickCaptureUiCopy.fabCloseLabel
                  : QuickCaptureUiCopy.fabOpenLabel,
              child: FloatingActionButton(
                heroTag: 'quick_capture',
                onPressed: _toggle,
                elevation: _open ? 2 : 3,
                focusElevation: 4,
                hoverElevation: 4,
                child: AnimatedRotation(
                  turns: _open ? 0.125 : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TodoCreateOutcome {
  final bool created;
  final bool hasReminder;
  final String? reminderSyncIssue;

  const _TodoCreateOutcome({
    required this.created,
    required this.hasReminder,
    this.reminderSyncIssue,
  });
}

class _AiCommandOutcome {
  final bool executed;
  final bool createdReminderTodo;
  final String? reminderSyncIssue;

  const _AiCommandOutcome({
    required this.executed,
    this.createdReminderTodo = false,
    this.reminderSyncIssue,
  });

  const _AiCommandOutcome.skipped()
    : executed = false,
      createdReminderTodo = false,
      reminderSyncIssue = null;
}

class _TemplateTile extends StatelessWidget {
  final QuickCaptureTemplate template;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TemplateTile({
    required this.template,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final isHabit = template.kind == QuickCaptureTemplateKind.habit;
    final icon = isHabit ? Icons.repeat_rounded : Icons.checklist_rounded;
    final color = isHabit
        ? (isDark ? const Color(0xFF4DB6AC) : DesignTokens.defaultAccent)
        : cs.primary;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(icon, size: 18),
        ),
        title: Text(
          QuickCaptureUiCopy.templateName(template),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          QuickCaptureUiCopy.templateSummary(template),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onDelete == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: I18n.tr('action.delete'),
                onPressed: onDelete,
              ),
        onTap: onTap,
      ),
    );
  }
}

/// One entry owns its providers and routes until its last awaited action ends.
/// Revoked access stays revoked even when a lock or covered route is restored.
class _CaptureOperation {
  _CaptureOperation(this.context)
    : authority = SettingsActionOrigin(context),
      notes = context.read<NoteProvider?>(),
      todos = context.read<TodoProvider?>(),
      habits = context.read<HabitProvider?>(),
      diary = context.read<DiaryProvider?>(),
      pomodoro = context.read<PomodoroProvider?>(),
      templates = context.read<QuickCaptureTemplateProvider?>(),
      notifications = context.read<NotificationService?>(),
      sync = context.read<CloudSyncProvider?>(),
      auth = context.read<AuthProvider?>(),
      lock = context.read<AppLockProvider?>(),
      update = context.read<AppUpdateService?>(),
      sourceRoute = ModalRoute.of(context) {
    _templateGeneration = templates?.storageGeneration;
    _todoGeneration = todos?.storageGeneration;
    _focusGeneration = pomodoro?.storageGeneration;
    _client = _clientSnapshot();
    for (final notifier in [auth, lock, update, templates, todos, pomodoro]) {
      if (notifier != null) {
        notifier.addListener(_observeAuthority);
        _notifiers.add(notifier);
      }
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _observeAuthority,
    );
    for (final observer in Navigator.of(context).widget.observers) {
      if (observer is AppAccessRouteGate) {
        _gates.add(observer);
        observer.routeRevision.addListener(_observeRoute);
      }
    }
  }

  final BuildContext context;
  final SettingsActionOrigin authority;
  final NoteProvider? notes;
  final TodoProvider? todos;
  final HabitProvider? habits;
  final DiaryProvider? diary;
  final PomodoroProvider? pomodoro;
  final QuickCaptureTemplateProvider? templates;
  final NotificationService? notifications;
  final CloudSyncProvider? sync;
  final AuthProvider? auth;
  final AppLockProvider? lock;
  final AppUpdateService? update;
  final ModalRoute<dynamic>? sourceRoute;
  final _notifiers = <ChangeNotifier>[];
  final _gates = <AppAccessRouteGate>[];
  late final int? _templateGeneration;
  late final int? _todoGeneration;
  late final int? _focusGeneration;
  late final Object _client;
  ModalRoute<dynamic>? route;
  bool _expired = false;
  bool _disposed = false;

  Object _clientSnapshot() => (
    auth?.client,
    auth?.client.token,
    auth?.client.baseUrl,
    auth?.state.token,
  );

  bool _ownsSource() =>
      authority.isCurrent(checkRoute: false) &&
      identical(context.read<NoteProvider?>(), notes) &&
      identical(context.read<TodoProvider?>(), todos) &&
      identical(context.read<HabitProvider?>(), habits) &&
      identical(context.read<DiaryProvider?>(), diary) &&
      identical(context.read<PomodoroProvider?>(), pomodoro) &&
      identical(context.read<QuickCaptureTemplateProvider?>(), templates) &&
      identical(context.read<NotificationService?>(), notifications) &&
      identical(context.read<CloudSyncProvider?>(), sync) &&
      templates?.storageGeneration == _templateGeneration &&
      todos?.storageGeneration == _todoGeneration &&
      pomodoro?.storageGeneration == _focusGeneration &&
      _clientSnapshot() == _client;

  void _observeAuthority() {
    if (_disposed || _expired) return;
    if (!context.mounted || !_ownsSource()) _invalidate();
  }

  void _observeRoute() {
    if (_disposed || _expired) return;
    for (final gate in _gates) {
      final current = gate.currentRoute;
      if (!identical(current, route) && !identical(current, sourceRoute)) {
        _invalidate();
      }
    }
  }

  void _observeCover() {
    if ((route?.secondaryAnimation?.value ?? 0) > 0) _invalidate();
  }

  void _invalidate() {
    if (_expired || _disposed) return;
    _expired = true;
    _closeOwnedModal();
  }

  void _closeOwnedModal() {
    final owned = route;
    // Remove the exact obsolete modal, even if another route covers it.
    // Dedicated editor pages own their navigation and are not removed here.
    if (owned is! DialogRoute && owned is! ModalBottomSheetRoute) return;
    void close() {
      final navigator = owned?.navigator;
      if (owned?.isActive == true && navigator?.mounted == true) {
        navigator!.removeRoute(owned!);
      }
    }

    scheduleMicrotask(() {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => close());
      } else {
        close();
      }
    });
  }

  void own(ModalRoute<dynamic> owned) {
    route = owned;
  }

  void listenForCover() {
    route?.secondaryAnimation?.addListener(_observeCover);
  }

  void release(ModalRoute<dynamic> owned) {
    owned.secondaryAnimation?.removeListener(_observeCover);
    if (identical(route, owned)) route = null;
  }

  bool isCurrent() {
    if (_disposed || _expired || !context.mounted) return false;
    _observeAuthority();
    _observeRoute();
    if (_expired) return false;
    final owned = route;
    return owned == null
        ? sourceRoute == null || sourceRoute!.isCurrent
        : owned.isActive && owned.isCurrent;
  }

  void dispose() {
    if (_disposed) return;
    _closeOwnedModal();
    _disposed = true;
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _observeAuthority,
    );
    route?.secondaryAnimation?.removeListener(_observeCover);
    for (final notifier in _notifiers) {
      notifier.removeListener(_observeAuthority);
    }
    for (final gate in _gates) {
      gate.routeRevision.removeListener(_observeRoute);
    }
  }
}

/// Keep retained control callbacks from mutating a removed or expired form.
class _CaptureStatefulBuilder extends StatelessWidget {
  const _CaptureStatefulBuilder({
    required this.operation,
    required this.builder,
  });
  final _CaptureOperation operation;
  final StatefulWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => StatefulBuilder(
    builder: (context, setState) => builder(context, (mutation) {
      if (context.mounted && operation.isCurrent()) setState(mutation);
    }),
  );
}
