import '../widgets/app_date_format.dart';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/image_decode_cache.dart';
import '../core/i18n_date_format.dart';
import '../core/todo_detail_ui_copy.dart';
import '../models/goal.dart' show ReminderKind, ReminderPlan;
import '../models/location_reminder.dart';
import '../models/note.dart' show NoteAttachment, NoteBlock, NoteBlockType;
import '../models/todo.dart';
import '../models/workspace.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../services/alarm_service.dart';
import '../services/local_notifications.dart';
import '../services/note_attachment_picker.dart';
import '../services/reminder_issue_copy.dart' show NotificationIssueTitle;
import '../services/reminder_scheduler.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/notification_service.dart';
import '../providers/share_provider.dart';
import '../providers/todo_provider.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart';
import '../widgets/controller_dialog.dart';

/// Todo 详情页 / 编辑页。
///
/// Todo 详情页 / 编辑页状态机。
///
/// - `_EditState` 四档：`clean / editing / saving / confirmDiscard`；
/// - AppBar 的 check 按钮保存成功后返回上一页；
/// - 返回键在 `editing` 下会弹"放弃修改"对话框；
/// - 用 `PopScope` + `onPopInvoked` 统一拦截路由 pop，`Clean` 状态直接放行。
///
/// 同时保留 Task 7 的视觉对齐：token 化间距 / 圆角、优先级 ChoiceChip、提醒
/// 分段、目标时长模块、标签 / 子任务 / 重复 / 截止日 等模块。
class TodoDetailScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String todoId;
  final int? accountGeneration;

  const TodoDetailScreen({
    super.key,
    required this.todoId,
    this.accountGeneration,
  });

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

