import 'dart:convert' show utf8;

import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';
import 'package:file_selector/file_selector.dart';

import '../core/course_schedule_ui_copy.dart';
import '../widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';
import '../models/course_schedule.dart';
import '../providers/course_provider.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../core/design_tokens.dart' show AppSurfaceStyle;
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

const _weekdayKeys = [
  'weekday.mon',
  'weekday.tue',
  'weekday.wed',
  'weekday.thu',
  'weekday.fri',
  'weekday.sat',
  'weekday.sun',
];

Future<void> showCourseEditor(BuildContext context, {CourseItem? course}) {
  final provider = context.read<CourseProvider>();
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _CourseEditSheet(provider: provider, course: course),
  );
}

class CourseScheduleScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String? initialCourseId;
  final bool openInitialCourseSheet;

  const CourseScheduleScreen({
    super.key,
    this.initialCourseId,
    this.openInitialCourseSheet = true,
  });

  @override
  State<CourseScheduleScreen> createState() => _CourseScheduleScreenState();
}

class _CourseScheduleScreenState extends State<CourseScheduleScreen> {
  bool _openedInitialCourse = false;
  String? _highlightedCourseId;

  @override
  void initState() {
    super.initState();
    _highlightedCourseId = widget.initialCourseId;
    I18n.localeListenable.addListener(_handleLocaleChanged);
  }

