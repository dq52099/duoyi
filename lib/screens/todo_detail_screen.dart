import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/todo_provider.dart';
import '../widgets/recurrence_picker.dart';

class TodoDetailScreen extends StatefulWidget {
  final String todoId;

  const TodoDetailScreen({super.key, required this.todoId});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _subtaskCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  late TodoItem _todo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final provider = context.read<TodoProvider>();
    final todo = provider.todos.firstWhere((t) => t.id == widget.todoId);
    _todo = todo;
    _titleCtrl.text = todo.title;
    _notesCtrl.text = todo.notes;
  }

  void _save() {
    context.read<TodoProvider>().updateTodo(
          widget.todoId,
          _todo.copyWith(
            title: _titleCtrl.text.trim(),
            notes: _notesCtrl.text.trim(),
          ),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
    );
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
  }

  void _addTag() {
    final v = _tagCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _todo = _todo.copyWith(tags: [..._todo.tags, v]);
      _tagCtrl.clear();
    });
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
    }
  }

  Future<void> _pickRecurrence() async {
    final r = await RecurrencePicker.show(context, initial: _todo.recurrence);
    if (r != null) setState(() => _todo = _todo.copyWith(recurrence: r));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _subtaskCtrl.dispose();
    _tagCtrl.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务详情'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: '任务名称'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: '备注'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
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
            onChanged: (v) =>
                setState(() => _todo = _todo.copyWith(quadrant: v!)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<TodoPriority>(
            initialValue: _todo.priority,
            decoration: const InputDecoration(labelText: '优先级'),
            items: TodoPriority.values
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.label),
                    ))
                .toList(),
            onChanged: (v) => setState(
                () => _todo = _todo.copyWith(priority: v ?? TodoPriority.none)),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('截止日期'),
            subtitle: Text(
              _todo.dueDate == null
                  ? '未设置'
                  : '${_todo.dueDate!.year}-${_todo.dueDate!.month.toString().padLeft(2, '0')}-${_todo.dueDate!.day.toString().padLeft(2, '0')}',
            ),
            trailing: _todo.dueDate == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        setState(() => _todo = _todo.copyWith(dueDate: null)),
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _todo.hasReminder,
            title: const Text('到期提醒'),
            subtitle: Text(_todo.reminderAt != null
                ? '${_todo.reminderAt!.hour.toString().padLeft(2, '0')}:${_todo.reminderAt!.minute.toString().padLeft(2, '0')} 提醒'
                : '使用截止日期时间'),
            onChanged: (v) {
              setState(() {
                _todo = _todo.copyWith(hasReminder: v);
                if (v && _todo.dueDate != null && _todo.reminderAt == null) {
                  _todo = _todo.copyWith(reminderAt: _todo.dueDate);
                }
              });
            },
          ),
          if (_todo.hasReminder)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm),
              title: const Text('提醒时间'),
              subtitle: Text(
                _todo.reminderAt == null
                    ? '未设置具体时间'
                    : '${_todo.reminderAt!.year}-${_todo.reminderAt!.month.toString().padLeft(2, '0')}-${_todo.reminderAt!.day.toString().padLeft(2, '0')} ${_todo.reminderAt!.hour.toString().padLeft(2, '0')}:${_todo.reminderAt!.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final baseDate = _todo.reminderAt ??
                    _todo.dueDate ??
                    DateTime.now().add(const Duration(hours: 1));
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: baseDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2099, 12, 31),
                );
                if (pickedDate == null) return;
                if (!context.mounted) return;
                final pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(baseDate),
                );
                if (pickedTime == null) return;
                setState(() {
                  _todo = _todo.copyWith(
                    reminderAt: DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      pickedTime.hour,
                      pickedTime.minute,
                    ),
                  );
                });
              },
            ),
          const SizedBox(height: 12),
          const Text('标签', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ..._todo.tags.map(
                (t) => Chip(
                  label: Text('#$t'),
                  onDeleted: () => setState(
                    () => _todo = _todo.copyWith(
                      tags: _todo.tags.where((x) => x != t).toList(),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _tagCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '+ 新标签',
                  ),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('子任务',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const Spacer(),
              Text(
                '${_todo.subtasks.where((s) => s.isCompleted).length}/${_todo.subtasks.length}',
                style: TextStyle(
                    color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
              final ids =
                  _todo.subtasks.map((e) => e.id).toList();
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
                      fontSize: 14,
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
    );
  }
}
