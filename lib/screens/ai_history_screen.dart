import 'package:flutter/material.dart';
import '../core/i18n.dart';
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
        title: const Text('AI 周回顾历史'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清空历史',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AppDialog(
                    title: const Text('清空全部回顾?'),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    content: const Text('本地保留的 AI 回顾将被删除，无法恢复'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(I18n.tr('action.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空'),
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
          ? const EmptyState(
              icon: Icons.auto_awesome,
              message: '还没有 AI 回顾\n在"我的"页生成一份吧',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = items[i];
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final createdAt =
                    '${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}-${e.createdAt.day.toString().padLeft(2, '0')} '
                    '${e.createdAt.hour.toString().padLeft(2, '0')}:${e.createdAt.minute.toString().padLeft(2, '0')}';
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
                                fontWeight: FontWeight.w400,
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
                                    const SnackBar(content: Text('已复制')),
                                  );
                                } else if (v == 'delete') {
                                  await context.read<AiService>().deleteReview(
                                    e.id,
                                  );
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'copy', child: Text('复制')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    '删除',
                                    style: TextStyle(color: Colors.red),
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
                            fontWeight: FontWeight.w400,
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
