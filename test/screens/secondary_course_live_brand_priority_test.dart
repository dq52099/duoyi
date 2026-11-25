// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppModalSheet, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int courseWrites = 0;
  int themeWrites = 0;

  static bool _isCourseKey(String key) =>
      key == 'duoyi_courses' ||
      key == 'flutter.duoyi_courses' ||
      key == 'duoyi_course_settings' ||
      key == 'flutter.duoyi_course_settings' ||
      key.endsWith('.duoyi_courses') ||
      key.endsWith('.duoyi_course_settings');

  static bool _isThemeKey(String key) =>
      key == 'active_brand' ||
      key == 'flutter.active_brand' ||
      key == 'theme_shop_state' ||
      key == 'flutter.theme_shop_state' ||
      key == 'theme_unlocked_brands' ||
      key == 'flutter.theme_unlocked_brands' ||
      key.endsWith('.active_brand');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isCourseKey(key)) {
      courseWrites++;
    } else if (_isThemeKey(key)) {
      themeWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isCourseKey(key)) {
      courseWrites++;
    } else if (_isThemeKey(key)) {
      themeWrites++;
    }
    return super.remove(key);
  }
}

State _courseEditSheetState(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_CourseEditSheet',
  );
  expect(finder, findsOneWidget);
  final element = tester.element(finder);
  if (element is StatefulElement) {
    return element.state;
  }
  throw StateError('_CourseEditSheet is not a StatefulElement');
}

String _courseWeekLabel(int week) {
  return '${I18n.tr('course.week.prefix')}$week${I18n.tr('course.week.suffix')}';
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainAccountWrites(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() => AccountPreferenceWrites.drain().timeout(timeout));
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$explicitDir/course-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _CourseLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;

  const _CourseLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
  });
}

