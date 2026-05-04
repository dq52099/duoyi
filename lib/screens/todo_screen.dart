import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/todo_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_service.dart';
import '../widgets/eisenhower_matrix.dart';
import '../widgets/empty_state.dart';
import 'todo_detail_screen.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  bool _isMatrixView = true;

  void _showAddDialog() {
    final s = context.read<ThemeProvider>().brand.strings;
    final ai = context.read<AiService>();
    final titleCtrl = TextEditingController();
    var quadrant = EisenhowerQuadrant.notUrgentImportant;
    String groupName = '';
    bool aiBusy = false;
    List<String> aiSubtasks = [];
    String? aiError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s.todoCreateTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '任务名称'), autofocus: true),
                const SizedBox(height: 8),
                if (ai.enabled)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: aiBusy
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('AI 拆解为子任务'),
                      onPressed: aiBusy
                          ? null
                          : () async {
                              if (titleCtrl.text.trim().isEmpty) return;
                              setSt(() {
                                aiBusy = true;
                                aiError = null;
                              });
                              try {
                                final list = await ai.breakDownTask(titleCtrl.text.trim());
                                setSt(() => aiSubtasks = list);
                              } on AiException catch (e) {
                                setSt(() => aiError = e.message);
                              } catch (e) {
                                setSt(() => aiError = e.toString());
                              } finally {
                                setSt(() => aiBusy = false);
                              }
                            },
                    ),
                  ),
                if (aiError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(aiError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                if (aiSubtasks.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: aiSubtasks
                            .map((sub) => Row(
                                  children: [
                                    const Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(sub, style: const TextStyle(fontSize: 12))),
                                  ],
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<EisenhowerQuadrant>(
                  initialValue: quadrant,
                  decoration: const InputDecoration(labelText: '四象限'),
                  items: const [
                    DropdownMenuItem(value: EisenhowerQuadrant.urgentImportant, child: Text('Q1 重要且紧急')),
                    DropdownMenuItem(value: EisenhowerQuadrant.notUrgentImportant, child: Text('Q2 重要不紧急')),
                    DropdownMenuItem(value: EisenhowerQuadrant.urgentNotImportant, child: Text('Q3 紧急不重要')),
                    DropdownMenuItem(value: EisenhowerQuadrant.notUrgentNotImportant, child: Text('Q4 不重要不紧急')),
                  ],
                  onChanged: (v) => setSt(() => quadrant = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(labelText: '清单组 (可选)', hintText: '如: 工作、个人、学习'),
                  onChanged: (v) => groupName = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isNotEmpty) {
                  final subtasks = aiSubtasks.map((t) => Subtask(title: t)).toList();
                  context.read<TodoProvider>().addTodo(TodoItem(
                        title: titleCtrl.text.trim(),
                        quadrant: quadrant,
                        listGroupName: groupName.isEmpty ? null : groupName,
                        subtasks: subtasks,
                      ));
                  Navigator.pop(ctx);
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todoProvider = context.watch<TodoProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final quadrantGroups = todoProvider.quadrantGroups;
    final listGroups = todoProvider.listGroupedTodos;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.todoTitle),
        actions: [
          IconButton(
            icon: Icon(_isMatrixView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isMatrixView = !_isMatrixView),
            tooltip: _isMatrixView ? s.todoListView : s.todoMatrixView,
          ),
        ],
      ),
      body: todoProvider.activeTodos.isEmpty
          ? EmptyState(icon: Icons.task_alt, message: s.todoEmpty, actionLabel: s.todoAddAction, onAction: _showAddDialog)
          : _isMatrixView
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: EisenhowerMatrix(quadrantGroups: quadrantGroups, onQuadrantTap: (q) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => QuadrantListScreen(quadrant: q)));
                  }),
                )
              : ListView(
                  children: listGroups.entries.map((e) => _ListGroupTile(groupName: e.key, todos: e.value)).toList(),
                ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
    );
  }
}

class _ListGroupTile extends StatefulWidget {
  final String groupName;
  final List<TodoItem> todos;

  const _ListGroupTile({required this.groupName, required this.todos});

  @override
  State<_ListGroupTile> createState() => _ListGroupTileState();
}

class _ListGroupTileState extends State<_ListGroupTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            title: Text(widget.groupName, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text('${widget.todos.length}', style: TextStyle(color: cs.primary)),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded)
            ...widget.todos.map((t) => _TodoTile(todo: t)),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  final TodoItem todo;
  const _TodoTile({required this.todo});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TodoProvider>();
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Checkbox(
        value: todo.isCompleted,
        onChanged: (_) => provider.toggleTodo(todo.id),
      ),
      title: Text(todo.title, style: TextStyle(
        fontSize: 14,
        decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
      )),
      subtitle: Row(
        children: [
          if (todo.subtasks.isNotEmpty)
            Text('${todo.subtasks.where((s) => s.isCompleted).length}/${todo.subtasks.length} 子任务 ',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          if (todo.dueDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
              child: Text('${todo.dueDate!.month}/${todo.dueDate!.day}', style: TextStyle(fontSize: 10, color: cs.primary)),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => provider.deleteTodo(todo.id),
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TodoDetailScreen(todoId: todo.id))),
    );
  }
}

class QuadrantListScreen extends StatelessWidget {
  final EisenhowerQuadrant quadrant;

  const QuadrantListScreen({super.key, required this.quadrant});

  String _title(EisenhowerQuadrant q) {
    switch (q) {
      case EisenhowerQuadrant.urgentImportant: return '重要且紧急';
      case EisenhowerQuadrant.notUrgentImportant: return '重要不紧急';
      case EisenhowerQuadrant.urgentNotImportant: return '紧急不重要';
      case EisenhowerQuadrant.notUrgentNotImportant: return '不重要不紧急';
    }
  }

  @override
  Widget build(BuildContext context) {
    final todos = context.watch<TodoProvider>().getQuadrantTodos(quadrant);

    return Scaffold(
      appBar: AppBar(title: Text(_title(quadrant))),
      body: todos.isEmpty
          ? const EmptyState(icon: Icons.inbox, message: '这个象限没有任务')
          : ListView(children: todos.map((t) => _TodoTile(todo: t)).toList()),
    );
  }
}