/// "保存不返回" 状态机的四档状态。
///
/// - `clean`    ：与基线一致，无未保存改动；返回键直接 pop；
/// - `editing`  ：至少有一处与基线不同，点击保存会 → `saving`，点击返回会
///                → `confirmDiscard`；
/// - `saving`   ：正在写入 provider / 持久化；期间不应再触发另一次保存；
/// - `confirmDiscard`：正在展示"放弃修改"对话框，用户选择后回到
///                `editing`（取消）或 `clean` → pop（放弃）。
enum _EditState { clean, editing, saving, confirmDiscard }

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _subtaskCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _timeTargetCtrl = TextEditingController();
  late TodoItem _todo;
  bool _missingTodo = false;
  bool _notesPreview = false;
  bool _subtaskAdding = false;
  int _saveSeq = 0;
  int _subtaskAddingSeq = 0;
  int _subtaskActionSeq = 0;
  final Map<String, int> _subtaskOpSeqs = <String, int>{};
  final Set<String> _busySubtaskIds = <String>{};
  String? _commentsLoadedForWorkspaceId;

  /// "保存不返回"状态机当前状态。
  _EditState _state = _EditState.clean;

  /// 基线快照：`_load()` 与成功保存后都会刷新。任何与基线偏离的改动
  /// 都会把状态抬升到 `editing`。用 JSON 化的字符串表示，避免深比较。
  late String _baseline;
  late TodoItem _baselineTodo;
  late final int _originAccountGeneration;

  @override
  void initState() {
    super.initState();
    _originAccountGeneration =
        widget.accountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
    _load();
  }

  void _onAccountDataGenerationChanged() {
    if (!mounted) return;
    _saveSeq++;
    _subtaskAddingSeq++;
    _subtaskActionSeq++;
    _subtaskOpSeqs.clear();
    _busySubtaskIds.clear();
    _subtaskAdding = false;
    if (_state == _EditState.saving) {
      _state = _EditState.editing;
    }
    if (!_isCurrentAccount) {
      _titleCtrl.clear();
      _notesCtrl.clear();
      _subtaskCtrl.clear();
      _tagCtrl.clear();
      _timeTargetCtrl.clear();
      _todo = TodoItem(id: widget.todoId, title: '');
      _baselineTodo = _cloneTodo(_todo);
      _baseline = '';
      _missingTodo = true;
      _state = _EditState.clean;
    }
    setState(() {});
  }

  bool get _isCurrentAccount =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        _originAccountGeneration,
      );

  /// 把当前 `_todo` + 文本控制器中的可编辑字段序列化为快照字符串。
  ///
  /// 这里只关心"UI 可编辑"的字段，不包括 `createdAt / id / sortOrder` 等
  /// 由系统维护的元字段，也不包括 `subtasks` 的完成状态（子任务勾选会直接
  /// 调 provider，不走本页的 save 路径）。
  String _snapshot(TodoItem t) {
    final tags = [...t.tags]..sort();
    return <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'quadrant': t.quadrant.index,
      'priority': t.priority.index,
      'listGroupId': t.listGroupId,
      'tags': tags,
      'dueDate': t.dueDate?.toIso8601String(),
      'reminderPlan': t.reminderPlan.toJson(),
      'focusLink': t.focusLink.toJson(),
      'timeTargetSeconds': t.timeTargetSeconds,
      'recurrence': t.recurrence.toJson(),
      'autoToggleByChildren': t.autoToggleByChildren,
      'workspaceId': t.workspaceId,
      'assigneeId': t.assigneeId,
      'attachments': t.attachments.map((a) => a.toJson()).toList(),
    }.toString();
  }

  bool _reminderSchedulingFieldsChanged(TodoItem before, TodoItem after) {
    // ignore: deprecated_member_use_from_same_package
    final beforeHasReminder = before.hasReminder;
    // ignore: deprecated_member_use_from_same_package
    final afterHasReminder = after.hasReminder;
    final beforeReminderEnabled =
        beforeHasReminder ||
        before.reminder.enabled ||
        before.reminderPlan.enabled;
    final afterReminderEnabled =
        afterHasReminder ||
        after.reminder.enabled ||
        after.reminderPlan.enabled;
    if (!beforeReminderEnabled && !afterReminderEnabled) return false;
    // ignore: deprecated_member_use_from_same_package
    final beforeReminderAt = before.reminderAt;
    // ignore: deprecated_member_use_from_same_package
    final afterReminderAt = after.reminderAt;
    final legacyChanged =
        beforeHasReminder != afterHasReminder ||
        beforeReminderAt != afterReminderAt;
    return before.dueDate != after.dueDate ||
        legacyChanged ||
        jsonEncode(before.reminder.toJson()) !=
            jsonEncode(after.reminder.toJson()) ||
        jsonEncode(before.reminderPlan.toJson()) !=
            jsonEncode(after.reminderPlan.toJson());
  }

  void _load() {
    if (!_isCurrentAccount) {
      _todo = TodoItem(id: widget.todoId, title: '');
      _baselineTodo = _cloneTodo(_todo);
      _baseline = '';
      _missingTodo = true;
      _state = _EditState.clean;
      return;
    }
    final provider = context.read<TodoProvider>();
    final matches = provider.todos.where((t) => t.id == widget.todoId);
    if (matches.isEmpty) {
      _todo = TodoItem(id: widget.todoId, title: '');
      _baselineTodo = _cloneTodo(_todo);
      _baseline = '';
      _missingTodo = true;
      _state = _EditState.clean;
      return;
    }
    final todo = matches.first;
    _missingTodo = false;
    _syncDraftFromProvider(todo);
    _baselineTodo = _cloneTodo(todo);
    _baseline = _snapshot(_todo);
    _state = _EditState.clean;
  }

  void _syncDraftFromProvider(TodoItem todo) {
    _todo = todo;
    if (_titleCtrl.text != todo.title) {
      _titleCtrl.text = todo.title;
    }
    if (_notesCtrl.text != todo.notes) {
      _notesCtrl.text = todo.notes;
    }
    final sec = todo.timeTargetSeconds;
    final minutesText = sec != null && sec > 0 ? (sec ~/ 60).toString() : '';
    if (_timeTargetCtrl.text != minutesText) {
      _timeTargetCtrl.text = minutesText;
    }
  }

  TodoItem _cloneTodo(TodoItem todo) => TodoItem.fromJson(todo.toJson());

  TodoItem _mergeEditableDraftIntoLatest(TodoItem latest, TodoItem draft) {
    final base = _baselineTodo;
    var next = latest;
    if (draft.title != base.title) {
      next = next.copyWith(title: draft.title);
    }
    if (draft.notes != base.notes) {
      next = next.copyWith(notes: draft.notes);
    }
    if (draft.quadrant != base.quadrant) {
      next = next.copyWith(quadrant: draft.quadrant);
    }
    if (draft.priority != base.priority) {
      next = next.copyWith(priority: draft.priority);
    }
    if (draft.listGroupId != base.listGroupId) {
      next = next.copyWith(listGroupId: draft.listGroupId);
    }
    if (draft.listGroupName != base.listGroupName) {
      next = next.copyWith(listGroupName: draft.listGroupName);
    }
    if (draft.workspaceId != base.workspaceId) {
      next = next.copyWith(workspaceId: draft.workspaceId);
    }
    if (draft.assigneeId != base.assigneeId) {
      next = next.copyWith(assigneeId: draft.assigneeId);
    }
    if (!_sameJson(draft.tags, base.tags)) {
      next = next.copyWith(tags: [...draft.tags]);
    }
    if (!_sameJson(
      draft.attachments.map((a) => a.toJson()).toList(),
      base.attachments.map((a) => a.toJson()).toList(),
    )) {
      next = next.copyWith(attachments: [...draft.attachments]);
    }
    if (draft.dueDate != base.dueDate) {
      next = next.copyWith(dueDate: draft.dueDate);
    }
    if (_reminderSchedulingFieldsChanged(base, draft)) {
      next = next.copyWith(
        hasReminder: draft.hasReminder,
        reminderAt: draft.reminderAt,
        reminder: draft.reminder,
        reminderPlan: draft.reminderPlan,
      );
    }
    if (!_sameJson(draft.focusLink.toJson(), base.focusLink.toJson())) {
      next = next.copyWith(focusLink: draft.focusLink);
    }
    if (draft.timeTargetSeconds != base.timeTargetSeconds) {
      next = next.copyWith(timeTargetSeconds: draft.timeTargetSeconds);
    }
    if (!_sameJson(draft.recurrence.toJson(), base.recurrence.toJson())) {
      next = next.copyWith(recurrence: draft.recurrence);
    }
    if (draft.autoToggleByChildren != base.autoToggleByChildren) {
      next = next.copyWith(autoToggleByChildren: draft.autoToggleByChildren);
    }
    return next;
  }

  bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  /// 任一可编辑字段变动时调用；根据是否偏离基线切换状态。
  ///
  /// - 若当前已经是 `saving`，保持不动（在途保存不应被抢占）；
  /// - 若当前与基线一致，回到 `clean`；否则升到 `editing`。
  void _markEditing() {
    if (!_isCurrentAccount || _state == _EditState.saving) return;
    final dirty = _snapshot(_todo) != _baseline;
    final next = dirty ? _EditState.editing : _EditState.clean;
    if (_state != next) {
      setState(() => _state = next);
    }
  }

  /// 保存当前编辑结果。
  ///
  /// - `clean`：不触发任何写入，直接返回上一页；
  /// - 其他状态：`_state = saving` → `updateTodo` → 成功回到 `clean`
  ///   并刷新基线后返回上一页；失败回到 `editing`
  ///   并展示错误 snackbar。
  ///
  Future<void> _save() async {
    if (!_isCurrentAccount || _state == _EditState.saving) return;
    final provider = context.read<TodoProvider>();
    final savedTodo = provider.todos.firstWhere(
      (t) => t.id == widget.todoId,
      orElse: () => _todo,
    );
    if (!(context.read<ShareProvider?>()?.canEdit(savedTodo.workspaceId) ??
        true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(TodoDetailUiCopy.sharedSpaceReadOnlyError),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 同步基线检查：用户点了 check 但什么也没改 → 轻量反馈、不打扰。
    if (_state == _EditState.clean) {
      Navigator.of(context).maybePop();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(TodoDetailUiCopy.taskTitleEmptyError),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.error,
        ),
      );
      return;
    }

    final draftTodo = _todo.copyWith(
      title: title,
      notes: _notesCtrl.text.trim(),
    );
    final nextTodo = _mergeEditableDraftIntoLatest(savedTodo, draftTodo);
    final seq = ++_saveSeq;
    setState(() => _state = _EditState.saving);

    try {
      final waitForReminderSync = _reminderSchedulingFieldsChanged(
        savedTodo,
        nextTodo,
      );
      if (waitForReminderSync) {
        final reminderReady = await preflightTodoReminderSave(
          context,
          todo: nextTodo,
          notificationService: context.read<NotificationService?>(),
          issueTitleBuilder: () =>
              TodoDetailUiCopy.reminderRegisterFailedIssueTitle,
          issueTitleCode: NotificationIssueTitle.taskRegistrationFailed,
          accountGeneration: _originAccountGeneration,
        );
        if (!mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            ) ||
            _saveSeq != seq) {
          return;
        }
        if (!reminderReady) {
          _restoreEditingAfterSaveInterruption(seq);
          return;
        }
      }
      final saveResult = await provider.updateTodoWithResult(
        widget.todoId,
        nextTodo,
        waitForReminderSync: waitForReminderSync,
      );
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          ) ||
          _saveSeq != seq) {
        return;
      }
      if (!saveResult.saved) {
        _restoreEditingAfterSaveInterruption(seq);
        messenger.showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, _, _) =>
                  Text(TodoDetailUiCopy.saveInProgressError),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: cs.error,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      final reminderSyncIssue = waitForReminderSync
          ? saveResult.reminderSync?.issue
          : null;

      // 刷新本地 _todo 引用与基线，便于继续编辑。
      _todo = provider.todos.firstWhere(
        (t) => t.id == widget.todoId,
        orElse: () => _todo,
      );
      _baselineTodo = _cloneTodo(_todo);
      _baseline = _snapshot(_todo);
      setState(() => _state = _EditState.clean);

      if (reminderSyncIssue != null) {
        messenger.showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, _, _) => Text(
                TodoDetailUiCopy.savedWithoutReminder(reminderSyncIssue),
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: cs.error,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              _originAccountGeneration,
            ) ||
            _saveSeq != seq) {
          return;
        }
        Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          ) ||
          _saveSeq != seq) {
        return;
      }
      _restoreEditingAfterSaveInterruption(seq);
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(TodoDetailUiCopy.saveFailed(userVisibleApiError(e))),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.error,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted && _saveSeq == seq) {
        if (_state == _EditState.saving) {
          setState(() => _state = _EditState.editing);
        }
      }
    }
  }

  void _restoreEditingAfterSaveInterruption(int seq) {
    if (!mounted || _saveSeq != seq || _state != _EditState.saving) return;
    setState(() => _state = _EditState.editing);
  }

  /// 用户尝试返回时（系统返回键 / AppBar 返回按钮）。
  ///
  /// - `editing`：转到 `confirmDiscard` 并弹确认框；
  ///   - "放弃"：重置为 `clean` 后允许路由 pop；
  ///   - "取消"：保持 `editing`，不 pop。
  /// - 其他状态：放行。
  ///
  /// 返回 `true` 表示"允许 pop"，返回 `false` 表示"拦截"。
  Future<bool> _handleBack() async {
    if (!_isCurrentAccount) return true;
    if (_state == _EditState.saving) {
      // 正在保存期间不允许离开页面，避免 provider 写入与 pop 竞态。
      return false;
    }
    if (_state != _EditState.editing) return true;

    setState(() => _state = _EditState.confirmDiscard);
    final discard = await showControllerDialog<bool>(
      context: context,
      controllers: const [],
      builder: (dialogCtx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => AppDialog(
          title: Text(TodoDetailUiCopy.discardDialogTitle),
          content: Text(TodoDetailUiCopy.discardDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(TodoDetailUiCopy.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(TodoDetailUiCopy.discardAction),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return false;
    if (!_isCurrentAccount) return true;

    if (discard == true) {
      setState(() => _state = _EditState.clean);
      return true;
    }
    setState(() => _state = _EditState.editing);
    return false;
  }

  Future<void> _addSubtask() async {
    if (_subtaskAdding || !_isCurrentAccount) return;
    if (!(context.read<ShareProvider?>()?.canEdit(_todo.workspaceId) ?? true)) {
      return;
    }
    final title = _subtaskCtrl.text.trim();
    if (title.isEmpty) return;
    final seq = ++_subtaskAddingSeq;
    setState(() => _subtaskAdding = true);
    try {
      await context.read<TodoProvider>().addSubtask(
        widget.todoId,
        title,
        expectedAccountDataGeneration: _originAccountGeneration,
      );
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          ) ||
          _subtaskAddingSeq != seq) {
        return;
      }
      _subtaskCtrl.clear();
      _refreshTodoBaseline();
    } finally {
      if (mounted && _subtaskAddingSeq == seq) {
        setState(() => _subtaskAdding = false);
      }
    }
  }

  void _refreshTodoBaseline() {
    if (!_isCurrentAccount) return;
    setState(() {
      _todo = context.read<TodoProvider>().todos.firstWhere(
        (t) => t.id == widget.todoId,
        orElse: () => _todo,
      );
      _baselineTodo = _cloneTodo(_todo);
      _baseline = _snapshot(_todo);
    });
  }

  Future<void> _toggleSubtask(String subtaskId) async {
    if (!_isCurrentAccount || !_busySubtaskIds.add(subtaskId)) return;
    final seq = ++_subtaskActionSeq;
    _subtaskOpSeqs[subtaskId] = seq;
    setState(() {});
    try {
      await context.read<TodoProvider>().toggleSubtask(
        widget.todoId,
        subtaskId,
        expectedAccountDataGeneration: _originAccountGeneration,
      );
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          ) ||
          _subtaskOpSeqs[subtaskId] != seq) {
        return;
      }
      _refreshTodoBaseline();
    } finally {
      if (mounted && _subtaskOpSeqs[subtaskId] == seq) {
        _subtaskOpSeqs.remove(subtaskId);
        setState(() => _busySubtaskIds.remove(subtaskId));
      }
    }
  }

  Future<void> _deleteSubtask(String subtaskId) async {
    if (!_isCurrentAccount || !_busySubtaskIds.add(subtaskId)) return;
    final seq = ++_subtaskActionSeq;
    _subtaskOpSeqs[subtaskId] = seq;
    setState(() {});
    try {
      await context.read<TodoProvider>().deleteSubtask(
        widget.todoId,
        subtaskId,
        expectedAccountDataGeneration: _originAccountGeneration,
      );
      if (!mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          ) ||
          _subtaskOpSeqs[subtaskId] != seq) {
        return;
      }
      _refreshTodoBaseline();
    } finally {
      if (mounted && _subtaskOpSeqs[subtaskId] == seq) {
        _subtaskOpSeqs.remove(subtaskId);
        setState(() => _busySubtaskIds.remove(subtaskId));
      }
    }
  }

  void _addTag(String v) {
    if (!_isCurrentAccount) return;
    final value = v.trim();
    if (value.isEmpty) return;
    if (_todo.tags.contains(value)) return;
    setState(() {
      _todo = _todo.copyWith(tags: [..._todo.tags, value]);
      _tagCtrl.clear();
    });
    _markEditing();
  }

  void _removeTag(String tag) {
    if (!_isCurrentAccount) return;
    setState(() {
      _todo = _todo.copyWith(tags: _todo.tags.where((x) => x != tag).toList());
    });
    _markEditing();
  }

  Future<void> _addAttachment() async {
    if (!_isCurrentAccount) return;
    final picked = await NoteAttachmentPicker.pickFile();
    if (!mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        picked == null) {
      return;
    }
    setState(() {
      _todo = _todo.copyWith(attachments: [..._todo.attachments, picked]);
    });
    _markEditing();
  }

  void _addManualAttachment(NoteAttachment attachment) {
    if (!_isCurrentAccount) return;
    setState(() {
      _todo = _todo.copyWith(attachments: [..._todo.attachments, attachment]);
    });
    _markEditing();
  }

  Future<void> _showManualAttachmentDialog() async {
    if (!_isCurrentAccount) return;
    final nameCtrl = TextEditingController();
    final uriCtrl = TextEditingController();
    final mimeCtrl = TextEditingController();
    final attachment = await showControllerDialog<NoteAttachment>(
      context: context,
      controllers: [nameCtrl, uriCtrl, mimeCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => AppDialog(
          title: Text(TodoDetailUiCopy.addAttachmentLinkDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: TodoDetailUiCopy.attachmentNameLabel,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: uriCtrl,
                decoration: InputDecoration(
                  labelText: TodoDetailUiCopy.attachmentUriLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mimeCtrl,
                decoration: InputDecoration(
                  labelText: TodoDetailUiCopy.attachmentMimeLabel,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(TodoDetailUiCopy.cancel),
            ),
            FilledButton(
              onPressed: () {
                final uri = uriCtrl.text.trim();
                if (uri.isEmpty) return;
                Navigator.pop(
                  ctx,
                  NoteAttachment(
                    name: nameCtrl.text.trim().isEmpty
                        ? TodoDetailUiCopy.defaultAttachmentName
                        : nameCtrl.text.trim(),
                    uri: uri,
                    mimeType: mimeCtrl.text.trim(),
                  ),
                );
              },
              child: Text(TodoDetailUiCopy.add),
            ),
          ],
        ),
      ),
    );
    if (!mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        ) ||
        attachment == null) {
      return;
    }
    _addManualAttachment(attachment);
  }

  void _removeAttachment(NoteAttachment attachment) {
    if (!_isCurrentAccount) return;
    setState(() {
      _todo = _todo.copyWith(
        attachments: _todo.attachments.where((a) => a != attachment).toList(),
      );
    });
    _markEditing();
  }

  Future<void> _pickDueDate() async {
    if (!_isCurrentAccount) return;
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _todo.dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
      title: TodoDetailUiCopy.dueDatePickerTitle,
      subtitle: TodoDetailUiCopy.dueDatePickerSubtitle,
    );
    if (!mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }
    if (picked != null) {
      setState(() => _todo = _todo.copyWith(dueDate: picked));
      _markEditing();
    }
  }

  Future<void> _pickRecurrence() async {
    if (!_isCurrentAccount) return;
    final r = await RecurrencePicker.show(context, initial: _todo.recurrence);
    if (!mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }
    if (r != null) {
      setState(() => _todo = _todo.copyWith(recurrence: r));
      _markEditing();
    }
  }

  // ---- Priority ----------------------------------------------------------

  void _pickPriority(TodoPriority p) {
    if (!_isCurrentAccount) return;
    setState(() => _todo = _todo.copyWith(priority: p));
    _markEditing();
  }

  // ---- Reminder ----------------------------------------------------------

  /// 同步新 `reminderPlan` 与旧 `reminder / hasReminder / reminderAt` 镜像。
  void _applyReminderPlan(ReminderPlan plan) {
    if (!_isCurrentAccount) return;
    final legacy = plan.toLegacyReminderConfig(fallback: _todo.reminder);
    final nowForMirror = DateTime.now();
    DateTime? mirroredAt;
    if (legacy.enabled && legacy.hour != null && legacy.minute != null) {
      final base = _todo.dueDate ?? _todo.reminderAt ?? nowForMirror;
      mirroredAt = DateTime(
        base.year,
        base.month,
        base.day,
        legacy.hour!,
        legacy.minute!,
      );
      if (_todo.dueDate == null && !mirroredAt.isAfter(nowForMirror)) {
        mirroredAt = mirroredAt.add(const Duration(days: 1));
      }
    }
    setState(() {
      // ignore: deprecated_member_use_from_same_package
      _todo = _todo.copyWith(
        reminder: legacy,
        reminderPlan: plan,
        hasReminder: legacy.enabled,
        reminderAt: mirroredAt,
      );
    });
    _markEditing();
  }

  // ---- Time target -------------------------------------------------------

  void _applyTimeTargetMinutes(int? minutes) {
    if (!_isCurrentAccount) return;
    final seconds = (minutes == null || minutes <= 0) ? null : minutes * 60;
    setState(() {
      _todo = _todo.copyWith(timeTargetSeconds: seconds);
      _timeTargetCtrl.text = (seconds == null)
          ? ''
          : (seconds ~/ 60).toString();
    });
    _markEditing();
  }

  void _insertNotePrefix(String prefix) {
    if (!_isCurrentAccount) return;
    final text = _notesCtrl.text;
    final selection = _notesCtrl.selection;
    final start = selection.isValid ? selection.start : text.length;
    final lineStart = start <= 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final next = text.replaceRange(lineStart, lineStart, prefix);
    _notesCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
    _markEditing();
  }

  void _wrapNoteSelection(String marker) {
    if (!_isCurrentAccount) return;
    final text = _notesCtrl.text;
    final selection = _notesCtrl.selection;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.start : text.length;
      final next = text.replaceRange(offset, offset, '$marker$marker');
      _notesCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: offset + marker.length),
      );
      _markEditing();
      return;
    }

    final selected = selection.textInside(text);
    final next = text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    );
    _notesCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: selection.end + marker.length * 2,
      ),
    );
    _markEditing();
  }

  void _insertNoteLink() {
    if (!_isCurrentAccount) return;
    final text = _notesCtrl.text;
    final selection = _notesCtrl.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? selection.textInside(text)
        : TodoDetailUiCopy.markdownLinkPlaceholder;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final replacement = '[$selected](https://)';
    final next = text.replaceRange(start, end, replacement);
    _notesCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + replacement.length - 1,
      ),
    );
    _markEditing();
  }

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _subtaskCtrl.dispose();
    _tagCtrl.dispose();
    _timeTargetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final theme = Theme.of(context);
        final routeBackground = theme.brightness == Brightness.dark
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLowest;
        final surfaceStyle = appSurfaceStyleOf(context);
        final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

        Widget wrapWithBackground(Widget child) {
          if (!isLiquidGlass) {
            return child;
          }
          final hasBrandSurface =
              context.findAncestorWidgetOfExactType<BrandBackground>() !=
                  null ||
              context.findAncestorWidgetOfExactType<BrandRouteSurface>() !=
                  null;
          if (hasBrandSurface) {
            return child;
          }
          return Material(
            color: routeBackground,
            child: BrandBackground(child: child),
          );
        }

        if (!_isCurrentAccount ||
            _missingTodo ||
            !provider.todos.any((t) => t.id == widget.todoId)) {
          final missingRoute = PopScope(
            canPop: true,
            child: Scaffold(
              backgroundColor: isLiquidGlass ? Colors.transparent : null,
              appBar: AppBar(
                title: Text(TodoDetailUiCopy.screenTitle),
                titleTextStyle: appSecondaryRouteTitleTextStyle(context),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(DesignTokens.space3xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 56,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: DesignTokens.spaceMd),
                              Text(
                                TodoDetailUiCopy.taskNotFound,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: DesignTokens.spaceLg),
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back),
                                label: Text(TodoDetailUiCopy.back),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          return wrapWithBackground(missingRoute);
        }
        if (_isCurrentAccount) {
          final providerTodo = provider.todos.firstWhere(
            (t) => t.id == widget.todoId,
            orElse: () => _todo,
          );
          if (_state == _EditState.clean) {
            _syncDraftFromProvider(providerTodo);
          }
        }
        final canEdit =
            _isCurrentAccount &&
            (context.watch<ShareProvider?>()?.canEdit(_todo.workspaceId) ??
                true);
        final shareProvider = context.watch<ShareProvider?>();
        final locationReminderProvider = context
            .watch<LocationReminderProvider?>();
        final linkedLocationReminders =
            locationReminderProvider?.reminders
                .where((r) => r.linkedType == 'todo' && r.linkedId == _todo.id)
                .toList() ??
            const <LocationReminder>[];
        final workspace = _workspaceFor(shareProvider, _todo.workspaceId);
        if (_isCurrentAccount &&
            workspace != null &&
            _commentsLoadedForWorkspaceId != workspace.id &&
            shareProvider != null) {
          _commentsLoadedForWorkspaceId = workspace.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_isCurrentAccount) return;
            context.read<ShareProvider>().loadWorkspaceCollaboration(
              workspace.id,
            );
          });
        }
        final cs = Theme.of(context).colorScheme;

        // canPop 反映当前状态机是否允许直接 pop：
        // - clean：没有未保存改动，系统返回键 / AppBar 返回键直接放行；
        // - 其它：拦截，走 `_handleBack` → 弹"放弃修改"对话框的分支。
        final bool canPop = !_isCurrentAccount || _state == _EditState.clean;
        final detailRoute = PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final allow = await _handleBack();
            if (allow && mounted) {
              // `_handleBack` 已经把 state 切回 clean；再主动请求一次 pop。
              // ignore: use_build_context_synchronously
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: isLiquidGlass ? Colors.transparent : null,
            appBar: AppBar(
              title: Text(TodoDetailUiCopy.screenTitle),
              titleTextStyle: appSecondaryRouteTitleTextStyle(context),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // 统一走 PopScope：clean → 直接 pop；其它 → 触发
                  // `onPopInvokedWithResult` 的拦截分支。
                  Navigator.of(context).maybePop();
                },
              ),
              actions: [
                IconButton(
                  icon: _state == _EditState.saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  tooltip: TodoDetailUiCopy.save,
                  onPressed: _state == _EditState.saving || !canEdit
                      ? null
                      : _save,
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(DesignTokens.spaceLg),
              children: [
                TextField(
                  controller: _titleCtrl,
                  enabled: canEdit,
                  decoration: InputDecoration(
                    labelText: TodoDetailUiCopy.taskTitleLabel,
                  ),
                  style: const TextStyle(
                    fontSize: DesignTokens.fontSizeLg,
                    fontWeight: FontWeight.normal,
                  ),
                  onChanged: (_) => _markEditing(),
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                _TodoMarkdownDescriptionEditor(
                  controller: _notesCtrl,
                  preview: _notesPreview,
                  enabled: canEdit,
                  onPreviewChanged: (value) =>
                      setState(() => _notesPreview = value),
                  onChanged: (_) => _markEditing(),
                  onHeading: () => _insertNotePrefix('## '),
                  onBold: () => _wrapNoteSelection('**'),
                  onItalic: () => _wrapNoteSelection('*'),
                  onQuote: () => _insertNotePrefix('> '),
                  onBullet: () => _insertNotePrefix('- '),
                  onChecklist: () => _insertNotePrefix('- [ ] '),
                  onCode: () => _wrapNoteSelection('`'),
                  onLink: _insertNoteLink,
                ),

                const SizedBox(height: DesignTokens.spaceLg),
                _TodoAttachmentPanel(
                  attachments: _todo.attachments,
                  enabled: canEdit,
                  onPickFile: _addAttachment,
                  onAddManual: _showManualAttachmentDialog,
                  onRemove: _removeAttachment,
                ),

                // ---- 四象限 --------------------------------------------------
                const SizedBox(height: DesignTokens.spaceLg),
                AppDropdownField<EisenhowerQuadrant>(
                  initialValue: _todo.quadrant,
                  wrapSelectedText: true,
                  labelText: TodoDetailUiCopy.quadrantLabel,
                  enabled: canEdit,
                  items: [
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.urgentImportant,
                      child: Text(TodoDetailUiCopy.quadrantQ1),
                    ),
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.notUrgentImportant,
                      child: Text(TodoDetailUiCopy.quadrantQ2),
                    ),
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.urgentNotImportant,
                      child: Text(TodoDetailUiCopy.quadrantQ3),
                    ),
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.notUrgentNotImportant,
                      child: Text(TodoDetailUiCopy.quadrantQ4),
                    ),
                  ],
                  onChanged: (v) {
                    if (!canEdit || v == null) return;
                    setState(() => _todo = _todo.copyWith(quadrant: v));
                    _markEditing();
                  },
                ),

                // ---- 优先级 --------------------------------------------------
                const SizedBox(height: DesignTokens.spaceLg),
                _SectionLabel(text: TodoDetailUiCopy.prioritySection),
                const SizedBox(height: DesignTokens.spaceXs),
                _PriorityChipRow(
                  selected: _todo.priority,
                  enabled: canEdit,
                  onSelected: _pickPriority,
                ),

                // ---- 截止日 + 重复 --------------------------------------------
                const SizedBox(height: DesignTokens.spaceLg),
                AppSurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: Text(TodoDetailUiCopy.dueDateTileTitle),
                        subtitle: Text(
                          _todo.dueDate == null
                              ? TodoDetailUiCopy.dueDateNotSet
                              : AppDateFormat.date(context, _todo.dueDate!),
                        ),
                        trailing: _todo.dueDate == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: canEdit
                                    ? () {
                                        setState(
                                          () => _todo = _todo.copyWith(
                                            dueDate: null,
                                          ),
                                        );
                                        _markEditing();
                                      }
                                    : null,
                              ),
                        onTap: canEdit ? _pickDueDate : null,
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 40,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.repeat),
                        title: Text(TodoDetailUiCopy.repeatTileTitle),
                        subtitle: Text(
                          _todo.recurrence.displayLabel(
                            datePattern: AppDateFormat.patternOf(context),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: canEdit ? _pickRecurrence : null,
                      ),
                    ],
                  ),
                ),

                // ---- 共享负责人 ----------------------------------------------
                const SizedBox(height: DesignTokens.spaceSm),
                _AssignmentEditor(
                  workspace: workspace,
                  assigneeId: _todo.assigneeId,
                  enabled: canEdit,
                  onChanged: (value) {
                    if (!canEdit) return;
                    setState(() => _todo = _todo.copyWith(assigneeId: value));
                    _markEditing();
                  },
                ),
                if (workspace != null && shareProvider != null) ...[
                  const SizedBox(height: DesignTokens.spaceLg),
                  _TaskCommentsPanel(
                    workspace: workspace,
                    todoId: _todo.id,
                    comments: shareProvider.commentsForTarget(
                      workspace.id,
                      _todo.id,
                    ),
                    accountGeneration: _originAccountGeneration,
                    enabled: canEdit,
                  ),
                ],

                // ---- 提醒 ----------------------------------------------------
                const SizedBox(height: DesignTokens.spaceSm),
                IgnorePointer(
                  ignoring: !canEdit,
                  child: ReminderPlanEditor(
                    plan: _todo.reminderPlan,
                    onChanged: (p) {
                      if (!canEdit) return;
                      _applyReminderPlan(p);
                    },
                    title: TodoDetailUiCopy.reminderTitle,
                    allowAlarm: true,
                    allowRelativeToDue: true,
                    allowWeekly: true,
                    hasAnchorDate: _todo.dueDate != null,
                    defaultKind: ReminderKind.push,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Builder(
                  builder: (context) {
                    final notif = context.watch<NotificationService?>();
                    if (notif == null) return const SizedBox.shrink();
                    final kind =
                        _todo.reminderPlan.primaryRule?.kind ??
                        _todo.reminder.kind;
                    return ReminderHealthHint(
                      reminderKind: kind,
                      onOpenSystemSettings: () => _openSystemSettings(context),
                      onRequestNotificationPermission: () async {
                        await context
                            .read<NotificationService>()
                            .requestPermission();
                      },
                      onRequestExactAlarmPermission: () async {
                        await AlarmService.instance
                            .requestExactAlarmPermission();
                      },
                      onRequestFullScreenIntentPermission: () async {
                        await AlarmService.instance
                            .requestFullScreenIntentPermission();
                      },
                    );
                  },
                ),
                if (locationReminderProvider != null) ...[
                  const SizedBox(height: DesignTokens.spaceSm),
                  _TodoLocationReminderCard(
                    reminders: linkedLocationReminders,
                    enabled: canEdit,
                    onAdd: canEdit
                        ? () => _addLinkedLocationReminder(
                            context,
                            locationReminderProvider,
                          )
                        : null,
                    onRemove: canEdit
                        ? (id) => locationReminderProvider.remove(id)
                        : null,
                  ),
                ],

                // ---- 目标时长 ------------------------------------------------
                const SizedBox(height: DesignTokens.spaceLg),
                _TimeTargetEditor(
                  controller: _timeTargetCtrl,
                  minutes: _todo.timeTargetSeconds == null
                      ? null
                      : (_todo.timeTargetSeconds! ~/ 60),
                  enabled: canEdit,
                  onPreset: _applyTimeTargetMinutes,
                  onChanged: (s) =>
                      _applyTimeTargetMinutes(int.tryParse(s.trim())),
                  onClear: () => _applyTimeTargetMinutes(null),
                ),

                // ---- 标签 ----------------------------------------------------
                const SizedBox(height: DesignTokens.spaceLg),
                _SectionLabel(text: TodoDetailUiCopy.tagsSection),
                const SizedBox(height: DesignTokens.spaceXs),
                _TagsEditor(
                  tags: _todo.tags,
                  controller: _tagCtrl,
                  enabled: canEdit,
                  onAdd: _addTag,
                  onRemove: _removeTag,
                ),

                // ---- 子任务 --------------------------------------------------
                const SizedBox(height: DesignTokens.spaceXxl),
                Row(
                  children: [
                    Text(
                      TodoDetailUiCopy.subtasksSection,
                      style: const TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: DesignTokens.fontSizeMd,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_todo.subtasks.where((s) => s.isCompleted).length}/${_todo.subtasks.length}',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subtaskCtrl,
                        enabled: canEdit && !_subtaskAdding,
                        decoration: InputDecoration(
                          labelText: TodoDetailUiCopy.addSubtaskLabel,
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          _addSubtask();
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: canEdit && !_subtaskAdding
                          ? _addSubtask
                          : null,
                      icon: _subtaskAdding
                          ? SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            )
                          : Icon(Icons.add_circle, color: cs.primary),
                    ),
                  ],
                ),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // ignore: deprecated_member_use
                  onReorder: (oldI, newI) {
                    if (!canEdit || !_isCurrentAccount) return;
                    if (newI > oldI) newI -= 1;
                    final ids = _todo.subtasks.map((e) => e.id).toList();
                    final id = ids.removeAt(oldI);
                    ids.insert(newI, id);
                    context.read<TodoProvider>().reorderSubtasks(
                      widget.todoId,
                      ids,
                      expectedAccountDataGeneration: _originAccountGeneration,
                    );
                  },
                  children: [
                    for (final s in _todo.subtasks)
                      Builder(
                        key: ValueKey('subtask-${s.id}'),
                        builder: (context) {
                          final busy = _busySubtaskIds.contains(s.id);
                          return ListTile(
                            dense: true,
                            leading: Checkbox(
                              value: s.isCompleted,
                              onChanged: canEdit && !busy
                                  ? (_) {
                                      _toggleSubtask(s.id);
                                    }
                                  : null,
                            ),
                            title: Text(
                              s.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeBase,
                                decoration: s.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            trailing: IconButton(
                              icon: busy
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.close, size: 16),
                              onPressed: canEdit && !busy
                                  ? () {
                                      _deleteSubtask(s.id);
                                    }
                                  : null,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
        return wrapWithBackground(detailRoute);
      },
    );
  }

  Workspace? _workspaceFor(ShareProvider? provider, String workspaceId) {
    if (provider == null || workspaceId.isEmpty || workspaceId == 'private') {
      return null;
    }
    for (final workspace in provider.workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return null;
  }

  Future<void> _addLinkedLocationReminder(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    if (!_isCurrentAccount) return;
    final titleCtrl = TextEditingController(text: _todo.title);
    final noteCtrl = TextEditingController(text: _todo.notes);
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final radiusCtrl = TextEditingController(text: '200');
    var trigger = LocationTrigger.enter;
    var oneShot = true;

    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [titleCtrl, noteCtrl, latCtrl, lngCtrl, radiusCtrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) {
            final media = MediaQuery.of(context);
            final horizontalInset = media.size.width < 360 ? 12.0 : 20.0;
            final availableWidth = media.size.width - horizontalInset * 2;
            final dialogMaxWidth = availableWidth.isFinite
                ? availableWidth.clamp(0.0, 420.0).toDouble()
                : 420.0;
            final contentWidth = dialogMaxWidth - 48.0;

            final textDirection = Directionality.of(context);
            final locale = Localizations.maybeLocaleOf(context);

            final labelPainter = TextPainter(
              text: TextSpan(
                text: TodoDetailUiCopy.triggerDirectionLabel,
                style: DefaultTextStyle.of(context).style,
              ),
              textDirection: textDirection,
              textScaler: media.textScaler,
              locale: locale,
              maxLines: 1,
            )..layout();
            final labelWidth = labelPainter.width;
            labelPainter.dispose();

            final arrivePainter = TextPainter(
              text: TextSpan(
                text: TodoDetailUiCopy.arriveTrigger,
                style:
                    Theme.of(context).textTheme.labelLarge ??
                    DefaultTextStyle.of(context).style,
              ),
              textDirection: textDirection,
              textScaler: media.textScaler,
              locale: locale,
              maxLines: 1,
            )..layout();
            final arriveChipWidth = arrivePainter.width + 36.0;
            arrivePainter.dispose();

            final leavePainter = TextPainter(
              text: TextSpan(
                text: TodoDetailUiCopy.leaveTrigger,
                style:
                    Theme.of(context).textTheme.labelLarge ??
                    DefaultTextStyle.of(context).style,
              ),
              textDirection: textDirection,
              textScaler: media.textScaler,
              locale: locale,
              maxLines: 1,
            )..layout();
            final leaveChipWidth = leavePainter.width + 36.0;
            leavePainter.dispose();

            final chipsWidth = arriveChipWidth + leaveChipWidth + 8.0;
            const double minSpacerWidth = 16.0;
            final fitsInline =
                labelWidth + chipsWidth + minSpacerWidth <= contentWidth;

            final chipWrap = Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text(TodoDetailUiCopy.arriveTrigger),
                  selected: trigger == LocationTrigger.enter,
                  onSelected: (_) =>
                      setSt(() => trigger = LocationTrigger.enter),
                ),
                ChoiceChip(
                  label: Text(TodoDetailUiCopy.leaveTrigger),
                  selected: trigger == LocationTrigger.leave,
                  onSelected: (_) =>
                      setSt(() => trigger = LocationTrigger.leave),
                ),
              ],
            );

            final triggerControl = fitsInline
                ? Row(
                    children: [
                      Text(TodoDetailUiCopy.triggerDirectionLabel),
                      const Spacer(),
                      chipWrap,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(TodoDetailUiCopy.triggerDirectionLabel),
                      const SizedBox(height: 4),
                      chipWrap,
                    ],
                  );

            return AppDialog(
              title: Text(
                TodoDetailUiCopy.addLocationReminderDialogTitle,
              ), // title: const Text('添加位置提醒')
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: TodoDetailUiCopy.locationReminderTitleLabel,
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: TodoDetailUiCopy.locationReminderNotesLabel,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latCtrl,
                            decoration: InputDecoration(
                              labelText: TodoDetailUiCopy.latitudeLabel,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: lngCtrl,
                            decoration: InputDecoration(
                              labelText: TodoDetailUiCopy.longitudeLabel,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: radiusCtrl,
                      decoration: InputDecoration(
                        labelText: TodoDetailUiCopy.radiusLabel,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    triggerControl,
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: oneShot,
                      onChanged: (value) => setSt(() => oneShot = value),
                      title: Text(TodoDetailUiCopy.autoCloseAfterTrigger),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (ctx.mounted && ModalRoute.of(ctx)?.isCurrent == true) {
                      Navigator.pop(ctx, false);
                    }
                  },
                  child: Text(TodoDetailUiCopy.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    if (ctx.mounted &&
                        ModalRoute.of(ctx)?.isCurrent == true &&
                        _isCurrentAccount) {
                      Navigator.pop(ctx, true);
                    }
                  },
                  child: Text(TodoDetailUiCopy.save),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (ok != true ||
        !context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }

    final title = titleCtrl.text.trim();
    final note = noteCtrl.text.trim();
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    final radius = double.tryParse(radiusCtrl.text.trim()) ?? 200;

    if (title.isEmpty || lat == null || lng == null) {
      if (!context.mounted ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _originAccountGeneration,
          )) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(TodoDetailUiCopy.invalidLocationCoordinates),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await provider.add(
      LocationReminder(
        title: title,
        note: note,
        latitude: lat,
        longitude: lng,
        radiusMeters: radius.clamp(50, 10000).toDouble(),
        trigger: trigger,
        oneShot: oneShot,
        linkedType: 'todo',
        linkedId: _todo.id,
      ),
    );
    if (!context.mounted ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          _originAccountGeneration,
        )) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) => Text(
            TodoDetailUiCopy.locationReminderAdded,
          ), // content: Text('已添加任务位置提醒')
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<bool> preflightTodoReminderSave(
  BuildContext context, {
  required TodoItem todo,
  NotificationService? notificationService,
  String? issueTitle,
  String Function()? issueTitleBuilder,
  NotificationIssueTitle? issueTitleCode,
  int? accountGeneration,
}) async {
  bool isAborted() =>
      !context.mounted ||
      (accountGeneration != null &&
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          ));

  String renderIssueTitle() =>
      issueTitleBuilder?.call() ??
      issueTitle ??
      TodoDetailUiCopy.reminderRegisterFailedIssueTitle;
  final result = preflightTodoReminderPlan(todo);
  if (!result.hasEnabledPlan) return true;

  final messenger = ScaffoldMessenger.of(context);
  final blocking = result.blockingIssue;
  if (blocking != null) {
    messenger.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) =>
              Text('${blocking.title}：${blocking.message}'),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
    return false;
  }

  final usesPush = result.kinds.contains(ReminderKind.push);
  final usesPopup = result.kinds.contains(ReminderKind.popup);
  final usesAlarm = result.kinds.contains(ReminderKind.alarm);
  final notif = notificationService ?? context.read<NotificationService?>();
  if ((usesPush || usesPopup) && notif != null) {
    notif.clearScheduleIssue();
    final ready = await notif
        .ensureReadyForReminder(
          scheduledTime: result.firstScheduledTime,
          issueTitle: renderIssueTitle(),
          issueTitleCode: issueTitleCode,
          relatedId: todo.id,
        )
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (isAborted()) return false;
    if (!ready) {
      final issue = notif.lastScheduleIssue;
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) => Text(
              issue == null
                  ? TodoDetailUiCopy.reminderPreflightUnregistered(
                      renderIssueTitle(),
                    )
                  : '${issue.renderTitle()}：${issue.renderMessage()}',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  if (usesAlarm && !usesPush && !usesPopup) {
    final notificationGranted = await LocalNotifications.instance
        .ensurePermission()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (isAborted()) return false;
    if (!notificationGranted) {
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) => Text(
              TodoDetailUiCopy.alarmPermissionDenied,
            ), // 闹钟提醒注册失败：系统通知权限未开启
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  final warnings = <String Function()>[];

  if (usesPush || usesPopup) {
    final channelIds = await LocalNotifications.instance
        .notificationChannelIds()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (isAborted()) return false;
    if (channelIds != null &&
        channelIds.isNotEmpty &&
        !channelIds.contains(NotificationService.channelId)) {
      warnings.add(() => TodoDetailUiCopy.normalChannelNotReadyWarning);
    }
  }

  if (usesAlarm) {
    try {
      await AlarmService.instance.init().timeout(const Duration(seconds: 5));
    } catch (e, st) {
      debugPrint('[TodoDetail] alarm reminder init failed: $e\n$st');
      if (isAborted()) return false;
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) => Text(TodoDetailUiCopy.alarmInitFailed),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }

    final alarmChannelIds = await AlarmService.instance
        .notificationChannelIds()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (isAborted()) return false;
    if (alarmChannelIds != null &&
        alarmChannelIds.isNotEmpty &&
        !alarmChannelIds.contains(AlarmService.channelId)) {
      warnings.add(() => TodoDetailUiCopy.alarmChannelNotReadyWarning);
    }
    // 主动申请精准闹钟 / 全屏 intent 权限，而不只是检查后给软提示。
    // 否则首次保存的闹钟提醒会静默降级，用户必须先点一次“测试强提醒”
    // 才会触发权限申请、之后的闹钟才正常——这正是“到点没提醒”的成因。
    final exactGranted =
        (await AlarmService.instance.hasExactAlarmPermission().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        )) ||
        (await AlarmService.instance.requestExactAlarmPermission().timeout(
          const Duration(seconds: 8),
          onTimeout: () => false,
        ));
    if (isAborted()) return false;
    if (!exactGranted) {
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(TodoDetailUiCopy.exactAlarmDenied), // 闹钟提醒注册失败：精准闹钟权限未开启
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
    final fullScreenGranted =
        (await AlarmService.instance.hasFullScreenIntentPermission().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        )) ||
        (await AlarmService.instance
            .requestFullScreenIntentPermission()
            .timeout(const Duration(seconds: 8), onTimeout: () => false));
    if (isAborted()) return false;
    if (!fullScreenGranted) {
      messenger.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) => Text(
              TodoDetailUiCopy.fullScreenIntentDenied,
            ), // 闹钟提醒注册失败：全屏提醒权限未开启
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  if (warnings.isNotEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) => Text(
            TodoDetailUiCopy.reminderWarnings(
              renderIssueTitle(),
              warnings.map((render) => render()).toList(),
            ),
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
  return true;
}

Future<void> _openSystemSettings(BuildContext context) async {
  final opened = await openAppSettings();
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) =>
              Text(TodoDetailUiCopy.unableToOpenSettings),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 下面是 TodoDetailScreen 拆出来的私有子组件。
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: DesignTokens.fontSizeSm,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
        fontWeight: DesignTokens.fontWeightRegular,
      ),
    );
  }
}

class _TodoLocationReminderCard extends StatelessWidget {
  final List<LocationReminder> reminders;
  final bool enabled;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onRemove;

  const _TodoLocationReminderCard({
    required this.reminders,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TodoDetailUiCopy.locationReminderTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                label: Text(TodoDetailUiCopy.add),
              ),
            ],
          ),
          if (reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Text(
                TodoDetailUiCopy.locationReminderSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...reminders.map((reminder) {
              final trigger = reminder.trigger == LocationTrigger.enter
                  ? TodoDetailUiCopy.arriveTrigger
                  : TodoDetailUiCopy.leaveTrigger;
              return Padding(
                padding: const EdgeInsets.only(left: 28, top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${reminder.title} · $trigger · '
                        '${reminder.radiusMeters.toStringAsFixed(0)}m',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: TodoDetailUiCopy.deleteLocationReminderTooltip,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: enabled
                          ? () => onRemove?.call(reminder.id)
                          : null,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _TodoMarkdownDescriptionEditor extends StatelessWidget {
  final TextEditingController controller;
  final bool preview;
  final bool enabled;
  final ValueChanged<bool> onPreviewChanged;
  final ValueChanged<String> onChanged;
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onCode;
  final VoidCallback onLink;

  const _TodoMarkdownDescriptionEditor({
    required this.controller,
    required this.preview,
    required this.enabled,
    required this.onPreviewChanged,
    required this.onChanged,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBullet,
    required this.onChecklist,
    required this.onCode,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: _SectionLabel(
                    text: TodoDetailUiCopy.descriptionSection,
                  ),
                ),
                IconButton(
                  tooltip: preview
                      ? TodoDetailUiCopy.editDescriptionTooltip
                      : TodoDetailUiCopy.previewDescriptionTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onPreviewChanged(!preview),
                  icon: Icon(
                    preview ? Icons.edit_outlined : Icons.visibility_outlined,
                  ),
                ),
              ],
            ),
          ),
          if (!preview)
            _TodoMarkdownToolbar(
              enabled: enabled,
              onHeading: onHeading,
              onBold: onBold,
              onItalic: onItalic,
              onQuote: onQuote,
              onBullet: onBullet,
              onChecklist: onChecklist,
              onCode: onCode,
              onLink: onLink,
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: preview
                ? _TodoMarkdownPreview(
                    key: const ValueKey('todo-description-preview'),
                    content: controller.text,
                  )
                : Padding(
                    key: const ValueKey('todo-description-editor'),
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      minLines: 4,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: TodoDetailUiCopy.markdownHint,
                        border: InputBorder.none,
                      ),
                      onChanged: onChanged,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TodoMarkdownToolbar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onCode;
  final VoidCallback onLink;

  const _TodoMarkdownToolbar({
    required this.enabled,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBullet,
    required this.onChecklist,
    required this.onCode,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.48)),
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.48)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _TodoMarkdownToolButton(
              icon: Icons.title,
              tooltip: TodoDetailUiCopy.markdownHeading, // tooltip: '标题'
              enabled: enabled,
              onPressed: onHeading,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_bold,
              tooltip: TodoDetailUiCopy.markdownBold, // tooltip: '加粗'
              enabled: enabled,
              onPressed: onBold,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_italic,
              tooltip: TodoDetailUiCopy.markdownItalic, // tooltip: '斜体'
              enabled: enabled,
              onPressed: onItalic,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_quote,
              tooltip: TodoDetailUiCopy.markdownQuote, // tooltip: '引用'
              enabled: enabled,
              onPressed: onQuote,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_list_bulleted,
              tooltip: TodoDetailUiCopy.markdownBullet, // tooltip: '列表'
              enabled: enabled,
              onPressed: onBullet,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.checklist,
              tooltip: TodoDetailUiCopy.markdownChecklist, // tooltip: '清单'
              enabled: enabled,
              onPressed: onChecklist,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.code,
              tooltip: TodoDetailUiCopy.markdownCode, // tooltip: '代码'
              enabled: enabled,
              onPressed: onCode,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.link,
              tooltip: TodoDetailUiCopy.markdownLink, // tooltip: '链接'
              enabled: enabled,
              onPressed: onLink,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoMarkdownToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _TodoMarkdownToolButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
    );
  }
}

class _TodoMarkdownPreview extends StatelessWidget {
  final String content;

  const _TodoMarkdownPreview({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocks = content.trim().isEmpty
        ? const <NoteBlock>[]
        : NoteBlock.fromMarkdown(content);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: blocks.isEmpty
          ? Text(
              TodoDetailUiCopy.noDescription, // '暂无描述'
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final block in blocks)
                  _TodoMarkdownPreviewBlock(block: block, colorScheme: cs),
              ],
            ),
    );
  }
}

class _TodoMarkdownPreviewBlock extends StatelessWidget {
  final NoteBlock block;
  final ColorScheme colorScheme;

  const _TodoMarkdownPreviewBlock({
    required this.block,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (block.type == NoteBlockType.heading) {
      final style = block.level <= 1
          ? Theme.of(context).textTheme.titleLarge
          : Theme.of(context).textTheme.titleMedium;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _TodoInlineMarkdownText(
          text: block.text,
          style: style?.copyWith(fontWeight: FontWeight.normal),
        ),
      );
    }
    if (block.type == NoteBlockType.quote) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
          color: colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: _TodoInlineMarkdownText(
          text: block.text,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.checklist) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              block.checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: block.checked
                  ? DesignTokens.defaultSuccess
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: _TodoInlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.bullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.circle,
                size: 6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _TodoInlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.code) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          block.text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      );
    }
    if (block.type == NoteBlockType.divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(color: colorScheme.outlineVariant),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _TodoInlineMarkdownText(text: block.text),
    );
  }
}

