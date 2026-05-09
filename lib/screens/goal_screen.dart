import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../widgets/empty_state.dart';
import 'goal_edit_screen.dart';
import 'recommended_goals_picker.dart';

class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoalProvider>();
    final goals = provider.goals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('目标管理'),
        actions: [
          IconButton(
            tooltip: '推荐模板',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _openRecommended(context),
          ),
        ],
      ),
      body: goals.isEmpty
          ? EmptyState(
              icon: Icons.flag_outlined,
              message: '设立一个目标，让时间为你累积',
              actionLabel: '新建目标',
              onAction: () => _openEdit(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: goals.length,
              itemBuilder: (_, i) => _GoalCard(goal: goals[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.add),
        label: const Text('新目标'),
      ),
    );
  }

  void _openEdit(BuildContext context, {GoalItem? goal}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
    );
  }

  void _openRecommended(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecommendedGoalsPicker()),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalItem goal;
  const _GoalCard({required this.goal});

  Color _statusColor() => switch (goal.status) {
        GoalStatus.active => const Color(0xFF66BB6A),
        GoalStatus.paused => Colors.grey,
        GoalStatus.achieved => const Color(0xFFFFA726),
        GoalStatus.abandoned => Colors.red.shade300,
      };

  String _statusText() => switch (goal.status) {
        GoalStatus.active => '进行中',
        GoalStatus.paused => '已暂停',
        GoalStatus.achieved => '已达成',
        GoalStatus.abandoned => '已放弃',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(goal.colorValue);
    final progress = goal.computedProgress;
    final days = goal.daysRemaining;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.flag, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (goal.description.isNotEmpty)
                          Text(
                            goal.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusText(),
                      style: TextStyle(
                        fontSize: 11,
                        color: _statusColor(),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: color.withValues(alpha: 0.1),
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '里程碑 ${goal.milestones.where((m) => m.isCompleted).length}/${goal.milestones.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (goal.targetDate != null) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.schedule,
                        size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      days >= 0 ? '还剩 $days 天' : '已超期 ${-days} 天',
                      style: TextStyle(
                        fontSize: 11,
                        color: days >= 0
                            ? Colors.grey.shade600
                            : Colors.red,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
