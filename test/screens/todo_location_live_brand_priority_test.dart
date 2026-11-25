// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/todo_detail_ui_copy.dart';
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_dialog_text_probe.dart';
import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int todoWrites = 0;
  int locationReminderWrites = 0;

  static bool _isTodoKey(String key) =>
      key == 'todos' || key == 'flutter.todos' || key.endsWith('.todos');

  static bool _isLocationKey(String key) =>
      key == 'duoyi_location_reminders_v1' ||
      key == 'flutter.duoyi_location_reminders_v1' ||
      key.endsWith('.duoyi_location_reminders_v1');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isTodoKey(key)) {
      todoWrites++;
    }
    if (_isLocationKey(key)) {
      locationReminderWrites++;
    }
    return super.setValue(valueType, key, value);
  }
}

enum _LocationTestAction { cancel, save, fences, validation }

class _TodoLocationScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final _LocationTestAction testAction;

  const _TodoLocationScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.testAction,
  });
}

const _scenarios = <_TodoLocationScenario>[
  _TodoLocationScenario(
    name: 'zh-narrow-scale20-save',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    testAction: _LocationTestAction.save,
  ),
  _TodoLocationScenario(
    name: 'en-landscape-scale10-cancel',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    testAction: _LocationTestAction.cancel,
  ),
  _TodoLocationScenario(
    name: 'zh-landscape-scale10-fences',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    testAction: _LocationTestAction.fences,
  ),
  _TodoLocationScenario(
    name: 'en-narrow-scale20-validation',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    testAction: _LocationTestAction.validation,
  ),
];

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 5),
}) {
  return tester.pumpAndSettle(
    duration,
    EnginePhase.sendSemanticsUpdate,
    timeout,
  );
}

