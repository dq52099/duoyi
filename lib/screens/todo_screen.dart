import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../models/goal.dart' show ReminderKind;
import '../models/todo.dart';
import '../models/workspace.dart';
import '../providers/auth_provider.dart';
import '../providers/share_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_service.dart';
import '../core/todo_templates.dart';
import '../widgets/eisenhower_matrix.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'share_screen.dart';
import 'todo_detail_screen.dart' show TodoDetailScreen, priorityColor;

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

    showAppModalSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppSurfaceCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 24,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  s.todoCreateTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(hintText: '准备做什么？'),
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
                          fontWeight: FontWeight.w400,
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
                      color: Theme.of(
                        ctx,
                      ).colorScheme.surface.withValues(alpha: 0.55),
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
                    fontWeight: FontWeight.w400,
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
                    fontWeight: FontWeight.w400,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                AppDropdownField<EisenhowerQuadrant>(
                  initialValue: quadrant,
                  labelText: '优先级',
                  onTap: () => FocusScope.of(ctx).unfocus(),
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
                    fontWeight: FontWeight.w400,
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
                        final workspaceId = groupName.isEmpty
                            ? 'private'
                            : context
                                      .read<TodoProvider>()
                                      .workspaceForListGroup(groupName) ??
                                  'private';
                        if (!context.read<ShareProvider>().canEdit(
                          workspaceId,
                        )) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('你在这个共享空间中只有查看权限')),
                          );
                          return;
                        }
                        context.read<TodoProvider>().addTodo(
                          TodoItem(
                            title: titleCtrl.text.trim(),
                            quadrant: quadrant,
                            priority: priority,
                            listGroupName: groupName.isEmpty ? null : groupName,
                            workspaceId: workspaceId,
                            createdBy: context
                                .read<AuthProvider>()
                                .state
                                .userId,
                            updatedBy: context
                                .read<AuthProvider>()
                                .state
                                .userId,
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
                        fontWeight: FontWeight.w400,
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
    final overdueCount = todoProvider.overdueTodos.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.todoTitle),
        actions: [
          if (overdueCount > 0)
            TextButton.icon(
              onPressed: () async {
                await context.read<TodoProvider>().postponeOverdue(
                  DateTime.now(),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已顺延 $overdueCount 个逾期任务'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.update_outlined, size: 18),
              label: const Text('顺延'),
            ),
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
    final todoProvider = context.watch<TodoProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final workspaceId = todoProvider.workspaceForListGroup(widget.groupName);
    final workspace = workspaceId == null
        ? null
        : shareProvider.workspaces
              .where((workspace) => workspace.id == workspaceId)
              .firstOrNull;
    return AppSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: cs.primary,
              ),
            ),
            title: Text(
              widget.groupName,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
            subtitle: workspace == null
                ? null
                : Text(
                    '共享：${workspace.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (workspace != null)
                  Icon(Icons.groups_2_outlined, size: 18, color: cs.primary),
                IconButton(
                  tooltip: '共享清单',
                  onPressed: () => _shareGroup(context),
                  icon: const Icon(Icons.ios_share_outlined),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${widget.todos.length}',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...widget.todos.map((t) => _TodoTile(todo: t)),
        ],
      ),
    );
  }

  Future<void> _shareGroup(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShareScreen()),
      );
      return;
    }

    final share = context.read<ShareProvider>();
    if (share.workspaces.isEmpty) await share.load();
    if (!context.mounted) return;
    final workspaces = share.workspaces.where((w) => !w.isPrivate).toList();
    if (workspaces.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShareScreen()),
      );
      return;
    }

    final picked = await showAppModalSheet<String>(
      context: context,
      builder: (_) => AppModalSheet(
        title: '共享清单',
        subtitle: '把「${widget.groupName}」标记到共享空间',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('仅自己可见'),
              onTap: () => Navigator.pop(context, 'private'),
            ),
            for (final workspace in workspaces)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(workspace.name),
                subtitle: Text(
                  '${workspace.members.length} 位成员 · ${workspace.roleFor(auth.state.userId).label}',
                ),
                enabled: workspace.roleFor(auth.state.userId).canEdit,
                onTap: workspace.roleFor(auth.state.userId).canEdit
                    ? () => Navigator.pop(context, workspace.id)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await context.read<TodoProvider>().updateListGroupWorkspace(
      widget.groupName,
      picked,
      userId: auth.state.userId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('共享状态已更新')));
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}

