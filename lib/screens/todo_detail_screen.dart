import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../models/goal.dart' show ReminderConfig, ReminderKind;
import '../models/todo.dart';
import '../providers/todo_provider.dart';
import '../widgets/recurrence_picker.dart';

/// Todo 详情页 / 编辑页。
///
/// Task 9：引入"保存不返回"状态机。
///
/// - `_EditState` 四档：`clean / editing / saving / confirmDiscard`；
/// - AppBar 的 check 按钮**只持久化不 pop**，成功时用 floating snackbar
///   展示"已保存"反馈，失败时保留 `editing` 并弹错误提示；
/// - 返回键在 `editing` 下会弹"放弃修改"对话框；
/// - 用 `PopScope` + `onPopInvoked` 统一拦截路由 pop，`Clean` 状态直接放行。
///
/// 同时保留 Task 7 的视觉对齐：token 化间距 / 圆角、优先级 ChoiceChip、提醒
/// 分段、目标时长模块、标签 / 子任务 / 重复 / 截止日 等模块。
class TodoDetailScreen extends StatefulWidget {
  final String todoId;

  const TodoDetailScreen({super.key, required this.todoId});

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

  /// "保存不返回"状态机当前状态。
  _EditState _state = _EditState.clean;

  /// 基线快照：`_load()` 与成功保存后都会刷新。任何与基线偏离的改动
  /// 都会把状态抬升到 `editing`。用 JSON 化的字符串表示，避免深比较。
  late String _baseline;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      'reminder': t.reminder.toJson(),
      'focusLink': t.focusLink.toJson(),
      'timeTargetSeconds': t.timeTargetSeconds,
      'recurrence': t.recurrence.toJson(),
      'autoToggleByChildren': t.autoToggleByChildren,
    }.toString();
  }

  void _load() {
    final provider = context.read<TodoProvider>();
    final todo = provider.todos.firstWhere((t) => t.id == widget.todoId);
    _todo = todo;
    _titleCtrl.text = todo.title;
    _notesCtrl.text = todo.notes;
    final sec = todo.timeTargetSeconds;
    if (sec != null && sec > 0) {
      _timeTargetCtrl.text = (sec ~/ 60).toString();
    }
    _baseline = _snapshot(_todo);
    _state = _EditState.clean;
  }

  /// 任一可编辑字段变动时调用；根据是否偏离基线切换状态。
  ///
  /// - 若当前已经是 `saving`，保持不动（在途保存不应被抢占）；
  /// - 若当前与基线一致，回到 `clean`；否则升到 `editing`。
  void _markEditing() {
    if (_state == _EditState.saving) return;
    final dirty = _snapshot(_todo) != _baseline;
    final next = dirty ? _EditState.editing : _EditState.clean;
    if (_state != next) {
      setState(() => _state = next);
    }
  }

  /// 保存当前编辑结果。
  ///
  /// - `clean`：不触发任何写入，仅提示"无未保存改动"；
  /// - 其他状态：`_state = saving` → `updateTodo` → 成功回到 `clean`
  ///   并刷新基线、展示 "已保存" inline snackbar；失败回到 `editing`
  ///   并展示错误 snackbar。
  ///
  /// 关键约束（P18）：本方法**绝不调用 `Navigator.pop`**，路由栈顶必须
  /// 在调用前后保持同一路由实例。
  Future<void> _save() async {
    if (_state == _EditState.saving) return;

    // 同步基线检查：用户点了 check 但什么也没改 → 轻量反馈、不打扰。
    if (_state == _EditState.clean) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无未保存改动'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1000),
        ),
      );
      return;
    }

    setState(() => _state = _EditState.saving);

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<TodoProvider>();
    final cs = Theme.of(context).colorScheme;

    try {
      await provider.updateTodo(
        widget.todoId,
        _todo.copyWith(
          title: _titleCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        ),
      );
      if (!mounted) return;

      // 刷新本地 _todo 引用与基线，便于继续编辑。
      _todo = provider.todos.firstWhere(
        (t) => t.id == widget.todoId,
        orElse: () => _todo,
      );
      _baseline = _snapshot(_todo);
      setState(() => _state = _EditState.clean);

      // inline banner：floating + checkmark icon + 1200ms。
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_circle, size: 18, color: Colors.white),
              SizedBox(width: DesignTokens.spaceSm),
              Text('已保存'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = _EditState.editing);
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存失败：$e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.error,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
    if (_state == _EditState.saving) {
      // 正在保存期间不允许离开页面，避免 provider 写入与 pop 竞态。
      return false;
    }
    if (_state != _EditState.editing) return true;

    setState(() => _state = _EditState.confirmDiscard);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: DesignTokens.dialogBorderRadius,
        ),
        contentPadding: DesignTokens.dialogContentPadding,
        actionsPadding: DesignTokens.dialogActionsPadding,
        title: const Text('放弃未保存的修改？'),
        content: const Text('当前修改尚未保存，返回将丢弃这些改动。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (!mounted) return false;

    if (discard == true) {
      setState(() => _state = _EditState.clean);
      return true;
    }
    setState(() => _state = _EditState.editing);
    return false;
  }

  void _addSubtask() {
    if (_subtaskCtrl.text.trim().isEmpty) return;
    context.read<TodoProvider>().addSubtask(
          widget.todoId,
          _subtaskCtrl.text.trim(),
        );
    _subtaskCtrl.clear();
    setState(() {
      _todo = context.read<TodoProvider>().todos.firstWhere(
            (t) => t.id == widget.todoId,
          );
    });
    // 子任务列表由 provider 直接维护，基线也需跟着刷新，避免它们被误判为脏。
    _baseline = _snapshot(_todo);
  }

  void _addTag(String v) {
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
    setState(() {
      _todo = _todo.copyWith(
        tags: _todo.tags.where((x) => x != tag).toList(),
      );
    });
    _markEditing();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _todo.dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      setState(() => _todo = _todo.copyWith(dueDate: picked));
      _markEditing();
    }
  }

  Future<void> _pickRecurrence() async {
    final r = await RecurrencePicker.show(context, initial: _todo.recurrence);
    if (r != null) {
      setState(() => _todo = _todo.copyWith(recurrence: r));
      _markEditing();
    }
  }

  // ---- Priority ----------------------------------------------------------

  void _pickPriority(TodoPriority p) {
    setState(() => _todo = _todo.copyWith(priority: p));
    _markEditing();
  }

  // ---- Reminder ----------------------------------------------------------

  /// 同步新 `reminder` 与旧 `hasReminder / reminderAt` 两套字段。
  ///
  /// 保持向后兼容：旧代码读 `hasReminder` / `reminderAt` 也能得到最新值。
  void _applyReminder(ReminderConfig r) {
    final nowForMirror = DateTime.now();
    DateTime? mirroredAt;
    if (r.enabled && r.hour != null && r.minute != null) {
      final base = _todo.dueDate ?? nowForMirror;
      mirroredAt = DateTime(base.year, base.month, base.day, r.hour!, r.minute!);
    }
    setState(() {
      // ignore: deprecated_member_use_from_same_package
      _todo = _todo.copyWith(
        reminder: r,
        hasReminder: r.enabled,
        reminderAt: mirroredAt,
      );
    });
    _markEditing();
  }

  void _toggleReminderEnabled(bool v) {
    final current = _todo.reminder;
    // 开启时若没有 hour/minute,用"现在+1 小时"作为默认起点
    int? hour = current.hour;
    int? minute = current.minute;
    if (v && (hour == null || minute == null)) {
      final seed = _todo.reminderAt ??
          _todo.dueDate ??
          DateTime.now().add(const Duration(hours: 1));
      hour = seed.hour;
      minute = seed.minute;
    }
    _applyReminder(current.copyWith(
      enabled: v,
      hour: hour,
      minute: minute,
    ));
  }

  Future<void> _pickReminderTime() async {
    final current = _todo.reminder;
    final initial = TimeOfDay(
      hour: current.hour ?? 9,
      minute: current.minute ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    _applyReminder(current.copyWith(
      enabled: true,
      hour: picked.hour,
      minute: picked.minute,
    ));
  }

  // ---- Time target -------------------------------------------------------

  void _applyTimeTargetMinutes(int? minutes) {
    final seconds = (minutes == null || minutes <= 0) ? null : minutes * 60;
    setState(() {
      _todo = _todo.copyWith(timeTargetSeconds: seconds);
      _timeTargetCtrl.text =
          (seconds == null) ? '' : (seconds ~/ 60).toString();
    });
    _markEditing();
  }

  @override
  void dispose() {
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
    _todo = provider.todos.firstWhere(
      (t) => t.id == widget.todoId,
      orElse: () => _todo,
    );
    final cs = Theme.of(context).colorScheme;

    // canPop 反映当前状态机是否允许直接 pop：
    // - clean：没有未保存改动，系统返回键 / AppBar 返回键直接放行；
    // - 其它：拦截，走 `_handleBack` → 弹"放弃修改"对话框的分支。
    final bool canPop = _state == _EditState.clean;
    return PopScope(
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
        appBar: AppBar(
          title: const Text('任务详情'),
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
              tooltip: '保存',
              onPressed: _state == _EditState.saving ? null : _save,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: '任务名称'),
              style: const TextStyle(
                fontSize: DesignTokens.fontSizeLg,
                fontWeight: DesignTokens.fontWeightSemiBold,
              ),
              onChanged: (_) => _markEditing(),
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: '备注'),
              maxLines: 3,
              onChanged: (_) => _markEditing(),
            ),

            // ---- 四象限 --------------------------------------------------
            const SizedBox(height: DesignTokens.spaceLg),
            DropdownButtonFormField<EisenhowerQuadrant>(
              initialValue: _todo.quadrant,
              decoration: const InputDecoration(labelText: '四象限'),
              items: const [
                DropdownMenuItem(
                  value: EisenhowerQuadrant.urgentImportant,
                  child: Text('Q1 重要且紧急'),
                ),
                DropdownMenuItem(
                  value: EisenhowerQuadrant.notUrgentImportant,
                  child: Text('Q2 重要不紧急'),
                ),
                DropdownMenuItem(
                  value: EisenhowerQuadrant.urgentNotImportant,
                  child: Text('Q3 紧急不重要'),
                ),
                DropdownMenuItem(
                  value: EisenhowerQuadrant.notUrgentNotImportant,
                  child: Text('Q4 不重要不紧急'),
                ),
              ],
              onChanged: (v) {
                setState(() => _todo = _todo.copyWith(quadrant: v!));
                _markEditing();
              },
            ),

            // ---- 优先级 --------------------------------------------------
            const SizedBox(height: DesignTokens.spaceLg),
            _SectionLabel(text: '优先级'),
            const SizedBox(height: DesignTokens.spaceXs),
            _PriorityChipRow(
              selected: _todo.priority,
              onSelected: _pickPriority,
            ),

            // ---- 截止日 + 重复 --------------------------------------------
            const SizedBox(height: DesignTokens.spaceLg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('截止日期'),
              subtitle: Text(
                _todo.dueDate == null
                    ? '未设置'
                    : _formatYmd(_todo.dueDate!),
              ),
              trailing: _todo.dueDate == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() => _todo = _todo.copyWith(dueDate: null));
                        _markEditing();
                      },
                    ),
              onTap: _pickDueDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.repeat),
              title: const Text('重复'),
              subtitle: Text(_todo.recurrence.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickRecurrence,
            ),

            // ---- 提醒 ----------------------------------------------------
            const SizedBox(height: DesignTokens.spaceSm),
            _ReminderEditor(
              reminder: _todo.reminder,
              onToggle: _toggleReminderEnabled,
              onPickTime: _pickReminderTime,
              onKindChange: (k) =>
                  _applyReminder(_todo.reminder.copyWith(kind: k)),
              onVibrateChange: (v) =>
                  _applyReminder(_todo.reminder.copyWith(vibrate: v)),
              onFullScreenChange: (v) =>
                  _applyReminder(_todo.reminder.copyWith(fullScreen: v)),
            ),

            // ---- 目标时长 ------------------------------------------------
            const SizedBox(height: DesignTokens.spaceLg),
            _TimeTargetEditor(
              controller: _timeTargetCtrl,
              minutes: _todo.timeTargetSeconds == null
                  ? null
                  : (_todo.timeTargetSeconds! ~/ 60),
              onPreset: _applyTimeTargetMinutes,
              onChanged: (s) =>
                  _applyTimeTargetMinutes(int.tryParse(s.trim())),
              onClear: () => _applyTimeTargetMinutes(null),
            ),

            // ---- 标签 ----------------------------------------------------
            const SizedBox(height: DesignTokens.spaceLg),
            _SectionLabel(text: '标签'),
            const SizedBox(height: DesignTokens.spaceXs),
            _TagsEditor(
              tags: _todo.tags,
              controller: _tagCtrl,
              onAdd: _addTag,
              onRemove: _removeTag,
            ),

            // ---- 子任务 --------------------------------------------------
            const SizedBox(height: DesignTokens.spaceXxl),
            Row(
              children: [
                const Text(
                  '子任务',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightSemiBold,
                    fontSize: DesignTokens.fontSizeMd,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_todo.subtasks.where((s) => s.isCompleted).length}/${_todo.subtasks.length}',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: DesignTokens.fontWeightSemiBold,
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
                    decoration: const InputDecoration(
                      labelText: '新增子任务',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                IconButton(
                  onPressed: _addSubtask,
                  icon: Icon(Icons.add_circle, color: cs.primary),
                ),
              ],
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldI, newI) {
                final ids = _todo.subtasks.map((e) => e.id).toList();
                if (newI > oldI) newI -= 1;
                final id = ids.removeAt(oldI);
                ids.insert(newI, id);
                context
                    .read<TodoProvider>()
                    .reorderSubtasks(widget.todoId, ids);
              },
              children: [
                for (final s in _todo.subtasks)
                  ListTile(
                    key: ValueKey(s.id),
                    dense: true,
                    leading: Checkbox(
                      value: s.isCompleted,
                      onChanged: (_) {
                        provider.toggleSubtask(widget.todoId, s.id);
                        setState(() {});
                      },
                    ),
                    title: Text(
                      s.title,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeBase,
                        decoration: s.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        provider.deleteSubtask(widget.todoId, s.id);
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
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
        fontWeight: DesignTokens.fontWeightMedium,
      ),
    );
  }
}

