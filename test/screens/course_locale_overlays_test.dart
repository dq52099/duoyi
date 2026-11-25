import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    _courseTest('course route and week picker retain state $brand', (
      tester,
    ) async {
      final fixture = await _mount(tester, brand);
      final route = tester.element(find.byType(CourseScheduleScreen));
      fixture.courses.setViewingWeek(5);
      await tester.pumpAndSettle();
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(CourseScheduleScreen)), same(route));
        expect(fixture.courses.viewingWeek, 5);
        expect(find.text(_weekLabel(5)), findsOneWidget);
        expect(find.byType(AppModalSheet), findsNothing);
        await fixture.capture(tester, '$brand-route-${locale.name}');
      }
      await tester.tap(find.text(_weekLabel(5)));
      await tester.pumpAndSettle();
      final sheet = tester.element(_modal('course.week_picker.title'));
      final grid = tester.element(
        find.byKey(const ValueKey('course_week_picker_adaptive_grid')),
      );
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(_modal('course.week_picker.title')), same(sheet));
        expect(
          find.text(I18n.tr('course.week_picker.subtitle')),
          findsOneWidget,
        );
        expect(
          tester.element(
            find.byKey(const ValueKey('course_week_picker_adaptive_grid')),
          ),
          same(grid),
        );
        expect(fixture.courses.viewingWeek, 5);
        expect(
          find.widgetWithText(OutlinedButton, _weekLabel(7)),
          findsOneWidget,
        );
        await fixture.capture(tester, '$brand-week-${locale.name}');
      }
      final week = find.widgetWithText(OutlinedButton, _weekLabel(7));
      await tester.ensureVisible(week);
      await tester.pumpAndSettle();
      await tester.tap(week);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(fixture.courses.viewingWeek, 7);
      await fixture.expectStorageUnchanged();
      expect(tester.takeException(), isNull);
    });

    _courseTest('new course editor retains draft and selected weeks $brand', (
      tester,
    ) async {
      final fixture = await _mount(tester, brand);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      final sheet = tester.element(_modal('course.editor.add_title'));
      final field = find.byType(TextField).first;
      final fieldElement = tester.element(field);
      final controller = tester.widget<TextField>(field).controller!;
      await tester.enterText(field, 'New user draft 用户草稿');
      await tester.pumpAndSettle();
      final week3 = find.widgetWithText(FilterChip, '3');
      await tester.ensureVisible(week3);
      await tester.pumpAndSettle();
      await tester.tap(week3);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(week3).selected, isFalse);
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(_modal('course.editor.add_title')), same(sheet));
        expect(tester.element(field), same(fieldElement));
        expect(tester.widget<TextField>(field).controller, same(controller));
        expect(controller.text, 'New user draft 用户草稿');
        expect(tester.widget<FilterChip>(week3).selected, isFalse);
        expect(
          tester.widget<TextField>(field).decoration?.labelText,
          I18n.tr('course.field.name'),
        );
        await fixture.capture(tester, '$brand-new-editor-${locale.name}');
      }
      await _cancel(tester, _modal('course.editor.add_title'));
      expect(find.byType(AppModalSheet), findsNothing);
      await fixture.expectStorageUnchanged();
      expect(tester.takeException(), isNull);
    });

    _courseTest('course settings retain unsaved slider draft $brand', (
      tester,
    ) async {
      final fixture = await _mount(tester, brand);
      await _openSettings(tester);
      final state = tester.state(_privateWidget('_ScheduleSettingsSheet'));
      final slider = find.byType(Slider).first;
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(60, 0));
      await tester.pumpAndSettle();
      final value = tester.widget<Slider>(slider).value;
      expect(value, isNot(fixture.courses.settings.totalWeeks.toDouble()));
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(
          tester.state(_privateWidget('_ScheduleSettingsSheet')),
          same(state),
        );
        expect(_modal('course.settings.title'), findsOneWidget);
        expect(find.text(I18n.tr('course.field.total_weeks')), findsOneWidget);
        expect(tester.widget<Slider>(slider).value, value);
        expect(fixture.courses.settings.totalWeeks, 20);
        await fixture.capture(tester, '$brand-settings-${locale.name}');
      }
      // A real platform Back dismisses this modal without invoking Save.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      await fixture.expectStorageUnchanged();
      expect(tester.takeException(), isNull);
    });

    for (final date in [true, false]) {
      _courseTest('course ${date ? 'date' : 'time'} picker live title $brand', (
        tester,
      ) async {
        final fixture = await _mount(tester, brand);
        await _openSettings(tester);
        final settingsState = tester.state(
          _privateWidget('_ScheduleSettingsSheet'),
        );
        final tileKey = date
            ? 'course.field.term_start'
            : 'course.field.first_session_time';
        final tile = find.widgetWithText(ListTile, I18n.tr(tileKey));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        final picker = _privateWidget(
          date ? '_AppDatePickerSheet' : '_AppTimePickerSheet',
        );
        final state = tester.state(picker);
        final titleKey = date
            ? 'course.field.term_start_picker'
            : 'course.field.first_session_time';
        final wheels = date
            ? <ListWheelScrollView>[]
            : tester
                  .widgetList<ListWheelScrollView>(
                    find.descendant(
                      of: picker,
                      matching: find.byType(ListWheelScrollView),
                    ),
                  )
                  .toList();
        final controllers = wheels
            .map((wheel) => wheel.controller! as FixedExtentScrollController)
            .toList();
        if (date) {
          final day = find.byKey(const ValueKey('solar-day-2026-05-19'));
          await tester.ensureVisible(day);
          await tester.pumpAndSettle();
          await tester.tap(day);
        } else {
          controllers[0].jumpToItem(10);
          controllers[1].jumpToItem(3);
        }
        await tester.pumpAndSettle();
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(tester.state(picker), same(state));
          expect(
            tester.state(_privateWidget('_ScheduleSettingsSheet')),
            same(settingsState),
          );
          expect(_modal(titleKey), findsOneWidget);
          if (date) {
            expect(
              find.text(I18nDateFormat.date(DateTime(2026, 5, 19))),
              findsOneWidget,
            );
          } else {
            expect(
              find.text(I18n.tr('course.field.first_session_time_subtitle')),
              findsOneWidget,
            );
            final current = tester
                .widgetList<ListWheelScrollView>(
                  find.descendant(
                    of: picker,
                    matching: find.byType(ListWheelScrollView),
                  ),
                )
                .toList();
            expect(current[0].controller, same(controllers[0]));
            expect(current[1].controller, same(controllers[1]));
            expect(controllers[0].selectedItem, 10);
            expect(controllers[1].selectedItem, 3);
            expect(
              find.descendant(
                of: picker,
                matching: find.text(
                  I18nDateFormat.timeOfDay(hour: 10, minute: 15),
                ),
              ),
              findsOneWidget,
            );
          }
          await fixture.capture(
            tester,
            '$brand-${date ? 'date' : 'time'}-${locale.name}',
          );
        }
        await _cancel(tester, _modal(titleKey));
        expect(picker, findsNothing);
        expect(fixture.courses.settings.termStart, DateTime(2026, 5, 4));
        expect(fixture.courses.settings.firstSessionHour, 8);
        expect(fixture.courses.settings.firstSessionMinute, 0);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AppModalSheet), findsNothing);
        await fixture.expectStorageUnchanged();
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final layout in [
      (name: '320px scale1.6', width: 320.0, scaler: TextScaler.linear(1.6)),
      (name: '390px scale1.0', width: 390.0, scaler: TextScaler.noScaling),
      (name: '400px scale1.6', width: 400.0, scaler: TextScaler.linear(1.6)),
      (name: '390px scale2.0', width: 390.0, scaler: TextScaler.linear(2)),
      (name: '360px scale1.0', width: 360.0, scaler: TextScaler.noScaling),
      (
        name: '332px nonlinear',
        width: 332.0,
        scaler: const _CourseNonlinearScaler(),
      ),
    ]) {
      final suffix = '$brand ${layout.name}';
      Future<_Fixture> mount(WidgetTester tester) =>
          _mount(tester, brand, width: layout.width, textScaler: layout.scaler);

      _courseTest('course toolbar labels remain readable $suffix', (
        tester,
      ) async {
        final fixture = await mount(tester);
        fixture.courses.setViewingWeek(20);
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          _expectFullLabel(tester, find.text(_weekLabel(20)));
          if (layout.name == '390px scale2.0') {
            await fixture.capture(
              tester,
              'boundaries/$brand-route-${locale.name}',
            );
            final grid = _privateWidget('_ScheduleGrid');
            const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
            for (var day = 0; day < 7; day++) {
              final date = fixture.courses.settings.termStart.add(
                Duration(days: 19 * 7 + day),
              );
              for (final copy in [
                I18n.tr('weekday.${weekdays[day]}'),
                '${date.month}/${date.day}',
              ]) {
                final label = find.descendant(
                  of: grid,
                  matching: find.text(copy),
                );
                await tester.ensureVisible(label);
                await tester.pumpAndSettle();
                _expectFullLabel(tester, label);
              }
            }
          }
          for (final icon in [
            Icons.chevron_left,
            Icons.chevron_right,
            Icons.today,
            Icons.settings_outlined,
          ]) {
            expect(find.byIcon(icon).hitTestable(), findsOneWidget);
          }
          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
          expect(fixture.courses.viewingWeek, 19);
          await tester.tap(find.byIcon(Icons.chevron_right));
          await tester.pumpAndSettle();
          expect(fixture.courses.viewingWeek, 20);
          fixture.courses.setViewingWeek(
            fixture.courses.currentWeek == 1 ? 2 : 1,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.today));
          await tester.pumpAndSettle();
          expect(fixture.courses.viewingWeek, fixture.courses.currentWeek);
          fixture.courses.setViewingWeek(20);
          await tester.pumpAndSettle();
        }
        await fixture.expectStorageUnchanged();
        expect(tester.takeException(), isNull);
      });

      _courseTest('course week buttons show complete labels $suffix', (
        tester,
      ) async {
        final fixture = await mount(tester);
        fixture.courses.setViewingWeek(5);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_weekLabel(5)));
        await tester.pumpAndSettle();
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          for (final week in [1, 7, 10, 20]) {
            final label = find.descendant(
              of: _modal('course.week_picker.title'),
              matching: find.text(_weekLabel(week)),
            );
            await tester.ensureVisible(label);
            await tester.pumpAndSettle();
            _expectFullLabel(tester, label);
          }
        }
        await tester.tap(find.widgetWithText(OutlinedButton, _weekLabel(20)));
        await tester.pumpAndSettle();
        expect(fixture.courses.viewingWeek, 20);
        expect(find.byType(AppModalSheet), findsNothing);
        await fixture.expectStorageUnchanged();
        expect(tester.takeException(), isNull);
      });

      _courseTest('course session labels remain readable $suffix', (
        tester,
      ) async {
        final fixture = await mount(tester);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          for (final key in [
            'course.field.start_section',
            'course.field.section_count',
          ]) {
            final label = find.text(I18n.tr(key));
            await tester.ensureVisible(label);
            await tester.pumpAndSettle();
            _expectFullLabel(tester, label);
            final control = find
                .ancestor(of: label, matching: find.byType(Column))
                .first;
            await tester.ensureVisible(control);
            await tester.pumpAndSettle();
            final helper = key == 'course.field.start_section'
                ? fixture.courses.settings.sectionTimeLabel(1)
                : fixture.courses.settings.sectionTimeRangeLabel(1, 2);
            final initialValue = key == 'course.field.start_section' ? 1 : 2;
            _expectFullLabel(
              tester,
              find.descendant(of: control, matching: find.text(helper)),
            );
            final plus = find.descendant(
              of: control,
              matching: find.byIcon(Icons.add),
            );
            final minus = find.descendant(
              of: control,
              matching: find.byIcon(Icons.remove),
            );
            await tester.ensureVisible(plus);
            await tester.pumpAndSettle();
            await tester.tap(plus);
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: control,
                matching: find.text('${initialValue + 1}'),
              ),
              findsOneWidget,
            );
            await tester.tap(minus);
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: control,
                matching: find.text('$initialValue'),
              ),
              findsOneWidget,
            );
          }
        }
        await _cancel(tester, _modal('course.editor.add_title'));
        await fixture.expectStorageUnchanged();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

