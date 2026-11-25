import '../support/habit_public_text_bounds.dart';
import 'dart:math' as math;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart' show AppSurfaceCard;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

// Same continuous monotone curve as frozen NEW2368; no private layout helper.
class _RingNonlinearScaler extends TextScaler {
  const _RingNonlinearScaler();
  @override
  double scale(double fontSize) {
    if (fontSize <= 10) return 2.4 * fontSize;
    if (fontSize <= 13) return 24 + .6 * (fontSize - 10);
    return 25.8 + 1.4 * (fontSize - 13);
  }
  @override
  double get textScaleFactor => 1;
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Future<void> _host(WidgetTester tester, Future<void> Function() action) async {
  final done = await tester.runAsync(() async {
    await action().timeout(const Duration(seconds: 20));
    return true;
  });
  expect(done, isTrue, reason: 'bounded provider/font setup completed');
}

Finder _todayScroll() => find.descendant(
  of: find.byKey(const ValueKey('habit_today_scroll_view')),
  matching: find.byType(Scrollable),
).first;

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final position = tester.state<ScrollableState>(_todayScroll()).position;
  position.jumpTo(position.minScrollExtent);
  await _settle(tester);
  await tester.scrollUntilVisible(
    target, 160, scrollable: _todayScroll(), maxScrolls: 60,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .05);
  await _settle(tester);
}

Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(
  box.getTransformTo(null), Offset.zero & box.size,
);

Rect _viewport(WidgetTester tester, Finder finder) {
  final viewport = RenderAbstractViewport.maybeOf(
    tester.renderObject<RenderBox>(finder),
  );
  if (viewport is! RenderBox) {
    throw TestFailure('summary must belong to a box viewport');
  }
  return _globalRect(viewport as RenderBox);
}

void _contained(Rect inner, Rect outer, String reason) {
  expect(inner.width, greaterThan(0), reason: reason);
  expect(inner.height, greaterThan(0), reason: reason);
  expect(inner.left, greaterThanOrEqualTo(outer.left - .5), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top - .5), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + .5), reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .5), reason: reason);
}

List<Offset> _corners(Rect rect) => [
  rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight,
];

void _unitTransform(RenderBox box, String reason) {
  final origin = box.localToGlobal(Offset.zero);
  final x = box.localToGlobal(const Offset(1, 0)) - origin;
  final y = box.localToGlobal(const Offset(0, 1)) - origin;
  expect(x.dx, closeTo(1, .001), reason: reason);
  expect(x.dy, closeTo(0, .001), reason: reason);
  expect(y.dx, closeTo(0, .001), reason: reason);
  expect(y.dy, closeTo(1, .001), reason: reason);
}

RenderParagraph _completeText(
  WidgetTester tester, Finder summary, String text,
  TextScaler scaler, double fontSize,
) {
  final finder = find.descendant(of: summary, matching: find.text(text));
  expect(finder, findsOneWidget, reason: 'full literal remains: $text');
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.text.style?.fontSize, fontSize, reason: text);
  expect(paragraph.textScaler.scale(fontSize),
    closeTo(scaler.scale(fontSize), .001), reason: 'real scaler: $text');
  expect(paragraph.didExceedMaxLines, isFalse, reason: text);
  expect(paragraph.maxLines, isNull, reason: text);
  expect(paragraph.overflow, isNot(TextOverflow.ellipsis), reason: text);
  _unitTransform(paragraph, 'no shrink/rotation/shear: $text');
  _contained(_globalRect(paragraph), tester.getRect(summary), '$text in card');
  _contained(_globalRect(paragraph), _viewport(tester, finder), '$text visible');
  expectHabitTextPaintBounds(
    paragraph, cardRect: tester.getRect(summary),
    viewportRect: _viewport(tester, finder), reason: 'full visible text: $text',
  );
  expect(
    tester.getSemantics(finder).getSemanticsData().label,
    contains(text), reason: 'full accessible copy: $text',
  );
  return paragraph;
}

double _distanceToRect(Offset point, Rect rect) {
  final dx = math.max(math.max(rect.left - point.dx, point.dx - rect.right), 0.0);
  final dy = math.max(math.max(rect.top - point.dy, point.dy - rect.bottom), 0.0);
  return Offset(dx, dy).distance;
}

