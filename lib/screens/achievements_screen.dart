import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/achievements.dart';
import '../providers/achievement_provider.dart';
import '../widgets/surface_components.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AchievementProvider>();
    final all = Achievements.all;
    final unlocked = provider.unlockedCount;

    return Scaffold(
      appBar: AppBar(title: Text('成就 · $unlocked / ${all.length}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          _ProgressHeader(unlocked: unlocked, total: all.length),
          const SizedBox(height: 12),
          const AppSectionHeader(
            title: '徽章墙',
            subtitle: '按使用进度逐步解锁',
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.42,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: all.map((a) {
              final snapshot = provider.snapshotFor(a.id);
              final target = snapshot.target;
              return _BadgeCard(
                ach: a,
                unlocked: snapshot.unlocked,
                current: a.current == null && target == null
                    ? null
                    : snapshot.current,
                target: target,
                progress: snapshot.progress,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int unlocked;
  final int total;
  const _ProgressHeader({required this.unlocked, required this.total});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = total == 0 ? 0.0 : unlocked / total;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        colors: [
          cs.primary.withValues(alpha: 0.92),
          cs.tertiary.withValues(alpha: 0.78),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: cs.onPrimary.withValues(alpha: 0.14)),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.emoji_events, color: cs.onPrimary, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你的成就',
                  style: TextStyle(
                    color: cs.onPrimary.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$unlocked / $total',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p,
                    minHeight: 7,
                    backgroundColor: cs.onPrimary.withValues(alpha: 0.25),
                    color: cs.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final Achievement ach;
  final bool unlocked;
  final int? current;
  final int? target;
  final double progress;

  const _BadgeCard({
    required this.ach,
    required this.unlocked,
    required this.current,
    required this.target,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = unlocked ? ach.color : Colors.grey.shade400;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: color.withValues(alpha: unlocked ? 0.24 : 0.14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(ach.icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ach.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: unlocked
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.48),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: unlocked ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unlocked ? '已解锁' : '进行中',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ach.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.62),
              height: 1.4,
            ),
          ),
          const Spacer(),
          if (current != null && target != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: color.withValues(alpha: 0.12),
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$current / $target',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
