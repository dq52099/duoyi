/// Typed UI localization copy for the Statistics screen and report exports.
library;

import 'i18n.dart';
import 'i18n_date_format.dart';
import 'period_report.dart';
import '../models/time_entry.dart';

class StatisticsUiCopy {
  final AppLocale locale;
  final String? datePattern;
  const StatisticsUiCopy(this.locale, {this.datePattern});

  factory StatisticsUiCopy.current({String? datePattern}) =>
      StatisticsUiCopy(I18n.current, datePattern: datePattern);

  bool get isEn => locale == AppLocale.en;
  bool get isZh => locale == AppLocale.zh;

  String pick(String zh, String en) => isEn ? en : zh;

  // ---------------------------------------------------------------------------
  // App bar & Ranges
  // ---------------------------------------------------------------------------
  String get pageTitle => pick('时光足迹', 'Time Footprint');
  String get copyReportTooltip => pick('复制报告', 'Copy report');
  String get reportShareImageTooltip => pick('报告分享图', 'Report share image');

  String get rangeWeek => pick('本周', 'This week');
  String get rangeMonth => pick('本月', 'This month');
  String get rangeYear => pick('本年', 'This year');

  // ---------------------------------------------------------------------------
  // KPI Cards
  // ---------------------------------------------------------------------------
  String get kpiCompletedTodos => pick('待办完成', 'Tasks completed');
  String get kpiDeepFocus => pick('深度专注', 'Deep focus');
  String get kpiHabitCheckIns => pick('习惯打卡', 'Habit check-ins');
  String get kpiDiary => pick('日记', 'Diary');
  String get kpiTimeFootprint => pick('时间足迹', 'Time footprint');

  String minutesCount(int minutes) => isEn ? '$minutes min' : '$minutes 分';
  String timesCount(int count) =>
      isEn ? '$count ${count == 1 ? 'time' : 'times'}' : '$count 次';
  String diaryEntriesCount(int count) =>
      isEn ? '$count ${count == 1 ? 'entry' : 'entries'}' : '$count 篇';
  String itemsCount(int count) =>
      isEn ? '$count ${count == 1 ? 'item' : 'items'}' : '$count 项';
  String pointsCount(int score) => isEn ? '$score pts' : '$score 分';

  // ---------------------------------------------------------------------------
  // Period Report Digest Card
  // ---------------------------------------------------------------------------
  String get copyReport => pick('复制报告', 'Copy report');
  String get aiReview => pick('AI 解读', 'AI review');
  String get shareImage => pick('分享图', 'Share image');
  String get aiHistory => pick('AI 历史', 'AI history');
  String get aiDisabledMessage => pick(
    '管理员启用 AI 后可生成云端个性化解读',
    'Enable AI in the admin console to generate personalized cloud reviews',
  );
  String get aiReviewHeading => pick('云端个性化解读', 'Personalized AI Review');
  String digestTitle(PeriodReportKind kind) => switch (kind) {
    PeriodReportKind.daily => pick('每日复盘', 'Daily Review'),
    PeriodReportKind.weekly => pick('本周周报', 'Weekly Report'),
    PeriodReportKind.monthly => pick('本月月报', 'Monthly Report'),
    PeriodReportKind.yearly => pick('年度报告', 'Annual Report'),
  };
  String digestSubtitle(PeriodReportKind kind, int days) => switch (kind) {
    PeriodReportKind.daily => pick('今天的效率复盘', "Today's productivity review"),
    PeriodReportKind.weekly => pick(
      '最近 $days 天的效率复盘',
      'Productivity review for last $days days',
    ),
    PeriodReportKind.monthly => pick(
      '本月 $days 天的时间投入',
      'Time investment for $days days this month',
    ),
    PeriodReportKind.yearly => pick(
      '全年成长轨迹与关键成果',
      'Year-round growth and key results',
    ),
  };

