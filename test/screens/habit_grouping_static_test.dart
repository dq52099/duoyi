import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('习惯页提供可见分组列表并沿用习惯分类字段', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains("import '../core/habit_grouping.dart';"));
    expect(source, contains('groupHabitsByCategory(provider.habits)'));
    expect(source, contains('_HabitGroupSection'));
    expect(source, contains('ExpansionTile('));
    expect(source, contains('习惯分组'));
    expect(source, contains('Icons.folder_outlined'));
    expect(
      source,
      contains('category: habitCategoryOrNull(categoryCtrl.text)'),
    );
  });

  test('习惯模板选择会带入分类，手动创建也暴露分组字段', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains('final categoryCtrl = TextEditingController()'));
    expect(source, contains('selectedKind = HabitKind.positive'));
    expect(source, contains('unitCtrl.text = t.localizedUnit'));
    expect(source, contains('categoryCtrl.text = t.localizedCategory'));
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

  test('习惯打卡提供完成反馈和轻量动效', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, contains('AnimatedScale('));
    expect(source, contains('AnimatedSwitcher('));
    expect(source, contains('_HabitFeedbackBadge'));
    expect(source, contains('HapticFeedback.mediumImpact()'));
    expect(source, contains('SystemSound.play(SystemSoundType.click)'));
    expect(source, contains('HapticFeedback.selectionClick()'));
    expect(source, contains('dimension: 48'));
    expect(source, contains('width: 48'));
    expect(source, contains('height: 48'));
    expect(source, contains('size: 22'));
    expect(source, contains('messenger.hideCurrentSnackBar()'));
    expect(source, contains('今日已达标'));
    expect(source, contains("label: '已达标'"));
    expect(source, contains("label: '已记录'"));
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

    expect(source, contains("import '../core/habit_insights.dart';"));
    expect(source, contains('HabitInsightEngine.buildInsights('));
    expect(source, contains('_HabitInsightCard'));
    expect(source, contains('智能习惯洞察'));
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

    expect(screen, contains('flexRuleEnabled'));
    expect(screen, contains('SegmentedButton<HabitFlexPeriod>'));
    expect(screen, contains("label: Text('每周')"));
    expect(screen, contains("label: Text('每月')"));
    expect(screen, contains("labelText: '周期目标'"));
    expect(screen, contains('flexTarget: shouldUseFlex ? flexTarget : null'));
    expect(screen, contains('flexPeriod: shouldUseFlex'));
    expect(screen, contains('habit.flexPeriodGoalLabel'));
    expect(screen, contains('habit.streakUnitLabel'));

    expect(detail, contains("I18n.tr('habit.flex.rule')"));
    expect(detail, contains('flexRuleEnabled = habit.hasFlexRule'));
    expect(detail, contains('clearFlexRule: !shouldUseFlex'));
    expect(detail, contains('habit.flexProgressForDate(DateTime.now())'));
    expect(detail, contains('localizedHabitCountForDate(habit, d)'));
    expect(detail, contains('_localizedHabitStreakUnit(habit)'));

    expect(provider, contains('_recalcFlexStreak'));
    expect(provider, contains('h.periodBoundsForDate(DateTime.now())'));
    expect(provider, contains('h.previousPeriodBounds(bounds)'));
  });

  test('习惯创建和详情编辑暴露起止日期并禁用周期外补卡', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final detail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final dateFields = File(
      'lib/widgets/habit_date_range_fields.dart',
    ).readAsStringSync();

    expect(
      screen,
      contains("import '../widgets/habit_date_range_fields.dart';"),
    );
    expect(screen, contains('DateTime? startDate'));
    expect(screen, contains('DateTime? endDate'));
    expect(screen, contains('HabitDateRangeFields('));
    expect(screen, contains('habitDateRangeIsValid(startDate, endDate)'));
    expect(screen, contains('startDate: startDate'));
    expect(screen, contains('endDate: endDate'));

    expect(
      detail,
      contains("import '../widgets/habit_date_range_fields.dart';"),
    );
    expect(detail, contains('DateTime? startDate = habit.startDate'));
    expect(detail, contains('DateTime? endDate = habit.endDate'));
    expect(detail, contains('clearStartDate: startDate == null'));
    expect(detail, contains('clearEndDate: endDate == null'));
    expect(
      detail,
      contains('habitDateRangeLabel(habit.startDate, habit.endDate)'),
    );
    expect(detail, contains('final activeForDay = habit.activeForDate(d)'));
    expect(detail, contains("I18n.tr('habit.records.inactive')"));
    expect(detail, contains('onPressed: activeForDay'));

    expect(dateFields, contains("I18n.tr('habit.date_range.start')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.end')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.start_empty')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.end_empty')"));
    expect(dateFields, contains('bool habitDateRangeIsValid'));
  });
}