class _TodoInlineMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _TodoInlineMarkdownText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = style ?? const TextStyle(fontSize: 15, height: 1.5);
    return Text.rich(
      TextSpan(style: base, children: _parseInline(text, base, cs)),
    );
  }

  List<InlineSpan> _parseInline(
    String source,
    TextStyle base,
    ColorScheme cs,
  ) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final bold = source.indexOf('**', i);
      final italic = source.indexOf('*', i);
      final code = source.indexOf('`', i);
      final link = source.indexOf('[', i);
      final candidates = <int>[
        bold,
        italic,
        code,
        link,
      ].where((pos) => pos >= 0).toList()..sort();
      final next = candidates.isEmpty ? -1 : candidates.first;
      if (next < 0) {
        spans.add(TextSpan(text: source.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: source.substring(i, next)));
        i = next;
      }
      if (source.startsWith('**', i)) {
        final end = source.indexOf('**', i + 2);
        if (end > i + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 2, end),
              style: base.copyWith(fontWeight: FontWeight.normal),
            ),
          );
          i = end + 2;
          continue;
        }
      }
      if (source.startsWith('`', i)) {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(
                fontFamily: 'monospace',
                backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      if (source.startsWith('[', i)) {
        final closeLabel = source.indexOf('](', i + 1);
        final closeUrl = closeLabel < 0 ? -1 : source.indexOf(')', closeLabel);
        if (closeLabel > i + 1 && closeUrl > closeLabel + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, closeLabel),
              style: base.copyWith(
                color: cs.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          );
          i = closeUrl + 1;
          continue;
        }
      }
      if (source.startsWith('*', i)) {
        final end = source.indexOf('*', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      spans.add(TextSpan(text: source[i]));
      i++;
    }
    return spans;
  }
}