  @override
  void didUpdateWidget(covariant CourseScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCourseId != widget.initialCourseId ||
        oldWidget.openInitialCourseSheet != widget.openInitialCourseSheet) {
      _openedInitialCourse = false;
      _highlightedCourseId = widget.initialCourseId;
      _openInitialCourseIfNeeded();
    }
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _openInitialCourseIfNeeded();
  }

  void _openInitialCourseIfNeeded() {
    final id = widget.initialCourseId;
    if (_openedInitialCourse || id == null || id.isEmpty) return;
    _openedInitialCourse = true;
    _highlightedCourseId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CourseProvider>();
      final matches = provider.courses.where((course) => course.id == id);
      if (matches.isEmpty) return;
      final course = matches.first;
      if (course.weeks.isNotEmpty) {
        provider.setViewingWeek(course.weeks.first);
      }
      if (widget.openInitialCourseSheet) {
        showCourseEditor(context, course: course);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseProvider>();
    final settings = provider.settings;
    final week = provider.viewingWeek;
    final courses = provider.coursesOfWeek(week);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScaler = MediaQuery.textScalerOf(context);

    final currentTitle = _courseWeekLabel(week);
    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final titlePainter = TextPainter(
      text: TextSpan(text: currentTitle, style: titleStyle),
      textDirection: Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final titleWidth = titlePainter.width + 26.0;
    titlePainter.dispose();

    // Five padded IconButtons (5 * 48 = 240) + leading BackButton (56) +
    // NavigationToolbar spacing (32) + slack (12) = 340.
    final availableSingleLineWidth = screenWidth - 340.0;
    final compactToolbar = screenWidth <= 360;
    final needsStackedToolbar =
        compactToolbar || (titleWidth > availableSingleLineWidth);

    final toolbarActions = [
      IconButton(
        icon: const Icon(Icons.chevron_left),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        onPressed: () => provider.setViewingWeek(week - 1),
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        onPressed: () => provider.setViewingWeek(week + 1),
      ),
      IconButton(
        icon: const Icon(Icons.today),
        tooltip: I18n.tr('course.week.current_tooltip'),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        onPressed: () => provider.setViewingWeek(provider.currentWeek),
      ),
      IconButton(
        key: const ValueKey('course_import_timetable_btn'),
        icon: const Icon(Icons.file_upload_outlined),
        tooltip: CourseScheduleUiCopy.importTooltip,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        onPressed: () => _showImportDialog(context, provider),
      ),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        onPressed: () => _editSettings(context, provider),
      ),
    ];

    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        title: GestureDetector(
          onTap: () => _pickWeek(context, provider),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _courseWeekLabel(week),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
        actions: needsStackedToolbar ? null : toolbarActions,
        bottom: needsStackedToolbar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ...toolbarActions,
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: provider.courses.isEmpty
          ? EmptyState(
              icon: Icons.school_outlined,
              message: I18n.tr('course.empty.message'),
              actionLabel: I18n.tr('course.add'),
              onAction: () => _addCourse(context),
            )
          : _ScheduleGrid(
              settings: settings,
              courses: courses,
              week: week,
              highlightedCourseId: _highlightedCourseId,
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'course_add_fab',
        onPressed: () => _addCourse(context),
        child: const Icon(Icons.add),
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

  void _pickWeek(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => AppModalSheet(
          title: I18n.tr('course.week_picker.title'),
          subtitle: I18n.tr('course.week_picker.subtitle'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final textScaler = MediaQuery.textScalerOf(context);
              final btnTextStyle =
                  Theme.of(context).textTheme.labelLarge ??
                  const TextStyle(fontSize: 14);
              final textDirection = Directionality.of(context);

              double maxBtnWidth = 0;
              double maxBtnHeight = 0;
              for (var i = 1; i <= p.settings.totalWeeks; i++) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: _courseWeekLabel(i),
                    style: btnTextStyle,
                  ),
                  textDirection: textDirection,
                  textScaler: textScaler,
                  maxLines: 1,
                )..layout();
                if (painter.width > maxBtnWidth) maxBtnWidth = painter.width;
                if (painter.height > maxBtnHeight) {
                  maxBtnHeight = painter.height;
                }
                painter.dispose();
              }

              final minItemWidth = maxBtnWidth + 16.0;
              const spacing = 8.0;
              final crossAxisCount =
                  ((width + spacing) / (minItemWidth + spacing))
                      .floor()
                      .clamp(1, 5);
              final calculatedHeight = maxBtnHeight + 18.0;
              final itemHeight =
                  calculatedHeight > 36.0 ? calculatedHeight : 36.0;
              return GridView.builder(
                key: const ValueKey('course_week_picker_adaptive_grid'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: itemHeight,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: p.settings.totalWeeks,
                itemBuilder: (context, i) {
                  final w = i + 1;
                  final cs = Theme.of(context).colorScheme;
                  final current = w == p.currentWeek;
                  final selected = w == p.viewingWeek;
                  final selectedBackground = Color.alphaBlend(
                    cs.primary.withValues(alpha: 0.09),
                    cs.surface,
                  );
                  return OutlinedButton(
                    onPressed: () {
                      p.setViewingWeek(w);
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: selected
                          ? selectedBackground
                          : (current ? cs.primary.withValues(alpha: 0.1) : null),
                      foregroundColor: selected ? cs.onSurface : null,
                      side: BorderSide(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.32)
                            : cs.outlineVariant.withValues(alpha: 0.24),
                        width: 0.45,
                      ),
                    ),
                    child: Text(
                      _courseWeekLabel(w),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _editSettings(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => _ScheduleSettingsSheet(provider: p),
    );
  }

  void _showImportDialog(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => _CourseImportSheet(provider: p),
    );
  }

  void _addCourse(BuildContext context) => showCourseEditor(context);
}

class _ScheduleGrid extends StatelessWidget {
  final ScheduleSettings settings;
  final List<CourseItem> courses;
  final int week;
  final String? highlightedCourseId;

  const _ScheduleGrid({
    required this.settings,
    required this.courses,
    required this.week,
    this.highlightedCourseId,
  });

  @override
  Widget build(BuildContext context) {
    final monday = settings.termStart.add(Duration(days: (week - 1) * 7));
    final today = DateTime.now();

    const timeW = 34.0;
    const baseMinDayW = 64.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final defaultStyle = DefaultTextStyle.of(context).style;
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final scaffoldBg = theme.scaffoldBackgroundColor;

        final weekdayStyle = defaultStyle.merge(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
        );
        final dateStyle = defaultStyle.merge(const TextStyle(fontSize: 11));
        final periodStyle = defaultStyle.merge(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
        );
        final timeStyle = defaultStyle.merge(
          const TextStyle(
            fontSize: 9,
            height: 1.05,
            fontWeight: FontWeight.normal,
          ),
        );
        final titleStyle = defaultStyle.merge(
          const TextStyle(
            fontSize: 12,
            height: 1.08,
            fontWeight: FontWeight.normal,
          ),
        );

        double maxWeekdayH = 0;
        double maxWeekdayW = 0;
        for (var i = 1; i <= 7; i++) {
          final p = TextPainter(
            text: TextSpan(text: _weekdayLabel(i), style: weekdayStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          if (p.height > maxWeekdayH) maxWeekdayH = p.height;
          if (p.width > maxWeekdayW) maxWeekdayW = p.width;
          p.dispose();
        }

        final sampleDate = monday.add(const Duration(days: 6));
        final dateSampleStr = '${sampleDate.month}/${sampleDate.day}';
        final dateP = TextPainter(
          text: TextSpan(
            text: dateSampleStr.length < 5 ? '12/31' : dateSampleStr,
            style: dateStyle,
          ),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        final dateH = dateP.height;
        final dateW = dateP.width;
        dateP.dispose();

        final measuredHeaderH = maxWeekdayH + dateH + 8.0;
        final headerH = measuredHeaderH > 48.0 ? measuredHeaderH : 48.0;

        final periodP = TextPainter(
          text: TextSpan(text: '12', style: periodStyle),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        final periodH = periodP.height;
        periodP.dispose();

        final sampleTimeP = TextPainter(
          text: TextSpan(text: '00:00-00:00', style: timeStyle),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        double maxTimeW = sampleTimeP.width;
        final sampleTimeH = sampleTimeP.height;
        sampleTimeP.dispose();

        for (final c in courses) {
          final timeLabel = settings.sectionTimeRangeLabel(
            c.startSection,
            c.sectionCount,
          );
          final p = TextPainter(
            text: TextSpan(text: timeLabel, style: timeStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          if (p.width > maxTimeW) maxTimeW = p.width;
          p.dispose();
        }

        final sampleTitleP = TextPainter(
          text: TextSpan(text: 'Art', style: titleStyle),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        final sampleTitleH = sampleTitleP.height;
        sampleTitleP.dispose();

        final maxTitleBound = 12.0 * 12.0 * textScaler.scale(1.0);
        double maxTitleW = 0;
        for (final c in courses) {
          if (c.name.isEmpty) continue;
          final p = TextPainter(
            text: TextSpan(text: c.name, style: titleStyle),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final boundedW = p.width > maxTitleBound ? maxTitleBound : p.width;
          if (boundedW > maxTitleW) maxTitleW = boundedW;
          p.dispose();
        }

        final minSectionHForCard =
            (sampleTimeH + 2.0 + sampleTitleH + 12.0 + 6.0).ceilToDouble();
        final minSectionHForPeriod = (periodH + 8.0).ceilToDouble();
        final minSectionH = minSectionHForCard > minSectionHForPeriod
            ? minSectionHForCard
            : minSectionHForPeriod;
        final sectionH = minSectionH > 56.0 ? minSectionH : 56.0;

        final maxHeaderW = maxWeekdayW > dateW ? maxWeekdayW : dateW;
        final headerRequiredDayW = maxHeaderW + 8.0;
        final maxCardContentW = maxTimeW > maxTitleW ? maxTimeW : maxTitleW;
        final cardRequiredDayW = maxCardContentW + 18.0;
        final maxContentDayW = cardRequiredDayW > headerRequiredDayW
            ? cardRequiredDayW
            : headerRequiredDayW;
        final minDayW =
            maxContentDayW > baseMinDayW ? maxContentDayW : baseMinDayW;

        final minGridW = timeW + minDayW * 7;
        final gridW = availableW > minGridW ? availableW : minGridW;
        final bodyW = gridW - timeW;
        final cellW = bodyW / 7;

        final naturalCellW = (availableW - timeW) / 7;
        final isCompact = (naturalCellW - 4.0) < 76.0;

        final isDark = theme.brightness == Brightness.dark;
        final gridLineColor = cs.outlineVariant.withValues(
          alpha: isDark ? 0.22 : 0.45,
        );
        final nonTodayDateColor = appReadableForeground(
          scaffoldBg,
          cs.onSurfaceVariant,
        );
        final periodColor = appReadableForeground(
          scaffoldBg,
          cs.onSurfaceVariant,
        );

        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              key: const ValueKey('course_schedule_adaptive_grid'),
              width: gridW,
              child: Column(
                children: [
                  // 顶栏：周几 + 日期
                  Row(
                    children: [
                      SizedBox(width: timeW, height: headerH),
                      ...List.generate(7, (i) {
                        final d = monday.add(Duration(days: i));
                        final isToday =
                            d.year == today.year &&
                            d.month == today.month &&
                            d.day == today.day;
                        return Expanded(
                          child: Container(
                            height: headerH,
                            alignment: Alignment.center,
                            color: isToday
                                ? cs.primary.withValues(alpha: 0.08)
                                : null,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _weekdayLabel(i + 1),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isToday ? cs.primary : null,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${d.month}/${d.day}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isToday
                                        ? cs.primary
                                        : nonTodayDateColor,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  Divider(height: 1, color: gridLineColor),
                  // 主体：节数 × 星期
                  SizedBox(
                    height: sectionH * settings.sessionsPerDay,
                    child: Stack(
                      children: [
                        // 背景：节次+格线
                        Row(
                          children: [
                            // 节次列
                            SizedBox(
                              width: timeW,
                              child: Column(
                                children: List.generate(
                                  settings.sessionsPerDay,
                                  (i) => Container(
                                    height: sectionH,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: gridLineColor,
                                          width: 0.6,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: periodColor,
                                        fontWeight: FontWeight.normal,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // 日格
                            ...List.generate(7, (col) {
                              return Expanded(
                                child: Column(
                                  children: List.generate(
                                    settings.sessionsPerDay,
                                    (row) => Container(
                                      height: sectionH,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: gridLineColor,
                                            width: 0.6,
                                          ),
                                          bottom: BorderSide(
                                            color: gridLineColor,
                                            width: 0.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        // 课程块
                        ...courses.map((c) {
                          final col = c.weekday - 1;
                          final row = c.startSection - 1;
                          if (row < 0 || row >= settings.sessionsPerDay) {
                            return const SizedBox.shrink();
                          }
                          final hasConflict = courses.any(
                            (other) => other.id != c.id && c.overlapsWith(other),
                          );
                          return Positioned(
                            left: timeW + col * cellW + 2,
                            top: row * sectionH + 2,
                            width: cellW - 4,
                            height: sectionH * c.sectionCount - 4,
                            child: _CourseBlock(
                              course: c,
                              isCompact: isCompact,
                              highlighted: c.id == highlightedCourseId,
                              hasConflict: hasConflict,
                            ),
                          );
                        }),
                      ],
                    ),
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

class _CourseBlock extends StatelessWidget {
  final CourseItem course;
  final bool? isCompact;
  final bool highlighted;
  final bool hasConflict;

  const _CourseBlock({
    required this.course,
    this.isCompact,
    this.highlighted = false,
    this.hasConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    final settings = context.read<CourseProvider>().settings;
    final weekPattern = _weekPatternLabel(course.weeks, settings.totalWeeks);
    final theme = Theme.of(context);
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final cardBg = Color.alphaBlend(color.withValues(alpha: 0.9), scaffoldBg);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final defaultStyle = DefaultTextStyle.of(context).style;

    final titleFg = _resolveTitleForeground(cardBg, 12.0, textScaler);
    final secondaryFg = _resolveSecondaryForeground(cardBg, titleFg);

    final timeLabel = settings.sectionTimeRangeLabel(
      course.startSection,
      course.sectionCount,
    );

    return GestureDetector(
      onTap: () => showCourseEditor(context, course: course),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactWidth = isCompact ?? (constraints.maxWidth < 76);
          final inferredSectionH = (constraints.maxHeight + 4.0) /
              (course.sectionCount > 0 ? course.sectionCount : 1);
          final scaleFactor = inferredSectionH / 56.0;

          final compactHeight = constraints.maxHeight < 72 * scaleFactor;
          final padding = compactWidth
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
              : const EdgeInsets.all(6);

          final availableContentW =
              (constraints.maxWidth - padding.horizontal) > 0.0
                  ? constraints.maxWidth - padding.horizontal
                  : 0.0;

          final showTime = constraints.maxHeight >= 42;
          final timeStyle = defaultStyle.merge(
            TextStyle(fontSize: 9, height: 1.05, color: secondaryFg),
          );
          final titleMaxLines =
              constraints.maxHeight >= 82 * scaleFactor && !compactWidth ? 2 : 1;
          final titleStyle = defaultStyle.merge(
            TextStyle(
              fontSize: 12,
              height: 1.08,
              fontWeight: FontWeight.normal,
              color: titleFg,
            ),
          );
          final locStyle = defaultStyle.merge(
            TextStyle(fontSize: 10, height: 1.05, color: secondaryFg),
          );
          final teachStyle = defaultStyle.merge(
            TextStyle(fontSize: 10, height: 1.05, color: secondaryFg),
          );
          final weekStyle = defaultStyle.merge(
            TextStyle(fontSize: 9, height: 1.05, color: secondaryFg),
          );

          final timeH = showTime
              ? _measureTextHeight(
                  timeLabel,
                  timeStyle,
                  textScaler,
                  textDirection,
                  maxWidth: availableContentW,
                ) + 2.0
              : 0.0;
          final titleH = _measureTextHeight(
            course.name,
            titleStyle,
            textScaler,
            textDirection,
            maxLines: titleMaxLines,
            maxWidth: availableContentW,
          );
          final locH = course.location.isNotEmpty
              ? _measureTextHeight(
                  '@${course.location}',
                  locStyle,
                  textScaler,
                  textDirection,
                  maxWidth: availableContentW,
                ) + 2.0
              : 0.0;
          final teachH = course.teacher.isNotEmpty
              ? _measureTextHeight(
                  course.teacher,
                  teachStyle,
                  textScaler,
                  textDirection,
                  maxWidth: availableContentW,
                )
              : 0.0;
          final weekH = weekPattern != null
              ? _measureTextHeight(
                  weekPattern,
                  weekStyle,
                  textScaler,
                  textDirection,
                  maxWidth: availableContentW,
                ) + 2.0
              : 0.0;

          final baseH = padding.vertical + timeH + titleH;
          final canFitDetails = (baseH + locH) <= constraints.maxHeight;
          final canFitTeacher = (baseH + locH + teachH) <= constraints.maxHeight;
          final canFitWeek =
              (baseH + locH + teachH + weekH) <= constraints.maxHeight;

          final showDetails = !compactWidth &&
              constraints.maxHeight >= 96 * scaleFactor &&
              !compactHeight &&
              canFitDetails;
          final showTeacher = showDetails &&
              constraints.maxHeight >= 112 * scaleFactor &&
              course.teacher.isNotEmpty &&
              canFitTeacher;
          final showWeek = showDetails &&
              constraints.maxHeight >= 128 * scaleFactor &&
              weekPattern != null &&
              canFitWeek;

          final blockBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTime) ...[
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.05,
                    color: secondaryFg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
              ],
              Text(
                course.name,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.08,
                  fontWeight: FontWeight.normal,
                  color: titleFg,
                ),
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
              if (showDetails && course.location.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '@${course.location}',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.05,
                      color: secondaryFg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (showTeacher)
                Text(
                  course.teacher,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.05,
                    color: secondaryFg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (showWeek)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    weekPattern,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.05,
                      color: secondaryFg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          );

          return Container(
            clipBehavior: Clip.antiAlias,
            padding: padding,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
              border: hasConflict
                  ? Border.all(color: theme.colorScheme.error, width: 0.6)
                  : (highlighted
                        ? Border.all(
                            color: theme.colorScheme.primary,
                            width: 0.6,
                          )
                        : null),
            ),
            child: hasConflict
                ? Stack(
                    children: [
                      blockBody,
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Icon(
                          Icons.warning_amber_rounded,
                          key: ValueKey('course_conflict_badge_${course.id}'),
                          size: 12,
                          color: titleFg,
                        ),
                      ),
                    ],
                  )
                : blockBody,
          );
        },
      ),
    );
  }

  static double _measureTextHeight(
    String text,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection, {
    int maxLines = 1,
    double maxWidth = double.infinity,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  static Color _resolveTitleForeground(
    Color cardBg,
    double fontSize,
    TextScaler textScaler,
  ) {
    final scaledSize = textScaler.scale(fontSize);
    if (scaledSize >= 24.0 && appContrastRatio(cardBg, Colors.white) >= 3.0) {
      return Colors.white;
    }
    return appReadableForeground(cardBg, Colors.white);
  }

  static Color _resolveSecondaryForeground(Color cardBg, Color titleFg) {
    return appReadableForeground(cardBg, titleFg.withValues(alpha: 0.85));
  }

  String? _weekPatternLabel(List<int> weeks, int totalWeeks) {
    if (weeks.isEmpty) return null;
    final normalized = weeks.toSet();
    final all = normalized.length >= totalWeeks;
    if (all) return I18n.tr('course.weeks.all');
    final oddCount = normalized.where((w) => w.isOdd).length;
    final evenCount = normalized.where((w) => w.isEven).length;
    final expectedOdd = List.generate(
      totalWeeks,
      (i) => i + 1,
    ).where((w) => w.isOdd).length;
    final expectedEven = totalWeeks - expectedOdd;
    if (oddCount == expectedOdd && evenCount == 0) {
      return I18n.tr('course.weeks.odd');
    }
    if (evenCount == expectedEven && oddCount == 0) {
      return I18n.tr('course.weeks.even');
    }
    return '${normalized.length}${I18n.tr('course.week.count_suffix')}';
  }
}

class _ScheduleSettingsSheet extends StatefulWidget {
  final CourseProvider provider;
  const _ScheduleSettingsSheet({required this.provider});

  @override
  State<_ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<_ScheduleSettingsSheet> {
  late DateTime _termStart;
  late int _totalWeeks;
  late int _sessionsPerDay;
  late int _sessionMinutes;
  late TimeOfDay _firstSessionTime;
  late int _breakMinutes;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    final s = widget.provider.settings;
    _termStart = s.termStart;
    _totalWeeks = s.totalWeeks;
    _sessionsPerDay = s.sessionsPerDay;
    _sessionMinutes = s.sessionMinutes;
    _firstSessionTime = TimeOfDay(
      hour: s.firstSessionHour,
      minute: s.firstSessionMinute,
    );
    _breakMinutes = s.breakMinutes;
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: I18n.tr('course.settings.title'),
      subtitle: I18n.tr('course.settings.subtitle'),
      actions: [
        FilledButton(
          onPressed: () {
            widget.provider.updateSettings(
              ScheduleSettings(
                termStart: _termStart,
                totalWeeks: _totalWeeks,
                sessionsPerDay: _sessionsPerDay,
                sessionMinutes: _sessionMinutes,
                firstSessionHour: _firstSessionTime.hour,
                firstSessionMinute: _firstSessionTime.minute,
                breakMinutes: _breakMinutes,
              ),
            );
            Navigator.pop(context);
          },
          child: Text(I18n.tr('action.save')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(I18n.tr('course.field.term_start')),
            subtitle: Text(AppDateFormat.date(context, _termStart)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await AppDatePicker.pickSolar(
                context,
                initialDate: _termStart,
                firstDate: DateTime(2020),
                lastDate: DateTime(2099, 12, 31),
                titleKey: 'course.field.term_start_picker',
              );
              if (!mounted) return;
              if (picked != null) {
                final monday = picked.subtract(
                  Duration(days: picked.weekday - 1),
                );
                setState(() => _termStart = monday);
              }
            },
          ),
          _sliderRow(
            I18n.tr('course.field.total_weeks'),
            _totalWeeks.toDouble(),
            8,
            30,
            1,
            (v) {
              setState(() => _totalWeeks = v.toInt());
            },
          ),
          _sliderRow(
            I18n.tr('course.field.sessions_per_day'),
            _sessionsPerDay.toDouble(),
            4,
            14,
            1,
            (v) {
              setState(() => _sessionsPerDay = v.toInt());
            },
          ),
          _sliderRow(
            I18n.tr('course.field.session_minutes'),
            _sessionMinutes.toDouble(),
            30,
            90,
            5,
            (v) {
              setState(() => _sessionMinutes = v.toInt());
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(I18n.tr('course.field.first_session_time')),
            subtitle: Text(
              I18nDateFormat.timeOfDay(
                hour: _firstSessionTime.hour,
                minute: _firstSessionTime.minute,
              ),
            ),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await AppTimePicker.show(
                context,
                initialTime: _firstSessionTime,
                titleKey: 'course.field.first_session_time',
                subtitleKey: 'course.field.first_session_time_subtitle',
                minuteStep: 5,
              );
              if (!mounted) return;
              if (picked != null) {
                setState(() => _firstSessionTime = picked);
              }
            },
          ),
          _sliderRow(
            I18n.tr('course.field.break_minutes'),
            _breakMinutes.toDouble(),
            0,
            30,
            5,
            (v) {
              setState(() => _breakMinutes = v.toInt());
            },
          ),
          const SizedBox(height: 8),
          Text(
            '${I18n.tr('course.settings.preview_prefix')}1 ${_previewSettings().sectionTimeLabel(1)} · '
            '2 ${_previewSettings().sectionTimeLabel(2)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }

  ScheduleSettings _previewSettings() {
    return ScheduleSettings(
      termStart: _termStart,
      totalWeeks: _totalWeeks,
      sessionsPerDay: _sessionsPerDay,
      sessionMinutes: _sessionMinutes,
      firstSessionHour: _firstSessionTime.hour,
      firstSessionMinute: _firstSessionTime.minute,
      breakMinutes: _breakMinutes,
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChange,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final valueText = Text(
            value.toInt().toString(),
            textAlign: TextAlign.right,
            maxLines: 1,
          );
          final slider = Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: value.toInt().toString(),
            onChanged: onChange,
          );
          final title = Text(
            label,
            style: const TextStyle(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 8),
                    SizedBox(width: 42, child: valueText),
                  ],
                ),
                slider,
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 104, child: title),
              Expanded(child: slider),
              SizedBox(width: 42, child: valueText),
            ],
          );
        },
      ),
    );
  }
}

class _CourseEditSheet extends StatefulWidget {
  final CourseProvider provider;
  final CourseItem? course;
  const _CourseEditSheet({required this.provider, this.course});

  @override
  State<_CourseEditSheet> createState() => _CourseEditSheetState();
}

class _CourseEditSheetState extends State<_CourseEditSheet> {
  late TextEditingController _name;
  late TextEditingController _teacher;
  late TextEditingController _location;
  int _weekday = 1;
  int _startSection = 1;
  int _sectionCount = 2;
  List<int> _weeks = [];
  int _colorValue = 0xFF42A5F5;
  int _reminderMinutes = CourseItem.defaultReminderMinutes;

  static const _presetColors = [
    0xFF42A5F5,
    0xFF66BB6A,
    0xFFFFA726,
    0xFFEF5350,
    0xFFAB47BC,
    0xFF26A69A,
    0xFFEC407A,
    0xFF5C6BC0,
  ];

  static const _reminderOptions = <int>[0, 5, 10, 15, 30];

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weekday = c?.weekday ?? 1;
    _startSection = c?.startSection ?? 1;
    _sectionCount = c?.sectionCount ?? 2;
    _weeks = [...?c?.weeks];
    if (_weeks.isEmpty) {
      _weeks = List.generate(widget.provider.settings.totalWeeks, (i) => i + 1);
    }
    _colorValue = c?.colorValue ?? 0xFF42A5F5;
    _reminderMinutes =
        c?.reminderMinutes ?? CourseItem.defaultReminderMinutes;
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.provider.settings;
    final cs = Theme.of(context).colorScheme;
    final draft = CourseItem(
      id: widget.course?.id,
      name: _name.text.trim(),
      teacher: _teacher.text.trim(),
      location: _location.text.trim(),
      weekday: _weekday,
      startSection: _startSection,
      sectionCount: _sectionCount,
      weeks: _weeks,
      colorValue: _colorValue,
      reminderMinutes: _reminderMinutes,
    );
    final conflicts = widget.provider.findConflicts(
      draft,
      excludeCourseId: widget.course?.id,
    );
    return AppModalSheet(
      title: widget.course == null
          ? I18n.tr('course.editor.add_title')
          : I18n.tr('course.editor.edit_title'),
      subtitle: I18n.tr('course.editor.subtitle'),
      leadingActions: widget.course == null
          ? const []
          : [
              TextButton(
                onPressed: () {
                  widget.provider.delete(widget.course!.id);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(I18n.tr('action.delete')),
              ),
            ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            final item = CourseItem(
              id: widget.course?.id,
              name: _name.text.trim(),
              teacher: _teacher.text.trim(),
              location: _location.text.trim(),
              weekday: _weekday,
              startSection: _startSection,
              sectionCount: _sectionCount,
              weeks: _weeks..sort(),
              colorValue: _colorValue,
              reminderMinutes: _reminderMinutes,
            );
            if (widget.course == null) {
              widget.provider.add(item);
            } else {
              widget.provider.update(item);
            }
            Navigator.pop(context);
          },
          child: Text(
            widget.course == null
                ? I18n.tr('action.add')
                : I18n.tr('action.save'),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conflicts.isNotEmpty) ...[
            Container(
              key: const ValueKey('course_conflict_banner'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.error.withValues(alpha: 0.55),
                  width: 0.6,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: cs.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          CourseScheduleUiCopy.conflictWarningTitle(
                            conflicts.length,
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final c in conflicts.take(3))
                    Text(
                      CourseScheduleUiCopy.conflictLine(
                        c.name,
                        _weekdayLabel(c.weekday),
                        c.startSection,
                        c.endSection,
                        draft.overlappingWeeksWith(c),
                      ),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
          ],
          TextField(
            controller: _name,
            autofocus: widget.course == null,
            decoration: InputDecoration(
              labelText: I18n.tr('course.field.name'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _teacher,
            decoration: InputDecoration(
              labelText: I18n.tr('course.field.teacher'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _location,
            decoration: InputDecoration(
              labelText: I18n.tr('course.field.location'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            I18n.tr('course.field.weekday'),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: List.generate(7, (i) {
              final w = i + 1;
              return ChoiceChip(
                label: Text(_weekdayLabel(w)),
                selected: _weekday == w,
                onSelected: (_) => setState(() => _weekday = w),
              );
            }),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final startLabel = I18n.tr('course.field.start_section');
              final countLabel = I18n.tr('course.field.section_count');
              final helper1 = settings.sectionTimeLabel(_startSection);
              final helper2 = settings.sectionTimeRangeLabel(
                _startSection,
                _sectionCount,
              );
              final textDirection = Directionality.of(context);
              final defaultStyle = DefaultTextStyle.of(context).style;

              double measureText(String text, TextStyle style) {
                final mergedStyle = defaultStyle.merge(style);
                final painter = TextPainter(
                  text: TextSpan(
                    text: text,
                    style: mergedStyle,
                  ),
                  textDirection: textDirection,
                  textScaler: textScaler,
                  maxLines: 1,
                )..layout();
                final w = painter.width;
                painter.dispose();
                return w;
              }

              final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
              final w1 = measureText(
                startLabel,
                TextStyle(fontSize: 11, color: mutedColor),
              );
              final w2 = measureText(
                countLabel,
                TextStyle(fontSize: 11, color: mutedColor),
              );
              final h1 = measureText(
                helper1,
                TextStyle(fontSize: 10, color: mutedColor),
              );
              final h2 = measureText(
                helper2,
                TextStyle(fontSize: 10, color: mutedColor),
              );
              final stepperWidth = measureText(
                    '${settings.sessionsPerDay}',
                    const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ) +
                  56.0;
              final maxContentWidth = [w1, w2, h1, h2, stepperWidth].reduce(
                (a, b) => a > b ? a : b,
              );

              final halfWidth = (constraints.maxWidth - 10.0) / 2.0;
              final usableWidth = halfWidth - 24.0;
              final isNarrowOrLarge =
                  usableWidth < (maxContentWidth + 4.0) ||
                  constraints.maxWidth < 300.0;

              final startPick = _numberPick(
                label: startLabel,
                helper: helper1,
                value: _startSection,
                min: 1,
                max: settings.sessionsPerDay,
                onChange: (v) => setState(() => _startSection = v),
              );
              final countPick = _numberPick(
                label: countLabel,
                helper: helper2,
                value: _sectionCount,
                min: 1,
                max: (settings.sessionsPerDay - _startSection + 1).clamp(
                  1,
                  settings.sessionsPerDay,
                ),
                onChange: (v) => setState(() => _sectionCount = v),
              );

              if (isNarrowOrLarge) {
                return Column(
                  children: [
                    startPick,
                    const SizedBox(height: 10),
                    countPick,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: startPick),
                  const SizedBox(width: 10),
                  Expanded(child: countPick),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _classWeeksHeader(settings),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(settings.totalWeeks, (i) {
              final w = i + 1;
              final selected = _weeks.contains(w);
              return FilterChip(
                label: Text('$w'),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  if (selected) {
                    _weeks.remove(w);
                  } else {
                    _weeks.add(w);
                  }
                }),
              );
            }),
          ),
          const SizedBox(height: 14),
          Text(
            I18n.tr('course.field.color'),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: _presetColors.map((v) {
              return GestureDetector(
                onTap: () => setState(() => _colorValue = v),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(v),
                    shape: BoxShape.circle,
                    border: v == _colorValue
                        ? Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.42),
                            width: 0.8,
                          )
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Text(
            CourseScheduleUiCopy.reminderFieldLabel,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _reminderOptions.map((mins) {
              return ChoiceChip(
                key: ValueKey('course_reminder_chip_$mins'),
                label: Text(
                  CourseScheduleUiCopy.reminderOptionLabel(mins),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                selected: _reminderMinutes == mins,
                onSelected: (_) => setState(() => _reminderMinutes = mins),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _classWeeksHeader(ScheduleSettings settings) {
    Widget action(String label, VoidCallback onPressed) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }

    final label = Text(
      I18n.tr('course.field.class_weeks'),
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        action(
          I18n.tr('course.weeks.select_all'),
          () => setState(
            () => _weeks = List.generate(settings.totalWeeks, (i) => i + 1),
          ),
        ),
        action(
          I18n.tr('course.weeks.odd'),
          () => setState(
            () => _weeks = List.generate(
              settings.totalWeeks,
              (i) => i + 1,
            ).where((w) => w.isOdd).toList(),
          ),
        ),
        action(
          I18n.tr('course.weeks.even'),
          () => setState(
            () => _weeks = List.generate(
              settings.totalWeeks,
              (i) => i + 1,
            ).where((w) => w.isEven).toList(),
          ),
        ),
        action(I18n.tr('action.clear'), () => setState(() => _weeks = [])),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: label),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    );
  }

  Widget _numberPick({
    required String label,
    String? helper,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChange,
  }) {
    Widget stepButton(IconData icon, VoidCallback? onPressed) {
      return SizedBox.square(
        dimension: 28,
        child: IconButton(
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(28, 28),
          ),
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          Row(
            children: [
              stepButton(
                Icons.remove,
                value > min ? () => onChange(value - 1) : null,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              stepButton(
                Icons.add,
                value < max ? () => onChange(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _courseWeekLabel(int week) {
  return '${I18n.tr('course.week.prefix')}$week${I18n.tr('course.week.suffix')}';
}

String _weekdayLabel(int weekday) {
  final index = weekday.clamp(1, 7) - 1;
  return I18n.tr(_weekdayKeys[index]);
}

class _CourseImportSheet extends StatefulWidget {
  final CourseProvider provider;

  const _CourseImportSheet({required this.provider});

  @override
  State<_CourseImportSheet> createState() => _CourseImportSheetState();
}

class _CourseImportSheetState extends State<_CourseImportSheet> {
  final TextEditingController _inputController = TextEditingController();
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _inputController.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickTimetableFile() async {
    try {
      const typeGroup = XTypeGroup(
        label: 'Timetable',
        extensions: ['ics', 'csv', 'txt'],
      );
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _inputController.text = utf8.decode(bytes, allowMalformed: true);
      });
    } catch (_) {
      // Ignore canceled or unsupported file selection errors cleanly.
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = CourseProvider.parseTimetable(
      _inputController.text,
      settings: widget.provider.settings,
    );
    final overlapCount = preview.courses
        .where((c) => widget.provider.findConflicts(c).isNotEmpty)
        .length;

    return AppModalSheet(
      title: CourseScheduleUiCopy.importTitle,
      subtitle: CourseScheduleUiCopy.importSubtitle,
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          key: const ValueKey('course_import_confirm_btn'),
          onPressed: (_importing || preview.courses.isEmpty)
              ? null
              : () async {
                  setState(() => _importing = true);
                  final count = await widget.provider.importCourses(
                    preview.courses,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.maybeOf(context)
                    ?..removeCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          CourseScheduleUiCopy.importedSuccess(count),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
          child: Text(
            CourseScheduleUiCopy.importAction(preview.courses.length),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('course_import_pick_file_btn'),
                onPressed: _pickTimetableFile,
                icon: const Icon(Icons.folder_open_outlined, size: 17),
                label: Text(CourseScheduleUiCopy.pickFileLabel),
              ),
              TextButton.icon(
                key: const ValueKey('course_import_sample_btn'),
                onPressed: () => setState(() {
                  _inputController.text = CourseScheduleUiCopy.sampleCsv;
                }),
                icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                label: Text(CourseScheduleUiCopy.useSampleCsv),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('course_import_text_field'),
            controller: _inputController,
            minLines: 4,
            maxLines: 7,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: CourseScheduleUiCopy.inputHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant, width: 0.6),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant, width: 0.6),
              ),
            ),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (_inputController.text.trim().isNotEmpty)
            Container(
              key: const ValueKey('course_import_preview_box'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant, width: 0.6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.courses.isEmpty
                        ? CourseScheduleUiCopy.noCoursesParsed
                        : CourseScheduleUiCopy.previewSummary(
                            preview.format,
                            preview.courses.length,
                          ),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  if (overlapCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      CourseScheduleUiCopy.importConflictNote(overlapCount),
                      style: TextStyle(fontSize: 11.5, color: cs.error),
                    ),
                  ],
                  if (preview.courses.isNotEmpty) const SizedBox(height: 6),
                  for (final c in preview.courses.take(6))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        CourseScheduleUiCopy.conflictLine(
                          c.name,
                          _weekdayLabel(c.weekday),
                          c.startSection,
                          c.endSection,
                          c.weeks,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
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
