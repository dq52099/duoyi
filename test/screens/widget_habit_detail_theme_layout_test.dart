import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/habit_trend.dart';
import 'package:duoyi/core/habit_ui_copy.dart';
import 'package:duoyi/core/heatmap_calendar.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/habit_date_range_fields.dart';
import 'package:duoyi/widgets/habit_unit_field.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

enum _Scene { detail, editor }

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'ordinary', size: Size(390, 844), scaler: TextScaler.noScaling),
        (name: 'narrow', size: Size(320, 844), scaler: TextScaler.linear(1.6)),
        (name: 'landscape', size: Size(568, 320), scaler: TextScaler.linear(2)),
        (name: 'nonlinear', size: Size(332, 844), scaler: _HabitScaler()),
      ]) {
        for (final scene in _Scene.values) {
          final name = '$brand-${locale.name}-${layout.name}-${scene.name}';
          testWidgets('widget Habit route, state and theme $name', (
            tester,
          ) async {
            final f = _Fixture();
            await f.open(tester, brand, locale, layout.size, layout.scaler);
            try {
              if (scene == _Scene.detail) {
                _expectOverviewCopy(tester, layout.scaler);
                await _capture(tester, f.boundary, '$name-overview');
                expect(tester.takeException(), isNull);
                await _reveal(
                  tester,
                  find.byType(SegmentedButton<HabitTrendWindow>),
                );
                for (final w in HabitTrendWindow.values) {
                  _expectComplete(
                    tester,
                    localizedHabitTrendWindowLabel(w),
                    layout.scaler,
                  );
                }
                await tester.tap(
                  find.text(
                    localizedHabitTrendWindowLabel(HabitTrendWindow.days90),
                  ),
                );
                await tester.pumpAndSettle();
                expect(
                  tester
                      .widget<SegmentedButton<HabitTrendWindow>>(
                        find.byType(SegmentedButton<HabitTrendWindow>),
                      )
                      .selected,
                  {HabitTrendWindow.days90},
                );
                await _capture(tester, f.boundary, '$name-trend');
                _expectBucketCopy(
                  tester,
                  f.habits.habits.single,
                  f.today,
                  layout.scaler,
                );
                I18n.setLocale(
                  locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
                );
                await tester.pumpAndSettle();
                expect(
                  tester.state(find.byType(HabitDetailScreen)),
                  same(f.routeState),
                );
                expect(
                  tester
                      .widget<SegmentedButton<HabitTrendWindow>>(
                        find.byType(SegmentedButton<HabitTrendWindow>),
                      )
                      .selected,
                  {HabitTrendWindow.days90},
                );
                for (final w in HabitTrendWindow.values) {
                  _expectComplete(
                    tester,
                    localizedHabitTrendWindowLabel(w),
                    layout.scaler,
                  );
                }
                await _capture(tester, f.boundary, '$name-trend-switched');
                _expectBucketCopy(
                  tester,
                  f.habits.habits.single,
                  f.today,
                  layout.scaler,
                );
                expect(f.preferences.getString('habits'), f.stored);
                final overviewScroll = find.descendant(
                  of: find.byType(HabitDetailScreen),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  ),
                );
                tester
                    .state<ScrollableState>(overviewScroll.first)
                    .position
                    .jumpTo(0);
                await tester.pumpAndSettle();
                _expectOverviewCopy(tester, layout.scaler);
                await _capture(tester, f.boundary, '$name-overview-switched');
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                final record = find.byIcon(Icons.add_circle_outline);
                await _reveal(tester, record);
                await tester.tap(record.first);
                await tester.pumpAndSettle();
                expect(f.habits.habits.single.countForDate(f.today), 3);
                await _capture(tester, f.boundary, '$name-record-feedback');
                final undo = find.byIcon(Icons.undo).first;
                await tester.ensureVisible(undo);
                await tester.pumpAndSettle();
                await tester.tap(undo);
                await tester.pumpAndSettle();
                expect(f.habits.habits.single.countForDate(f.today), 2);
                await _reveal(
                  tester,
                  find.widgetWithText(
                    OutlinedButton,
                    HabitUiCopy.endHabitAction(locale),
                  ),
                );
                await tester.tap(
                  find.widgetWithText(
                    OutlinedButton,
                    HabitUiCopy.endHabitAction(locale),
                  ),
                );
                await tester.pumpAndSettle();
                expect(find.byType(AppDialog), findsOneWidget);
                await _capture(tester, f.boundary, '$name-end-dialog');
                await tester.tap(
                  find.widgetWithText(
                    TextButton,
                    HabitUiCopy.actionCancel(locale),
                  ),
                );
                await tester.pumpAndSettle();
                expect(f.habits.habits.single.endDate, isNull);
                await tester.tap(
                  find.widgetWithText(
                    OutlinedButton,
                    HabitUiCopy.actionDelete(locale),
                  ),
                );
                await tester.pumpAndSettle();
                await _capture(tester, f.boundary, '$name-delete-dialog');
                await tester.tap(
                  find.widgetWithText(
                    TextButton,
                    HabitUiCopy.actionCancel(locale),
                  ),
                );
                await tester.pumpAndSettle();
                expect(f.habits.habits, hasLength(1));
              } else {
                await tester.tap(find.byIcon(Icons.edit_outlined));
                await tester.pumpAndSettle();
                expect(find.byType(AppModalSheet), findsOneWidget);
                final nameField = _field('habit.field.name');
                final controller = tester
                    .widget<TextField>(nameField)
                    .controller!;
                await tester.enterText(nameField, 'Draft habit 用户草稿');
                controller.selection = const TextSelection(
                  baseOffset: 1,
                  extentOffset: 6,
                );
                await tester.enterText(
                  _field('habit.field.group'),
                  'Literal category 原分组',
                );
                if (layout.name == 'narrow' || layout.name == 'nonlinear') {
                  tester.view.viewInsets = const FakeViewPadding(bottom: 180);
                }
                FocusManager.instance.primaryFocus?.unfocus();
                await tester.pumpAndSettle();
                for (final stage in ['initial', 'switched']) {
                  if (stage == 'switched') {
                    I18n.setLocale(
                      locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
                    );
                    await tester.pumpAndSettle();
                  }
                  await _reveal(
                    tester,
                    find.byType(HabitUnitField),
                    sheet: true,
                  );
                  if (stage == 'initial') {
                    await _capture(tester, f.boundary, '$name-inputs-initial');
                  }
                  final unit = tester.widget<TextField>(
                    find.descendant(
                      of: find.byType(HabitUnitField),
                      matching: find.byType(TextField),
                    ),
                  );
                  expect(unit.controller!.text, isEmpty);
                  _expectComplete(
                    tester,
                    unit.decoration!.hintText!,
                    layout.scaler,
                  );
                  final kind = find.widgetWithText(
                    ChoiceChip,
                    I18n.tr('habit.kind.positive'),
                  );
                  await _reveal(tester, kind, sheet: true);
                  if (stage == 'switched') {
                    await _capture(tester, f.boundary, '$name-kind-switched');
                  }
                  for (final key in [
                    'habit.kind.positive',
                    'habit.kind.negative',
                  ]) {
                    _expectComplete(tester, I18n.tr(key), layout.scaler);
                  }
                  expect(
                    tester
                        .widget<TextField>(_field('habit.field.name'))
                        .controller,
                    same(controller),
                  );
                  expect(controller.text, 'Draft habit 用户草稿');
                  expect(
                    controller.selection,
                    const TextSelection(baseOffset: 1, extentOffset: 6),
                  );
                  expect(f.preferences.getString('habits'), f.stored);
                  expect(tester.takeException(), isNull);
                }
                final flexSwitch = find.descendant(
                  of: find
                      .ancestor(
                        of: find.text(I18n.tr('habit.flex.rule')),
                        matching: find.byType(Row),
                      )
                      .first,
                  matching: find.byType(Switch),
                );
                await _reveal(tester, flexSwitch, sheet: true);
                await tester.tap(flexSwitch);
                await tester.pumpAndSettle();
                await _reveal(
                  tester,
                  find.byType(SegmentedButton<HabitFlexPeriod>),
                  sheet: true,
                );
                for (final key in ['habit.flex.weekly', 'habit.flex.monthly']) {
                  _expectComplete(tester, I18n.tr(key), layout.scaler);
                }
                await tester.tap(find.text(I18n.tr('habit.flex.monthly')));
                await tester.pumpAndSettle();
                await tester.enterText(_field('habit.flex.period_target'), '4');
                FocusManager.instance.primaryFocus?.unfocus();
                await tester.pumpAndSettle();
                await _capture(tester, f.boundary, '$name-flex');
                for (final key in [
                  'habit.kind.negative',
                  'habit.kind.positive',
                ]) {
                  final kindChoice = find.widgetWithText(
                    ChoiceChip,
                    I18n.tr(key),
                  );
                  await _reveal(tester, kindChoice, sheet: true);
                  await tester.tap(kindChoice);
                  await tester.pumpAndSettle();
                  expect(
                    tester.widget<ChoiceChip>(kindChoice).selected,
                    isTrue,
                  );
                  expect(tester.widget<Switch>(flexSwitch).value, isFalse);
                  expect(
                    find.byType(SegmentedButton<HabitFlexPeriod>),
                    findsNothing,
                  );
                }
                await _reveal(tester, flexSwitch, sheet: true);
                await tester.tap(flexSwitch);
                await tester.pumpAndSettle();
                expect(
                  tester
                      .widget<SegmentedButton<HabitFlexPeriod>>(
                        find.byType(SegmentedButton<HabitFlexPeriod>),
                      )
                      .selected,
                  {HabitFlexPeriod.month},
                );
                expect(
                  tester
                      .widget<TextField>(_field('habit.flex.period_target'))
                      .controller!
                      .text,
                  '4',
                );
                await _reveal(
                  tester,
                  find.byType(HabitDateRangeFields),
                  sheet: true,
                );
                await _capture(tester, f.boundary, '$name-dates');
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                expect(
                  tester
                      .widget<SegmentedButton<HabitFlexPeriod>>(
                        find.byType(SegmentedButton<HabitFlexPeriod>),
                      )
                      .selected,
                  {HabitFlexPeriod.month},
                );
                expect(f.habits.habits.single.name, f.original.name);
                expect(f.preferences.getString('habits'), f.stored);
                final action = locale == AppLocale.en
                    ? find.widgetWithText(FilledButton, I18n.tr('action.save'))
                    : find.widgetWithText(TextButton, I18n.tr('action.cancel'));
                await _reveal(tester, action, sheet: true);
                await tester.tap(action);
                await tester.pumpAndSettle();
                expect(find.byType(AppModalSheet), findsNothing);
                expect(
                  tester.state(find.byType(HabitDetailScreen)),
                  same(f.routeState),
                );
                if (locale == AppLocale.en) {
                  final saved = f.habits.habits.single;
                  expect(saved.name, 'Draft habit 用户草稿');
                  expect(saved.category, 'Literal category 原分组');
                  expect(saved.flexPeriod, HabitFlexPeriod.month);
                  expect(saved.flexTarget, 4);
                  expect(saved.unit, isNull);
                  final stored =
                      (jsonDecode(f.preferences.getString('habits')!) as List)
                              .single
                          as Map;
                  expect(stored['name'], saved.name);
                  expect(stored['flexTarget'], 4);
                } else {
                  expect(f.habits.habits.single.toJson(), f.persisted);
                  expect(f.preferences.getString('habits'), f.stored);
                }
              }
              expect(tester.takeException(), isNull);
              await tester.pageBack();
              await tester.pumpAndSettle();
              expect(find.text('Open habit'), findsOneWidget);
            } finally {
              await f.close(tester);
            }
          });
        }
      }
    }
  }
}

