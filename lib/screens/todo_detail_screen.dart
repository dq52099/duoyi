import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/todo_provider.dart';

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
    context.read<TodoProvider>().updateTodo(widget.todoId, _todo.copyWith(
          title: _titleCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        ));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)));
  }

  void _addSubtask() {
    if (_subtaskCtrl.text.trim().isEmpty) return;
    context.read<TodoProvider>().addSubtask(widget.todoId, _subtaskCtrl.text.trim());
    _subtaskCtrl.clear();
    setState(() {
      _todo = context.read<TodoProvider>().todos.firstWhere((t) => t.id == widget.todoId);
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _subtaskCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TodoProvider>();
    _todo = provider.todos.firstWhere((t) => t.id == widget.todoId, orElse: () => _todo);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('任务详情'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: '任务名称'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: '备注'), maxLines: 3),
          const SizedBox(height: 16),

          DropdownButtonFormField<EisenhowerQuadrant>(
            initialValue: _todo.quadrant,
            decoration: const InputDecoration(labelText: '四象限'),
            items: const [
              DropdownMenuItem(value: EisenhowerQuadrant.urgentImportant, child: Text('Q1 重要且紧急')),
              DropdownMenuItem(value: EisenhowerQuadrant.notUrgentImportant, child: Text('Q2 重要不紧急')),
              DropdownMenuItem(value: EisenhowerQuadrant.urgentNotImportant, child: Text('Q3 紧急不重要')),
              DropdownMenuItem(value: EisenhowerQuadrant.notUrgentNotImportant, child: Text('Q4 不重要不紧急')),
            ],
            onChanged: (v) => setState(() => _todo = _todo.copyWith(quadrant: v!)),
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              const Text('子任务', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const Spacer(),
              Text('${_todo.subtasks.where((s) => s.isCompleted).length}/${_todo.subtasks.length}',
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _subtaskCtrl, decoration: const InputDecoration(labelText: '新增子任务', isDense: true))),
              IconButton(onPressed: _addSubtask, icon: Icon(Icons.add_circle, color: cs.primary)),
            ],
          ),
          ..._todo.subtasks.map((s) => ListTile(
                dense: true,
                leading: Checkbox(
                  value: s.isCompleted,
                  onChanged: (_) {
                    provider.toggleSubtask(widget.todoId, s.id);
                    setState(() {});
                  },
                ),
                title: Text(s.title, style: TextStyle(fontSize: 14, decoration: s.isCompleted ? TextDecoration.lineThrough : null)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    provider.deleteSubtask(widget.todoId, s.id);
                    setState(() {});
                  },
                ),
              )),
        ],
      ),
    );
  }
}