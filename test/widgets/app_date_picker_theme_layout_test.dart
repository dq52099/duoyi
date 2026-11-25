import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _layouts = [
  (name: '320-normal', size: Size(320, 844), scaler: TextScaler.linear(1)),
  (name: '320-large', size: Size(320, 844), scaler: TextScaler.linear(1.6)),
  (name: '390-double', size: Size(390, 844), scaler: TextScaler.linear(2)),
  (name: '568-landscape', size: Size(568, 320), scaler: TextScaler.linear(1.6)),
  (
    name: '332-nonlinear',
    size: Size(332, 844),
    scaler: _PickerNonlinearScaler(),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final summary in [true, false]) {
      _pickerTest(
        'date picker ${summary ? 'full lunar summary' : 'weekday gutters'} $brand',
        (tester) async {
          final fixture = await _mount(tester, brand);
          try {
            await fixture.capture(
              tester,
              '$brand-${summary ? 'summary' : 'weekdays'}',
            );
            if (summary) {
              _expectSummary(tester);
            } else {
              _expectWeekdayGutters(tester);
            }
          } finally {
            await fixture.close(tester);
          }
        },
      );
    }
    for (final layout in _layouts) {
      for (final firstDay in [1, 7]) {
        final name = '$brand-${layout.name}-start$firstDay';
        _pickerTest('date picker retained layout and actions $name', (
          tester,
        ) async {
          final fixture = await _mount(
            tester,
            brand,
            size: layout.size,
            scaler: layout.scaler,
            firstDay: firstDay,
          );
          try {
            final sheetState = tester.state(_sheet());
            final day = find.byKey(const ValueKey('solar-day-2026-05-21'));
            await _reveal(tester, day);
            expect(day.hitTestable(), findsOneWidget);
            await tester.tap(day);
            await tester.pumpAndSettle();
            for (final locale in [AppLocale.en, AppLocale.zh]) {
              I18n.setLocale(locale);
              await tester.pumpAndSettle();
              expect(tester.state(_sheet()), same(sheetState));
              expect(find.byType(AppModalSheet), findsOneWidget);
              final summary = _summaryText(DateTime(2026, 5, 21));
              await _reveal(tester, find.text(summary));
              _expectSummary(tester, date: DateTime(2026, 5, 21));
              _expectGlyphsInViewport(tester, find.text(summary));
              await fixture.capture(tester, '$name-${locale.name}-summary');
              _expectWeekdayGutters(tester, firstDay: firstDay);
              final order = firstDay == 1
                  ? ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
                  : ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
              for (final key in order) {
                final label = find.text(I18n.tr('picker.weekday.$key'));
                await _reveal(tester, label);
                _expectGlyphsInViewport(tester, label);
              }
              // Weekdays and dates share the same column coordinate even if
              // the whole enlarged calendar needs horizontal scrolling.
              final thursday = find.text(I18n.tr('picker.weekday.thu'));
              expect(
                tester.getCenter(day).dx,
                closeTo(tester.getCenter(thursday).dx, 1),
              );
              await fixture.capture(tester, '$name-${locale.name}-calendar');
              expect(tester.takeException(), isNull);
            }
            await _action(tester, 'action.confirm');
            final confirmed = await fixture.result;
            expect(confirmed?.date, DateTime(2026, 5, 21));
            expect(confirmed?.mode, AppDatePickerMode.solar);
            expect(find.byType(AppModalSheet), findsNothing);
            await tester.tap(find.text('Open picker'));
            await tester.pumpAndSettle();
            final other = find.byKey(const ValueKey('solar-day-2026-05-22'));
            await _reveal(tester, other);
            await tester.tap(other);
            await tester.pumpAndSettle();
            await _action(tester, 'action.cancel');
            expect(await fixture.result, isNull);
            expect(find.byType(AppModalSheet), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.close(tester);
          }
        });
      }
    }
  }
}

String _summaryText(DateTime date) =>
    AppDatePickerResult(date: date, mode: AppDatePickerMode.solar).lunarText;

void _expectSummary(WidgetTester tester, {DateTime? date}) {
  final value = _summaryText(date ?? DateTime(2026, 5, 19));
  final text = find.text(value);
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'The selected date lunar summary must be fully readable: $value',
  );
  expect(tester.widget<Text>(text).overflow, isNot(TextOverflow.ellipsis));
}

