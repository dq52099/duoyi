import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页展示周期效率对比', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/report_engine.dart';"));
    expect(source, contains('ReportEngine.buildReport'));
    expect(source, contains('ReportEngine.compare'));
    expect(source, contains('_ProductivityComparisonCard'));
    expect(source, contains('.productivityComparison'));
    expect(source, contains('.rangeCompareLabelWeek'));
    expect(source, contains('.completionRate'));
    expect(source, contains('.efficiencyScore'));
    expect(source, contains('.vsPreviousPeriod'));
  });

  test('统计页展示多周期效率趋势折线', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_buildProductivityTrend'));
    expect(source, contains('_ProductivityTrendCard'));
    expect(source, contains('_ProductivityTrendPoint'));
    expect(source, contains('LineChart'));
    expect(source, contains('FlSpot'));
    expect(source, contains('.productivityTrend'));
    expect(source, contains('.trendSubtitleWeek'));
    expect(source, contains('.trendSubtitleMonth'));
    expect(source, contains('.trendSubtitleYear'));
  });

  test('统计页展示趋势洞察和历史摘要', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('.trendInsights'));
    expect(source, contains('_insightText'));
    expect(source, contains('_bestPoint'));
    expect(source, contains('_averageScore'));
    expect(source, contains('_rankText'));
    expect(source, contains('_TrendHistoryMetric'));
    expect(source, contains('.historicalBest'));
    expect(source, contains('.averageScore'));
    expect(source, contains('.currentRank'));
  });

  test('统计页展示逐周期趋势详情 drill-down', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('.viewTrendDetail'));
    expect(source, contains('_ProductivityTrendDetailScreen'));
    expect(source, contains('MaterialPageRoute('));
    expect(source, contains('.trendDetailTitle'));
    expect(
      source,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(source, contains('.trendOverview'));
    expect(source, contains('.periodByPeriodBreakdown'));
    expect(source, contains('.cycleBreakdown'));
    expect(source, contains('_TrendDetailTile'));
    expect(source, contains('_TrendDetailMetric'));
    expect(source, contains('dateRangeLabel'));
    expect(source, contains('point.completedTodos'));
    expect(source, contains('point.focusMinutes'));
    expect(source, contains('point.habitCheckIns'));
    expect(source, contains('point.timeEntryMinutes'));
    expect(source, contains('.todos'));
    expect(source, contains('.focus'));
    expect(source, contains('.habits'));
    expect(source, contains('.footprint'));
    expect(source, contains('.best'));
    expect(source, contains('.current'));
  });

  test('统计页展示全局活动热力图', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final card = File(
      'lib/widgets/activity_heatmap_card.dart',
    ).readAsStringSync();

    expect(source, contains("import '../widgets/activity_heatmap_card.dart';"));
    expect(
      source,
      contains('ActivityHeatmapCard(heatmapData: activityHeatmap)'),
    );
    expect(source, isNot(contains('_ActivityHeatmapCard')));
    expect(source, isNot(contains('_HeatmapSummary')));
    expect(card, contains('copy.activityTitle'));
    expect(card, contains('copy.activitySubtitle'));
    expect(card, contains('copy.activeDays(summary.activeDays)'));
    expect(card, contains('copy.maximum(summary.maximumLevel)'));
    expect(card, contains('HeatmapMetric.activity'));
  });

  test('统计页展示多维交叉分析', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final core = File('lib/core/report_cross_analysis.dart').readAsStringSync();

    expect(source, contains("import '../core/report_cross_analysis.dart';"));
    expect(source, contains('ReportCrossAnalysis.build'));
    expect(source, contains('_buildFocusTodoCorrelationCard'));
    expect(source, contains('_buildFocusTodoScatter'));
    expect(source, contains('_buildHabitTodoCorrelationCard'));
    expect(source, contains('_buildHabitTodoScatter'));
    expect(source, contains('_buildDiaryFocusCorrelationCard'));
    expect(source, contains('_buildDiaryFocusScatter'));
    expect(source, contains('_buildTimeCategoryShareTrendCard'));
    expect(source, contains('_buildTimeCategoryShareChart'));
    expect(source, contains('_buildTimeOutputEfficiencyCard'));
    expect(source, contains('_buildTimeOutputEfficiencyChart'));
    expect(source, contains('ReportCrossDiaryEntry'));
    expect(source, contains('crossAnalysis.diaryFocus'));
    expect(source, contains('crossAnalysis.timeOutputEfficiency'));
    expect(source, contains('ScatterChart'));
    expect(source, contains('ScatterSpot'));
    expect(source, contains('BarChartRodStackItem'));
    expect(source, contains('.focusTodoCorrelation'));
    expect(source, contains('.focusTodoAxisLabel'));
    expect(source, contains('.habitTodoCorrelation'));
    expect(source, contains('.habitTodoAxisLabel'));
    expect(source, contains('.diaryFocusCorrelation'));
    expect(source, contains('.diaryFocusAxisLabel'));
    expect(source, contains('.timeCategoryShareTrend'));
    expect(source, contains('.timeCategoryShareTrendSubtitle'));
    expect(source, contains('.timeOutputEfficiencyTitle'));
    expect(source, contains('.completedPerHour'));

    expect(core, contains('class ReportCrossAnalysis'));
    expect(core, contains('class FocusTodoCorrelation'));
    expect(core, contains('class HabitTodoCorrelation'));
    expect(core, contains('class DiaryFocusCorrelation'));
    expect(core, contains('class TimeCategoryShareTrend'));
    expect(core, contains('class TimeOutputEfficiencyTrend'));
    expect(core, contains('class TimeOutputPoint'));
    expect(core, contains('timeOutputEfficiency'));
    expect(core, contains('final double? pearson'));
    expect(core, contains('otherCategoryKey'));
  });

  test('统计页按习惯达标周期聚合弹性打卡', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('habit.completionDatesInRange(start, end)'));
    expect(source, isNot(contains('habit.isCompletedForDate(d)')));
    expect(
      source,
      contains('final habitDoneInRange = habitCompletionDates.length'),
    );
  });

  test('统计页展示项目效率拆解', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/project_efficiency.dart';"));
    expect(source, contains('context.watch<GoalProvider>()'));
    expect(source, contains('_buildProjectEfficiencyBreakdown'));
    expect(source, contains('_buildProjectEfficiencyCard'));
    expect(source, contains('_buildProjectEfficiencyChart'));
    expect(source, contains('_ProjectEfficiencyRow'));
    expect(source, contains('.projectEfficiencyTitle'));
    expect(source, contains('.projectEfficiencySubtitle'));
    expect(source, contains('.itemsPerHour'));
  });
}