class _AssignmentEditor extends StatelessWidget {
  final Workspace? workspace;
  final String? assigneeId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _AssignmentEditor({
    required this.workspace,
    required this.assigneeId,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final workspace = this.workspace;
    if (workspace == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_outline),
        title: Text(TodoDetailUiCopy.assigneeLabel),
        subtitle: Text(TodoDetailUiCopy.assigneePrivateSubtitle),
      );
    }
    final members = workspace.members;
    final selected = members.any((member) => member.userId == assigneeId)
        ? assigneeId!
        : '';
    return AppDropdownField<String>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: TodoDetailUiCopy.assigneeLabel, // labelText: '负责人'
        helperText: TodoDetailUiCopy.sharedSpaceHelper(workspace.name),
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.assignment_ind_outlined),
      ),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(TodoDetailUiCopy.unassigned),
        ),
        for (final member in members)
          DropdownMenuItem<String>(
            value: member.userId,
            child: Text(
              member.username.isEmpty ? member.userId : member.username,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      enabled: enabled,
      onChanged: (value) =>
          onChanged(value == null || value.isEmpty ? null : value),
    );
  }
}

class _TaskCommentsPanel extends StatefulWidget {
  final Workspace workspace;
  final String todoId;
  final List<WorkspaceComment> comments;
  final int accountGeneration;
  final bool enabled;

