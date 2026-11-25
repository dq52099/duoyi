import '../widgets/app_date_format.dart';
import 'dart:async';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/web_file_download.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../core/desktop_tokens.dart';
import '../core/focus_tag_stats.dart';
import '../core/heatmap_calendar.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/project_efficiency.dart';
import '../core/report_cross_analysis.dart';
import '../core/report_engine.dart';
import '../core/period_report_presentation.dart';
import '../core/statistics_ui_copy.dart';
import '../services/account_local_data_cleaner.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../providers/app_lock_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../services/ai_service.dart';
import '../services/app_update_service.dart';
import '../widgets/activity_heatmap_card.dart';
import '../widgets/result_states.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart';
import 'ai_history_screen.dart';
import 'time_audit_screen.dart';

enum _Range { week, month, year }

enum _ReportPdfTemplate { visual, archive, briefing, dashboard, timeline }

class StatisticsScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Range _range = _Range.week;
  bool _aiReportBusy = false;
  String? _aiReportReview;
  String? _aiReportError;
  int _aiReportRequestSeq = 0;
  int _lastAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;

  @override
  void initState() {
    super.initState();
    _lastAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountGenerationChanged,
    );
  }

  void _onAccountGenerationChanged() {
    final next = AccountLocalDataCleaner.accountDataGeneration;
    if (_lastAccountGeneration != next) {
      _lastAccountGeneration = next;
      _aiReportRequestSeq++;
      if (mounted) {
        setState(() {
          _aiReportBusy = false;
          _aiReportReview = null;
          _aiReportError = null;
        });
      }
    }
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountGenerationChanged,
    );
    super.dispose();
  }

  (DateTime, DateTime) get _rangeBounds {
    final now = DateTime.now();
    switch (_range) {
      case _Range.week:
        final monday = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case _Range.month:
        return (DateTime(now.year, now.month, 1), now);
      case _Range.year:
        return (DateTime(now.year, 1, 1), now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoProv = context.watch<TodoProvider>();
    final goalProv = context.watch<GoalProvider>();
    final habitProv = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomoProv = context.read<PomodoroProvider>();
    final diaryProv = context.watch<DiaryProvider>();
    final timeAuditProv = context.watch<TimeAuditProvider>();
    final ai = context.watch<AiService>();
    final cs = Theme.of(context).colorScheme;
    final copy = StatisticsUiCopy.current(
      datePattern: AppDateFormat.patternOf(context),
    );

    final (start, end) = _rangeBounds;
    final (previousStart, previousEnd) = _previousRangeBounds(start, end);
    final report = ReportEngine.buildReport(
      start: start,
      end: end,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
    );
    final previousReport = ReportEngine.buildReport(
      start: previousStart,
      end: previousEnd,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
    );
    final comparison = ReportEngine.compare(
      current: report,
      previous: previousReport,
    );
    final digest = PeriodReportDigest(
      kind: switch (_range) {
        _Range.week => PeriodReportKind.weekly,
        _Range.month => PeriodReportKind.monthly,
        _Range.year => PeriodReportKind.yearly,
      },
      report: report,
      comparison: comparison,
      generatedAt: DateTime.now(),
    );
    final productivityTrend = _buildProductivityTrend(
      range: _range,
      start: start,
      end: end,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
      copy: copy,
    );
    final activityHeatmap = _buildActivityHeatmap(
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
      diaries: diaryProv.entries,
    );
    final auditEntries = timeAuditProv.entriesInRange(start, end);
    final auditTotalMinutes =
        timeAuditProv.totalSecondsInRange(start, end) ~/ 60;
    final auditCategorySeconds = timeAuditProv.secondsByCategory(start, end);
    bool inRange(DateTime d) =>
        !d.isBefore(DateTime(start.year, start.month, start.day)) &&
        !d.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));

    final completedTodos = todoProv.completedTodos.where((t) {
      final ts = t.completedAt ?? t.updatedAt;
      return inRange(ts);
    }).toList();

    final focusSessions = pomoProv.sessions
        .where((s) => s.type == PomodoroType.focus && inRange(s.startTime))
        .toList();
    final focusMinutes =
        focusSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/ 60;
    final focusTagStats = FocusTagStats.build(sessions: focusSessions);
    final focusTagTrend = FocusTagStats.buildTrend(
      sessions: focusSessions,
      start: start,
      end: end,
      tags: focusTagStats.map((stat) => stat.tag).take(3),
      bucket: _range == _Range.year
          ? FocusTagTrendBucket.month
          : FocusTagTrendBucket.day,
    );
    final habitCompletionDates = [
      for (final habit in habitProv.habits)
        ...habit.completionDatesInRange(start, end),
    ];
    final crossAnalysis = ReportCrossAnalysis.build(
      start: start,
      end: end,
      bucket: _range == _Range.year
          ? ReportCrossBucket.month
          : ReportCrossBucket.day,
      todoCompletions: completedTodos.map(
        (todo) => ReportCrossTodoCompletion(todo.completedAt ?? todo.updatedAt),
      ),
      focusSessions: focusSessions.map(
        (session) => ReportCrossFocusSession(
          endedAt: session.endTime,
          durationSeconds: session.durationSeconds,
        ),
      ),
      habitCompletions: habitCompletionDates.map(
        ReportCrossHabitCompletion.new,
      ),
      diaryEntries: diaryProv.entries.map(
        (entry) => ReportCrossDiaryEntry(entry.date),
      ),
      timeEntries: auditEntries.map(
        (entry) => ReportCrossTimeEntry(
          startedAt: entry.startAt,
          durationSeconds: entry.durationSeconds,
          categoryKey: entry.category.name,
        ),
      ),
    );
    final projectEfficiency = _buildProjectEfficiencyBreakdown(
      start: start,
      end: end,
      completedTodos: completedTodos,
      goals: goalProv.goals,
      timeEntries: auditEntries,
      todos: todoProv.todos,
      copy: copy,
    );

    final diaryInRange = diaryProv.entries.where((d) => inRange(d.date)).length;

    final habitDoneInRange = habitCompletionDates.length;

    final now = DateTime.now();
    final quadrantStats = _buildQuadrantStats(
      {
        for (final quadrant in EisenhowerQuadrant.values)
          quadrant: todoProv.getQuadrantTodos(quadrant),
      },
      now: now,
      cs: cs,
      copy: copy,
    );

    // Weekly time audit data (always computed, independent of selected range)
    final weekMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekMonday.add(const Duration(days: 7));
    final weekSourceSeconds = timeAuditProv.secondsBySource(
      weekMonday,
      weekEnd,
    );
    final weekTotalSeconds = timeAuditProv.totalSecondsInRange(
      weekMonday,
      weekEnd,
    );
    final weekDaySeconds = timeAuditProv.secondsByDay(weekMonday, weekEnd);

    final buildAccountGeneration =
        AccountLocalDataCleaner.accountDataGeneration;
    final buildRoute = ModalRoute.of(context);
    bool isBuildOriginValid() {
      if (!mounted) return false;
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        buildAccountGeneration,
      )) {
        return false;
      }
      final route = buildRoute ?? (mounted ? ModalRoute.of(context) : null);
      if (route != null && !route.isCurrent) {
        return false;
      }
      final currentRoute = ModalRoute.of(context);
      if (currentRoute != null && !currentRoute.isCurrent) {
        return false;
      }
      return true;
    }

    final textScaler = MediaQuery.textScalerOf(context);
    final selectorPreferredHeight = math.max(
      48.0,
      2 * textScaler.scale(16.0) + 24.0,
    );

    final titleStyle =
        Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 16.0);
    final availableTitleWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - 184.0,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: copy.pageTitle, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: textScaler.clamp(maxScaleFactor: 1.34),
    )..layout(maxWidth: availableTitleWidth);
    final titleLineCount = titlePainter.computeLineMetrics().length;
    final titleHeight = titlePainter.height;
    titlePainter.dispose();

    final baseToolbarHeight = math.max(56.0, textScaler.scale(22.0) + 16.0);
    final effectiveToolbarHeight = titleLineCount > 1
        ? math.max(baseToolbarHeight, titleHeight + 16.0)
        : baseToolbarHeight;

    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(
          copy.pageTitle,
          softWrap: true,
          overflow: TextOverflow.visible,
          textAlign: TextAlign.center,
        ),
        toolbarHeight: effectiveToolbarHeight,
        actions: [
          IconButton(
            tooltip: copy.copyReportTooltip,
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () {
              if (!isBuildOriginValid()) return;
              _copyReport(
                context,
                start: start,
                end: end,
                completedTodos: completedTodos,
                focusMinutes: focusMinutes,
                habitDoneInRange: habitDoneInRange,
                diaryInRange: diaryInRange,
                auditTotalMinutes: auditTotalMinutes,
                auditCategorySeconds: auditCategorySeconds,
                auditEntries: auditEntries,
                originAccountGeneration: buildAccountGeneration,
                originRoute: buildRoute,
              );
            },
          ),
          IconButton(
            tooltip: copy.reportShareImageTooltip,
            icon: const Icon(Icons.image_outlined),
            onPressed: () {
              if (!isBuildOriginValid()) return;
              _showReportShareCard(
                context,
                start: start,
                end: end,
                completedTodos: completedTodos,
                focusMinutes: focusMinutes,
                habitDoneInRange: habitDoneInRange,
                diaryInRange: diaryInRange,
                auditTotalMinutes: auditTotalMinutes,
                auditCategorySeconds: auditCategorySeconds,
                auditEntries: auditEntries,
                originAccountGeneration: buildAccountGeneration,
                originRoute: buildRoute,
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(selectorPreferredHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SegmentedButton<_Range>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                ButtonSegment(
                  value: _Range.week,
                  label: Text(
                    copy.rangeWeek,
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ),
                ButtonSegment(
                  value: _Range.month,
                  label: Text(
                    copy.rangeMonth,
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ),
                ButtonSegment(
                  value: _Range.year,
                  label: Text(
                    copy.rangeYear,
                    textAlign: TextAlign.center,
                    softWrap: true,
                  ),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() {
                _range = s.first;
                _aiReportRequestSeq++;
                _aiReportBusy = false;
                _aiReportReview = null;
                _aiReportError = null;
              }),
            ),
          ),
        ),
      ),
      body: _widescreenReportBody(
        isWidescreen:
            MediaQuery.widthOf(context) >= DesktopTokens.breakpointTwoColumn,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 720
                    ? 3
                    : width < 360
                    ? 1
                    : 2;
                final childAspectRatio = crossAxisCount == 1
                    ? 4.2
                    : width >= 720
                    ? 2.8
                    : 2.5;
                final tileWidth =
                    (width - (crossAxisCount - 1) * 8) / crossAxisCount;
                final textScaler = MediaQuery.textScalerOf(context);
                final textDirection = Directionality.of(context);

                final surfaceStyle = appSurfaceStyleOf(context);
                final borderDimensions =
                    surfaceStyle?.cardBorder?.dimensions ??
                    (surfaceStyle == null
                        ? const EdgeInsets.all(0.55)
                        : EdgeInsets.zero);
                final cardBorderInsets = borderDimensions.resolve(
                  textDirection,
                );
                final cardHorizontalInsets = 20.0 + cardBorderInsets.horizontal;
                final cardVerticalInsets = 20.0 + cardBorderInsets.vertical;

                final bodyMedium =
                    Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
                final titleStyle = bodyMedium.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                );
                final valueStyle = bodyMedium.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                );

                final kpiItems = [
                  (
                    icon: Icons.check_circle,
                    color: cs.primary,
                    title: copy.kpiCompletedTodos,
                    value: '${completedTodos.length}',
                  ),
                  (
                    icon: Icons.timer,
                    color: DesignTokens.defaultError,
                    title: copy.kpiDeepFocus,
                    value: copy.minutesCount(focusMinutes),
                  ),
                  (
                    icon: Icons.repeat,
                    color: DesignTokens.defaultSuccess,
                    title: copy.kpiHabitCheckIns,
                    value: copy.timesCount(habitDoneInRange),
                  ),
                  (
                    icon: Icons.book_outlined,
                    color: DesignTokens.defaultAccent,
                    title: copy.kpiDiary,
                    value: copy.diaryEntriesCount(diaryInRange),
                  ),
                  (
                    icon: Icons.timelapse_outlined,
                    color: cs.onSurfaceVariant,
                    title: copy.kpiTimeFootprint,
                    value: copy.minutesCount(auditTotalMinutes),
                  ),
                ];

                final sideTextWidth = math.max(
                  0.0,
                  tileWidth - cardHorizontalInsets - 44.0,
                );
                final reflowTextWidth = math.max(
                  0.0,
                  tileWidth - cardHorizontalInsets,
                );
                final reflowFlags = <bool>[];
                var maxMeasuredExtent = 0.0;

                for (final item in kpiItems) {
                  final titleToken = _Kpi.maxTokenWidth(
                    item.title,
                    titleStyle,
                    textScaler,
                    textDirection,
                  );
                  final valueToken = _Kpi.maxTokenWidth(
                    item.value,
                    valueStyle,
                    textScaler,
                    textDirection,
                  );
                  final needsReflow =
                      crossAxisCount == 2 &&
                      (titleToken > sideTextWidth ||
                          valueToken > sideTextWidth);
                  reflowFlags.add(needsReflow);

                  final textWidth = needsReflow
                      ? reflowTextWidth
                      : sideTextWidth;
                  final tpTitle = TextPainter(
                    text: TextSpan(text: item.title, style: titleStyle),
                    textScaler: textScaler,
                    textDirection: textDirection,
                  )..layout(maxWidth: textWidth);
                  final tpValue = TextPainter(
                    text: TextSpan(text: item.value, style: valueStyle),
                    textScaler: textScaler,
                    textDirection: textDirection,
                  )..layout(maxWidth: textWidth);

                  final contentHeight = needsReflow
                      ? 34.0 + 6.0 + tpTitle.height + 2.0 + tpValue.height
                      : math.max(34.0, tpTitle.height + 2.0 + tpValue.height);
                  final itemHeight = contentHeight + cardVerticalInsets;
                  tpTitle.dispose();
                  tpValue.dispose();

                  if (itemHeight > maxMeasuredExtent) {
                    maxMeasuredExtent = itemHeight;
                  }
                }

                final tileExtent = math.max(
                  tileWidth / childAspectRatio,
                  maxMeasuredExtent,
                );
                return GridView.count(
                  key: const ValueKey('statistics_kpi_grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  mainAxisExtent: tileExtent,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _Kpi(
                      icon: Icons.check_circle,
                      color: cs.primary,
                      title: copy.kpiCompletedTodos,
                      value: '${completedTodos.length}',
                      reflow: reflowFlags[0],
                    ),
                    _Kpi(
                      icon: Icons.timer,
                      color: DesignTokens.defaultError,
                      title: copy.kpiDeepFocus,
                      value: copy.minutesCount(focusMinutes),
                      reflow: reflowFlags[1],
                    ),
                    _Kpi(
                      icon: Icons.repeat,
                      color: DesignTokens.defaultSuccess,
                      title: copy.kpiHabitCheckIns,
                      value: copy.timesCount(habitDoneInRange),
                      reflow: reflowFlags[2],
                    ),
                    _Kpi(
                      icon: Icons.book_outlined,
                      color: DesignTokens.defaultAccent,
                      title: copy.kpiDiary,
                      value: copy.diaryEntriesCount(diaryInRange),
                      reflow: reflowFlags[3],
                    ),
                    _Kpi(
                      icon: Icons.timelapse_outlined,
                      color: cs.onSurfaceVariant,
                      title: copy.kpiTimeFootprint,
                      value: copy.minutesCount(auditTotalMinutes),
                      reflow: reflowFlags[4],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _PeriodReportDigestCard(
              digest: digest,
              cs: cs,
              onCopy: () {
                if (!isBuildOriginValid()) return;
                _copyDigest(
                  context,
                  digest,
                  originAccountGeneration: buildAccountGeneration,
                  originRoute: buildRoute,
                );
              },
              aiEnabled: ai.enabled,
              aiBusy: _aiReportBusy,
              aiReview: _aiReportReview,
              aiError: _aiReportError,
              onAiReview: () {
                if (!isBuildOriginValid() || _aiReportBusy) return;
                _runDigestAiReview(
                  context,
                  digest,
                  originAccountGeneration: buildAccountGeneration,
                  originRoute: buildRoute,
                );
              },
              onOpenAiHistory: () {
                if (!isBuildOriginValid()) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AiHistoryScreen()),
                );
              },
              onShareImage: () {
                if (!isBuildOriginValid()) return;
                _showReportShareCard(
                  context,
                  start: start,
                  end: end,
                  completedTodos: completedTodos,
                  focusMinutes: focusMinutes,
                  habitDoneInRange: habitDoneInRange,
                  diaryInRange: diaryInRange,
                  auditTotalMinutes: auditTotalMinutes,
                  auditCategorySeconds: auditCategorySeconds,
                  auditEntries: auditEntries,
                  originAccountGeneration: buildAccountGeneration,
                  originRoute: buildRoute,
                );
              },
              copy: copy,
            ),
            const SizedBox(height: 10),
            _ProductivityComparisonCard(
              comparison: comparison,
              range: _range,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _ProductivityTrendCard(
              points: productivityTrend,
              range: _range,
              copy: copy,
              onOpenDetail: () {
                if (!isBuildOriginValid()) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ProductivityTrendDetailScreen(
                      points: productivityTrend,
                      range: _range,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildFocusTodoCorrelationCard(
              correlation: crossAnalysis.focusTodo,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _buildHabitTodoCorrelationCard(
              correlation: crossAnalysis.habitTodo,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _buildDiaryFocusCorrelationCard(
              correlation: crossAnalysis.diaryFocus,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _buildTimeCategoryShareTrendCard(
              trend: crossAnalysis.timeCategoryTrend,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _buildTimeOutputEfficiencyCard(
              trend: crossAnalysis.timeOutputEfficiency,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _buildProjectEfficiencyCard(
              breakdown: projectEfficiency,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            ActivityHeatmapCard(heatmapData: activityHeatmap),
            const SizedBox(height: 10),
            _WeeklyTimeOverview(
              weekTotalSeconds: weekTotalSeconds,
              sourceSeconds: weekSourceSeconds,
              daySeconds: weekDaySeconds,
              weekMonday: weekMonday,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _chartCard(
              copy.timeDistribution,
              SizedBox(
                height: 180,
                child: _buildAuditPie(
                  secondsByCategory: auditCategorySeconds,
                  cs: cs,
                  copy: copy,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _chartCard(
              copy.timeline,
              _buildAuditTimeline(
                auditEntries,
                cs,
                copy: copy,
                onViewAll: () {
                  if (!isBuildOriginValid()) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimeAuditScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _chartCard(
              _range == _Range.year
                  ? copy.monthlyFocusMinutes
                  : copy.dailyFocusMinutes,
              SizedBox(
                height: 180,
                child: _buildFocusSeries(
                  sessions: focusSessions,
                  range: _range,
                  start: start,
                  end: end,
                  cs: cs,
                  copy: copy,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildFocusTagRankingCard(stats: focusTagStats, cs: cs, copy: copy),
            const SizedBox(height: 10),
            _buildFocusTagTrendCard(
              series: focusTagTrend,
              range: _range,
              cs: cs,
              copy: copy,
            ),
            const SizedBox(height: 10),
            _QuadrantDistributionCard(stats: quadrantStats, cs: cs, copy: copy),
          ],
        ),
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  /// 宽屏桌面档：报告内容限宽居中（KPI 网格在 ≥720 内宽保持 3 列所需
  /// 最小外宽 960，见 [DesktopTokens.reportMaxContentWidth]）；窄屏原样。
  Widget _widescreenReportBody({
    required bool isWidescreen,
    required Widget child,
  }) {
    if (!isWidescreen) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesktopTokens.reportMaxContentWidth,
        ),
        child: child,
      ),
    );
  }

  (DateTime, DateTime) _previousRangeBounds(DateTime start, DateTime end) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    final days = endDate.difference(startDate).inDays + 1;
    final previousEnd = startDate.subtract(const Duration(days: 1));
    final previousStart = previousEnd.subtract(Duration(days: days - 1));
    return (previousStart, previousEnd);
  }

  List<_ProductivityTrendPoint> _buildProductivityTrend({
    required _Range range,
    required DateTime start,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    final currentSpanDays = endDate.difference(startDate).inDays;

    return switch (range) {
      _Range.week => [
        for (int offset = 5; offset >= 0; offset--)
          _productivityTrendPoint(
            label: offset == 0
                ? effectiveCopy.rangeWeek
                : '${startDate.subtract(Duration(days: offset * 7)).month}/'
                      '${startDate.subtract(Duration(days: offset * 7)).day}',
            start: startDate.subtract(Duration(days: offset * 7)),
            end: startDate
                .subtract(Duration(days: offset * 7))
                .add(Duration(days: currentSpanDays)),
            todos: todos,
            habits: habits,
            sessions: sessions,
            timeEntries: timeEntries,
            range: _Range.week,
            isCurrentPeriod: offset == 0,
          ),
      ],
      _Range.month => [
        for (int offset = 5; offset >= 0; offset--)
          _monthTrendPoint(
            offset: offset,
            end: endDate,
            todos: todos,
            habits: habits,
            sessions: sessions,
            timeEntries: timeEntries,
            copy: effectiveCopy,
          ),
      ],
      _Range.year => [
        for (int offset = 4; offset >= 0; offset--)
          _yearTrendPoint(
            offset: offset,
            end: endDate,
            todos: todos,
            habits: habits,
            sessions: sessions,
            timeEntries: timeEntries,
            copy: effectiveCopy,
          ),
      ],
    };
  }

  _ProductivityTrendPoint _monthTrendPoint({
    required int offset,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final periodStart = DateTime(end.year, end.month - offset, 1);
    final periodLastDay = DateTime(periodStart.year, periodStart.month + 1, 0);
    final periodEnd = DateTime(
      periodStart.year,
      periodStart.month,
      end.day.clamp(1, periodLastDay.day),
    );
    return _productivityTrendPoint(
      label: offset == 0
          ? effectiveCopy.rangeMonth
          : effectiveCopy.monthNumberLabel(periodStart.month),
      start: periodStart,
      end: periodEnd,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
      range: _Range.month,
      isCurrentPeriod: offset == 0,
    );
  }

  _ProductivityTrendPoint _yearTrendPoint({
    required int offset,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final year = end.year - offset;
    final periodStart = DateTime(year, 1, 1);
    final targetMonthLastDay = DateTime(year, end.month + 1, 0).day;
    final periodEnd = DateTime(
      year,
      end.month,
      end.day.clamp(1, targetMonthLastDay),
    );
    return _productivityTrendPoint(
      label: offset == 0 ? effectiveCopy.thisYear : '$year',
      start: periodStart,
      end: periodEnd,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
      range: _Range.year,
      isCurrentPeriod: offset == 0,
    );
  }

  _ProductivityTrendPoint _productivityTrendPoint({
    required String label,
    required DateTime start,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    _Range? range,
    bool isCurrentPeriod = false,
  }) {
    final report = ReportEngine.buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
    return _ProductivityTrendPoint(
      label: label,
      start: start,
      end: end,
      report: report,
      range: range,
      isCurrentPeriod: isCurrentPeriod,
    );
  }

  Map<String, int> _buildActivityHeatmap({
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    required List<DiaryEntry> diaries,
  }) {
    final raw = <String, int>{};

    void add(DateTime date, int amount) {
      if (amount <= 0) return;
      final key = _dateKey(date);
      raw[key] = (raw[key] ?? 0) + amount;
    }

    for (final todo in todos) {
      final completedAt = todo.completedAt;
      if (todo.isCompleted && completedAt != null) {
        add(completedAt.toLocal(), 2);
      }
    }
    for (final habit in habits) {
      for (final entry in habit.completions.entries) {
        final date = _parseDateKey(entry.key);
        if (date != null && habit.activeForDate(date)) add(date, entry.value);
      }
    }
    for (final session in sessions) {
      if (session.type == PomodoroType.focus) add(session.endTime.toLocal(), 2);
    }
    for (final entry in timeEntries) {
      final minutes = entry.durationSeconds ~/ 60;
      add(entry.startAt.toLocal(), minutes >= 60 ? 2 : 1);
    }
    for (final diary in diaries) {
      add(diary.date, 1);
    }

    return raw.map((key, value) => MapEntry(key, value.clamp(0, 5)));
  }

  String _dateKey(DateTime date) => HeatmapCalendarWindow.dateKey(date);

  DateTime? _parseDateKey(String key) =>
      HeatmapCalendarWindow.tryParseDateKey(key);

  Widget _chartCard(String title, Widget child) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  List<_QuadrantStat> _buildQuadrantStats(
    Map<EisenhowerQuadrant, List<TodoItem>> groups, {
    required DateTime now,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final today = DateTime(now.year, now.month, now.day);

    _QuadrantStat stat(
      EisenhowerQuadrant quadrant, {
      required String label,
      required String action,
      required String guidance,
      required Color color,
      required IconData icon,
    }) {
      final items = groups[quadrant] ?? const <TodoItem>[];
      final active = items.where((todo) => !todo.isCompleted).length;
      final completed = items.where((todo) => todo.isCompleted).length;
      final overdue = items.where((todo) {
        final due = todo.dueDate;
        if (todo.isCompleted || due == null) return false;
        return DateTime(due.year, due.month, due.day).isBefore(today);
      }).length;
      final dueToday = items.where((todo) {
        final due = todo.dueDate;
        if (todo.isCompleted || due == null) return false;
        return due.year == today.year &&
            due.month == today.month &&
            due.day == today.day;
      }).length;
      return _QuadrantStat(
        label: label,
        action: action,
        guidance: guidance,
        color: color,
        icon: icon,
        totalCount: items.length,
        activeCount: active,
        completedCount: completed,
        overdueCount: overdue,
        dueTodayCount: dueToday,
      );
    }

    return [
      stat(
        EisenhowerQuadrant.urgentImportant,
        label: effectiveCopy.quadrantUrgentImportantLabel,
        action: effectiveCopy.quadrantUrgentImportantAction,
        guidance: effectiveCopy.quadrantUrgentImportantGuidance,
        color: DesignTokens.defaultError,
        icon: Icons.priority_high_rounded,
      ),
      stat(
        EisenhowerQuadrant.notUrgentImportant,
        label: effectiveCopy.quadrantNotUrgentImportantLabel,
        action: effectiveCopy.quadrantNotUrgentImportantAction,
        guidance: effectiveCopy.quadrantNotUrgentImportantGuidance,
        color: DesignTokens.defaultWarning,
        icon: Icons.event_available_outlined,
      ),
      stat(
        EisenhowerQuadrant.urgentNotImportant,
        label: effectiveCopy.quadrantUrgentNotImportantLabel,
        action: effectiveCopy.quadrantUrgentNotImportantAction,
        guidance: effectiveCopy.quadrantUrgentNotImportantGuidance,
        color: DesignTokens.defaultInfo,
        icon: Icons.swap_horiz_rounded,
      ),
      stat(
        EisenhowerQuadrant.notUrgentNotImportant,
        label: effectiveCopy.quadrantNotUrgentNotImportantLabel,
        action: effectiveCopy.quadrantNotUrgentNotImportantAction,
        guidance: effectiveCopy.quadrantNotUrgentNotImportantGuidance,
        color: cs.onSurfaceVariant,
        icon: Icons.filter_alt_off_outlined,
      ),
    ];
  }

  Widget _buildFocusTagRankingCard({
    required List<FocusTagStat> stats,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            effectiveCopy.focusTagRanking,
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (stats.isEmpty)
            EmptyHint(
              icon: Icons.timer_outlined,
              message: effectiveCopy.noFocusTagData,
            )
          else
            for (final (index, stat) in stats.indexed)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#${index + 1}',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.normal,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  stat.tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                effectiveCopy.minutesCount(stat.totalMinutes),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          _buildFocusTagShare(stat.share, cs),
                          const SizedBox(height: 4),
                          Text(
                            effectiveCopy.focusTagSessionSummary(
                              stat.sessionCount,
                              stat.averageMinutes,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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

  Widget _buildFocusTagShare(double share, ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: share.clamp(0, 1),
        minHeight: 6,
        backgroundColor: cs.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
      ),
    );
  }

  Widget _buildFocusTagTrendCard({
    required List<FocusTagTrendSeries> series,
    required _Range range,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activeSeries = series
        .where((item) => item.points.any((point) => point.minutes > 0))
        .toList();
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.focusTagTrend,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                range == _Range.year
                    ? effectiveCopy.byMonth
                    : effectiveCopy.byDay,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (activeSeries.isEmpty)
            EmptyHint(
              icon: Icons.trending_up,
              message: effectiveCopy.noFocusTagTrend,
            )
          else ...[
            SizedBox(
              height: 190,
              child: _buildFocusTagTrendChart(
                activeSeries,
                cs,
                copy: effectiveCopy,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final (index, item) in activeSeries.indexed)
                  _legend(_focusTagTrendColor(index, cs), item.tag),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusTagTrendChart(
    List<FocusTagTrendSeries> series,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final points = series.first.points;
    final maxMinutes = series.fold<int>(
      0,
      (max, item) => item.maxMinutes > max ? item.maxMinutes : max,
    );
    final maxY = (maxMinutes * 1.2).clamp(10, double.infinity).toDouble();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY <= 30 ? 10 : null,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                if (points.length > 10 && index.isOdd) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    points[index].label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (items) => [
              for (final item in items)
                LineTooltipItem(
                  '${series[item.barIndex].tag}\n'
                  '${points[item.x.toInt()].label} · ${effectiveCopy.minutesCount(item.y.toInt())}',
                  TextStyle(color: cs.onInverseSurface, fontSize: 11),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final (seriesIndex, item) in series.indexed)
            LineChartBarData(
              spots: [
                for (int i = 0; i < item.points.length; i++)
                  FlSpot(i.toDouble(), item.points[i].minutes.toDouble()),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              color: _focusTagTrendColor(seriesIndex, cs),
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: seriesIndex == 0,
                color: _focusTagTrendColor(
                  seriesIndex,
                  cs,
                ).withValues(alpha: 0.08),
              ),
            ),
        ],
      ),
    );
  }

  Color _focusTagTrendColor(int index, ColorScheme cs) {
    final colors = [
      cs.primary,
      DesignTokens.defaultAccent,
      DesignTokens.defaultWarning,
    ];
    return colors[index % colors.length];
  }

  Widget _buildFocusTodoCorrelationCard({
    required FocusTodoCorrelation correlation,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activePoints = correlation.activePoints;
    final r = correlation.pearson;
    final rText = r == null
        ? effectiveCopy.insufficientSamples
        : r.toStringAsFixed(2);
    final insight = effectiveCopy.focusTodoInsight(r);

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.focusTodoCorrelation,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(label: 'r', value: rText, cs: cs),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            effectiveCopy.focusTodoAxisLabel,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: activePoints.isEmpty
                ? EmptyHint(
                    icon: Icons.donut_small,
                    message: effectiveCopy.noCrossAnalysisData,
                  )
                : _buildFocusTodoScatter(correlation, cs, copy: effectiveCopy),
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusTodoScatter(
    FocusTodoCorrelation correlation,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activePoints = correlation.activePoints;
    final maxX = (correlation.maxFocusMinutes * 1.2)
        .clamp(10, 100000)
        .toDouble();
    final maxY = (correlation.maxCompletedTodos * 1.2)
        .clamp(3, 100000)
        .toDouble();

    FocusTodoPoint? pointFor(ScatterSpot spot) {
      for (final point in activePoints) {
        if (point.focusMinutes.toDouble() == spot.x &&
            point.completedTodos.toDouble() == spot.y) {
          return point;
        }
      }
      return null;
    }

    return ScatterChart(
      ScatterChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(
          touchSpotThreshold: 16,
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spot) {
              final point = pointFor(spot);
              return ScatterTooltipItem(
                point == null
                    ? effectiveCopy.minutesAndItems(
                        spot.x.toInt(),
                        spot.y.toInt(),
                      )
                    : '${point.label}\n${effectiveCopy.minutesAndItems(point.focusMinutes, point.completedTodos)}',
                textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        scatterSpots: [
          for (final point in activePoints)
            ScatterSpot(
              point.focusMinutes.toDouble(),
              point.completedTodos.toDouble(),
              dotPainter: FlDotCirclePainter(
                radius: 5,
                color: cs.primary,
                strokeWidth: 2,
                strokeColor: cs.surface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHabitTodoCorrelationCard({
    required HabitTodoCorrelation correlation,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activePoints = correlation.activePoints;
    final r = correlation.pearson;
    final rText = r == null
        ? effectiveCopy.insufficientSamples
        : r.toStringAsFixed(2);
    final insight = effectiveCopy.habitTodoInsight(r);

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.habitTodoCorrelation,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(label: 'r', value: rText, cs: cs),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            effectiveCopy.habitTodoAxisLabel,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: activePoints.isEmpty
                ? EmptyHint(
                    icon: Icons.repeat,
                    message: effectiveCopy.noHabitCrossData,
                  )
                : _buildHabitTodoScatter(correlation, cs, copy: effectiveCopy),
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitTodoScatter(
    HabitTodoCorrelation correlation,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activePoints = correlation.activePoints;
    final maxX = (correlation.maxHabitCheckIns * 1.2)
        .clamp(3, 100000)
        .toDouble();
    final maxY = (correlation.maxCompletedTodos * 1.2)
        .clamp(3, 100000)
        .toDouble();

    HabitTodoPoint? pointFor(ScatterSpot spot) {
      for (final point in activePoints) {
        if (point.habitCheckIns.toDouble() == spot.x &&
            point.completedTodos.toDouble() == spot.y) {
          return point;
        }
      }
      return null;
    }

    return ScatterChart(
      ScatterChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(
          touchSpotThreshold: 16,
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spot) {
              final point = pointFor(spot);
              return ScatterTooltipItem(
                point == null
                    ? effectiveCopy.timesAndItems(
                        spot.x.toInt(),
                        spot.y.toInt(),
                      )
                    : '${point.label}\n${effectiveCopy.timesAndItems(point.habitCheckIns, point.completedTodos)}',
                textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        scatterSpots: [
          for (final point in activePoints)
            ScatterSpot(
              point.habitCheckIns.toDouble(),
              point.completedTodos.toDouble(),
              dotPainter: FlDotCirclePainter(
                radius: 5,
                color: cs.tertiary,
                strokeWidth: 2,
                strokeColor: cs.surface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiaryFocusCorrelationCard({
    required DiaryFocusCorrelation correlation,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activePoints = correlation.activePoints;
    final r = correlation.pearson;
    final rText = r == null
        ? effectiveCopy.insufficientSamples
        : r.toStringAsFixed(2);
    final insight = effectiveCopy.diaryFocusInsight(r);

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.diaryFocusCorrelation,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(label: 'r', value: rText, cs: cs),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            effectiveCopy.diaryFocusAxisLabel,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: activePoints.isEmpty
                ? EmptyHint(
                    icon: Icons.menu_book,
                    message: effectiveCopy.noDiaryFocusCrossData,
                  )
                : _buildDiaryFocusScatter(correlation, cs, copy: effectiveCopy),
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiaryFocusScatter(
    DiaryFocusCorrelation correlation,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final activePoints = correlation.activePoints;
    final maxX = (correlation.maxDiaryEntries * 1.2)
        .clamp(3, 100000)
        .toDouble();
    final maxY = (correlation.maxFocusMinutes * 1.2)
        .clamp(10, 100000)
        .toDouble();

    DiaryFocusPoint? pointFor(ScatterSpot spot) {
      for (final point in activePoints) {
        if (point.diaryEntries.toDouble() == spot.x &&
            point.focusMinutes.toDouble() == spot.y) {
          return point;
        }
      }
      return null;
    }

    return ScatterChart(
      ScatterChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(
          touchSpotThreshold: 16,
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spot) {
              final point = pointFor(spot);
              return ScatterTooltipItem(
                point == null
                    ? effectiveCopy.diaryAndMinutes(
                        spot.x.toInt(),
                        spot.y.toInt(),
                      )
                    : '${point.label}\n${effectiveCopy.diaryAndMinutes(point.diaryEntries, point.focusMinutes)}',
                textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        scatterSpots: [
          for (final point in activePoints)
            ScatterSpot(
              point.diaryEntries.toDouble(),
              point.focusMinutes.toDouble(),
              dotPainter: FlDotCirclePainter(
                radius: 5,
                color: cs.tertiary,
                strokeWidth: 2,
                strokeColor: cs.surface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeCategoryShareTrendCard({
    required TimeCategoryShareTrend trend,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            effectiveCopy.timeCategoryShareTrend,
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            effectiveCopy.timeCategoryShareTrendSubtitle,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: trend.hasData
                ? _buildTimeCategoryShareChart(trend, cs, copy: effectiveCopy)
                : EmptyHint(
                    icon: Icons.pie_chart_outline,
                    message: effectiveCopy.noTimeCategoryTrend,
                  ),
          ),
          if (trend.hasData) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final key in trend.categoryKeys)
                  _legend(
                    _crossCategoryColor(key, cs),
                    _crossCategoryLabel(key, effectiveCopy),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeCategoryShareChart(
    TimeCategoryShareTrend trend,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final buckets = trend.buckets;
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= buckets.length) return null;
              final bucket = buckets[groupIndex];
              final lines = <String>[
                bucket.label,
                for (final key in trend.categoryKeys)
                  if ((bucket.secondsByCategory[key] ?? 0) > 0)
                    '${_crossCategoryLabel(key, effectiveCopy)} '
                        '${((bucket.shareByCategory[key] ?? 0) * 100).round()}%',
              ];
              return BarTooltipItem(
                lines.join('\n'),
                TextStyle(color: cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 25,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}%',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= buckets.length) {
                  return const SizedBox();
                }
                if (buckets.length > 10 && index.isOdd) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    buckets[index].label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (final (index, bucket) in buckets.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: 100,
                  width: buckets.length > 14 ? 8 : 14,
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  rodStackItems: _buildShareStackItems(bucket, trend, cs),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimeOutputEfficiencyCard({
    required TimeOutputEfficiencyTrend trend,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final points = trend.points;
    final hasData = points.any((point) => point.hasActivity);
    final average = _averageCompletedTodosPerHour(points);

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.timeOutputEfficiencyTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(
                label: effectiveCopy.completedPerHour,
                value: average <= 0
                    ? effectiveCopy.itemsCount(0)
                    : effectiveCopy.itemsCountDouble(average),
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            effectiveCopy.timeOutputEfficiencySubtitle,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: hasData
                ? _buildTimeOutputEfficiencyChart(
                    trend,
                    cs,
                    copy: effectiveCopy,
                  )
                : EmptyHint(
                    icon: Icons.swap_vert,
                    message: effectiveCopy.noTimeOutputData,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeOutputEfficiencyChart(
    TimeOutputEfficiencyTrend trend,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final points = trend.points;
    final peak = points.fold<double>(
      0,
      (max, point) =>
          point.completedTodosPerHour > max ? point.completedTodosPerHour : max,
    );
    final maxY = peak <= 0 ? 1.0 : peak * 1.25;
    final interval = _timeOutputAxisInterval(maxY);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= points.length) return null;
              final point = points[groupIndex];
              return BarTooltipItem(
                '${_timeOutputPeriodLabel(point)}\n'
                '${effectiveCopy.completedPerHour}: ${point.completedTodosPerHour.toStringAsFixed(1)}\n'
                '${effectiveCopy.minutesAndItems(point.timeMinutes, point.completedTodos)}',
                TextStyle(color: cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                _formatTimeOutputRate(value),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                if (points.length > 10 && index.isOdd) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: SizedBox(
                    width: 38,
                    child: Text(
                      _timeOutputPeriodLabel(points[index]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (final (index, point) in points.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: point.completedTodosPerHour,
                  width: points.length > 14 ? 7 : 12,
                  color: DesignTokens.defaultAccent,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  ProjectEfficiencyBreakdown _buildProjectEfficiencyBreakdown({
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required List<GoalItem> goals,
    required List<TimeEntry> timeEntries,
    required List<TodoItem> todos,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final todoById = {for (final todo in todos) todo.id: todo};
    final goalById = {for (final goal in goals) goal.id: goal};

    return ProjectEfficiencyAnalyzer.build(
      todoCompletions: completedTodos.map(
        (todo) => ProjectEfficiencyTodoCompletion(
          completedAt: todo.completedAt ?? todo.updatedAt,
          projectKey: _todoProjectKey(todo),
          projectLabel: _todoProjectLabel(todo, effectiveCopy),
        ),
      ),
      goalCompletions: [
        for (final goal in goals)
          for (final milestone in goal.milestones)
            if (milestone.isCompleted &&
                milestone.completedAt != null &&
                _isDateTimeInRange(milestone.completedAt!, start, end))
              ProjectEfficiencyGoalCompletion(
                completedAt: milestone.completedAt!,
                projectKey: _goalProjectKey(goal),
                projectLabel: _goalProjectLabel(goal, effectiveCopy),
              ),
      ],
      timeAllocations: [
        for (final entry in timeEntries)
          if (entry.durationSeconds > 0)
            ProjectEfficiencyTimeAllocation(
              projectKey: _timeEntryProjectKey(
                entry,
                todoById: todoById,
                goalById: goalById,
              ),
              projectLabel: _timeEntryProjectLabel(
                entry,
                todoById: todoById,
                goalById: goalById,
                copy: effectiveCopy,
              ),
              durationSeconds: entry.durationSeconds,
            ),
      ],
    );
  }

  Widget _buildProjectEfficiencyCard({
    required ProjectEfficiencyBreakdown breakdown,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final items = breakdown.rankedItems.take(6).toList(growable: false);
    final top = breakdown.topItem;

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.projectEfficiencyTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(
                label: effectiveCopy.highest,
                value: top == null
                    ? effectiveCopy.noData
                    : effectiveCopy.itemsPerHour(top.outputPerHour),
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            effectiveCopy.projectEfficiencySubtitle,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            EmptyHint(
              icon: Icons.speed,
              message: effectiveCopy.noProjectEfficiencyData,
            )
          else ...[
            SizedBox(
              height: 190,
              child: _buildProjectEfficiencyChart(
                items,
                cs,
                copy: effectiveCopy,
              ),
            ),
            const SizedBox(height: 10),
            for (final item in items.take(4))
              _ProjectEfficiencyRow(
                item: item,
                maxOutputPerHour: breakdown.maxOutputPerHour,
                cs: cs,
                copy: effectiveCopy,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectEfficiencyChart(
    List<ProjectEfficiencyItem> items,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final maxY =
        (items.fold<double>(
                  0,
                  (max, item) =>
                      item.outputPerHour > max ? item.outputPerHour : max,
                ) *
                1.25)
            .clamp(1, double.infinity)
            .toDouble();
    final interval = _timeOutputAxisInterval(maxY);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= items.length) return null;
              final item = items[groupIndex];
              return BarTooltipItem(
                '${item.projectLabel}\n'
                '${effectiveCopy.projectEfficiencyTooltipOutput(outputCount: item.outputCount, timeMinutes: item.timeMinutes)}\n'
                '${effectiveCopy.itemsPerHour(item.outputPerHour)}',
                TextStyle(color: cs.onInverseSurface, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                _formatTimeOutputRate(value),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= items.length) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: SizedBox(
                    width: 44,
                    child: Text(
                      items[index].projectLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (final (index, item) in items.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: item.outputPerHour,
                  width: items.length > 5 ? 10 : 14,
                  color: _projectEfficiencyColor(index, cs),
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _todoProjectKey(TodoItem todo) {
    final id = todo.listGroupId?.trim();
    if (id != null && id.isNotEmpty) return 'todo:$id';
    final name = todo.listGroupName?.trim();
    if (name != null && name.isNotEmpty) return 'todo_name:$name';
    return 'todo:inbox';
  }

  String _todoProjectLabel(TodoItem todo, [StatisticsUiCopy? copy]) {
    final name = todo.listGroupName?.trim();
    return name == null || name.isEmpty
        ? (copy ?? StatisticsUiCopy.current()).inbox
        : name;
  }

  String _goalProjectKey(GoalItem goal) => 'goal:${goal.id}';

  String _goalProjectLabel(GoalItem goal, [StatisticsUiCopy? copy]) =>
      goal.title.trim().isEmpty
      ? (copy ?? StatisticsUiCopy.current()).untitledGoal
      : goal.title.trim();

  String _timeEntryProjectKey(
    TimeEntry entry, {
    required Map<String, TodoItem> todoById,
    required Map<String, GoalItem> goalById,
  }) {
    if (entry.source == TimeEntrySource.todo && entry.sourceId != null) {
      final todo = todoById[entry.sourceId!];
      if (todo != null) return _todoProjectKey(todo);
    }
    if (entry.source == TimeEntrySource.goal && entry.sourceId != null) {
      final goalId = entry.sourceId!.split(':').first;
      final goal = goalById[goalId];
      if (goal != null) return _goalProjectKey(goal);
    }
    return 'manual:${entry.category.name}';
  }

  String _timeEntryProjectLabel(
    TimeEntry entry, {
    required Map<String, TodoItem> todoById,
    required Map<String, GoalItem> goalById,
    StatisticsUiCopy? copy,
  }) {
    if (entry.source == TimeEntrySource.todo && entry.sourceId != null) {
      final todo = todoById[entry.sourceId!];
      if (todo != null) return _todoProjectLabel(todo, copy);
    }
    if (entry.source == TimeEntrySource.goal && entry.sourceId != null) {
      final goalId = entry.sourceId!.split(':').first;
      final goal = goalById[goalId];
      if (goal != null) return _goalProjectLabel(goal, copy);
    }
    return entry.category.label;
  }

  bool _isDateTimeInRange(DateTime value, DateTime start, DateTime end) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    return !value.isBefore(startDate) && value.isBefore(endExclusive);
  }

  Color _projectEfficiencyColor(int index, ColorScheme cs) {
    final colors = [
      cs.primary,
      DesignTokens.defaultAccent,
      DesignTokens.defaultWarning,
      DesignTokens.defaultInfo,
      cs.tertiary,
      cs.onSurfaceVariant,
    ];
    return colors[index % colors.length];
  }

  String _timeOutputPeriodLabel(TimeOutputPoint point) {
    final dynamic dynamicPoint = point;
    try {
      return dynamicPoint.periodLabel as String;
    } on NoSuchMethodError {
      return dynamicPoint.label as String;
    }
  }

  double _averageCompletedTodosPerHour(List<TimeOutputPoint> points) {
    final activePoints = points
        .where((point) => point.timeMinutes > 0 || point.completedTodos > 0)
        .toList(growable: false);
    if (activePoints.isEmpty) return 0;
    final total = activePoints.fold<double>(
      0,
      (sum, point) => sum + point.completedTodosPerHour,
    );
    return total / activePoints.length;
  }

  double _timeOutputAxisInterval(double maxY) {
    if (maxY <= 2) return 0.5;
    if (maxY <= 6) return 1;
    return (maxY / 4).ceilToDouble();
  }

  String _formatTimeOutputRate(double value) {
    if (value == 0) return '0';
    if (value >= 10) return value.toStringAsFixed(0);
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  List<BarChartRodStackItem> _buildShareStackItems(
    TimeCategoryShareBucket bucket,
    TimeCategoryShareTrend trend,
    ColorScheme cs,
  ) {
    var cursor = 0.0;
    final items = <BarChartRodStackItem>[];
    for (final key in trend.categoryKeys) {
      final share = ((bucket.shareByCategory[key] ?? 0) * 100).clamp(0, 100);
      if (share <= 0) continue;
      final next = (cursor + share).clamp(0, 100).toDouble();
      items.add(
        BarChartRodStackItem(cursor, next, _crossCategoryColor(key, cs)),
      );
      cursor = next;
    }
    return items;
  }

  String _crossCategoryLabel(String key, StatisticsUiCopy copy) {
    if (key == ReportCrossAnalysis.otherCategoryKey) return copy.otherCategory;
    final category = _timeEntryCategoryFromKey(key);
    return category != null ? copy.categoryLabel(category) : key;
  }

  Color _crossCategoryColor(String key, ColorScheme cs) {
    if (key == ReportCrossAnalysis.otherCategoryKey) {
      return cs.onSurfaceVariant;
    }
    final category = _timeEntryCategoryFromKey(key);
    return category == null ? cs.secondary : _auditColor(category, cs);
  }

  TimeEntryCategory? _timeEntryCategoryFromKey(String key) {
    for (final category in TimeEntryCategory.values) {
      if (category.name == key ||
          category.label == key ||
          StatisticsUiCopy(AppLocale.zh).categoryLabel(category) == key ||
          StatisticsUiCopy(AppLocale.en).categoryLabel(category) == key) {
        return category;
      }
    }
    return null;
  }

  Widget _buildAuditPie({
    required Map<TimeEntryCategory, int> secondsByCategory,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final values = secondsByCategory.entries
        .where((entry) => entry.value > 0)
        .toList();
    final total = values.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total == 0) {
      return EmptyHint(
        icon: Icons.schedule,
        message: effectiveCopy.noTimeFootprint,
      );
    }
    PieChartSectionData sec(int v, Color c) => PieChartSectionData(
      value: v.toDouble(),
      color: c,
      radius: 48,
      title: v == 0 ? '' : '${((v / total) * 100).toStringAsFixed(0)}%',
      titleStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.normal,
        fontSize: 11,
      ),
    );
    final chart = PieChart(
      PieChartData(
        centerSpaceRadius: 32,
        sectionsSpace: 2,
        sections: [
          for (final entry in values)
            sec(entry.value, _auditColor(entry.key, cs)),
        ],
      ),
    );
    final legend = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in values.take(5))
          _legend(_auditColor(entry.key, cs), entry.key.label),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320) {
          return Column(
            children: [
              SizedBox(height: 150, child: chart),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in values.take(5))
                    _legend(_auditColor(entry.key, cs), entry.key.label),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: chart),
            SizedBox(width: 104, child: legend),
          ],
        );
      },
    );
  }

  Widget _legend(Color c, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildAuditTimeline(
    List<TimeEntry> entries,
    ColorScheme cs, {
    StatisticsUiCopy? copy,
    VoidCallback? onViewAll,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    if (entries.isEmpty) {
      return EmptyHint(
        icon: Icons.schedule,
        message: effectiveCopy.noTimeEntries,
      );
    }
    final sorted = [...entries]..sort((a, b) => b.startAt.compareTo(a.startAt));
    return Column(
      children: [
        for (final entry in sorted.take(6))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: _auditColor(
                entry.category,
                cs,
              ).withValues(alpha: 0.12),
              child: Icon(
                _auditIcon(entry.category),
                color: _auditColor(entry.category, cs),
                size: 16,
              ),
            ),
            title: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry.category.label} · ${_formatDateTime(entry.startAt)} · '
              '${_formatDuration(entry.durationSeconds, effectiveCopy)}',
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed:
                onViewAll ??
                () {
                  if (!mounted) return;
                  final route = ModalRoute.of(context);
                  if (route != null && !route.isCurrent) return;
                  if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                    AccountLocalDataCleaner.accountDataGeneration,
                  )) {
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimeAuditScreen()),
                  );
                },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(effectiveCopy.viewAll),
          ),
        ),
      ],
    );
  }

  Color _auditColor(TimeEntryCategory category, ColorScheme cs) =>
      switch (category) {
        TimeEntryCategory.focus => DesignTokens.defaultError,
        TimeEntryCategory.todo => cs.primary,
        TimeEntryCategory.habit => DesignTokens.defaultSuccess,
        TimeEntryCategory.goal => cs.tertiary,
        TimeEntryCategory.study => DesignTokens.defaultAccent,
        TimeEntryCategory.work => DesignTokens.defaultWarning,
        TimeEntryCategory.life => cs.secondary,
        TimeEntryCategory.other => cs.onSurfaceVariant,
      };

  IconData _auditIcon(TimeEntryCategory category) => switch (category) {
    TimeEntryCategory.focus => Icons.timer_outlined,
    TimeEntryCategory.todo => Icons.check_circle_outline,
    TimeEntryCategory.habit => Icons.repeat,
    TimeEntryCategory.goal => Icons.flag_outlined,
    TimeEntryCategory.study => Icons.menu_book_outlined,
    TimeEntryCategory.work => Icons.work_outline,
    TimeEntryCategory.life => Icons.favorite_outline,
    TimeEntryCategory.other => Icons.more_horiz,
  };

  String _formatDateTime(DateTime d) => I18nDateFormat.shortDateTime(d);

  String _formatDuration(int seconds, [StatisticsUiCopy? copy]) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    return effectiveCopy.formatDuration(seconds);
  }

  Future<void> _copyReport(
    BuildContext context, {
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required int focusMinutes,
    required int habitDoneInRange,
    required int diaryInRange,
    required int auditTotalMinutes,
    required Map<TimeEntryCategory, int> auditCategorySeconds,
    required List<TimeEntry> auditEntries,
    int? originAccountGeneration,
    ModalRoute<dynamic>? originRoute,
  }) async {
    if (!mounted || !context.mounted) return;
    final originalRoute = originRoute ?? ModalRoute.of(context);
    if (originalRoute != null && !originalRoute.isCurrent) return;
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) return;
    final capturedAccountGeneration =
        originAccountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      capturedAccountGeneration,
    )) {
      return;
    }
    final exportLocale = I18n.current;
    final exportCopy = StatisticsUiCopy(
      exportLocale,
      datePattern: AppDateFormat.readPattern(context),
    );
    final text = _buildReportMarkdown(
      start: start,
      end: end,
      completedTodos: completedTodos,
      focusMinutes: focusMinutes,
      habitDoneInRange: habitDoneInRange,
      diaryInRange: diaryInRange,
      auditTotalMinutes: auditTotalMinutes,
      auditCategorySeconds: auditCategorySeconds,
      auditEntries: auditEntries,
      copy: exportCopy,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || !context.mounted) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      capturedAccountGeneration,
    )) {
      return;
    }
    if (originalRoute != null && !originalRoute.isCurrent) return;
    final postRoute = ModalRoute.of(context);
    if (postRoute != null && !postRoute.isCurrent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) {
            final copy = StatisticsUiCopy(locale);
            return Text(copy.reportCopiedNotice);
          },
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showReportShareCard(
    BuildContext context, {
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required int focusMinutes,
    required int habitDoneInRange,
    required int diaryInRange,
    required int auditTotalMinutes,
    required Map<TimeEntryCategory, int> auditCategorySeconds,
    required List<TimeEntry> auditEntries,
    int? originAccountGeneration,
    ModalRoute<dynamic>? originRoute,
  }) async {
    if (!mounted || !context.mounted) return;
    final originalRoute = originRoute ?? ModalRoute.of(context);
    if (originalRoute != null && !originalRoute.isCurrent) return;
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) return;
    final capturedAccountGeneration =
        originAccountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      capturedAccountGeneration,
    )) {
      return;
    }
    final topCategories =
        auditCategorySeconds.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final themeProvider = context.read<ThemeProvider>();
    await showDialog<void>(
      context: context,
      builder: (_) => ListenableBuilder(
        listenable: themeProvider,
        builder: (context, _) => Theme(
          data: themeProvider.brand.theme,
          child: _ReportShareDialog(
            markdownBuilder: (copy) => _buildReportMarkdown(
              start: start,
              end: end,
              completedTodos: completedTodos,
              focusMinutes: focusMinutes,
              habitDoneInRange: habitDoneInRange,
              diaryInRange: diaryInRange,
              auditTotalMinutes: auditTotalMinutes,
              auditCategorySeconds: auditCategorySeconds,
              auditEntries: auditEntries,
              copy: copy,
            ),
            cardBuilder: (copy) => _ReportShareCard(
              start: start,
              end: end,
              completedTodos: completedTodos.length,
              focusMinutes: focusMinutes,
              habitDoneInRange: habitDoneInRange,
              diaryInRange: diaryInRange,
              auditTotalMinutes: auditTotalMinutes,
              topCategories: topCategories.take(4).toList(),
              copy: copy,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyDigest(
    BuildContext context,
    PeriodReportDigest digest, {
    int? originAccountGeneration,
    ModalRoute<dynamic>? originRoute,
  }) async {
    if (!mounted || !context.mounted) return;
    final originalRoute = originRoute ?? ModalRoute.of(context);
    if (originalRoute != null && !originalRoute.isCurrent) return;
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) return;
    final capturedAccountGeneration =
        originAccountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      capturedAccountGeneration,
    )) {
      return;
    }
    final exportLocale = I18n.current;
    final exportCopy = StatisticsUiCopy(
      exportLocale,
      datePattern: AppDateFormat.readPattern(context),
    );
    final text = _digestMarkdown(digest, exportCopy);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted || !context.mounted) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      capturedAccountGeneration,
    )) {
      return;
    }
    if (originalRoute != null && !originalRoute.isCurrent) return;
    final postRoute = ModalRoute.of(context);
    if (postRoute != null && !postRoute.isCurrent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) {
            final copy = StatisticsUiCopy(locale);
            final presentation = PeriodReportPresentation(
              digest,
              isEnglish: copy.isEn,
            );
            return Text(copy.digestCopiedNotice(presentation.title));
          },
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runDigestAiReview(
    BuildContext context,
    PeriodReportDigest digest, {
    int? originAccountGeneration,
    ModalRoute<dynamic>? originRoute,
  }) async {
    if (!mounted || _aiReportBusy) return;
    final originalRoute = originRoute ?? ModalRoute.of(context);
    if (originalRoute != null && !originalRoute.isCurrent) return;
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null && !currentRoute.isCurrent) return;
    final capturedAccountGeneration =
        originAccountGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      capturedAccountGeneration,
    )) {
      return;
    }
    final capturedLocale = I18n.current;
    final capturedCopy = StatisticsUiCopy(
      capturedLocale,
      datePattern: AppDateFormat.readPattern(context),
    );
    final capturedRange = _range;
    final capturedSeq = ++_aiReportRequestSeq;
    final aiService = context.read<AiService>();

    setState(() {
      _aiReportBusy = true;
      _aiReportError = null;
    });

    final presentation = PeriodReportPresentation(
      digest,
      isEnglish: capturedCopy.isEn,
    );
    final reportMarkdown = _digestMarkdown(digest, capturedCopy);

    bool isCurrentOwnership() {
      if (!mounted) return false;
      if (_aiReportRequestSeq != capturedSeq) return false;
      if (_range != capturedRange) return false;
      if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        capturedAccountGeneration,
      )) {
        return false;
      }
      return true;
    }

    bool isCurrentPeriodValid() {
      if (!isCurrentOwnership()) return false;
      if (originalRoute != null && !originalRoute.isCurrent) return false;
      if (mounted) {
        final curRoute = ModalRoute.of(context);
        if (curRoute != null && !curRoute.isCurrent) return false;
      }
      final now = DateTime.now();
      final (curStart, curEnd) = switch (_range) {
        _Range.week => (
          DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1)),
          now,
        ),
        _Range.month => (DateTime(now.year, now.month, 1), now),
        _Range.year => (DateTime(now.year, 1, 1), now),
      };
      final sameStart =
          digest.report.start.year == curStart.year &&
          digest.report.start.month == curStart.month &&
          digest.report.start.day == curStart.day;
      final sameEnd =
          digest.report.end.year == curEnd.year &&
          digest.report.end.month == curEnd.month &&
          digest.report.end.day == curEnd.day;
      return sameStart && sameEnd;
    }

    try {
      final review = await aiService.personalizedReportReview(
        periodLabel: presentation.title,
        reportMarkdown: reportMarkdown,
        locale: capturedLocale,
      );
      if (!isCurrentPeriodValid()) return;
      setState(() => _aiReportReview = review);
    } on AiException catch (e) {
      if (!isCurrentPeriodValid()) return;
      setState(() => _aiReportError = e.message);
    } catch (e) {
      if (!isCurrentPeriodValid()) return;
      setState(() => _aiReportError = e.toString());
    } finally {
      if (isCurrentOwnership()) {
        setState(() => _aiReportBusy = false);
      }
    }
  }

  String _digestMarkdown(PeriodReportDigest digest, [StatisticsUiCopy? copy]) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final presentation = PeriodReportPresentation(
      digest,
      isEnglish: effectiveCopy.isEn,
    );
    return presentation.toMarkdown(
      formatDate: (dt) => effectiveCopy.formatDate(dt),
      formatCategory: (category) => effectiveCopy.formatCategory(category),
    );
  }

  String _buildReportMarkdown({
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required int focusMinutes,
    required int habitDoneInRange,
    required int diaryInRange,
    required int auditTotalMinutes,
    required Map<TimeEntryCategory, int> auditCategorySeconds,
    required List<TimeEntry> auditEntries,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final categories =
        auditCategorySeconds.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final entries = [...auditEntries]
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final sb = StringBuffer()
      ..writeln(effectiveCopy.markdownReportTitle)
      ..writeln()
      ..writeln(
        '${effectiveCopy.markdownRangePrefix}${effectiveCopy.formatDate(start)} - ${effectiveCopy.formatDate(end)}',
      )
      ..writeln()
      ..writeln(effectiveCopy.markdownOverview)
      ..writeln(
        '- ${effectiveCopy.kpiCompletedTodos}：${effectiveCopy.itemsCount(completedTodos.length)}',
      )
      ..writeln(
        '- ${effectiveCopy.kpiDeepFocus}：${effectiveCopy.minutesCount(focusMinutes)}',
      )
      ..writeln(
        '- ${effectiveCopy.kpiHabitCheckIns}：${effectiveCopy.timesCount(habitDoneInRange)}',
      )
      ..writeln(
        '- ${effectiveCopy.kpiDiary}：${effectiveCopy.diaryEntriesCount(diaryInRange)}',
      )
      ..writeln(
        '- ${effectiveCopy.kpiTimeFootprint}：${effectiveCopy.minutesCount(auditTotalMinutes)}',
      )
      ..writeln();

    if (categories.isNotEmpty) {
      sb
        ..writeln(effectiveCopy.markdownTimeDistribution)
        ..writeln();
      final colon = effectiveCopy.markdownColon;
      for (final entry in categories) {
        sb.writeln(
          '- ${effectiveCopy.categoryLabel(entry.key)}$colon${effectiveCopy.formatDuration(entry.value)}',
        );
      }
      sb.writeln();
    }

    if (entries.isNotEmpty) {
      sb
        ..writeln(effectiveCopy.markdownRecentRecords)
        ..writeln();
      for (final entry in entries.take(8)) {
        sb.writeln(
          '- ${effectiveCopy.formatShortDateTime(entry.startAt)} ${entry.title} · '
          '${effectiveCopy.categoryLabel(entry.category)} · ${effectiveCopy.formatDuration(entry.durationSeconds)}',
        );
      }
      sb.writeln();
    }

    if (completedTodos.isNotEmpty) {
      sb
        ..writeln(effectiveCopy.markdownCompletedTodos)
        ..writeln();
      for (final todo in completedTodos.take(12)) {
        sb.writeln('- [x] ${todo.title}');
      }
      sb.writeln();
    }

    return sb.toString();
  }

  Widget _buildFocusSeries({
    required List<PomodoroSession> sessions,
    required _Range range,
    required DateTime start,
    required DateTime end,
    required ColorScheme cs,
    StatisticsUiCopy? copy,
  }) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final buckets = <String, int>{};
    DateTime cursor = DateTime(start.year, start.month, start.day);
    final endNorm = DateTime(end.year, end.month, end.day);

    if (range == _Range.year) {
      for (int m = 1; m <= DateTime.now().month; m++) {
        buckets[effectiveCopy.monthNumberLabel(m)] = 0;
      }
    } else {
      while (!cursor.isAfter(endNorm)) {
        final k = '${cursor.month}/${cursor.day}';
        buckets[k] = 0;
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    for (final s in sessions) {
      final k = range == _Range.year
          ? effectiveCopy.monthNumberLabel(s.startTime.month)
          : '${s.startTime.month}/${s.startTime.day}';
      buckets[k] = (buckets[k] ?? 0) + (s.durationSeconds ~/ 60);
    }

    if (buckets.values.every((v) => v == 0)) {
      return EmptyHint(
        icon: Icons.timer_outlined,
        message: effectiveCopy.noFocusData,
      );
    }

    final entries = buckets.entries.toList();
    final maxV = buckets.values.isEmpty
        ? 1.0
        : (buckets.values.reduce((a, b) => a > b ? a : b)).toDouble();

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxV * 1.2).clamp(10, double.infinity),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(
                  fontSize: 9,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                if (entries.length > 10 && i % 2 != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.toDouble(),
                  color: cs.primary,
                  width: entries.length > 14 ? 5 : 9,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReportShareDialog extends StatefulWidget {
  final String Function(StatisticsUiCopy copy)? markdownBuilder;
  final Widget? child;
  final Widget Function(StatisticsUiCopy copy)? cardBuilder;

  const _ReportShareDialog({this.markdownBuilder, this.child, this.cardBuilder})
    : assert(
        child != null || cardBuilder != null,
        'Either child or cardBuilder must be provided',
      );

  @override
  State<_ReportShareDialog> createState() => _ReportShareDialogState();
}

class _ReportShareDialogState extends State<_ReportShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  _ReportPdfTemplate _pdfTemplate = _ReportPdfTemplate.visual;
  bool _saving = false;
  late final int _originAccountGeneration;
  ModalRoute<dynamic>? _dialogRoute;
  StatisticsUiCopy? _frozenExportCopy;
  AppLockProvider? _appLock;
  AppUpdateService? _appUpdate;

  @override
  void initState() {
    super.initState();
    _originAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dialogRoute ??= ModalRoute.of(context);
    try {
      _appLock ??= context.read<AppLockProvider?>();
    } catch (_) {}
    try {
      _appUpdate ??= context.read<AppUpdateService?>();
    } catch (_) {}
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool get _isAppAccessAllowed {
    if (_appLock?.isLocked == true) return false;
    if (_appUpdate?.mustUpdate == true) return false;
    return true;
  }

  bool _isOriginValid() {
    if (!mounted) return false;
    if (!_isAppAccessAllowed) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originAccountGeneration,
    )) {
      return false;
    }
    final route = _dialogRoute ?? (mounted ? ModalRoute.of(context) : null);
    if (route != null && !route.isCurrent) {
      return false;
    }
    return true;
  }

  void _onClose() {
    if (_saving || !_isOriginValid()) return;
    final route = _dialogRoute ?? (mounted ? ModalRoute.of(context) : null);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  String _resolvedMarkdown([StatisticsUiCopy? copy]) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    return widget.markdownBuilder?.call(effectiveCopy) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final liveCopy = StatisticsUiCopy.current(
      datePattern: AppDateFormat.patternOf(context),
    );
    final cardCopy = _frozenExportCopy ?? liveCopy;
    return AppDialog(
      title: Text(liveCopy.shareDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              key: _cardKey,
              child: widget.cardBuilder?.call(cardCopy) ?? widget.child!,
            ),
            const SizedBox(height: 14),
            Text(
              liveCopy.pdfTemplate,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_ReportPdfTemplate>(
                segments: [
                  ButtonSegment(
                    value: _ReportPdfTemplate.visual,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: Text(liveCopy.pdfTemplateVisual),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.archive,
                    icon: const Icon(Icons.text_snippet_outlined, size: 16),
                    label: Text(liveCopy.pdfTemplateArchive),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.briefing,
                    icon: const Icon(
                      Icons.dashboard_customize_outlined,
                      size: 16,
                    ),
                    label: Text(liveCopy.pdfTemplateBriefing),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.dashboard,
                    icon: const Icon(Icons.space_dashboard_outlined, size: 16),
                    label: Text(liveCopy.pdfTemplateDashboard),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.timeline,
                    icon: const Icon(Icons.timeline_outlined, size: 16),
                    label: Text(liveCopy.pdfTemplateTimeline),
                  ),
                ],
                selected: {_pdfTemplate},
                onSelectionChanged: _saving
                    ? null
                    : (selected) {
                        if (!mounted || _saving || !_isOriginValid()) return;
                        setState(() => _pdfTemplate = selected.single);
                      },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _onClose,
          child: Text(
            liveCopy.close,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _copyMarkdown,
          icon: const Icon(Icons.copy, size: 16),
          label: Text(liveCopy.copyMarkdownAction),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _savePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: Text(liveCopy.savePdfAction),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _savePng,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined, size: 16),
          label: Text(liveCopy.savePngAction),
        ),
      ],
    );
  }

  Future<void> _copyMarkdown() async {
    if (_saving || !_isOriginValid()) return;
    final exportCopy = StatisticsUiCopy(
      I18n.current,
      datePattern: AppDateFormat.readPattern(context),
    );
    final text = _resolvedMarkdown(exportCopy);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted || !_isOriginValid()) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, locale, _) {
                final copy = StatisticsUiCopy(locale);
                return Text(copy.markdownCopiedNotice);
              },
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted || !_isOriginValid()) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, locale, _) {
                final copy = StatisticsUiCopy(locale);
                return Text(copy.exportFailedRetry);
              },
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _savePng() async {
    if (_saving || !_isOriginValid()) return;
    final exportCopy = StatisticsUiCopy(
      I18n.current,
      datePattern: AppDateFormat.readPattern(context),
    );
    setState(() {
      _saving = true;
      _frozenExportCopy = exportCopy;
    });
    try {
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!completer.isCompleted) completer.complete();
      });
      await Future.any([completer.future, WidgetsBinding.instance.endOfFrame]);
      if (!mounted || !_isOriginValid()) return;

      final bytes = await _captureCardPngBytes();
      if (bytes == null || !_isOriginValid()) return;

      final fileName =
          'duoyi_report_${DateTime.now().millisecondsSinceEpoch}.png';
      if (kIsWeb) {
        final result = await WebFileDownload.saveBytes(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'image/png',
          shareText: _resolvedMarkdown(exportCopy),
          shareSubject: exportCopy.shareSubject,
          canProceed: () => mounted && _isOriginValid(),
        );
        if (!mounted || !_isOriginValid() || !result.saved) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(exportCopy.shareImageSaved(fileName))),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      if (!mounted || !_isOriginValid()) return;

      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted || !_isOriginValid()) return;

      final filePath = file.path;
      await Clipboard.setData(ClipboardData(text: filePath));
      if (!mounted || !_isOriginValid()) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: _resolvedMarkdown(exportCopy),
          subject: exportCopy.shareSubject,
        ),
      );
      if (!mounted || !_isOriginValid()) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) {
              final copy = StatisticsUiCopy(locale);
              return Text(copy.shareImageSaved(filePath));
            },
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted || !_isOriginValid()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) {
              final copy = StatisticsUiCopy(locale);
              return Text(copy.exportFailedRetry);
            },
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _frozenExportCopy = null;
        });
      }
    }
  }

  Future<void> _savePdf() async {
    if (_saving || !_isOriginValid()) return;
    final exportTemplate = _pdfTemplate;
    final exportCopy = StatisticsUiCopy(
      I18n.current,
      datePattern: AppDateFormat.readPattern(context),
    );
    setState(() {
      _saving = true;
      _frozenExportCopy = exportCopy;
    });
    try {
      Uint8List? imageBytes;
      if (exportTemplate == _ReportPdfTemplate.visual) {
        final completer = Completer<void>();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!completer.isCompleted) completer.complete();
        });
        await Future.any([
          completer.future,
          WidgetsBinding.instance.endOfFrame,
        ]);
        if (!mounted || !_isOriginValid()) return;

        imageBytes = await _captureCardPngBytes();
        if (imageBytes == null || !_isOriginValid()) return;
      }

      if (!mounted || !_isOriginValid()) return;

      final doc = await _buildPdfDocument(
        template: exportTemplate,
        imageBytes: imageBytes,
        copy: exportCopy,
      );
      if (!mounted || !_isOriginValid()) return;

      final pdfBytes = await doc.save();
      if (!mounted || !_isOriginValid()) return;

      final fileName =
          'duoyi_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      if (kIsWeb) {
        final result = await WebFileDownload.saveBytes(
          bytes: pdfBytes,
          fileName: fileName,
          mimeType: 'application/pdf',
          shareText: _resolvedMarkdown(exportCopy),
          shareSubject: exportCopy.sharePdfSubject,
          canProceed: () => mounted && _isOriginValid(),
        );
        if (!mounted || !_isOriginValid() || !result.saved) return;
        final templateLabel = _reportPdfTemplateLabel(
          exportTemplate,
          exportCopy,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(exportCopy.sharePdfSaved(templateLabel, fileName)),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      if (!mounted || !_isOriginValid()) return;

      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);
      if (!mounted || !_isOriginValid()) return;

      final filePath = file.path;
      await Clipboard.setData(ClipboardData(text: filePath));
      if (!mounted || !_isOriginValid()) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: _resolvedMarkdown(exportCopy),
          subject: exportCopy.sharePdfSubject,
        ),
      );
      if (!mounted || !_isOriginValid()) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) {
              final copy = StatisticsUiCopy(locale);
              final templateLabel = _reportPdfTemplateLabel(
                exportTemplate,
                copy,
              );
              return Text(copy.sharePdfSaved(templateLabel, filePath));
            },
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted || !_isOriginValid()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) {
              final copy = StatisticsUiCopy(locale);
              return Text(copy.exportFailedRetry);
            },
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _frozenExportCopy = null;
        });
      }
    }
  }

  Future<pw.Document> _buildPdfDocument({
    required _ReportPdfTemplate template,
    Uint8List? imageBytes,
    required StatisticsUiCopy copy,
  }) async {
    final latinFontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    final cjkFontData = await rootBundle.load(
      'assets/fonts/DroidSansFallbackFull.ttf',
    );
    final latinFont = pw.Font.ttf(latinFontData);
    final cjkFont = pw.Font.ttf(cjkFontData);
    final doc = pw.Document(
      title: copy.shareReportTitle,
      author: copy.isEn ? 'Duoyi' : '多仪',
      creator: 'Duoyi',
      subject: '${_reportPdfTemplateLabel(template, copy)} PDF',
      keywords: 'duoyi, productivity, report, markdown, searchable',
      theme: pw.ThemeData.withFont(
        base: latinFont,
        bold: latinFont,
        fontFallback: [cjkFont],
      ),
    );

    if (template == _ReportPdfTemplate.visual && imageBytes != null) {
      final image = pw.MemoryImage(imageBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final brandName = copy.isEn ? 'Duoyi' : '多仪';
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '$brandName · ${_reportPdfTemplateLabel(template, copy)} · ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => switch (template) {
          _ReportPdfTemplate.briefing => _buildBriefingPdfContent(copy),
          _ReportPdfTemplate.dashboard => _buildDashboardPdfContent(copy),
          _ReportPdfTemplate.timeline => _buildTimelinePdfContent(copy),
          _ => _buildSearchablePdfContent(template, copy),
        },
      ),
    );
    return doc;
  }

  List<pw.Widget> _buildBriefingPdfContent(StatisticsUiCopy copy) {
    final markdown = _resolvedMarkdown(copy);
    final title = _markdownTitle(markdown, copy);
    final range =
        _markdownLineStartsWith(markdown, [
          copy.markdownRangePrefix,
          '范围：',
          'Range:',
        ]) ??
        '${copy.markdownRangePrefix} ${copy.unspecifiedRange}';
    final overview = _markdownSectionItems(markdown, [
      copy.markdownOverviewTitle,
      '概览',
      'Overview',
    ]);
    final categories = _markdownSectionItems(markdown, [
      copy.markdownTimeDistributionTitle,
      '时间投入分布',
      'Time Distribution',
    ]).take(4).toList();
    final records = _markdownSectionItems(markdown, [
      copy.markdownRecentRecordsTitle,
      '最近时间记录',
      'Recent Time Entries',
      'Recent Records',
    ]).take(5).toList();
    final todos = _markdownSectionItems(markdown, [
      copy.markdownCompletedTodosTitle,
      '已完成待办',
      'Completed Todos',
    ]).take(6).toList();

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey900,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              copy.pdfTemplateBriefing,
              style: const pw.TextStyle(
                fontSize: 11,
                color: PdfColors.blueGrey100,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 27,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              range,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 18),
      pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in overview)
            pw.Container(
              width: 118,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                item,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
              ),
            ),
        ],
      ),
      pw.SizedBox(height: 18),
      _buildBriefingSection(copy.pdfBriefingTimeFocus, categories, copy),
      pw.SizedBox(height: 12),
      _buildBriefingSection(copy.pdfBriefingRecentRecords, records, copy),
      pw.SizedBox(height: 12),
      _buildBriefingSection(copy.pdfBriefingCompletedItems, todos, copy),
      pw.SizedBox(height: 18),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.amber50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.amber200),
        ),
        child: pw.Text(
          copy.pdfBriefingNotice,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
        ),
      ),
    ];
  }

  pw.Widget _buildBriefingSection(
    String title,
    List<String> items,
    StatisticsUiCopy copy,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.normal),
        ),
        pw.SizedBox(height: 7),
        if (items.isEmpty)
          pw.Text(
            copy.noData,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          )
        else
          for (final item in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
                  pw.Expanded(
                    child: pw.Text(
                      item,
                      style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  List<pw.Widget> _buildDashboardPdfContent(StatisticsUiCopy copy) {
    final markdown = _resolvedMarkdown(copy);
    final title = _markdownTitle(markdown, copy);
    final range =
        _markdownLineStartsWith(markdown, [
          copy.markdownRangePrefix,
          '范围：',
          'Range:',
        ]) ??
        '${copy.markdownRangePrefix} ${copy.unspecifiedRange}';
    final overview = _markdownSectionItems(markdown, [
      copy.markdownOverviewTitle,
      '概览',
      'Overview',
    ]);
    final categories = _markdownSectionItems(markdown, [
      copy.markdownTimeDistributionTitle,
      '时间投入分布',
      'Time Distribution',
    ]).take(5).toList();
    final records = _markdownSectionItems(markdown, [
      copy.markdownRecentRecordsTitle,
      '最近时间记录',
      'Recent Time Entries',
      'Recent Records',
    ]).take(3).toList();
    final todos = _markdownSectionItems(markdown, [
      copy.markdownCompletedTodosTitle,
      '已完成待办',
      'Completed Todos',
    ]).take(4).toList();

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo900,
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              copy.pdfTemplateDashboard,
              style: const pw.TextStyle(
                fontSize: 11,
                color: PdfColors.indigo50,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              range,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 18),
      pw.Text(
        copy.pdfDashboardCoreMetrics,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.normal),
      ),
      pw.SizedBox(height: 8),
      pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < overview.length; i++)
            _buildDashboardMetricCard(overview[i], i),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _buildDashboardPanel(
              copy.pdfDashboardRanking,
              categories.isEmpty
                  ? [_buildPdfMutedText(copy.noTimeInvestmentData)]
                  : [
                      for (var i = 0; i < categories.length; i++)
                        _buildDashboardRankItem(categories[i], i),
                    ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _buildDashboardPanel(copy.pdfDashboardRecentProgress, [
              ...records.map((item) => _buildPdfBullet(item)),
              if (records.isEmpty) _buildPdfMutedText(copy.noTimeEntries),
              pw.SizedBox(height: 8),
              pw.Text(
                copy.pdfBriefingCompletedItems,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
              pw.SizedBox(height: 4),
              ...todos.map((item) => _buildPdfBullet(item)),
              if (todos.isEmpty) _buildPdfMutedText(copy.noCompletedTodos),
            ]),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.indigo100),
        ),
        child: pw.Text(
          copy.pdfDashboardNotice,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.indigo900),
        ),
      ),
    ];
  }

  pw.Widget _buildDashboardMetricCard(String item, int index) {
    final delimiter = item.contains('：') ? '：' : ':';
    final parts = item.split(delimiter);
    final title = parts.first.trim();
    final value = parts.length > 1
        ? parts.sublist(1).join(delimiter).trim()
        : item;
    final colors = [
      PdfColors.indigo50,
      PdfColors.green50,
      PdfColors.amber50,
      PdfColors.pink50,
      PdfColors.cyan50,
    ];
    final borders = [
      PdfColors.indigo200,
      PdfColors.green200,
      PdfColors.amber200,
      PdfColors.pink200,
      PdfColors.cyan200,
    ];
    return pw.Container(
      width: 102,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: colors[index % colors.length],
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: borders[index % borders.length]),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDashboardPanel(String title, List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
          ),
          pw.SizedBox(height: 9),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _buildDashboardRankItem(String item, int index) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 20,
            height: 20,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo900,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              '${index + 1}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
            ),
          ),
          pw.SizedBox(width: 7),
          pw.Expanded(
            child: pw.Text(
              item,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildTimelinePdfContent(StatisticsUiCopy copy) {
    final markdown = _resolvedMarkdown(copy);
    final title = _markdownTitle(markdown, copy);
    final range =
        _markdownLineStartsWith(markdown, [
          copy.markdownRangePrefix,
          '范围：',
          'Range:',
        ]) ??
        '${copy.markdownRangePrefix} ${copy.unspecifiedRange}';
    final overview = _markdownSectionItems(markdown, [
      copy.markdownOverviewTitle,
      '概览',
      'Overview',
    ]);
    final records = _markdownSectionItems(markdown, [
      copy.markdownRecentRecordsTitle,
      '最近时间记录',
      'Recent Time Entries',
      'Recent Records',
    ]).take(8).toList();
    final todos = _markdownSectionItems(markdown, [
      copy.markdownCompletedTodosTitle,
      '已完成待办',
      'Completed Todos',
    ]).take(10).toList();
    final categories = _markdownSectionItems(markdown, [
      copy.markdownTimeDistributionTitle,
      '时间投入分布',
      'Time Distribution',
    ]).take(4).toList();

    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 5, height: 58, color: PdfColors.teal700),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  copy.pdfTemplateTimeline,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.teal700,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 27,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(range, style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in overview)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.teal50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColors.teal100),
              ),
              child: pw.Text(item, style: const pw.TextStyle(fontSize: 9)),
            ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Text(
        copy.pdfTimelineRecentRecords,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.normal),
      ),
      pw.SizedBox(height: 9),
      if (records.isEmpty)
        _buildPdfMutedText(copy.noTimeEntries)
      else
        for (final item in records) _buildTimelineItem(item),
      pw.SizedBox(height: 14),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _buildTimelineSideSection(
              copy.pdfBriefingCompletedItems,
              todos,
              copy,
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _buildTimelineSideSection(
              copy.timeInvestment,
              categories,
              copy,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.teal50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.teal100),
        ),
        child: pw.Text(
          copy.pdfTimelineNotice,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.teal900),
        ),
      ),
    ];
  }

  pw.Widget _buildTimelineItem(String item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            children: [
              pw.Container(
                width: 11,
                height: 11,
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal700,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
              ),
              pw.Container(width: 1, height: 26, color: PdfColors.teal100),
            ],
          ),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                item,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTimelineSideSection(
    String title,
    List<String> items,
    StatisticsUiCopy copy,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.normal),
          ),
          pw.SizedBox(height: 7),
          if (items.isEmpty)
            _buildPdfMutedText(copy.noData)
          else
            ...items.map((item) => _buildPdfBullet(item)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfBullet(String item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(
            child: pw.Text(
              item,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfMutedText(String text) {
    return pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
    );
  }

  List<pw.Widget> _buildSearchablePdfContent(
    _ReportPdfTemplate template,
    StatisticsUiCopy copy,
  ) {
    final lines = _resolvedMarkdown(copy).split('\n');
    final widgets = <pw.Widget>[
      pw.Text(
        template == _ReportPdfTemplate.visual
            ? copy.pdfSearchableLayerTitle
            : copy.shareReportTitle,
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.normal),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        copy.pdfSearchableTemplateLabel(
          _reportPdfTemplateLabel(template, copy),
        ),
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 14),
    ];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
      } else if (line.startsWith('# ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
            child: pw.Text(
              line.substring(2),
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        );
      } else if (line.startsWith('## ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.Text(
              line.substring(3),
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ', style: const pw.TextStyle(fontSize: 11)),
                pw.Expanded(
                  child: pw.Text(
                    line.substring(2),
                    style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              line,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  String _markdownTitle(String markdown, StatisticsUiCopy copy) {
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('# ')) return line.substring(2).trim();
    }
    return copy.shareReportTitle;
  }

  String? _markdownLineStartsWith(String markdown, List<String> prefixes) {
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      for (final prefix in prefixes) {
        if (line.startsWith(prefix)) return line;
      }
    }
    return null;
  }

  List<String> _markdownSectionItems(String markdown, List<String> headings) {
    final result = <String>[];
    var inSection = false;
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('## ')) {
        final headingText = line.substring(3).trim();
        inSection = headings.contains(headingText);
        continue;
      }
      if (!inSection) continue;
      if (line.startsWith('- [x] ')) {
        result.add(line.substring(6).trim());
      } else if (line.startsWith('- ')) {
        result.add(line.substring(2).trim());
      }
    }
    return result;
  }

  String _reportPdfTemplateLabel(
    _ReportPdfTemplate template, [
    StatisticsUiCopy? copy,
  ]) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    return switch (template) {
      _ReportPdfTemplate.visual => effectiveCopy.pdfTemplateVisual,
      _ReportPdfTemplate.archive => effectiveCopy.pdfTemplateArchive,
      _ReportPdfTemplate.briefing => effectiveCopy.pdfTemplateBriefing,
      _ReportPdfTemplate.dashboard => effectiveCopy.pdfTemplateDashboard,
      _ReportPdfTemplate.timeline => effectiveCopy.pdfTemplateTimeline,
    };
  }

  Future<Uint8List?> _captureCardPngBytes() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

class _ReportShareCard extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final int completedTodos;
  final int focusMinutes;
  final int habitDoneInRange;
  final int diaryInRange;
  final int auditTotalMinutes;
  final List<MapEntry<TimeEntryCategory, int>> topCategories;
  final StatisticsUiCopy? copy;

  const _ReportShareCard({
    this.start,
    this.end,
    required this.completedTodos,
    required this.focusMinutes,
    required this.habitDoneInRange,
    required this.diaryInRange,
    required this.auditTotalMinutes,
    required this.topCategories,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final pattern = AppDateFormat.patternOf(context);
    final effectiveCopy =
        copy ?? StatisticsUiCopy.current(datePattern: pattern);
    final cs = Theme.of(context).colorScheme;
    final rangeText = (start != null && end != null)
        ? '${effectiveCopy.formatDate(start!)} - ${effectiveCopy.formatDate(end!)}'
        : effectiveCopy.unspecifiedRange;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            effectiveCopy.shareReportTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.normal,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rangeText,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ShareMetric(
                label: effectiveCopy.todos,
                value: effectiveCopy.itemsCount(completedTodos),
              ),
              _ShareMetric(
                label: effectiveCopy.focus,
                value: effectiveCopy.minutesCount(focusMinutes),
              ),
              _ShareMetric(
                label: effectiveCopy.habits,
                value: effectiveCopy.timesCount(habitDoneInRange),
              ),
              _ShareMetric(
                label: effectiveCopy.kpiDiary,
                value: effectiveCopy.diaryEntriesCount(diaryInRange),
              ),
              _ShareMetric(
                label: effectiveCopy.footprint,
                value: effectiveCopy.minutesCount(auditTotalMinutes),
              ),
            ],
          ),
          if (topCategories.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              effectiveCopy.timeInvestment,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in topCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        effectiveCopy.categoryLabel(entry.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(effectiveCopy.formatDuration(entry.value)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          Text(
            effectiveCopy.generatedByDuoyi,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.44),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ShareMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuadrantStat {
  final String label;
  final String action;
  final String guidance;
  final Color color;
  final IconData icon;
  final int totalCount;
  final int activeCount;
  final int completedCount;
  final int overdueCount;
  final int dueTodayCount;

  const _QuadrantStat({
    required this.label,
    required this.action,
    required this.guidance,
    required this.color,
    required this.icon,
    required this.totalCount,
    required this.activeCount,
    required this.completedCount,
    required this.overdueCount,
    required this.dueTodayCount,
  });

  double shareOf(int total) => total == 0 ? 0 : totalCount / total;
}

class _QuadrantDistributionCard extends StatelessWidget {
  final List<_QuadrantStat> stats;
  final ColorScheme cs;
  final StatisticsUiCopy? copy;

  const _QuadrantDistributionCard({
    required this.stats,
    required this.cs,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final total = stats.fold<int>(0, (sum, stat) => sum + stat.totalCount);
    final activeTotal = stats.fold<int>(
      0,
      (sum, stat) => sum + stat.activeCount,
    );
    final overdueTotal = stats.fold<int>(
      0,
      (sum, stat) => sum + stat.overdueCount,
    );
    final dueTodayTotal = stats.fold<int>(
      0,
      (sum, stat) => sum + stat.dueTodayCount,
    );

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  effectiveCopy.quadrantTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                effectiveCopy.quadrantSubtitle,
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.56),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            effectiveCopy.quadrantDescription,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuadrantMetric(
                label: effectiveCopy.quadrantTotalTasks,
                value: '$total',
                cs: cs,
              ),
              _QuadrantMetric(
                label: effectiveCopy.quadrantActive,
                value: '$activeTotal',
                cs: cs,
              ),
              _QuadrantMetric(
                label: effectiveCopy.quadrantOverdue,
                value: '$overdueTotal',
                cs: cs,
              ),
              _QuadrantMetric(
                label: effectiveCopy.quadrantDueToday,
                value: '$dueTodayTotal',
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Text(
              effectiveCopy.quadrantEmpty,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.58)),
            )
          else
            Column(
              children: [
                for (final stat in stats)
                  _QuadrantDistributionRow(
                    stat: stat,
                    total: total,
                    cs: cs,
                    copy: effectiveCopy,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuadrantMetric extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _QuadrantMetric({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.58),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _QuadrantDistributionRow extends StatelessWidget {
  final _QuadrantStat stat;
  final int total;
  final ColorScheme cs;
  final StatisticsUiCopy? copy;

  const _QuadrantDistributionRow({
    required this.stat,
    required this.total,
    required this.cs,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final ratio = stat.shareOf(total).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: stat.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon, color: stat.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${stat.label} · ${stat.action}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.62),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Stack(
                  children: [
                    Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: stat.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: stat.color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  effectiveCopy.quadrantRowSummary(
                    guidance: stat.guidance,
                    active: stat.activeCount,
                    overdue: stat.overdueCount,
                    dueToday: stat.dueTodayCount,
                    completed: stat.completedCount,
                  ),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.62),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(
              '${stat.totalCount}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final bool reflow;

  const _Kpi({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.reflow = false,
  });

  static double maxTokenWidth(
    String text,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    var maxW = 0.0;
    final tokens = RegExp(
      r'[A-Za-z0-9%+.,−-]+|[^\x00-\x7F]',
    ).allMatches(text).map((m) => m.group(0)!);
    for (final token in tokens) {
      final painter = TextPainter(
        text: TextSpan(text: token, style: style),
        textScaler: textScaler,
        textDirection: textDirection,
      )..layout();
      if (painter.width > maxW) maxW = painter.width;
      painter.dispose();
    }
    return maxW;
  }

  @override
  Widget build(BuildContext context) {
    final style = appSurfaceStyleOf(context);
    final titleColor = appSecondaryDescriptionColor(context);
    final bodyMedium =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final effectiveTitleStyle = bodyMedium.copyWith(
      fontSize: 11,
      color: titleColor,
      fontWeight: FontWeight.normal,
    );
    final effectiveValueStyle = bodyMedium.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final iconBox = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );

    return AppSurfaceCard(
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(
        style?.smallTileRadius ?? DesignTokens.radiusCard,
      ),
      child: reflow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconBox,
                const SizedBox(height: 6),
                Text(title, style: effectiveTitleStyle),
                const SizedBox(height: 2),
                Text(value, style: effectiveValueStyle),
              ],
            )
          : Row(
              children: [
                iconBox,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, style: effectiveTitleStyle),
                      const SizedBox(height: 2),
                      Text(value, style: effectiveValueStyle),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PeriodReportDigestCard extends StatelessWidget {
  final PeriodReportDigest digest;
  final ColorScheme cs;
  final VoidCallback onCopy;
  final bool aiEnabled;
  final bool aiBusy;
  final String? aiReview;
  final String? aiError;
  final VoidCallback onAiReview;
  final VoidCallback onOpenAiHistory;
  final VoidCallback onShareImage;
  final StatisticsUiCopy? copy;

  const _PeriodReportDigestCard({
    required this.digest,
    required this.cs,
    required this.onCopy,
    required this.aiEnabled,
    required this.aiBusy,
    required this.aiReview,
    required this.aiError,
    required this.onAiReview,
    required this.onOpenAiHistory,
    required this.onShareImage,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final presentation = PeriodReportPresentation(
      digest,
      isEnglish: effectiveCopy.isEn,
    );
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.summarize_outlined, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presentation.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      presentation.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _ScoreBadge(score: digest.report.productivityScore, cs: cs),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in presentation.highlights.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(line)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: Text(effectiveCopy.copyReport),
              ),
              TextButton.icon(
                onPressed: aiEnabled && !aiBusy ? onAiReview : null,
                icon: aiBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(effectiveCopy.aiReview),
              ),
              TextButton.icon(
                onPressed: onShareImage,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(effectiveCopy.shareImage),
              ),
              if (aiReview != null)
                TextButton.icon(
                  onPressed: onOpenAiHistory,
                  icon: const Icon(Icons.history, size: 16),
                  label: Text(effectiveCopy.aiHistory),
                ),
            ],
          ),
          if (!aiEnabled) ...[
            const SizedBox(height: 4),
            Text(
              effectiveCopy.aiDisabledMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (aiError != null) ...[
            const SizedBox(height: 8),
            Text(
              aiError!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (aiReview != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        effectiveCopy.aiReviewHeading,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: cs.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    aiReview!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.58),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  final ColorScheme cs;

  const _ScoreBadge({required this.score, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.primary.withValues(alpha: 0.32)),
        color: cs.primary.withValues(alpha: 0.08),
      ),
      child: Text(
        '$score',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}

class _CrossMetricBadge extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _CrossMetricBadge({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ProjectEfficiencyRow extends StatelessWidget {
  final ProjectEfficiencyItem item;
  final double maxOutputPerHour;
  final ColorScheme cs;
  final StatisticsUiCopy? copy;

  const _ProjectEfficiencyRow({
    required this.item,
    required this.maxOutputPerHour,
    required this.cs,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final ratio = maxOutputPerHour <= 0
        ? 0.0
        : (item.outputPerHour / maxOutputPerHour).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.projectLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                effectiveCopy.itemsPerHour(item.outputPerHour),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.primary,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            effectiveCopy.projectEfficiencyItemSummary(
              outputCount: item.outputCount,
              completedTodos: item.completedTodos,
              completedGoalSteps: item.completedGoalSteps,
              timeMinutes: item.timeMinutes,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest.withValues(
                alpha: 0.64,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductivityTrendPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final PeriodReport report;
  final _Range? range;
  final bool isCurrentPeriod;

  const _ProductivityTrendPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.report,
    this.range,
    this.isCurrentPeriod = false,
  });

  int get score => report.productivityScore;
  int get completedTodos => report.todosCompleted;
  int get focusMinutes => report.focusMinutes;
  int get habitCheckIns => report.habitCheckIns;
  int get timeEntryMinutes => report.timeEntryMinutes;

  String displayLabel([StatisticsUiCopy? copy]) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    if (isCurrentPeriod && range != null) {
      return switch (range!) {
        _Range.week => effectiveCopy.rangeWeek,
        _Range.month => effectiveCopy.rangeMonth,
        _Range.year => effectiveCopy.thisYear,
      };
    }
    if (range == _Range.month) {
      return effectiveCopy.monthNumberLabel(start.month);
    }
    return label;
  }

  String dateRangeLabel(StatisticsUiCopy copy) {
    final startText = '${start.month}/${start.day}';
    final endText = '${end.month}/${end.day}';
    if (start.year == end.year) return '$startText-$endText';
    return '${copy.formatDate(start)}-${copy.formatDate(end)}';
  }
}

class _ProductivityTrendCard extends StatelessWidget {
  final List<_ProductivityTrendPoint> points;
  final _Range range;
  final StatisticsUiCopy? copy;
  final VoidCallback? onOpenDetail;

  const _ProductivityTrendCard({
    required this.points,
    required this.range,
    this.copy,
    this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final cs = Theme.of(context).colorScheme;
    final latest = points.isEmpty ? null : points.last;
    final first = points.isEmpty ? null : points.first;
    final best = _bestPoint;
    final averageScore = _averageScore;
    final delta = latest == null || first == null
        ? 0
        : latest.score - first.score;
    final secondaryTextColor = appSecondaryDescriptionColor(context);

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;
          final titleColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                effectiveCopy.productivityTrend,
                style:
                    (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle())
                        .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
              ),
              const SizedBox(height: 2),
              Text(
                _trendSubtitle(effectiveCopy),
                style:
                    (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle())
                        .copyWith(fontSize: 11, color: secondaryTextColor),
              ),
            ],
          );

          final detailIconButton = IconButton(
            tooltip: effectiveCopy.viewTrendDetail,
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: points.isEmpty
                ? null
                : () {
                    if (onOpenDetail != null) {
                      onOpenDetail!();
                      return;
                    }
                    if (!context.mounted) return;
                    final route = ModalRoute.of(context);
                    if (route != null && !route.isCurrent) return;
                    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                      AccountLocalDataCleaner.accountDataGeneration,
                    )) {
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ProductivityTrendDetailScreen(
                          points: points,
                          range: range,
                        ),
                      ),
                    );
                  },
          );

          final textScaler = MediaQuery.textScalerOf(context);
          final textDirection = Directionality.of(context);
          final locale = Localizations.maybeLocaleOf(context);
          final axisStyle =
              (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                  .copyWith(
                    fontSize: 10,
                    height: 1.2,
                    fontWeight: FontWeight.normal,
                    color: secondaryTextColor,
                  );

          double maxYLabelWidth = 0;
          double maxYLabelHeight = 0;
          for (final val in ['0', '25', '50', '75', '100']) {
            final tp = TextPainter(
              text: TextSpan(text: val, style: axisStyle),
              textDirection: textDirection,
              locale: locale,
              textScaler: textScaler,
            )..layout();
            if (tp.width > maxYLabelWidth) maxYLabelWidth = tp.width;
            if (tp.height > maxYLabelHeight) maxYLabelHeight = tp.height;
            tp.dispose();
          }

          double maxBottomWidth = 0;
          double maxBottomHeight = 0;
          for (final point in points) {
            final label = point.displayLabel(effectiveCopy);
            final tp = TextPainter(
              text: TextSpan(text: label, style: axisStyle),
              textDirection: textDirection,
              locale: locale,
              textScaler: textScaler,
            )..layout();
            if (tp.width > maxBottomWidth) maxBottomWidth = tp.width;
            if (tp.height > maxBottomHeight) maxBottomHeight = tp.height;
            tp.dispose();
          }

          final leftReservedSize = math.max(38.0, maxYLabelWidth + 12.0);
          final bottomReservedSize = math.max(32.0, maxBottomHeight + 12.0);
          final minPlotHeight = math.max(140.0, maxYLabelHeight * 7.0 + 32.0);
          final chartHeight = math.max(180.0, minPlotHeight + bottomReservedSize);
          final pointCount = points.isEmpty ? 1 : points.length;
          final minInterval = math.max(72.0, maxBottomWidth * 1.6 + 32.0);
          final minPlotWidth = (pointCount - 1) * minInterval + 32.0;
          final totalChartWidth = leftReservedSize + minPlotWidth + 24.0;
          final chartWidth = math.max(constraints.maxWidth, totalChartWidth);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                titleColumn,
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (latest != null)
                      _TrendSummaryBadge(
                        score: latest.score,
                        delta: delta,
                        copy: effectiveCopy,
                      ),
                    const Spacer(),
                    detailIconButton,
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(child: titleColumn),
                    if (latest != null)
                      _TrendSummaryBadge(
                        score: latest.score,
                        delta: delta,
                        copy: effectiveCopy,
                      ),
                    const SizedBox(width: 8),
                    detailIconButton,
                  ],
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: chartHeight,
                child: points.isEmpty
                    ? EmptyHint(
                        icon: Icons.trending_up,
                        message: effectiveCopy.noTrendData,
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: chartWidth,
                          height: chartHeight,
                          child: _buildChart(
                            context,
                            cs,
                            effectiveCopy,
                            leftReservedSize: leftReservedSize,
                            bottomReservedSize: bottomReservedSize,
                            axisStyle: axisStyle,
                          ),
                        ),
                      ),
              ),
              if (latest != null && best != null) ...[
                const SizedBox(height: 12),
                Text(
                  effectiveCopy.trendInsights,
                  style:
                      (Theme.of(context).textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(
                            fontSize: 12,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.normal,
                          ),
                ),
                const SizedBox(height: 6),
                Text(
                  _insightText(effectiveCopy),
                  style:
                      (Theme.of(context).textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(
                            fontSize: 11,
                            height: 1.45,
                            color: secondaryTextColor,
                          ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TrendHistoryMetric(
                      label: effectiveCopy.historicalBest,
                      value:
                          '${best.displayLabel(effectiveCopy)} · ${effectiveCopy.pointsCount(best.score)}',
                    ),
                    _TrendHistoryMetric(
                      label: effectiveCopy.averageScore,
                      value: effectiveCopy.pointsCount(averageScore),
                    ),
                    _TrendHistoryMetric(
                      label: effectiveCopy.currentRank,
                      value: _rankText(effectiveCopy),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  effectiveCopy.cycleBreakdown,
                  style:
                      (Theme.of(context).textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(
                            fontSize: 12,
                            color: secondaryTextColor,
                            fontWeight: FontWeight.normal,
                          ),
                ),
                const SizedBox(height: 6),
                ...points.reversed.map((point) {
                  final index = points.indexOf(point);
                  final previous = index <= 0 ? null : points[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _TrendDetailTile(
                      point: point,
                      previous: previous,
                      isLatest: point == latest,
                      isBest: point == best,
                      copy: effectiveCopy,
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    ColorScheme cs,
    StatisticsUiCopy copy, {
    double leftReservedSize = 38.0,
    double bottomReservedSize = 32.0,
    TextStyle? axisStyle,
  }) {
    final spots = [
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].score.toDouble()),
    ];
    final effectiveAxisStyle =
        axisStyle ??
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.normal,
          color: appSecondaryDescriptionColor(context),
        );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: leftReservedSize,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                space: 4,
                fitInside: SideTitleFitInsideData.fromTitleMeta(
                  meta,
                  distanceFromEdge: 0,
                ),
                child: Text(
                  value.toInt().toString(),
                  style: effectiveAxisStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: bottomReservedSize,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(
                    meta,
                    distanceFromEdge: 0,
                  ),
                  child: Text(
                    points[index].displayLabel(copy),
                    style: effectiveAxisStyle,
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (items) => [
              for (final item in items)
                LineTooltipItem(
                  '${points[item.x.toInt()].displayLabel(copy)}\n${copy.pointsCount(item.y.toInt())}',
                  TextStyle(color: cs.onInverseSurface, fontSize: 11),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: cs.primary,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 3,
                    color: cs.primary,
                    strokeWidth: 2,
                    strokeColor: cs.surface,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: cs.primary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  String _trendSubtitle(StatisticsUiCopy copy) => switch (range) {
    _Range.week => copy.trendSubtitleWeek,
    _Range.month => copy.trendSubtitleMonth,
    _Range.year => copy.trendSubtitleYear,
  };

  _ProductivityTrendPoint? get _bestPoint {
    if (points.isEmpty) return null;
    var best = points.first;
    for (final point in points.skip(1)) {
      if (point.score > best.score) best = point;
    }
    return best;
  }

  int get _averageScore {
    if (points.isEmpty) return 0;
    final total = points.fold<int>(0, (sum, point) => sum + point.score);
    return (total / points.length).round();
  }

  String _rankText(StatisticsUiCopy copy) {
    if (points.isEmpty) return copy.noData;
    final latest = points.last;
    final higherCount = points
        .where((point) => point.score > latest.score)
        .length;
    return copy.rank(higherCount + 1, points.length);
  }

  String _insightText(StatisticsUiCopy copy) {
    if (points.length < 2) return copy.trendInsightInsufficient;
    final latest = points.last;
    final previous = points[points.length - 2];
    final best = _bestPoint;
    final delta = latest.score - previous.score;
    final average = _averageScore;
    return copy.trendInsightText(
      delta: delta,
      bestLabel: best?.displayLabel(copy),
      bestScore: best?.score,
      average: average,
      latestScore: latest.score,
    );
  }
}

class _ProductivityTrendDetailScreen extends StatefulWidget {
  final List<_ProductivityTrendPoint> points;
  final _Range range;

  const _ProductivityTrendDetailScreen({
    required this.points,
    required this.range,
  });

  @override
  State<_ProductivityTrendDetailScreen> createState() =>
      _ProductivityTrendDetailScreenState();
}

class _ProductivityTrendDetailScreenState
    extends State<_ProductivityTrendDetailScreen> {
  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final copy = StatisticsUiCopy.current(
      datePattern: AppDateFormat.patternOf(context),
    );
    final cs = Theme.of(context).colorScheme;
    final points = widget.points;
    final latest = points.isEmpty ? null : points.last;
    final best = _bestPoint;
    final textScaler = MediaQuery.textScalerOf(context);
    final secondaryTextColor = appSecondaryDescriptionColor(context);
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(copy.trendDetailTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        toolbarHeight: math.max(56.0, textScaler.scale(22.0) + 16.0),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 420;
                final titleColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.trendOverview,
                      style:
                          (Theme.of(context).textTheme.bodyMedium ??
                                  const TextStyle())
                              .copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.normal,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rangeSubtitle(copy),
                      style:
                          (Theme.of(context).textTheme.bodyMedium ??
                                  const TextStyle())
                              .copyWith(
                                fontSize: 11,
                                color: secondaryTextColor,
                              ),
                    ),
                  ],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNarrow) ...[
                      Row(
                        children: [
                          Icon(Icons.insights_outlined, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(child: titleColumn),
                        ],
                      ),
                      if (latest != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _TrendSummaryBadge(
                            score: latest.score,
                            delta: points.length < 2
                                ? 0
                                : latest.score - points.first.score,
                            copy: copy,
                          ),
                        ),
                      ],
                    ] else
                      Row(
                        children: [
                          Icon(Icons.insights_outlined, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(child: titleColumn),
                          if (latest != null)
                            _TrendSummaryBadge(
                              score: latest.score,
                              delta: points.length < 2
                                  ? 0
                                  : latest.score - points.first.score,
                              copy: copy,
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _insightText(copy),
                      style:
                          (Theme.of(context).textTheme.bodyMedium ??
                                  const TextStyle())
                              .copyWith(
                                fontSize: 12,
                                height: 1.45,
                                color: secondaryTextColor,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _TrendHistoryMetric(
                          label: copy.historicalBest,
                          value: best == null
                              ? copy.noData
                              : '${best.displayLabel(copy)} · ${copy.pointsCount(best.score)}',
                        ),
                        _TrendHistoryMetric(
                          label: copy.averageScore,
                          value: copy.pointsCount(_averageScore),
                        ),
                        _TrendHistoryMetric(
                          label: copy.currentRank,
                          value: _rankText(copy),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            copy.periodByPeriodBreakdown,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                  fontSize: 13,
                  color: secondaryTextColor,
                  fontWeight: FontWeight.normal,
                ),
          ),
          const SizedBox(height: 8),
          for (final point in points.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TrendDetailTile(
                point: point,
                previous: _previousPoint(point),
                isLatest: point == latest,
                isBest: point == best,
                copy: copy,
              ),
            ),
        ],
      ),
    );

    if (!isLiquidGlass) {
      return scaffold;
    }

    final hasBrandSurface =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return scaffold;
    }
    return Material(
      color: routeBackground,
      child: BrandBackground(child: scaffold),
    );
  }

  String _rangeSubtitle(StatisticsUiCopy copy) => switch (widget.range) {
    _Range.week => copy.trendSubtitleWeek,
    _Range.month => copy.trendSubtitleMonth,
    _Range.year => copy.trendSubtitleYear,
  };

  _ProductivityTrendPoint? get _bestPoint {
    final points = widget.points;
    if (points.isEmpty) return null;
    var best = points.first;
    for (final point in points.skip(1)) {
      if (point.score > best.score) best = point;
    }
    return best;
  }

  int get _averageScore {
    final points = widget.points;
    if (points.isEmpty) return 0;
    final total = points.fold<int>(0, (sum, point) => sum + point.score);
    return (total / points.length).round();
  }

  String _rankText(StatisticsUiCopy copy) {
    final points = widget.points;
    if (points.isEmpty) return copy.noData;
    final latest = points.last;
    final higherCount = points
        .where((point) => point.score > latest.score)
        .length;
    return copy.rank(higherCount + 1, points.length);
  }

  String _insightText(StatisticsUiCopy copy) {
    final points = widget.points;
    if (points.length < 2) return copy.trendInsightInsufficient;
    final latest = points.last;
    final previous = points[points.length - 2];
    final best = _bestPoint;
    final delta = latest.score - previous.score;
    final average = _averageScore;
    return copy.trendInsightText(
      delta: delta,
      bestLabel: best?.displayLabel(copy),
      bestScore: best?.score,
      average: average,
      latestScore: latest.score,
    );
  }

  _ProductivityTrendPoint? _previousPoint(_ProductivityTrendPoint point) {
    final points = widget.points;
    final index = points.indexOf(point);
    if (index <= 0) return null;
    return points[index - 1];
  }
}

class _TrendDetailTile extends StatelessWidget {
  final _ProductivityTrendPoint point;
  final _ProductivityTrendPoint? previous;
  final bool isLatest;
  final bool isBest;
  final StatisticsUiCopy? copy;

  const _TrendDetailTile({
    required this.point,
    required this.previous,
    required this.isLatest,
    required this.isBest,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final cs = Theme.of(context).colorScheme;
    final secondaryTextColor = appSecondaryDescriptionColor(context);
    final delta = previous == null ? null : point.score - previous!.score;
    final deltaColor = delta == null
        ? secondaryTextColor
        : _trendDeltaColor(context, delta);
    final deltaText = delta == null
        ? effectiveCopy.baseline
        : delta == 0
        ? effectiveCopy.flat
        : '${delta > 0 ? '+' : ''}$delta';
    final scoreColor = isLatest ? _latestScoreColor(context, cs) : cs.onSurface;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLatest
            ? cs.primary.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBest
              ? DesignTokens.defaultWarning.withValues(alpha: 0.46)
              : cs.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420;
          final titleWidget = Text(
            '${point.displayLabel(effectiveCopy)} · ${point.dateRangeLabel(effectiveCopy)}',
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(fontSize: 12, fontWeight: FontWeight.normal),
          );

          final trailingRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isBest)
                AppStatusBadge(
                  label: effectiveCopy.best,
                  color: DesignTokens.defaultWarning,
                )
              else if (isLatest)
                AppStatusBadge(label: effectiveCopy.current, color: cs.primary),
              if (isBest || isLatest) const SizedBox(width: 8),
              Text(
                effectiveCopy.pointsCount(point.score),
                style:
                    (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle())
                        .copyWith(
                          fontSize: 12,
                          color: scoreColor,
                          fontWeight: FontWeight.normal,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
              const SizedBox(width: 6),
              Text(
                deltaText,
                style:
                    (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle())
                        .copyWith(
                          fontSize: 11,
                          color: deltaColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                titleWidget,
                const SizedBox(height: 6),
                trailingRow,
              ] else
                Row(
                  children: [
                    Expanded(child: titleWidget),
                    const SizedBox(width: 8),
                    trailingRow,
                  ],
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TrendDetailMetric(
                    label: effectiveCopy.todos,
                    value: effectiveCopy.itemsCount(point.completedTodos),
                  ),
                  _TrendDetailMetric(
                    label: effectiveCopy.focus,
                    value: effectiveCopy.minutesCount(point.focusMinutes),
                  ),
                  _TrendDetailMetric(
                    label: effectiveCopy.habits,
                    value: effectiveCopy.timesCount(point.habitCheckIns),
                  ),
                  _TrendDetailMetric(
                    label: effectiveCopy.footprint,
                    value: effectiveCopy.minutesCount(point.timeEntryMinutes),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Color _latestScoreColor(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass =
        surfaceStyle != null && (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;

    final tileBg = cs.primary.withValues(alpha: 0.08);
    final baseSurface = isLiquidGlass
        ? Color.alphaBlend(tileBg, theme.scaffoldBackgroundColor)
        : Color.alphaBlend(tileBg, cs.surface);

    final preferred = cs.primary;
    final targetContrast = isDark ? 4.5 : 5.2;
    if (appContrastRatio(baseSurface, preferred) >= targetContrast) {
      return preferred;
    }
    final target = isDark ? Colors.white : const Color(0xFF111827);
    for (var t = 0.05; t <= 0.60; t += 0.05) {
      final candidate = Color.lerp(preferred, target, t)!;
      if (appContrastRatio(baseSurface, candidate) >= targetContrast) {
        return candidate;
      }
    }
    return appReadableForeground(baseSurface, preferred);
  }
}

class _TrendDetailMetric extends StatelessWidget {
  final String label;
  final String value;

  const _TrendDetailMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secondaryTextColor = appSecondaryDescriptionColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(fontSize: 10, color: secondaryTextColor),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                  fontSize: 11,
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _TrendSummaryBadge extends StatelessWidget {
  final int score;
  final int delta;
  final StatisticsUiCopy? copy;

  const _TrendSummaryBadge({
    required this.score,
    required this.delta,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final color = _trendDeltaColor(context, delta);
    final label = delta == 0
        ? effectiveCopy.flat
        : '${delta > 0 ? '+' : ''}$delta';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            effectiveCopy.pointsCount(score),
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                  fontSize: 11,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _TrendHistoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _TrendHistoryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secondaryTextColor = appSecondaryDescriptionColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(fontSize: 10, color: secondaryTextColor),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _ProductivityComparisonCard extends StatelessWidget {
  final ReportComparison comparison;
  final _Range range;
  final ColorScheme cs;
  final StatisticsUiCopy? copy;

  const _ProductivityComparisonCard({
    required this.comparison,
    required this.range,
    required this.cs,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    final score = comparison.productivityScore;
    final trendColor = _trendColor(context, score.direction);
    final trendIcon = _trendIcon(score.direction);
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final textScaler = MediaQuery.textScalerOf(context);
          final textDirection = Directionality.of(context);

          final bodyMedium =
              Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
          final scoreStyle = bodyMedium.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final effStyle = bodyMedium.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.normal,
          );
          final valueStyle = bodyMedium.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final smallStyle = bodyMedium.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final badgeStyle = bodyMedium.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: trendColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final titleStyle = bodyMedium.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.normal,
          );
          final subTitleStyle = bodyMedium.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: appSecondaryDescriptionColor(context),
          );

          final scorePainter = TextPainter(
            text: TextSpan(
              text: comparison.current.productivityScore.toString(),
              style: scoreStyle,
            ),
            textScaler: textScaler,
            textDirection: textDirection,
          )..layout();

          final effPainter = TextPainter(
            text: TextSpan(
              text: effectiveCopy.efficiencyScore,
              style: effStyle,
            ),
            textScaler: textScaler,
            textDirection: textDirection,
          )..layout();

          final effTokenWidth = _Kpi.maxTokenWidth(
            effectiveCopy.efficiencyScore,
            effStyle,
            textScaler,
            textDirection,
          );

          final actualScoreWidth = math.max(
            76.0,
            math.max(
                  scorePainter.width,
                  math.max(effPainter.width, effTokenWidth),
                ) +
                24.0,
          );
          final actualScoreHeight = math.max(
            76.0,
            scorePainter.height + effPainter.height + 20.0,
          );
          final actualScoreSize = math.max(actualScoreWidth, actualScoreHeight);
          scorePainter.dispose();
          effPainter.dispose();

          final metricItems = [
            (
              label: effectiveCopy.completionRate,
              value: _percent(comparison.current.todoCompletionRate),
              delta: _percentagePointDelta(
                comparison.todoCompletionRate,
                effectiveCopy,
              ),
              direction: comparison.todoCompletionRate.direction,
            ),
            (
              label: effectiveCopy.focus,
              value: effectiveCopy.minutesCount(
                comparison.current.focusMinutes,
              ),
              delta: _signedNumber(
                comparison.focusMinutes.difference,
                suffix: effectiveCopy.minutesSuffix,
                copy: effectiveCopy,
              ),
              direction: comparison.focusMinutes.direction,
            ),
            (
              label: effectiveCopy.habits,
              value: effectiveCopy.timesCount(comparison.current.habitCheckIns),
              delta: _signedNumber(
                comparison.habitCheckIns.difference,
                suffix: effectiveCopy.timesSuffix,
                copy: effectiveCopy,
              ),
              direction: comparison.habitCheckIns.direction,
            ),
            (
              label: effectiveCopy.footprint,
              value: effectiveCopy.minutesCount(
                comparison.current.timeEntryMinutes,
              ),
              delta: _signedNumber(
                comparison.timeEntryMinutes.difference,
                suffix: effectiveCopy.minutesSuffix,
                copy: effectiveCopy,
              ),
              direction: comparison.timeEntryMinutes.direction,
            ),
          ];

          var maxMetricToken = 0.0;
          for (final m in metricItems) {
            final wVal = _Kpi.maxTokenWidth(
              m.value,
              valueStyle,
              textScaler,
              textDirection,
            );
            final wLab = _Kpi.maxTokenWidth(
              m.label,
              smallStyle,
              textScaler,
              textDirection,
            );
            final wDel = _Kpi.maxTokenWidth(
              m.delta,
              smallStyle,
              textScaler,
              textDirection,
            );
            final mMax = math.max(wVal, math.max(wLab, wDel));
            if (mMax > maxMetricToken) maxMetricToken = mMax;
          }

          final minTileWidth = maxMetricToken + 20.0;
          final sideBySideNeeded =
              actualScoreSize + 12.0 + 2 * minTileWidth + 8.0;
          final isSideBySide = width >= sideBySideNeeded;
          final reflow = !isSideBySide;

          final scoreWidget = Container(
            width: isSideBySide ? actualScoreSize : actualScoreWidth,
            height: isSideBySide ? actualScoreSize : actualScoreHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: isSideBySide ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isSideBySide ? null : BorderRadius.circular(16),
              color: cs.primary.withValues(alpha: 0.1),
              border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  comparison.current.productivityScore.toString(),
                  style: scoreStyle.copyWith(color: cs.primary),
                ),
                Text(
                  effectiveCopy.efficiencyScore,
                  style: effStyle.copyWith(
                    color: appSecondaryDescriptionColor(context),
                  ),
                ),
              ],
            ),
          );

          final tileAreaWidth = isSideBySide
              ? width - actualScoreSize - 12.0
              : width;
          final tileColumns = isSideBySide
              ? (tileAreaWidth >= 4 * minTileWidth + 24.0 ? 4 : 2)
              : (tileAreaWidth >= 2 * minTileWidth + 8.0 ? 2 : 1);
          final tileWidth =
              (tileAreaWidth - (tileColumns - 1) * 8.0) / tileColumns;

          final metricsList = [
            for (final m in metricItems)
              _ComparisonMetric(
                label: m.label,
                value: m.value,
                delta: m.delta,
                direction: m.direction,
                width: tileWidth,
              ),
          ];

          final badgeWidget = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon, size: 16, color: trendColor),
                const SizedBox(width: 4),
                Text(
                  _signedNumber(
                    score.difference,
                    suffix: effectiveCopy.pointsSuffix,
                    copy: effectiveCopy,
                  ),
                  style: badgeStyle,
                ),
              ],
            ),
          );

          final titleColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(effectiveCopy.productivityComparison, style: titleStyle),
              const SizedBox(height: 2),
              Text(_rangeCompareLabel(effectiveCopy), style: subTitleStyle),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reflow) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleColumn,
                    const SizedBox(height: 8),
                    badgeWidget,
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: titleColumn),
                    badgeWidget,
                  ],
                ),
              ],
              const SizedBox(height: 14),
              if (isSideBySide)
                Row(
                  children: [
                    scoreWidget,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: metricsList,
                      ),
                    ),
                  ],
                )
              else ...[
                Center(child: scoreWidget),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: metricsList),
              ],
              if (score.hasBaseline) ...[
                const SizedBox(height: 10),
                Text(
                  '${effectiveCopy.vsPreviousPeriod} ${_signedPercent(score.percentChangeRounded ?? 0, copy: effectiveCopy)}',
                  style: subTitleStyle,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _rangeCompareLabel(StatisticsUiCopy copy) => switch (range) {
    _Range.week => copy.rangeCompareLabelWeek,
    _Range.month => copy.rangeCompareLabelCycle,
    _Range.year => copy.rangeCompareLabelCycle,
  };

  Color _trendColor(BuildContext context, ReportTrendDirection direction) =>
      switch (direction) {
        ReportTrendDirection.up => _trendDeltaColor(context, 1),
        ReportTrendDirection.down => _trendDeltaColor(context, -1),
        ReportTrendDirection.flat => appSecondaryDescriptionColor(context),
      };

  IconData _trendIcon(ReportTrendDirection direction) => switch (direction) {
    ReportTrendDirection.up => Icons.trending_up,
    ReportTrendDirection.down => Icons.trending_down,
    ReportTrendDirection.flat => Icons.trending_flat,
  };

  String _percent(double value) => '${(value * 100).round()}%';

  String _percentagePointDelta(ReportMetricDelta delta, StatisticsUiCopy copy) {
    final points = (delta.difference * 100).round();
    return _signedInt(points, suffix: copy.percentagePointsSuffix, copy: copy);
  }

  String _signedNumber(
    double value, {
    required String suffix,
    required StatisticsUiCopy copy,
  }) {
    if (value == 0) return copy.flat;
    return _signedInt(value.round(), suffix: suffix, copy: copy);
  }

  String _signedPercent(int value, {required StatisticsUiCopy copy}) =>
      _signedInt(value, suffix: '%', copy: copy);

  String _signedInt(
    int value, {
    required String suffix,
    required StatisticsUiCopy copy,
  }) {
    if (value == 0) return copy.flat;
    return '${value > 0 ? '+' : ''}$value$suffix';
  }
}

class _ComparisonMetric extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final ReportTrendDirection direction;
  final double? width;

  const _ComparisonMetric({
    required this.label,
    required this.value,
    required this.delta,
    required this.direction,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (direction) {
      ReportTrendDirection.up => _trendDeltaColor(context, 1),
      ReportTrendDirection.down => _trendDeltaColor(context, -1),
      ReportTrendDirection.flat => appSecondaryDescriptionColor(context),
    };
    final bodyMedium =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final valueStyle = bodyMedium.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final smallStyle = bodyMedium.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: valueStyle),
          const SizedBox(height: 2),
          Text(
            label,
            style: smallStyle.copyWith(
              color: appSecondaryDescriptionColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(delta, style: smallStyle.copyWith(color: color)),
        ],
      ),
    );
    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return SizedBox(width: 96, child: content);
  }
}

// ---------------------------------------------------------------------------
// Weekly Time Overview card  (M4 Time Audit integration)
// ---------------------------------------------------------------------------

class _WeeklyTimeOverview extends StatelessWidget {
  final int weekTotalSeconds;
  final Map<String, int> sourceSeconds;
  final Map<String, int> daySeconds;
  final DateTime weekMonday;
  final ColorScheme cs;
  final StatisticsUiCopy? copy;

  const _WeeklyTimeOverview({
    required this.weekTotalSeconds,
    required this.sourceSeconds,
    required this.daySeconds,
    required this.weekMonday,
    required this.cs,
    this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveCopy = copy ?? StatisticsUiCopy.current();
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            effectiveCopy.weeklyTimeOverview,
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
          const SizedBox(height: 10),
          // Headline total
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.access_time_filled_outlined,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effectiveCopy.formatDuration(weekTotalSeconds),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.normal,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    effectiveCopy.weeklyTotalInvested,
                    style: TextStyle(
                      fontSize: 11,
                      color: appSecondaryDescriptionColor(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Source breakdown pie
          if (weekTotalSeconds > 0) ...[
            SizedBox(
              height: 160,
              child: _buildSourcePie(context, effectiveCopy),
            ),
            const SizedBox(height: 10),
          ],
          // Daily bar trend
          SizedBox(height: 120, child: _buildDailyBars(context, effectiveCopy)),
        ],
      ),
    );
  }

  Widget _buildSourcePie(BuildContext context, StatisticsUiCopy copy) {
    final nonZero = sourceSeconds.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (nonZero.isEmpty) {
      return EmptyHint(icon: Icons.inbox_outlined, message: copy.noData);
    }
    final total = nonZero.fold<int>(0, (s, e) => s + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 28,
              sectionsSpace: 2,
              sections: [
                for (final entry in nonZero)
                  PieChartSectionData(
                    value: entry.value.toDouble(),
                    color: _sourceColor(entry.key, cs),
                    radius: 40,
                    title: total == 0
                        ? ''
                        : '${((entry.value / total) * 100).toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.normal,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in nonZero.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _sourceColor(entry.key, cs),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          copy.sourceLabel(entry.key),
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDailyBars(BuildContext context, StatisticsUiCopy copy) {
    final dayLabels = copy.weekdayLabels;
    final buckets = <String, int>{};
    for (int i = 0; i < 7; i++) {
      final d = weekMonday.add(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      buckets[dayLabels[i]] = daySeconds[key] ?? 0;
    }

    final maxV = buckets.values.fold<int>(0, (a, b) => a > b ? a : b);
    if (maxV == 0) {
      return EmptyHint(icon: Icons.date_range, message: copy.noWeeklyData);
    }

    final entries = buckets.entries.toList();
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxV / 60 * 1.2).clamp(1, double.infinity),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(
                  fontSize: 9,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value / 60,
                  color: cs.primary,
                  width: 12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Color _sourceColor(String label, ColorScheme cs) => switch (label) {
    '番茄钟' || 'Pomodoro' => DesignTokens.defaultError,
    '待办' || 'Task' => cs.primary,
    '习惯' || 'Habit' => DesignTokens.defaultSuccess,
    '目标' || 'Goal' => cs.tertiary,
    '手动' || 'Manual' => cs.onSurfaceVariant,
    _ => cs.onSurfaceVariant,
  };
}

Color _trendDeltaColor(BuildContext context, int delta) {
  if (delta == 0) return appSecondaryDescriptionColor(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base =
      delta > 0 ? DesignTokens.defaultSuccess : DesignTokens.defaultError;
  return isDark
      ? Color.lerp(base, Colors.white, 0.35)!
      : Color.lerp(base, const Color(0xFF111827), 0.25)!;
}
