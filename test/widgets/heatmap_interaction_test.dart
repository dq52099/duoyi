import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/core/heatmap_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/widgets/activity_heatmap_card.dart';
import 'package:duoyi/widgets/calendar_heatmap.dart';
import 'package:duoyi/widgets/habit_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 5, 17);

String _key(DateTime day) => HeatmapCalendarWindow.dateKey(day);

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: SingleChildScrollView(padding: const EdgeInsets.all(8), child: child),
  ),
);

CalendarHeatmap _calendar({
  int weeks = 1,
  DateTime? today,
  ValueChanged<DateTime>? onOpenDay,
}) => CalendarHeatmap(
  window: HeatmapCalendarWindow(weeks: weeks, today: today ?? _today),
  title: 'Daily activity',
  describeDay: _key,
  colorForDay: (_) => Colors.green,
  legend: const Text('Legend'),
  onOpenDay: onOpenDay,
  openDayLabel: (day) => 'Open ${_key(day)}',
);

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'metric titles, level labels and hints follow the selected metric',
    (tester) async {
      for (final metric in HeatmapMetric.values) {
        await tester.pumpWidget(
          _app(
            HabitHeatmap(
              heatmapData: const {},
              weeks: 1,
              today: _today,
              metric: metric,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final chinese = HeatmapUiCopy(AppLocale.zh);
        expect(
          find.bySemanticsLabel(chinese.metricTitle(metric)),
          findsOneWidget,
        );
        expect(find.text(chinese.levelLabel(metric, 0)), findsOneWidget);
        expect(
          find.text(
            metric == HeatmapMetric.activity
                ? chinese.activityHint
                : chinese.progressHint,
          ),
          findsOneWidget,
        );
        expect(find.byTooltip(chinese.levelLabel(metric, 2)), findsOneWidget);

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        final english = HeatmapUiCopy(AppLocale.en);
        expect(
          find.bySemanticsLabel(english.metricTitle(metric)),
          findsOneWidget,
        );
        expect(find.text(english.levelLabel(metric, 0)), findsOneWidget);
        expect(
          find.text(
            metric == HeatmapMetric.activity
                ? english.activityHint
                : english.progressHint,
          ),
          findsOneWidget,
        );
        expect(find.byTooltip(english.levelLabel(metric, 2)), findsOneWidget);
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'day selection, navigation, semantics and diary action stay in range',
    (tester) async {
      final opened = <DateTime>[];
      await tester.pumpWidget(_app(_calendar(onOpenDay: opened.add)));
      await tester.pumpAndSettle();

      expect(find.text('2026-05-17'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('heatmap_day_2026-05-18')),
        findsNothing,
      );

      final monday = find.byKey(const ValueKey('heatmap_day_2026-05-11'));
      await tester.tap(monday);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-11'), findsOneWidget);
      final mondaySemantics = tester.getSemantics(monday);
      expect(mondaySemantics.flagsCollection.isButton, isTrue);
      expect(mondaySemantics.flagsCollection.isSelected.toBoolOrNull(), isTrue);

      final previous = tester.widget<IconButton>(
        find.byKey(const ValueKey('heatmap_previous_day')),
      );
      expect(previous.onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('heatmap_next_day')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('heatmap_next_day')));
      await tester.pumpAndSettle();
      expect(find.text('2026-05-12'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('heatmap_today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('heatmap_open_day')));
      await tester.pumpAndSettle();
      expect(opened, [DateTime(2026, 5, 17)]);

      await tester.tap(find.byKey(const ValueKey('heatmap_day_2026-05-16')));
      await tester.pumpAndSettle();
      expect(find.text('2026-05-16'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('heatmap_day_2026-05-16')))
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
    },
  );

  testWidgets(
    'grid focus supports arrows, Home and End within its weekday rows',
    (tester) async {
      await tester.pumpWidget(_app(_calendar(weeks: 2)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('heatmap_day_2026-05-04')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-04'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-05'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-06'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-13'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-06'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-17'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-17'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-16'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-04'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('2026-05-04'), findsOneWidget);
    },
  );

  testWidgets(
    'solar picker enforces the visible range and cancel keeps selection',
    (tester) async {
      await tester.pumpWidget(_app(_calendar()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('heatmap_selected_date')));
      await tester.pumpAndSettle();
      final beforeWindow = tester.getSemantics(
        find.byKey(const ValueKey('solar-day-2026-05-10')),
      );
      final firstVisibleDay = tester.getSemantics(
        find.byKey(const ValueKey('solar-day-2026-05-11')),
      );
      final afterToday = tester.getSemantics(
        find.byKey(const ValueKey('solar-day-2026-05-18')),
      );
      expect(beforeWindow.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      expect(firstVisibleDay.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(afterToday.flagsCollection.isEnabled.toBoolOrNull(), isFalse);

      await tester.tap(find.byKey(const ValueKey('solar-day-2026-05-12')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarHeatmap), findsOneWidget);
      expect(find.text('2026-05-17'), findsOneWidget);
      expect(find.text('公历'), findsNothing);
    },
  );

  testWidgets('language changes preserve selected date and horizontal scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        HabitHeatmap(
          heatmapData: {_key(_today): 4},
          weeks: 52,
          today: _today,
          metric: HeatmapMetric.progress,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = find.byKey(const ValueKey('heatmap_scroll'));
    final controller = tester.widget<SingleChildScrollView>(grid).controller!;
    final maxOffset = controller.position.maxScrollExtent;
    expect(maxOffset, greaterThan(0));
    expect(controller.offset, maxOffset);
    await tester.drag(grid, const Offset(120, 0));
    await tester.pumpAndSettle();
    final selectedOffset = controller.offset;
    expect(selectedOffset, greaterThan(0));
    expect(selectedOffset, lessThan(maxOffset));
    expect(find.text('达成等级 4/5'), findsOneWidget);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Habit progress calendar'), findsOneWidget);
    expect(find.text('Progress level 4/5'), findsOneWidget);
    expect(controller.offset, selectedOffset);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('heatmap_day_2026-05-17')))
          .flagsCollection
          .isSelected
          .toBoolOrNull(),
      isTrue,
    );

    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('习惯进度日历'), findsOneWidget);
    expect(find.text('达成等级 4/5'), findsOneWidget);
    expect(controller.offset, selectedOffset);
  });

  testWidgets('dark activity card fits a 320 logical pixel 52-week layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final yesterday = HeatmapCalendarWindow.shiftDay(_today, -1);
    await tester.pumpWidget(
      _app(
        ActivityHeatmapCard(
          today: _today,
          heatmapData: {
            _key(yesterday): 4,
            _key(HeatmapCalendarWindow.shiftDay(_today, 1)): 5,
          },
        ),
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('近 52 周活动'), findsOneWidget);
    expect(find.bySemanticsLabel('活动日历'), findsOneWidget);
    expect(find.text('1 天活跃'), findsOneWidget);
    expect(find.text('最高 4/5 级'), findsOneWidget);
    for (final key in [
      'heatmap_previous_day',
      'heatmap_selected_date',
      'heatmap_next_day',
      'heatmap_today',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('heatmap_scroll')),
          )
          .controller!
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });
}