  // ---------------------------------------------------------------------------
  // Productivity Comparison Card
  // ---------------------------------------------------------------------------
  String get productivityComparison => pick('效率对比', 'Efficiency Comparison');
  String get rangeCompareLabelWeek =>
      pick('与上周同段对比', 'Compared with same period last week');
  String get rangeCompareLabelCycle =>
      pick('与上一同长度周期对比', 'Compared with previous cycle of same length');
  String get efficiencyScore => pick('效率分', 'Efficiency');
  String get completionRate => pick('完成率', 'Completion rate');
  String get focus => pick('专注', 'Focus');
  String get habits => pick('习惯', 'Habits');
  String get footprint => pick('足迹', 'Footprint');
  String get todos => pick('待办', 'Todos');
  String get vsPreviousPeriod => pick('较上期', 'vs previous period');
  String get flat => pick('持平', 'Flat');
  String get percentagePointsSuffix => pick(' 个点', ' pts');
  String get pointsSuffix => pick(' 分', ' pts');
  String get timesSuffix => pick(' 次', ' times');
  String get minutesSuffix => pick(' 分', ' min');

  // ---------------------------------------------------------------------------
  // Productivity Trend Card & Drill-down Detail Screen
  // ---------------------------------------------------------------------------
  String get productivityTrend => pick('效率趋势', 'Efficiency Trend');
  String get trendSubtitleWeek =>
      pick('近 6 周同段效率分', 'Efficiency score over last 6 weeks');
  String get trendSubtitleMonth =>
      pick('近 6 个月同段效率分', 'Efficiency score over last 6 months');
  String get trendSubtitleYear =>
      pick('近 5 年同段效率分', 'Efficiency score over last 5 years');
  String get viewTrendDetail => pick('查看趋势详情', 'View trend details');
  String get noTrendData => pick('暂无趋势数据', 'No trend data yet');
  String get trendInsights => pick('趋势洞察', 'Trend Insights');
  String get historicalBest => pick('历史最佳', 'All-time best');
  String get averageScore => pick('平均分', 'Average');
  String get currentRank => pick('当前排名', 'Current rank');
  String get cycleBreakdown => pick('周期明细', 'Cycle breakdown');

  String get trendDetailTitle => pick('趋势详情', 'Trend Details');
  String get trendOverview => pick('趋势概览', 'Trend Overview');
  String get periodByPeriodBreakdown =>
      pick('逐周期明细', 'Period-by-period breakdown');
  String get best => pick('最佳', 'Best');
  String get current => pick('当前', 'Current');
  String get baseline => pick('基准', 'Baseline');
  String get noData => pick('暂无', 'None');

  String rank(int rank, int total) =>
      isEn ? '#$rank of $total' : '第 $rank/$total';

  String get trendInsightInsufficient => pick(
    '趋势样本不足，继续记录后会生成更稳定的解读。',
    'Insufficient trend samples; more records will provide more stable insights.',
  );

  String trendInsightText({
    required int delta,
    required String? bestLabel,
    required int? bestScore,
    required int average,
    required int latestScore,
  }) {
    if (isEn) {
      final direction = delta > 0
          ? 'improved by $delta pts'
          : delta < 0
          ? 'dropped by ${delta.abs()} pts'
          : 'remained stable';
      final bestText = bestLabel != null && bestScore != null
          ? 'all-time best was $bestScore pts in $bestLabel, '
          : '';
      final averageText = latestScore >= average
          ? 'currently above recent average of $average pts.'
          : 'currently below recent average of $average pts.';
      return 'Compared to previous cycle, score $direction; ${bestText}and $averageText';
    } else {
      final direction = delta > 0
          ? '提升了 $delta 分'
          : delta < 0
          ? '回落了 ${delta.abs()} 分'
          : '保持稳定';
      final bestText = bestLabel != null && bestScore != null
          ? '历史最佳是 $bestLabel 的 $bestScore 分，'
          : '';
      final averageText = latestScore >= average
          ? '当前高于最近平均 $average 分。'
          : '当前低于最近平均 $average 分。';
      return '较上一周期$direction，$bestText$averageText';
    }
  }