void _expectWeekdayGutters(WidgetTester tester, {int firstDay = 1}) {
  final keys = firstDay == 1
      ? ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
      : ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
  Rect? previous;
  for (final key in keys) {
    final value = I18n.tr('picker.weekday.$key');
    final text = find.text(value);
    expect(text, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: value.length),
    );
    expect(boxes, hasLength(1));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.textScaler.scale(13),
      MediaQuery.textScalerOf(tester.element(text)).scale(13),
    );
    final origin = paragraph.localToGlobal(Offset.zero);
    final unit = paragraph.localToGlobal(const Offset(1, 0));
    expect(
      unit.dx - origin.dx,
      closeTo(1, 0.001),
      reason: 'Weekday text must not be geometrically scaled down',
    );
    final bounds = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      boxes.single.toRect(),
    );
    if (previous != null) {
      expect(
        bounds.left - previous.right,
        greaterThanOrEqualTo(4 - 0.1),
        reason:
            'Adjacent weekday glyphs must retain a visible gutter before $value',
      );
    }
    previous = bounds;
  }
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String brand, {
  Size size = const Size(320, 844),
  TextScaler scaler = const TextScaler.linear(1.6),
  int firstDay = 1,
}) async {
  final shadows = debugDisableShadows;
  SharedPreferences.setMockInitialValues({
    'active_brand': brand,
    'pref_first_day_of_week': firstDay,
  });
  final theme = ThemeProvider();
  final prefs = PreferencesProvider();
  await theme.loadFromStorage();
  await tester.runAsync(prefs.loadFromStorage);
  I18n.setLocale(AppLocale.en);
  await tester.runAsync(loadWeeklyReviewScreenshotFonts);
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final boundary = GlobalKey();
  final fixture = _Fixture(theme, prefs, boundary, shadows);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<PreferencesProvider>.value(value: prefs),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.brand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: BrandRouteSurface(
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () {
                    fixture.result = AppDatePicker.show(
                      context,
                      initialDate: DateTime(2026, 5, 19),
                      firstDate: DateTime(2026),
                      lastDate: DateTime(2027),
                    );
                  },
                  child: const Text('Open picker'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
  expect(find.byType(AppModalSheet), findsOneWidget);
  expect(tester.takeException(), isNull);
  return fixture;
}

class _Fixture {
  final ThemeProvider theme;
  final PreferencesProvider preferences;
  final GlobalKey boundary;
  final bool oldShadows;
  Future<AppDatePickerResult?>? result;
  _Fixture(this.theme, this.preferences, this.boundary, this.oldShadows);

  Future<void> capture(WidgetTester tester, String name) async {
    final run = Platform.environment['DUOYI_DATE_PICKER_CAPTURE'];
    if (run == null) return;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await render.toImage();
      try {
        final data = await picture.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'evidence/screenshots/date-picker-theme-20261020/$run/$name.png',
        );
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        picture.dispose();
      }
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    theme.dispose();
    preferences.dispose();
    I18n.setLocale(AppLocale.zh);
    debugDisableShadows = oldShadows;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Finder _sheet() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_AppDatePickerSheet',
);

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, String key) async {
  final target = find.text(I18n.tr(key));
  await _reveal(tester, target);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectGlyphsInViewport(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final view =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  )) {
    final bounds = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      box.toRect(),
    );
    expect(bounds.left, greaterThanOrEqualTo(view.left - 0.1));
    expect(bounds.right, lessThanOrEqualTo(view.right + 0.1));
    expect(bounds.top, greaterThanOrEqualTo(view.top - 0.1));
    expect(bounds.bottom, lessThanOrEqualTo(view.bottom + 0.1));
  }
}

class _PickerNonlinearScaler extends TextScaler {
  const _PickerNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize < 10 ? fontSize : fontSize * 1.6;
  @override
  double get textScaleFactor => 1;
}

// Restore test-global state before Flutter checks invariants even if mounting
// fails before the fixture is returned to the caller.
void _pickerTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final shadows = debugDisableShadows;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = shadows;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      I18n.setLocale(AppLocale.zh);
    }
  });
}
