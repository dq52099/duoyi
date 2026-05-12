import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/design_tokens.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../services/alarm_service.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';

const List<int> _habitEditColors = <int>[
  0xFF4CAF50,
  0xFF2196F3,
  0xFFFF9800,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF607D8B,
];

class HabitDetailScreen extends StatefulWidget {
  final String habitId;

  const HabitDetailScreen({super.key, required this.habitId});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  Future<void> _showEditSheet(Habit habit) async {
    final nameCtrl = TextEditingController(text: habit.name);
    final targetCtrl = TextEditingController(
      text: habit.targetCount.toString(),
    );
    var selectedColor = habit.colorValue;
    var selectedKind = habit.kind;
    var reminderPlan = _habitReminderPlan(habit);

    await showAppModalSheet(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSt) {
          Future<void> save() async {
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(sheetCtx);
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              messenger.showSnackBar(const SnackBar(content: Text('请填写习惯名称')));
              return;
            }

            final target = int.tryParse(targetCtrl.text.trim()) ?? 1;
            if (target < 1) {
              messenger.showSnackBar(
                const SnackBar(content: Text('每日目标次数至少为 1')),
              );
              return;
            }

            final reminderRule = _habitPrimaryReminder(reminderPlan);
            final hasReminder =
                reminderPlan.enabled &&
                reminderRule != null &&
                reminderRule.enabled &&
                reminderRule.hour != null &&
                reminderRule.minute != null;
            final nextActiveWeekdays =
                hasReminder &&
                    reminderRule.type == ReminderRuleType.weeklyTime &&
                    reminderRule.weekdays.isNotEmpty
                ? reminderRule.weekdays
                      .where((d) => d >= 1 && d <= 7)
                      .map((d) => d - 1)
                      .toList()
                : habit.activeWeekdays;

            final updated = habit.copyWith(
              name: name,
              targetCount: target,
              colorValue: selectedColor,
              kind: selectedKind,
              activeWeekdays: nextActiveWeekdays,
              remind: hasReminder,
              remindHour: hasReminder ? reminderRule.hour : null,
              remindMinute: hasReminder ? reminderRule.minute : null,
            );

            await context.read<HabitProvider>().updateHabit(habit.id, updated);
            if (!mounted) return;
            navigator.pop();
            messenger.showSnackBar(
              const SnackBar(
                content: Text('已保存'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(milliseconds: 1200),
              ),
            );
          }

          return AppModalSheet(
            title: '编辑习惯',
            subtitle: habit.name,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(onPressed: save, child: const Text('保存')),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '习惯名称',
                    prefixIcon: Icon(Icons.edit, size: 20),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '每日目标次数',
                          prefixIcon: Icon(Icons.track_changes, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                const Text(
                  '习惯类型',
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    fontWeight: DesignTokens.fontWeightMedium,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('✅ 正向养成'),
                        selected: selectedKind == HabitKind.positive,
                        onSelected: (_) =>
                            setSt(() => selectedKind = HabitKind.positive),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spaceSm),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('🚫 反向戒除'),
                        selected: selectedKind == HabitKind.negative,
                        onSelected: (_) =>
                            setSt(() => selectedKind = HabitKind.negative),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                const Text(
                  '颜色',
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSm,
                    fontWeight: DesignTokens.fontWeightMedium,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Wrap(
                  spacing: DesignTokens.spaceSm,
                  runSpacing: DesignTokens.spaceSm,
                  children: [
                    for (final c in _habitEditColors)
                      GestureDetector(
                        onTap: () => setSt(() => selectedColor = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: selectedColor == c
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                            boxShadow: selectedColor == c
                                ? [
                                    BoxShadow(
                                      color: Color(c).withValues(alpha: 0.35),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                ReminderPlanEditor(
                  plan: reminderPlan,
                  title: '提醒',
                  allowAlarm: false,
                  allowRelativeToDue: false,
                  allowWeekly: true,
                  allowSnooze: false,
                  hasAnchorDate: false,
                  maxRules: 1,
                  onChanged: (plan) => setSt(() => reminderPlan = plan),
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Builder(
                  builder: (context) {
                    final notif = context.watch<NotificationService?>();
                    if (notif == null) return const SizedBox.shrink();
                    return ReminderHealthHint(
                      reminderKind: ReminderKind.push,
                      onOpenSystemSettings: () => _openSystemSettings(context),
                      onRequestNotificationPermission: () async {
                        await context
                            .read<NotificationService>()
                            .requestPermission();
                      },
                      onRequestExactAlarmPermission: () async {
                        await AlarmService.instance
                            .requestExactAlarmPermission();
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final matches = provider.habits.where((h) => h.id == widget.habitId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('习惯详情')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.space3xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                Text(
                  '这个习惯不存在或已被删除',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: DesignTokens.spaceLg),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final habit = matches.first;
    final heatmapData = habit.heatmapData(20);
    final cs = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.name),
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditSheet(habit),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.star, color: color, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    habit.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatChip(
                        label: '当前连续',
                        value: '${habit.currentStreak}天',
                      ),
                      const SizedBox(width: 16),
                      _StatChip(label: '最佳纪录', value: '${habit.bestStreak}天'),
                      const SizedBox(width: 16),
                      _StatChip(
                        label: '今日',
                        value: '${habit.todayCount()}/${habit.targetCount}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '打卡热力图',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          HabitHeatmap(heatmapData: heatmapData, weeks: 20),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '最近打卡记录',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 30,
            itemBuilder: (_, i) {
              final d = DateTime.now().subtract(Duration(days: i));
              final count = habit.countForDate(d);
              final target = habit.targetCount < 1 ? 1 : habit.targetCount;
              return ListTile(
                dense: true,
                leading: Text(
                  '${d.month}/${d.day}',
                  style: const TextStyle(fontSize: 13),
                ),
                title: LinearProgressIndicator(
                  value: (count / target).clamp(0.0, 1.0),
                ),
                trailing: Text(
                  '$count/${habit.targetCount}',
                  style: TextStyle(
                    fontSize: 12,
                    color: count >= habit.targetCount
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<void> _openSystemSettings(BuildContext context) async {
  final opened = await openAppSettings();
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('无法打开系统设置'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

ReminderPlan _habitReminderPlan(Habit habit) {
  if (!habit.remind || habit.remindHour == null || habit.remindMinute == null) {
    return const ReminderPlan.disabled();
  }
  final weekdays =
      habit.activeWeekdays
          .where((d) => d >= 0 && d <= 6)
          .map((d) => d + 1)
          .toList()
        ..sort();
  final fullWeek = weekdays.length == 7;
  return ReminderPlan(
    enabled: true,
    rules: [
      ReminderRule(
        id: 'habit-reminder',
        enabled: true,
        type: fullWeek
            ? ReminderRuleType.dailyTime
            : ReminderRuleType.weeklyTime,
        kind: ReminderKind.push,
        hour: habit.remindHour,
        minute: habit.remindMinute,
        weekdays: fullWeek ? const <int>[] : weekdays,
      ),
    ],
  );
}

ReminderRule? _habitPrimaryReminder(ReminderPlan plan) {
  for (final rule in plan.rules) {
    if (rule.enabled) return rule;
  }
  return plan.rules.isEmpty ? null : plan.rules.first;
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }
}
