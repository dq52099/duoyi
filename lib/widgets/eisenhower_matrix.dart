import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../models/todo.dart';
import '../providers/theme_provider.dart';

class EisenhowerMatrix extends StatelessWidget {
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;
  final void Function(EisenhowerQuadrant) onQuadrantTap;

  /// 长按拖动条目到目标象限时回调；为 null 时矩阵保持只读。
  final void Function(TodoItem todo, EisenhowerQuadrant target)?
  onTodoQuadrantChanged;

  /// 单条待办的拖拽编辑权限谓词；为 null 时全部允许。
  /// 只读共享工作区成员应返回 false：该行不再可拖拽，投放也被拒收，
  /// 与 tile 级入口的 canEdit 闸保持一致。
  final bool Function(TodoItem todo)? canEditTodo;

  const EisenhowerMatrix({
    super.key,
    required this.quadrantGroups,
    required this.onQuadrantTap,
    this.onTodoQuadrantChanged,
    this.canEditTodo,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    // 局部变量以获得空值提升，供四处 _QuadrantCard 接线使用。
    final onTodoChanged = onTodoQuadrantChanged;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuadrantCard(
                quadrant: EisenhowerQuadrant.urgentImportant,
                label: s.quadrantQ1Label,
                subLabel: s.quadrantQ1Sub,
                items: quadrantGroups[EisenhowerQuadrant.urgentImportant] ?? [],
                onTodoDropped: onTodoChanged == null
                    ? null
                    : (todo) => onTodoChanged(
                        todo,
                        EisenhowerQuadrant.urgentImportant,
                      ),
                canEditTodo: canEditTodo,
                onTap: () => onQuadrantTap(EisenhowerQuadrant.urgentImportant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuadrantCard(
                quadrant: EisenhowerQuadrant.notUrgentImportant,
                label: s.quadrantQ2Label,
                subLabel: s.quadrantQ2Sub,
                items:
                    quadrantGroups[EisenhowerQuadrant.notUrgentImportant] ?? [],
                onTodoDropped: onTodoChanged == null
                    ? null
                    : (todo) => onTodoChanged(
                        todo,
                        EisenhowerQuadrant.notUrgentImportant,
                      ),
                canEditTodo: canEditTodo,
                onTap: () =>
                    onQuadrantTap(EisenhowerQuadrant.notUrgentImportant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuadrantCard(
                quadrant: EisenhowerQuadrant.urgentNotImportant,
                label: s.quadrantQ3Label,
                subLabel: s.quadrantQ3Sub,
                items:
                    quadrantGroups[EisenhowerQuadrant.urgentNotImportant] ?? [],
                onTodoDropped: onTodoChanged == null
                    ? null
                    : (todo) => onTodoChanged(
                        todo,
                        EisenhowerQuadrant.urgentNotImportant,
                      ),
                canEditTodo: canEditTodo,
                onTap: () =>
                    onQuadrantTap(EisenhowerQuadrant.urgentNotImportant),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuadrantCard(
                quadrant: EisenhowerQuadrant.notUrgentNotImportant,
                label: s.quadrantQ4Label,
                subLabel: s.quadrantQ4Sub,
                items:
                    quadrantGroups[EisenhowerQuadrant.notUrgentNotImportant] ??
                    [],
                onTodoDropped: onTodoChanged == null
                    ? null
                    : (todo) => onTodoChanged(
                        todo,
                        EisenhowerQuadrant.notUrgentNotImportant,
                      ),
                canEditTodo: canEditTodo,
                onTap: () =>
                    onQuadrantTap(EisenhowerQuadrant.notUrgentNotImportant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  final EisenhowerQuadrant quadrant;
  final String label;
  final String subLabel;
  final List<TodoItem> items;
  final VoidCallback onTap;
  final ValueChanged<TodoItem>? onTodoDropped;
  final bool Function(TodoItem)? canEditTodo;

  const _QuadrantCard({
    required this.quadrant,
    required this.label,
    required this.subLabel,
    required this.items,
    required this.onTap,
    this.onTodoDropped,
    this.canEditTodo,
  });

  Color _bgColor() {
    switch (quadrant) {
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
    final bg = _bgColor();
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.018),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 4, width: double.infinity, color: bg),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.normal,
                                color: bg,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (items.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: bg.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${items.length}',
                                style: TextStyle(
                                  color: bg,
                                  fontWeight: FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              '暂无任务',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const previewRowHeight = 24.0;
                              const moreLabelHeight = 17.0;
                              final reserveMoreLabel = items.length > 3;
                              final availableForRows =
                                  constraints.maxHeight -
                                  (reserveMoreLabel ? moreLabelHeight : 0);
                              var visibleCount =
                                  (availableForRows / previewRowHeight).floor();
                              if (visibleCount < 1) visibleCount = 1;
                              if (visibleCount > 3) visibleCount = 3;

                              final visibleItems = items
                                  .take(visibleCount)
                                  .toList(growable: false);
                              final hiddenCount =
                                  items.length - visibleItems.length;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...visibleItems.map((t) {
                                    final visual =
                                        CompletionVisibilityPolicy.visualState(
                                          t,
                                        );
                                    final stateColor =
                                        CompletionVisibilityPolicy.colorFor(
                                          visual,
                                        );
                                    final isCompleted =
                                        visual == TodoVisualState.completed;
                                    final isOverdue =
                                        visual == TodoVisualState.overdue;
                                    final isDueSoon =
                                        visual == TodoVisualState.dueSoon;
                                    final itemColor =
                                        isCompleted || isOverdue || isDueSoon
                                        ? stateColor
                                        : bg.withValues(alpha: 0.8);
                                    final row = Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: itemColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              t.title,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isCompleted
                                                    ? Colors.grey
                                                    : isOverdue
                                                    ? stateColor
                                                    : null,
                                                decoration: isCompleted
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isOverdue || isCompleted)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              child: Text(
                                                isCompleted ? '已完成' : '逾期',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: itemColor,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                    // 只读成员（canEditTodo 返回 false）的行
                                    // 不进入拖拽，杜绝绕过权限换象限。
                                    final canDrag =
                                        onTodoDropped != null &&
                                        (canEditTodo?.call(t) ?? true);
                                    if (!canDrag) return row;
                                    return LongPressDraggable<TodoItem>(
                                      data: t,
                                      feedback: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            t.title,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.4,
                                        child: row,
                                      ),
                                      child: row,
                                    );
                                  }),
                                  if (hiddenCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '+$hiddenCount 更多...',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTodoDropped == null) return card;
    return DragTarget<TodoItem>(
      // 拒收同象限与无编辑权限的投放（防御性复查，拖拽源已按权限收口）。
      onWillAcceptWithDetails: (details) =>
          details.data.quadrant != quadrant &&
          (canEditTodo?.call(details.data) ?? true),
      onAcceptWithDetails: (details) => onTodoDropped!(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        if (!hovering) return card;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(color: bg, width: 2),
          ),
          child: card,
        );
      },
    );
  }
}