  // ---------------------------------------------------------------------------
  // Cross Analysis Cards
  // ---------------------------------------------------------------------------
  String get focusTodoCorrelation =>
      pick('专注 × 待办相关性', 'Focus × Todo Correlation');
  String get focusTodoAxisLabel => pick(
    '横轴为专注分钟数，纵轴为待办完成数',
    'Horizontal axis: focus minutes; vertical axis: completed tasks',
  );

  String get habitTodoCorrelation =>
      pick('习惯 × 待办相关性', 'Habit × Todo Correlation');
  String get habitTodoAxisLabel => pick(
    '横轴为习惯达标次数，纵轴为待办完成数',
    'Horizontal axis: habit completions; vertical axis: completed tasks',
  );

  String get diaryFocusCorrelation =>
      pick('日记 × 专注相关性', 'Diary × Focus Correlation');
  String get diaryFocusAxisLabel => pick(
    '横轴为日记篇数，纵轴为专注分钟数',
    'Horizontal axis: diary entries; vertical axis: focus minutes',
  );

  String get insufficientSamples => pick('样本不足', 'Need more data');
  String get noCrossAnalysisData =>
      pick('暂无交叉分析数据', 'No cross-analysis data yet');
  String get noHabitCrossData => pick('暂无习惯交叉数据', 'No habit cross data yet');
  String get noDiaryFocusCrossData =>
      pick('暂无日记专注交叉数据', 'No diary focus cross data yet');

  String focusTodoInsight(double? r) {
    if (r == null) {
      return pick(
        '需要至少两个有变化的周期点，才能判断专注投入与待办完成的关系。',
        'At least two varying periods are required to determine the relationship between focus and task completions.',
      );
    }
    if (r >= 0.45) {
      return pick(
        '专注分钟数越高，待办完成数通常同步提升。',
        'Higher focus minutes typically correlate with more completed tasks.',
      );
    }
    if (r <= -0.45) {
      return pick(
        '专注投入和待办完成出现反向变化，适合检查任务粒度或专注目标。',
        'Focus time and task completions move in opposite directions; consider checking task granularity or focus goals.',
      );
    }
    return pick(
      '两者关系较弱，当前周期的完成数可能更多受任务数量、难度或日程影响。',
      'Correlation is weak; completed tasks may depend more on difficulty, count, or schedule.',
    );
  }

  String habitTodoInsight(double? r) {
    if (r == null) {
      return pick(
        '需要至少两个有变化的周期点，才能判断习惯达标与待办完成的关系。',
        'At least two varying periods are required to determine the relationship between habit check-ins and task completions.',
      );
    }
    if (r >= 0.45) {
      return pick(
        '习惯达标越稳定，待办完成数通常也更高。',
        'More consistent habit completions usually correlate with higher task completion.',
      );
    }
    if (r <= -0.45) {
      return pick(
        '习惯达标和待办完成出现反向变化，适合检查当天计划是否过载。',
        'Habit check-ins and task completions move inversely; check whether daily plans are overloaded.',
      );
    }
    return pick(
      '两者关系较弱，当前周期的待办完成可能更多受任务难度或外部日程影响。',
      'Correlation is weak; task completions may be influenced more by difficulty or external schedule.',
    );
  }

  String diaryFocusInsight(double? r) {
    if (r == null) {
      return pick(
        '需要至少两个有变化的周期点，才能判断记录日记与专注投入的关系。',
        'At least two varying periods are required to determine the relationship between journaling and focus time.',
      );
    }
    if (r >= 0.45) {
      return pick(
        '日记记录越稳定，专注分钟数通常也更高。',
        'Consistent journaling typically correlates with higher focus minutes.',
      );
    }
    if (r <= -0.45) {
      return pick(
        '日记记录和专注投入出现反向变化，适合检查复盘是否集中在低专注日。',
        'Journaling and focus time move inversely; check if reflection happens mostly on low-focus days.',
      );
    }
    return pick(
      '两者关系较弱，当前周期的专注投入可能更多受任务安排或外部日程影响。',
      'Correlation is weak; focus time may depend more on specific task plans or schedule.',
    );
  }