class _Fixture {
  final habits = HabitProvider()..scheduler = RecordingReminderScheduler();
  final theme = ThemeProvider();
  final boundary = GlobalKey();
  final today = DateTime.now();
  late final Habit original;
  late final SharedPreferences preferences;
  late final String? stored;
  late final Map<String, dynamic> persisted;
  late final State routeState;
  late final bool shadows;

  Future<void> open(
    WidgetTester tester,
    String brand,
    AppLocale locale,
    Size size,
    TextScaler scaler,
  ) async {
    SharedPreferences.setMockInitialValues({'active_brand': brand});
    I18n.setLocale(locale);
    shadows = debugDisableShadows;
    debugDisableShadows = false;
    original = Habit(
      id: 'habit/theme-object',
      name: 'Literal habit 用户习惯',
      targetCount: 8,
      completions: {HeatmapCalendarWindow.dateKey(today): 2},
      startDate: DateTime(2026, 1, 1),
    );
    await habits.addHabit(original);
    await theme.loadFromStorage();
    preferences = await SharedPreferences.getInstance();
    stored = preferences.getString('habits');
    persisted =
        jsonDecode(jsonEncode(habits.habits.single.toJson()))
            as Map<String, dynamic>;
    await tester.runAsync(() async {
      await loadWeeklyReviewScreenshotFonts(
        emojiFontPath:
            'evidence/widget-detail-theme-20261020/fonts/NotoColorEmoji.ttf',
      );
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => TodayDetailRouter.open(
                    context,
                    TodaySectionKind.habits,
                    id: original.id,
                  ),
                  child: const Text('Open habit'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open habit'));
    await tester.pumpAndSettle();
    expect(find.byType(BrandRouteSurface), findsOneWidget);
    routeState = tester.state(find.byType(HabitDetailScreen));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    habits.dispose();
    theme.dispose();
    tester.view.reset();
    debugDisableShadows = shadows;
    I18n.setLocale(AppLocale.zh);
  }
}

Finder _field(String key) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == I18n.tr(key),
);

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  bool sheet = false,
}) async {
  final scroll = find
      .descendant(
        of: find.byType(sheet ? AppModalSheet : HabitDetailScreen),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  for (var step = 0; step < 100 && target.evaluate().isEmpty; step++) {
    await tester.drag(scroll, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

void _expectOverviewCopy(WidgetTester tester, TextScaler scaler) {
  for (final key in [
    'habit.stat.current_streak',
    'habit.stat.best_streak',
    'habit.stat.today',
  ]) {
    _expectComplete(tester, I18n.tr(key), scaler);
  }
  _expectComplete(
    tester,
    I18n.current == AppLocale.en ? '0 days' : '0天',
    scaler,
  );
  _expectComplete(tester, '2/8', scaler);
}

void _expectComplete(WidgetTester tester, String text, TextScaler scaler) {
  final finder = find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == text,
  );
  expect(finder, findsWidgets, reason: text);
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    if (HabitTrendWindow.values
        .map(localizedHabitTrendWindowLabel)
        .contains(text)) {
      final themeStyle = Theme.of(element).textTheme.labelLarge!;
      expect(
        paragraph.text.style?.fontFamily,
        themeStyle.fontFamily,
        reason: 'Trend controls must inherit theme typography',
      );
      expect(
        paragraph.text.style?.fontFamilyFallback,
        themeStyle.fontFamilyFallback,
      );
      expect(paragraph.text.style?.fontSize, 12);
      expect(paragraph.text.style?.fontWeight, FontWeight.normal);
    }
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
    )..layout(maxWidth: paragraph.size.width);
    if (HabitTrendWindow.values
        .map(localizedHabitTrendWindowLabel)
        .contains(text)) {
      expect(
        painter.computeLineMetrics(),
        hasLength(1),
        reason:
            'Trend windows must stay readable without splitting words: $text',
      );
    }
    expect(
      painter.didExceedMaxLines,
      isFalse,
      reason: 'Complete Habit label: $text',
    );
    expect(
      painter.height,
      lessThanOrEqualTo(paragraph.size.height + 0.5),
      reason: text,
    );
    for (final font in [11.0, 14.0]) {
      expect(
        paragraph.textScaler.scale(font),
        closeTo(scaler.scale(font), 0.01),
      );
    }
    expect(paragraph.text.style?.fontSize, greaterThanOrEqualTo(11));
    painter.dispose();
  }
}

void _expectBucketCopy(
  WidgetTester tester,
  Habit habit,
  DateTime today,
  TextScaler scaler,
) {
  final summary = buildHabitTrendSummary(
    habit,
    window: HabitTrendWindow.days90,
    today: today,
  );
  final unit = habitUnit(habit, I18n.current, summary.averageCount);
  for (final bucket in summary.buckets) {
    _expectComplete(tester, bucket.label, scaler);
    _expectComplete(
      tester,
      '${bucket.completedDays}/${bucket.activeDays} · ${bucket.totalCount} $unit',
      scaler,
    );
  }
}

class _HabitScaler extends TextScaler {
  const _HabitScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 14 ? 1.9 : 1.6);
  @override
  double get textScaleFactor => 1;
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_HABIT_THEME'] != '1') return;
  if (Platform.environment['DUOYI_HABIT_OVERVIEW_ONLY'] == '1' &&
      !name.endsWith('-overview') &&
      !name.endsWith('-overview-switched')) {
    return;
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final run = Platform.environment['DUOYI_HABIT_THEME_RUN'] ?? 'current';
    final file = File(
      'evidence/screenshots/widget-habit-theme-20261020/$run/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    if (name.endsWith('-trend')) {
      final texts = <Map<String, Object?>>[];
      for (final e in find.byType(RichText).evaluate()) {
        final widget = e.widget as RichText;
        if ([
          '14天',
          '30天',
          '90天',
          '一年',
          '14 days',
          '30 days',
          '90 days',
          '1 year',
        ].contains(widget.text.toPlainText())) {
          texts.add({
            'text': widget.text.toPlainText(),
            'span': widget.text.toStringDeep(),
            'scaler': widget.textScaler.toString(),
          });
        }
      }
      File('${file.path}.text.json').writeAsStringSync(jsonEncode(texts));
    }
  });
}