/// 优先级 Chip 行。
///
/// 对齐 Requirement 2.1："列表项展示优先级色标"。编辑面板用 ChoiceChip 做分段选择。
class _PriorityChipRow extends StatelessWidget {
  final TodoPriority selected;
  final ValueChanged<TodoPriority> onSelected;

  const _PriorityChipRow({
    required this.selected,
    required this.onSelected,
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
            onSelected: (_) => onSelected(p),
          ),
      ],
    );
  }
}

/// 提醒编辑器：总开关 + HH:MM + push/alarm 分段 + 震动 + 全屏（仅 alarm）。
class _ReminderEditor extends StatelessWidget {
  final ReminderConfig reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;
  final ValueChanged<ReminderKind> onKindChange;
  final ValueChanged<bool> onVibrateChange;
  final ValueChanged<bool> onFullScreenChange;

  const _ReminderEditor({
    required this.reminder,
    required this.onToggle,
    required this.onPickTime,
    required this.onKindChange,
    required this.onVibrateChange,
    required this.onFullScreenChange,
  });

  @override
  Widget build(BuildContext context) {
    final timeLabel = _formatHm(reminder.hour, reminder.minute) ?? '选择时间';
    final kindLabel =
        reminder.kind == ReminderKind.alarm ? '闹钟' : '推送';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: reminder.enabled,
          title: const Text('到期提醒'),
          subtitle: Text(
            reminder.enabled ? '$kindLabel · $timeLabel' : '已关闭',
          ),
          onChanged: onToggle,
        ),
        if (reminder.enabled) ...[
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spaceXs),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: DesignTokens.borderRadiusSm,
                    onTap: onPickTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spaceSm,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: DesignTokens.spaceSm),
                          Text(
                            timeLabel,
                            style: const TextStyle(
                              fontSize: DesignTokens.fontSizeMd,
                              fontWeight: DesignTokens.fontWeightSemiBold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceSm),
                SegmentedButton<ReminderKind>(
                  segments: const [
                    ButtonSegment(
                      value: ReminderKind.push,
                      label: Text('推送'),
                      icon: Icon(Icons.notifications),
                    ),
                    ButtonSegment(
                      value: ReminderKind.alarm,
                      label: Text('闹钟'),
                      icon: Icon(Icons.alarm),
                    ),
                  ],
                  selected: {reminder.kind},
                  onSelectionChanged: (s) => onKindChange(s.first),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminder.vibrate,
            title: const Text('震动'),
            onChanged: onVibrateChange,
          ),
          if (reminder.kind == ReminderKind.alarm)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: reminder.fullScreen,
              title: const Text('全屏提醒'),
              subtitle: const Text('到点全屏弹出（需系统权限）'),
              onChanged: onFullScreenChange,
            ),
        ],
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

  const _TimeTargetEditor({
    required this.controller,
    required this.minutes,
    required this.onPreset,
    required this.onChanged,
    required this.onClear,
  });

  static const List<int> _presets = [15, 25, 45, 60];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: '目标时长'),
        const SizedBox(height: DesignTokens.spaceXs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '分钟（0 或空 = 清除）',
                  suffixText: '分钟',
                ),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              tooltip: '清除',
              onPressed: onClear,
              icon: const Icon(Icons.clear),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceXs,
          runSpacing: DesignTokens.spaceXs,
          children: [
            for (final m in _presets)
              ChoiceChip(
                label: Text('$m 分钟'),
                selected: minutes == m,
                onSelected: (_) => onPreset(m),
              ),
          ],
        ),
      ],
    );
  }
}

/// 标签编辑器：已有标签 + 新标签输入。
class _TagsEditor extends StatelessWidget {
  final List<String> tags;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  const _TagsEditor({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXs,
      children: [
        ...tags.map(
          (t) => Chip(
            label: Text('#$t'),
            onDeleted: () => onRemove(t),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '+ 新标签',
            ),
            onSubmitted: onAdd,
          ),
        ),
      ],
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
      return const Color(0xFFD32F2F); // 深红，区分于 high
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

String? _formatHm(int? hour, int? minute) {
  if (hour == null || minute == null) return null;
  final hh = hour.toString().padLeft(2, '0');
  final mm = minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
