import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/calendar_month_grid.dart';
import 'package:duoyi/widgets/calendar_week_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final parts in [
    [2021, 2],
    [2026, 2],
    [2026, 5],
  ]) {
    testWidgets(
      'month ${parts.join('-')} keeps all dates in four/five/six-row layouts',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          for (final first in [1, 7]) {
            final month = DateTime.utc(parts[0], parts[1]);
            final days = DateTime.utc(parts[0], parts[1] + 1, 0).day;
            final offset = (month.weekday - first) % 7;
            final grid = CalendarMonthGrid(
              focusedMonth: month,
              selectedDay: DateTime(parts[0], parts[1], 17),
              dateEventTypes: const {},
              showLunar: false,
              firstDayOfWeek: first,
              onDaySelected: (_) {},
            );
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(body: SizedBox(height: 308, child: grid)),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.descendant(
                of: find.byType(CalendarMonthGrid),
                matching: find.text('$days'),
              ),
              findsOneWidget,
            );
            final day1 = find.descendant(
              of: find.byType(CalendarMonthGrid),
              matching: find.text('1'),
            );
            final dayLast = find.descendant(
              of: find.byType(CalendarMonthGrid),
              matching: find.text('$days'),
            );
            final gridRect = tester.getRect(find.byType(CalendarMonthGrid));
            final contentWidth = gridRect.width - 12;
            expect(
              tester.getCenter(day1).dx,
              closeTo(
                gridRect.left + 6 + contentWidth * ((offset + .5) / 7),
                2,
              ),
            );
            expect(tester.getCenter(dayLast).dy, lessThan(gridRect.bottom));
            final rows = ((offset + days) / 7).ceil();
            expect(rows, inInclusiveRange(4, 6));
          }
        }
      },
    );
  }

  testWidgets(
    'date sheet inherits a page-local preference and updates while open',
    (tester) async {
      final prefs = PreferencesProvider();
      addTearDown(prefs.dispose);
      await tester.runAsync(prefs.loadFromStorage);
      await tester.runAsync(() => prefs.setFirstDayOfWeek(7));
      Future<AppDatePickerResult?>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<PreferencesProvider>.value(
            value: prefs,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => result = AppDatePicker.show(
                    context,
                    initialDate: DateTime(2024, 9, 4),
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2025),
                  ),
                  child: const Text('Open calendar'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open calendar'));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('solar-day-2024-09-01'));
      expect(first, findsOneWidget);
      expect(
        tester.getCenter(first).dx,
        lessThan(tester.getCenter(find.text('日')).dx + 2),
      );
      final sundayX = tester.getCenter(first).dx;
      await tester.runAsync(() => prefs.setFirstDayOfWeek(1));
      await tester.pumpAndSettle();
      expect(tester.getCenter(first).dx, greaterThan(sundayX + 200));
      expect(tester.takeException(), isNull);
      final confirm = find.text(I18n.tr('action.confirm'));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(tester.getCenter(confirm).dy, lessThan(600));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect((await result)!.date, DateTime(2024, 9, 4));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in AppLocale.values) {
    testWidgets(
      '${locale.name} calendar previews follow saved week start at narrow sizes',
      (tester) async {
        I18n.setLocale(locale);
        final capture =
            Platform.environment['DUOYI_CAPTURE_WIDGET_LOCALE_SCREENSHOTS'] ==
            '1';
        if (capture) await tester.runAsync(loadWidgetPolishScreenshotFonts);
        await tester.binding.setSurfaceSize(const Size(320, 620));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final prefs = PreferencesProvider();
        addTearDown(prefs.dispose);
        final themeProvider = ThemeProvider();
        addTearDown(themeProvider.dispose);
        final theme = themeProvider.brand.theme;
        final fonts = theme.textTheme.apply(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        );
        await tester.runAsync(prefs.loadFromStorage);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PreferencesProvider>.value(value: prefs),
              ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final mode in WidgetDisplayMode.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: WidgetPreviewCard.calendar(
                            displayMode: mode,
                            platformOverride: TargetPlatform.android,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        for (final first in [1, 7]) {
          await tester.runAsync(() => prefs.setFirstDayOfWeek(first));
          await tester.pumpAndSettle();
          final standard = find.byType(WidgetPreviewCard).at(1);
          final text = tester
              .widgetList<Text>(
                find.descendant(of: standard, matching: find.byType(Text)),
              )
              .map((t) => t.data)
              .whereType<String>()
              .toList();
          final label = locale == AppLocale.zh
              ? (first == 1 ? '一' : '日')
              : (first == 1 ? 'M' : 'S');
          final headerIndex = text.indexOf(label);
          expect(headerIndex, greaterThanOrEqualTo(0));
          expect(
            text.sublist(headerIndex, headerIndex + 7),
            locale == AppLocale.zh
                ? (first == 1
                      ? ['一', '二', '三', '四', '五', '六', '日']
                      : ['日', '一', '二', '三', '四', '五', '六'])
                : (first == 1
                      ? ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      : ['S', 'M', 'T', 'W', 'T', 'F', 'S']),
          );
          expect(tester.takeException(), isNull);
          if (capture) {
            await _save(tester, boundaryKey, '${locale.name}-previews-$first');
            await tester.ensureVisible(find.byType(WidgetPreviewCard).last);
            await tester.pumpAndSettle();
            await _save(
              tester,
              boundaryKey,
              '${locale.name}-previews-$first-bottom',
            );
            await tester.drag(find.byType(ListView), const Offset(0, 1000));
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('Sunday week retains disabled year-boundary cells', (
    tester,
  ) async {
    final provider = CalendarProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarWeekStrip(
            selectedDay: DateTime(1, 1, 1),
            dateEventTypes: const {},
            calendarProvider: provider,
            firstDayOfWeek: 7,
            onDaySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final unavailable = find.byKey(
      const ValueKey('calendar_week_unavailable_0'),
    );
    expect(unavailable, findsOneWidget);
    final semantics = tester.widget<Semantics>(unavailable);
    expect(semantics.properties.enabled, isFalse);
    expect(semantics.properties.button, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final base = Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR']!;
      final file = File('$base/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
