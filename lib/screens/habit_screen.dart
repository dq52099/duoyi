import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/habit_grouping.dart';
import '../core/habit_insights.dart';
import '../core/habit_templates.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../services/alarm_service.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/habit_date_range_fields.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_weekly_card.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
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
    final flexTargetCtrl = TextEditingController(text: '5');
    final unitCtrl = TextEditingController(text: '次');
    final categoryCtrl = TextEditingController();
    var selectedColor = 0xFF4CAF50;
    var selectedKind = HabitKind.positive;
    var flexRuleEnabled = false;
    var selectedFlexPeriod = HabitFlexPeriod.week;
    DateTime? startDate;
    DateTime? endDate;
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
                                '${t.localizedName} · ${t.localizedFrequencyLabel}',
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
                                  selectedKind = HabitKind.positive;
                                  nameCtrl.text = t.localizedName;
                                  targetCtrl.text = t.targetCount.toString();
                                  unitCtrl.text = t.localizedUnit;
                                  categoryCtrl.text = t.localizedCategory;
                                  selectedColor = t.colorValue;
                                  flexRuleEnabled = t.hasFlexRule;
                                  if (t.hasFlexRule) {
                                    selectedFlexPeriod = t.flexPeriod!;
                                    flexTargetCtrl.text = t.flexTarget!
                                        .toString();
                                  }
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
                        onSelected: (_) => setSt(() {
                          selectedKind = HabitKind.positive;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('🚫 反向戒除'),
                        selected: selectedKind == HabitKind.negative,
                        onSelected: (_) => setSt(() {
                          selectedKind = HabitKind.negative;
                          flexRuleEnabled = false;
                        }),
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
                TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(
                    labelText: '分组',
                    hintText: '例如 身体健康、学习提升',
                    prefixIcon: Icon(Icons.folder_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: targetCtrl,
                        decoration: const InputDecoration(
                          labelText: '每日目标',
                          prefixIcon: Icon(Icons.track_changes, size: 20),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 82,
                      child: TextField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(labelText: '单位'),
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
                const SizedBox(height: 12),
                AppSurfaceCard(
                  padding: const EdgeInsets.all(12),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('目标规则')),
                          Switch(
                            value:
                                flexRuleEnabled &&
                                selectedKind == HabitKind.positive,
                            onChanged: selectedKind == HabitKind.positive
                                ? (v) => setSt(() => flexRuleEnabled = v)
                                : null,
                          ),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child:
                            flexRuleEnabled &&
                                selectedKind == HabitKind.positive
                            ? Padding(
                                key: const ValueKey('habit-flex-rule-fields'),
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SegmentedButton<HabitFlexPeriod>(
                                      showSelectedIcon: false,
                                      segments: const [
                                        ButtonSegment(
                                          value: HabitFlexPeriod.week,
                                          label: Text('每周'),
                                        ),
                                        ButtonSegment(
                                          value: HabitFlexPeriod.month,
                                          label: Text('每月'),
                                        ),
                                      ],
                                      selected: {selectedFlexPeriod},
                                      onSelectionChanged: (value) => setSt(
                                        () => selectedFlexPeriod = value.first,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: flexTargetCtrl,
                                      decoration: const InputDecoration(
                                        labelText: '周期目标',
                                        hintText: '例如一周至少 5 次',
                                        prefixIcon: Icon(
                                          Icons.event_repeat,
                                          size: 20,
                                        ),
                                      ),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : Padding(
                                key: const ValueKey('habit-daily-rule-note'),
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  selectedKind == HabitKind.positive
                                      ? '关闭时按每日目标连续统计'
                                      : '反向戒除按每日不发生统计',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                HabitDateRangeFields(
                  startDate: startDate,
                  endDate: endDate,
                  onStartChanged: (value) => setSt(() => startDate = value),
                  onEndChanged: (value) => setSt(() => endDate = value),
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
                        final shouldUseFlex =
                            flexRuleEnabled &&
                            selectedKind == HabitKind.positive;
                        final flexTarget =
                            int.tryParse(flexTargetCtrl.text.trim()) ?? 0;
                        if (shouldUseFlex && flexTarget < 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('周期目标至少为 1')),
                          );
                          return;
                        }
                        if (!habitDateRangeIsValid(startDate, endDate)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('结束日期不能早于开始日期')),
                          );
                          return;
                        }
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
                            targetCount: (int.tryParse(targetCtrl.text) ?? 1)
                                .clamp(1, 9999)
                                .toInt(),
                            unit: unitCtrl.text.trim().isEmpty
                                ? null
                                : unitCtrl.text.trim(),
                            category: habitCategoryOrNull(categoryCtrl.text),
                            flexTarget: shouldUseFlex ? flexTarget : null,
                            flexPeriod: shouldUseFlex
                                ? selectedFlexPeriod
                                : null,
                            startDate: startDate,
                            endDate: endDate,
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
    final habitGroups = groupHabitsByCategory(provider.habits);
    final insights = HabitInsightEngine.buildInsights(
      provider.habits,
      limit: 3,
    );
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
                    if (insights.isNotEmpty)
                      _HabitInsightCard(insights: insights),
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
              if (provider.habits.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.folder_open,
                    message: s.habitEmpty,
                    actionLabel: s.habitAddAction,
                    onAction: _showAddDialog,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '习惯分组',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ),
                for (final group in habitGroups)
                  _HabitGroupSection(
                    group: group,
                    streakLabel: s.habitStreakLabel,
                  ),
              ],
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

class _HabitGroupSection extends StatelessWidget {
  final HabitGroup group;
  final String streakLabel;

  const _HabitGroupSection({required this.group, required this.streakLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      initiallyExpanded: true,
      leading: Icon(Icons.folder_outlined, color: cs.primary),
      title: Text(group.category),
      subtitle: Text(
        '${group.completedTodayCount}/${group.habits.length} 今日达标',
        style: const TextStyle(fontSize: 12),
      ),
      children: [
        for (final habit in group.habits)
          _HabitSummaryTile(habit: habit, streakLabel: streakLabel),
      ],
    );
  }
}

class _HabitInsightCard extends StatelessWidget {
  final List<HabitInsight> insights;

  const _HabitInsightCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '智能习惯洞察',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w400),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _insightIcon(insight.kind),
                    size: 16,
                    color: _insightColor(cs, insight.kind),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          insight.message,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _insightIcon(HabitInsightKind kind) => switch (kind) {
    HabitInsightKind.overview => Icons.auto_graph_outlined,
    HabitInsightKind.rising => Icons.trending_up,
    HabitInsightKind.slipping => Icons.trending_down,
    HabitInsightKind.streak => Icons.local_fire_department_outlined,
    HabitInsightKind.attention => Icons.tips_and_updates_outlined,
  };

  Color _insightColor(ColorScheme cs, HabitInsightKind kind) => switch (kind) {
    HabitInsightKind.overview => cs.primary,
    HabitInsightKind.rising => const Color(0xFF2E7D32),
    HabitInsightKind.slipping => const Color(0xFFC62828),
    HabitInsightKind.streak => const Color(0xFFF57C00),
    HabitInsightKind.attention => cs.tertiary,
  };
}

class _HabitSummaryTile extends StatelessWidget {
  final Habit habit;
  final String streakLabel;

  const _HabitSummaryTile({required this.habit, required this.streakLabel});

  @override
  Widget build(BuildContext context) {
    final streakUnit = habit.streakUnitLabel;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(habit.colorValue).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.star, color: Color(habit.colorValue), size: 18),
      ),
      title: Text(habit.name),
      subtitle: Text(
        '$streakLabel ${habit.currentStreak} $streakUnit · 最佳 ${habit.bestStreak} $streakUnit',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id)),
      ),
    );
  }
}