  const _TaskCommentsPanel({
    required this.workspace,
    required this.todoId,
    required this.comments,
    required this.accountGeneration,
    this.enabled = true,
  });

  @override
  State<_TaskCommentsPanel> createState() => _TaskCommentsPanelState();
}

class _TaskCommentsPanelState extends State<_TaskCommentsPanel> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  int _sendSeq = 0;

  bool get _isCurrentAccount =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        widget.accountGeneration,
      );

  @override
  void initState() {
    super.initState();
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataGenerationChanged,
    );
  }

  void _onAccountDataGenerationChanged() {
    if (!mounted) return;
    _sendSeq++;
    if (_sending) {
      _sending = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataGenerationChanged,
    );
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canInteract = widget.enabled && _isCurrentAccount && !_sending;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(TodoDetailUiCopy.taskCommentsTitle)),
              Text(
                '${widget.comments.length}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            enabled: canInteract,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText: TodoDetailUiCopy.commentHint,
              suffixIcon: IconButton(
                tooltip: TodoDetailUiCopy.sendCommentTooltip,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                onPressed: canInteract ? _send : null,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 8),
          if (widget.comments.isEmpty)
            Text(
              TodoDetailUiCopy.noComments,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else
            ...widget.comments
                .take(4)
                .map(
                  (comment) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 13,
                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                      child: Text(
                        comment.authorName.isEmpty
                            ? '?'
                            : comment.authorName.substring(0, 1),
                        style: TextStyle(fontSize: 10, color: cs.primary),
                      ),
                    ),
                    title: Text(
                      comment.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${comment.authorName.isEmpty ? comment.authorUserId : comment.authorName} · ${_formatCommentTime(comment.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending || !widget.enabled || !_isCurrentAccount) {
      return;
    }
    final seq = ++_sendSeq;
    setState(() => _sending = true);
    try {
      await context.read<ShareProvider>().createComment(
        widget.workspace.id,
        text,
        targetId: widget.todoId,
      );
      if (!mounted || !_isCurrentAccount || _sendSeq != seq) {
        return;
      }
      if (!mounted) return;
      _ctrl.clear();
    } catch (e) {
      if (!mounted || !_isCurrentAccount || _sendSeq != seq) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) => Text(
              TodoDetailUiCopy.commentSendFailed(_shareError(e)),
            ), // 评论发送失败: ${_shareError(e)}
          ),
        ),
      );
    } finally {
      if (mounted && _sendSeq == seq && _sending) {
        setState(() => _sending = false);
      }
    }
  }
}

