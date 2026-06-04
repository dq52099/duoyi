import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/habit_grouping.dart';
import '../core/habit_icons.dart';
import '../core/habit_insights.dart';
import '../core/habit_templates.dart';
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/habit_date_range_fields.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_weekly_card.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/brand_background.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'habit_detail_screen.dart';

const int _habitHeatmapGroupPreviewLimit = 8;

class HabitScreen extends StatefulWidget {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _heatmapTabBuilt = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(_markHeatmapTabBuilt);
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_markHeatmapTabBuilt);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _markHeatmapTabBuilt() {
    if (_heatmapTabBuilt || _tabCtrl.index != 1) return;
    setState(() => _heatmapTabBuilt = true);
  }

  Future<bool> _ensureHabitReminderReady() async {
    final messenger = ScaffoldMessenger.of(context);
    final notificationService = context.read<NotificationService?>();
    final granted =
        notificationService == null ||
        await notificationService.requestPermission();
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
    var selectedIcon = defaultHabitIconToken;
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
          child: AppSecondaryControlTheme(
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
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Recommended Section ---
                  const Text(
                    '推荐目标',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
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
                              final frequencyLabel = t.hasFlexRule
                                  ? _habitTemplateFrequencyLabel(t)
                                  : t.localizedFrequencyLabel;
                              return ActionChip(
                                avatar: Icon(
                                  t.icon,
                                  size: 16,
                                  color: Color(t.colorValue),
                                ),
                                label: Text(
                                  '${t.localizedName} · $frequencyLabel',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                backgroundColor: Color(
                                  t.colorValue,
                                ).withValues(alpha: 0.05),
                                side: BorderSide(
                                  color: Color(
                                    t.colorValue,
                                  ).withValues(alpha: 0.14),
                                  width: 0.45,
                                ),
                                onPressed: () {
                                  setSt(() {
                                    selectedKind = HabitKind.positive;
                                    selectedIcon = habitIconTokenForIcon(
                                      t.icon,
                                    );
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
                          label: const Text('正向养成'),
                          selected: selectedKind == HabitKind.positive,
                          onSelected: (_) => setSt(() {
                            selectedKind = HabitKind.positive;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('反向戒除'),
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
                              initialTime:
                                  remindTime ?? nextHalfHourTimeOfDay(),
                              title: '每日提醒时间',
                              minuteStep: 5,
                            );
                            if (t == null || !mounted || !ctx.mounted) return;
                            setSt(() => remindTime = t);
                          }
                          if (remindTime == null) return;
                          final ready = await _ensureHabitReminderReady();
                          if (!mounted || !ctx.mounted) return;
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
                              remindTime ??
                              const TimeOfDay(hour: 20, minute: 0),
                          title: '每日提醒时间',
                          minuteStep: 5,
                        );
                        if (t == null || !mounted || !ctx.mounted) return;
                        setSt(() => remindTime = t);
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
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: Color(c),
                                        shape: BoxShape.circle,
                                        border: selectedColor == c
                                            ? Border.all(
                                                color: Colors.white,
                                                width: 1.2,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SegmentedButton<HabitFlexPeriod>(
                                        showSelectedIcon: false,
                                        segments: [
                                          ButtonSegment(
                                            value: HabitFlexPeriod.week,
                                            label: Text(
                                              I18n.tr('habit.flex.weekly'),
                                            ),
                                          ),
                                          ButtonSegment(
                                            value: HabitFlexPeriod.month,
                                            label: Text(
                                              I18n.tr('habit.flex.monthly'),
                                            ),
                                          ),
                                        ],
                                        selected: {selectedFlexPeriod},
                                        onSelectionChanged: (value) => setSt(
                                          () =>
                                              selectedFlexPeriod = value.first,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: flexTargetCtrl,
                                        decoration: InputDecoration(
                                          labelText: I18n.tr(
                                            'habit.flex.period_target',
                                          ),
                                          hintText: I18n.tr(
                                            'habit.flex.period_target_hint',
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.event_repeat,
                                            size: 20,
                                          ),
                                        ),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
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
                    height: 46,
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
                              icon: selectedIcon,
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
                        foregroundColor: _habitButtonForeground(
                          Color(selectedColor),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '开启新习惯',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return BrandScaffold(
      paintBackground: false,
      appBar: AppBar(
        title: Text(s.habitTitle),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabCtrl,
          labelStyle: appSecondaryMenuItemTextStyle(context),
          unselectedLabelStyle: appSecondaryMenuItemTextStyle(context),
          labelColor: cs.onSurface,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary.withValues(alpha: 0.72),
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
          CustomScrollView(
            key: const ValueKey('habit_today_scroll_view'),
            slivers: [
              const SliverToBoxAdapter(child: HabitWeeklyCard()),
              SliverToBoxAdapter(
                key: const ValueKey('habit_insight_before_today_list'),
                child: _HabitInsightSection(habits: provider.habits),
              ),
              if (activeHabits.isEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('habit_today_empty_state_sliver'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    child: EmptyState(
                      icon: Icons.repeat,
                      message: s.habitEmpty,
                      actionLabel: s.habitAddAction,
                      onAction: _showAddDialog,
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _HabitTodaySummaryCard(
                    completedCount: activeHabits
                        .where((h) => h.isCompletedToday())
                        .length,
                    totalCount: activeHabits.length,
                    progress: provider.todayOverallProgress,
                    longestStreak: provider.longestCurrentStreak,
                    doneLabel: s.habitTodayDone,
                    streakLabel: s.habitStreakLabel,
                  ),
                ),
                SliverList.builder(
                  key: const ValueKey('habit_today_checkin_sliver'),
                  itemCount: activeHabits.length,
                  itemBuilder: (context, index) =>
                      _HabitCheckinCard(habit: activeHabits[index]),
                ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.paddingOf(context).bottom + 88,
                ),
              ),
            ],
          ),
          // Heatmap
          _heatmapTabBuilt
              ? _HabitHeatmapTab(
                  provider: provider,
                  heading: s.habitHeatmapHeading,
                  streakLabel: s.habitStreakLabel,
                  emptyMessage: s.habitEmpty,
                  actionLabel: s.habitAddAction,
                  onAdd: _showAddDialog,
                )
              : const SizedBox.shrink(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HabitHeatmapTab extends StatelessWidget {
  final HabitProvider provider;
  final String heading;
  final String streakLabel;
  final String emptyMessage;
  final String actionLabel;
  final VoidCallback onAdd;

  const _HabitHeatmapTab({
    required this.provider,
    required this.heading,
    required this.streakLabel,
    required this.emptyMessage,
    required this.actionLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final heatmapData = provider.combinedHeatmap(12);
    final habitGroups = groupHabitsByCategory(provider.habits);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AppSurfaceCard(
            key: const ValueKey('habit_heatmap_skin_card'),
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: appSecondaryRouteTitleTextStyle(
                    context,
                  ).copyWith(fontSize: DesignTokens.fontSizeCardTitle),
                ),
                const SizedBox(height: 2),
                HabitHeatmap(heatmapData: heatmapData),
              ],
            ),
          ),
        ),
        if (provider.habits.isEmpty)
          SliverToBoxAdapter(
            child: AppSurfaceCard(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.all(16),
              child: EmptyState(
                icon: Icons.folder_open,
                message: emptyMessage,
                actionLabel: actionLabel,
                onAction: onAdd,
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Text(
                '习惯分组',
                style: appSecondaryControlTextStyle(context).copyWith(
                  color: cs.onSurface.withValues(alpha: 0.68),
                  fontSize: DesignTokens.fontSizeCaption,
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: habitGroups.length,
            itemBuilder: (context, index) => _HabitGroupSection(
              key: ValueKey(
                'habit_heatmap_group_${habitGroups[index].category}',
              ),
              group: habitGroups[index],
              streakLabel: streakLabel,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 88),
        ),
      ],
    );
  }
}

class _HabitInsightSection extends StatelessWidget {
  final List<Habit> habits;

  const _HabitInsightSection({required this.habits});

  @override
  Widget build(BuildContext context) {
    final insights = HabitInsightEngine.buildInsights(habits, limit: 3);
    if (insights.isEmpty) return const SizedBox.shrink();
    return _HabitInsightCard(insights: insights);
  }
}

class _HabitTodaySummaryCard extends StatelessWidget {
  final int completedCount;
  final int totalCount;
  final double progress;
  final int longestStreak;
  final String doneLabel;
  final String streakLabel;

  const _HabitTodaySummaryCard({
    required this.completedCount,
    required this.totalCount,
    required this.progress,
    required this.longestStreak,
    required this.doneLabel,
    required this.streakLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 3),
      child: AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.normal,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$completedCount / $totalCount $doneLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$streakLabel $longestStreak 天',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitGroupSection extends StatelessWidget {
  final HabitGroup group;
  final String streakLabel;

  const _HabitGroupSection({
    super.key,
    required this.group,
    required this.streakLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final previewHabits = group.habits.length > _habitHeatmapGroupPreviewLimit
        ? group.habits.take(_habitHeatmapGroupPreviewLimit).toList()
        : group.habits;
    final hiddenCount = group.habits.length - previewHabits.length;
    return AppSurfaceCard(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded:
              group.habits.length <= _habitHeatmapGroupPreviewLimit,
          tilePadding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          childrenPadding: const EdgeInsets.only(bottom: 4),
          leading: Icon(Icons.folder_outlined, color: cs.primary, size: 18),
          minTileHeight: 44,
          dense: true,
          title: Text(
            group.category,
            style: appSecondaryMenuItemTextStyle(context).copyWith(
              fontSize: DesignTokens.fontSizeSecondary,
              fontWeight: DesignTokens.fontWeightRegular,
              color: cs.onSurface,
            ),
          ),
          subtitle: Text(
            '${group.completedTodayCount}/${group.habits.length} 今日达标',
            style: appSecondaryControlLabelStyle(context).copyWith(
              color: cs.onSurfaceVariant,
              fontSize: DesignTokens.fontSizeCaption,
            ),
          ),
          children: [
            for (final habit in previewHabits)
              _HabitSummaryTile(habit: habit, streakLabel: streakLabel),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(
                  '还有 $hiddenCount 个习惯，请进入今日打卡或习惯详情查看',
                  style: appSecondaryControlLabelStyle(context).copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: DesignTokens.fontSizeCaption,
                  ),
                ),
              ),
          ],
        ),
      ),
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
      key: const ValueKey('habit_insight_card'),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 3),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 5),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, color: cs.primary, size: 16),
              const SizedBox(width: 6),
              Text(
                '智能习惯洞察',
                style: appSecondaryRouteTitleTextStyle(
                  context,
                ).copyWith(fontSize: DesignTokens.fontSizeSection),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _insightIcon(insight.kind),
                    size: 14,
                    color: _insightColor(cs, insight.kind),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeSecondary,
                            fontWeight: DesignTokens.fontWeightRegular,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          insight.message,
                          style: TextStyle(
                            fontSize: DesignTokens.fontSizeCaption,
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
    return _HabitSwipeActionWrapper(
      habit: habit,
      showEndAction: _habitCanEnd(habit),
      actionMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Color(habit.colorValue).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _habitDisplayIcon(habit),
            color: Color(habit.colorValue),
            size: 18,
          ),
        ),
        title: Text(
          habit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeListTitle,
            fontWeight: DesignTokens.fontWeightRegular,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          '$streakLabel ${habit.currentStreak} $streakUnit · 最佳 ${habit.bestStreak} $streakUnit',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeSecondary,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HabitDetailScreen(habitId: habit.id),
          ),
        ),
      ),
    );
  }
}

const double _habitCheckinCardBodyHeight = 40;
const double _habitTitleStatusHeight = 16;
const double _habitCheckinButtonWidth = 54;
const double _habitUndoButtonWidth = 28;
const double _habitActionButtonGap = 3;
const double _habitActionRailWidth =
    _habitUndoButtonWidth + _habitActionButtonGap + _habitCheckinButtonWidth;
const double _habitSwipeActionWidth = 144;
const double _habitSwipeOpenThreshold = 36;

bool _habitCanEnd(Habit habit) {
  final endDate = habit.endDate;
  if (endDate == null) return true;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final endDay = DateTime(endDate.year, endDate.month, endDate.day);
  return !endDay.isBefore(today);
}

String _habitFlexGoalText(Habit habit) {
  if (!habit.hasFlexRule) return '';
  return switch (habit.flexPeriod!) {
    HabitFlexPeriod.week => '每周目标: ${habit.effectiveFlexTarget} 次',
    HabitFlexPeriod.month => '每月目标: ${habit.effectiveFlexTarget} 次',
  };
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
    final isFlexDone = flexProgress?.isCompleted ?? false;
    final isDailyDone = todayCount >= habit.targetCount;
    final canCheckIn =
        isNegative ||
        (habit.hasFlexRule ? !isFlexDone && !isDailyDone : !isDone);
    final hasNegativeOccurrence = isNegative && todayCount > 0;
    final habitColor = hasNegativeOccurrence
        ? cs.error
        : Color(habit.colorValue);
    final targetText = isNegative
        ? '目标: 不发生'
        : habit.hasFlexRule
        ? '${_habitFlexGoalText(habit)} · 单次目标: ${habit.targetCount} ${habit.unit ?? '次'}'
        : '目标: ${habit.targetCount} ${habit.unit ?? '次'}/天';
    final countText = isNegative
        ? '$todayCount ${habit.unit ?? '次'}'
        : habit.hasFlexRule
        ? (flexProgress?.label ?? '$todayCount/${habit.targetCount}')
        : '$todayCount/${habit.targetCount}';

    return _HabitSwipeActionWrapper(
      habit: habit,
      actionMargin: const EdgeInsets.fromLTRB(10, 0, 10, 1),
      borderRadius: BorderRadius.circular(10),
      child: AppSurfaceCard(
        key: ValueKey('habit_checkin_card_${habit.id}'),
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 1),
        padding: const EdgeInsets.fromLTRB(7, 3, 6, 3),
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HabitDetailScreen(habitId: habit.id),
          ),
        ),
        border: Border.all(
          color: isDone || hasNegativeOccurrence
              ? habitColor.withValues(alpha: 0.12)
              : Colors.transparent,
          width: 0.45,
        ),
        child: SizedBox(
          height: _habitCheckinCardBodyHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  color: habitColor.withValues(
                    alpha: isDone && !hasNegativeOccurrence ? 0.22 : 0.15,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _habitDisplayIcon(habit),
                  color: habitColor,
                  size: 13,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _habitTitleStatusHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              habit.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: DesignTokens.fontWeightRegular,
                                fontSize: DesignTokens.fontSizeSecondary,
                                height: 1.14,
                                decoration: isDone && !isNegative
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: hasNegativeOccurrence
                                    ? cs.error
                                    : (isDone && !isNegative
                                          ? Colors.grey
                                          : null),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: _habitTitleStatusHeight,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: habit.hasFlexRule ? 68 : 58,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: isDone && !isNegative
                                      ? _HabitFeedbackBadge(
                                          key: const ValueKey(
                                            'habit-completed-feedback',
                                          ),
                                          icon: Icons.check_circle,
                                          label: habit.hasFlexRule
                                              ? '${flexProgress?.labelPrefix ?? '周期'}达标'
                                              : '已达标',
                                          color: const Color(0xFF4CAF50),
                                        )
                                      : hasNegativeOccurrence
                                      ? _HabitFeedbackBadge(
                                          key: const ValueKey(
                                            'habit-warning-feedback',
                                          ),
                                          icon: Icons.info_outline,
                                          label: '已记录',
                                          color: cs.error,
                                        )
                                      : const SizedBox.shrink(
                                          key: ValueKey('habit-no-feedback'),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$targetText · $countText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: DesignTokens.fontSizeCaption,
                              height: 1.1,
                            ),
                          ),
                        ),
                        if (habit.currentStreak > 0) ...[
                          const SizedBox(width: 8),
                          _HabitStreakBadge(habit: habit),
                        ],
                      ],
                    ),
                    const SizedBox(height: 0),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(
                              height: 2,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Container(
                              height: 2,
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
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: _habitActionRailWidth,
                  maxWidth: _habitActionRailWidth,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Visibility(
                      visible: todayCount > 0,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: todayCount > 0
                          ? _HabitUndoButton(
                              key: const ValueKey('habit-undo-visible'),
                              color: hasNegativeOccurrence
                                  ? cs.error
                                  : cs.onSurfaceVariant,
                              onPressed: () => _handleUndo(context),
                            )
                          : _HabitUndoButton(
                              key: const ValueKey('habit-undo-hidden'),
                              color: cs.onSurfaceVariant,
                              onPressed: null,
                            ),
                    ),
                    const SizedBox(width: _habitActionButtonGap),
                    SizedBox(
                      width: _habitCheckinButtonWidth,
                      height: 26,
                      child: FilledButton(
                        onPressed: canCheckIn
                            ? () => _handleCheckIn(context)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: habitColor,
                          foregroundColor: _habitButtonForeground(habitColor),
                          disabledBackgroundColor: Colors.grey.shade200,
                          disabledForegroundColor: Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          minimumSize: const Size(_habitCheckinButtonWidth, 26),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        child: Text(
                          _habitCheckInButtonLabel(
                            habit: habit,
                            canCheckIn: canCheckIn,
                            flexProgress: flexProgress,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }

  Future<void> _handleCheckIn(BuildContext context) async {
    final provider = context.read<HabitProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final isNegative = habit.kind == HabitKind.negative;
    final currentCount = habit.todayCount();
    final currentFlexProgress = habit.flexProgressForDate(DateTime.now());
    if (!isNegative &&
        habit.hasFlexRule &&
        (currentFlexProgress?.isCompleted ?? false)) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '「${habit.name}」${currentFlexProgress?.labelPrefix ?? '本周期'}目标已达标',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
      return;
    }
    if (!isNegative && habit.hasFlexRule && currentCount >= habit.targetCount) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('「${habit.name}」今日单次目标已完成'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
      return;
    }
    final increment = _defaultDisplayCheckInAmount(habit, currentCount);
    final nextCount = currentCount + increment;
    final willReachTarget =
        !isNegative &&
        !habit.hasFlexRule &&
        !habit.isCompletedToday() &&
        nextCount >= habit.targetCount;

    await provider.incrementHabit(habit.id);
    final updatedMatches = provider.habits.where((item) => item.id == habit.id);
    final displayHabit = updatedMatches.isEmpty ? habit : updatedMatches.first;
    final updatedCount = displayHabit.todayCount();
    final flexProgress = displayHabit.flexProgressForDate(DateTime.now());
    final flexMessage = flexProgress == null
        ? '已打卡「${displayHabit.name}」 $updatedCount/${displayHabit.targetCount}'
        : flexProgress.isCompleted
        ? '「${displayHabit.name}」${flexProgress.labelPrefix}目标已达标'
        : '已打卡「${displayHabit.name}」 ${flexProgress.label}';
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isNegative
              ? '已记录一次「${displayHabit.name}」'
              : displayHabit.hasFlexRule
              ? flexMessage
              : (willReachTarget
                    ? '「${displayHabit.name}」今日已达标'
                    : '已打卡「${displayHabit.name}」 $updatedCount/${displayHabit.targetCount}'),
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

String _habitCheckInButtonLabel({
  required Habit habit,
  required bool canCheckIn,
  required HabitFlexProgress? flexProgress,
}) {
  if (habit.kind == HabitKind.negative) return '记录';
  if (canCheckIn) return '打卡';
  if (!habit.hasFlexRule) return '完成';
  if (flexProgress?.isCompleted ?? false) {
    return '${flexProgress?.labelPrefix ?? '周期'}完成';
  }
  return '今日完成';
}

class _HabitSwipeActionWrapper extends StatefulWidget {
  final Habit habit;
  final Widget child;
  final EdgeInsetsGeometry actionMargin;
  final BorderRadiusGeometry borderRadius;
  final bool showEndAction;

  const _HabitSwipeActionWrapper({
    required this.habit,
    required this.child,
    required this.actionMargin,
    required this.borderRadius,
    this.showEndAction = true,
  });

  @override
  State<_HabitSwipeActionWrapper> createState() =>
      _HabitSwipeActionWrapperState();
}

class _HabitSwipeActionWrapperState extends State<_HabitSwipeActionWrapper> {
  var _swipeOffset = 0.0;
  var _dragging = false;

  void _closeSwipe() {
    if (!mounted || _swipeOffset == 0) return;
    setState(() => _swipeOffset = 0);
  }

  void _runAction(VoidCallback action) {
    _closeSwipe();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) {
        final next = (_swipeOffset - details.delta.dx).clamp(
          0.0,
          _habitSwipeActionWidth,
        );
        if (next == _swipeOffset) return;
        setState(() => _swipeOffset = next);
      },
      onHorizontalDragEnd: (_) => _settleSwipe(),
      onHorizontalDragCancel: _settleSwipe,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_swipeOffset > 0)
            Positioned.fill(
              child: _HabitInlineSwipeActions(
                margin: widget.actionMargin,
                borderRadius: widget.borderRadius,
                onEdit: () => _runAction(
                  () => _handleHabitMenuAction(context, widget.habit, 'edit'),
                ),
                onEnd: () => _runAction(
                  () => _handleHabitMenuAction(context, widget.habit, 'end'),
                ),
                onDelete: () => _runAction(
                  () => _handleHabitMenuAction(context, widget.habit, 'delete'),
                ),
                showEndAction: widget.showEndAction,
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  void _settleSwipe() {
    final shouldOpen = _swipeOffset >= _habitSwipeOpenThreshold;
    setState(() {
      _dragging = false;
      _swipeOffset = shouldOpen ? _habitSwipeActionWidth : 0;
    });
  }
}

class _HabitInlineSwipeActions extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback onEdit;
  final VoidCallback onEnd;
  final VoidCallback onDelete;
  final bool showEndAction;

  const _HabitInlineSwipeActions({
    required this.margin,
    required this.borderRadius,
    required this.onEdit,
    required this.onEnd,
    required this.onDelete,
    this.showEndAction = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.74),
        borderRadius: borderRadius,
      ),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _habitSwipeActionWidth,
        height: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _HabitSwipeButton(
              key: const ValueKey('habit_swipe_edit_button'),
              icon: Icons.edit_outlined,
              label: '编辑',
              background: cs.primaryContainer.withValues(alpha: 0.60),
              foreground: cs.primary,
              onTap: onEdit,
            ),
            if (showEndAction) ...[
              const SizedBox(width: 6),
              _HabitSwipeButton(
                key: const ValueKey('habit_swipe_end_button'),
                icon: Icons.event_busy_outlined,
                label: '结束',
                background: cs.tertiaryContainer.withValues(alpha: 0.60),
                foreground: cs.tertiary,
                onTap: onEnd,
              ),
            ],
            const SizedBox(width: 6),
            _HabitSwipeButton(
              key: const ValueKey('habit_swipe_delete_button'),
              icon: Icons.delete_outline,
              label: '删除',
              background: cs.errorContainer.withValues(alpha: 0.64),
              foreground: cs.error,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _HabitSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
    if (label == '编辑') {
      return Tooltip(message: '编辑', child: child);
    }
    return Tooltip(message: label, child: child);
  }
}

class _HabitStreakBadge extends StatelessWidget {
  final Habit habit;

  const _HabitStreakBadge({required this.habit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department,
            size: 11,
            color: Colors.orange,
          ),
          const SizedBox(width: 3),
          Text(
            '${habit.currentStreak} ${habit.streakUnitLabel}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.normal,
              fontSize: 10,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitUndoButton extends StatelessWidget {
  final Color color;
  final VoidCallback? onPressed;

  const _HabitUndoButton({
    super.key,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _habitUndoButtonWidth,
      height: 26,
      child: Tooltip(
        message: '撤回一次',
        child: IconButton(
          key: const ValueKey('habit-undo-inline-button'),
          onPressed: onPressed,
          icon: const Icon(Icons.undo_rounded, size: 14),
          style: IconButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.08),
            foregroundColor: color,
            fixedSize: const Size(_habitUndoButtonWidth, 26),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            side: BorderSide(color: color.withValues(alpha: 0.12), width: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ),
    );
  }
}

class _HabitFeedbackBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HabitFeedbackBadge({
    super.key,
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
        border: Border.all(color: color.withValues(alpha: 0.14), width: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.normal,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _handleHabitMenuAction(
  BuildContext context,
  Habit habit,
  String value,
) async {
  final provider = context.read<HabitProvider>();
  if (value == 'edit') {
    await showHabitEditor(context, habit);
    return;
  }
  if (value == 'end') {
    await provider.endHabit(habit.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('习惯已结束，历史记录已保留')));
    return;
  }
  if (value == 'delete') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('删除习惯？'),
        icon: const Icon(Icons.delete_outline),
        content: const Text('会删除该习惯和关联记录，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await provider.deleteHabit(habit.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('习惯已删除')));
  }
}

Color _habitButtonForeground(Color background) {
  final black = const Color(0xFF111827);
  final blackContrast = _habitContrastRatio(background, black);
  final whiteContrast = _habitContrastRatio(background, Colors.white);
  return blackContrast >= whiteContrast ? black : Colors.white;
}

double _habitContrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}

IconData _habitDisplayIcon(Habit habit) {
  return habitDisplayIconFor(habit);
}

String _habitTemplateFrequencyLabel(HabitTemplate template) {
  if (!template.hasFlexRule) return template.localizedFrequencyLabel;
  final unit = switch (template.flexPeriod!) {
    HabitFlexPeriod.week => I18n.tr('habit.unit.week'),
    HabitFlexPeriod.month => I18n.tr('habit.unit.month'),
  };
  final label = switch (template.flexPeriod!) {
    HabitFlexPeriod.week => '每周目标',
    HabitFlexPeriod.month => '每月目标',
  };
  return '$label ${template.flexTarget} ${template.localizedUnit}/$unit';
}