class _TodoTile extends StatelessWidget {
  final TodoItem todo;
  const _TodoTile({required this.todo});

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
    final visual = CompletionVisibilityPolicy.visualState(todo);
    // 已归档的任务不在今日 / 列表中渲染（P5）。
    if (visual == TodoVisualState.archived) {
      return const SizedBox.shrink();
    }

    final provider = context.read<TodoProvider>();
    final canEdit = context.watch<ShareProvider>().canEdit(todo.workspaceId);
    final cs = Theme.of(context).colorScheme;
    final qColor = _quadrantColor(todo.quadrant);

    return Dismissible(
      key: ValueKey(todo.id),
      direction: canEdit ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceMd,
          vertical: DesignTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: DesignTokens.borderRadiusMd,
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: DesignTokens.spaceXl),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => provider.deleteTodo(todo.id),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceMd,
          vertical: DesignTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: DesignTokens.borderRadiusMd,
          boxShadow: DesignTokens.shadowXs,
        ),
        child: ClipRRect(
          borderRadius: DesignTokens.borderRadiusMd,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: qColor),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TodoDetailScreen(todoId: todo.id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spaceSm,
                        DesignTokens.spaceSm,
                        DesignTokens.spaceSm,
                        DesignTokens.spaceSm,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: DesignTokens.spaceXxs,
                            ),
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: Checkbox(
                                value: todo.isCompleted,
                                shape: const CircleBorder(),
                                activeColor: qColor,
                                onChanged: canEdit
                                    ? (_) => provider.toggleTodo(todo.id)
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: DesignTokens.spaceXs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _TitleRow(todo: todo, visual: visual),
                                const SizedBox(height: DesignTokens.spaceXxs),
                                _MetaRow(
                                  todo: todo,
                                  quadrantColor: qColor,
                                  visual: visual,
                                ),
                              ],
                            ),
                          ),
                        ],
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

/// 标题 + 优先级色点。
class _TitleRow extends StatelessWidget {
  final TodoItem todo;
  final TodoVisualState visual;
  const _TitleRow({required this.todo, required this.visual});