Future<void> _drainAccountWrites(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> _pumpThemeSwitchFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'] ??
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
      final file = File('$explicitDir/todo-location-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

bool _isDisposed(ChangeNotifier notifier) {
  try {
    notifier.addListener(_disposalProbeListener);
    notifier.removeListener(_disposalProbeListener);
    return false;
  } catch (_) {
    return true;
  }
}

void _disposalProbeListener() {}

void main() {
  final initialGlobalLocale = I18n.current;
  final originalTimeZoneReader =
      LocalTimezoneResolver.debugSystemTimeZoneReader;
  setUp(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
  });
  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = originalTimeZoneReader;
  });
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('todo location reminder live brand priority ${scenario.name}', (
      tester,
    ) async {
      I18n.setLocale(scenario.locale);
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;

      final initialPrefs = <String, Object>{
        'pref_app_timezone_mode': 'fixed',
        'pref_app_timezone_iana': 'Asia/Shanghai',
        'active_brand': scenario.initialBrand,
        'theme_shop_state': jsonEncode({
          'activeBrand': scenario.initialBrand,
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.active_brand': scenario.initialBrand,
        'flutter.theme_shop_state': jsonEncode({
          'activeBrand': scenario.initialBrand,
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      };
      SharedPreferences.setMockInitialValues(initialPrefs);
      final store = _RecordingPreferencesStore({
        for (final entry in initialPrefs.entries)
          if (!entry.key.startsWith('flutter.'))
            'flutter.${entry.key}': entry.value,
      });
      final previousStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );

      final scheduler = RecordingReminderScheduler();
      late final TodoProvider todos;
      late final LocationReminderProvider locationReminders;
      late final ThemeProvider theme;
      late final PreferencesProvider preferences;
      final boundaryKey = GlobalKey();

      final original = TodoItem(
        id: 'todo-location-${scenario.name}',
        title: scenario.locale == AppLocale.zh
            ? '位置提醒测试任务'
            : 'Location Reminder Test Task',
        notes: 'Task notes for reminder verification',
      );

      try {
        // Explicit real async hydration for all providers before UI entry
        await tester.runAsync(() async {
          todos = TodoProvider()..scheduler = scheduler;
          locationReminders = LocationReminderProvider();
          theme = ThemeProvider();
          preferences = PreferencesProvider();
          await theme.loadFromStorage().timeout(const Duration(seconds: 10));
          await preferences.loadFromStorage().timeout(
            const Duration(seconds: 10),
          );
          await todos.loadFromStorage().timeout(const Duration(seconds: 10));
          await locationReminders.loadFromStorage().timeout(
            const Duration(seconds: 10),
          );
          await todos.addTodo(original).timeout(const Duration(seconds: 10));
          await loadWeeklyReviewScreenshotFonts().timeout(
            const Duration(seconds: 10),
          );
        });
        await _drainAccountWrites(tester);

        expect(theme.brand.id, scenario.initialBrand);
        expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
              ChangeNotifierProvider<LocationReminderProvider>.value(
                value: locationReminders,
              ),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences,
              ),
            ],
            child: Consumer<ThemeProvider>(
              builder: (context, currentTheme, _) =>
                  ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, currentLocale, _) => MaterialApp(
                      debugShowCheckedModeBanner: false,
                      locale: Locale(
                        currentLocale == AppLocale.en ? 'en' : 'zh',
                      ),
                      supportedLocales: const [Locale('en'), Locale('zh')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      theme: currentTheme.brand.theme,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: scenario.size,
                          textScaler: TextScaler.linear(scenario.scale),
                        ),
                        child: RepaintBoundary(key: boundaryKey, child: child!),
                      ),
                      home: Stack(
                        children: [
                          BrandBackground(
                            child: TodoDetailScreen(todoId: original.id),
                          ),
                          for (final brand in [
                            AppBrands.defaultBrand,
                            AppBrands.liquidGlass,
                          ])
                            Offstage(
                              offstage: true,
                              child: Theme(
                                data: brand.theme,
                                child: AppSecondaryControlTheme(
                                  child: Builder(
                                    key: ValueKey('ref_theme_${brand.id}'),
                                    builder: (refContext) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
        );

        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final screenFinder = find.byType(TodoDetailScreen);
        expect(screenFinder, findsOneWidget);
        final initialScreenElement = tester.element(screenFinder);
        final initialScreenState = tester.state(screenFinder);

        // 1. Locate the linked location reminder Add control in TodoDetailScreen
        final addLocationButton = find.widgetWithIcon(
          TextButton,
          Icons.add_location_alt_outlined,
        );
        final scrollable = find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          addLocationButton,
          150,
          scrollable: scrollable,
        );
        await _boundedPumpAndSettle(tester);
        expect(addLocationButton, findsOneWidget);

        // 2. Open actual linked location reminder Add control
        await tester.tap(addLocationButton);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);
        final initialDialogElement = tester.element(dialogFinder);
        final initialDialogRoute = ModalRoute.of(initialDialogElement);
        expect(initialDialogRoute, isNotNull);

        // Track 5 exact controller references
        final textFields = tester
            .widgetList<TextField>(
              find.descendant(
                of: dialogFinder,
                matching: find.byType(TextField),
              ),
            )
            .toList();
        expect(
          textFields.length,
          5,
          reason: 'Dialog must render exactly 5 TextFields',
        );
        final titleCtrl = textFields[0].controller!;
        final noteCtrl = textFields[1].controller!;
        final latCtrl = textFields[2].controller!;
        final lngCtrl = textFields[3].controller!;
        final radiusCtrl = textFields[4].controller!;

        expect(titleCtrl.text, original.title);
        expect(noteCtrl.text, original.notes);
        expect(latCtrl.text, '');
        expect(lngCtrl.text, '');
        expect(radiusCtrl.text, '200');

        // Enter draft modifications with specific radius for clamping/validation
        final draftTitle = scenario.locale == AppLocale.zh
            ? '自定义提醒地点'
            : 'Custom Reminder Location';
        final draftNote = scenario.locale == AppLocale.zh
            ? '到达地点后记得办业务'
            : 'Remember to complete business';
        final draftRadius = scenario.testAction == _LocationTestAction.save
            ? '25' // under 50 to test clamp(50, 10000)
            : '500';

        await tester.enterText(find.byWidget(textFields[0]), draftTitle);
        await tester.enterText(find.byWidget(textFields[1]), draftNote);
        await tester.enterText(find.byWidget(textFields[2]), '31.2304');
        await tester.enterText(find.byWidget(textFields[3]), '121.4737');
        await tester.enterText(find.byWidget(textFields[4]), draftRadius);

        // Explicitly focus and set text selections
        await tester.tap(find.byWidget(textFields[2]));
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, isNotNull);

        titleCtrl.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 4,
        );
        noteCtrl.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 6,
        );
        latCtrl.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
        lngCtrl.selection = const TextSelection(baseOffset: 2, extentOffset: 5);
        radiusCtrl.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 2,
        );

        // Toggle ChoiceChip to leave
        final leaveChipFinder = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(
            ChoiceChip,
            TodoDetailUiCopy.leaveTrigger,
          ),
        );
        await Scrollable.ensureVisible(tester.element(leaveChipFinder));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(leaveChipFinder);
        await _boundedPumpAndSettle(tester);

        // Toggle SwitchListTile to false
        final switchFinder = find.descendant(
          of: dialogFinder,
          matching: find.byType(SwitchListTile),
        );
        await Scrollable.ensureVisible(tester.element(switchFinder));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(switchFinder);
        await _boundedPumpAndSettle(tester);

        expect(titleCtrl.text, draftTitle);
        expect(noteCtrl.text, draftNote);
        expect(latCtrl.text, '31.2304');
        expect(lngCtrl.text, '121.4737');
        expect(radiusCtrl.text, draftRadius);
        expect(tester.widget<ChoiceChip>(leaveChipFinder).selected, isTrue);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

        void assertDialogThemeAndSurface(String expectedBrandId) {
          final currentDialogElement = tester.element(dialogFinder);
          final dialogTheme = Theme.of(currentDialogElement);
          final refElement = tester.element(
            find.byKey(
              ValueKey('ref_theme_$expectedBrandId'),
              skipOffstage: false,
            ),
          );
          final refTheme = Theme.of(refElement);
          final refStyle = appSecondaryFilledButtonStyle(refElement);

          final expectedPrimary = refTheme.colorScheme.primary;
          final expectedDialogBg =
              refTheme.dialogTheme.backgroundColor ??
              refTheme.colorScheme.surface;
          final expectedButtonBg = refStyle.backgroundColor?.resolve(const {});
          final expectedButtonFg = refStyle.foregroundColor?.resolve(const {});

          expect(
            dialogTheme.colorScheme.primary,
            equals(expectedPrimary),
            reason:
                'Dialog Theme.of primary must match $expectedBrandId reference',
          );

          final actualSurfaceStyle = appSurfaceStyleOf(currentDialogElement);
          if (expectedBrandId == 'liquidGlass') {
            expect(
              actualSurfaceStyle,
              equals(AppSurfaceStyle.liquidGlass),
              reason: 'liquidGlass surface style must match reference',
            );
          } else {
            expect(
              actualSurfaceStyle,
              isNot(equals(AppSurfaceStyle.liquidGlass)),
              reason: 'defaultBrand surface style must not be liquidGlass',
            );
          }

          final alertDialogFinder = find.descendant(
            of: dialogFinder,
            matching: find.byType(AlertDialog),
          );
          expect(alertDialogFinder, findsOneWidget);
          final dialogMaterial = tester.widget<Material>(
            find
                .descendant(
                  of: alertDialogFinder,
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(
            dialogMaterial.color,
            equals(expectedDialogBg),
            reason:
                'Dialog surface Material background must match $expectedBrandId reference',
          );

          // Dialog title style check against rendered DefaultTextStyle reference
          final titleWidgetFinder = find.descendant(
            of: dialogFinder,
            matching: find.text(
              TodoDetailUiCopy.addLocationReminderDialogTitle,
            ),
          );
          final titleDefaultTextStyle = tester.widget<DefaultTextStyle>(
            find
                .ancestor(
                  of: titleWidgetFinder,
                  matching: find.byType(DefaultTextStyle),
                )
                .first,
          );
          expect(
            titleDefaultTextStyle.style.color,
            equals(refTheme.colorScheme.onSurface),
            reason:
                'Dialog title text color must match $expectedBrandId reference onSurface',
          );
          expect(titleDefaultTextStyle.style.fontSize, equals(16));

          // Dialog actions check against AppSecondaryControlTheme reference
          final saveFinder = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(FilledButton, TodoDetailUiCopy.save),
          );
          expect(saveFinder, findsOneWidget);
          final saveElement = tester.element(saveFinder);
          final ambientFilledStyle = Theme.of(
            saveElement,
          ).filledButtonTheme.style;
          final effectiveBtnBg = ambientFilledStyle?.backgroundColor?.resolve(
            const {},
          );
          final effectiveBtnFg = ambientFilledStyle?.foregroundColor?.resolve(
            const {},
          );

          expect(
            effectiveBtnBg,
            isNotNull,
            reason: 'Ambient filledButtonTheme background must be non-null',
          );
          expect(
            effectiveBtnBg,
            equals(expectedButtonBg),
            reason:
                'Save button background inside AppSecondaryControlTheme must match reference',
          );
          expect(
            effectiveBtnFg,
            isNotNull,
            reason: 'Ambient filledButtonTheme foreground must be non-null',
          );
          expect(
            effectiveBtnFg,
            equals(expectedButtonFg),
            reason:
                'Save button foreground inside AppSecondaryControlTheme must match reference',
          );

          // Assert actual rendered Material background of the Save FilledButton
          final saveMaterial = tester.widget<Material>(
            find
                .descendant(of: saveFinder, matching: find.byType(Material))
                .first,
          );
          expect(
            saveMaterial.color,
            equals(expectedButtonBg),
            reason: 'Rendered Save button Material color must match reference',
          );

          // Assert Cancel button ambient style against reference
          final cancelFinder = find.descendant(
            of: dialogFinder,
            matching: find.widgetWithText(TextButton, TodoDetailUiCopy.cancel),
          );
          expect(cancelFinder, findsOneWidget);
          final cancelElement = tester.element(cancelFinder);
          final ambientTextStyle = Theme.of(
            cancelElement,
          ).textButtonTheme.style;
          final refTextStyle = refTheme.textButtonTheme.style;
          expect(
            ambientTextStyle?.textStyle?.resolve(const {})?.fontSize,
            equals(refTextStyle?.textStyle?.resolve(const {})?.fontSize),
            reason:
                'Cancel button text style must match AppSecondaryControlTheme reference',
          );
        }

        Future<void> assertDialogTexts() async {
          final checks = <(Finder, String)>[
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(
                  TodoDetailUiCopy.addLocationReminderDialogTitle,
                ),
              ),
              TodoDetailUiCopy.addLocationReminderDialogTitle,
            ),
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(TodoDetailUiCopy.triggerDirectionLabel),
              ),
              TodoDetailUiCopy.triggerDirectionLabel,
            ),
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(TodoDetailUiCopy.arriveTrigger),
              ),
              TodoDetailUiCopy.arriveTrigger,
            ),
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(TodoDetailUiCopy.leaveTrigger),
              ),
              TodoDetailUiCopy.leaveTrigger,
            ),
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(TodoDetailUiCopy.autoCloseAfterTrigger),
              ),
              TodoDetailUiCopy.autoCloseAfterTrigger,
            ),
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(TodoDetailUiCopy.cancel),
              ),
              TodoDetailUiCopy.cancel,
            ),
            (
              find.descendant(
                of: dialogFinder,
                matching: find.text(TodoDetailUiCopy.save),
              ),
              TodoDetailUiCopy.save,
            ),
          ];

          for (final (finder, expectedText) in checks) {
            expect(finder, findsOneWidget);
            await Scrollable.ensureVisible(tester.element(finder));
            await tester.pump(const Duration(milliseconds: 20));
            await verifyRetainedDialogText(
              tester,
              finder,
              expected: expectedText,
            );
          }
        }

        assertDialogThemeAndSurface(scenario.initialBrand);
        await assertDialogTexts();
        await _capture(tester, boundaryKey, '${scenario.name}-01-initial');

        // 3. Live brand switch to targetBrand while same dialog remains mounted
        await tester.runAsync(() async {
          final switched = await theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          identical(tester.element(dialogFinder), initialDialogElement),
          isTrue,
          reason: 'Dialog Element must be retained across brand switch',
        );
        expect(
          identical(
            ModalRoute.of(tester.element(dialogFinder)),
            initialDialogRoute,
          ),
          isTrue,
          reason: 'ModalRoute must be retained across brand switch',
        );
        expect(
          identical(tester.element(screenFinder), initialScreenElement),
          isTrue,
          reason: 'TodoDetailScreen Element must be retained',
        );
        expect(
          identical(tester.state(screenFinder), initialScreenState),
          isTrue,
          reason: 'TodoDetailScreen State must be retained',
        );

        // Exact controller instance references preserved
        final switchedTextFields = tester
            .widgetList<TextField>(
              find.descendant(
                of: dialogFinder,
                matching: find.byType(TextField),
              ),
            )
            .toList();
        expect(switchedTextFields[0].controller, same(titleCtrl));
        expect(switchedTextFields[1].controller, same(noteCtrl));
        expect(switchedTextFields[2].controller, same(latCtrl));
        expect(switchedTextFields[3].controller, same(lngCtrl));
        expect(switchedTextFields[4].controller, same(radiusCtrl));

        // Focus, draft values, and selections preserved
        expect(FocusManager.instance.primaryFocus, isNotNull);
        expect(titleCtrl.text, draftTitle);
        expect(
          titleCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        expect(noteCtrl.text, draftNote);
        expect(
          noteCtrl.selection,
          const TextSelection(baseOffset: 2, extentOffset: 6),
        );
        expect(latCtrl.text, '31.2304');
        expect(
          latCtrl.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(lngCtrl.text, '121.4737');
        expect(
          lngCtrl.selection,
          const TextSelection(baseOffset: 2, extentOffset: 5),
        );
        expect(radiusCtrl.text, draftRadius);
        expect(
          radiusCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
        );
        expect(tester.widget<ChoiceChip>(leaveChipFinder).selected, isTrue);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

        assertDialogThemeAndSurface(scenario.targetBrand);
        await assertDialogTexts();
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-02-switched-${scenario.targetBrand}',
        );

        // 4. Live brand roundtrip return to initialBrand
        await tester.runAsync(() async {
          final reverted = await theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          identical(tester.element(dialogFinder), initialDialogElement),
          isTrue,
        );
        expect(
          identical(
            ModalRoute.of(tester.element(dialogFinder)),
            initialDialogRoute,
          ),
          isTrue,
        );
        expect(switchedTextFields[0].controller, same(titleCtrl));
        expect(switchedTextFields[1].controller, same(noteCtrl));
        expect(switchedTextFields[2].controller, same(latCtrl));
        expect(switchedTextFields[3].controller, same(lngCtrl));
        expect(switchedTextFields[4].controller, same(radiusCtrl));

        assertDialogThemeAndSurface(scenario.initialBrand);
        await assertDialogTexts();
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-03-returned-${scenario.initialBrand}',
        );

        // 5. Live locale switch to alternate locale and back
        final altLocale = scenario.locale == AppLocale.zh
            ? AppLocale.en
            : AppLocale.zh;
        I18n.setLocale(altLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          identical(tester.element(dialogFinder), initialDialogElement),
          isTrue,
          reason: 'Dialog Element must be retained across locale switch',
        );
        expect(
          identical(
            ModalRoute.of(tester.element(dialogFinder)),
            initialDialogRoute,
          ),
          isTrue,
        );
        expect(titleCtrl.text, draftTitle);
        expect(noteCtrl.text, draftNote);
        expect(latCtrl.text, '31.2304');
        expect(lngCtrl.text, '121.4737');
        expect(radiusCtrl.text, draftRadius);
        expect(
          titleCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        expect(
          noteCtrl.selection,
          const TextSelection(baseOffset: 2, extentOffset: 6),
        );
        expect(
          latCtrl.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(
          lngCtrl.selection,
          const TextSelection(baseOffset: 2, extentOffset: 5),
        );
        expect(
          radiusCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
        );
        final altLeaveChip = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(
            ChoiceChip,
            TodoDetailUiCopy.leaveTrigger,
          ),
        );
        expect(tester.widget<ChoiceChip>(altLeaveChip).selected, isTrue);
        expect(
          tester
              .widget<SwitchListTile>(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(SwitchListTile),
                ),
              )
              .value,
          isFalse,
        );
        await assertDialogTexts();
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-04-locale-${altLocale.name}',
        );

        // Switch back to scenario initial locale
        I18n.setLocale(scenario.locale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          identical(tester.element(dialogFinder), initialDialogElement),
          isTrue,
        );
        expect(titleCtrl.text, draftTitle);
        expect(noteCtrl.text, draftNote);
        expect(latCtrl.text, '31.2304');
        expect(lngCtrl.text, '121.4737');
        expect(radiusCtrl.text, draftRadius);
        expect(
          titleCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        expect(
          noteCtrl.selection,
          const TextSelection(baseOffset: 2, extentOffset: 6),
        );
        expect(
          latCtrl.selection,
          const TextSelection(baseOffset: 1, extentOffset: 4),
        );
        expect(
          lngCtrl.selection,
          const TextSelection(baseOffset: 2, extentOffset: 5),
        );
        expect(
          radiusCtrl.selection,
          const TextSelection(baseOffset: 0, extentOffset: 2),
        );
        final returnedLeaveChip = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(
            ChoiceChip,
            TodoDetailUiCopy.leaveTrigger,
          ),
        );
        expect(tester.widget<ChoiceChip>(returnedLeaveChip).selected, isTrue);
        expect(
          tester
              .widget<SwitchListTile>(
                find.descendant(
                  of: dialogFinder,
                  matching: find.byType(SwitchListTile),
                ),
              )
              .value,
          isFalse,
        );
        await assertDialogTexts();
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-05-locale-returned-${scenario.locale.name}',
        );

        // 6. Execute action scope tests
        switch (scenario.testAction) {
          case _LocationTestAction.cancel:
            final cancelBtn = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                TextButton,
                TodoDetailUiCopy.cancel,
              ),
            );
            await Scrollable.ensureVisible(tester.element(cancelBtn));
            await tester.pump(const Duration(milliseconds: 20));
            await tester.tap(cancelBtn);

            // Verify: During exit animation, controllers are NOT disposed
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              _isDisposed(titleCtrl),
              isFalse,
              reason: 'Controllers must not be disposed during exit animation',
            );
            expect(_isDisposed(noteCtrl), isFalse);
            expect(_isDisposed(latCtrl), isFalse);
            expect(_isDisposed(lngCtrl), isFalse);
            expect(_isDisposed(radiusCtrl), isFalse);

            // Complete exit animation
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsNothing);

            // Verify: After exit unmounts, controllers ARE disposed
            expect(
              _isDisposed(titleCtrl),
              isTrue,
              reason: 'Controllers must be disposed after exit completion',
            );
            expect(_isDisposed(noteCtrl), isTrue);
            expect(_isDisposed(latCtrl), isTrue);
            expect(_isDisposed(lngCtrl), isTrue);
            expect(_isDisposed(radiusCtrl), isTrue);

            // Verify: Cancel leaves provider and storage writes untouched
            expect(locationReminders.reminders, isEmpty);
            expect(store.locationReminderWrites, 0);

          case _LocationTestAction.save:
            final saveBtn = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                TodoDetailUiCopy.save,
              ),
            );
            await Scrollable.ensureVisible(tester.element(saveBtn));
            await tester.pump(const Duration(milliseconds: 20));
            await tester.tap(saveBtn);

            // Verify: During exit animation, controllers are NOT disposed
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              _isDisposed(titleCtrl),
              isFalse,
              reason: 'Controllers must not be disposed during exit animation',
            );

            // Complete exit animation
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsNothing);

            // Verify controllers disposed upon completion
            expect(_isDisposed(titleCtrl), isTrue);
            expect(_isDisposed(noteCtrl), isTrue);
            expect(_isDisposed(latCtrl), isTrue);
            expect(_isDisposed(lngCtrl), isTrue);
            expect(_isDisposed(radiusCtrl), isTrue);

            // Verify successful mock local add once with correct fields/id and clamped radius
            expect(locationReminders.reminders.length, 1);
            final added = locationReminders.reminders.single;
            expect(added.title, draftTitle);
            expect(added.note, draftNote);
            expect(added.latitude, 31.2304);
            expect(added.longitude, 121.4737);
            // Radius 25 is clamped to minimum 50
            expect(added.radiusMeters, 50.0);
            expect(added.trigger, LocationTrigger.leave);
            expect(added.oneShot, isFalse);
            expect(added.linkedType, 'todo');
            expect(added.linkedId, original.id);
            expect(added.id, isNotEmpty);
            expect(store.locationReminderWrites, 1);

            // Verify snackbar
            expect(
              find.text(TodoDetailUiCopy.locationReminderAdded),
              findsOneWidget,
            );

          case _LocationTestAction.fences:
            // 1. Covered route check: push a covering route
            final nav = Navigator.of(
              tester.element(dialogFinder),
              rootNavigator: true,
            );
            nav.push(
              MaterialPageRoute(
                builder: (_) =>
                    const Scaffold(body: Text('Covering Route Fence')),
              ),
            );
            await _boundedPumpAndSettle(tester);
            expect(find.text('Covering Route Fence'), findsOneWidget);

            // Covered dialog callback invocation must not pop covering route or mutate
            final coveredSaveBtn = tester.widget<FilledButton>(
              find.descendant(
                of: find.byType(AppDialog, skipOffstage: false),
                matching: find.widgetWithText(
                  FilledButton,
                  TodoDetailUiCopy.save,
                  skipOffstage: false,
                ),
                skipOffstage: false,
              ),
            );
            coveredSaveBtn.onPressed?.call();
            await tester.pump(const Duration(milliseconds: 50));

            expect(
              find.text('Covering Route Fence'),
              findsOneWidget,
              reason: 'Covering route must not be popped by covered callback',
            );
            expect(
              locationReminders.reminders,
              isEmpty,
              reason: 'Covered callback must not mutate provider',
            );

            final coveredCancelBtn = tester.widget<TextButton>(
              find.descendant(
                of: find.byType(AppDialog, skipOffstage: false),
                matching: find.widgetWithText(
                  TextButton,
                  TodoDetailUiCopy.cancel,
                  skipOffstage: false,
                ),
                skipOffstage: false,
              ),
            );
            coveredCancelBtn.onPressed?.call();
            await tester.pump(const Duration(milliseconds: 50));
            expect(
              find.text('Covering Route Fence'),
              findsOneWidget,
              reason: 'Covering route must not be popped by covered cancel',
            );

            // Pop covering route
            nav.pop();
            await _boundedPumpAndSettle(tester);
            expect(find.text('Covering Route Fence'), findsNothing);
            expect(dialogFinder, findsOneWidget);

            // 2. Stale account check
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            await tester.pump();

            final staleSaveBtn = tester.widget<FilledButton>(
              find.descendant(
                of: dialogFinder,
                matching: find.widgetWithText(
                  FilledButton,
                  TodoDetailUiCopy.save,
                ),
              ),
            );
            staleSaveBtn.onPressed?.call();
            await _boundedPumpAndSettle(tester);

            expect(
              dialogFinder,
              findsOneWidget,
              reason: 'Stale account callback must not pop dialog',
            );
            expect(
              locationReminders.reminders,
              isEmpty,
              reason: 'Stale account callback must not mutate provider',
            );

            // Cleanly pop dialog and verify disposal
            nav.pop();
            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsNothing);
            expect(_isDisposed(titleCtrl), isTrue);

          case _LocationTestAction.validation:
            // Clear coordinate inputs with malformed values
            await tester.enterText(
              find.byWidgetPredicate(
                (widget) => widget is TextField && widget.controller == latCtrl,
              ),
              'not-a-number',
            );
            await tester.enterText(
              find.byWidgetPredicate(
                (widget) => widget is TextField && widget.controller == lngCtrl,
              ),
              '',
            );
            await tester.pump();

            final saveBtn = find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(
                FilledButton,
                TodoDetailUiCopy.save,
              ),
            );
            await Scrollable.ensureVisible(tester.element(saveBtn));
            await tester.pump(const Duration(milliseconds: 20));
            await tester.tap(saveBtn);
            await _boundedPumpAndSettle(tester);

            // Dialog popped with true, but coordinate validation blocked provider mutation
            expect(find.byType(AppDialog), findsNothing);
            expect(locationReminders.reminders, isEmpty);
            expect(
              find.text(TodoDetailUiCopy.invalidLocationCoordinates),
              findsOneWidget,
            );
            expect(_isDisposed(titleCtrl), isTrue);
            expect(_isDisposed(noteCtrl), isTrue);
            expect(_isDisposed(latCtrl), isTrue);
            expect(_isDisposed(lngCtrl), isTrue);
            expect(_isDisposed(radiusCtrl), isTrue);

            // Also test barrier dismissal lifecycle
            await Scrollable.ensureVisible(tester.element(addLocationButton));
            await tester.pump(const Duration(milliseconds: 20));
            await tester.tap(addLocationButton);
            await _boundedPumpAndSettle(tester);

            expect(find.byType(AppDialog), findsOneWidget);
            final reopenedFields = tester
                .widgetList<TextField>(
                  find.descendant(
                    of: find.byType(AppDialog),
                    matching: find.byType(TextField),
                  ),
                )
                .toList();
            final reopenedTitleCtrl = reopenedFields[0].controller!;

            // Tap outside barrier
            await tester.tapAt(const Offset(10, 10));
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              _isDisposed(reopenedTitleCtrl),
              isFalse,
              reason:
                  'Controller must survive barrier dismissal exit animation',
            );

            await _boundedPumpAndSettle(tester);
            expect(find.byType(AppDialog), findsNothing);
            expect(
              _isDisposed(reopenedTitleCtrl),
              isTrue,
              reason:
                  'Controller must be disposed after barrier dismissal finishes',
            );
            expect(locationReminders.reminders, isEmpty);
        }

        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = originalShadows;
        await tester.pumpWidget(const SizedBox.shrink());
        await _boundedPumpAndSettle(tester);
        todos.dispose();
        locationReminders.dispose();
        theme.dispose();
        preferences.dispose();
      }
    });
  }
}