  // ---------------------------------------------------------------------------
  // Time Category Share Trend & Output Efficiency
  // ---------------------------------------------------------------------------
  String get timeCategoryShareTrend =>
      pick('时间分类占比趋势', 'Time Category Distribution Trend');
  String get timeCategoryShareTrendSubtitle => pick(
    '按当前周期展示各类时间投入结构变化',
    'Shows category investment shifts across current cycle',
  );
  String get noTimeCategoryTrend =>
      pick('暂无时间分类趋势', 'No category trend data yet');
  String get otherCategory => pick('其他', 'Other');

  String get timeOutputEfficiencyTitle =>
      pick('时间投入 × 待办产出效率', 'Time Investment × Task Output Efficiency');
  String get completedPerHour => pick('每小时完成', 'Completed per hour');
  String get timeOutputEfficiencySubtitle => pick(
    '按当前周期展示每小时完成项',
    'Shows tasks completed per hour across current cycle',
  );
  String get noTimeOutputData =>
      pick('暂无时间投入产出数据', 'No output efficiency data yet');

  // ---------------------------------------------------------------------------
  // Project Efficiency Breakdown
  // ---------------------------------------------------------------------------
  String get projectEfficiencyTitle =>
      pick('项目效率拆解', 'Project Efficiency Breakdown');
  String get highest => pick('最高', 'Peak');
  String get projectEfficiencySubtitle => pick(
    '按清单/目标汇总完成项、目标里程碑和时间投入',
    'Summarizes completed tasks, milestones, and time by list/goal',
  );
  String get noProjectEfficiencyData =>
      pick('暂无项目效率数据', 'No project efficiency data yet');
  String itemsPerHour(double rate) => isEn
      ? '${rate.toStringAsFixed(1)} items/h'
      : '${rate.toStringAsFixed(1)} 项/时';
  String get inbox => pick('收件箱', 'Inbox');
  String get untitledGoal => pick('未命名目标', 'Untitled goal');

  String projectEfficiencyItemSummary({
    required int outputCount,
    required int completedTodos,
    required int completedGoalSteps,
    required int timeMinutes,
  }) => isEn
      ? 'Output $outputCount items · Tasks $completedTodos · Goals $completedGoalSteps · $timeMinutes min'
      : '输出 $outputCount 项 · 待办 $completedTodos · 目标 $completedGoalSteps · $timeMinutes 分';

  String projectEfficiencyTooltipOutput({
    required int outputCount,
    required int timeMinutes,
  }) => isEn
      ? '$outputCount items output / $timeMinutes min'
      : '$outputCount 项输出 / $timeMinutes 分';

  // ---------------------------------------------------------------------------
  // Weekly Overview & Timeline & General
  // ---------------------------------------------------------------------------
  String get weeklyTimeOverview => pick('本周时间概览', 'Weekly Time Overview');
  String get weeklyTotalInvested => pick('本周累计投入', 'Total invested this week');
  String get noWeeklyData => pick('暂无本周数据', 'No weekly data yet');
  String get noTimeFootprint => pick('暂无时间足迹', 'No time footprint data yet');
  String get noTimeEntries => pick('暂无时间记录', 'No time entries yet');
  String get timeDistribution => pick('时间投入分布', 'Time Distribution');
  String get timeline => pick('时间线', 'Timeline');
  String get monthlyFocusMinutes => pick('每月专注分钟数', 'Monthly Focus Minutes');
  String get dailyFocusMinutes => pick('每日专注分钟数', 'Daily Focus Minutes');
  String get noFocusData => pick('暂无专注数据', 'No focus data yet');
  String get viewAll => pick('查看全部', 'View all');

