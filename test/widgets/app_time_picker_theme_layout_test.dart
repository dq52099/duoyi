import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerLayoutMatrix();
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final wheel in [false, true]) {
      testWidgets(
        'time picker ${wheel ? 'wheel room' : 'natural shortcut text'} $brand',
        (tester) async {
          final shadows = debugDisableShadows;
          final theme = ThemeProvider();
          final preferences = PreferencesProvider();
          try {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(AppLocale.en);
            debugDisableShadows = false;
            await theme.loadFromStorage();
            expect(theme.brand.id, brand);
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            tester.view.physicalSize = const Size(320, 844);
            tester.view.devicePixelRatio = 1;
            final boundary = GlobalKey();
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: preferences,
                  ),
                ],
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: BrandRouteSurface(
                    child: Scaffold(
                      body: Builder(
                        builder: (context) => Center(
                          child: TextButton(
                            onPressed: () => AppTimePicker.show(
                              context,
                              initialTime: const TimeOfDay(hour: 9, minute: 13),
                            ),
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
            final target = wheel
                ? find.byType(ListWheelScrollView).first
                : find.text(I18n.tr('picker.time.earlier_30m'));
            await Scrollable.ensureVisible(
              tester.element(target),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            final capture = Platform.environment['DUOYI_TIME_PICKER_CAPTURE'];
            if (capture != null) {
              await tester.runAsync(() async {
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final picture = await render.toImage();
                try {
                  final bytes = await picture.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    'evidence/screenshots/time-picker-theme-20261020/$capture/$brand-${wheel ? 'wheel' : 'shortcuts'}.png',
                  );
                  file.parent.createSync(recursive: true);
                  file.writeAsBytesSync(bytes!.buffer.asUint8List());
                } finally {
                  picture.dispose();
                }
              });
            }
            if (wheel) {
              for (final element
                  in find.byType(ListWheelScrollView).evaluate()) {
                final view = element.widget as ListWheelScrollView;
                final paragraphs = find.descendant(
                  of: find.byWidget(view),
                  matching: find.byType(RichText),
                );
                expect(paragraphs, findsWidgets);
                final paragraph = tester.renderObject<RenderParagraph>(
                  paragraphs.first,
                );
                // Measure the natural line rather than its already constrained box.
                final painter = TextPainter(
                  text: paragraph.text,
                  textDirection: paragraph.textDirection,
                  textScaler: paragraph.textScaler,
                )..layout();
                try {
                  expect(
                    view.itemExtent,
                    greaterThanOrEqualTo(painter.height + 8),
                    reason:
                        'Each wheel row needs the scaled glyph height and breathing room',
                  );
                } finally {
                  painter.dispose();
                }
              }
            } else {
              for (final key in ['earlier_30m', 'later_30m']) {
                final label = find.text(I18n.tr('picker.time.$key'));
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: label, matching: find.byType(RichText)),
                );
                final origin = paragraph.localToGlobal(Offset.zero);
                final unit = paragraph.localToGlobal(const Offset(1, 0));
                expect(
                  unit.dx - origin.dx,
                  closeTo(1, 0.001),
                  reason: 'The requested system text size must survive layout',
                );
                expect(paragraph.didExceedMaxLines, isFalse);
              }
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            theme.dispose();
            preferences.dispose();
            I18n.setLocale(AppLocale.zh);
            debugDisableShadows = shadows;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        },
      );
    }
  }
}

void _registerLayoutMatrix() {
  const layouts = [
    (name: '320-normal', size: Size(320, 844), scaler: TextScaler.linear(1)),
    (name: '320-large', size: Size(320, 844), scaler: TextScaler.linear(1.6)),
    (name: '390-double', size: Size(390, 844), scaler: TextScaler.linear(2)),
    (name: '568-landscape', size: Size(568, 320), scaler: TextScaler.linear(2)),
    (
      name: '332-nonlinear',
      size: Size(332, 844),
      scaler: _TimeNonlinearScaler(),
    ),
  ];
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in layouts) {
      final name = '$brand-${layout.name}';
      testWidgets('time picker retained actions and readable layout $name', (
        tester,
      ) async {
        final oldShadows = debugDisableShadows;
        final theme = ThemeProvider();
        final prefs = PreferencesProvider();
        final boundary = GlobalKey();
        Future<TimeOfDay?>? result;
        try {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(AppLocale.en);
          debugDisableShadows = false;
          await theme.loadFromStorage();
          expect(theme.brand.id, brand);
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
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
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: layout.scaler),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: BrandRouteSurface(
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () {
                            result = AppTimePicker.show(
                              context,
                              initialTime: const TimeOfDay(hour: 9, minute: 13),
                              titleKey: 'course.field.first_session_time',
                              subtitleKey:
                                  'course.field.first_session_time_subtitle',
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
          final sheet = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_AppTimePickerSheet',
          );
          final state = tester.state(sheet);
          final wheels = tester
              .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
              .toList();
          final hour = wheels[0].controller! as FixedExtentScrollController;
          final minute = wheels[1].controller! as FixedExtentScrollController;
          expect(hour.selectedItem, 9);
          expect(minute.selectedItem, 3);
          for (final locale in [AppLocale.en, AppLocale.zh]) {
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            expect(tester.state(sheet), same(state));
            final currentWheels = tester
                .widgetList<ListWheelScrollView>(
                  find.byType(ListWheelScrollView),
                )
                .toList();
            expect(currentWheels[0].controller, same(hour));
            expect(currentWheels[1].controller, same(minute));
            final modal = tester.widget<AppModalSheet>(
              find.byType(AppModalSheet),
            );
            expect(modal.title, I18n.tr('course.field.first_session_time'));
            expect(
              modal.subtitle,
              I18n.tr('course.field.first_session_time_subtitle'),
            );
            await _revealTime(
              tester,
              find.text(
                AppTimePicker.format(
                  TimeOfDay(
                    hour: hour.selectedItem,
                    minute: minute.selectedItem * 5,
                  ),
                ),
              ),
            );
            await _captureTime(
              tester,
              boundary,
              '$name-${locale.name}-summary',
            );
            final before = hour.selectedItem * 60 + minute.selectedItem * 5;
            for (final entry in [('earlier_30m', -30), ('later_30m', 30)]) {
              final text = find.text(I18n.tr('picker.time.${entry.$1}'));
              final button = find.ancestor(
                of: text,
                matching: find.byType(OutlinedButton),
              );
              await _revealTime(tester, button);
              _expectTimeLabel(tester, text, button);
              await _captureTime(
                tester,
                boundary,
                '$name-${locale.name}-${entry.$1}',
              );
              await tester.tap(button);
              await tester.pumpAndSettle();
              final expected = (before + (entry.$2 == -30 ? -30 : 0)) % 1440;
              expect(
                hour.selectedItem * 60 + minute.selectedItem * 5,
                expected,
              );
            }
            for (final key in [
              'preset_morning',
              'preset_noon',
              'preset_evening',
              'preset_now',
              'preset_next_slot',
            ]) {
              final text = find.text(I18n.tr('picker.time.$key'));
              final chip = find.ancestor(
                of: text,
                matching: find.byType(ActionChip),
              );
              await _revealTime(tester, chip);
              _expectTimeLabel(tester, text, chip);
            }
            final evening = find.ancestor(
              of: find.text(I18n.tr('picker.time.preset_evening')),
              matching: find.byType(ActionChip),
            );
            await _revealTime(tester, evening);
            await tester.tap(evening);
            await tester.pumpAndSettle();
            expect(hour.selectedItem, 20);
            expect(minute.selectedItem, 0);
            final firstWheel = find.byType(ListWheelScrollView).first;
            await _revealTime(tester, firstWheel);
            for (final wheel in tester.widgetList<ListWheelScrollView>(
              find.byType(ListWheelScrollView),
            )) {
              final p = tester.renderObject<RenderParagraph>(
                find
                    .descendant(
                      of: find.byWidget(wheel),
                      matching: find.byType(RichText),
                    )
                    .first,
              );
              final painter = TextPainter(
                text: p.text,
                textScaler: p.textScaler,
                textDirection: p.textDirection,
              )..layout();
              try {
                expect(
                  wheel.itemExtent,
                  greaterThanOrEqualTo(painter.height + 8),
                );
                expect(
                  tester.getSize(find.byWidget(wheel)).width,
                  greaterThanOrEqualTo(painter.width),
                );
              } finally {
                painter.dispose();
              }
            }
            await _captureTime(tester, boundary, '$name-${locale.name}-wheel');
            // Exercise real wheel gesture/scroll notification selection.
            await tester.drag(
              firstWheel,
              Offset(0, -currentWheels[0].itemExtent),
            );
            await tester.pumpAndSettle();
            expect(hour.selectedItem, isNot(20));
            expect(
              find.text(
                AppTimePicker.format(
                  TimeOfDay(
                    hour: hour.selectedItem,
                    minute: minute.selectedItem * 5,
                  ),
                ),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
          final expected = TimeOfDay(
            hour: hour.selectedItem,
            minute: minute.selectedItem * 5,
          );
          final confirm = find.text(I18n.tr('action.confirm'));
          await _revealTime(tester, confirm);
          await tester.tap(confirm);
          await tester.pumpAndSettle();
          expect(await result, expected);
          expect(find.byType(AppModalSheet), findsNothing);
          await tester.tap(find.text('Open picker'));
          await tester.pumpAndSettle();
          final cancel = find.text(I18n.tr('action.cancel'));
          await _revealTime(tester, cancel);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(await result, isNull);
          expect(find.byType(AppModalSheet), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          theme.dispose();
          prefs.dispose();
          I18n.setLocale(AppLocale.zh);
          debugDisableShadows = oldShadows;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      });
    }
  }
}

void _expectTimeLabel(WidgetTester tester, Finder label, Finder control) {
  expect(control.hitTestable(), findsOneWidget);
  final bounds = tester.getRect(control);
  expect(bounds.height, greaterThanOrEqualTo(44));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  final fontSize =
      tester.widget<Text>(label).style?.fontSize ??
      DefaultTextStyle.of(tester.element(label)).style.fontSize!;
  expect(
    paragraph.textScaler.scale(fontSize),
    MediaQuery.textScalerOf(tester.element(label)).scale(fontSize),
  );
  expect(
    paragraph.localToGlobal(const Offset(1, 0)).dx -
        paragraph.localToGlobal(Offset.zero).dx,
    closeTo(1, 0.001),
  );
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  )) {
    final glyphs = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      box.toRect(),
    );
    expect(glyphs.left, greaterThanOrEqualTo(bounds.left - 0.1));
    expect(glyphs.right, lessThanOrEqualTo(bounds.right + 0.1));
    expect(glyphs.top, greaterThanOrEqualTo(bounds.top - 0.1));
    expect(glyphs.bottom, lessThanOrEqualTo(bounds.bottom + 0.1));
    expect(glyphs.left, greaterThanOrEqualTo(-0.1));
    expect(
      glyphs.right,
      lessThanOrEqualTo(tester.view.physicalSize.width + 0.1),
    );
    expect(glyphs.top, greaterThanOrEqualTo(-0.1));
    expect(
      glyphs.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height + 0.1),
    );
  }
}

Future<void> _revealTime(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> _captureTime(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final run = Platform.environment['DUOYI_TIME_PICKER_CAPTURE'];
  if (run == null) return;
  await tester.runAsync(() async {
    final picture =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/time-picker-theme-20261020/$run/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

class _TimeNonlinearScaler extends TextScaler {
  const _TimeNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize < 10 ? fontSize : fontSize * 1.8;
  @override
  double get textScaleFactor => 1;
}