const _scenarios = <_CourseLiveBrandScenario>[
  _CourseLiveBrandScenario(
    name: 'zh-portrait-320x844-defaultBrand-to-liquidGlass',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
  ),
  _CourseLiveBrandScenario(
    name: 'en-portrait-320x844-liquidGlass-to-defaultBrand',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
  ),
  _CourseLiveBrandScenario(
    name: 'zh-landscape-844x390-defaultBrand-to-liquidGlass',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
  ),
  _CourseLiveBrandScenario(
    name: 'en-landscape-844x390-liquidGlass-to-defaultBrand',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'course live brand priority defaultBrand <-> liquidGlass ${scenario.name}',
      (tester) async {
        final recordedRequests = <String>[];
        await HttpOverrides.runZoned(
          () async {
            final originalLocale = I18n.current;
            final originalShadows = debugDisableShadows;
            final previousStore = SharedPreferencesStorePlatform.instance;

            final baselineCourse = CourseItem(
              id: 'course-baseline-1',
              name: 'Math 101',
              teacher: 'Prof. Euler',
              location: 'Room 314',
              weekday: 1,
              startSection: 1,
              sectionCount: 2,
              weeks: [1, 2, 3, 4],
              colorValue: 0xFF42A5F5,
            );
            final baselineSettings = ScheduleSettings(
              termStart: DateTime(2026, 9, 1),
              totalWeeks: 20,
            );

            final initialPrefs = <String, Object>{
              'active_brand': scenario.initialBrand,
              'theme_shop_state': jsonEncode({
                'activeBrand': scenario.initialBrand,
                'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
              }),
              'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
              'duoyi_courses': [jsonEncode(baselineCourse.toJson())],
              'duoyi_course_settings': jsonEncode(baselineSettings.toJson()),
              'flutter.active_brand': scenario.initialBrand,
              'flutter.theme_shop_state': jsonEncode({
                'activeBrand': scenario.initialBrand,
                'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
              }),
              'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
              'flutter.duoyi_courses': [jsonEncode(baselineCourse.toJson())],
              'flutter.duoyi_course_settings': jsonEncode(
                baselineSettings.toJson(),
              ),
            };

            SharedPreferences.setMockInitialValues(initialPrefs);
            final store = _RecordingPreferencesStore({
              for (final entry in initialPrefs.entries)
                if (!entry.key.startsWith('flutter.'))
                  'flutter.${entry.key}': entry.value,
            });
            SharedPreferencesStorePlatform.instance = store;

            final theme = ThemeProvider();
            final courseProvider = CourseProvider();
            late final PreferencesProvider preferences;

            try {
              I18n.setLocale(scenario.locale);
              debugDisableShadows = false;

              await tester.runAsync(() async {
                preferences = PreferencesProvider();
                await theme.loadFromStorage().timeout(
                  const Duration(seconds: 5),
                );
                await preferences.loadFromStorage().timeout(
                  const Duration(seconds: 5),
                );
                await courseProvider.loadFromStorage().timeout(
                  const Duration(seconds: 5),
                );
                await loadWeeklyReviewScreenshotFonts().timeout(
                  const Duration(seconds: 5),
                );
              });

              await _drainAccountWrites(tester);

              courseProvider.setViewingWeek(3);
              await _boundedPumpAndSettle(tester);
              expect(courseProvider.viewingWeek, 3);

              expect(theme.brand.id, scenario.initialBrand);
              expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);
              expect(store.courseWrites, 0);

              tester.view.physicalSize = scenario.size;
              tester.view.devicePixelRatio = 1.0;

              final boundary = GlobalKey();

              await tester.pumpWidget(
                MultiProvider(
                  providers: [
                    ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                    ChangeNotifierProvider<CourseProvider>.value(
                      value: courseProvider,
                    ),
                    ChangeNotifierProvider<PreferencesProvider>.value(
                      value: preferences,
                    ),
                  ],
                  child: AnimatedBuilder(
                    animation: Listenable.merge([theme, I18n.localeListenable]),
                    builder: (context, _) => MaterialApp(
                      locale: Locale(
                        I18n.current == AppLocale.en ? 'en' : 'zh',
                      ),
                      supportedLocales: const [Locale('en'), Locale('zh')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      theme: theme.brand.theme,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scenario.scale),
                        ),
                        child: RepaintBoundary(key: boundary, child: child!),
                      ),
                      home: const BrandRouteSurface(
                        remountOnLocaleChange: false,
                        child: CourseScheduleScreen(),
                      ),
                    ),
                  ),
                ),
              );

              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              final courseScreenFinder = find.byType(CourseScheduleScreen);
              expect(courseScreenFinder, findsOneWidget);
              expect(find.byType(BrandRouteSurface), findsOneWidget);
              expect(courseProvider.viewingWeek, 3);
              expect(find.text(_courseWeekLabel(3)), findsWidgets);

              await _capture(tester, boundary, '${scenario.name}-01-schedule');

              // 1. Open Course Editor via visible hit-testable tap on FloatingActionButton
              final fab = find.byType(FloatingActionButton);
              await tester.ensureVisible(fab);
              await _boundedPumpAndSettle(tester);
              expect(fab.hitTestable(), findsOneWidget);
              await tester.tap(fab);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              final editorSheet = find.byType(AppModalSheet);
              expect(editorSheet, findsOneWidget);
              expect(
                find.text(I18n.tr('course.editor.add_title')),
                findsOneWidget,
              );

              final initialEditorState = _courseEditSheetState(tester);
              final initialModalRoute = ModalRoute.of(
                tester.element(editorSheet),
              );
              expect(initialModalRoute, isNotNull);

              // Find the 3 text fields inside the open modal sheet by position in the editor
              final textFields = tester
                  .widgetList<TextField>(
                    find.descendant(
                      of: editorSheet,
                      matching: find.byType(TextField),
                    ),
                  )
                  .toList();
              expect(textFields.length, greaterThanOrEqualTo(3));

              final initialNameController = textFields[0].controller!;
              final initialTeacherController = textFields[1].controller!;
              final initialLocationController = textFields[2].controller!;

              Finder findFieldByController(TextEditingController controller) =>
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is TextField && widget.controller == controller,
                  );

              final nameField = findFieldByController(initialNameController);
              final teacherField = findFieldByController(
                initialTeacherController,
              );
              final locationField = findFieldByController(
                initialLocationController,
              );

              // 2. Enter uncommitted draft into name, teacher, location
              final draftName = 'Draft Course ${scenario.name}';
              final draftTeacher = 'Prof. Euler Draft';
              final draftLocation = 'Lab 404 Draft';
              const draftSelection = TextSelection(
                baseOffset: 2,
                extentOffset: 7,
              );

              await tester.ensureVisible(nameField);
              await _boundedPumpAndSettle(tester);
              await tester.tap(nameField);
              await tester.enterText(nameField, draftName);
              initialNameController.selection = draftSelection;

              await tester.ensureVisible(teacherField);
              await _boundedPumpAndSettle(tester);
              await tester.tap(teacherField);
              await tester.enterText(teacherField, draftTeacher);

              await tester.ensureVisible(locationField);
              await _boundedPumpAndSettle(tester);
              await tester.tap(locationField);
              await tester.enterText(locationField, draftLocation);

              FocusManager.instance.primaryFocus?.unfocus();
              await _boundedPumpAndSettle(tester);

              expect(initialNameController.text, draftName);
              expect(initialNameController.selection, draftSelection);
              expect(initialTeacherController.text, draftTeacher);
              expect(initialLocationController.text, draftLocation);

              // 3. Select Wednesday ChoiceChip
              final wednesdayChip = find.widgetWithText(
                ChoiceChip,
                I18n.tr('weekday.wed'),
              );
              await tester.ensureVisible(wednesdayChip);
              await _boundedPumpAndSettle(tester);
              expect(wednesdayChip.hitTestable(), findsOneWidget);
              await tester.tap(wednesdayChip);
              await _boundedPumpAndSettle(tester);

              expect(
                tester
                    .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, I18n.tr('weekday.wed')),
                    )
                    .selected,
                isTrue,
              );
              expect(
                tester
                    .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, I18n.tr('weekday.mon')),
                    )
                    .selected,
                isFalse,
              );

              // 4. Toggle week 2 FilterChip off
              final week2Chip = find.widgetWithText(FilterChip, '2');
              await tester.ensureVisible(week2Chip);
              await _boundedPumpAndSettle(tester);
              expect(week2Chip.hitTestable(), findsOneWidget);
              expect(tester.widget<FilterChip>(week2Chip).selected, isTrue);
              await tester.tap(week2Chip);
              await _boundedPumpAndSettle(tester);
              expect(tester.widget<FilterChip>(week2Chip).selected, isFalse);

              const draftColor = Color(0xFF66BB6A);
              Finder colorCircle(Color color) => find.descendant(
                of: editorSheet,
                matching: find.byWidgetPredicate((widget) {
                  if (widget is! Container ||
                      widget.decoration is! BoxDecoration) {
                    return false;
                  }
                  final decoration = widget.decoration! as BoxDecoration;
                  return decoration.shape == BoxShape.circle &&
                      decoration.color == color;
                }),
              );
              await tester.ensureVisible(colorCircle(draftColor));
              await _boundedPumpAndSettle(tester);
              expect(colorCircle(draftColor).hitTestable(), findsOneWidget);
              await tester.tap(colorCircle(draftColor));
              await _boundedPumpAndSettle(tester);

              void assertEditorRetained(AppLocale locale) {
                expect(_courseEditSheetState(tester), same(initialEditorState));
                expect(
                  ModalRoute.of(tester.element(editorSheet)),
                  same(initialModalRoute),
                );
                expect(
                  Localizations.localeOf(
                    tester.element(editorSheet),
                  ).languageCode,
                  locale == AppLocale.en ? 'en' : 'zh',
                );
                final fields = find.descendant(
                  of: editorSheet,
                  matching: find.byType(TextField),
                );
                expect(fields, findsNWidgets(3));
                expect(
                  tester.widget<TextField>(fields.at(0)).controller,
                  same(initialNameController),
                );
                expect(
                  tester.widget<TextField>(fields.at(1)).controller,
                  same(initialTeacherController),
                );
                expect(
                  tester.widget<TextField>(fields.at(2)).controller,
                  same(initialLocationController),
                );
                expect(initialNameController.text, draftName);
                expect(initialNameController.selection, draftSelection);
                expect(initialTeacherController.text, draftTeacher);
                expect(initialLocationController.text, draftLocation);
                expect(
                  tester
                      .widget<ChoiceChip>(
                        find.widgetWithText(ChoiceChip, I18n.tr('weekday.wed')),
                      )
                      .selected,
                  isTrue,
                );
                expect(
                  tester
                      .widget<FilterChip>(find.widgetWithText(FilterChip, '2'))
                      .selected,
                  isFalse,
                );
                final selected =
                    tester
                            .widget<Container>(colorCircle(draftColor))
                            .decoration!
                        as BoxDecoration;
                expect(selected.border, isNotNull);
                expect(
                  (selected.border! as Border).top.color,
                  Theme.of(
                    tester.element(colorCircle(draftColor)),
                  ).colorScheme.primary.withValues(alpha: 0.42),
                );
                final unselected =
                    tester
                            .widget<Container>(
                              colorCircle(const Color(0xFF42A5F5)),
                            )
                            .decoration!
                        as BoxDecoration;
                expect(unselected.border, isNull);
                expect(store.courseWrites, 0);
              }

              assertEditorRetained(scenario.locale);

              // 5. Establish meaningful nonzero scroll offset in editor scrollable
              final editorScrollable = find
                  .descendant(
                    of: editorSheet,
                    matching: find.byType(Scrollable),
                  )
                  .first;

              await tester.drag(editorScrollable, const Offset(0, -60));
              await _boundedPumpAndSettle(tester);
              var scrollOffsetAfterSetup = tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .pixels;
              if (scrollOffsetAfterSetup <= 0.0) {
                final cancelBtn = find.descendant(
                  of: editorSheet,
                  matching: find.widgetWithText(
                    TextButton,
                    I18n.tr('action.cancel'),
                  ),
                );
                await tester.scrollUntilVisible(
                  cancelBtn,
                  50,
                  scrollable: editorScrollable,
                  maxScrolls: 20,
                );
                await _boundedPumpAndSettle(tester);
                scrollOffsetAfterSetup = tester
                    .state<ScrollableState>(editorScrollable)
                    .position
                    .pixels;
              }
              expect(
                scrollOffsetAfterSetup,
                greaterThan(0.0),
                reason: 'Meaningful nonzero scroll offset must be established',
              );

              // Check initial theme and surface style
              final initialExpectedBrand = AppBrands.byId(
                scenario.initialBrand,
              );
              expect(
                Theme.of(
                  tester.element(findFieldByController(initialNameController)),
                ).colorScheme.primary,
                equals(initialExpectedBrand.theme.colorScheme.primary),
              );
              final initialSurfaceStyle = scenario.initialBrand == 'liquidGlass'
                  ? AppSurfaceStyle.liquidGlass
                  : AppSurfaceStyle.ios;
              expect(
                appSurfaceStyleOf(tester.element(editorSheet)),
                equals(initialSurfaceStyle),
              );
              expect(store.courseWrites, 0);

              await _capture(
                tester,
                boundary,
                '${scenario.name}-02-editor-draft',
              );

              // 6. Live brand switch to targetBrand
              await tester.runAsync(() async {
                final switched = await theme.setBrand(scenario.targetBrand);
                expect(switched, isTrue);
                await AccountPreferenceWrites.drain().timeout(
                  const Duration(seconds: 5),
                );
              });
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              expect(theme.brand.id, scenario.targetBrand);
              final targetExpectedBrand = AppBrands.byId(scenario.targetBrand);
              expect(
                Theme.of(
                  tester.element(findFieldByController(initialNameController)),
                ).colorScheme.primary,
                equals(targetExpectedBrand.theme.colorScheme.primary),
                reason:
                    'Target control Theme.of primary must match switched brand',
              );
              final targetSurfaceStyle = scenario.targetBrand == 'liquidGlass'
                  ? AppSurfaceStyle.liquidGlass
                  : AppSurfaceStyle.ios;
              expect(
                appSurfaceStyleOf(tester.element(editorSheet)),
                equals(targetSurfaceStyle),
                reason:
                    'Open editor appSurfaceStyleOf must match switched brand style',
              );

              // Assert State, ModalRoute, and controller identity retention
              expect(
                identical(
                  ModalRoute.of(tester.element(editorSheet)),
                  initialModalRoute,
                ),
                isTrue,
                reason:
                    'ModalRoute identity must be preserved across brand switch',
              );
              expect(
                identical(_courseEditSheetState(tester), initialEditorState),
                isTrue,
                reason:
                    '_CourseEditSheet State identity must be preserved across brand switch',
              );
              expect(
                identical(
                  tester
                      .widget<TextField>(
                        findFieldByController(initialNameController),
                      )
                      .controller,
                  initialNameController,
                ),
                isTrue,
                reason: 'Name controller identity must be preserved',
              );
              expect(
                identical(
                  tester
                      .widget<TextField>(
                        findFieldByController(initialTeacherController),
                      )
                      .controller,
                  initialTeacherController,
                ),
                isTrue,
                reason: 'Teacher controller identity must be preserved',
              );
              expect(
                identical(
                  tester
                      .widget<TextField>(
                        findFieldByController(initialLocationController),
                      )
                      .controller,
                  initialLocationController,
                ),
                isTrue,
                reason: 'Location controller identity must be preserved',
              );

              expect(initialNameController.text, draftName);
              expect(initialNameController.selection, draftSelection);
              expect(initialTeacherController.text, draftTeacher);
              expect(initialLocationController.text, draftLocation);

              expect(
                tester
                    .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, I18n.tr('weekday.wed')),
                    )
                    .selected,
                isTrue,
              );
              expect(
                tester
                    .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, I18n.tr('weekday.mon')),
                    )
                    .selected,
                isFalse,
              );
              expect(
                tester
                    .widget<FilterChip>(find.widgetWithText(FilterChip, '2'))
                    .selected,
                isFalse,
              );
              expect(courseProvider.viewingWeek, 3);

              final scrollOffsetAfterBrandSwitch = tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .pixels;
              expect(
                scrollOffsetAfterBrandSwitch,
                equals(scrollOffsetAfterSetup),
                reason:
                    'Exact nonzero scroll offset must be retained on theme switch',
              );
              expect(store.courseWrites, 0);

              assertEditorRetained(scenario.locale);
              await _capture(
                tester,
                boundary,
                '${scenario.name}-03-targetBrand',
              );

              // 7. Live locale switch and verification
              final altLocale = scenario.locale == AppLocale.zh
                  ? AppLocale.en
                  : AppLocale.zh;
              final beforeLocale = tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .pixels;
              I18n.setLocale(altLocale);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);
              assertEditorRetained(altLocale);
              final localizedPosition = tester
                  .state<ScrollableState>(editorScrollable)
                  .position;
              expect(
                localizedPosition.pixels,
                closeTo(
                  beforeLocale.clamp(
                    localizedPosition.minScrollExtent,
                    localizedPosition.maxScrollExtent,
                  ),
                  0.01,
                ),
              );

              expect(
                find.text(I18n.tr('course.editor.add_title')),
                findsOneWidget,
              );
              expect(find.text(I18n.tr('action.cancel')), findsOneWidget);
              expect(find.text(I18n.tr('action.add')), findsOneWidget);

              expect(
                identical(
                  ModalRoute.of(tester.element(editorSheet)),
                  initialModalRoute,
                ),
                isTrue,
                reason:
                    'ModalRoute identity must be preserved across locale switch',
              );
              expect(
                identical(_courseEditSheetState(tester), initialEditorState),
                isTrue,
                reason: 'State identity must be preserved across locale switch',
              );
              expect(
                identical(
                  tester
                      .widget<TextField>(
                        findFieldByController(initialNameController),
                      )
                      .controller,
                  initialNameController,
                ),
                isTrue,
              );
              expect(initialNameController.text, draftName);
              expect(initialNameController.selection, draftSelection);
              expect(initialTeacherController.text, draftTeacher);
              expect(initialLocationController.text, draftLocation);

              expect(
                tester
                    .widget<ChoiceChip>(
                      find.widgetWithText(ChoiceChip, I18n.tr('weekday.wed')),
                    )
                    .selected,
                isTrue,
              );
              expect(
                tester
                    .widget<FilterChip>(find.widgetWithText(FilterChip, '2'))
                    .selected,
                isFalse,
              );
              expect(courseProvider.viewingWeek, 3);

              final scrollOffsetAfterLocale = tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .pixels;
              expect(
                scrollOffsetAfterLocale,
                greaterThan(0.0),
                reason:
                    'Scroll offset must remain meaningful and clamped after locale change',
              );
              expect(store.courseWrites, 0);

              // Switch locale back to scenario original locale
              I18n.setLocale(scenario.locale);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);
              assertEditorRetained(scenario.locale);
              final localeBackPosition = tester
                  .state<ScrollableState>(editorScrollable)
                  .position;
              final scrollOffsetAfterLocaleBack = localeBackPosition.pixels;
              expect(
                localeBackPosition.pixels,
                closeTo(
                  scrollOffsetAfterLocale.clamp(
                    localeBackPosition.minScrollExtent,
                    localeBackPosition.maxScrollExtent,
                  ),
                  0.01,
                ),
              );
              expect(
                find.text(I18n.tr('course.editor.add_title')),
                findsOneWidget,
              );
              expect(store.courseWrites, 0);

              // 8. Live brand roundtrip back to initialBrand
              await tester.runAsync(() async {
                final reverted = await theme.setBrand(scenario.initialBrand);
                expect(reverted, isTrue);
                await AccountPreferenceWrites.drain().timeout(
                  const Duration(seconds: 5),
                );
              });
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              expect(theme.brand.id, scenario.initialBrand);
              expect(
                Theme.of(
                  tester.element(findFieldByController(initialNameController)),
                ).colorScheme.primary,
                equals(initialExpectedBrand.theme.colorScheme.primary),
                reason: 'Theme primary must revert to initial brand style',
              );
              expect(
                appSurfaceStyleOf(tester.element(editorSheet)),
                equals(initialSurfaceStyle),
                reason: 'appSurfaceStyleOf must revert to initial brand style',
              );

              final scrollOffsetAfterRevert = tester
                  .state<ScrollableState>(editorScrollable)
                  .position
                  .pixels;
              expect(
                scrollOffsetAfterRevert,
                equals(scrollOffsetAfterLocaleBack),
                reason:
                    'Exact nonzero scroll offset must be retained on theme revert',
              );

              expect(
                identical(
                  ModalRoute.of(tester.element(editorSheet)),
                  initialModalRoute,
                ),
                isTrue,
              );
              expect(
                identical(_courseEditSheetState(tester), initialEditorState),
                isTrue,
              );
              expect(initialNameController.text, draftName);
              expect(initialNameController.selection, draftSelection);
              expect(initialTeacherController.text, draftTeacher);
              expect(initialLocationController.text, draftLocation);
              expect(courseProvider.viewingWeek, 3);
              expect(store.courseWrites, 0);

              assertEditorRetained(scenario.locale);
              await _capture(
                tester,
                boundary,
                '${scenario.name}-04-revertedBrand',
              );

              // 9. Cancellation without saving and return to the same course page
              final cancelButton = find.descendant(
                of: editorSheet,
                matching: find.widgetWithText(
                  TextButton,
                  I18n.tr('action.cancel'),
                ),
              );
              expect(cancelButton, findsOneWidget);
              await tester.scrollUntilVisible(
                cancelButton,
                120,
                scrollable: editorScrollable,
                maxScrolls: 40,
              );
              await _boundedPumpAndSettle(tester);
              expect(cancelButton.hitTestable(), findsOneWidget);
              await tester.tap(cancelButton);
              await _boundedPumpAndSettle(tester);
              expect(tester.takeException(), isNull);

              // Open editor must be dismissed
              expect(find.byType(AppModalSheet), findsNothing);

              // Returned to the exact same course page
              expect(find.byType(CourseScheduleScreen), findsOneWidget);
              expect(courseProvider.viewingWeek, 3);
              expect(find.text(_courseWeekLabel(3)), findsWidgets);

              // Discard contract: zero course writes occurred across all operations
              expect(
                store.courseWrites,
                0,
                reason:
                    'Zero course writes must occur when discarding draft without saving',
              );
              expect(
                store.themeWrites,
                greaterThan(0),
                reason:
                    'Theme writes must have occurred during brand switching',
              );

              // Stored and in-memory courses remained baseline
              expect(courseProvider.courses.length, 1);
              expect(courseProvider.courses.first.name, 'Math 101');
              final prefs = await SharedPreferences.getInstance();
              final storedCourses = prefs.getStringList('duoyi_courses') ?? [];
              expect(storedCourses.length, 1);
              expect(storedCourses.first.contains('Math 101'), isTrue);

              // Zero unexpected network calls
              expect(
                recordedRequests,
                isEmpty,
                reason: 'Expected zero unexpected network calls',
              );

              await _capture(tester, boundary, '${scenario.name}-05-cancelled');

              expect(tester.takeException(), isNull);
            } finally {
              try {
                await _drainAccountWrites(tester);
                await tester.pumpWidget(const SizedBox.shrink());
                await _boundedPumpAndSettle(tester);
              } finally {
                SharedPreferences.resetStatic();
                SharedPreferencesStorePlatform.instance = previousStore;
                courseProvider.dispose();
                theme.dispose();
                preferences.dispose();
                tester.view.reset();
                debugDisableShadows = originalShadows;
                I18n.setLocale(originalLocale);
              }
            }
          },
          createHttpClient: (_) {
            recordedRequests.add('HTTP client creation');
            throw StateError('Unexpected network client during course fixture');
          },
        );
      },
    );
  }
}
