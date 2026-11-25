import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/todo_ui_copy.dart';
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

  /// 最宽桌面档（调用方按窗口宽度 ≥ DesktopTokens.breakpointThreeColumn
  /// 传入）：四象限单行 4 列横排。false（默认）保持 2×2 竖排，
  /// 紧迫/重要两轴语义不变。
  final bool fourColumn;

  const EisenhowerMatrix({
    super.key,
    required this.quadrantGroups,
    required this.onQuadrantTap,
    this.onTodoQuadrantChanged,
    this.canEditTodo,
    this.fourColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final onTodoChanged = onTodoQuadrantChanged;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final s = themeProvider.brand.strings;
        _QuadrantCard quadrantCard(
          EisenhowerQuadrant quadrant,
          String label,
          String sub,
        ) {
          return _QuadrantCard(
            quadrant: quadrant,
            label: label,
            subLabel: sub,
            items: quadrantGroups[quadrant] ?? [],
            onTodoDropped: onTodoChanged == null
                ? null
                : (todo) => onTodoChanged(todo, quadrant),
            canEditTodo: canEditTodo,
            onTap: () => onQuadrantTap(quadrant),
          );
        }

        final cards = <_QuadrantCard>[
          quadrantCard(
            EisenhowerQuadrant.urgentImportant,
            s.quadrantQ1Label,
            s.quadrantQ1Sub,
          ),
          quadrantCard(
            EisenhowerQuadrant.notUrgentImportant,
            s.quadrantQ2Label,
            s.quadrantQ2Sub,
          ),
          quadrantCard(
            EisenhowerQuadrant.urgentNotImportant,
            s.quadrantQ3Label,
            s.quadrantQ3Sub,
          ),
          quadrantCard(
            EisenhowerQuadrant.notUrgentNotImportant,
            s.quadrantQ4Label,
            s.quadrantQ4Sub,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            var columns = fourColumn ? 4 : 2;
            var width =
                (constraints.maxWidth - DesignTokens.spaceSm * (columns - 1)) /
                columns;
            final scaler = MediaQuery.textScalerOf(context);
            final inheritedStyle = DefaultTextStyle.of(context).style;
            double textHeight(String text, TextStyle style, double maxWidth) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: inheritedStyle.merge(style)),
                textDirection: Directionality.of(context),
                textScaler: scaler,
              )..layout(maxWidth: math.max(1.0, maxWidth));
              final height = painter.height;
              painter.dispose();
              return height;
            }

            const titleStyle = TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
            );
            const subStyle = TextStyle(fontSize: 11);
            if (!fourColumn) {
              for (final card in cards) {
                // CJK headings can wrap between characters. Preserve that
                // grid; use one column when a Latin word cannot fit whole.
                if (!RegExp(r'[A-Za-z]').hasMatch(card.label)) continue;
                final painter = TextPainter(
                  text: TextSpan(
                    text: card.label,
                    style: inheritedStyle.merge(titleStyle),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: scaler,
                )..layout();
                final needsOneColumn = painter.minIntrinsicWidth > width - 28;
                painter.dispose();
                if (needsOneColumn) {
                  columns = 1;
                  width = constraints.maxWidth;
                  break;
                }
              }
            }
            var extraHeight = 0.0;
            for (final card in cards) {
              var badgeWidth = 0.0;
              if (card.items.isNotEmpty) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: '${card.items.length}',
                    style: inheritedStyle.merge(
                      const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: scaler,
                )..layout();
                badgeWidth = painter.width + 12 + 8;
                painter.dispose();
              }
              final titleExtra =
                  textHeight(card.label, titleStyle, width - 28) -
                  textHeight(card.label, titleStyle, double.infinity);
              final subExtra =
                  textHeight(card.subLabel, subStyle, width - 28 - badgeWidth) -
                  textHeight(card.subLabel, subStyle, double.infinity);
              extraHeight = math.max(
                extraHeight,
                math.max(0.0, titleExtra) + math.max(0.0, subExtra),
              );
            }
            // Keep all four cards equally tall while reserving the full header
            // height. Task preview space stays available after labels wrap.
            final height =
                160.0 * scaler.scale(1).clamp(1.0, 1.6) + extraHeight;
            Widget sizedCard(int index) => Expanded(
              child: SizedBox(height: height, child: cards[index]),
            );
            if (columns == 1) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: DesignTokens.spaceSm),
                    SizedBox(height: height, child: cards[i]),
                  ],
                ],
              );
            }
            if (fourColumn) {
              return Row(
                children: [
                  sizedCard(0),
                  const SizedBox(width: DesignTokens.spaceSm),
                  sizedCard(1),
                  const SizedBox(width: DesignTokens.spaceSm),
                  sizedCard(2),
                  const SizedBox(width: DesignTokens.spaceSm),
                  sizedCard(3),
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    sizedCard(0),
                    const SizedBox(width: DesignTokens.spaceSm),
                    sizedCard(1),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Row(
                  children: [
                    sizedCard(2),
                    const SizedBox(width: DesignTokens.spaceSm),
                    sizedCard(3),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

TextStyle _matrixEffectiveTextStyle(BuildContext context, TextStyle? style) {
  final defaultTextStyle = DefaultTextStyle.of(context);
  var effectiveTextStyle = style;
  if (style == null || style.inherit) {
    effectiveTextStyle = defaultTextStyle.style.merge(style);
  }
  if (MediaQuery.boldTextOf(context)) {
    effectiveTextStyle = effectiveTextStyle!.merge(
      const TextStyle(fontWeight: FontWeight.bold),
    );
  }
  final lineHeightScaleFactor =
      MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (lineHeightScaleFactor != null ||
      letterSpacing != null ||
      wordSpacing != null) {
    final overrideTextStyle = TextStyle(
      height: lineHeightScaleFactor,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
    );
    effectiveTextStyle =
        effectiveTextStyle?.merge(overrideTextStyle) ?? overrideTextStyle;
  }
  return effectiveTextStyle ?? const TextStyle();
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

  Color _bgColor(bool isDark) {
    switch (quadrant) {
      case EisenhowerQuadrant.urgentImportant:
        return isDark ? DesignTokens.todoOverdueDark : DesignTokens.defaultError;
      case EisenhowerQuadrant.notUrgentImportant:
        return isDark ? DesignTokens.todoDueSoonDark : DesignTokens.todoDueSoon;
      case EisenhowerQuadrant.urgentNotImportant:
        return isDark ? const Color(0xFF60A5FA) : DesignTokens.defaultInfo;
      case EisenhowerQuadrant.notUrgentNotImportant:
        return isDark
            ? DesignTokens.todoArchivedDark
            : DesignTokens.defaultTextMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = _bgColor(isDark);
    // The matrix reserves equal card heights, including wrapped headings.
    // Keep task row estimates consistent with the existing scaled preview.
    final fontScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.6).toDouble();
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
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
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          color: bg,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              subLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (items.isNotEmpty) ...[
                            const SizedBox(width: 8),
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
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              TodoUiCopy.eisenhowerEmpty,
                              style: TextStyle(
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.72,
                                ),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final textScaler = MediaQuery.textScalerOf(
                                context,
                              );
                              final textDirection = Directionality.of(context);
                              final locale = Localizations.maybeLocaleOf(context);
                              Size measuredSize(
                                String text,
                                TextStyle style, {
                                int? maxLines,
                                double maxWidth = double.infinity,
                              }) {
                                final painter = TextPainter(
                                  text: TextSpan(
                                    text: text,
                                    style: _matrixEffectiveTextStyle(
                                      context,
                                      style,
                                    ),
                                    locale: locale,
                                  ),
                                  textScaler: textScaler,
                                  textDirection: textDirection,
                                  locale: locale,
                                  maxLines: maxLines,
                                )..layout(
                                    maxWidth: maxWidth.isFinite
                                        ? math.max(1.0, maxWidth)
                                        : double.infinity,
                                  );
                                final size = painter.size;
                                painter.dispose();
                                return size;
                              }

                              const dotAndGap = 14.0; // 6px dot + 8px gap
                              final candidateRows =
                                  <
                                    ({
                                      TodoItem item,
                                      double height,
                                      bool stackStatus,
                                      bool indentStatus,
                                      bool isCompleted,
                                      bool isOverdue,
                                      Color itemColor,
                                      TextStyle titleStyle,
                                      TextStyle statusStyle,
                                      String statusText,
                                    })
                                  >[];

                              for (final t in items.take(3)) {
                                final visual =
                                    CompletionVisibilityPolicy.visualState(t);
                                final stateColor =
                                    CompletionVisibilityPolicy.colorFor(
                                      visual,
                                      isDark: isDark,
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
                                final titleStyle = TextStyle(
                                  fontSize: 12,
                                  color: isCompleted
                                      ? cs.onSurfaceVariant
                                      : isOverdue
                                      ? stateColor
                                      : null,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                );
                                final hasStatus = isOverdue || isCompleted;
                                final statusText = isCompleted
                                    ? TodoUiCopy.completed
                                    : TodoUiCopy.overdue;
                                final statusStyle = TextStyle(
                                  fontSize: 10,
                                  color: itemColor,
                                );

                                final statusRawWidth = hasStatus
                                    ? measuredSize(
                                            statusText,
                                            statusStyle,
                                            maxLines: 1,
                                          ).width +
                                          1.0
                                    : 0.0;
                                final statusInlineWidth = hasStatus
                                    ? 6.0 + statusRawWidth
                                    : 0.0;
                                final titleWidth = measuredSize(
                                  t.title,
                                  titleStyle,
                                  maxLines: 1,
                                ).width;
                                final minTitleReserve = math.min(
                                  titleWidth,
                                  measuredSize(
                                    '字',
                                    titleStyle,
                                    maxLines: 1,
                                  ).width,
                                );
                                final stackStatus =
                                    hasStatus &&
                                    constraints.maxWidth.isFinite &&
                                    (constraints.maxWidth -
                                            dotAndGap -
                                            statusInlineWidth) <
                                        minTitleReserve;
                                final indentStatus =
                                    !constraints.maxWidth.isFinite ||
                                    (constraints.maxWidth - dotAndGap) >=
                                        statusRawWidth;

                                final double contentHeight;
                                if (stackStatus) {
                                  final titleAvail = math.max(
                                    1.0,
                                    constraints.maxWidth - dotAndGap,
                                  );
                                  final statusAvail = math.max(
                                    1.0,
                                    constraints.maxWidth -
                                        (indentStatus ? dotAndGap : 0.0),
                                  );
                                  final titleH = measuredSize(
                                    t.title,
                                    titleStyle,
                                    maxLines: 1,
                                    maxWidth: titleAvail,
                                  ).height;
                                  final statusH = measuredSize(
                                    statusText,
                                    statusStyle,
                                    maxWidth: statusAvail,
                                  ).height;
                                  contentHeight = math.max(
                                    24.0 * fontScale,
                                    math.max(6.0, titleH) + 2.0 + statusH,
                                  );
                                } else {
                                  final titleAvail = constraints.maxWidth
                                      .isFinite
                                      ? math.max(
                                          1.0,
                                          constraints.maxWidth -
                                              dotAndGap -
                                              statusInlineWidth,
                                        )
                                      : double.infinity;
                                  final titleH = measuredSize(
                                    t.title,
                                    titleStyle,
                                    maxLines: 1,
                                    maxWidth: titleAvail,
                                  ).height;
                                  final statusH = hasStatus
                                      ? measuredSize(
                                          statusText,
                                          statusStyle,
                                          maxLines: 1,
                                        ).height
                                      : 0.0;
                                  contentHeight = math.max(
                                    24.0 * fontScale,
                                    math.max(titleH, statusH),
                                  );
                                }

                                candidateRows.add((
                                  item: t,
                                  height: contentHeight + 6.0,
                                  stackStatus: stackStatus,
                                  indentStatus: indentStatus,
                                  isCompleted: isCompleted,
                                  isOverdue: isOverdue,
                                  itemColor: itemColor,
                                  titleStyle: titleStyle,
                                  statusStyle: statusStyle,
                                  statusText: statusText,
                                ));
                              }

                              final moreLabelHeight =
                                  measuredSize(
                                    TodoUiCopy.eisenhowerMore(items.length),
                                    const TextStyle(fontSize: 11),
                                    maxWidth: constraints.maxWidth,
                                  ).height +
                                  2;
                              var visibleCount = 0;
                              var usedHeight = 0.0;
                              for (var i = 0; i < candidateRows.length; i++) {
                                final nextUsed =
                                    usedHeight + candidateRows[i].height;
                                final needsMore = (i + 1) < items.length;
                                final totalRequired =
                                    nextUsed +
                                    (needsMore ? moreLabelHeight : 0.0);
                                if (totalRequired <=
                                    constraints.maxHeight + 0.01) {
                                  visibleCount = i + 1;
                                  usedHeight = nextUsed;
                                } else {
                                  break;
                                }
                              }

                              final visibleRows = candidateRows
                                  .take(visibleCount)
                                  .toList(growable: false);
                              final hiddenCount =
                                  items.length - visibleRows.length;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...visibleRows.map((entry) {
                                    final t = entry.item;
                                    final dot = Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: entry.itemColor,
                                        shape: BoxShape.circle,
                                      ),
                                    );
                                    final titleWidget = Expanded(
                                      child: Text(
                                        t.title,
                                        style: entry.titleStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                    final hasStatus =
                                        entry.isOverdue || entry.isCompleted;
                                    final statusLabel = Text(
                                      entry.statusText,
                                      style: entry.statusStyle,
                                    );

                                    final row = Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: entry.stackStatus
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    dot,
                                                    const SizedBox(width: 8),
                                                    titleWidget,
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    left: entry.indentStatus
                                                        ? dotAndGap
                                                        : 0,
                                                  ),
                                                  child: statusLabel,
                                                ),
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                dot,
                                                const SizedBox(width: 8),
                                                titleWidget,
                                                if (hasStatus)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 6,
                                                        ),
                                                    child: statusLabel,
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
                                        TodoUiCopy.eisenhowerMore(hiddenCount),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant.withValues(
                                            alpha: 0.72,
                                          ),
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
            border: Border.all(color: bg, width: 0.6),
          ),
          child: card,
        );
      },
    );
  }
}