  List<String> get weekdayLabels => isEn
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  String sourceLabel(String source) => switch (source) {
    '番茄钟' => pick('番茄钟', 'Pomodoro'),
    '待办' => pick('待办', 'Todos'),
    '习惯' => pick('习惯', 'Habits'),
    '目标' => pick('目标', 'Goals'),
    '手动' => pick('手动', 'Manual'),
    _ => source,
  };

  String formatDuration(int seconds) {
    if (seconds >= 3600) {
      final h = seconds / 3600;
      final hStr = h.toStringAsFixed(seconds % 3600 == 0 ? 0 : 1);
      return isEn ? '$hStr ${h == 1 ? 'hour' : 'hours'}' : '$hStr 小时';
    }
    final m = seconds / 60;
    final mStr = m.toStringAsFixed(seconds % 60 == 0 ? 0 : 1);
    return isEn ? '$mStr min' : '$mStr 分钟';
  }

  // ---------------------------------------------------------------------------
  // Focus Tag Ranking & Trend
  // ---------------------------------------------------------------------------
  String get focusTagRanking => pick('专注标签排行', 'Focus Tag Ranking');
  String get noFocusTagData => pick('暂无专注标签数据', 'No focus tag data yet');
  String get focusTagTrend => pick('专注标签趋势', 'Focus Tag Trend');
  String get byMonth => pick('按月', 'Monthly');
  String get byDay => pick('按日', 'Daily');
  String get noFocusTagTrend => pick('暂无专注标签趋势', 'No focus tag trend yet');

  String focusTagSessionSummary(int count, int avgMinutes) => isEn
      ? '$count ${count == 1 ? 'session' : 'sessions'} · avg $avgMinutes min'
      : '$count 次 · 平均 $avgMinutes 分';

  // ---------------------------------------------------------------------------
  // Eisenhower Quadrant Distribution
  // ---------------------------------------------------------------------------
  String get quadrantTitle =>
      pick('四象限执行分布', 'Quadrant Execution Distribution');
  String get quadrantSubtitle => pick('当前待办池', 'Current Task Pool');
  String get quadrantDescription => pick(
    '按重要/紧急象限拆解未完成压力、今日到期和已完成沉淀。',
    'Breaks down active pressure, due-today tasks, and completions by importance/urgency.',
  );
  String get quadrantTotalTasks => pick('任务总数', 'Total Tasks');
  String get quadrantActive => pick('未完成', 'Active');
  String get quadrantOverdue => pick('逾期', 'Overdue');
  String get quadrantDueToday => pick('今日到期', 'Due Today');
  String get quadrantEmpty => pick(
    '当前没有可统计的待办。新增任务并设置象限后，这里会显示优先级结构。',
    'No tasks to display. Add tasks and assign quadrants to see priority structure.',
  );

  String get quadrantUrgentImportantLabel => pick('重要紧急', 'Urgent & Important');
  String get quadrantUrgentImportantAction => pick('立即处理', 'Do First');
  String get quadrantUrgentImportantGuidance => pick(
    '优先清空逾期和今天到期事项。',
    'Prioritize clearing overdue and due-today tasks.',
  );

  String get quadrantNotUrgentImportantLabel =>
      pick('重要不紧急', 'Important & Not Urgent');
  String get quadrantNotUrgentImportantAction => pick('安排计划', 'Schedule');
  String get quadrantNotUrgentImportantGuidance => pick(
    '保持推进节奏，避免滚入紧急区。',
    'Maintain steady progress to avoid rolling into urgent zone.',
  );

  String get quadrantUrgentNotImportantLabel =>
      pick('紧急不重要', 'Urgent & Not Important');
  String get quadrantUrgentNotImportantAction =>
      pick('委派或限时', 'Delegate or Timebox');
  String get quadrantUrgentNotImportantGuidance =>
      pick('用批量处理减少被打断时间。', 'Batch tasks to reduce interruptions.');