void _expectFullLabel(WidgetTester tester, Finder label) {
  expect(label, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(label);
  expect(
    paragraph.size.width,
    greaterThan(0),
    reason: 'Label must have visible width',
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'Full label must fit: ${paragraph.text.toPlainText()}',
  );
  expect(label.hitTestable(), findsOneWidget);
  final element = tester.element(label);
  expect(
    paragraph.textScaler.scale(10),
    MediaQuery.textScalerOf(element).scale(10),
  );
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  )) {
    final bounds = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    expect(bounds.left, greaterThanOrEqualTo(viewport.left - 0.1));
    expect(bounds.right, lessThanOrEqualTo(viewport.right + 0.1));
    expect(bounds.top, greaterThanOrEqualTo(viewport.top - 0.1));
    expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 0.1));
  }
}

Finder _privateWidget(String name) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == name,
  skipOffstage: false,
);

Finder _modal(String titleKey) => find.byWidgetPredicate(
  (widget) => widget is AppModalSheet && widget.title == I18n.tr(titleKey),
  skipOffstage: false,
);

String _weekLabel(int week) =>
    '${I18n.tr('course.week.prefix')}$week${I18n.tr('course.week.suffix')}';

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
  expect(_modal('course.settings.title'), findsOneWidget);
}

Future<void> _cancel(WidgetTester tester, Finder modal) async {
  final cancel = find.descendant(
    of: modal,
    matching: find.text(I18n.tr('action.cancel')),
  );
  final scrollable = find
      .descendant(of: modal, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    cancel,
    150,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
  expect(cancel.hitTestable(), findsOneWidget);
  await tester.tap(cancel);
  await tester.pumpAndSettle();
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String brand, {
  double width = 320,
  double scale = 1.6,
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  await tester.runAsync(loadWeeklyReviewScreenshotFonts);
  final boundary = GlobalKey();
  final stored = [
    jsonEncode(
      CourseItem(
        id: 'stored-course',
        name: 'User course',
        teacher: 'User teacher',
        location: 'User classroom',
        weekday: 1,
        startSection: 1,
        weeks: [1, 3],
      ).toJson(),
    ),
  ];
  final settings = jsonEncode(
    ScheduleSettings(termStart: DateTime(2026, 5, 4)).toJson(),
  );
  SharedPreferences.setMockInitialValues({
    'active_brand': brand,
    'duoyi_courses': stored,
    'duoyi_course_settings': settings,
  });
  I18n.setLocale(AppLocale.zh);
  final courses = CourseProvider();
  final theme = ThemeProvider();
  await courses.loadFromStorage();
  await theme.loadFromStorage();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    courses.dispose();
    theme.dispose();
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CourseProvider>.value(value: courses),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(
        theme: theme.brand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: textScaler ?? TextScaler.linear(scale)),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.courses),
              child: const Text('Open courses'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open courses'));
  await tester.pumpAndSettle();
  return _Fixture(courses, stored, settings, boundary);
}

class _Fixture {
  final CourseProvider courses;
  final List<String> stored;
  final String settings;
  final GlobalKey boundary;
  _Fixture(this.courses, this.stored, this.settings, this.boundary);

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['DUOYI_CAPTURE_COURSE_SCREENSHOTS'] != '1') return;
    await tester.pump();
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await render.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      final run =
          Platform.environment['DUOYI_COURSE_SCREENSHOT_RUN'] ?? 'current';
      final file = File(
        'evidence/screenshots/widget-course-detail-20261020/$run/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> expectStorageUnchanged() async {
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('duoyi_courses'), stored);
    expect(prefs.getString('duoyi_course_settings'), settings);
    expect(courses.courses.map((c) => jsonEncode(c.toJson())), stored);
    expect(jsonEncode(courses.settings.toJson()), settings);
  }
}

// A monotonic scaler whose 1sp result does not describe actual label sizes.
class _CourseNonlinearScaler extends TextScaler {
  const _CourseNonlinearScaler();

  @override
  double scale(double fontSize) => fontSize < 10 ? fontSize : fontSize * 1.6;

  @override
  double get textScaleFactor => 1;
}

// Restore painting flags before Flutter verifies invariants; addTearDown runs
// after that verification and is therefore too late for this global flag.
void _courseTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
}