String _shareError(Object error) => userVisibleApiError(
  error,
  fallbackMessage: TodoDetailUiCopy.shareServiceUnavailableFallback,
);

String _formatCommentTime(DateTime value) {
  return I18nDateFormat.shortDateTime(value);
}

/// 优先级 Chip 行。
///
/// 对齐 Requirement 2.1："列表项展示优先级色标"。编辑面板用 ChoiceChip 做分段选择。
class _PriorityChipRow extends StatelessWidget {
  final TodoPriority selected;
  final ValueChanged<TodoPriority> onSelected;
  final bool enabled;

  const _PriorityChipRow({
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXs,
      children: [
        for (final p in TodoPriority.values)
          ChoiceChip(
            avatar: p == TodoPriority.none
                ? null
                : _PriorityDot(priority: p, size: 10),
            label: Text(p.label),
            selected: selected == p,
            onSelected: enabled ? (_) => onSelected(p) : null,
          ),
      ],
    );
  }
}

/// 目标时长编辑器：分钟输入 + 15/25/45/60 预设。
class _TimeTargetEditor extends StatelessWidget {
  final TextEditingController controller;
  final int? minutes;
  final ValueChanged<int?> onPreset;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool enabled;

  const _TimeTargetEditor({
    required this.controller,
    required this.minutes,
    required this.onPreset,
    required this.onChanged,
    required this.onClear,
    this.enabled = true,
  });

