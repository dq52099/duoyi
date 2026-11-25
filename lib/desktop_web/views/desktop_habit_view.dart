import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/habit_grouping.dart';
import '../../core/habit_icons.dart';
import '../../core/habit_templates.dart';
import '../../core/habit_ui_copy.dart';
import '../../core/habit_unit_draft.dart';
import '../../core/i18n.dart';
import '../../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../../models/habit.dart';
import '../../providers/habit_provider.dart';
import '../../providers/preferences_provider.dart';
import '../../screens/habit_detail_screen.dart';
import '../../widgets/app_date_format.dart';
import '../../widgets/app_date_picker.dart';
import '../../widgets/app_time_picker.dart';
import '../../widgets/controller_dialog.dart';
import '../../widgets/habit_active_weekday_picker.dart';
import '../../widgets/habit_date_range_fields.dart';
import '../../widgets/habit_heatmap.dart';
import '../../widgets/habit_unit_field.dart';
import '../../widgets/surface_components.dart';
import '../desktop_web_nav.dart';
import '../desktop_web_tokens.dart';

const List<int> _desktopHabitColors = <int>[
  0xFF4CAF50,
  0xFF2196F3,
  0xFFFF9800,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF607D8B,
];

const List<IconData> _desktopHabitIcons = <IconData>[
  Icons.track_changes_outlined,
  Icons.local_drink,
  Icons.wb_sunny,
  Icons.directions_run,
  Icons.book,
  Icons.bedtime,
  Icons.self_improvement,
  Icons.code,
  Icons.fitness_center,
  Icons.account_balance_wallet,
  Icons.edit_note,
  Icons.favorite,
];

const List<String> _starterTemplateIds = <String>[
  'habit.water',
  'habit.early_rise',
  'habit.read_30min',
  'habit.run_5km',
  'habit.meditation',
  'habit.bookkeeping',
];

const String _allCategoryToken = '__all__';

enum _DesktopHabitStatusFilter { active, archived }

List<String> _parseDesktopHabitTags(String raw) {
  final seen = <String>{};
  for (final part in raw.split(RegExp(r'[,，\s]+'))) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) seen.add(trimmed);
  }
  return seen.toList();
}

class DesktopHabitView extends StatefulWidget {
  final DesktopWebNavController? controller;
  final void Function(DesktopWebDestination destination)? onNavigate;

  const DesktopHabitView({
    super.key,
    this.controller,
    this.onNavigate,
  });

  @override
  State<DesktopHabitView> createState() => _DesktopHabitViewState();
}

class _DesktopHabitViewState extends State<DesktopHabitView> {
  String _selectedCategory = _allCategoryToken;
  String? _selectedTag;
  _DesktopHabitStatusFilter _statusFilter = _DesktopHabitStatusFilter.active;
  bool _onlyScheduledToday = false;
  bool _showHeatmap = false;
  String? _lastTopBarSignature;

  DesktopWebNavController? _resolveNav(BuildContext context) {
    return widget.controller ?? DesktopWebScope.maybeOf(context);
  }

