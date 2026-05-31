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
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final createdAt = I18nDateFormat.fullDateTime(e.createdAt);
                return AppSurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              createdAt,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.62),
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            if (e.model.isNotEmpty)
                              AppStatusBadge(
                                label: e.model,
                                color: cs.primary,
                                icon: Icons.memory_outlined,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                              ),
                            PopupMenuButton<String>(
                              iconSize: 18,
                              onSelected: (v) async {
                                if (v == 'copy') {
                                  await Clipboard.setData(
                                    ClipboardData(text: e.content),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        I18n.tr('ai_history.copy.done'),
                                      ),
                                    ),
                                  );
                                } else if (v == 'delete') {
                                  await context.read<AiService>().deleteReview(
                                    e.id,
                                  );
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
                          e.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.68),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          e.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            height: 1.62,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
