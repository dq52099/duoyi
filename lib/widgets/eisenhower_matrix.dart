import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../models/todo.dart';
import '../providers/theme_provider.dart';

class EisenhowerMatrix extends StatelessWidget {
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;
  final void Function(EisenhowerQuadrant) onQuadrantTap;

  const EisenhowerMatrix({
    super.key,
    required this.quadrantGroups,
    required this.onQuadrantTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
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

  const _QuadrantCard({
    required this.quadrant,
    required this.label,
    required this.subLabel,
    required this.items,
    required this.onTap,
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
    return GestureDetector(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...items.take(3).map((t) {
                                final visual =
                                    CompletionVisibilityPolicy.visualState(t);
                                final stateColor =
                                    CompletionVisibilityPolicy.colorFor(visual);
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
                                return Padding(
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
                              }),
                              if (items.length > 3)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '+${items.length - 3} 更多...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                            ],
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
  }
}