  String get quadrantNotUrgentNotImportantLabel =>
      pick('不重要不紧急', 'Not Urgent & Not Important');
  String get quadrantNotUrgentNotImportantAction => pick('清理剔除', 'Eliminate');
  String get quadrantNotUrgentNotImportantGuidance =>
      pick('定期归档，避免待办池膨胀。', 'Archive periodically to prevent pool bloat.');

  String quadrantRowSummary({
    required String guidance,
    required int active,
    required int overdue,
    required int dueToday,
    required int completed,
  }) => isEn
      ? '$guidance $active active, $overdue overdue, $dueToday due today, $completed completed.'
      : '$guidance 未完成 $active 项，逾期 $overdue 项，今日到期 $dueToday 项，完成 $completed 项。';

  // ---------------------------------------------------------------------------
  // Dialogs, Shares, and Reports
  // ---------------------------------------------------------------------------
  String get reportCopiedNotice => pick(
    '报告已复制，可粘贴到笔记、聊天或文档',
    'Report copied; ready to paste into notes, chat, or documents',
  );
  String digestCopiedNotice(String title) =>
      isEn ? '$title copied' : '$title已复制';

  String get shareDialogTitle => pick('报告分享图', 'Report Share Image');
  String get pdfTemplate => pick('PDF 模板', 'PDF Template');
  String get pdfTemplateVisual => pick('视觉版', 'Visual');
  String get pdfTemplateArchive => pick('归档版', 'Archive');
  String get pdfTemplateBriefing => pick('简报版', 'Briefing');
  String get pdfTemplateDashboard => pick('仪表版', 'Dashboard');
  String get pdfTemplateTimeline => pick('时间线版', 'Timeline');

  String get close => pick('关闭', 'Close');
  String get copyMarkdownAction => pick('复制文案', 'Copy Text');
  String get savePdfAction => pick('保存 PDF', 'Save PDF');
  String get savePngAction => pick('保存 PNG', 'Save PNG');
  String get markdownCopiedNotice => pick('报告文案已复制', 'Report text copied');

  String get shareReportTitle => pick('多仪时光报告', 'Duoyi Time Report');
  String get shareSubject => pick('多仪时光报告', 'Duoyi Time Report');
  String get sharePdfSubject => pick('多仪时光报告 PDF', 'Duoyi Time Report PDF');

  String shareImageSaved(String path) => isEn
      ? 'Share image saved and opened in system share sheet, path copied: $path'
      : '分享图已保存并打开系统分享面板，路径已复制：$path';

  String sharePdfSaved(String template, String path) => isEn
      ? '$template PDF report saved and opened in system share sheet, path copied: $path'
      : '$template PDF 报告已保存并打开系统分享面板，路径已复制：$path';
  String get exportFailedRetry =>
      pick('导出失败，请重试', 'Export failed, please try again');

  String get timeInvestment => pick('时间投入', 'Time Investment');
  String get generatedByDuoyi => pick('由多仪生成', 'Generated by Duoyi');

  String get pdfBriefingTimeFocus =>
      pick('时间投入重点', 'Time Investment Highlights');
  String get pdfBriefingRecentRecords => pick('最近记录', 'Recent Records');
  String get pdfBriefingCompletedItems => pick('完成事项', 'Completed Items');
  String get pdfBriefingNotice => pick(
    '这份简报保留可检索文字层，适合快速复盘、转发和归档。',
    'This briefing retains a searchable text layer, suitable for quick review, sharing, and archiving.',
  );
  String get pdfDashboardCoreMetrics => pick('核心指标', 'Core Metrics');
  String get pdfDashboardRanking => pick('时间投入排行', 'Time Investment Ranking');
  String get pdfDashboardRecentProgress => pick('近期推进', 'Recent Progress');
  String get pdfDashboardNotice => pick(
    '仪表版适合复盘关键指标和投入结构，保留可检索文字层。',
    'The dashboard is ideal for reviewing key metrics and time structure with a searchable text layer.',
  );
  String get pdfTimelineRecentRecords => pick('最近时间记录', 'Recent Time Records');
  String get pdfTimelineNotice => pick(
    '时间线版适合按行动顺序复盘过程，兼顾记录流、完成事项和投入结构。',
    'The timeline is ideal for chronological review, balancing logs, completed tasks, and time distribution.',
  );
  String get pdfSearchableLayerTitle => pick('可检索文字层', 'Searchable Text Layer');
  String pdfSearchableTemplateLabel(String name) =>
      isEn ? 'Template: $name' : '模板：$name';

