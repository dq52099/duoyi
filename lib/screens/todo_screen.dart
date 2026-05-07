import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../providers/todo_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_service.dart';
import '../core/todo_templates.dart';
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
    var priority = TodoPriority.none;
    String groupName = '';
    bool aiBusy = false;
    List<String> aiSubtasks = [];
    String? aiError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  s.todoCreateTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    hintText: '准备做什么？',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(18),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),

                // AI Action
                if (ai.enabled)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: aiBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Colors.purple,
                            ),
                      label: const Text(
                        'AI 智能拆解',
                        style: TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: Colors.purple.shade50,
                      side: BorderSide.none,
                      onPressed: aiBusy
                          ? null
                          : () async {
                              if (titleCtrl.text.trim().isEmpty) return;
                              setSt(() {
                                aiBusy = true;
                                aiError = null;
                              });
                              try {
                                final list = await ai.breakDownTask(
                                  titleCtrl.text.trim(),
                                );
                                setSt(() => aiSubtasks = list);
                              } catch (e) {
                                setSt(() => aiError = 'AI 拆解失败');
                              } finally {
                                setSt(() => aiBusy = false);
                              }
                            },
                    ),
                  ),

                if (aiError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      aiError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),

                if (aiSubtasks.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: aiSubtasks
                          .map(
                            (t) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),

                const SizedBox(height: 20),
                const Text(
                  '清单类型',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: TodoListTemplates.all
                        .map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                t.icon,
                                size: 16,
                                color: groupName == t.name
                                    ? Colors.white
                                    : t.color,
                              ),
                              label: Text(t.name),
                              selected: groupName == t.name,
                              selectedColor: t.color,
                              labelStyle: TextStyle(
                                color: groupName == t.name
                                    ? Colors.white
                                    : null,
                              ),
                              onSelected: (sel) =>
                                  setSt(() => groupName = sel ? t.name : ''),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  '优先级',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EisenhowerQuadrant>(
                  initialValue: quadrant,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.urgentImportant,
                      child: Text('🔴 重要且紧急 (Q1)'),
                    ),
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.notUrgentImportant,
                      child: Text('🟠 重要不紧急 (Q2)'),
                    ),
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.urgentNotImportant,
                      child: Text('🔵 紧急不重要 (Q3)'),
                    ),
                    DropdownMenuItem(
                      value: EisenhowerQuadrant.notUrgentNotImportant,
                      child: Text('⚪ 不重要不紧急 (Q4)'),
                    ),
                  ],
                  onChanged: (v) => setSt(() => quadrant = v!),
                ),
                const SizedBox(height: 16),
                const Text(
                  '优先级标记',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final p in TodoPriority.values)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: priority == p,
                        onSelected: (_) => setSt(() => priority = p),
                      ),
                  ],
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      if (titleCtrl.text.trim().isNotEmpty) {
                        final sub = aiSubtasks
                            .map((t) => Subtask(title: t))
                            .toList();
                        context.read<TodoProvider>().addTodo(
                          TodoItem(
                            title: titleCtrl.text.trim(),
                            quadrant: quadrant,
                            priority: priority,
                            listGroupName: groupName.isEmpty ? null : groupName,
                            subtasks: sub,
                          ),
                        );
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '添加任务',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          ? EmptyState(
              icon: Icons.task_alt,
              message: s.todoEmpty,
              actionLabel: s.todoAddAction,
              onAction: _showAddDialog,
            )
          : _isMatrixView
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: EisenhowerMatrix(
                quadrantGroups: quadrantGroups,
                onQuadrantTap: (q) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuadrantListScreen(quadrant: q),
                    ),
                  );
                },
              ),
            )
          : ListView(
              children: listGroups.entries
                  .map((e) => _ListGroupTile(groupName: e.key, todos: e.value))
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
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
            title: Text(
              widget.groupName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: Text(
              '${widget.todos.length}',
              style: TextStyle(color: cs.primary),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...widget.todos.map((t) => _TodoTile(todo: t)),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  final TodoItem todo;
  const _TodoTile({required this.todo});

  Color _priorityColor(TodoPriority p) {
    switch (p) {
      case TodoPriority.urgent:
        return const Color(0xFFD32F2F);
      case TodoPriority.high:
        return const Color(0xFFEF6C00);
      case TodoPriority.medium:
        return const Color(0xFFFBC02D);
      case TodoPriority.low:
        return const Color(0xFF388E3C);
      case TodoPriority.none:
        return Colors.grey;
    }
  }

  Color _quadrantColor(EisenhowerQuadrant q) {
    switch (q) {
      case EisenhowerQuadrant.urgentImportant:
        return const Color(0xFFE53935);
      case EisenhowerQuadrant.notUrgentImportant:
        return const Color(0xFFF6A339);
      case EisenhowerQuadrant.urgentNotImportant:
        return const Color(0xFF42A5F5);
      case EisenhowerQuadrant.notUrgentNotImportant:
        return const Color(0xFF8E8E8E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TodoProvider>();
    final cs = Theme.of(context).colorScheme;
    final qColor = _quadrantColor(todo.quadrant);

    return Dismissible(
      key: ValueKey(todo.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => provider.deleteTodo(todo.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: qColor),
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    leading: Checkbox(
                      value: todo.isCompleted,
                      shape: const CircleBorder(),
                      activeColor: qColor,
                      onChanged: (_) => provider.toggleTodo(todo.id),
                    ),
                    title: Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 15,
                        color: todo.isCompleted ? Colors.grey : null,
                        decoration: todo.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        if (todo.priority != TodoPriority.none)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: _priorityColor(todo.priority)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              todo.priority.label,
                              style: TextStyle(
                                fontSize: 10,
                                color: _priorityColor(todo.priority),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (todo.recurrence.isActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.repeat,
                                size: 11, color: Colors.grey.shade500),
                          ),
                        if (todo.isOverdue)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('过期',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.red)),
                          ),
                        if (todo.subtasks.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_tree_outlined,
                                  size: 12,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${todo.subtasks.where((s) => s.isCompleted).length}/${todo.subtasks.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (todo.dueDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: qColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 10,
                                  color: qColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${todo.dueDate!.month}/${todo.dueDate!.day}',
                                  style: TextStyle(fontSize: 11, color: qColor),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TodoDetailScreen(todoId: todo.id),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuadrantListScreen extends StatelessWidget {
  final EisenhowerQuadrant quadrant;

  const QuadrantListScreen({super.key, required this.quadrant});

  String _title(EisenhowerQuadrant q) {
    switch (q) {
      case EisenhowerQuadrant.urgentImportant:
        return '重要且紧急';
      case EisenhowerQuadrant.notUrgentImportant:
        return '重要不紧急';
      case EisenhowerQuadrant.urgentNotImportant:
        return '紧急不重要';
      case EisenhowerQuadrant.notUrgentNotImportant:
        return '不重要不紧急';
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