  static const List<int> _presets = [15, 25, 45, 60];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: TodoDetailUiCopy.targetDurationSection),
        const SizedBox(height: DesignTokens.spaceXs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: TodoDetailUiCopy.minutesSuffix,
                  suffixText: TodoDetailUiCopy.minutesSuffix,
                ),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              tooltip: TodoDetailUiCopy.clear,
              onPressed: enabled ? onClear : null,
              icon: const Icon(Icons.clear),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Text(
          TodoDetailUiCopy.targetDurationHint,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceXs,
          runSpacing: DesignTokens.spaceXs,
          children: [
            for (final m in _presets)
              ChoiceChip(
                label: Text(TodoDetailUiCopy.presetMinutes(m)),
                selected: minutes == m,
                onSelected: enabled ? (_) => onPreset(m) : null,
              ),
          ],
        ),
      ],
    );
  }
}

/// 标签编辑器：已有标签 + 新标签输入。
class _TodoAttachmentPanel extends StatelessWidget {
  final List<NoteAttachment> attachments;
  final bool enabled;
  final VoidCallback onPickFile;
  final VoidCallback onAddManual;
  final ValueChanged<NoteAttachment> onRemove;

  const _TodoAttachmentPanel({
    required this.attachments,
    required this.enabled,
    required this.onPickFile,
    required this.onAddManual,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = attachments.where((attachment) => attachment.isImage);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final headingStyle = DefaultTextStyle.of(
                context,
              ).style.merge(const TextStyle(fontWeight: FontWeight.normal));
              final textPainter = TextPainter(
                text: TextSpan(
                  text: TodoDetailUiCopy.attachmentsSection,
                  style: headingStyle,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                locale: Localizations.maybeLocaleOf(context),
                maxLines: 1,
              )..layout();
              final headingTextWidth = textPainter.width;
              textPainter.dispose();

              const double headingLeadingWidth = 18.0 + 6.0;
              final double headingWidth =
                  headingLeadingWidth + headingTextWidth;

              const double actionButtonWidth = 44.0;
              const double actionsWidth = actionButtonWidth * 2;

              final fitsInline =
                  !constraints.hasBoundedWidth ||
                  (headingWidth + actionsWidth <= constraints.maxWidth);

              final pickFileButton = IconButton(
                tooltip: TodoDetailUiCopy.pickFileTooltip,
                visualDensity: VisualDensity.standard,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: enabled ? onPickFile : null,
                icon: const Icon(Icons.upload_file_outlined),
              );
              final addLinkButton = IconButton(
                tooltip: TodoDetailUiCopy.addLinkTooltip,
                visualDensity: VisualDensity.standard,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: enabled ? onAddManual : null,
                icon: const Icon(Icons.add_link),
              );

              if (fitsInline) {
                return Row(
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        TodoDetailUiCopy.attachmentsSection,
                        style: const TextStyle(fontWeight: FontWeight.normal),
                      ),
                    ),
                    pickFileButton,
                    addLinkButton,
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.attach_file, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          TodoDetailUiCopy.attachmentsSection,
                          style: const TextStyle(fontWeight: FontWeight.normal),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [pickFileButton, addLinkButton],
                  ),
                ],
              );
            },
          ),
          if (attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spaceXs),
              child: Text(
                TodoDetailUiCopy.noAttachments,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children: [
                for (final attachment in attachments)
                  _TodoAttachmentChip(
                    attachment: attachment,
                    onDeleted: enabled ? () => onRemove(attachment) : null,
                  ),
              ],
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spaceMd),
            for (final image in images)
              _TodoAttachmentImagePreview(attachment: image),
          ],
        ],
      ),
    );
  }
}