  String get markdownReportTitle => pick('# 多仪时光报告', '# Duoyi Time Report');
  String get markdownOverview => pick('## 概览', '## Overview');
  String get markdownTimeDistribution =>
      pick('## 时间投入分布', '## Time Distribution');
  String get markdownRecentRecords =>
      pick('## 最近时间记录', '## Recent Time Entries');
  String get markdownCompletedTodos => pick('## 已完成待办', '## Completed Todos');
  String get thisYear => pick('今年', 'This year');
  String monthNumberLabel(int month) => isEn ? _enMonth(month) : '$month月';

  static const _enMonths = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String _enMonth(int month) => _enMonths[(month - 1).clamp(0, 11)];

  String minutesAndItems(int minutes, int items) =>
      isEn ? '$minutes min / $items items' : '$minutes 分 / $items 项';
  String timesAndItems(int times, int items) =>
      isEn ? '$times times / $items items' : '$times 次 / $items 项';
  String diaryAndMinutes(int diary, int minutes) =>
      isEn ? '$diary entries / $minutes min' : '$diary 篇 / $minutes 分';
  String itemsCountDouble(double count) => isEn
      ? '${count.toStringAsFixed(1)} items'
      : '${count.toStringAsFixed(1)} 项';

  String get markdownRangePrefix => pick('范围：', 'Range:');
  String get markdownOverviewTitle => pick('概览', 'Overview');
  String get markdownTimeDistributionTitle =>
      pick('时间投入分布', 'Time Distribution');
  String get markdownRecentRecordsTitle =>
      pick('最近时间记录', 'Recent Time Entries');
  String get markdownCompletedTodosTitle => pick('已完成待办', 'Completed Todos');

  String markdownRange(String start, String end) =>
      isEn ? 'Range: $start - $end' : '范围：$start - $end';

  String get markdownColon => isEn ? ': ' : '：';

  String categoryLabel(TimeEntryCategory category) => switch (category) {
    TimeEntryCategory.focus => pick('专注', 'Focus'),
    TimeEntryCategory.todo => pick('待办', 'Task'),
    TimeEntryCategory.habit => pick('习惯', 'Habit'),
    TimeEntryCategory.goal => pick('目标', 'Goal'),
    TimeEntryCategory.study => pick('学习', 'Study'),
    TimeEntryCategory.work => pick('工作', 'Work'),
    TimeEntryCategory.life => pick('生活', 'Life'),
    TimeEntryCategory.other => pick('其他', 'Other'),
  };

  String formatCategory(Object? category) {
    if (category is TimeEntryCategory) return categoryLabel(category);
    return category?.toString() ?? '';
  }

  String get noTimeInvestmentData =>
      pick('暂无时间投入数据', 'No time investment data yet');
  String get noCompletedTodos => pick('暂无完成待办', 'No completed tasks yet');
  String get unspecifiedRange => pick('未指定', 'Unspecified');

  String formatDate(DateTime value) =>
      I18nDateFormat.date(value, pattern: datePattern, locale: locale);

  String formatShortDateTime(DateTime value) {
    final mDay = isEn
        ? '${_enMonth(value.month)} ${value.day}'
        : '${value.month}月${value.day}日';
    final timeStr =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$mDay $timeStr';
  }
}
