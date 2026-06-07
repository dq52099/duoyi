import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// AI 周回顾历史：本地持久化最近 50 条。
class AiHistoryScreen extends StatelessWidget {
  const AiHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiService>();
    final items = ai.reviewHistory;
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('ai_history.title')),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: I18n.tr('ai_history.clear.tooltip'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AppDialog(
                    title: Text(I18n.tr('ai_history.clear.title')),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    content: Text(I18n.tr('ai_history.clear.content')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(I18n.tr('action.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(I18n.tr('ai_history.clear.action')),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<AiService>().clearReviewHistory();
                }
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.auto_awesome,
              message: I18n.tr('ai_history.empty'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = items[i];
                return _AiHistoryEntryCard(
                  key: ValueKey('ai_history_entry_${e.id}'),
                  entry: e,
                );
              },
            ),
    );
  }
}

class _AiHistoryEntryCard extends StatefulWidget {
  final AiReviewEntry entry;

  const _AiHistoryEntryCard({super.key, required this.entry});

  @override
  State<_AiHistoryEntryCard> createState() => _AiHistoryEntryCardState();
}

class _AiHistoryEntryCardState extends State<_AiHistoryEntryCard> {
  bool _expanded = false;

  AiReviewEntry get entry => widget.entry;

  @override
  void didUpdateWidget(covariant _AiHistoryEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (entry.id != oldWidget.entry.id) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final createdAt = I18nDateFormat.fullDateTime(entry.createdAt);
    final content = entry.content.trim();
    final canCollapse = content.length > 180 || content.contains('\n');

    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          createdAt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.model.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AppStatusBadge(
                        label: entry.model,
                        color: cs.primary,
                        icon: Icons.memory_outlined,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                      ),
                    ),
                  ),
                ],
                PopupMenuButton<String>(
                  iconSize: 18,
                  onSelected: (v) async {
                    if (v == 'copy') {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: entry.content),
                      );
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(I18n.tr('ai_history.copy.done')),
                        ),
                      );
                    } else if (v == 'delete') {
                      await context.read<AiService>().deleteReview(entry.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Text(I18n.tr('ai_history.copy')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        I18n.tr('ai_history.delete'),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text(
                content,
                key: ValueKey(
                  _expanded
                      ? 'ai_history_content_expanded_${entry.id}'
                      : 'ai_history_content_collapsed_${entry.id}',
                ),
                maxLines: _expanded ? null : 6,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  height: 1.62,
                ),
              ),
            ),
            if (canCollapse) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey(
                    _expanded
                        ? 'ai_history_collapse_button_${entry.id}'
                        : 'ai_history_expand_button_${entry.id}',
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _expanded
                        ? I18n.tr('ai_history.collapse')
                        : I18n.tr('ai_history.expand'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