class _TodoAttachmentChip extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback? onDeleted;

  const _TodoAttachmentChip({required this.attachment, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.uri);
    final target = _resolveOpenTarget(uri);
    return InputChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        _isWebUri(uri) ? Icons.link : Icons.insert_drive_file_outlined,
      ),
      label: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onDeleted,
      onPressed: target == null
          ? null
          : () async {
              await launchUrl(target, mode: LaunchMode.externalApplication);
            },
    );
  }

  Uri? _resolveOpenTarget(Uri? uri) {
    if (uri == null) return null;
    if (_isWebUri(uri) || (kIsWeb && uri.scheme == 'blob')) return uri;
    if (kIsWeb) return null;
    if (uri.scheme == 'file' || uri.scheme == 'content') return uri;
    if (uri.scheme.isEmpty) {
      return Uri.file(attachment.uri, windows: false);
    }
    return null;
  }

  bool _isWebUri(Uri? uri) => uri?.scheme == 'http' || uri?.scheme == 'https';
}

class _TodoAttachmentImagePreview extends StatelessWidget {
  final NoteAttachment attachment;

  const _TodoAttachmentImagePreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(attachment.uri);
    final dataBytes = ImageDecodeCache.decodeBase64Image(attachment.uri);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final maxLogicalWidth = MediaQuery.sizeOf(context).width;
    final cacheWidth = ImageDecodeCache.boundedCachePixels(maxLogicalWidth, dpr);
    final cacheHeight = ImageDecodeCache.boundedCachePixels(
      maxLogicalWidth * 9 / 16,
      dpr,
    );
    Widget image;
    if (dataBytes != null) {
      image = Image.memory(
        dataBytes,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else if (uri != null &&
        (uri.scheme == 'http' ||
            uri.scheme == 'https' ||
            (kIsWeb && uri.scheme == 'blob'))) {
      image = Image.network(
        attachment.uri,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else if (!kIsWeb && uri != null && uri.scheme == 'file') {
      image = Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else if (!kIsWeb && attachment.uri.startsWith('/')) {
      image = Image.file(
        File(attachment.uri),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else {
      image = _fallback(cs);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: image,
          ),
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme cs) => Center(
    child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
  );
}

/// 标签编辑器：已有标签 + 新标签输入。
class _TagsEditor extends StatelessWidget {
  final List<String> tags;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final bool enabled;

  const _TagsEditor({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final hint = TextPainter(
          text: TextSpan(
            text: TodoDetailUiCopy.newTagHint,
            style: (theme.textTheme.titleMedium ?? const TextStyle()).merge(
              theme.inputDecorationTheme.hintStyle,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        )..layout();
        final padding = theme.inputDecorationTheme.contentPadding?.resolve(
          Directionality.of(context),
        );
        final naturalWidth =
            hint.width.ceilToDouble() + (padding?.horizontal ?? 24) + 2;
        hint.dispose();
        final width = naturalWidth
            .clamp(140.0, double.infinity)
            .clamp(0.0, constraints.maxWidth);
        return Wrap(
          spacing: DesignTokens.spaceXs,
          runSpacing: DesignTokens.spaceXs,
          children: [
            ...tags.map(
              (t) => ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Chip(
                  label: Text(
                    '#$t',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onDeleted: enabled ? () => onRemove(t) : null,
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: TextField(
                controller: controller,
                enabled: enabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: TodoDetailUiCopy.newTagHint,
                  hintMaxLines: 2,
                ),
                onSubmitted: enabled ? onAdd : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 共享小工具：优先级色点 / 颜色映射 / 时间格式化
// ---------------------------------------------------------------------------

/// 优先级色标（圆点）。
class _PriorityDot extends StatelessWidget {
  final TodoPriority priority;
  final double size;

  const _PriorityDot({required this.priority, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: priorityColor(priority),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 由 TodoPriority 映射到 DesignTokens 中的语义色。
///
/// 供 `_PriorityChipRow` 与 Todo 列表项共享。
Color priorityColor(TodoPriority p) {
  switch (p) {
    case TodoPriority.urgent:
      return DesignTokens.defaultError; // 区分于 high
    case TodoPriority.high:
      return DesignTokens.priorityHigh;
    case TodoPriority.medium:
      return DesignTokens.priorityMedium;
    case TodoPriority.low:
      return DesignTokens.priorityLow;
    case TodoPriority.none:
      return DesignTokens.priorityNone;
  }
}
