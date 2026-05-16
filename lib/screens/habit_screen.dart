import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../providers/theme_provider.dart';
import '../services/alarm_service.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_weekly_card.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../core/habit_templates.dart';
import 'habit_detail_screen.dart';

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<bool> _ensureHabitReminderReady() async {
    final messenger = ScaffoldMessenger.of(context);
    final notificationService = context.read<NotificationService?>();
    final granted =
        notificationService == null ||
        await notificationService.requestPermission();
    if (notificationService != null) {
      await AlarmService.instance.requestExactAlarmPermission();
      await AlarmService.instance.requestFullScreenIntentPermission();
    }
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('系统通知未授权，习惯提醒不会响铃或弹出'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return granted;
  }

  void _showAddDialog() {
    final s = context.read<ThemeProvider>().brand.strings;
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '1');
    var selectedColor = 0xFF4CAF50;
    var selectedKind = HabitKind.positive;
    var remindEnabled = false;
    TimeOfDay? remindTime = nextHalfHourTimeOfDay();
    final templatesByCategory = HabitTemplates.byCategory;

    final colors = [
      0xFF4CAF50,
      0xFF2196F3,
      0xFFFF9800,
      0xFFE91E63,
      0xFF9C27B0,
      0xFF00BCD4,
      0xFFFF5722,
      0xFF607D8B,
    ];

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
                  s.habitCreateTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),

                // --- Recommended Section ---
                const Text(
                  '推荐目标',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 12),
                ...templatesByCategory.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: entry.value.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            final t = entry.value[i];
                            return ActionChip(
                              avatar: Icon(
                                t.icon,
                                size: 16,
                                color: Color(t.colorValue),
                              ),
                              label: Text(
                                t.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                              backgroundColor: Color(
                                t.colorValue,
                              ).withValues(alpha: 0.05),
                              side: BorderSide(
                                color: Color(
                                  t.colorValue,
                                ).withValues(alpha: 0.2),
                              ),
                              onPressed: () {
                                setSt(() {
                                  nameCtrl.text = t.name;
                                  targetCtrl.text = t.targetCount.toString();
                                  selectedColor = t.colorValue;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),

                const Divider(height: 32),

                // --- Kind Selector ---
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
                    const SizedBox(width: 8),
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
                const SizedBox(height: 12),

                // --- Remind ---
                Row(
                  children: [
                    const Icon(Icons.alarm, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text('每日提醒'),
                    const Spacer(),
                    Switch(
                      value: remindEnabled,
                      onChanged: (v) async {
                        if (!v) {
                          setSt(() => remindEnabled = false);
                          return;
                        }
                        if (remindTime == null) {
                          final t = await AppTimePicker.show(
                            ctx,
                            initialTime: remindTime ?? nextHalfHourTimeOfDay(),
                            title: '每日提醒时间',
                            minuteStep: 5,
                          );
                          if (t != null) setSt(() => remindTime = t);
                        }
                        if (remindTime == null) return;
                        final ready = await _ensureHabitReminderReady();
                        if (!mounted) return;
                        setSt(() => remindEnabled = ready);
                      },
                    ),
                  ],
                ),
                if (remindEnabled)
                  TextButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      remindTime == null
                          ? '选择时间'
                          : AppTimePicker.format(remindTime!),
                    ),
                    onPressed: () async {
                      final t = await AppTimePicker.show(
                        ctx,
                        initialTime:
                            remindTime ?? const TimeOfDay(hour: 20, minute: 0),
                        title: '每日提醒时间',
                        minuteStep: 5,
                      );
                      if (t != null) setSt(() => remindTime = t);
                    },
                  ),
                const SizedBox(height: 4),

                // --- Manual Entry ---
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '习惯名称',
                    hintText: '输入或从上方选择',
                    prefixIcon: Icon(Icons.edit, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        decoration: const InputDecoration(
                          labelText: '每日目标次数',
                          prefixIcon: Icon(Icons.track_changes, size: 20),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppSurfaceCard(
                      padding: const EdgeInsets.all(6),
                      borderRadius: BorderRadius.circular(16),
                      child: Row(
                        children: colors
                            .take(4)
                            .map(
                              (c) => GestureDetector(
                                onTap: () => setSt(() => selectedColor = c),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Color(c),
                                      shape: BoxShape.circle,
                                      border: selectedColor == c
                                          ? Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            )
                                          : null,
                                      boxShadow: selectedColor == c
                                          ? [
                                              BoxShadow(
                                                color: Color(
                                                  c,
                                                ).withValues(alpha: 0.4),
                                                blurRadius: 4,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isNotEmpty) {
                        final habitProvider = context.read<HabitProvider>();
                        final navigator = Navigator.of(ctx);
                        final shouldRemind =
                            remindEnabled && remindTime != null;
                        final reminderReady = shouldRemind
                            ? await _ensureHabitReminderReady()
                            : false;
                        if (!mounted || !ctx.mounted) return;
                        await habitProvider.addHabit(
                          Habit(
                            id: DateTime.now().millisecondsSinceEpoch
                                .toString(),
                            name: nameCtrl.text.trim(),
                            colorValue: selectedColor,
                            kind: selectedKind,
                            targetCount: int.tryParse(targetCtrl.text) ?? 1,
                            remind: shouldRemind && reminderReady,
                            remindHour: remindTime?.hour,
                            remindMinute: remindTime?.minute,
                          ),
                        );
                        navigator.pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(selectedColor),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '开启新习惯',
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
    final provider = context.watch<HabitProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final activeHabits = provider.habits
        .where((h) => h.isActiveToday())
        .toList();
    final heatmapData = provider.combinedHeatmap(12);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(s.habitTitle),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: s.habitTabToday),
            Tab(text: s.habitTabHeatmap),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Today check-in
          activeHabits.isEmpty
              ? EmptyState(
                  icon: Icons.repeat,
                  message: s.habitEmpty,
                  actionLabel: s.habitAddAction,
                  onAction: _showAddDialog,
                )
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppSurfaceCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: BorderRadius.circular(18),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 68,
                              height: 68,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: provider.todayOverallProgress,
                                    strokeWidth: 4,
                                    backgroundColor: cs.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                  Text(
                                    '${(provider.todayOverallProgress * 100).toInt()}%',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${activeHabits.where((h) => h.isCompletedToday()).length} / ${activeHabits.length} ${s.habitTodayDone}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${s.habitStreakLabel} ${provider.longestCurrentStreak} 天',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const HabitWeeklyCard(),
                    ...activeHabits.map((h) => _HabitCheckinCard(habit: h)),
                  ],
                ),
          // Heatmap
          ListView(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  s.habitHeatmapHeading,
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 15,
                  ),
                ),
              ),
              HabitHeatmap(heatmapData: heatmapData),
              const Divider(),
              // All habits list
              ...provider.habits.map(
                (h) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(h.colorValue).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.star,
                      color: Color(h.colorValue),
                      size: 18,
                    ),
                  ),
                  title: Text(h.name),
                  subtitle: Text(
                    '${s.habitStreakLabel} ${h.currentStreak} 天 · 最佳 ${h.bestStreak} 天',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HabitDetailScreen(habitId: h.id),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HabitCheckinCard extends StatelessWidget {
  final Habit habit;
  const _HabitCheckinCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<HabitProvider>();
    final progress = habit.todayProgress();
    final isDone = progress >= 1.0;

    return AppSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: isDone
            ? Color(habit.colorValue).withValues(alpha: 0.3)
            : Colors.transparent,
        width: 1.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(habit.colorValue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isDone ? Icons.star : Icons.star_border,
                  color: Color(habit.colorValue),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 16,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '目标: ${habit.targetCount} 次/天',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${habit.currentStreak} 天',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 8,
                      width:
                          (MediaQuery.of(context).size.width - 150) * progress,
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFF4CAF50)
                            : Color(habit.colorValue),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: isDone
                          ? null
                          : () => provider.incrementHabit(habit.id),
                      icon: Icon(isDone ? Icons.check : Icons.check_circle),
                      label: Text(isDone ? '已完成' : '打卡'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Color(habit.colorValue),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${habit.todayCount()}/${habit.targetCount}',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: isDone
                                ? const Color(0xFF4CAF50)
                                : Colors.grey.shade700,
                          ),
                        ),
                        if (habit.todayCount() > 0) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => provider.decrementHabit(habit.id),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.undo,
                                size: 15,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