void _actualRingGeometry(
  WidgetTester tester, Finder summary, RenderParagraph paragraph,
) {
  final indicatorFinder = find.descendant(
    of: summary, matching: find.byType(CircularProgressIndicator),
  );
  expect(indicatorFinder, findsOneWidget);
  final indicator = tester.widget<CircularProgressIndicator>(indicatorFinder);
  expect(indicator.value, 1, reason: 'actual CPI represents 100 percent');
  final theme = Theme.of(tester.element(indicatorFinder));
  final profile = ProgressIndicatorTheme.of(tester.element(indicatorFinder));
  final stroke = indicator.strokeWidth ?? profile.strokeWidth ?? 4.0;
  expect(stroke, 4, reason: 'this fix owns the original 4px stroke');
  // Mirror the installed CPI appearance choice when measuring its actual paint.
  // ignore: deprecated_member_use
  final year2023 = indicator.year2023 ?? profile.year2023 ?? true;
  final align = indicator.strokeAlign ?? profile.strokeAlign ??
      (theme.useMaterial3 && !year2023
          ? CircularProgressIndicator.strokeAlignInside
          : CircularProgressIndicator.strokeAlignCenter);
  final paintFinder = find.descendant(
    of: indicatorFinder, matching: find.byType(CustomPaint),
  );
  expect(paintFinder, findsOneWidget);
  final canvas = tester.renderObject<RenderCustomPaint>(paintFinder);
  expect(canvas.painter, isNotNull);
  expect(canvas.size.width, greaterThan(0));
  expect(canvas.size.width, closeTo(canvas.size.height, .001));
  _unitTransform(canvas, 'actual ring paint is not scaled');
  _contained(_globalRect(canvas), tester.getRect(summary), 'paint canvas in card');
  _contained(_globalRect(canvas), _viewport(tester, paintFinder), 'paint visible');

  // Use the actual CustomPaint canvas, after effective indicator padding.
  // Public strokeAlign resolves the same symmetric arc inset as the SDK:
  // arc size = canvas size - 2 * (stroke / 2 * -align).
  final strokeOffset = stroke / 2 * -align;
  final arcWidth = canvas.size.width - 2 * strokeOffset;
  final arcHeight = canvas.size.height - 2 * strokeOffset;
  expect(arcWidth, greaterThan(0));
  expect(arcHeight, greaterThan(0));
  final center = Offset(canvas.size.width / 2, canvas.size.height / 2);
  final centerlineRadius = math.min(arcWidth, arcHeight) / 2;
  const aaMargin = 2.0;
  final safeInnerRadius = centerlineRadius - stroke / 2 - aaMargin;
  final excludedOuterRadius = centerlineRadius + stroke / 2 + aaMargin;
  expect(safeInnerRadius, greaterThan(0));

  Offset inCanvas(Offset point) =>
      canvas.globalToLocal(paragraph.localToGlobal(point));
  final paragraphCorners = _corners(Offset.zero & paragraph.size)
      .map(inCanvas).toList();
  final fullParagraph = Rect.fromPoints(
    paragraphCorners[0], paragraphCorners[3],
  );
  final text = paragraph.text.toPlainText();
  final selection = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  expect(selection, isNotEmpty);
  final selectionCorners = <Offset>[
    for (final box in selection) ..._corners(box.toRect()).map(inCanvas),
  ];
  final inside = [
    ...paragraphCorners, ...selectionCorners,
  ].every((point) => (point - center).distance <= safeInnerRadius + .001);
  // Testing only rectangle corners outside a circle can miss a crossing edge.
  // The nearest point of the complete paragraph rectangle must clear the
  // whole outer stroke+AA circle; selection rectangles must also clear it.
  final outside = _distanceToRect(center, fullParagraph) >=
          excludedOuterRadius + .001 &&
      selection.every((box) {
        final points = _corners(box.toRect()).map(inCanvas).toList();
        return _distanceToRect(center, Rect.fromPoints(points[0], points[3])) >=
            excludedOuterRadius + .001;
      });
  expect(
    inside || outside, isTrue,
    reason: 'complete 100% must fit the actual safe circle or clear the stroke: '
        'canvas=${canvas.size}, stroke=$stroke, align=$align, '
        'safe=$safeInnerRadius, outer=$excludedOuterRadius, '
        'paragraph=$fullParagraph, selection=$selectionCorners',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (scalerName, scaler) in <(String, TextScaler)>[
    ('linear100', TextScaler.linear(1)),
    ('nonlinear', const _RingNonlinearScaler()),
  ]) {
    for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        testWidgets(
          'Habit ring geometry $scalerName/${brand.id}/${locale.name}/320x844',
          (tester) async {
            final oldLocale = I18n.current;
            I18n.setLocale(locale);
            addTearDown(() => I18n.setLocale(oldLocale));
            SharedPreferences.setMockInitialValues({
              'active_brand': brand.id,
              'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            });
            tester.view.physicalSize = const Size(320, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final semantics = tester.ensureSemantics();
            var semanticsDisposed = false;
            addTearDown(() {
              if (!semanticsDisposed) {
                semanticsDisposed = true;
                semantics.dispose();
              }
            });
            late TimeAuditProvider audit;
            late HabitProvider habits;
            late ThemeProvider theme;
            late AuthProvider auth;
            await _host(tester, () async {
              audit = TimeAuditProvider();
              habits = HabitProvider()
                ..timeAudit = audit
                ..scheduler = RecordingReminderScheduler();
              theme = ThemeProvider();
              auth = AuthProvider();
              addTearDown(() {
                habits.dispose(); audit.dispose(); theme.dispose(); auth.dispose();
              });
              await theme.loadFromStorage();
              await habits.loadFromStorage();
              await audit.loadFromStorage();
              final now = DateTime.now();
              final day = DateTime(now.year, now.month, now.day);
              for (var index = 0; index < 3; index++) {
                final habit = Habit(
                  id: 'ring-$index', name: 'Ring fixture $index',
                  targetCount: 1, currentStreak: 7, bestStreak: 7,
                  startDate: day.subtract(const Duration(days: 14)),
                  sortOrder: index,
                );
                for (var back = 0; back < 7; back++) {
                  habit.completions[habit.dateKey(
                    day.subtract(Duration(days: back)),
                  )] = 1;
                }
                await habits.addHabit(habit);
              }
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await _settle(tester);
            });
            expect(habits.habits, hasLength(3));
            expect(habits.habits.every((habit) => habit.isCompletedToday()), isTrue);
            expect(habits.todayOverallProgress, 1);
            expect(habits.longestCurrentStreak, 7);
            expect(theme.brand.id, brand.id);
            await _host(tester, loadWeeklyReviewScreenshotFonts);
            await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider<HabitProvider>.value(value: habits),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ],
              child: MaterialApp(
                locale: locale.flutterLocale,
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: scaler),
                  child: child!,
                ),
                home: const BrandBackground(child: HabitScreen()),
              ),
            ));
            await _settle(tester);
            final strings = theme.brand.strings;
            final completedLabel = find.text('3 / 3 ${strings.habitTodayDone}');
            await _reveal(tester, completedLabel);
            expect(completedLabel, findsOneWidget);
            final summary = find.ancestor(
              of: completedLabel, matching: find.byType(AppSurfaceCard),
            ).first;
            expect(summary, findsOneWidget);
            final percentFinder = find.descendant(
              of: summary, matching: find.text('100%'),
            );
            expect(percentFinder, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(summary), alignment: .05);
            await _settle(tester);
            final percent = _completeText(tester, summary, '100%', scaler, 10);
            expect(percent.text.style?.fontWeight, FontWeight.w400);
            _completeText(
              tester, summary, '3 / 3 ${strings.habitTodayDone}', scaler, 13,
            );
            _completeText(
              tester, summary,
              '${strings.habitStreakLabel} 7 ${I18n.tr('unit.day')}',
              scaler, 11,
            );
            _actualRingGeometry(tester, summary, percent);
            expect(habits.todayOverallProgress, 1);
            expect(habits.habits, hasLength(3));
            expect(tester.takeException(), isNull);
            semanticsDisposed = true;
            semantics.dispose();
          },
        );
      }
    }
  }
}