  @override
  Widget build(BuildContext context) {
    final isCompleted = visual == TodoVisualState.completed;
    final baseColor = Theme.of(context).colorScheme.onSurface;
    final titleColor = isCompleted
        ? baseColor.withValues(alpha: DesignTokens.completedTextOpacity)
        : null;

    return Row(
      children: [
        if (todo.priority != TodoPriority.none) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: priorityColor(todo.priority),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DesignTokens.spaceXs),
        ],
        Expanded(
          child: Text(
            todo.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeBase,
              color: titleColor,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// 元信息行：优先级胶囊、重复、过期、子任务、标签、目标时长、下次提醒、截止日。
class _MetaRow extends StatelessWidget {
  final TodoItem todo;
  final Color quadrantColor;
  final TodoVisualState visual;

  const _MetaRow({
    required this.todo,
    required this.quadrantColor,
    required this.visual,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (todo.priority != TodoPriority.none) {
      final c = priorityColor(todo.priority);
      chips.add(
        _MetaPill(
          color: c,
          child: Text(
            todo.priority.label,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: c,
              fontWeight: DesignTokens.fontWeightSemiBold,
            ),
          ),
        ),
      );
    }

    if (todo.recurrence.isActive) {
      chips.add(Icon(Icons.repeat, size: 12, color: Colors.grey.shade500));
    }

    // 已完成：绿色 "已完成" 徽章。
    if (visual == TodoVisualState.completed) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.completed);
      chips.add(
        _MetaPill(
          color: c,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 11, color: c),
              const SizedBox(width: 2),
              Text(
                '已完成',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: c,
                  fontWeight: DesignTokens.fontWeightSemiBold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 临期：橙色 "临期" 胶囊 + 闪烁 alarm icon。
    if (visual == TodoVisualState.dueSoon) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.dueSoon);
      chips.add(
        _MetaPill(
          color: c,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BlinkingIcon(icon: Icons.alarm, color: c, size: 11),
              const SizedBox(width: 2),
              Text(
                '临期',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: c,
                  fontWeight: DesignTokens.fontWeightSemiBold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 已过期：红色 "过期" 胶囊。沿用已有视觉语义，统一 token 色。
    if (visual == TodoVisualState.overdue) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.overdue);
      chips.add(
        _MetaPill(
          color: c,
          child: Text(
            '过期',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: c,
              fontWeight: DesignTokens.fontWeightSemiBold,
            ),
          ),
        ),
      );
    }

    if (todo.subtasks.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
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
                fontSize: DesignTokens.fontSizeSm,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    // 标签：最多展示前 3 个，多出部分以 "+N" 汇总。
    if (todo.tags.isNotEmpty) {
      const maxShown = 3;
      final shown = todo.tags.take(maxShown).toList();
      for (final t in shown) {
        chips.add(
          _MetaPill(
            color: Theme.of(context).colorScheme.primary,
            child: Text(
              '#$t',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final overflow = todo.tags.length - shown.length;
      if (overflow > 0) {
        chips.add(
          _MetaPill(
            color: Colors.grey.shade600,
            child: Text(
              '+$overflow',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        );
      }
    }

    // 目标时长
    final tSec = todo.timeTargetSeconds;
    if (tSec != null && tSec > 0) {
      chips.add(
        _MetaPill(
          color: Colors.teal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_bottom, size: 11, color: Colors.teal),
              const SizedBox(width: 2),
              Text(
                '目标 ${tSec ~/ 60}m',
                style: const TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 下一次提醒。临期状态下把 alarm icon 也闪烁一下，强化提示。
    final r = todo.reminder;
    if (r.enabled && r.hour != null && r.minute != null) {
      final hh = r.hour!.toString().padLeft(2, '0');
      final mm = r.minute!.toString().padLeft(2, '0');
      final icon = r.kind == ReminderKind.alarm
          ? Icons.alarm
          : Icons.notifications;
      final reminderColor = visual == TodoVisualState.dueSoon
          ? CompletionVisibilityPolicy.colorFor(TodoVisualState.dueSoon)
          : Colors.indigo;
      final iconWidget = visual == TodoVisualState.dueSoon
          ? _BlinkingIcon(icon: icon, color: reminderColor, size: 11)
          : Icon(icon, size: 11, color: reminderColor);
      chips.add(
        _MetaPill(
          color: reminderColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 2),
              Text(
                '下次 $hh:$mm',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: reminderColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (todo.dueDate != null) {
      chips.add(
        _MetaPill(
          color: quadrantColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 10, color: quadrantColor),
              const SizedBox(width: 4),
              Text(
                '${todo.dueDate!.month}/${todo.dueDate!.day}',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: quadrantColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (todo.workspaceId != 'private') {
      chips.add(
        _MetaPill(
          color: Theme.of(context).colorScheme.primary,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                '共享',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }
}

/// 临期任务的闪烁图标：1s 周期内 opacity 在 0.5↔1.0 之间来回过渡。
///
/// 使用 [AnimationController] + `reverse = true` 实现"脉冲"效果，
/// 给"临期"胶囊上的 alarm / notifications icon 一个可视化的警示感。
class _BlinkingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _BlinkingIcon({
    required this.icon,
    required this.color,
    this.size = 12,
  });

  @override
  State<_BlinkingIcon> createState() => _BlinkingIconState();
}

class _BlinkingIconState extends State<_BlinkingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _opacity = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}

/// 统一的元信息胶囊（带 12% 底色）。
class _MetaPill extends StatelessWidget {
  final Color color;
  final Widget child;

  const _MetaPill({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceXs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: DesignTokens.borderRadiusSm,
      ),
      child: child,
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
