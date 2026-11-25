import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_haptics.dart';
import 'package:provider/provider.dart';
import '../core/account_preference_writes.dart';
import '../core/brand_strings.dart';
import '../core/desktop_tokens.dart';
import '../core/design_tokens.dart';
import '../core/habit_ui_copy.dart';
import '../core/habit_unit_draft.dart';
import '../core/i18n.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/main_ui_copy.dart';
import '../core/habit_grouping.dart';
import '../core/habit_icons.dart';
import '../core/habit_insights.dart';
import '../core/habit_templates.dart';
import '../models/habit.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/habit_active_weekday_picker.dart';
import '../widgets/habit_date_range_fields.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/habit_unit_field.dart';
import '../widgets/habit_weekly_card.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/brand_background.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'habit_detail_screen.dart';

const int _habitHeatmapGroupPreviewLimit = 8;

enum _HabitArchiveFilter { all, active, archived }

List<String> _parseHabitScreenTags(String raw) {
  final seen = <String>{};
  for (final part in raw.split(RegExp(r'[,，\s]+'))) {
    final trimmed = part.trim();
    if (trimmed.isNotEmpty) seen.add(trimmed);
  }
  return seen.toList();
}

class HabitScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  const HabitScreen({super.key});

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _heatmapTabBuilt = false;
  String? _selectedTag;
  _HabitArchiveFilter _archiveFilter = _HabitArchiveFilter.all;
  int? _todayHabitsFingerprint;
  int? _todayHabitsDayKey;
  String? _todayHabitsTag;
  List<Habit>? _cachedActiveHabits;
  int _cachedCompletedTodayCount = 0;

  static int _habitsFingerprint(List<Habit> habits) {
    var fp = habits.length;
    for (final h in habits) {
      fp = Object.hash(
        fp,
        identityHashCode(h),
        h.id,
        h.name,
        h.category,
        h.updatedAt.microsecondsSinceEpoch,
        h.endDate?.millisecondsSinceEpoch,
        h.startDate?.millisecondsSinceEpoch,
        h.targetCount,
        h.flexTarget,
        h.flexPeriod,
        h.currentStreak,
        h.bestStreak,
        h.sortOrder,
        Object.hashAll(h.tags),
        Object.hashAllUnordered(
          h.completions.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
    }
    return fp;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(_markHeatmapTabBuilt);
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _tabCtrl.removeListener(_markHeatmapTabBuilt);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _markHeatmapTabBuilt() {
    if (_heatmapTabBuilt || _tabCtrl.index != 1) return;
    setState(() => _heatmapTabBuilt = true);
  }

  Future<bool> _ensureHabitReminderReady({
    DateTime? scheduledTime,
    String? relatedId,
  }) async {
    final notificationService = context.read<NotificationService?>();
    final granted =
        notificationService == null ||
        (scheduledTime == null
            ? await notificationService.requestPermission()
            : await notificationService.ensureReadyForReminder(
                scheduledTime: scheduledTime,
                issueTitle: I18n.tr('habit.error.reminder_register_failed'),
                relatedId: relatedId,
              ));
    if (!granted && mounted) {
      final issue = notificationService.lastScheduleIssue;
      showHabitSafeFeedback(
        context,
        (locale) =>
            issue?.message ?? HabitUiCopy.notificationsNotGranted(locale),
      );
    }
    return granted;
  }

  Future<void> _showAddDialog() async {
    final rootRoute = ModalRoute.of(context);
    if (rootRoute == null || !rootRoute.isCurrent) return;
    final origin = HabitActionOrigin.capture(context);
    if (origin == null || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController(text: '1');
    final flexTargetCtrl = TextEditingController(text: '5');
    final unitDraft = HabitUnitDraft();
    final categoryCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    var selectedColor = 0xFF4CAF50;
    var selectedIcon = defaultHabitIconToken;
    var selectedKind = HabitKind.positive;
    var flexRuleEnabled = false;
    var selectedFlexPeriod = HabitFlexPeriod.week;
    // 生效星期：0=周一 … 6=周日，默认全 7 天（保持历史行为）。
    var selectedActiveWeekdays = [0, 1, 2, 3, 4, 5, 6];
    DateTime? startDate;
    DateTime? endDate;
    // 习惯打卡默认应用内弹出提醒，支持多个时间（例如每天 8 杯水）。
    final remindTimes = <TimeOfDay>[nextHalfHourTimeOfDay()];

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
    var saving = false;
    Habit? completedResult;
    ModalRoute<dynamic>? ownedSheet;

    await showAppModalSheet(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => StatefulBuilder(
          builder: (ctx, setSt) {
            ownedSheet ??= ModalRoute.of(ctx);
            void changeDraft(VoidCallback change) {
              final route = ModalRoute.of(ctx);
              if (saving ||
                  !ctx.mounted ||
                  route == null ||
                  !origin.isValid(ctx, specificRoute: route)) {
                return;
              }
              setSt(change);
            }

            final s = context.read<ThemeProvider>().brand.strings;
            final isEn = locale == AppLocale.en;
            final templatesByCategory = HabitTemplates.byCategory;
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;
            final isDark = theme.brightness == Brightness.dark;
            final surfaceStyle = appSurfaceStyleOf(ctx);
            final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
            final isDefaultIos = surfaceStyle == AppSurfaceStyle.ios;
            final isPriorityTheme = !isDark && (isDefaultIos || isLiquidGlass);

            final sheetSurface =
                isLiquidGlass && surfaceStyle?.cardFillColor != null
                    ? Color.alphaBlend(surfaceStyle!.cardFillColor!, cs.surface)
                    : null;
            final compositedSheetBg = sheetSurface ?? cs.surface;
            final cardSurface =
                isLiquidGlass && surfaceStyle?.cardFillColor != null
                    ? Color.alphaBlend(
                        surfaceStyle!.cardFillColor!,
                        compositedSheetBg,
                      )
                    : cs.surface;

            final headingColor = isPriorityTheme
                ? appReadableForeground(compositedSheetBg, cs.onSurface)
                : cs.onSurface;
            final categoryColor = isPriorityTheme
                ? appReadableForeground(compositedSheetBg, cs.onSurfaceVariant)
                : cs.onSurfaceVariant;
            final reminderGuidanceColor = isPriorityTheme
                ? appReadableForeground(compositedSheetBg, cs.onSurfaceVariant)
                : cs.onSurfaceVariant;
            final ruleGuidanceColor = isPriorityTheme
                ? appReadableForeground(cardSurface, cs.onSurfaceVariant)
                : cs.onSurfaceVariant;

            final scaledRecommendationHeight =
                MediaQuery.textScalerOf(ctx).scale(13.0) + 24.0;
            final recommendationRowHeight = scaledRecommendationHeight < 44.0
                ? 44.0
                : scaledRecommendationHeight;
            return AppSurfaceCard(
              color: sheetSurface,
              margin: EdgeInsets.zero,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 24,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: AppSecondaryControlTheme(
                child: AbsorbPointer(
                  absorbing: saving,
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
                        Text(
                          isEn ? 'Recommended Goals' : '推荐目标',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: headingColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...templatesByCategory.entries.map((entry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 8.0,
                                  top: 4.0,
                                ),
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: categoryColor,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: recommendationRowHeight,
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
                                        changeDraft(() {
                                          selectedKind = HabitKind.positive;
                                          selectedIcon = habitIconTokenForIcon(
                                            t.icon,
                                          );
                                          nameCtrl.text = t.localizedName;
                                          targetCtrl.text = t.targetCount
                                              .toString();
                                          unitDraft.selectGenerated(
                                            t.generatedUnitKey,
                                          );
                                          categoryCtrl.text =
                                              t.localizedCategory;
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: Text(isEn ? 'Build habit' : '正向养成'),
                              selected: selectedKind == HabitKind.positive,
                              onSelected: (_) => setSt(() {
                                selectedKind = HabitKind.positive;
                              }),
                            ),
                            ChoiceChip(
                              label: Text(isEn ? 'Avoid habit' : '反向戒除'),
                              selected: selectedKind == HabitKind.negative,
                              onSelected: (_) => setSt(() {
                                selectedKind = HabitKind.negative;
                                flexRuleEnabled = false;
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // --- Remind ---
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.alarm,
                                    size: 18,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      isEn ? 'Check-in reminder' : '打卡提醒',
                                    ),
                                  ),
                                ],
                              ),
                              AppStatusBadge(
                                label: isEn ? 'In-app popup' : '默认弹出',
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 26,
                            top: 2,
                            bottom: 6,
                          ),
                          child: Text(
                            isEn
                                ? 'In-app popups at scheduled times, multiple times supported'
                                : '到点应用内弹出打卡提醒，可添加多个时间（例如每天 8 杯水）',
                            style: TextStyle(
                              fontSize: 11,
                              color: reminderGuidanceColor,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < remindTimes.length; i++)
                                InputChip(
                                  avatar: const Icon(Icons.schedule, size: 16),
                                  label: Text(
                                    AppTimePicker.format(remindTimes[i]),
                                  ),
                                  onPressed: () async {
                                    final t = await AppTimePicker.show(
                                      ctx,
                                      initialTime: remindTimes[i],
                                      title: isEn ? 'Reminder time' : '提醒时间',
                                      minuteStep: 5,
                                    );
                                    if (t == null || !mounted || !ctx.mounted) {
                                      return;
                                    }
                                    setSt(() => remindTimes[i] = t);
                                  },
                                  onDeleted: remindTimes.length <= 1
                                      ? null
                                      : () => setSt(
                                          () => remindTimes.removeAt(i),
                                        ),
                                ),
                              ActionChip(
                                avatar: const Icon(Icons.add, size: 16),
                                label: Text(isEn ? 'Add time' : '添加时间'),
                                onPressed: () async {
                                  final t = await AppTimePicker.show(
                                    ctx,
                                    initialTime: nextHalfHourTimeOfDay(),
                                    title: isEn ? 'Reminder time' : '提醒时间',
                                    minuteStep: 5,
                                  );
                                  if (t == null || !mounted || !ctx.mounted) {
                                    return;
                                  }
                                  setSt(() {
                                    if (!remindTimes.any(
                                      (e) =>
                                          e.hour == t.hour &&
                                          e.minute == t.minute,
                                    )) {
                                      remindTimes.add(t);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),

                        // --- Manual Entry ---
                        TextField(
                          enabled: !saving,
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: isEn ? 'Habit name' : '习惯名称',
                            hintText: isEn
                                ? 'Enter or choose from above'
                                : '输入或从上方选择',
                            prefixIcon: const Icon(Icons.edit, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enabled: !saving,
                          controller: categoryCtrl,
                          decoration: isEn
                              ? const InputDecoration(
                                  labelText: 'Group',
                                  hintText: 'e.g. Health, Study',
                                  prefixIcon: Icon(
                                    Icons.folder_outlined,
                                    size: 20,
                                  ),
                                )
                              : const InputDecoration(
                                  labelText: '分组',
                                  hintText: '例如 身体健康、学习提升',
                                  prefixIcon: Icon(
                                    Icons.folder_outlined,
                                    size: 20,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          enabled: !saving,
                          controller: tagsCtrl,
                          decoration: isEn
                              ? const InputDecoration(
                                  labelText: 'Tags',
                                  hintText: 'Comma separated, e.g. morning, health',
                                  prefixIcon: Icon(
                                    Icons.sell_outlined,
                                    size: 20,
                                  ),
                                )
                              : const InputDecoration(
                                  labelText: '标签',
                                  hintText: '逗号或空格分隔，例如 晨间, 健康',
                                  prefixIcon: Icon(
                                    Icons.sell_outlined,
                                    size: 20,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (ctx, constraints) {
                            final textScaler = MediaQuery.textScalerOf(ctx);
                            final direction = Directionality.of(ctx);
                            final maybeLocale =
                                Localizations.maybeLocaleOf(ctx);
                            final inputTheme = theme.inputDecorationTheme;
                            final defaultTextStyle =
                                DefaultTextStyle.of(ctx).style;
                            final targetLabelStyle = inputTheme.labelStyle ??
                                theme.textTheme.bodyLarge ??
                                defaultTextStyle;
                            final unitHintStyle = inputTheme.hintStyle ??
                                theme.textTheme.bodyMedium ??
                                defaultTextStyle;

                            double measureTextWidth(
                              String text,
                              TextStyle style,
                            ) {
                              final painter = TextPainter(
                                text: TextSpan(text: text, style: style),
                                textDirection: direction,
                                textScaler: textScaler,
                                locale: maybeLocale,
                              )..layout();
                              final w = painter.width;
                              painter.dispose();
                              return w;
                            }

                            final targetLabel = isEn ? 'Daily target' : '每日目标';
                            final naturalTargetLabelWidth = measureTextWidth(
                              targetLabel,
                              targetLabelStyle,
                            );
                            final targetPrefixWidth =
                                inputTheme.prefixIconConstraints?.minWidth ??
                                    48.0;
                            final targetPadding = inputTheme.contentPadding
                                    ?.resolve(direction)
                                    .horizontal ??
                                24.0;
                            final naturalTargetFieldWidth = targetPrefixWidth +
                                naturalTargetLabelWidth +
                                (targetPadding / 2) +
                                8.0;

                            final unitLabel = isEn ? 'Unit' : '单位';
                            var maxUnitContentWidth = measureTextWidth(
                              unitLabel,
                              targetLabelStyle,
                            );
                            for (final hint in const [
                              'times',
                              'cups',
                              'time',
                              'cup',
                              '次',
                              '杯',
                            ]) {
                              final w = measureTextWidth(hint, unitHintStyle);
                              if (w > maxUnitContentWidth) {
                                maxUnitContentWidth = w;
                              }
                            }
                            final unitPadding = inputTheme.contentPadding
                                    ?.resolve(direction)
                                    .horizontal ??
                                24.0;
                            final measuredUnitWidth =
                                maxUnitContentWidth + unitPadding + 12.0;
                            final formulaUnitWidth =
                                textScaler.scale(DesignTokens.fontSizeSm) *
                                        4.2 +
                                    32.0;
                            final candidateUnitWidth =
                                measuredUnitWidth > formulaUnitWidth
                                    ? measuredUnitWidth
                                    : formulaUnitWidth;
                            final naturalUnitFieldWidth =
                                candidateUnitWidth < 82.0
                                    ? 82.0
                                    : candidateUnitWidth;

                            const colorPickerWidth = 158.0;

                            final colorPicker = AppSurfaceCard(
                              padding: const EdgeInsets.all(6),
                              borderRadius: BorderRadius.circular(16),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: colors
                                    .take(4)
                                    .map(
                                      (c) => GestureDetector(
                                        onTap: () =>
                                            setSt(() => selectedColor = c),
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
                                                        color: Color(c)
                                                            .withValues(
                                                              alpha: 0.4,
                                                            ),
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
                            );

                            final unitFieldWidget = SizedBox(
                              width: naturalUnitFieldWidth,
                              child: HabitUnitField(
                                draft: unitDraft,
                                targetController: targetCtrl,
                                locale: locale,
                                enabled: !saving,
                                maximumTarget: 9999,
                                onChanged: (value) => changeDraft(
                                  () => unitDraft.recordEdit(value),
                                ),
                              ),
                            );

                            Widget buildTargetField({
                              required bool expanded,
                              int flex = 1,
                            }) {
                              final field = TextField(
                                enabled: !saving,
                                controller: targetCtrl,
                                decoration: InputDecoration(
                                  labelText: isEn ? 'Daily target' : '每日目标',
                                  prefixIcon: const Icon(
                                    Icons.track_changes,
                                    size: 20,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                              );
                              return expanded
                                  ? Expanded(flex: flex, child: field)
                                  : field;
                            }

                            final fitsAllThree = constraints.maxWidth >=
                                (naturalTargetFieldWidth +
                                    10.0 +
                                    naturalUnitFieldWidth +
                                    12.0 +
                                    colorPickerWidth);
                            final fitsTargetAndUnit = constraints.maxWidth >=
                                (naturalTargetFieldWidth +
                                    10.0 +
                                    naturalUnitFieldWidth);

                            if (fitsAllThree) {
                              return Row(
                                children: [
                                  buildTargetField(expanded: true, flex: 2),
                                  const SizedBox(width: 10),
                                  unitFieldWidget,
                                  const SizedBox(width: 12),
                                  colorPicker,
                                ],
                              );
                            }

                            if (fitsTargetAndUnit) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      buildTargetField(expanded: true),
                                      const SizedBox(width: 10),
                                      unitFieldWidget,
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  colorPicker,
                                ],
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                buildTargetField(expanded: false),
                                const SizedBox(height: 10),
                                unitFieldWidget,
                                const SizedBox(height: 10),
                                colorPicker,
                              ],
                            );
                          },
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
                                  Expanded(
                                    child: Text(isEn ? 'Goal rules' : '目标规则'),
                                  ),
                                  Switch(
                                    value:
                                        flexRuleEnabled &&
                                        selectedKind == HabitKind.positive,
                                    onChanged:
                                        selectedKind == HabitKind.positive
                                        ? (v) =>
                                              setSt(() => flexRuleEnabled = v)
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
                                        key: const ValueKey(
                                          'habit-flex-rule-fields',
                                        ),
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child:
                                                  SegmentedButton<
                                                    HabitFlexPeriod
                                                  >(
                                                    showSelectedIcon: false,
                                                    segments: [
                                                      ButtonSegment(
                                                        value: HabitFlexPeriod
                                                            .week,
                                                        label: Text(
                                                          I18n.tr(
                                                            'habit.flex.weekly',
                                                          ),
                                                        ),
                                                      ),
                                                      ButtonSegment(
                                                        value: HabitFlexPeriod
                                                            .month,
                                                        label: Text(
                                                          I18n.tr(
                                                            'habit.flex.monthly',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    selected: {
                                                      selectedFlexPeriod,
                                                    },
                                                    onSelectionChanged:
                                                        (value) => setSt(
                                                          () =>
                                                              selectedFlexPeriod =
                                                                  value.first,
                                                        ),
                                                  ),
                                            ),
                                            const SizedBox(height: 10),
                                            TextField(
                                              enabled: !saving,
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
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                            ),
                                          ],
                                        ),
                                      )
                                    : Padding(
                                        key: const ValueKey(
                                          'habit-daily-rule-note',
                                        ),
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          selectedKind == HabitKind.positive
                                              ? (isEn
                                                    ? 'Off tracks daily streaks'
                                                    : '关闭时按每日目标连续统计')
                                              : (isEn
                                                    ? 'Avoid habits track zero occurrences'
                                                    : '反向戒除按每日不发生统计'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: ruleGuidanceColor,
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
                          onStartChanged: (value) =>
                              setSt(() => startDate = value),
                          onEndChanged: (value) => setSt(() => endDate = value),
                        ),

                        const SizedBox(height: 16),
                        HabitActiveWeekdayPicker(
                          weekdays: selectedActiveWeekdays,
                          onChanged: (value) =>
                              setSt(() => selectedActiveWeekdays = value),
                        ),

                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final sheetRoute = ModalRoute.of(ctx);
                                    if (!ctx.mounted ||
                                        sheetRoute == null ||
                                        !sheetRoute.isCurrent) {
                                      return;
                                    }
                                    if (completedResult != null) {
                                      if (origin.isValid(
                                        ctx,
                                        checkCurrentRoute: false,
                                      )) {
                                        Navigator.of(ctx).pop();
                                      }
                                      return;
                                    }
                                    if (saving) return;
                                    if (!origin.isValid(
                                      ctx,
                                      specificRoute: sheetRoute,
                                    )) {
                                      return;
                                    }
                                    final name = nameCtrl.text.trim();
                                    if (name.isEmpty) {
                                      showHabitSafeFeedback(
                                        ctx,
                                        (loc) => HabitUiCopy.nameRequired(loc),
                                        origin: origin,
                                        route: sheetRoute,
                                      );
                                      return;
                                    }
                                    final shouldUseFlex =
                                        flexRuleEnabled &&
                                        selectedKind == HabitKind.positive;
                                    final flexTarget =
                                        int.tryParse(
                                          flexTargetCtrl.text.trim(),
                                        ) ??
                                        0;
                                    if (shouldUseFlex && flexTarget < 1) {
                                      showHabitSafeFeedback(
                                        ctx,
                                        (loc) =>
                                            HabitUiCopy.flexTargetInvalid(loc),
                                        origin: origin,
                                        route: sheetRoute,
                                      );
                                      return;
                                    }
                                    if (!habitDateRangeIsValid(
                                      startDate,
                                      endDate,
                                    )) {
                                      showHabitSafeFeedback(
                                        ctx,
                                        (loc) =>
                                            HabitUiCopy.dateRangeInvalid(loc),
                                        origin: origin,
                                        route: sheetRoute,
                                      );
                                      return;
                                    }
                                    FocusScope.of(ctx).unfocus();
                                    setSt(() => saving = true);
                                    try {
                                      final sortedRemindTimes =
                                          remindTimes.toList()..sort(
                                            (a, b) => a.hour != b.hour
                                                ? a.hour - b.hour
                                                : a.minute - b.minute,
                                          );
                                      final shouldRemind =
                                          sortedRemindTimes.isNotEmpty;
                                      final reminderPlan = shouldRemind
                                          ? _habitPopupDailyReminderPlan(
                                              sortedRemindTimes,
                                            )
                                          : const ReminderPlan.disabled();
                                      final habitId = DateTime.now()
                                          .millisecondsSinceEpoch
                                          .toString();
                                      final newHabit = Habit(
                                        id: habitId,
                                        name: name,
                                        icon: selectedIcon,
                                        colorValue: selectedColor,
                                        kind: selectedKind,
                                        targetCount:
                                            (int.tryParse(targetCtrl.text) ?? 1)
                                                .clamp(1, 9999)
                                                .toInt(),
                                        unit: unitDraft.authoredUnit,
                                        generatedUnitKey:
                                            unitDraft.generatedUnitKey,
                                        category: habitCategoryOrNull(
                                          categoryCtrl.text,
                                        ),
                                        tags: _parseHabitScreenTags(
                                          tagsCtrl.text,
                                        ),
                                        flexTarget: shouldUseFlex
                                            ? flexTarget
                                            : null,
                                        flexPeriod: shouldUseFlex
                                            ? selectedFlexPeriod
                                            : null,
                                        startDate: startDate,
                                        endDate: endDate,
                                        activeWeekdays: List<int>.from(
                                          selectedActiveWeekdays,
                                        ),
                                        remind: shouldRemind,
                                        remindHour: sortedRemindTimes.isNotEmpty
                                            ? sortedRemindTimes.first.hour
                                            : null,
                                        remindMinute:
                                            sortedRemindTimes.isNotEmpty
                                            ? sortedRemindTimes.first.minute
                                            : null,
                                        reminderPlan: reminderPlan,
                                      );
                                      if (shouldRemind) {
                                        final reminderReady =
                                            await _ensureHabitReminderReady(
                                              scheduledTime:
                                                  _nextHabitReminderTriggerForTimes(
                                                    sortedRemindTimes,
                                                  ),
                                              relatedId: habitId,
                                            );
                                        if (!ctx.mounted ||
                                            !sheetRoute.isCurrent ||
                                            !origin.isValid(
                                              ctx,
                                              specificRoute: sheetRoute,
                                            )) {
                                          return;
                                        }
                                        if (!reminderReady) {
                                          return;
                                        }
                                      }
                                      if (!ctx.mounted ||
                                          !origin.isValid(
                                            ctx,
                                            checkCurrentRoute: false,
                                          )) {
                                        return;
                                      }
                                      await origin.habitProvider.addHabit(
                                        newHabit,
                                      );
                                      final reminderSyncIssue = shouldRemind
                                          ? origin
                                                .habitProvider
                                                .lastReminderSyncIssue
                                          : null;

                                      if (!ctx.mounted ||
                                          !origin.isValid(
                                            ctx,
                                            checkCurrentRoute: false,
                                            checkAccess: false,
                                          )) {
                                        return;
                                      }
                                      completedResult = newHabit;
                                      setSt(() => saving = false);
                                      if (origin.isValid(
                                        ctx,
                                        specificRoute: sheetRoute,
                                      )) {
                                        Navigator.of(ctx).pop();
                                        if (!mounted) return;
                                        showHabitSafeFeedback(
                                          context,
                                          (loc) => reminderSyncIssue == null
                                              ? HabitUiCopy.saveSuccess(loc)
                                              : HabitUiCopy.reminderSyncWarning(
                                                  _habitReminderSyncIssueText(
                                                    reminderSyncIssue,
                                                    loc,
                                                  ),
                                                  loc,
                                                ),
                                          backgroundColor:
                                              reminderSyncIssue == null
                                              ? null
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                        );
                                      }
                                    } on AccountPreferenceWriteCanceled {
                                      return;
                                    } catch (_) {
                                      if (!ctx.mounted ||
                                          !origin.isValid(
                                            ctx,
                                            specificRoute: sheetRoute,
                                          )) {
                                        return;
                                      }
                                      showHabitSafeFeedback(
                                        ctx,
                                        (loc) =>
                                            HabitUiCopy.saveFailedWithRetry(
                                              loc,
                                            ),
                                        origin: origin,
                                        route: sheetRoute,
                                      );
                                    } finally {
                                      if (ctx.mounted &&
                                          completedResult == null) {
                                        setSt(() => saving = false);
                                      }
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
                            child: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    isEn ? 'Start new habit' : '开启新习惯',
                                    style: const TextStyle(
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
            );
          },
        ),
      ),
    ).whenComplete(() async {
      await ownedSheet?.completed;
      nameCtrl.dispose();
      targetCtrl.dispose();
      flexTargetCtrl.dispose();
      unitDraft.dispose();
      categoryCtrl.dispose();
      tagsCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HabitProvider>();
    final s = context.select<ThemeProvider, BrandStrings>(
      (t) => t.brand.strings,
    );
    final allTags = provider.allTags;
    final selectedTag =
        (_selectedTag != null && allTags.contains(_selectedTag))
        ? _selectedTag
        : null;
    final now = DateTime.now();
    final dayKey = now.year * 10000 + now.month * 100 + now.day;
    final habitsFp = _habitsFingerprint(provider.habits);
    List<Habit> activeHabits;
    int completedTodayCount;
    if (_cachedActiveHabits != null &&
        _todayHabitsFingerprint == habitsFp &&
        _todayHabitsDayKey == dayKey &&
        _todayHabitsTag == selectedTag) {
      activeHabits = _cachedActiveHabits!;
      completedTodayCount = _cachedCompletedTodayCount;
    } else {
      final filtered = provider.habits
          .where(
            (h) =>
                h.isActiveToday() &&
                (selectedTag == null || h.tags.contains(selectedTag)),
          )
          .toList(growable: false);
      activeHabits = List<Habit>.unmodifiable(filtered);
      completedTodayCount = activeHabits
          .where((h) => h.isCompletedToday())
          .length;
      _todayHabitsFingerprint = habitsFp;
      _todayHabitsDayKey = dayKey;
      _todayHabitsTag = selectedTag;
      _cachedActiveHabits = activeHabits;
      _cachedCompletedTodayCount = completedTodayCount;
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    // 宽屏桌面档（与 today 桌面仪表盘同款纯宽度判定）：打卡列与热力图
    // 双栏并置，替代窄屏的 TabBar 切换；标记已构建，缩回窄屏时热力图
    // 不再退回占位。
    final isWidescreen =
        MediaQuery.widthOf(context) >= DesktopTokens.breakpointTwoColumn;
    if (isWidescreen) {
      _heatmapTabBuilt = true;
    }
    final todayScrollView = CustomScrollView(
      key: const ValueKey('habit_today_scroll_view'),
      slivers: [
        const SliverToBoxAdapter(child: HabitWeeklyCard()),
        SliverToBoxAdapter(
          key: const ValueKey('habit_insight_before_today_list'),
          child: _HabitInsightSection(habits: provider.habits),
        ),
        if (allTags.isNotEmpty || selectedTag != null)
          SliverToBoxAdapter(
            key: const ValueKey('habit_today_tag_filter_sliver'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(
                        I18n.current == AppLocale.en ? 'All tags' : '全部标签',
                      ),
                      selected: selectedTag == null,
                      onSelected: (_) => setState(() => _selectedTag = null),
                    ),
                    for (final tag in allTags) ...[
                      const SizedBox(width: 6),
                      FilterChip(
                        label: Text('#$tag'),
                        selected: selectedTag == tag,
                        onSelected: (_) => setState(
                          () => _selectedTag = _selectedTag == tag ? null : tag,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (activeHabits.isEmpty)
          SliverToBoxAdapter(
            key: const ValueKey('habit_today_empty_state_sliver'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: EmptyState(
                icon: Icons.repeat,
                message: provider.habits.isEmpty
                    ? s.habitEmpty
                    : MainUiCopy.habitNoScheduleToday,
                actionLabel: s.habitAddAction,
                onAction: _showAddDialog,
                minCardHeight: EmptyState.defaultMinCardHeight,
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: _HabitTodaySummaryCard(
              completedCount: completedTodayCount,
              totalCount: activeHabits.length,
              progress: provider.todayOverallProgress,
              longestStreak: provider.longestCurrentStreak,
              doneLabel: s.habitTodayDone,
              streakLabel: s.habitStreakLabel,
            ),
          ),
          _buildTodayCheckinSliver(
            context,
            activeHabits: activeHabits,
            isWidescreen: isWidescreen,
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 88),
        ),
      ],
    );
    final heatmapTab = _HabitHeatmapTab(
      provider: provider,
      heading: s.habitHeatmapHeading,
      streakLabel: s.habitStreakLabel,
      emptyMessage: s.habitEmpty,
      actionLabel: s.habitAddAction,
      selectedTag: selectedTag,
      archiveFilter: _archiveFilter,
      onSelectTag: (tag) => setState(() => _selectedTag = tag),
      onSelectArchiveFilter: (f) => setState(() => _archiveFilter = f),
      onAdd: _showAddDialog,
    );

    return BrandScaffold(
      paintBackground: false,
      appBar: AppBar(
        title: Text(s.habitTitle),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        // 宽屏双栏并置时 TabBar 失去切换意义，顶栏不再挂载。
        bottom: isWidescreen
            ? null
            : TabBar(
                controller: _tabCtrl,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                labelStyle: appSecondaryControlLabelStyle(context).copyWith(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: DesignTokens.fontWeightRegular,
                ),
                unselectedLabelStyle: appSecondaryControlLabelStyle(context)
                    .copyWith(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: DesignTokens.fontWeightRegular,
                    ),
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicator: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.16),
                    width: 0.55,
                  ),
                ),
                tabs: [
                  Tab(text: s.habitTabToday),
                  Tab(text: s.habitTabHeatmap),
                ],
              ),
      ),
      body: isWidescreen
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: todayScrollView),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  // 不传 color：走主题 dividerTheme 档位（outlineVariant@feel alpha）。
                ),
                Expanded(child: heatmapTab),
              ],
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [
                // Today check-in
                todayScrollView,
                // Heatmap
                _heatmapTabBuilt ? heatmapTab : const SizedBox.shrink(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habit_add_fab',
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _HabitHeatmapTab extends StatefulWidget {
  final HabitProvider provider;
  final String heading;
  final String streakLabel;
  final String emptyMessage;
  final String actionLabel;
  final String? selectedTag;
  final _HabitArchiveFilter archiveFilter;
  final ValueChanged<String?> onSelectTag;
  final ValueChanged<_HabitArchiveFilter> onSelectArchiveFilter;
  final VoidCallback onAdd;

  const _HabitHeatmapTab({
    required this.provider,
    required this.heading,
    required this.streakLabel,
    required this.emptyMessage,
    required this.actionLabel,
    required this.selectedTag,
    required this.archiveFilter,
    required this.onSelectTag,
    required this.onSelectArchiveFilter,
    required this.onAdd,
  });

  @override
  State<_HabitHeatmapTab> createState() => _HabitHeatmapTabState();
}

class _HabitHeatmapTabState extends State<_HabitHeatmapTab> {
  int? _heatmapFp;
  int? _heatmapDayKey;
  Map<String, int>? _cachedHeatmapData;

  int? _groupsFp;
  int? _groupsDayKey;
  _HabitArchiveFilter? _groupsFilter;
  String? _groupsTag;
  List<HabitGroup>? _cachedGroups;

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final cs = Theme.of(context).colorScheme;
    final isEn = I18n.current == AppLocale.en;
    final heatmapToday = DateTime.now();
    final dayKey =
        heatmapToday.year * 10000 +
        heatmapToday.month * 100 +
        heatmapToday.day;
    final habitsFp = _HabitScreenState._habitsFingerprint(provider.habits);

    Map<String, int> heatmapData;
    if (_cachedHeatmapData != null &&
        _heatmapFp == habitsFp &&
        _heatmapDayKey == dayKey) {
      heatmapData = _cachedHeatmapData!;
    } else {
      heatmapData = provider.combinedHeatmap(12, today: heatmapToday);
      _heatmapFp = habitsFp;
      _heatmapDayKey = dayKey;
      _cachedHeatmapData = heatmapData;
    }

    final endedCount = provider.endedHabits.length;
    final allTags = provider.allTags;
    List<HabitGroup> habitGroups;
    if (_cachedGroups != null &&
        _groupsFp == habitsFp &&
        _groupsDayKey == dayKey &&
        _groupsFilter == widget.archiveFilter &&
        _groupsTag == widget.selectedTag) {
      habitGroups = _cachedGroups!;
    } else {
      habitGroups = groupHabitsByCategory(provider.habits)
          .map((group) {
            final filtered = group.habits
                .where((h) {
                  if (widget.archiveFilter == _HabitArchiveFilter.active &&
                      h.isEnded) {
                    return false;
                  }
                  if (widget.archiveFilter == _HabitArchiveFilter.archived &&
                      !h.isEnded) {
                    return false;
                  }
                  if (widget.selectedTag != null &&
                      !h.tags.contains(widget.selectedTag)) {
                    return false;
                  }
                  return true;
                })
                .toList(growable: false);
            return HabitGroup(
              category: group.category,
              habits: List<Habit>.unmodifiable(filtered),
            );
          })
          .where((group) => group.habits.isNotEmpty)
          .toList(growable: false);
      _groupsFp = habitsFp;
      _groupsDayKey = dayKey;
      _groupsFilter = widget.archiveFilter;
      _groupsTag = widget.selectedTag;
      _cachedGroups = habitGroups;
    }

    final showHeatmapSummary = MediaQuery.sizeOf(context).height >= 720;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AppSurfaceCard(
            key: const ValueKey('habit_heatmap_skin_card'),
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.heading,
                  style: appSecondaryRouteTitleTextStyle(context).copyWith(
                    fontSize: 13,
                    fontWeight: DesignTokens.fontWeightRegular,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 2),
                HabitHeatmap(
                  heatmapData: heatmapData,
                  today: heatmapToday,
                  showSummary: showHeatmapSummary,
                ),
              ],
            ),
          ),
        ),
        if (provider.habits.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.folder_open,
              message: widget.emptyMessage,
              actionLabel: widget.actionLabel,
              onAction: widget.onAdd,
              minCardHeight: EmptyState.defaultMinCardHeight,
            ),
          )
        else ...[
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final inlineGroupHeader = constraints.crossAxisExtent >= 480;
              final groupHeaderText = Text(
                HeatmapUiCopy(I18n.current).habitGroups,
                style: appSecondaryControlTextStyle(context).copyWith(
                  color: cs.onSurface.withValues(alpha: 0.68),
                  fontSize: DesignTokens.fontSizeCaption,
                ),
              );
              const archivedKey = ValueKey('habit_mobile_filter_archived');
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (inlineGroupHeader)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 6,
                                  right: 10,
                                ),
                                child: groupHeaderText,
                              ),
                            ChoiceChip(
                              key: const ValueKey('habit_mobile_filter_all'),
                              label: Text(isEn ? 'All' : '全部'),
                              selected:
                                  widget.archiveFilter ==
                                  _HabitArchiveFilter.all,
                              onSelected: (_) => widget.onSelectArchiveFilter(
                                _HabitArchiveFilter.all,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              key: const ValueKey('habit_mobile_filter_active'),
                              label: Text(isEn ? 'Active' : '进行中'),
                              selected:
                                  widget.archiveFilter ==
                                  _HabitArchiveFilter.active,
                              onSelected: (_) => widget.onSelectArchiveFilter(
                                _HabitArchiveFilter.active,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              key: archivedKey,
                              label: Text(
                                isEn
                                    ? 'Archived ($endedCount)'
                                    : '已结束 ($endedCount)',
                              ),
                              selected:
                                  widget.archiveFilter ==
                                  _HabitArchiveFilter.archived,
                              onSelected: (_) => widget.onSelectArchiveFilter(
                                _HabitArchiveFilter.archived,
                              ),
                            ),
                            for (final tag in allTags) ...[
                              const SizedBox(width: 6),
                              FilterChip(
                                label: Text('#$tag'),
                                selected: widget.selectedTag == tag,
                                onSelected: (_) => widget.onSelectTag(
                                  widget.selectedTag == tag ? null : tag,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!inlineGroupHeader)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                        child: groupHeaderText,
                      ),
                  ],
                ),
              );
            },
          ),
          if (habitGroups.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    isEn ? 'No habits in this filter' : '当前筛选下暂无习惯',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: habitGroups.length,
              itemBuilder: (context, index) => _HabitGroupSection(
                key: ValueKey(
                  'habit_heatmap_group_${habitGroups[index].category}',
                ),
                group: habitGroups[index],
                streakLabel: widget.streakLabel,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final summaryBg = Color.alphaBlend(
      Color.alphaBlend(
        cs.primary.withValues(alpha: isDark ? 0.13 : 0.065),
        cs.surface,
      ),
      theme.scaffoldBackgroundColor,
    );
    final preferredPercentColor = progress >= 1
        ? (isDark ? const Color(0xFF81C784) : const Color(0xFF1B5E20))
        : cs.primary;
    final percentColor = appReadableForeground(summaryBg, preferredPercentColor);
    final baseStyle =
        theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    final percentStyle = baseStyle.copyWith(
      fontSize: 10,
      fontWeight: DesignTokens.fontWeightRegular,
      color: percentColor,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 7),
      child: AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              cs.primary.withValues(alpha: isDark ? 0.13 : 0.065),
              cs.surface,
            ),
            Color.alphaBlend(
              cs.secondary.withValues(alpha: isDark ? 0.09 : 0.04),
              cs.surface,
            ),
          ],
        ),
        border: Border.all(
          color: cs.primary.withValues(alpha: isDark ? 0.18 : 0.13),
          width: 0.6,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textDirection =
                Directionality.maybeOf(context) ?? TextDirection.ltr;
            final textScaler = MediaQuery.textScalerOf(context);
            final percentLabel = '${(progress * 100).toInt()}%';
            // Size from at least 3 digits ('100%') so ring geometry remains
            // stable from 0% to 100% and accounts for stroke + AA clearance.
            final sizingSample =
                percentLabel.length >= 4 ? percentLabel : '100%';
            final sampleSize = _measureHabitText(
              sizingSample,
              percentStyle,
              textScaler: textScaler,
              textDirection: textDirection,
            );
            final actualSize = percentLabel == sizingSample
                ? sampleSize
                : _measureHabitText(
                    percentLabel,
                    percentStyle,
                    textScaler: textScaler,
                    textDirection: textDirection,
                  );
            final measuredW = math.max(sampleSize.width, actualSize.width);
            final measuredH = math.max(sampleSize.height, actualSize.height);
            final halfDiag = math.sqrt(
              (measuredW / 2) * (measuredW / 2) +
                  (measuredH / 2) * (measuredH / 2),
            );
            const ringStrokeWidth = 4.0;
            const ringAaMargin = 2.0;
            const innerClearancePadding = 4.0;
            final requiredInsideRingSize =
                (2.0 *
                        (halfDiag +
                            innerClearancePadding +
                            ringStrokeWidth +
                            ringAaMargin))
                    .ceilToDouble();
            final availableCardW = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 274.8;
            final maxInlineRingSize = math.min(
              112.0,
              math.max(40.0, availableCardW * 0.42),
            );
            final placePercentInside =
                requiredInsideRingSize <= maxInlineRingSize;
            final ringSize = placePercentInside
                ? math.max(40.0, requiredInsideRingSize)
                : 44.0;

            final ringIndicator = SizedBox(
              width: ringSize,
              height: ringSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: ringStrokeWidth,
                      strokeCap: StrokeCap.round,
                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                      color: progress >= 1
                          ? DesignTokens.defaultSuccess
                          : cs.primary,
                    ),
                  ),
                  if (placePercentInside)
                    Text(percentLabel, style: percentStyle),
                ],
              ),
            );

            final leadingRing = placePercentInside
                ? ringIndicator
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ringIndicator,
                      const SizedBox(
                        height: ringStrokeWidth + ringAaMargin + 2.0,
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxInlineRingSize,
                        ),
                        child: Text(
                          percentLabel,
                          textAlign: TextAlign.center,
                          style: percentStyle,
                        ),
                      ),
                    ],
                  );

            return Row(
              children: [
                leadingRing,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$completedCount / $totalCount $doneLabel',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                          height: 1.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$streakLabel $longestStreak ${I18n.tr('unit.day')}',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.58),
                          fontSize: 11,
                          height: 1.15,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.task_alt_rounded,
                  size: 18,
                  color: progress >= 1
                      ? appReadableForeground(
                          cs.surface,
                          DesignTokens.defaultSuccess,
                        )
                      : cs.primary.withValues(alpha: 0.62),
                ),
              ],
            );
          },
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
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded:
              group.habits.length <= _habitHeatmapGroupPreviewLimit,
          tilePadding: const EdgeInsets.fromLTRB(9, 0, 8, 0),
          childrenPadding: const EdgeInsets.only(bottom: 2),
          leading: Icon(Icons.folder_outlined, color: cs.primary, size: 15),
          minTileHeight: 34,
          dense: true,
          title: Text(
            group.category == defaultHabitCategoryName
                ? I18n.tr('habit.group.ungrouped')
                : group.category,
            style: appSecondaryMenuItemTextStyle(context).copyWith(
              fontSize: 12,
              fontWeight: DesignTokens.fontWeightRegular,
              color: cs.onSurface,
              height: 1.12,
            ),
          ),
          subtitle: Text(
            '${group.completedTodayCount}/${group.habits.length}${I18n.tr('habit.group.today_suffix')}',
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: cs.onSurfaceVariant, fontSize: 10, height: 1.08),
          ),
          children: [
            for (final habit in previewHabits)
              _HabitSummaryTile(habit: habit, streakLabel: streakLabel),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(
                  "${I18n.tr('habit.group.more_habits_prefix')}$hiddenCount${I18n.tr('habit.group.more_habits_suffix')}",
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
              Expanded(
                child: Text(
                  I18n.current == AppLocale.en
                      ? 'Smart Habit Insights'
                      : '智能习惯洞察',
                  style: appSecondaryRouteTitleTextStyle(context).copyWith(
                    fontSize: 13,
                    fontWeight: DesignTokens.fontWeightRegular,
                  ),
                ),
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
                            fontSize: 12,
                            fontWeight: DesignTokens.fontWeightRegular,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          insight.message,
                          style: TextStyle(
                            fontSize: 10.5,
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
    final cs = Theme.of(context).colorScheme;
    final habitColor = Color(habit.colorValue);
    final streakUnit = habit.streakUnitLabel;
    final textScale = (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
      1.0,
      double.infinity,
    );
    return _HabitSwipeActionWrapper(
      habit: habit,
      showEndAction: _habitCanEnd(habit),
      actionMargin: const EdgeInsets.symmetric(horizontal: 8),
      borderRadius: BorderRadius.circular(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HabitDetailScreen(habitId: habit.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 2, 9, 3),
            child: SizedBox(
              // Swipe strip sits in Positioned.fill; reserve >= 44px total host
              // height (39 + 5 vertical padding) so 44x44 swipe buttons fit.
              height: math.max(_habitSwipeButtonSize - 5, 34 * textScale),
              child: Row(
                children: [
                  Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: habitColor.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _habitDisplayIcon(habit),
                      color: habitColor,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.08,
                            fontWeight: DesignTokens.fontWeightRegular,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '$streakLabel ${habit.currentStreak} $streakUnit · ${I18n.tr('habit.best_short')} ${habit.bestStreak} $streakUnit',
                            if (habit.tags.isNotEmpty)
                              habit.tags.take(3).map((t) => '#$t').join(' '),
                            if (habit.isEnded)
                              (I18n.current == AppLocale.en
                                  ? 'Archived'
                                  : '已结束'),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.05,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (habit.isEnded)
                    Tooltip(
                      message: I18n.current == AppLocale.en
                          ? 'Reactivate'
                          : '重新启用',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () =>
                            context.read<HabitProvider>().reopenHabit(habit.id),
                        icon: const Icon(Icons.replay_outlined),
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
}

const double _habitMinTouchTarget = 44;
const double _habitActionButtonGap = 4;
const double _habitSwipeButtonSize = 44;
const double _habitSwipeButtonGap = 4;
const double _habitSwipeHorizontalPadding = 6;
const double _habitSwipeActionWidth =
    _habitSwipeHorizontalPadding * 2 +
    _habitSwipeButtonSize * 3 +
    _habitSwipeButtonGap * 2;
const double _habitSwipeOpenThreshold = 36;
const double _habitCardHorizontalChrome = 8.0 + 8.0 + 1.1;
const double _habitCardIconAndGap = 20.0 + 9.0;
const double _habitCardActionGap = 6.0;
const double _habitPaddedTargetDim = 48.0;
const double _habitFeedbackBadgeChromeW = 12.0 + 0.9 + 10.0 + 3.0;
const double _habitStreakBadgeChromeW = 12.0 + 0.9 + 11.0 + 3.0;

Size _measureHabitText(
  String text,
  TextStyle style, {
  required TextScaler textScaler,
  required TextDirection textDirection,
  double maxWidth = double.infinity,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final size = painter.size;
  painter.dispose();
  return size;
}

class _HabitCheckinPresentation {
  final bool isNegative;
  final int todayCount;
  final HabitFlexProgress? flexProgress;
  final double progress;
  final bool isDone;
  final bool canCheckIn;
  final bool hasNegativeOccurrence;
  final String metaText;
  final String checkInLabel;
  final ValueKey<String>? feedbackKey;
  final IconData? feedbackIcon;
  final String? feedbackLabel;
  final Color? feedbackColor;
  final String? streakText;

  const _HabitCheckinPresentation({
    required this.isNegative,
    required this.todayCount,
    required this.flexProgress,
    required this.progress,
    required this.isDone,
    required this.canCheckIn,
    required this.hasNegativeOccurrence,
    required this.metaText,
    required this.checkInLabel,
    required this.feedbackKey,
    required this.feedbackIcon,
    required this.feedbackLabel,
    required this.feedbackColor,
    required this.streakText,
  });

  factory _HabitCheckinPresentation.fromHabit(
    Habit habit,
    ColorScheme cs,
  ) {
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
    final isEn = I18n.current == AppLocale.en;
    final targetUnit = habitUnit(habit, I18n.current, habit.targetCount);
    final countUnit = habitUnit(habit, I18n.current, todayCount);
    final targetText = isNegative
        ? (isEn ? 'Goal: None' : '目标: 不发生')
        : habit.hasFlexRule
        ? (isEn
              ? '${_habitFlexGoalText(habit)} · Target per session: ${habit.targetCount} $targetUnit'
              : '${_habitFlexGoalText(habit)} · 单次目标: ${habit.targetCount} $targetUnit')
        : (isEn
              ? 'Goal: ${habit.targetCount} $targetUnit/day'
              : '目标: ${habit.targetCount} $targetUnit/天');
    final countText = isNegative
        ? '$todayCount $countUnit'
        : habit.hasFlexRule
        ? (flexProgress?.label ?? '$todayCount/${habit.targetCount}')
        : '$todayCount/${habit.targetCount}';
    final checkInLabel = _habitCheckInButtonLabel(
      habit: habit,
      canCheckIn: canCheckIn,
      flexProgress: flexProgress,
    );

    ValueKey<String>? feedbackKey;
    IconData? feedbackIcon;
    String? feedbackLabel;
    Color? feedbackColor;
    if (isDone && !isNegative) {
      feedbackKey = const ValueKey('habit-completed-feedback');
      feedbackIcon = Icons.check_circle;
      feedbackLabel = habit.hasFlexRule
          ? (isEn
                ? '${flexProgress?.labelPrefix ?? 'Period'} reached'
                : '${flexProgress?.labelPrefix ?? '周期'}达标')
          : (isEn ? 'Completed' : '已达标');
      feedbackColor = const Color(0xFF4CAF50);
    } else if (hasNegativeOccurrence) {
      feedbackKey = const ValueKey('habit-warning-feedback');
      feedbackIcon = Icons.info_outline;
      feedbackLabel = isEn ? 'Recorded' : '已记录';
      feedbackColor = cs.error;
    }

    final streakText = habit.currentStreak > 0
        ? '${habit.currentStreak} ${habit.streakUnitLabel}'
        : null;

    return _HabitCheckinPresentation(
      isNegative: isNegative,
      todayCount: todayCount,
      flexProgress: flexProgress,
      progress: progress,
      isDone: isDone,
      canCheckIn: canCheckIn,
      hasNegativeOccurrence: hasNegativeOccurrence,
      metaText: '$targetText · $countText',
      checkInLabel: checkInLabel,
      feedbackKey: feedbackKey,
      feedbackIcon: feedbackIcon,
      feedbackLabel: feedbackLabel,
      feedbackColor: feedbackColor,
      streakText: streakText,
    );
  }
}

class _HabitCheckinCardLayout {
  final bool stackActions;
  final bool inlineTitleAndBadge;
  final bool inlineMetaAndStreak;

  const _HabitCheckinCardLayout({
    required this.stackActions,
    required this.inlineTitleAndBadge,
    required this.inlineMetaAndStreak,
  });
}

_HabitCheckinCardLayout _resolveHabitCheckinCardLayout({
  required Habit habit,
  required _HabitCheckinPresentation presentation,
  required double cardInnerWidth,
  required TextDirection textDirection,
  required TextScaler textScaler,
  required TextStyle titleStyle,
  required TextStyle metaStyle,
  required TextStyle badgeTextStyle,
  required TextStyle buttonTextStyle,
}) {
  final remainingInlineWidth = math.max(
    0.0,
    cardInnerWidth - _habitCardIconAndGap,
  );
  final singleLabelSize = _measureHabitText(
    presentation.checkInLabel,
    buttonTextStyle,
    textScaler: textScaler,
    textDirection: textDirection,
  );
  final checkInSingleVisualW = math.max(
    _habitMinTouchTarget,
    singleLabelSize.width + 20.0,
  );
  final checkInSingleOuterW = math.max(
    _habitPaddedTargetDim,
    checkInSingleVisualW,
  );
  final hasUndo = presentation.todayCount > 0;
  final inlineActionW = hasUndo
      ? _habitPaddedTargetDim + _habitActionButtonGap + checkInSingleOuterW
      : checkInSingleOuterW;
  final minInlineInfoW = math.max(90.0, textScaler.scale(13) * 6.9);
  final stackActions =
      (remainingInlineWidth - _habitCardActionGap - inlineActionW) <
      minInlineInfoW;

  final infoWidth = stackActions
      ? remainingInlineWidth
      : math.max(
          0.0,
          remainingInlineWidth - _habitCardActionGap - inlineActionW,
        );

  // Inline title/meta rows place the badge as a non-flex child, so measure its
  // natural unwrapped width to match actual Row layout constraints.
  var inlineTitleAndBadge = true;
  if (presentation.feedbackLabel != null) {
    final badgeNaturalText = _measureHabitText(
      presentation.feedbackLabel!,
      badgeTextStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    final badgeNaturalW =
        badgeNaturalText.width + _habitFeedbackBadgeChromeW + 0.5;
    final titleSingle = _measureHabitText(
      habit.name,
      titleStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    inlineTitleAndBadge =
        (titleSingle.width + 0.5 + 6.0 + badgeNaturalW) <= infoWidth;
  }

  var inlineMetaAndStreak = true;
  if (presentation.streakText != null) {
    final streakNaturalText = _measureHabitText(
      presentation.streakText!,
      badgeTextStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    final streakNaturalW =
        streakNaturalText.width + _habitStreakBadgeChromeW + 0.5;
    final metaSingle = _measureHabitText(
      presentation.metaText,
      metaStyle,
      textScaler: textScaler,
      textDirection: textDirection,
    );
    inlineMetaAndStreak =
        (metaSingle.width + 0.5 + 8.0 + streakNaturalW) <= infoWidth;
  }

  return _HabitCheckinCardLayout(
    stackActions: stackActions,
    inlineTitleAndBadge: inlineTitleAndBadge,
    inlineMetaAndStreak: inlineMetaAndStreak,
  );
}

Widget _buildTodayCheckinSliver(
  BuildContext context, {
  required List<Habit> activeHabits,
  required bool isWidescreen,
}) {
  if (!isWidescreen) {
    return SliverList.builder(
      key: const ValueKey('habit_today_checkin_sliver'),
      itemCount: activeHabits.length,
      itemBuilder: (context, index) =>
          _HabitCheckinCard(habit: activeHabits[index]),
    );
  }

  return SliverLayoutBuilder(
    builder: (context, constraints) {
      final paneWidth = constraints.crossAxisExtent;
      const horizontalOuterPadding = 10.0;
      const spacing = DesignTokens.spaceSm;
      final twoColTileWidth =
          (paneWidth - horizontalOuterPadding * 2 - spacing) / 2.0;
      final twoColCardInnerWidth =
          twoColTileWidth - _habitCardHorizontalChrome;
      final twoColStackedInfoWidth =
          twoColCardInnerWidth - _habitCardIconAndGap;

      final theme = Theme.of(context);
      final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
      final textScaler = MediaQuery.textScalerOf(context);
      final baseBodyStyle =
          theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
      final buttonTextStyle = (theme.textTheme.labelLarge ?? baseBodyStyle)
          .copyWith(
            fontSize: 10,
            fontWeight: DesignTokens.fontWeightRegular,
            height: 1.15,
          );

      final typicalCheckInLabel = I18n.current == AppLocale.en
          ? 'Check in'
          : '打卡';
      final typicalLabelSize = _measureHabitText(
        typicalCheckInLabel,
        buttonTextStyle,
        textScaler: textScaler,
        textDirection: textDirection,
      );
      final typicalCheckInWidth = math.max(
        _habitPaddedTargetDim,
        math.max(_habitMinTouchTarget, typicalLabelSize.width + 20.0),
      );
      final minStackedInfoWidth = math.max(90.0, textScaler.scale(13) * 5.0);
      final canUseTwoColumns =
          twoColTileWidth > 0 &&
          twoColCardInnerWidth >=
              math.max(_habitPaddedTargetDim, typicalCheckInWidth) &&
          twoColStackedInfoWidth >= minStackedInfoWidth;

      if (!canUseTwoColumns) {
        return SliverList.builder(
          key: const ValueKey('habit_today_checkin_sliver'),
          itemCount: activeHabits.length,
          itemBuilder: (context, index) =>
              _HabitCheckinCard(habit: activeHabits[index]),
        );
      }

      // Lazy variable-height paired rows avoid O(N) upfront habit scanning and
      // uniform-grid slack while preserving two-column layout where tiles fit.
      final rowCount = (activeHabits.length + 1) ~/ 2;
      return SliverPadding(
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalOuterPadding,
        ),
        sliver: SliverList.builder(
          key: const ValueKey('habit_today_checkin_sliver'),
          itemCount: rowCount,
          itemBuilder: (context, rowIndex) {
            final leftIndex = rowIndex * 2;
            final rightIndex = leftIndex + 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: spacing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _HabitCheckinCard(
                      habit: activeHabits[leftIndex],
                      margin: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: spacing),
                  Expanded(
                    child: rightIndex < activeHabits.length
                        ? _HabitCheckinCard(
                            habit: activeHabits[rightIndex],
                            margin: EdgeInsets.zero,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

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
  final copy = HabitUiCopy(I18n.current);
  return switch (habit.flexPeriod!) {
    HabitFlexPeriod.week => copy.weekGoal(habit.effectiveFlexTarget),
    HabitFlexPeriod.month => copy.monthGoal(habit.effectiveFlexTarget),
  };
}

class _HabitCheckinCard extends StatelessWidget {
  final Habit habit;
  final EdgeInsetsGeometry margin;

  const _HabitCheckinCard({
    required this.habit,
    this.margin = const EdgeInsets.fromLTRB(10, 0, 10, 1),
  });

  @override
  Widget build(BuildContext context) {
    final origin = HabitActionOrigin.capture(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final presentation = _HabitCheckinPresentation.fromHabit(habit, cs);
    final isNegative = presentation.isNegative;
    final todayCount = presentation.todayCount;
    final progress = presentation.progress;
    final isDone = presentation.isDone;
    final canCheckIn = presentation.canCheckIn;
    final hasNegativeOccurrence = presentation.hasNegativeOccurrence;
    final habitColor = hasNegativeOccurrence
        ? cs.error
        : Color(habit.colorValue);

    final surfaceStyle = appSurfaceStyleOf(context);
    final cardBaseBg = surfaceStyle?.cardFillColor != null
        ? Color.alphaBlend(
            surfaceStyle!.cardFillColor!,
            theme.scaffoldBackgroundColor,
          )
        : cs.surface;
    final cardEffectiveBg = isDone || hasNegativeOccurrence
        ? Color.alphaBlend(
            habitColor.withValues(alpha: isDark ? 0.16 : 0.08),
            cardBaseBg,
          )
        : cardBaseBg;

    final baseBodyStyle =
        theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    final doneTitleColor = _habitReadableTintForeground(
      cardEffectiveBg,
      cs.onSurface.withValues(alpha: isDark ? 0.68 : 0.64),
      isDark: isDark,
    );
    final titleColor = hasNegativeOccurrence
        ? _habitReadableTintForeground(cardEffectiveBg, cs.error, isDark: isDark)
        : (isDone && !isNegative ? doneTitleColor : cs.onSurface);
    final titleStyle = baseBodyStyle.copyWith(
      fontWeight: DesignTokens.fontWeightRegular,
      fontSize: 13,
      height: 1.18,
      decoration: isDone && !isNegative ? TextDecoration.lineThrough : null,
      color: titleColor,
    );
    final metaColor = _habitReadableTintForeground(
      cardEffectiveBg,
      appSecondaryDescriptionColor(context),
      isDark: isDark,
    );
    final metaStyle = baseBodyStyle.copyWith(
      color: metaColor,
      fontWeight: DesignTokens.fontWeightRegular,
      fontSize: 10.5,
      height: 1.20,
    );
    final badgeTextStyle = baseBodyStyle.copyWith(
      fontWeight: DesignTokens.fontWeightRegular,
      fontSize: 10,
      height: 1.15,
    );
    final buttonTextStyle = (theme.textTheme.labelLarge ?? baseBodyStyle)
        .copyWith(
          fontSize: 10,
          fontWeight: DesignTokens.fontWeightRegular,
          height: 1.15,
        );
    final disabledButtonBg = Color.alphaBlend(
      cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.78),
      cardBaseBg,
    );
    final disabledButtonFg = _habitReadableTintForeground(
      disabledButtonBg,
      cs.onSurface.withValues(alpha: 0.68),
      isDark: isDark,
    );

    return _HabitSwipeActionWrapper(
      habit: habit,
      actionMargin: margin,
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: AppSurfaceCard(
        key: ValueKey('habit_checkin_card_${habit.id}'),
        margin: margin,
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HabitDetailScreen(habitId: habit.id),
          ),
        ),
        gradient: isDone || hasNegativeOccurrence
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  habitColor.withValues(alpha: isDark ? 0.16 : 0.08),
                  cs.surface.withValues(alpha: 0.98),
                ],
              )
            : null,
        border: Border.all(
          color: isDone || hasNegativeOccurrence
              ? habitColor.withValues(alpha: isDark ? 0.24 : 0.16)
              : cs.outlineVariant.withValues(alpha: isDark ? 0.10 : 0.14),
          width: 0.55,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textDirection =
                Directionality.maybeOf(context) ?? TextDirection.ltr;
            final textScaler = MediaQuery.textScalerOf(context);
            final cardInnerWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 360.0 - _habitCardHorizontalChrome;
            final layout = _resolveHabitCheckinCardLayout(
              habit: habit,
              presentation: presentation,
              cardInnerWidth: cardInnerWidth,
              textDirection: textDirection,
              textScaler: textScaler,
              titleStyle: titleStyle,
              metaStyle: metaStyle,
              badgeTextStyle: badgeTextStyle,
              buttonTextStyle: buttonTextStyle,
            );

            final leadingIcon = Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: habitColor.withValues(
                  alpha: isDone && !hasNegativeOccurrence ? 0.22 : 0.13,
                ),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: habitColor.withValues(alpha: 0.16),
                  width: 0.5,
                ),
              ),
              child: Icon(
                _habitDisplayIcon(habit),
                color: habitColor,
                size: 12,
              ),
            );

            final titleWidget = Text(
              habit.name,
              softWrap: true,
              style: titleStyle,
            );
            final feedbackBadge = presentation.feedbackLabel != null
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _HabitFeedbackBadge(
                      key: presentation.feedbackKey,
                      icon: presentation.feedbackIcon!,
                      label: presentation.feedbackLabel!,
                      color: presentation.feedbackColor!,
                      surfaceBase: cardEffectiveBg,
                      textStyle: badgeTextStyle,
                    ),
                  )
                : null;
            final titleBlock = feedbackBadge == null
                ? titleWidget
                : (layout.inlineTitleAndBadge
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: titleWidget),
                            const SizedBox(width: 6),
                            feedbackBadge,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            titleWidget,
                            const SizedBox(height: 3),
                            feedbackBadge,
                          ],
                        ));

            final metaWidget = Text(
              presentation.metaText,
              softWrap: true,
              style: metaStyle,
            );
            final streakBadge = presentation.streakText != null
                ? _HabitStreakBadge(
                    habit: habit,
                    surfaceBase: cardEffectiveBg,
                    textStyle: badgeTextStyle,
                  )
                : null;
            final metaBlock = streakBadge == null
                ? metaWidget
                : (layout.inlineMetaAndStreak
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: metaWidget),
                            const SizedBox(width: 8),
                            streakBadge,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            metaWidget,
                            const SizedBox(height: 3),
                            streakBadge,
                          ],
                        ));

            final infoColumn = Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 2),
                metaBlock,
                const SizedBox(height: 3),
                LayoutBuilder(
                  builder: (context, barConstraints) {
                    return Stack(
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: isDark ? 0.20 : 0.44,
                            ),
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusPill,
                            ),
                          ),
                        ),
                        Container(
                          height: 4,
                          width: barConstraints.maxWidth * progress,
                          decoration: BoxDecoration(
                            color: isDone && !hasNegativeOccurrence
                                ? DesignTokens.defaultSuccess
                                : habitColor,
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusPill,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (habit.tags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final tag in habit.tags.take(3))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: habitColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: habitColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            );

            final undoControl = Visibility(
              visible: todayCount > 0,
              child: todayCount > 0
                  ? _HabitUndoButton(
                      key: const ValueKey('habit-undo-visible'),
                      color: hasNegativeOccurrence
                          ? cs.error
                          : cs.onSurfaceVariant,
                      surfaceBase: cardEffectiveBg,
                      onPressed: origin != null
                          ? () => _handleUndo(context, origin)
                          : null,
                    )
                  : _HabitUndoButton(
                      key: const ValueKey('habit-undo-hidden'),
                      color: cs.onSurfaceVariant,
                      surfaceBase: cardEffectiveBg,
                      onPressed: null,
                    ),
            );

            final checkInOnPressed = canCheckIn && origin != null
                ? () => _handleCheckIn(context, origin)
                : null;
            final checkInButton = FilledButton(
              onPressed: checkInOnPressed,
              style: FilledButton.styleFrom(
                backgroundColor: habitColor,
                foregroundColor: _habitButtonForeground(habitColor),
                disabledBackgroundColor: disabledButtonBg,
                disabledForegroundColor: disabledButtonFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: const Size(_habitMinTouchTarget, 34),
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
                textStyle: buttonTextStyle,
              ),
              child: Text(
                presentation.checkInLabel,
                textAlign: TextAlign.center,
                softWrap: true,
              ),
            );
            final checkInControl = checkInOnPressed == null
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () {},
                    child: checkInButton,
                  )
                : checkInButton;

            if (!layout.stackActions) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leadingIcon,
                  const SizedBox(width: 9),
                  Expanded(child: infoColumn),
                  const SizedBox(width: _habitCardActionGap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      undoControl,
                      if (todayCount > 0)
                        const SizedBox(width: _habitActionButtonGap),
                      checkInControl,
                    ],
                  ),
                ],
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    leadingIcon,
                    const SizedBox(width: 9),
                    Expanded(child: infoColumn),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: _habitActionButtonGap,
                    runSpacing: _habitActionButtonGap,
                    children: [
                      if (todayCount > 0) undoControl,
                      checkInControl,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleCheckIn(
    BuildContext context,
    HabitActionOrigin origin,
  ) async {
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    final isNegative = habit.kind == HabitKind.negative;
    final currentCount = habit.todayCount();
    final currentFlexProgress = habit.flexProgressForDate(DateTime.now());
    if (!isNegative &&
        habit.hasFlexRule &&
        (currentFlexProgress?.isCompleted ?? false)) {
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.periodGoalReached(
          habit.name,
          currentFlexProgress?.labelPrefix ??
              (locale == AppLocale.en ? 'period' : '本周期'),
          locale,
        ),
        origin: origin,
      );
      return;
    }
    if (!isNegative && habit.hasFlexRule && currentCount >= habit.targetCount) {
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.singleSessionGoalReached(habit.name, locale),
        origin: origin,
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

    try {
      await origin.habitProvider.incrementHabit(habit.id);
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.checkInFailedWithRetry(locale),
        origin: origin,
      );
      return;
    }

    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    await performAppHaptic(
      context,
      AppHaptic.mediumImpact,
      isCurrent: () => origin.isValid(context, checkCurrentRoute: true),
    );
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    await SystemSound.play(SystemSoundType.click);

    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    final updatedMatches = origin.habitProvider.habits.where(
      (item) => item.id == habit.id,
    );
    final displayHabit = updatedMatches.isEmpty ? habit : updatedMatches.first;
    final updatedCount = displayHabit.todayCount();
    final flexProgress = displayHabit.flexProgressForDate(DateTime.now());

    showHabitSafeFeedback(context, (locale) {
      if (isNegative) {
        return HabitUiCopy.checkInSuccessNegative(displayHabit.name, locale);
      }
      if (displayHabit.hasFlexRule) {
        return HabitUiCopy.checkInSuccessFlex(
          displayHabit.name,
          updatedCount,
          displayHabit.targetCount,
          flexProgress?.label,
          flexProgress?.isCompleted ?? false,
          flexProgress?.labelPrefix,
          locale,
        );
      }
      return HabitUiCopy.checkInSuccessStandard(
        displayHabit.name,
        updatedCount,
        displayHabit.targetCount,
        willReachTarget,
        locale,
      );
    }, origin: origin);
  }

  Future<void> _handleUndo(
    BuildContext context,
    HabitActionOrigin origin,
  ) async {
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    try {
      await origin.habitProvider.decrementHabit(habit.id);
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.undoFailedWithRetry(locale),
        origin: origin,
      );
      return;
    }
    if (!context.mounted || !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    await performAppHaptic(
      context,
      AppHaptic.selectionClick,
      isCurrent: () => origin.isValid(context, checkCurrentRoute: true),
    );
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
  final isEn = I18n.current == AppLocale.en;
  if (habit.kind == HabitKind.negative) return isEn ? 'Record' : '记录';
  if (canCheckIn) return isEn ? 'Check in' : '打卡';
  if (!habit.hasFlexRule) return isEn ? 'Done' : '完成';
  if (flexProgress?.isCompleted ?? false) {
    return isEn
        ? '${flexProgress?.labelPrefix ?? 'Period'} done'
        : '${flexProgress?.labelPrefix ?? '周期'}完成';
  }
  return isEn ? 'Done today' : '今日完成';
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
    final origin = HabitActionOrigin.capture(context);
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
                  () => _handleHabitMenuAction(
                    context,
                    widget.habit,
                    'edit',
                    origin,
                  ),
                ),
                onEnd: () => _runAction(
                  () => _handleHabitMenuAction(
                    context,
                    widget.habit,
                    'end',
                    origin,
                  ),
                ),
                onDelete: () => _runAction(
                  () => _handleHabitMenuAction(
                    context,
                    widget.habit,
                    'delete',
                    origin,
                  ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final stripBg = Color.alphaBlend(
      cs.surfaceContainerHighest.withValues(alpha: 0.88),
      cs.surface,
    );
    final editBg = Color.alphaBlend(
      cs.primaryContainer.withValues(alpha: 0.72),
      stripBg,
    );
    final editFg = _habitReadableTintForeground(
      editBg,
      cs.primary,
      isDark: isDark,
    );
    final endBg = Color.alphaBlend(
      cs.tertiaryContainer.withValues(alpha: 0.72),
      stripBg,
    );
    final endFg = _habitReadableTintForeground(
      endBg,
      cs.tertiary,
      isDark: isDark,
    );
    final deleteBg = Color.alphaBlend(
      cs.errorContainer.withValues(alpha: 0.74),
      stripBg,
    );
    final deleteFg = _habitReadableTintForeground(
      deleteBg,
      cs.error,
      isDark: isDark,
    );

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        return Container(
          margin: margin,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: stripBg,
            borderRadius: borderRadius,
          ),
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: _habitSwipeActionWidth,
            height: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _habitSwipeHorizontalPadding,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _HabitSwipeButton(
                    key: const ValueKey('habit_swipe_edit_button'),
                    icon: Icons.edit_outlined,
                    label: HabitUiCopy.actionEdit(locale),
                    background: editBg,
                    foreground: editFg,
                    onTap: onEdit,
                  ),
                  if (showEndAction) ...[
                    const SizedBox(width: _habitSwipeButtonGap),
                    _HabitSwipeButton(
                      key: const ValueKey('habit_swipe_end_button'),
                      icon: Icons.event_busy_outlined,
                      label: HabitUiCopy.actionEnd(locale),
                      background: endBg,
                      foreground: endFg,
                      onTap: onEnd,
                    ),
                  ],
                  const SizedBox(width: _habitSwipeButtonGap),
                  _HabitSwipeButton(
                    key: const ValueKey('habit_swipe_delete_button'),
                    icon: Icons.delete_outline,
                    label: HabitUiCopy.actionDelete(locale),
                    background: deleteBg,
                    foreground: deleteFg,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
            dimension: _habitSwipeButtonSize,
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
    return Tooltip(message: label, child: child);
  }
}

class _HabitStreakBadge extends StatelessWidget {
  final Habit habit;
  final Color? surfaceBase;
  final TextStyle? textStyle;

  const _HabitStreakBadge({
    required this.habit,
    this.surfaceBase,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = Color.lerp(
      const Color(0xFFF57C00),
      cs.primary,
      isDark ? 0.18 : 0.06,
    )!;
    final badgeBg = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.16 : 0.12),
      surfaceBase ?? cs.surface,
    );
    final readableFg = _habitReadableTintForeground(
      badgeBg,
      accent,
      isDark: isDark,
    );
    final resolvedStyle =
        (textStyle ??
                (theme.textTheme.bodyMedium ??
                    DefaultTextStyle.of(context).style))
            .copyWith(
              color: readableFg,
              fontWeight: DesignTokens.fontWeightRegular,
              fontSize: 10,
              height: 1.15,
            );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.24 : 0.18),
          width: 0.45,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 11, color: readableFg),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${habit.currentStreak} ${habit.streakUnitLabel}',
              softWrap: true,
              style: resolvedStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitUndoButton extends StatelessWidget {
  final Color color;
  final Color? surfaceBase;
  final VoidCallback? onPressed;

  const _HabitUndoButton({
    super.key,
    required this.color,
    this.surfaceBase,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isEn = I18n.current == AppLocale.en;
    final undoBg = Color.alphaBlend(
      color.withValues(alpha: isDark ? 0.14 : 0.10),
      surfaceBase ?? cs.surface,
    );
    final undoFg = _habitReadableTintForeground(undoBg, color, isDark: isDark);
    return IconButton(
      key: const ValueKey('habit-undo-inline-button'),
      onPressed: onPressed,
      tooltip: isEn ? 'Undo once' : '撤回一次',
      icon: const Icon(Icons.undo_rounded, size: 15),
      style: IconButton.styleFrom(
        backgroundColor: undoBg,
        foregroundColor: undoFg,
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        padding: EdgeInsets.zero,
        side: BorderSide(color: undoFg.withValues(alpha: 0.22), width: 0.45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}

class _HabitFeedbackBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? surfaceBase;
  final TextStyle? textStyle;

  const _HabitFeedbackBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.surfaceBase,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final badgeBg = Color.alphaBlend(
      color.withValues(alpha: isDark ? 0.16 : 0.12),
      surfaceBase ?? cs.surface,
    );
    final readableFg = _habitReadableTintForeground(
      badgeBg,
      color,
      isDark: isDark,
    );
    final resolvedStyle =
        (textStyle ??
                (theme.textTheme.bodyMedium ??
                    DefaultTextStyle.of(context).style))
            .copyWith(
              color: readableFg,
              fontSize: 10,
              fontWeight: DesignTokens.fontWeightRegular,
              height: 1.15,
            );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.24 : 0.18),
          width: 0.45,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: readableFg),
            const SizedBox(width: 3),
            Flexible(
              child: Text(label, softWrap: true, style: resolvedStyle),
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
  String value, [
  HabitActionOrigin? actionOrigin,
]) async {
  final origin = actionOrigin ?? HabitActionOrigin.capture(context);
  if (origin == null || !origin.isValid(context, checkCurrentRoute: true)) {
    return;
  }
  if (value == 'edit') {
    await showHabitEditor(context, habit, actionOrigin: origin);
    return;
  }
  if (value == 'end') {
    final confirmed = await confirmHabitEnd(context, habit, origin: origin);
    if (!confirmed ||
        !context.mounted ||
        !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    try {
      await origin.habitProvider.endHabit(habit.id);
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.endedFeedback(locale),
        origin: origin,
      );
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.actionFailedWithRetry(locale),
        origin: origin,
      );
    }
    return;
  }
  if (value == 'delete') {
    final confirmed = await confirmHabitDelete(context, habit, origin: origin);
    if (!confirmed ||
        !context.mounted ||
        !origin.isValid(context, checkCurrentRoute: true)) {
      return;
    }
    try {
      await origin.habitProvider.deleteHabit(habit.id);
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.deletedFeedback(locale),
        origin: origin,
      );
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (!context.mounted ||
          !origin.isValid(context, checkCurrentRoute: true)) {
        return;
      }
      showHabitSafeFeedback(
        context,
        (locale) => HabitUiCopy.actionFailedWithRetry(locale),
        origin: origin,
      );
    }
  }
}

ReminderPlan _habitPopupDailyReminderPlan(List<TimeOfDay> times) {
  if (times.isEmpty) return const ReminderPlan.disabled();
  return ReminderPlan(
    enabled: true,
    rules: [
      for (final time in times)
        ReminderRule(
          type: ReminderRuleType.dailyTime,
          kind: ReminderKind.popup,
          hour: time.hour,
          minute: time.minute,
        ),
    ],
  );
}

DateTime? _nextHabitReminderTriggerForTimes(List<TimeOfDay> times) {
  DateTime? next;
  final now = DateTime.now();
  for (final time in times) {
    var target = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!target.isAfter(now)) {
      final tomorrow = now.add(const Duration(days: 1));
      target = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        time.hour,
        time.minute,
      );
    }
    if (next == null || target.isBefore(next)) next = target;
  }
  return next;
}

Color _habitButtonForeground(Color background) {
  final whiteContrast = _habitContrastRatio(background, Colors.white);
  if (whiteContrast >= 4.5) return Colors.white;
  return appReadableForeground(background, Colors.white);
}

Color _habitReadableTintForeground(
  Color background,
  Color accent, {
  required bool isDark,
}) {
  final effective = Color.alphaBlend(accent, background);
  if (_habitContrastRatio(background, effective) >= 4.5) return effective;
  final target = isDark ? Colors.white : const Color(0xFF111827);
  for (final t in const [0.15, 0.30, 0.45, 0.60, 0.75, 0.90]) {
    final candidate = Color.lerp(effective, target, t)!;
    if (_habitContrastRatio(background, candidate) >= 4.5) {
      return candidate;
    }
  }
  return appReadableForeground(background, target);
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
  final copy = HabitUiCopy(I18n.current);
  return switch (template.flexPeriod!) {
    HabitFlexPeriod.week => copy.weekGoal(template.flexTarget!),
    HabitFlexPeriod.month => copy.monthGoal(template.flexTarget!),
  };
}

String _habitReminderSyncIssueText(String issue, [AppLocale? locale]) {
  if (issue == 'reminder_scheduler_missing') {
    return HabitUiCopy.reminderSchedulerMissing(locale);
  }
  return issue;
}