class _HabitCheckinCard extends StatelessWidget {
  final Habit habit;
  const _HabitCheckinCard({required this.habit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNegative = habit.kind == HabitKind.negative;
    final todayCount = habit.todayCount();
    final flexProgress = habit.flexProgressForDate(DateTime.now());
    final progress = habit.todayProgress();
    final isDone = habit.isCompletedToday();
    final isDailyDone = todayCount >= habit.targetCount;
    final canCheckIn =
        isNegative || (habit.hasFlexRule ? !isDailyDone : !isDone);
    final hasNegativeOccurrence = isNegative && todayCount > 0;
    final habitColor = hasNegativeOccurrence
        ? cs.error
        : Color(habit.colorValue);
    final targetText = isNegative
        ? '目标: 不发生'
        : habit.hasFlexRule
        ? '目标: ${habit.flexPeriodGoalLabel} · 每天 ${habit.targetCount} ${habit.unit ?? '次'}'
        : '目标: ${habit.targetCount} ${habit.unit ?? '次'}/天';
    final countText = isNegative
        ? '$todayCount ${habit.unit ?? '次'}'
        : habit.hasFlexRule
        ? (flexProgress?.label ?? '$todayCount/${habit.targetCount}')
        : '$todayCount/${habit.targetCount}';

    return AnimatedScale(
      scale: isDone && !hasNegativeOccurrence ? 1.01 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: AppSurfaceCard(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDone || hasNegativeOccurrence
              ? habitColor.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 1.5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: habitColor.withValues(
                      alpha: isDone && !hasNegativeOccurrence ? 0.22 : 0.15,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      isNegative
                          ? (hasNegativeOccurrence
                                ? Icons.warning_amber_rounded
                                : Icons.shield_outlined)
                          : (isDone
                                ? Icons.verified_rounded
                                : Icons.star_border),
                      key: ValueKey<String>(
                        '${habit.id}-${isDone && !hasNegativeOccurrence}-$hasNegativeOccurrence',
                      ),
                      color: habitColor,
                      size: 26,
                    ),
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
                          decoration: isDone && !isNegative
                              ? TextDecoration.lineThrough
                              : null,
                          color: hasNegativeOccurrence
                              ? cs.error
                              : (isDone && !isNegative ? Colors.grey : null),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        targetText,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: isDone && !isNegative
                            ? const Padding(
                                key: ValueKey('habit-completed-feedback'),
                                padding: EdgeInsets.only(top: 6),
                                child: _HabitFeedbackBadge(
                                  icon: Icons.check_circle,
                                  label: '已达标',
                                  color: Color(0xFF4CAF50),
                                ),
                              )
                            : hasNegativeOccurrence
                            ? Padding(
                                key: const ValueKey('habit-warning-feedback'),
                                padding: const EdgeInsets.only(top: 6),
                                child: _HabitFeedbackBadge(
                                  icon: Icons.info_outline,
                                  label: '已记录',
                                  color: cs.error,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('habit-no-feedback'),
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
                        '${habit.currentStreak} ${habit.streakUnitLabel}',
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
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
                            width: constraints.maxWidth * progress,
                            decoration: BoxDecoration(
                              color: isDone && !hasNegativeOccurrence
                                  ? const Color(0xFF4CAF50)
                                  : habitColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 112,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        onPressed: canCheckIn
                            ? () => _handleCheckIn(context)
                            : null,
                        icon: Icon(
                          isNegative
                              ? Icons.add_circle_outline
                              : (!canCheckIn
                                    ? Icons.check
                                    : Icons.check_circle),
                        ),
                        label: Text(
                          isNegative ? '记录一次' : (!canCheckIn ? '已完成' : '打卡'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: habitColor,
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
                            countText,
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 12,
                              color: hasNegativeOccurrence
                                  ? cs.error
                                  : (isDone
                                        ? const Color(0xFF4CAF50)
                                        : Colors.grey.shade700),
                            ),
                          ),
                          if (todayCount > 0) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _handleUndo(context),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.undo,
                                  size: 15,
                                  color: hasNegativeOccurrence
                                      ? cs.error
                                      : Colors.grey.shade600,
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
      ),
    );
  }

  Future<void> _handleCheckIn(BuildContext context) async {
    final provider = context.read<HabitProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final isNegative = habit.kind == HabitKind.negative;
    final currentCount = habit.todayCount();
    final increment = _defaultDisplayCheckInAmount(habit, currentCount);
    final nextCount = currentCount + increment;
    final willReachTarget =
        !isNegative &&
        !habit.hasFlexRule &&
        !habit.isCompletedToday() &&
        nextCount >= habit.targetCount;

    await provider.incrementHabit(habit.id);
    final flexProgress = habit.flexProgressForDate(DateTime.now());
    final flexMessage = flexProgress == null
        ? '已打卡「${habit.name}」 $nextCount/${habit.targetCount}'
        : '已打卡「${habit.name}」 ${flexProgress.label}';
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isNegative
              ? '已记录一次「${habit.name}」'
              : habit.hasFlexRule
              ? flexMessage
              : (willReachTarget
                    ? '「${habit.name}」今日已达标'
                    : '已打卡「${habit.name}」 $nextCount/${habit.targetCount}'),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _handleUndo(BuildContext context) async {
    final provider = context.read<HabitProvider>();
    await provider.decrementHabit(habit.id);
    await HapticFeedback.selectionClick();
  }

  int _defaultDisplayCheckInAmount(Habit habit, int currentCount) {
    if (habit.kind != HabitKind.positive) return 1;
    if (TimeAuditProvider.habitUnitSeconds(habit) == null) return 1;
    final remaining = habit.targetCount - currentCount;
    return remaining > 0 ? remaining : 1;
  }
}

class _HabitFeedbackBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HabitFeedbackBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
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
