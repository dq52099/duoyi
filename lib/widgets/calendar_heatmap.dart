import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/heatmap_calendar.dart';
import '../core/heatmap_ui_copy.dart';
import '../core/i18n.dart';
import '../core/design_tokens.dart';
import 'app_date_format.dart';
import 'app_date_picker.dart';

/// Shared calendar geometry and date inspection. Compact cells have one keyboard
/// focus; full-size date controls offer an alternative to tapping small cells.
class CalendarHeatmap extends StatefulWidget {
  final HeatmapCalendarWindow window;
  final String title;
  final String Function(DateTime) describeDay;
  final Color Function(DateTime) colorForDay;
  final Widget legend;
  final Widget? summary;
  final String? emptyLabel;
  final ValueChanged<DateTime>? onOpenDay;
  final String Function(DateTime)? openDayLabel;

  const CalendarHeatmap({
    super.key,
    required this.window,
    required this.title,
    required this.describeDay,
    required this.colorForDay,
    required this.legend,
    this.summary,
    this.emptyLabel,
    this.onOpenDay,
    this.openDayLabel,
  });

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late DateTime _selected = widget.window.today;
  bool _initialScrollDone = false;
  double _pitch = 20;

  @override
  void didUpdateWidget(CalendarHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.window.contains(_selected)) _selected = widget.window.today;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(DateTime day, {bool focusGrid = false}) {
    if (!widget.window.contains(day)) return;
    setState(() => _selected = day);
    if (focusGrid) _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final column =
          HeatmapCalendarWindow.dayDistance(widget.window.start, _selected) ~/
          7;
      final left = column * _pitch;
      final right = left + _pitch;
      final position = _scroll.position;
      if (left < position.pixels) {
        _scroll.jumpTo(left.clamp(0, position.maxScrollExtent));
      } else if (right > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (right - position.viewportDimension).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _move(int days) =>
      _select(HeatmapCalendarWindow.shiftDay(_selected, days));

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-7);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(7);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_selected.weekday > DateTime.monday) _move(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_selected.weekday < DateTime.sunday) _move(1);
    } else if (key == LogicalKeyboardKey.home) {
      _select(widget.window.start);
    } else if (key == LogicalKeyboardKey.end) {
      _select(widget.window.today);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _select(_selected);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _pickDay() async {
    final day = await AppDatePicker.pickSolar(
      context,
      initialDate: _selected,
      firstDate: widget.window.start,
      lastDate: widget.window.today,
    );
    if (!mounted || day == null) return;
    _select(day);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, _) {
      final copy = HeatmapUiCopy(locale);
      final cs = Theme.of(context).colorScheme;
      final textStyle = TextStyle(
        fontSize: DesignTokens.fontSizeCaption,
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.normal,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            copy.range(
              widget.window.start,
              widget.window.today,
              pattern: AppDateFormat.patternOf(context),
            ),
            style: textStyle.copyWith(fontSize: DesignTokens.fontSizeCaption),
          ),
          if (widget.summary != null) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            _summaryBanner(context, widget.summary!),
          ],
          const SizedBox(height: DesignTokens.spaceSm),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
              final available = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 360.0;
              final cell = ((available - 42) / widget.window.weeks - 3).clamp(
                16.0,
                22.0,
              );
              var labelWidth = 0.0;
              var labelHeight = 0.0;
              for (final day in [1, 3, 5, 7]) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: copy.weekday(day),
                    style: DefaultTextStyle.of(context).style.merge(textStyle),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                labelWidth = math.max(labelWidth, painter.width);
                labelHeight = math.max(labelHeight, painter.height);
                painter.dispose();
              }
              _pitch = math.max(cell + 3, labelHeight + 3);
              final axisWidth = math.max(32.0, labelWidth + 6);
              final months = <int, DateTime>{0: widget.window.start};
              for (
                var month = DateTime(
                  widget.window.start.year,
                  widget.window.start.month + 1,
                );
                widget.window.contains(month);
                month = DateTime(month.year, month.month + 1)
              ) {
                months[HeatmapCalendarWindow.dayDistance(
                          widget.window.start,
                          month,
                        ) ~/
                        7] =
                    month;
              }

              // Measure month text labels to prevent clipping enlarged glyphs and resolve placements without collision.
              var maxMonthHeight = 0.0;
              final monthWidths = <int, double>{};
              for (final entry in months.entries) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: copy.month(entry.value),
                    style: DefaultTextStyle.of(context).style.merge(textStyle),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                monthWidths[entry.key] = painter.width;
                maxMonthHeight = math.max(maxMonthHeight, painter.height);
                painter.dispose();
              }
              final headerHeight = math.max(22.0, maxMonthHeight + 4);

              final monthPositions = <int, double>{};
              double? prevRight;
              for (final entry in months.entries) {
                final idealLeft = entry.key * _pitch + 1.5;
                final width = monthWidths[entry.key] ?? 0.0;
                final placedLeft = prevRight == null
                    ? idealLeft
                    : math.max(idealLeft, prevRight + 4.0);
                monthPositions[entry.key] = placedLeft;
                prevRight = placedLeft + width;
              }

              final cellsWidth = widget.window.weeks * _pitch + 36 * scale;
              final lastMonthRight = (prevRight ?? 0.0) + 4.0;
              final contentWidth = math.max(cellsWidth, lastMonthRight);

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _initialScrollDone || !_scroll.hasClients) {
                  return;
                }
                _initialScrollDone = true;
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              });
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: axisWidth,
                    child: Column(
                      children: [
                        SizedBox(height: headerHeight),
                        for (var day = 1; day <= 7; day++)
                          SizedBox(
                            height: _pitch,
                            child: Center(
                              child: day.isOdd
                                  ? Text(
                                      copy.weekday(day),
                                      style: textStyle.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Focus(
                      key: const ValueKey('heatmap_grid_focus'),
                      focusNode: _focus,
                      onKeyEvent: _handleKey,
                      onFocusChange: (_) {
                        if (mounted) setState(() {});
                      },
                      child: Semantics(
                        label: widget.title,
                        hint: copy.inspectHint,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusSm,
                            ),
                            border: Border.all(
                              color: _focus.hasFocus
                                  ? cs.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: SingleChildScrollView(
                            key: const ValueKey('heatmap_scroll'),
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: contentWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: headerHeight,
                                    child: Stack(
                                      children: [
                                        for (final month in months.entries)
                                          Positioned(
                                            left: monthPositions[month.key] ??
                                                (month.key * _pitch + 1.5),
                                            child: Text(
                                              copy.month(month.value),
                                              style: textStyle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (
                                        var column = 0;
                                        column < widget.window.weeks;
                                        column++
                                      )
                                        Column(
                                          children: [
                                            for (var row = 0; row < 7; row++)
                                              _cell(
                                                context,
                                                widget.window.dayAt(
                                                  column * 7 + row,
                                                ),
                                                cell,
                                                copy,
                                              ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          widget.legend,
          const SizedBox(height: DesignTokens.spaceSm),
          LayoutBuilder(
            builder: (context, constraints) {
              final dateText = AppDateFormat.date(context, _selected);
              final previousButton = IconButton(
                key: const ValueKey('heatmap_previous_day'),
                tooltip: locale == AppLocale.en ? 'Previous day' : '前一天',
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                onPressed:
                    HeatmapCalendarWindow.dateKey(_selected) ==
                        HeatmapCalendarWindow.dateKey(widget.window.start)
                    ? null
                    : () => _move(-1),
                icon: const Icon(Icons.chevron_left, size: 20),
              );

              final nextButton = IconButton(
                key: const ValueKey('heatmap_next_day'),
                tooltip: locale == AppLocale.en ? 'Next day' : '后一天',
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                onPressed:
                    HeatmapCalendarWindow.dateKey(_selected) ==
                        HeatmapCalendarWindow.dateKey(widget.window.today)
                    ? null
                    : () => _move(1),
                icon: const Icon(Icons.chevron_right, size: 20),
              );

              final todayButton = IconButton(
                key: const ValueKey('heatmap_today'),
                tooltip: copy.today,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                onPressed: () => _select(widget.window.today),
                icon: const Icon(Icons.today_outlined, size: 20),
              );

              final dateButton = TextButton(
                key: const ValueKey('heatmap_selected_date'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _pickDay,
                child: Text(
                  dateText,
                  textAlign: TextAlign.center,
                ),
              );

              final availableWidth = constraints.maxWidth;
              final textStyle =
                  Theme.of(context).textTheme.labelLarge ??
                  DefaultTextStyle.of(context).style;
              final painter = TextPainter(
                text: TextSpan(text: dateText, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final naturalDateWidth = painter.width;
              painter.dispose();

              // Three 48dp icon buttons take 144dp, plus text button horizontal padding (24dp).
              final fitsSingleRow =
                  availableWidth.isFinite &&
                  (naturalDateWidth + 168.0 <= availableWidth);

              if (fitsSingleRow) {
                return Row(
                  children: [
                    previousButton,
                    Expanded(child: dateButton),
                    nextButton,
                    todayButton,
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: dateButton,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      previousButton,
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          nextButton,
                          todayButton,
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          Semantics(
            liveRegion: true,
            label:
                '${AppDateFormat.date(context, _selected)} · ${widget.describeDay(_selected)}',
            excludeSemantics: true,
            child: AnimatedSwitcher(
              duration: DesignTokens.durationFast,
              child: KeyedSubtree(
                key: ValueKey(HeatmapCalendarWindow.dateKey(_selected)),
                child: Text(
                  widget.describeDay(_selected),
                  key: const ValueKey('heatmap_selected_detail'),
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeSecondary,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (widget.emptyLabel != null) ...[
            const SizedBox(height: DesignTokens.spaceXs),
            Text(
              widget.emptyLabel!,
              key: const ValueKey('heatmap_empty_hint'),
              style: TextStyle(
                fontSize: DesignTokens.fontSizeCaption,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (widget.onOpenDay != null && widget.openDayLabel != null)
                TextButton(
                  key: const ValueKey('heatmap_open_day'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => widget.onOpenDay!(_selected),
                  child: Text(widget.openDayLabel!(_selected)),
                ),
            ],
          ),
        ],
      );
    },
  );

  Widget _summaryBanner(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(
          color: cs.primary.withValues(alpha: dark ? 0.22 : 0.12),
          width: 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceMd,
          vertical: DesignTokens.spaceSm,
        ),
        child: child,
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime day,
    double cell,
    HeatmapUiCopy copy,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected =
        HeatmapCalendarWindow.dateKey(day) ==
        HeatmapCalendarWindow.dateKey(_selected);
    final today =
        HeatmapCalendarWindow.dateKey(day) ==
        HeatmapCalendarWindow.dateKey(widget.window.today);
    if (!widget.window.contains(day)) {
      return SizedBox(width: _pitch, height: _pitch);
    }
    final color = widget.colorForDay(day);
    final label =
        '${AppDateFormat.date(context, day)} · ${widget.describeDay(day)}${today ? ' · ${copy.today}' : ''}';
    return Semantics(
      key: ValueKey('heatmap_day_${HeatmapCalendarWindow.dateKey(day)}'),
      button: true,
      selected: selected,
      label: label,
      onTap: () => _select(day),
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _select(day, focusGrid: true),
            child: SizedBox(
              width: _pitch,
              height: _pitch,
              child: Center(
                child: Container(
                  width: cell + 2,
                  height: cell + 2,
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: selected ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                    border: Border.all(
                      color: selected ? cs.onSurface : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Container(
                    key: ValueKey(
                      'heatmap_day_fill_${HeatmapCalendarWindow.dateKey(day)}',
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusXs,
                      ),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.24),
                        width: 0.5,
                      ),
                    ),
                    child: today
                        ? Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Container(
                                width: 3,
                                height: 3,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.computeLuminance() > 0.179
                                      ? Colors.black
                                      : Colors.white,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