  void _syncTopBar(
    BuildContext context, {
    required AppLocale locale,
    required int completedToday,
    required int activeTodayCount,
    required int totalCount,
  }) {
    final nav = _resolveNav(context);
    if (nav == null) return;
    final isEn = locale == AppLocale.en;
    final signature =
        '${locale.storageValue}|$completedToday|$activeTodayCount|$totalCount';
    if (_lastTopBarSignature == signature) return;
    _lastTopBarSignature = signature;
    final subtitle = totalCount == 0
        ? (isEn ? 'Build consistent daily routines' : '建立清晰稳定的日常习惯矩阵')
        : (isEn
              ? '$completedToday/$activeTodayCount completed today'
              : '今日已达标 $completedToday/$activeTodayCount 项');
    nav.setTopBarSpec(
      DesktopWebDestination.habit,
      DesktopTopBarSpec(
        title: isEn ? 'Habit Matrix' : '习惯打卡',
        breadcrumb: isEn ? 'Workspace / Habits' : '工作区 / 习惯',
        subtitle: subtitle,
        showQuickCreate: false,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _addFromTemplate(HabitTemplate template) async {
    final provider = context.read<HabitProvider>();
    final locale = I18n.current;
    final isEn = locale == AppLocale.en;
    final exists = provider.habits.any(
      (h) =>
          h.name.trim().toLowerCase() ==
          template.localizedName.trim().toLowerCase(),
    );
    if (exists) {
      _showFeedback(
        isEn
            ? '${template.localizedName} is already in your habits'
            : '「${template.localizedName}」已在你的习惯列表中',
      );
      return;
    }
    final habit = Habit(
      id: 'habit_${DateTime.now().microsecondsSinceEpoch}_${template.id}',
      name: template.localizedName,
      icon: habitIconTokenForIcon(template.icon),
      colorValue: template.colorValue,
      kind: HabitKind.positive,
      targetCount: template.targetCount,
      generatedUnitKey: template.generatedUnitKey,
      unit: template.generatedUnitKey == null ? template.localizedUnit : null,
      category: template.localizedCategory,
      flexTarget: template.flexTarget,
      flexPeriod: template.flexPeriod,
    );
    await provider.addHabit(habit);
    if (!mounted) return;
    _showFeedback(
      isEn
          ? 'Added "${template.localizedName}"'
          : '已添加习惯「${template.localizedName}」',
    );
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  Future<void> _handleCheckIn(Habit habit) async {
    final provider = context.read<HabitProvider>();
    final locale = I18n.current;
    await provider.incrementHabit(habit.id);
    if (!mounted) return;
    final updated = provider.habits
        .where((h) => h.id == habit.id)
        .firstOrNull;
    if (updated == null) return;
    final msg = updated.kind == HabitKind.negative
        ? HabitUiCopy.checkInSuccessNegative(updated.name, locale)
        : updated.hasFlexRule
        ? HabitUiCopy.checkInSuccessFlex(
            updated.name,
            updated.todayCount(),
            updated.targetCount,
            updated.flexProgressForDate(DateTime.now())?.labelFor(locale),
            updated.flexProgressForDate(DateTime.now())?.isCompleted ?? false,
            updated.flexProgressForDate(DateTime.now())?.labelPrefixFor(locale),
            locale,
          )
        : HabitUiCopy.checkInSuccessStandard(
            updated.name,
            updated.todayCount(),
            updated.targetCount,
            updated.isCompletedToday(),
            locale,
          );
    _showFeedback(msg);
  }

  Future<void> _handleUndo(Habit habit) async {
    await context.read<HabitProvider>().decrementHabit(habit.id);
  }

  Future<void> _toggleDayDot(Habit habit, DateTime day) async {
    final provider = context.read<HabitProvider>();
    final today = _dateOnly(DateTime.now());
    if (day.isAfter(today) || !habit.activeForDate(day)) return;
    final count = habit.countForDate(day);
    final completed = habit.isCompletedForDate(day);
    if (habit.kind == HabitKind.negative) {
      if (count == 0) {
        await provider.incrementHabitForDate(habit.id, day);
      } else {
        await provider.decrementHabitForDate(habit.id, day);
      }
      return;
    }
    if (completed || (habit.hasFlexRule && count > 0)) {
      await provider.decrementHabitForDate(habit.id, day);
    } else {
      await provider.incrementHabitForDate(habit.id, day);
    }
  }

  void _openDetail(Habit habit) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitDetailScreen(habitId: habit.id),
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    final habitProvider = context.read<HabitProvider>();
    final nameCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '1');
    final flexTargetCtrl = TextEditingController(text: '4');
    final unitDraft = HabitUnitDraft();

    var kind = HabitKind.positive;
    var selectedColor = _desktopHabitColors.first;
    var selectedIcon = defaultHabitIconToken;
    var flexEnabled = false;
    var flexPeriod = HabitFlexPeriod.week;
    var activeWeekdays = <int>[0, 1, 2, 3, 4, 5, 6];
    var remindEnabled = false;
    final remindTimes = <TimeOfDay>[const TimeOfDay(hour: 9, minute: 0)];
    DateTime? startDate;
    DateTime? endDate;
    var saving = false;

    await showControllerDialog<void>(
      context: context,
      controllers: [
        nameCtrl,
        categoryCtrl,
        tagsCtrl,
        targetCtrl,
        flexTargetCtrl,
        unitDraft.controller,
      ],
      builder: (dialogCtx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (dialogCtx, locale, _) => StatefulBuilder(
          builder: (dialogCtx, setSt) {
            final isEn = locale == AppLocale.en;
            final t = DesktopWebTokens.of(dialogCtx);
            final templates = HabitTemplates.all.take(8).toList(growable: false);

            Future<void> submit() async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                _showFeedback(HabitUiCopy.nameRequired(locale));
                return;
              }
              final target = int.tryParse(targetCtrl.text.trim()) ?? 0;
              if (target < 1) {
                _showFeedback(HabitUiCopy.dailyTargetInvalid(locale));
                return;
              }
              final useFlex = flexEnabled && kind == HabitKind.positive;
              final flexTarget = int.tryParse(flexTargetCtrl.text.trim()) ?? 0;
              if (useFlex && flexTarget < 1) {
                _showFeedback(HabitUiCopy.flexTargetInvalid(locale));
                return;
              }
              if (!habitDateRangeIsValid(startDate, endDate)) {
                _showFeedback(HabitUiCopy.dateRangeInvalid(locale));
                return;
              }
              setSt(() => saving = true);
              final sortedTimes = remindTimes.toList()
                ..sort(
                  (a, b) =>
                      a.hour != b.hour ? a.hour - b.hour : a.minute - b.minute,
                );
              final hasReminder = remindEnabled && sortedTimes.isNotEmpty;
              final reminderPlan = hasReminder
                  ? ReminderPlan(
                      enabled: true,
                      rules: [
                        for (var i = 0; i < sortedTimes.length; i++)
                          ReminderRule(
                            id: 'desktop-habit-${DateTime.now().microsecondsSinceEpoch}-$i',
                            enabled: true,
                            type: ReminderRuleType.dailyTime,
                            kind: ReminderKind.popup,
                            hour: sortedTimes[i].hour,
                            minute: sortedTimes[i].minute,
                          ),
                      ],
                    )
                  : const ReminderPlan.disabled();
              final newHabit = Habit(
                id: 'habit_${DateTime.now().microsecondsSinceEpoch}',
                name: name,
                icon: selectedIcon,
                colorValue: selectedColor,
                kind: kind,
                targetCount: target.clamp(1, 9999),
                unit: unitDraft.authoredUnit,
                generatedUnitKey: unitDraft.generatedUnitKey,
                category: habitCategoryOrNull(categoryCtrl.text),
                tags: _parseDesktopHabitTags(tagsCtrl.text),
                flexTarget: useFlex ? flexTarget : null,
                flexPeriod: useFlex ? flexPeriod : null,
                startDate: startDate,
                endDate: endDate,
                activeWeekdays: List<int>.from(activeWeekdays),
                remind: hasReminder,
                remindHour: hasReminder ? sortedTimes.first.hour : null,
                remindMinute: hasReminder ? sortedTimes.first.minute : null,
                reminderPlan: reminderPlan,
              );
              await habitProvider.addHabit(newHabit);
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
              if (mounted) {
                _showFeedback(HabitUiCopy.saveSuccess(locale));
              }
            }

            return Dialog(
              backgroundColor: t.elevatedSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusXl),
                side: BorderSide(
                  color: t.hairlineBorder,
                  width: DesktopWebTokens.hairlineWidth,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(selectedColor).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(
                                DesktopWebTokens.radiusSm,
                              ),
                            ),
                            child: Icon(
                              habitIconForToken(selectedIcon),
                              size: 18,
                              color: Color(selectedColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isEn ? 'Create Habit' : '新建习惯',
                              style: t.cardTitleStyle,
                            ),
                          ),
                          IconButton(
                            tooltip: I18n.trForLocale('action.close', locale),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: saving
                                ? null
                                : () => Navigator.of(dialogCtx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 0.6, color: t.hairlineBorder),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEn ? 'Quick Templates' : '热门模板一键填充',
                              style: t.captionStyle,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final tpl in templates)
                                  ActionChip(
                                    avatar: Icon(
                                      tpl.icon,
                                      size: 15,
                                      color: Color(tpl.colorValue),
                                    ),
                                    label: Text(
                                      tpl.localizedName,
                                      style: t.captionStyle.copyWith(
                                        color: t.textPrimary,
                                      ),
                                    ),
                                    onPressed: saving
                                        ? null
                                        : () => setSt(() {
                                            kind = HabitKind.positive;
                                            nameCtrl.text = tpl.localizedName;
                                            categoryCtrl.text =
                                                tpl.localizedCategory;
                                            targetCtrl.text = tpl.targetCount
                                                .toString();
                                            unitDraft.selectGenerated(
                                              tpl.generatedUnitKey,
                                            );
                                            selectedColor = tpl.colorValue;
                                            selectedIcon =
                                                habitIconTokenForIcon(tpl.icon);
                                            flexEnabled = tpl.hasFlexRule;
                                            if (tpl.hasFlexRule) {
                                              flexPeriod = tpl.flexPeriod!;
                                              flexTargetCtrl.text =
                                                  tpl.flexTarget!.toString();
                                            }
                                          }),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: Text(isEn ? 'Build habit' : '正向养成'),
                                  selected: kind == HabitKind.positive,
                                  onSelected: saving
                                      ? null
                                      : (_) => setSt(() {
                                          kind = HabitKind.positive;
                                        }),
                                ),
                                ChoiceChip(
                                  label: Text(isEn ? 'Avoid habit' : '反向戒除'),
                                  selected: kind == HabitKind.negative,
                                  onSelected: saving
                                      ? null
                                      : (_) => setSt(() {
                                          kind = HabitKind.negative;
                                          flexEnabled = false;
                                        }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              enabled: !saving,
                              controller: nameCtrl,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: isEn ? 'Habit name' : '习惯名称',
                                hintText: isEn
                                    ? 'e.g. Drink 8 cups of water'
                                    : '例如：每日喝水、阅读 30 分钟',
                                prefixIcon: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    enabled: !saving,
                                    controller: categoryCtrl,
                                    decoration: InputDecoration(
                                      labelText: isEn ? 'Group' : '分组',
                                      hintText: isEn
                                          ? 'Health, Learning...'
                                          : '身体健康、学习提升…',
                                      prefixIcon: const Icon(
                                        Icons.folder_outlined,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    enabled: !saving,
                                    controller: targetCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: isEn ? 'Target' : '每日目标',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 100,
                                  child: HabitUnitField(
                                    draft: unitDraft,
                                    targetController: targetCtrl,
                                    locale: locale,
                                    enabled: !saving,
                                    maximumTarget: 9999,
                                    onChanged: (v) =>
                                        setSt(() => unitDraft.recordEdit(v)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              enabled: !saving,
                              controller: tagsCtrl,
                              decoration: InputDecoration(
                                labelText: isEn ? 'Tags' : '标签',
                                hintText: isEn
                                    ? 'Comma separated, e.g. morning, health'
                                    : '逗号或空格分隔，例如 晨间, 健康',
                                prefixIcon: const Icon(
                                  Icons.sell_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              isEn ? 'Icon & Color' : '图标与色彩',
                              style: t.captionStyle,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final iconData in _desktopHabitIcons)
                                  Builder(
                                    builder: (_) {
                                      final token = habitIconTokenForIcon(
                                        iconData,
                                      );
                                      final active = selectedIcon == token;
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(
                                          DesktopWebTokens.radiusSm,
                                        ),
                                        onTap: saving
                                            ? null
                                            : () => setSt(
                                                () => selectedIcon = token,
                                              ),
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? Color(selectedColor)
                                                      .withValues(alpha: 0.16)
                                                : t.mutedSurface,
                                            borderRadius: BorderRadius.circular(
                                              DesktopWebTokens.radiusSm,
                                            ),
                                            border: Border.all(
                                              color: active
                                                  ? Color(selectedColor)
                                                  : t.hairlineBorder,
                                              width: active ? 1.2 : 0.6,
                                            ),
                                          ),
                                          child: Icon(
                                            iconData,
                                            size: 16,
                                            color: active
                                                ? Color(selectedColor)
                                                : t.textSecondary,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in _desktopHabitColors)
                                  InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: saving
                                        ? null
                                        : () => setSt(() => selectedColor = c),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Color(c),
                                        shape: BoxShape.circle,
                                        border: selectedColor == c
                                            ? Border.all(
                                                color: t.textPrimary,
                                                width: 1.6,
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (kind == HabitKind.positive) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isEn
                                          ? 'Flexible weekly/monthly goal'
                                          : '弹性周期目标（每周/每月 N 次）',
                                      style: t.bodyStyle,
                                    ),
                                  ),
                                  Switch(
                                    value: flexEnabled,
                                    onChanged: saving
                                        ? null
                                        : (v) => setSt(() => flexEnabled = v),
                                  ),
                                ],
                              ),
                              if (flexEnabled) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    SegmentedButton<HabitFlexPeriod>(
                                      showSelectedIcon: false,
                                      segments: [
                                        ButtonSegment(
                                          value: HabitFlexPeriod.week,
                                          label: Text(
                                            I18n.trForLocale(
                                              'habit.flex.weekly',
                                              locale,
                                            ),
                                          ),
                                        ),
                                        ButtonSegment(
                                          value: HabitFlexPeriod.month,
                                          label: Text(
                                            I18n.trForLocale(
                                              'habit.flex.monthly',
                                              locale,
                                            ),
                                          ),
                                        ),
                                      ],
                                      selected: {flexPeriod},
                                      onSelectionChanged: (sel) => setSt(
                                        () => flexPeriod = sel.first,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 110,
                                      child: TextField(
                                        enabled: !saving,
                                        controller: flexTargetCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          labelText: I18n.trForLocale(
                                            'habit.flex.period_target',
                                            locale,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                            const SizedBox(height: 14),
                            HabitDateRangeFields(
                              startDate: startDate,
                              endDate: endDate,
                              onStartChanged: (v) =>
                                  setSt(() => startDate = v),
                              onEndChanged: (v) => setSt(() => endDate = v),
                            ),
                            const SizedBox(height: 14),
                            HabitActiveWeekdayPicker(
                              weekdays: activeWeekdays,
                              onChanged: (v) =>
                                  setSt(() => activeWeekdays = v),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(
                                  Icons.notifications_none_outlined,
                                  size: 18,
                                  color: t.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isEn ? 'Check-in reminder' : '打卡提醒',
                                    style: t.bodyStyle,
                                  ),
                                ),
                                Switch(
                                  value: remindEnabled,
                                  onChanged: saving
                                      ? null
                                      : (v) =>
                                          setSt(() => remindEnabled = v),
                                ),
                              ],
                            ),
                            if (remindEnabled) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (var i = 0; i < remindTimes.length; i++)
                                    InputChip(
                                      avatar: const Icon(
                                        Icons.schedule_outlined,
                                        size: 15,
                                      ),
                                      label: Text(
                                        AppTimePicker.format(remindTimes[i]),
                                      ),
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final picked =
                                                  await AppTimePicker.show(
                                                    dialogCtx,
                                                    initialTime:
                                                        remindTimes[i],
                                                    title: isEn
                                                        ? 'Reminder time'
                                                        : '提醒时间',
                                                    minuteStep: 5,
                                                  );
                                              if (picked != null &&
                                                  dialogCtx.mounted) {
                                                setSt(
                                                  () =>
                                                      remindTimes[i] = picked,
                                                );
                                              }
                                            },
                                      onDeleted: remindTimes.length <= 1
                                          ? null
                                          : () => setSt(
                                              () => remindTimes.removeAt(i),
                                            ),
                                    ),
                                  ActionChip(
                                    avatar: const Icon(Icons.add, size: 15),
                                    label: Text(isEn ? 'Add time' : '添加时间'),
                                    onPressed: saving
                                        ? null
                                        : () async {
                                            final picked =
                                                await AppTimePicker.show(
                                                  dialogCtx,
                                                  initialTime: TimeOfDay.now(),
                                                  title: isEn
                                                      ? 'Reminder time'
                                                      : '提醒时间',
                                                  minuteStep: 5,
                                                );
                                            if (picked != null &&
                                                dialogCtx.mounted) {
                                              setSt(() {
                                                if (!remindTimes.any(
                                                  (e) =>
                                                      e.hour == picked.hour &&
                                                      e.minute ==
                                                          picked.minute,
                                                )) {
                                                  remindTimes.add(picked);
                                                }
                                              });
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, thickness: 0.6, color: t.hairlineBorder),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(dialogCtx).pop(),
                            child: Text(
                              I18n.trForLocale('action.cancel', locale),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: saving ? null : submit,
                            child: Text(
                              isEn ? 'Create Habit' : '开启新习惯',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final provider = context.watch<HabitProvider>();
        final firstDayOfWeek = context.select<PreferencesProvider?, int>(
          (prefs) => prefs?.firstDayOfWeek ?? DateTime.monday,
        );
        final t = DesktopWebTokens.of(context);
        final isEn = locale == AppLocale.en;
        final now = DateTime.now();
        final today = _dateOnly(now);
        final normalizedFirstDay = ((firstDayOfWeek - 1) % 7) + 1;
        final daysSinceWeekStart = (today.weekday - normalizedFirstDay + 7) % 7;
        final weekStart = today.subtract(Duration(days: daysSinceWeekStart));
        final weekDays = List<DateTime>.generate(
          7,
          (i) => weekStart.add(Duration(days: i)),
          growable: false,
        );
        final allHabits = provider.habits;
        final endedCount = provider.endedHabits.length;
        final allTags = provider.allTags;
        final effectiveTag = (_selectedTag != null && allTags.contains(_selectedTag))
            ? _selectedTag
            : null;
        final activeTodayHabits = allHabits
            .where((h) => h.isActiveToday())
            .toList(growable: false);
        final completedTodayCount = activeTodayHabits
            .where((h) => h.isCompletedToday())
            .length;
        final completionRate = provider.todayCompletionRate;
        final bestStreak = provider.longestBestStreak;
        final currentStreak = provider.longestCurrentStreak;

        _syncTopBar(
          context,
          locale: locale,
          completedToday: completedTodayCount,
          activeTodayCount: activeTodayHabits.length,
          totalCount: provider.activeHabits.length,
        );

        final categories = _collectCategories(allHabits, locale);
        final effectiveCategory =
            _selectedCategory == _allCategoryToken ||
                categories.contains(_selectedCategory)
            ? _selectedCategory
            : _allCategoryToken;

        final filteredHabits = allHabits.where((h) {
          if (_statusFilter == _DesktopHabitStatusFilter.active && h.isEnded) {
            return false;
          }
          if (_statusFilter == _DesktopHabitStatusFilter.archived && !h.isEnded) {
            return false;
          }
          if (_onlyScheduledToday && !h.isActiveToday()) return false;
          if (effectiveCategory != _allCategoryToken) {
            final label = _displayCategory(h.category, locale);
            if (label != effectiveCategory) return false;
          }
          if (effectiveTag != null && !h.tags.contains(effectiveTag)) {
            return false;
          }
          return true;
        }).toList(growable: false);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DesktopWebTokens.contentMaxWidth,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final innerWidth = math.max(
                  0.0,
                  constraints.maxWidth - (DesktopWebTokens.space2xl * 2),
                );
                final cols = innerWidth >= 1080
                    ? 3
                    : (innerWidth >= 660 ? 2 : 1);
                final rowCount = (filteredHabits.length + cols - 1) ~/ cols;
                final hasGrid =
                    allHabits.isNotEmpty && filteredHabits.isNotEmpty;

                return CustomScrollView(
                  key: const ValueKey('desktop_habit_view'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        DesktopWebTokens.space2xl,
                        DesktopWebTokens.spaceXl,
                        DesktopWebTokens.space2xl,
                        hasGrid
                            ? DesktopWebTokens.spaceLg
                            : DesktopWebTokens.space3xl,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HabitMetricsSummaryBar(
                              key: const ValueKey('desktop_habit_metrics_bar'),
                              locale: locale,
                              completedToday: completedTodayCount,
                              activeTodayTotal: activeTodayHabits.length,
                              todayCheckinCount: provider.todayTotalCompletions,
                              completionRate: completionRate,
                              bestStreak: bestStreak,
                              currentStreak: currentStreak,
                              totalActiveHabits: allHabits.length,
                            ),
                            if (allHabits.isNotEmpty) ...[
                              const SizedBox(height: DesktopWebTokens.spaceLg),
                              _HabitFilterBar(
                                locale: locale,
                                categories: categories,
                                selectedCategory: effectiveCategory,
                                tags: allTags,
                                selectedTag: effectiveTag,
                                statusFilter: _statusFilter,
                                endedCount: endedCount,
                                onlyScheduledToday: _onlyScheduledToday,
                                showHeatmap: _showHeatmap,
                                onSelectCategory: (cat) =>
                                    setState(() => _selectedCategory = cat),
                                onSelectTag: (tag) =>
                                    setState(() => _selectedTag = tag),
                                onSelectStatusFilter: (status) =>
                                    setState(() => _statusFilter = status),
                                onToggleScheduledToday: (v) =>
                                    setState(() => _onlyScheduledToday = v),
                                onToggleHeatmap: () =>
                                    setState(() => _showHeatmap = !_showHeatmap),
                                onAddHabit: _openCreateDialog,
                              ),
                            ],
                            if (_showHeatmap && allHabits.isNotEmpty) ...[
                              const SizedBox(height: DesktopWebTokens.spaceLg),
                              DesktopPanelCard(
                                padding: const EdgeInsets.all(16),
                                child: HabitHeatmap(
                                  heatmapData: provider.combinedHeatmap(12),
                                ),
                              ),
                            ],
                            if (allHabits.isEmpty) ...[
                              const SizedBox(height: DesktopWebTokens.spaceLg),
                              _HabitStarterEmptyState(
                                key: const ValueKey(
                                  'desktop_habit_empty_state',
                                ),
                                locale: locale,
                                onCreateCustom: _openCreateDialog,
                                onSelectTemplate: _addFromTemplate,
                              ),
                            ] else if (filteredHabits.isEmpty) ...[
                              const SizedBox(height: DesktopWebTokens.spaceLg),
                              DesktopPanelCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 36,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.filter_list_off_outlined,
                                      size: 36,
                                      color: t.textMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isEn
                                          ? 'No habits match the current filter'
                                          : '当前筛选条件下暂无习惯',
                                      style: t.cardTitleStyle,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isEn
                                          ? 'Try clearing filters or add a new habit.'
                                          : '可清除分组或今日生效筛选，或新建一个习惯。',
                                      style: t.bodyMutedStyle,
                                    ),
                                    const SizedBox(height: 14),
                                    OutlinedButton(
                                      onPressed: () => setState(() {
                                        _selectedCategory = _allCategoryToken;
                                        _selectedTag = null;
                                        _statusFilter =
                                            _DesktopHabitStatusFilter.active;
                                        _onlyScheduledToday = false;
                                      }),
                                      child: Text(
                                        isEn ? 'Clear filters' : '重置筛选',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (hasGrid)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          DesktopWebTokens.space2xl,
                          0,
                          DesktopWebTokens.space2xl,
                          DesktopWebTokens.space3xl,
                        ),
                        sliver: SliverList.builder(
                          itemCount: rowCount,
                          itemBuilder: (context, row) {
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: row == rowCount - 1
                                    ? 0
                                    : DesktopWebTokens.spaceLg,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var col = 0; col < cols; col++) ...[
                                    if (col > 0)
                                      const SizedBox(
                                        width: DesktopWebTokens.spaceLg,
                                      ),
                                    Expanded(
                                      child: (row * cols + col) <
                                              filteredHabits.length
                                          ? RepaintBoundary(
                                              child: _DesktopHabitMatrixCard(
                                                habit: filteredHabits[
                                                    row * cols + col],
                                                locale: locale,
                                                firstDayOfWeek: firstDayOfWeek,
                                                now: now,
                                                today: today,
                                                weekDays: weekDays,
                                                onCheckIn: () => _handleCheckIn(
                                                  filteredHabits[
                                                      row * cols + col],
                                                ),
                                                onUndo: () => _handleUndo(
                                                  filteredHabits[
                                                      row * cols + col],
                                                ),
                                                onToggleDate: (day) =>
                                                    _toggleDayDot(
                                                      filteredHabits[
                                                          row * cols + col],
                                                      day,
                                                    ),
                                                onOpenDetail: () => _openDetail(
                                                  filteredHabits[
                                                      row * cols + col],
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<String> _collectCategories(List<Habit> habits, AppLocale locale) {
    final seen = <String>{};
    final result = <String>[];
    for (final h in habits) {
      final label = _displayCategory(h.category, locale);
      if (seen.add(label)) {
        result.add(label);
      }
    }
    return result;
  }

  String _displayCategory(String? rawCategory, AppLocale locale) {
    final normalized = normalizeHabitCategory(rawCategory);
    if (normalized == defaultHabitCategoryName) {
      return I18n.trForLocale('habit.group.ungrouped', locale);
    }
    return normalized;
  }
}

class _HabitMetricsSummaryBar extends StatelessWidget {
  final AppLocale locale;
  final int completedToday;
  final int activeTodayTotal;
  final int todayCheckinCount;
  final double completionRate;
  final int bestStreak;
  final int currentStreak;
  final int totalActiveHabits;

  const _HabitMetricsSummaryBar({
    super.key,
    required this.locale,
    required this.completedToday,
    required this.activeTodayTotal,
    required this.todayCheckinCount,
    required this.completionRate,
    required this.bestStreak,
    required this.currentStreak,
    required this.totalActiveHabits,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = locale == AppLocale.en;
    final t = DesktopWebTokens.of(context);
    final ratePercent = (completionRate * 100).round();
    final dayUnit = isEn ? 'd' : '天';

    final cards = [
      _MetricTile(
        icon: Icons.task_alt_rounded,
        iconColor: t.success,
        label: isEn ? 'Checked In Today' : '今日已打卡',
        value: '$completedToday / $activeTodayTotal',
        caption: isEn
            ? '$todayCheckinCount total check-ins'
            : '累计记录 $todayCheckinCount 次',
      ),
      _MetricTile(
        icon: Icons.pie_chart_outline_rounded,
        iconColor: t.accent,
        label: isEn ? 'Completion Rate' : '打卡率',
        value: '$ratePercent%',
        caption: isEn
            ? (ratePercent >= 100 && activeTodayTotal > 0
                  ? 'All goals met today'
                  : 'Scheduled for today')
            : (ratePercent >= 100 && activeTodayTotal > 0
                  ? '今日习惯已全部达标'
                  : '基于今日生效习惯计算'),
      ),
      _MetricTile(
        icon: Icons.local_fire_department_outlined,
        iconColor: t.warning,
        label: isEn ? 'Best Streak' : '最佳连胜',
        value: '$bestStreak $dayUnit',
        caption: isEn
            ? 'Current peak: $currentStreak $dayUnit'
            : '当前最高连胜 $currentStreak $dayUnit',
      ),
      _MetricTile(
        icon: Icons.repeat_rounded,
        iconColor: t.info,
        label: isEn ? 'Active Habits' : '活跃习惯数',
        value: '$totalActiveHabits',
        caption: isEn
            ? '$activeTodayTotal scheduled today'
            : '今日生效 $activeTodayTotal 项',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: DesktopWebTokens.spaceMd),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: DesktopWebTokens.spaceMd,
          runSpacing: DesktopWebTokens.spaceMd,
          children: [
            for (final card in cards)
              SizedBox(
                width: math.max(
                  180.0,
                  (constraints.maxWidth - DesktopWebTokens.spaceMd) / 2,
                ),
                child: card,
              ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String caption;

  const _MetricTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    return DesktopPanelCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: t.isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.captionStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.metricValueStyle.copyWith(
                    fontSize: 20,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.captionStyle.copyWith(
                    color: t.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _HabitFilterBar extends StatelessWidget {
  final AppLocale locale;
  final List<String> categories;
  final String selectedCategory;
  final List<String> tags;
  final String? selectedTag;
  final _DesktopHabitStatusFilter statusFilter;
  final int endedCount;
  final bool onlyScheduledToday;
  final bool showHeatmap;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<String?> onSelectTag;
  final ValueChanged<_DesktopHabitStatusFilter> onSelectStatusFilter;
  final ValueChanged<bool> onToggleScheduledToday;
  final VoidCallback onToggleHeatmap;
  final VoidCallback onAddHabit;

  const _HabitFilterBar({
    required this.locale,
    required this.categories,
    required this.selectedCategory,
    required this.tags,
    required this.selectedTag,
    required this.statusFilter,
    required this.endedCount,
    required this.onlyScheduledToday,
    required this.showHeatmap,
    required this.onSelectCategory,
    required this.onSelectTag,
    required this.onSelectStatusFilter,
    required this.onToggleScheduledToday,
    required this.onToggleHeatmap,
    required this.onAddHabit,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = locale == AppLocale.en;
    final t = DesktopWebTokens.of(context);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterPill(
              key: const ValueKey('desktop_habit_filter_all'),
              label: isEn ? 'All' : '全部',
              selected: selectedCategory == _allCategoryToken,
              onTap: () => onSelectCategory(_allCategoryToken),
            ),
            for (final category in categories)
              _FilterPill(
                key: ValueKey('desktop_habit_filter_cat_$category'),
                label: category,
                selected: selectedCategory == category,
                onTap: () => onSelectCategory(category),
              ),
            const SizedBox(width: 4),
            _FilterPill(
              key: const ValueKey('desktop_habit_filter_today'),
              icon: Icons.today_outlined,
              label: isEn ? 'Today only' : '仅今日生效',
              selected: onlyScheduledToday,
              onTap: () => onToggleScheduledToday(!onlyScheduledToday),
            ),
            _FilterPill(
              key: const ValueKey('desktop_habit_filter_heatmap'),
              icon: Icons.grid_view_rounded,
              label: isEn ? '12w Heatmap' : '热力图',
              selected: showHeatmap,
              onTap: onToggleHeatmap,
            ),
            _FilterPill(
              key: const ValueKey('desktop_habit_status_active'),
              label: isEn ? 'Active' : '进行中',
              selected: statusFilter == _DesktopHabitStatusFilter.active,
              onTap: () => onSelectStatusFilter(_DesktopHabitStatusFilter.active),
            ),
            _FilterPill(
              key: const ValueKey('desktop_habit_filter_archived'),
              icon: Icons.archive_outlined,
              label: isEn ? 'Archived ($endedCount)' : '已结束 ($endedCount)',
              selected: statusFilter == _DesktopHabitStatusFilter.archived,
              onTap: () => onSelectStatusFilter(
                statusFilter == _DesktopHabitStatusFilter.archived
                    ? _DesktopHabitStatusFilter.active
                    : _DesktopHabitStatusFilter.archived,
              ),
            ),
            for (final tag in tags)
              _FilterPill(
                key: ValueKey('desktop_habit_filter_tag_$tag'),
                label: '#$tag',
                selected: selectedTag == tag,
                onTap: () => onSelectTag(selectedTag == tag ? null : tag),
              ),
          ],
        ),
        FilledButton.icon(
          key: const ValueKey('desktop_habit_add_button'),
          onPressed: onAddHabit,
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            isEn ? 'New Habit' : '新建习惯',
            style: t.bodyStyle.copyWith(color: t.accentForeground),
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    return Material(
      color: selected ? t.accentSoft : t.panelSurface,
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            border: Border.all(
              color: selected ? t.accentBorder : t.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? t.accent : t.textSecondary,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: t.captionStyle.copyWith(
                  color: selected ? t.accent : t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopHabitMatrixCard extends StatelessWidget {
  final Habit habit;
  final AppLocale locale;
  final int firstDayOfWeek;
  final DateTime now;
  final DateTime today;
  final List<DateTime> weekDays;
  final VoidCallback onCheckIn;
  final VoidCallback onUndo;
  final ValueChanged<DateTime> onToggleDate;
  final VoidCallback onOpenDetail;

  const _DesktopHabitMatrixCard({
    required this.habit,
    required this.locale,
    required this.firstDayOfWeek,
    required this.now,
    required this.today,
    required this.weekDays,
    required this.onCheckIn,
    required this.onUndo,
    required this.onToggleDate,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;

    final isNegative = habit.kind == HabitKind.negative;
    final isActiveToday = habit.isActiveToday();
    final todayCount = habit.todayCount();
    final isDoneToday = habit.isCompletedToday();
    final flexProgress = habit.flexProgressForDate(now);
    final isFlexCompleted = flexProgress?.isCompleted ?? false;
    final isDailyTargetMet = todayCount >= habit.targetCount;
    final canCheckIn =
        isActiveToday &&
        (isNegative ||
            (habit.hasFlexRule
                ? !isFlexCompleted && !isDailyTargetMet
                : !isDoneToday));
    final hasNegativeOccurrence = isNegative && todayCount > 0;
    final baseColor = hasNegativeOccurrence ? t.danger : Color(habit.colorValue);
    final progress = habit.todayProgress().clamp(0.0, 1.0);
    final progressBarColor = isDoneToday && !hasNegativeOccurrence
        ? t.success
        : baseColor;
    final streakUnit = !habit.hasFlexRule
        ? I18n.trForLocale('unit.day', locale)
        : switch (habit.flexPeriod!) {
            HabitFlexPeriod.week => I18n.trForLocale('habit.unit.week', locale),
            HabitFlexPeriod.month => I18n.trForLocale(
              'habit.unit.month',
              locale,
            ),
          };
    final countSummary = habit.formatCountForDate(now, locale: locale);

    final checkInLabel = !isActiveToday
        ? (isEn ? 'Rest day' : '今日休息')
        : isNegative
        ? (isEn ? 'Record' : '记录一次')
        : canCheckIn
        ? (isEn ? '+1 Check in' : '+1 打卡')
        : (isEn ? 'Done today' : '今日已完成');

    return DesktopPanelCard(
      key: ValueKey('desktop_habit_card_${habit.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title + Streak + Menu
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onOpenDetail,
                borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: baseColor.withValues(alpha: t.isDark ? 0.22 : 0.13),
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusMd,
                    ),
                    border: Border.all(
                      color: baseColor.withValues(alpha: 0.24),
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Icon(
                    habitDisplayIconFor(habit),
                    size: 19,
                    color: baseColor,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: InkWell(
                  onTap: onOpenDetail,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusXs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.cardTitleStyle.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _habitSubtitle(habit, locale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.captionStyle,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: isEn
                    ? 'Best streak: ${habit.bestStreak} $streakUnit'
                    : '最佳连胜：${habit.bestStreak} $streakUnit',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: t.warning.withValues(alpha: t.isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(
                      DesktopWebTokens.radiusPill,
                    ),
                    border: Border.all(
                      color: t.warning.withValues(alpha: 0.24),
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 13,
                        color: t.warning,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${habit.currentStreak} $streakUnit',
                        style: t.captionStyle.copyWith(
                          color: t.warning,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: HabitUiCopy.moreActions(locale),
                icon: Icon(Icons.more_horiz, size: 18, color: t.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                onSelected: (action) => _onMenuAction(context, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'detail',
                    child: Text(isEn ? 'Details' : '查看详情'),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(HabitUiCopy.actionEdit(locale)),
                  ),
                  PopupMenuItem(
                    value: 'note',
                    child: Text(isEn ? 'Today reflection' : '今日心得笔记'),
                  ),
                  if (habit.isActiveToday() && !habit.isCompletedToday())
                    PopupMenuItem(
                      value: 'freeze',
                      child: Text(
                        habit.isFrozenForDate(now)
                            ? (isEn ? 'Remove today rest pass' : '取消今日休息卡')
                            : (isEn ? 'Use rest pass today' : '今日用休息卡保连胜'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'backfill',
                    child: Text(isEn ? 'Backfill date...' : '选日期补卡...'),
                  ),
                  if (habit.isEnded)
                    PopupMenuItem(
                      value: 'reopen',
                      child: Text(isEn ? 'Reactivate' : '重新启用'),
                    )
                  else
                    PopupMenuItem(
                      value: 'end',
                      child: Text(HabitUiCopy.actionEnd(locale)),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      HabitUiCopy.actionDelete(locale),
                      style: TextStyle(color: t.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 7-day Mon-Sun Check-in Matrix
          Container(
            key: ValueKey('desktop_habit_matrix_${habit.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: t.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
              border: Border.all(
                color: t.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final day in weekDays)
                  _HabitWeekMatrixDot(
                    key: ValueKey(
                      'desktop_habit_dot_${habit.id}_${day.weekday}',
                    ),
                    habit: habit,
                    day: day,
                    today: today,
                    accentColor: baseColor,
                    locale: locale,
                    onTap: () => onToggleDate(day),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (habit.tags.isNotEmpty ||
              habit.isFrozenForDate(now) ||
              habit.noteForDate(now) != null ||
              habit.isEnded) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (habit.isEnded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.mutedSurface,
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                    ),
                    child: Text(
                      isEn ? 'Archived' : '已结束',
                      style: t.captionStyle.copyWith(color: t.textMuted),
                    ),
                  ),
                if (habit.isFrozenForDate(now))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.info.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.ac_unit_outlined, size: 11, color: t.info),
                        const SizedBox(width: 3),
                        Text(
                          isEn ? 'Rest pass active' : '休息卡生效中',
                          style: t.captionStyle.copyWith(color: t.info),
                        ),
                      ],
                    ),
                  ),
                for (final tag in habit.tags.take(3))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
                    ),
                    child: Text(
                      '#$tag',
                      style: t.captionStyle.copyWith(color: t.accent),
                    ),
                  ),
              ],
            ),
            if (habit.noteForDate(now) != null) ...[
              const SizedBox(height: 6),
              Text(
                habit.noteForDate(now)!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.captionStyle.copyWith(color: t.textSecondary),
              ),
            ],
            const SizedBox(height: 10),
          ],

          // Today's progress bar + count
          Row(
            children: [
              Expanded(
                child: Text(
                  countSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.captionStyle.copyWith(
                    color: t.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                isActiveToday
                    ? (isDoneToday && !hasNegativeOccurrence
                          ? (isEn ? 'Completed' : '已达标')
                          : '${(progress * 100).round()}%')
                    : (isEn ? 'Inactive' : '今日休息'),
                style: t.captionStyle.copyWith(
                  color: isDoneToday && !hasNegativeOccurrence
                      ? t.success
                      : t.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
            child: Stack(
              children: [
                Container(
                  height: 5,
                  color: t.hairlineBorder,
                ),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    height: 5,
                    color: progressBarColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Bottom action row: +1 Check-in + Undo + Note + Detail (or Reopen if ended)
          Row(
            children: [
              if (habit.isEnded)
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey('desktop_habit_reopen_${habit.id}'),
                    onPressed: () =>
                        context.read<HabitProvider>().reopenHabit(habit.id),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.replay_outlined, size: 16),
                    label: Text(isEn ? 'Reactivate' : '重新启用'),
                  ),
                )
              else ...[
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey('desktop_habit_checkin_${habit.id}'),
                    onPressed: canCheckIn ? onCheckIn : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: canCheckIn ? baseColor : t.mutedSurface,
                      foregroundColor: canCheckIn
                          ? appReadableForeground(baseColor, Colors.white)
                          : t.textMuted,
                      disabledBackgroundColor: t.mutedSurface,
                      disabledForegroundColor: t.textMuted,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: Icon(
                      canCheckIn
                          ? (isNegative ? Icons.info_outline : Icons.add_rounded)
                          : Icons.check_rounded,
                      size: 16,
                    ),
                    label: Text(
                      checkInLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (todayCount > 0) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: isEn ? 'Undo once' : '撤回一次',
                    child: OutlinedButton(
                      key: ValueKey('desktop_habit_undo_${habit.id}'),
                      onPressed: onUndo,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(36, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: BorderSide(
                          color: t.hairlineBorder,
                          width: DesktopWebTokens.hairlineWidth,
                        ),
                      ),
                      child: const Icon(Icons.undo_rounded, size: 16),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Tooltip(
                  message: isEn ? 'Today reflection' : '心得笔记',
                  child: OutlinedButton(
                    key: ValueKey('desktop_habit_note_${habit.id}'),
                    onPressed: () => _openNoteDialog(context, now),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: BorderSide(
                        color: habit.noteForDate(now) != null
                            ? t.accentBorder
                            : t.hairlineBorder,
                        width: DesktopWebTokens.hairlineWidth,
                      ),
                    ),
                    child: Icon(
                      habit.noteForDate(now) != null
                          ? Icons.sticky_note_2_outlined
                          : Icons.edit_note_outlined,
                      size: 16,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: isEn ? 'Habit Details' : '习惯详情',
                child: OutlinedButton(
                  onPressed: onOpenDetail,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(
                      color: t.hairlineBorder,
                      width: DesktopWebTokens.hairlineWidth,
                    ),
                  ),
                  child: const Icon(Icons.open_in_new_rounded, size: 15),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _habitSubtitle(Habit habit, AppLocale locale) {
    final isEn = locale == AppLocale.en;
    final category = normalizeHabitCategory(habit.category) ==
            defaultHabitCategoryName
        ? I18n.trForLocale('habit.group.ungrouped', locale)
        : habit.category!.trim();
    if (habit.kind == HabitKind.negative) {
      return '$category · ${isEn ? 'Avoid' : '戒除习惯'}';
    }
    if (habit.hasFlexRule) {
      return '$category · ${habit.flexPeriodGoalLabelFor(locale)}';
    }
    final unit = HabitUiCopy.measurementUnit(
      habit.targetCount,
      authoredUnit: habit.unit,
      generatedUnitKey: habit.generatedUnitKey,
      locale: locale,
    );
    return '$category · ${habit.targetCount} $unit/${isEn ? 'day' : '天'}';
  }

  Future<void> _onMenuAction(BuildContext context, String action) async {
    if (action == 'detail') {
      onOpenDetail();
      return;
    }
    final origin = HabitActionOrigin.capture(context);
    if (origin == null) return;
    if (action == 'edit') {
      await showHabitEditor(context, habit, actionOrigin: origin);
      return;
    }
    if (action == 'note') {
      await _openNoteDialog(context, DateTime.now());
      return;
    }
    if (action == 'freeze') {
      await origin.habitProvider.toggleStreakFreezeForDate(
        habit.id,
        DateTime.now(),
      );
      return;
    }
    if (action == 'backfill') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final picked = await AppDatePicker.pickSolar(
        context,
        initialDate: today,
        firstDate: DateTime(2000),
        lastDate: today,
        title: locale == AppLocale.en ? 'Backfill date' : '选日期补卡',
      );
      if (picked != null && context.mounted && habit.activeForDate(picked)) {
        await origin.habitProvider.incrementHabitForDate(habit.id, picked);
      }
      return;
    }
    if (action == 'reopen') {
      await origin.habitProvider.reopenHabit(habit.id);
      return;
    }
    if (action == 'end') {
      final ok = await confirmHabitEnd(context, habit, origin: origin);
      if (ok && context.mounted) {
        await origin.habitProvider.endHabit(habit.id);
      }
      return;
    }
    if (action == 'delete') {
      final ok = await confirmHabitDelete(context, habit, origin: origin);
      if (ok && context.mounted) {
        await origin.habitProvider.deleteHabit(habit.id);
      }
    }
  }

  Future<void> _openNoteDialog(BuildContext context, DateTime date) async {
    final provider = context.read<HabitProvider>();
    final isEn = locale == AppLocale.en;
    final ctrl = TextEditingController(text: habit.noteForDate(date) ?? '');
    try {
      final saved = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            isEn
                ? 'Reflection (${AppDateFormat.date(ctx, date)})'
                : '打卡心得 (${AppDateFormat.date(ctx, date)})',
          ),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: isEn
                  ? 'Add a reflection note...'
                  : '写下今天打卡的感想或笔记…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(I18n.trForLocale('action.cancel', locale)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: Text(I18n.trForLocale('action.save', locale)),
            ),
          ],
        ),
      );
      if (saved != null && context.mounted) {
        await provider.setHabitCheckinNote(habit.id, date, saved);
      }
    } finally {
      ctrl.dispose();
    }
  }
}

class _HabitWeekMatrixDot extends StatelessWidget {
  final Habit habit;
  final DateTime day;
  final DateTime today;
  final Color accentColor;
  final AppLocale locale;
  final VoidCallback onTap;

  const _HabitWeekMatrixDot({
    super.key,
    required this.habit,
    required this.day,
    required this.today,
    required this.accentColor,
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;
    final isFuture = day.isAfter(today);
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final isActive = habit.activeForDate(day);
    final count = habit.countForDate(day);
    final completed = habit.isCompletedForDate(day);
    final partial =
        habit.kind == HabitKind.positive && count > 0 && !completed;
    final negativeOccurred =
        habit.kind == HabitKind.negative && count > 0 && !isFuture;

    const zhLabels = ['一', '二', '三', '四', '五', '六', '日'];
    const enLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final dayLabel = (isEn ? enLabels : zhLabels)[day.weekday - 1];

    Color fillColor;
    Color borderColor;
    Color fgColor;
    IconData? dotIcon;

    if (isFuture || !isActive) {
      fillColor = Colors.transparent;
      borderColor = t.hairlineBorder.withValues(alpha: t.hairlineBorder.a * 0.65);
      fgColor = t.textMuted.withValues(alpha: 0.45);
      dotIcon = !isActive ? Icons.remove : null;
    } else if (negativeOccurred) {
      fillColor = t.danger.withValues(alpha: 0.18);
      borderColor = t.danger;
      fgColor = t.danger;
      dotIcon = Icons.close_rounded;
    } else if (completed) {
      fillColor = accentColor;
      borderColor = accentColor;
      fgColor = appReadableForeground(accentColor, Colors.white);
      dotIcon = Icons.check_rounded;
    } else if (partial) {
      fillColor = accentColor.withValues(alpha: t.isDark ? 0.28 : 0.18);
      borderColor = accentColor;
      fgColor = accentColor;
    } else {
      fillColor = t.panelSurface;
      borderColor = isToday ? t.accent : t.strongBorder;
      fgColor = isToday ? t.accent : t.textMuted;
    }

    final tooltipText =
        '${day.month}/${day.day} ($dayLabel): ${habit.formatCountForDate(day, locale: locale)}';

    final canTap = !isFuture && isActive;
    return Tooltip(
      message: tooltipText,
      child: InkWell(
        onTap: canTap ? onTap : null,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayLabel,
                style: t.captionStyle.copyWith(
                  fontSize: 11,
                  color: isToday ? t.accent : t.textMuted,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: isToday && !completed ? 1.4 : 0.8,
                  ),
                ),
                child: dotIcon != null
                    ? Icon(dotIcon, size: 14, color: fgColor)
                    : partial
                    ? Text(
                        '$count',
                        style: t.captionStyle.copyWith(
                          fontSize: 10,
                          color: fgColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HabitStarterEmptyState extends StatelessWidget {
  final AppLocale locale;
  final VoidCallback onCreateCustom;
  final ValueChanged<HabitTemplate> onSelectTemplate;

  const _HabitStarterEmptyState({
    super.key,
    required this.locale,
    required this.onCreateCustom,
    required this.onSelectTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;
    final starters = _starterTemplateIds
        .map(
          (id) => HabitTemplates.all.firstWhere(
            (tpl) => tpl.id == id,
            orElse: () => HabitTemplates.all.first,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPanelCard(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusLg,
                  ),
                  border: Border.all(
                    color: t.accentBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
                child: Icon(Icons.repeat_rounded, size: 26, color: t.accent),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEn
                          ? 'Start Your Daily Habit Matrix'
                          : '开启你的每日习惯矩阵',
                      style: t.heroTitleStyle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEn
                          ? 'Pick a popular starter template in one click or customize your own cadence.'
                          : '从下方热门模板一键开启，或自定义专属打卡节奏与周目标。',
                      style: t.bodyMutedStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                key: const ValueKey('desktop_habit_add_button'),
                onPressed: onCreateCustom,
                icon: const Icon(Icons.add, size: 18),
                label: Text(isEn ? 'New Habit' : '新建习惯'),
              ),
            ],
          ),
        ),
        const SizedBox(height: DesktopWebTokens.spaceLg),
        Text(
          isEn ? 'Popular Starter Templates' : '热门习惯模板 · 一键添加',
          style: t.sectionHeaderStyle,
        ),
        const SizedBox(height: DesktopWebTokens.spaceMd),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 980
                ? 3
                : (constraints.maxWidth >= 600 ? 2 : 1);
            final rowCount = (starters.length + cols - 1) ~/ cols;
            return Column(
              children: [
                for (var row = 0; row < rowCount; row++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: row == rowCount - 1
                          ? 0
                          : DesktopWebTokens.spaceMd,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var col = 0; col < cols; col++) ...[
                          if (col > 0)
                            const SizedBox(width: DesktopWebTokens.spaceMd),
                          Expanded(
                            child: (row * cols + col) < starters.length
                                ? _StarterTemplateCard(
                                    template: starters[row * cols + col],
                                    locale: locale,
                                    onAdd: () => onSelectTemplate(
                                      starters[row * cols + col],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StarterTemplateCard extends StatelessWidget {
  final HabitTemplate template;
  final AppLocale locale;
  final VoidCallback onAdd;

  const _StarterTemplateCard({
    required this.template,
    required this.locale,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final t = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;
    final color = Color(template.colorValue);
    return DesktopPanelCard(
      key: ValueKey('desktop_habit_starter_${template.id}'),
      padding: const EdgeInsets.all(16),
      onTap: onAdd,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: t.isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
            ),
            child: Icon(template.icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.localizedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.cardTitleStyle.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  '${template.localizedCategory} · ${template.localizedFrequencyLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.captionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: BorderSide(
                color: color.withValues(alpha: 0.35),
                width: DesktopWebTokens.hairlineWidth,
              ),
              foregroundColor: color,
            ),
            icon: const Icon(Icons.add, size: 15),
            label: Text(isEn ? 'Add' : '添加'),
          ),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
