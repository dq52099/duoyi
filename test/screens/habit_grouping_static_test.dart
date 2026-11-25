import 'dart:io';

import 'package:test/test.dart';

import 'package:duoyi/core/habit_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';

void main() {
  test('习惯页提供可见分组列表并沿用习惯分类字段', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains("import '../core/habit_grouping.dart';"));
    expect(source, contains('groupHabitsByCategory(provider.habits)'));
    expect(source, contains('_HabitGroupSection'));
    expect(source, contains('ExpansionTile('));
    expect(source, contains('const int _habitHeatmapGroupPreviewLimit = 8'));
    expect(
      source,
      matches(
        RegExp(
          r'initiallyExpanded:\s*group\.habits\.length\s*<=\s*_habitHeatmapGroupPreviewLimit',
        ),
      ),
    );
    expect(source, contains('for (final habit in previewHabits)'));
    expect(source, contains('HeatmapUiCopy(I18n.current).habitGroups'));
    expect(
      File('lib/core/heatmap_ui_copy.dart').readAsStringSync(),
      contains('习惯分组'),
    );
    expect(source, contains('Icons.folder_outlined'));
    expect(
      source.replaceAll(RegExp(r'\s+'), ''),
      contains('category:habitCategoryOrNull(categoryCtrl.text,),'),
    );
  });

  test('习惯模板选择会带入分类，手动创建也暴露分组字段', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains('final categoryCtrl = TextEditingController()'));
    expect(source, contains('selectedKind = HabitKind.positive'));
    expect(source, contains('selectedIcon = habitIconTokenForIcon('));
    expect(source, contains('t.icon'));
    expect(
      source,
      matches(
        RegExp(r'unitDraft\.selectGenerated\(\s*t\.generatedUnitKey,?\s*\)'),
      ),
    );
    expect(
      source,
      matches(RegExp(r'categoryCtrl\.text\s*=\s*t\.localizedCategory')),
    );
    expect(source, contains('flexRuleEnabled = t.hasFlexRule'));
    expect(source, contains('selectedFlexPeriod = t.flexPeriod!'));
    expect(source, contains('flexTargetCtrl.text = t.flexTarget!'));
    expect(source, contains('t.localizedFrequencyLabel'));
    expect(source, contains("labelText: '分组'"));
    expect(source, contains("hintText: '例如 身体健康、学习提升'"));
  });

  test('习惯详情编辑支持修改或清空分组', () {
    final source = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/habit_grouping.dart';"));
    expect(
      source,
      contains(
        "final categoryCtrl = TextEditingController(text: habit.category ?? '')",
      ),
    );
    expect(
      source,
      contains('category: habitCategoryOrNull(categoryCtrl.text)'),
    );
    expect(source, contains('clearCategory:'));
    expect(source, contains('defaultHabitCategoryName'));
    expect(source, contains("I18n.tr('habit.field.group.empty_hint')"));
  });

  test('习惯详情页直接暴露结束和删除操作', () {
    final source = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final copy = File('lib/core/habit_ui_copy.dart').readAsStringSync();
    final compactSource = source.replaceAll(RegExp(r'\s+'), '');

    expect(source, contains('OutlinedButton.icon('));
    expect(source, contains('HabitUiCopy.endHabitAction(locale)'));
    expect(source, contains('HabitUiCopy.actionDelete(locale)'));
    expect(source, contains('_habitDetailActionButtonStyle(context)'));
    expect(source, contains('_habitDangerOutlinedButtonStyle(context)'));
    expect(source, contains('Icons.event_busy_outlined'));
    expect(source, contains('Icons.delete_outline'));
    expect(source, contains('origin.habitProvider.endHabit(habit.id)'));
    expect(source, contains('origin.habitProvider.deleteHabit(habit.id)'));
    expect(source, contains('_executeEndHabit(context, habit, origin)'));
    expect(source, contains('_executeDeleteHabit(context, habit, origin)'));
    expect(
      source,
      contains('origin.isValid(context, checkCurrentRoute: true)'),
    );
    expect(source, contains('HabitUiCopy.deleteConfirmTitle(locale)'));
    expect(source, contains('HabitUiCopy.endConfirmTitle(locale)'));
    expect(source, contains('HabitUiCopy.actionCancel(locale)'));
    expect(source, contains('HabitUiCopy.endedFeedback(loc)'));
    expect(source, contains('HabitUiCopy.deletedFeedback(loc)'));
    expect(copy, contains('static String actionCancel('));
    expect(copy, contains('static String endHabitAction('));
    expect(copy, contains('static String deleteHabitAction('));
    expect(copy, contains('static String deleteConfirmTitle('));
    expect(copy, contains('static String endConfirmTitle('));
    expect(source, contains('HabitUiCopy.moreActions(locale)'));
    expect(source, contains("value: 'end'"));
    expect(source, contains('title: Text(HabitUiCopy.endHabitAction(locale))'));
    expect(source, contains("value: 'delete'"));
    expect(source, contains('HabitUiCopy.deleteHabitAction(locale)'));
    expect(source, isNot(contains("value == 'detail'")));
    expect(source, contains('habitDisplayIconFor(habit)'));
    expect(
      File('lib/core/habit_icons.dart').readAsStringSync(),
      contains('IconData habitDisplayIconFor(Habit habit)'),
    );
    expect(source, isNot(contains('IconData(codePoint')));
    expect(source, isNot(contains('child: Icon(Icons.star')));
    expect(
      compactSource,
      contains('builder:(ctx)=>ValueListenableBuilder<AppLocale>('),
    );
    expect(compactSource, contains('returnAppDialog('));
    expect(
      compactSource,
      contains('authority.isValid(ctx,specificRoute:route)'),
    );
    expect(compactSource, isNot(contains('builder:(ctx)=>AlertDialog(')));
  });

  test('习惯打卡提供完成反馈和轻量动效', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final feedback = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final copy = File('lib/core/habit_ui_copy.dart').readAsStringSync();
    final undoStart = source.indexOf('class _HabitUndoButton');
    final undoEnd = source.indexOf('class _HabitFeedbackBadge', undoStart);
    expect(undoStart, greaterThanOrEqualTo(0));
    expect(undoEnd, greaterThan(undoStart));
    final undoSource = source.substring(undoStart, undoEnd);
    final presentationStart = source.indexOf('class _HabitCheckinPresentation {');
    final presentationEnd = source.indexOf('class _HabitCheckinCardLayout {');
    expect(presentationStart, greaterThanOrEqualTo(0));
    expect(presentationEnd, greaterThan(presentationStart));
    final presentationSource = source.substring(presentationStart, presentationEnd);

    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, contains("import '../services/app_haptics.dart';"));
    expect(source, isNot(contains('AnimatedScale(')));
    expect(source, contains('AnimatedSwitcher('));
    expect(source, contains('_HabitFeedbackBadge'));
    expect(source, contains('AppHaptic.mediumImpact'));
    expect(source, contains('await performAppHaptic('));
    expect(source, contains('SystemSound.play(SystemSoundType.click)'));
    expect(source, contains('AppHaptic.selectionClick'));
    expect(source, contains("'habit-undo-inline-button'"));
    expect(source, contains('IconButton('));
    // Public geometry cases check the actual Undo node and localized tooltip.
    expect(undoSource, contains("'撤回一次'"));
    expect(undoSource, contains("'Undo once'"));
    expect(source, isNot(contains("label: const Text('还原')")));
    // 2351 measures the independent undo hit/semantics bounds and edge taps.
    // Its public oracle replaces the old compact painted-size ceiling.
    expect(undoSource, contains('minimumSize:'));
    expect(undoSource, contains('tapTargetSize: MaterialTapTargetSize.padded'));
    expect(undoSource, isNot(contains('fixedSize:')));
    expect(source, contains('showHabitSafeFeedback('));
    expect(source, contains('HabitUiCopy.checkInSuccessStandard('));
    expect(source, contains('HabitUiCopy.checkInSuccessFlex('));
    expect(source, contains('HabitUiCopy.checkInSuccessNegative('));
    expect(feedback, contains('void showHabitSafeFeedback('));
    expect(feedback, contains('messenger.removeCurrentSnackBar()'));
    expect(feedback, contains('messageBuilder(locale)'));
    expect(feedback, contains('origin.isValid('));
    expect(copy, contains('static String checkInSuccessStandard('));
    expect(copy, contains('static String checkInSuccessFlex('));
    expect(copy, contains('static String checkInSuccessNegative('));
    expect(
      HabitUiCopy.checkInSuccessStandard('Habit', 1, 1, true, AppLocale.zh),
      '「Habit」今日已达标',
    );
    expect(
      HabitUiCopy.checkInSuccessStandard('Habit', 1, 1, true, AppLocale.en),
      '"Habit" goal reached today',
    );
    expect(copy, contains('l10n.habitCopyCheckInSuccessStandardReached(habitName)'));
    expect(presentationSource, contains("feedbackLabel = habit.hasFlexRule"));
    expect(source, contains("isEn ? 'Completed' : '已达标'"));
    expect(presentationSource, contains("feedbackLabel = isEn ? 'Recorded' : '已记录'"));
  });

  test('习惯打卡卡片采用紧凑排版让一屏展示更多任务', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final copy = File('lib/core/habit_ui_copy.dart').readAsStringSync();
    final cardStart = source.indexOf('class _HabitCheckinCard extends StatelessWidget');
    final cardEnd = source.indexOf('Future<void> _handleCheckIn', cardStart);
    expect(cardStart, greaterThanOrEqualTo(0));
    expect(cardEnd, greaterThan(cardStart));
    final cardSource = source.substring(cardStart, cardEnd);
    final presentationStart = source.indexOf('class _HabitCheckinPresentation {');
    final presentationEnd = source.indexOf('class _HabitCheckinCardLayout {');
    expect(presentationStart, greaterThanOrEqualTo(0));
    expect(presentationEnd, greaterThan(presentationStart));
    final presentationSource = source.substring(presentationStart, presentationEnd);
    final sliverStart = source.indexOf('Widget _buildTodayCheckinSliver(');
    final sliverEnd = source.indexOf('bool _habitCanEnd(', sliverStart);
    expect(sliverStart, greaterThanOrEqualTo(0));
    expect(sliverEnd, greaterThan(sliverStart));
    final checkinSliverSource = source.substring(sliverStart, sliverEnd);
    final swipeActionsStart = source.indexOf('class _HabitInlineSwipeActions');
    final swipeButtonStart = source.indexOf(
      'class _HabitSwipeButton',
      swipeActionsStart,
    );
    expect(swipeActionsStart, greaterThanOrEqualTo(0));
    expect(swipeButtonStart, greaterThan(swipeActionsStart));
    final swipeActions = source.substring(swipeActionsStart, swipeButtonStart);

    expect(
      cardSource,
      contains('this.margin = const EdgeInsets.fromLTRB(10, 0, 10, 1)'),
    );
    // 2351 observes full paragraphs and real card/row bounds; density cannot
    // require fixed body/title/control heights or the old vertical padding.
    expect(cardSource, contains('LayoutBuilder('));
    expect(cardSource, isNot(contains('FittedBox(')));
    expect(source, isNot(contains('const double _habitMenuButtonWidth')));
    // Lazy paired rows retain reachability without a uniform private extent.
    expect(checkinSliverSource, contains('SliverList.builder('));
    expect(checkinSliverSource, contains('itemBuilder:'));
    expect(cardSource, contains('width: 20'));
    expect(cardSource, contains('height: 20'));
    expect(cardSource, contains('height: 2'));
    // Public target/semantics rectangles and edge taps own minimum sizing.
    expect(cardSource, contains('minimumSize: const Size('));
    expect(cardSource, contains('tapTargetSize: MaterialTapTargetSize.padded'));
    expect(cardSource, contains('_habitDisplayIcon(habit)'));
    expect(source, contains('_HabitSummaryTile'));
    expect(source, contains('_habitDisplayIcon(habit)'));
    expect(source, contains("import '../core/habit_icons.dart';"));
    expect(source, isNot(contains('IconData(codePoint')));
    expect(source, isNot(contains('Icon(Icons.star')));
    expect(source, isNot(contains('child: Icon(Icons.star')));
    expect(cardSource, isNot(contains('Icons.shield_outlined')));
    expect(cardSource, isNot(contains('Icons.warning_amber_rounded')));
    expect(cardSource, isNot(contains('Icons.verified_rounded')));
    expect(cardSource, isNot(contains('_HabitEditButton(habit: habit)')));
    expect(
      source,
      isNot(contains('class _HabitEditButton extends StatelessWidget')),
    );
    expect(
      source,
      isNot(contains("key: const ValueKey('habit_inline_edit_button')")),
    );
    expect(source, contains('message: label'));
    expect(source, isNot(contains("tooltip: '习惯操作'")));
    expect(source, isNot(contains('PopupMenuButton<String>')));
    expect(source, contains('class _HabitInlineSwipeActions'));
    expect(source, contains("key: const ValueKey('habit_swipe_edit_button')"));
    expect(source, contains("key: const ValueKey('habit_swipe_end_button')"));
    expect(
      source,
      contains("key: const ValueKey('habit_swipe_delete_button')"),
    );
    expect(swipeActions, contains('label: HabitUiCopy.actionEdit(locale)'));
    expect(swipeActions, contains('label: HabitUiCopy.actionEnd(locale)'));
    expect(swipeActions, contains('label: HabitUiCopy.actionDelete(locale)'));
    expect(source, contains('Semantics('));
    expect(source, contains('button: true'));
    expect(source, contains('label: label'));
    expect(source, contains('Tooltip(message: label, child: child)'));
    expect(copy, contains('static String actionEdit('));
    expect(copy, contains('static String actionEnd('));
    expect(copy, contains('static String actionDelete('));
    expect(HabitUiCopy.actionEdit(AppLocale.zh), '编辑');
    expect(HabitUiCopy.actionEdit(AppLocale.en), 'Edit');
    expect(HabitUiCopy.actionEnd(AppLocale.zh), '结束');
    expect(HabitUiCopy.actionEnd(AppLocale.en), 'End');
    expect(HabitUiCopy.actionDelete(AppLocale.zh), '删除');
    expect(HabitUiCopy.actionDelete(AppLocale.en), 'Delete');
    expect(copy, contains('_l10nFor(locale).actionEdit'));
    expect(copy, contains('_l10nFor(locale).habitCopyActionEnd'));
    expect(copy, contains('_l10nFor(locale).actionDelete'));
    expect(source, isNot(contains("PopupMenuItem(value: 'end'")));
    expect(source, isNot(contains("value: 'delete'")));
    expect(
      source,
      isNot(contains("AppSecondaryMenuText('删除习惯', color: cs.error)")),
    );
    expect(cardSource, contains('Visibility('));
    expect(cardSource, isNot(contains('maintainSize: true')));
    expect(
      cardSource,
      contains('const SizedBox(width: _habitActionButtonGap)'),
    );
    expect(presentationSource, contains("'\$targetText · \$countText'"));
    expect(presentationSource, contains('habit.currentStreak > 0'));
    expect(cardSource, contains('presentation.streakText != null'));
    expect(cardSource, isNot(contains('TextOverflow.ellipsis')));
  });

  test('习惯本周概览置顶且保持紧凑', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final weekly = File(
      'lib/widgets/habit_weekly_card.dart',
    ).readAsStringSync();

    final weeklyIndex = screen.indexOf(
      'SliverToBoxAdapter(child: HabitWeeklyCard())',
    );
    final scrollViewIndex = screen.indexOf(
      "key: const ValueKey('habit_today_scroll_view')",
    );
    final sliversIndex = screen.indexOf('slivers: [', scrollViewIndex);
    final insightIndex = screen.indexOf(
      "key: const ValueKey('habit_insight_before_today_list')",
    );
    expect(scrollViewIndex, greaterThanOrEqualTo(0));
    expect(sliversIndex, greaterThan(scrollViewIndex));
    expect(weeklyIndex, greaterThanOrEqualTo(0));
    expect(weeklyIndex, greaterThan(sliversIndex));
    expect(weeklyIndex, lessThan(insightIndex));
    expect(weeklyIndex, lessThan(screen.indexOf('_HabitTodaySummaryCard(')));
    expect(
      weeklyIndex,
      lessThan(
        screen.indexOf("key: const ValueKey('habit_today_checkin_sliver')"),
      ),
    );
    expect(
      weeklyIndex,
      lessThan(
        screen.indexOf("key: const ValueKey('habit_today_empty_state_sliver')"),
      ),
    );
    expect(
      weekly,
      contains("key: const ValueKey('habit_weekly_overview_card')"),
    );
    expect(weekly, contains('context.watch<HabitProvider>()'));
    expect(weekly, contains('final data = provider.currentWeekProgress();'));
    expect(weekly, contains('margin: const EdgeInsets.fromLTRB(10, 4, 10, 4)'));
    expect(weekly, contains('padding: const EdgeInsets.fromLTRB(8, 6, 8, 7)'));
    expect(weekly, contains('currentWeekProgress()'));
    expect(
      weekly,
      contains('borderRadius: BorderRadius.circular(DesignTokens.radiusCard)'),
    );
    expect(weekly, contains('fontSize: 13'));
    expect(weekly, contains('fontSize: DesignTokens.fontSizeCaption'));
    expect(weekly, contains('minHeight: 3'));
    expect(weekly, contains('width: 30'));
    expect(weekly, contains('height: 30'));
    expect(weekly, contains('width: 25'));
    expect(weekly, contains('height: 25'));
    expect(weekly, contains('fontWeight: DesignTokens.fontWeightRegular'));
  });

  test('习惯达标状态与任务名同一行靠右展示', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final cardStart = source.indexOf('class _HabitCheckinCard extends StatelessWidget');
    expect(cardStart, greaterThanOrEqualTo(0));
    final cardEnd = source.indexOf('Future<void> _handleCheckIn', cardStart);
    expect(cardEnd, greaterThan(cardStart));
    final cardSource = source.substring(cardStart, cardEnd);
    final presentationStart = source.indexOf('class _HabitCheckinPresentation {');
    final presentationEnd = source.indexOf('class _HabitCheckinCardLayout {');
    expect(presentationStart, greaterThanOrEqualTo(0));
    expect(presentationEnd, greaterThan(presentationStart));
    final presentationSource = source.substring(presentationStart, presentationEnd);
    final nameIndex = cardSource.indexOf('habit.name');
    final badgeIndex = cardSource.indexOf('_HabitFeedbackBadge');
    final streakIndex = cardSource.indexOf('presentation.streakText != null');

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(badgeIndex, greaterThan(nameIndex));
    expect(streakIndex, greaterThan(badgeIndex));
    expect(presentationSource, contains("'habit-completed-feedback'"));
    expect(presentationSource, contains("'\${habit.currentStreak} \${habit.streakUnitLabel}'"));
    expect(cardSource, contains('key: const ValueKey('));
    expect(presentationSource, contains("'habit-warning-feedback'"));
    // Inline when content fits, reflow below otherwise; 2351 owns real bounds.
    expect(cardSource, contains('layout.inlineTitleAndBadge'));
  });

  test('习惯打卡先落盘再通知界面，且不被耗时记录拖住状态', () {
    final source = File('lib/providers/habit_provider.dart').readAsStringSync();

    final incrementStart = source.indexOf('Future<void> incrementHabitForDate');
    final decrementStart = source.indexOf('Future<void> decrementHabitForDate');
    final defaultStart = source.indexOf('int _defaultCheckInAmount');
    expect(incrementStart, greaterThanOrEqualTo(0));
    expect(decrementStart, greaterThan(incrementStart));
    expect(defaultStart, greaterThan(decrementStart));

    final incrementBody = source.substring(incrementStart, decrementStart);
    final decrementBody = source.substring(decrementStart, defaultStart);

    expect(
      incrementBody.indexOf('await _save();'),
      lessThan(incrementBody.indexOf('notifyListeners();')),
    );
    expect(
      incrementBody.indexOf('notifyListeners();'),
      lessThan(incrementBody.indexOf('await timeAudit.recordHabitCheckIn(')),
    );
    expect(
      decrementBody.indexOf('await _save();'),
      lessThan(decrementBody.indexOf('notifyListeners();')),
    );
    expect(
      decrementBody.indexOf('notifyListeners();'),
      lessThan(decrementBody.indexOf('await timeAudit.removeHabitCheckIn(')),
    );
  });

  test('习惯详情提供长期趋势范围切换和区间明细', () {
    final source = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/habit_trend.dart';"));
    expect(source, contains('buildHabitTrendSummary(widget.habit'));
    expect(source, contains('HabitTrendWindow.days30'));
    expect(source, contains('SegmentedButton<HabitTrendWindow>'));
    expect(source, contains('for (final window in HabitTrendWindow.values)'));
    expect(source, contains("I18n.tr('habit.trend.title')"));
    expect(source, contains("I18n.tr('habit.trend.vs_previous')"));
    expect(source, contains("I18n.tr('habit.trend.longest_streak')"));
    expect(source, contains("I18n.tr('habit.trend.bucket_details')"));
    expect(source, contains('_HabitTrendBucketRow'));
  });

  test('习惯首页展示智能习惯洞察', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final weeklyIndex = source.indexOf(
      'SliverToBoxAdapter(child: HabitWeeklyCard())',
    );
    final insightKeyIndex = source.indexOf(
      "key: const ValueKey('habit_insight_before_today_list')",
    );
    final insightIndex = source.indexOf(
      '_HabitInsightSection(habits: provider.habits)',
    );
    final emptyIndex = source.indexOf(
      "key: const ValueKey('habit_today_empty_state_sliver')",
    );
    final summaryIndex = source.indexOf('_HabitTodaySummaryCard(');
    final listIndex = source.indexOf(
      "key: const ValueKey('habit_today_checkin_sliver')",
    );

    expect(source, contains("import '../core/habit_insights.dart';"));
    expect(source, contains('HabitInsightEngine.buildInsights('));
    expect(source, contains('_HabitInsightCard'));
    expect(source, contains('_HabitInsightSection(habits: provider.habits)'));
    expect(
      source,
      contains("key: const ValueKey('habit_insight_before_today_list')"),
    );
    expect(source, contains('智能习惯洞察'));
    expect(weeklyIndex, greaterThanOrEqualTo(0));
    expect(insightKeyIndex, greaterThan(weeklyIndex));
    expect(insightIndex, greaterThan(insightKeyIndex));
    expect(insightIndex, lessThan(emptyIndex));
    expect(insightIndex, lessThan(summaryIndex));
    expect(insightIndex, lessThan(listIndex));
    expect(source, contains('HabitInsightKind.rising'));
    expect(source, contains('HabitInsightKind.slipping'));
  });

  test('习惯创建和详情编辑暴露弹性打卡规则', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final detail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/habit_provider.dart',
    ).readAsStringSync();
    final zh = File('lib/l10n/app_zh.arb').readAsStringSync();
    final en = File('lib/l10n/app_en.arb').readAsStringSync();
    final compactScreen = screen.replaceAll(RegExp(r'\s+'), '');
    final periodSelector = RegExp(
      r'(?:SegmentedButton|DropdownButtonFormField|DropdownButton|DropdownMenu|PopupMenuButton)\s*<\s*HabitFlexPeriod\s*>',
    );

    expect(screen, contains('flexRuleEnabled'));
    expect(screen, matches(periodSelector));
    expect(screen, contains('copy.weekGoal(template.flexTarget!)'));
    expect(screen, contains('copy.monthGoal(template.flexTarget!)'));
    expect(screen, contains("'habit.flex.period_target'"));
    expect(screen, contains("'habit.flex.period_target_hint'"));
    expect(
      compactScreen,
      contains('flexTarget:shouldUseFlex?flexTarget:null,'),
    );
    expect(
      compactScreen,
      contains('flexPeriod:shouldUseFlex?selectedFlexPeriod:null,'),
    );
    expect(screen, contains('_habitFlexGoalText(habit)'));
    expect(screen, contains('copy.weekGoal(habit.effectiveFlexTarget)'));
    expect(screen, contains('copy.monthGoal(habit.effectiveFlexTarget)'));
    expect(screen, contains('habit.streakUnitLabel'));
    expect(compactScreen, contains("I18n.tr('habit.flex.weekly',)"));
    expect(compactScreen, contains("I18n.tr('habit.flex.monthly',)"));
    expect(screen, contains('HabitUiCopy.flexTargetInvalid(loc)'));
    final copy = File('lib/core/habit_ui_copy.dart').readAsStringSync();
    expect(copy, contains('static String flexTargetInvalid('));
    expect(HabitUiCopy.flexTargetInvalid(AppLocale.zh), '周期目标至少为 1');
    expect(
      HabitUiCopy.flexTargetInvalid(AppLocale.en),
      'Period target must be at least 1',
    );
    expect(copy, contains('_l10nFor(locale).habitErrorFlexTarget'));
    expect(
      screen,
      contains('HabitFlexPeriod.week => copy.weekGoal(template.flexTarget!)'),
    );
    expect(
      screen,
      contains('HabitFlexPeriod.month => copy.monthGoal(template.flexTarget!)'),
    );

    expect(detail, contains("I18n.tr('habit.flex.rule')"));
    expect(detail, matches(periodSelector));
    expect(detail, contains('flexRuleEnabled = habit.hasFlexRule'));
    expect(detail, contains('clearFlexRule: !shouldUseFlex'));
    expect(detail, contains('localizedFlexPeriodGoalLabel(habit, locale)'));
    expect(detail, contains('habit.flexProgressForDate(DateTime.now())'));
    expect(detail, contains('localizedHabitCountForDate(habit, d, locale)'));
    expect(detail, contains('_localizedHabitStreakUnit(habit, locale)'));
    expect(detail, contains("'habit.flex.period_target'"));
    expect(detail, contains('copy.weekGoal(habit.effectiveFlexTarget)'));
    expect(detail, contains('copy.monthGoal(habit.effectiveFlexTarget)'));
    expect(detail, contains('String localizedFlexPeriodGoalLabel('));
    expect(detail, contains('I18n.trForLocale(key, locale ?? I18n.current)'));

    expect(provider, contains('_recalcFlexStreak'));
    expect(provider, contains('h.periodBoundsForDate(DateTime.now())'));
    expect(provider, contains('h.previousPeriodBounds(bounds)'));

    expect(zh, contains('"habitFlexWeekly": "每周目标"'));
    expect(zh, contains('"habitFlexMonthly": "每月目标"'));
    expect(zh, contains('"habitFlexPeriodTarget": "目标次数"'));
    expect(zh, contains('"habitFlexPeriodTargetHint": "例如每周目标 5 次"'));
    expect(en, contains('"habitFlexWeekly": "Weekly target"'));
    expect(en, contains('"habitFlexMonthly": "Monthly target"'));
    expect(en, contains('"habitFlexPeriodTarget": "Target count"'));
  });

  test('习惯创建和详情编辑暴露起止日期并禁用周期外补卡', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final detail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final dateFields = File(
      'lib/widgets/habit_date_range_fields.dart',
    ).readAsStringSync();
    final compactScreen = screen.replaceAll(RegExp(r'\s+'), '');
    final compactDetail = detail.replaceAll(RegExp(r'\s+'), '');

    expect(
      screen,
      contains("import '../widgets/habit_date_range_fields.dart';"),
    );
    expect(screen, contains('DateTime? startDate'));
    expect(screen, contains('DateTime? endDate'));
    expect(screen, contains('HabitDateRangeFields('));
    expect(
      compactScreen,
      contains('habitDateRangeIsValid(startDate,endDate,)'),
    );
    expect(screen, contains('startDate: startDate'));
    expect(screen, contains('endDate: endDate'));

    expect(
      detail,
      contains("import '../widgets/habit_date_range_fields.dart';"),
    );
    expect(detail, contains("import '../widgets/app_date_format.dart';"));
    expect(detail, contains('DateTime? startDate = habit.startDate'));
    expect(detail, contains('DateTime? endDate = habit.endDate'));
    expect(detail, contains('HabitDateRangeFields('));
    expect(
      compactDetail,
      contains('onStartChanged:(value)=>setSt(()=>startDate=value)'),
    );
    expect(
      compactDetail,
      contains('onEndChanged:(value)=>setSt(()=>endDate=value)'),
    );
    expect(
      compactDetail,
      contains('!habitDateRangeIsValid(startDate,endDate)'),
    );
    expect(detail, contains('clearStartDate: startDate == null'));
    expect(detail, contains('clearEndDate: endDate == null'));
    expect(detail, contains('habitDateRangeLabel('));
    expect(detail, contains('AppDateFormat.patternOf(context)'));
    expect(dateFields, contains('String habitDateRangeLabel('));
    expect(
      dateFields,
      contains('I18nDateFormat.date(startDate, pattern: pattern)'),
    );
    expect(
      dateFields,
      contains('I18nDateFormat.date(endDate, pattern: pattern)'),
    );
    expect(detail, contains('final activeForDay = habit.activeForDate(d)'));
    expect(detail, contains("I18n.tr('habit.records.inactive')"));
    expect(
      compactDetail,
      contains(
        "if(count>0&&activeForDay)Tooltip(message:I18n.tr('habit.records.undo_once')",
      ),
    );
    expect(
      compactDetail,
      contains(
        'onPressed:(origin==null||!origin.isValid(context,checkCurrentRoute:true,))?null:()=>_handleDateUndo(context,habit,d,origin,)',
      ),
    );
    expect(
      compactDetail,
      contains(
        'onPressed:(activeForDay&&origin!=null&&origin.isValid(context,checkCurrentRoute:true,))?()=>_handleDateRecord(context,habit,d,origin,):null',
      ),
    );

    expect(dateFields, contains("I18n.tr('habit.date_range.start')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.end')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.start_empty')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.end_empty')"));
    expect(dateFields, contains('bool habitDateRangeIsValid'));
    expect(
      dateFields,
      contains('if (startDate == null || endDate == null) return true;'),
    );
    expect(
      dateFields,
      contains(
        'return !habitDateOnly(endDate).isBefore(habitDateOnly(startDate));',
      ),
    );
  });
}
