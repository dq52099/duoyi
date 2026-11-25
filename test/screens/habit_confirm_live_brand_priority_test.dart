// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/habit_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_update_service.dart';
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

  int habitWrites = 0;
  int habitRemoves = 0;
  final List<String> recordedHabitPayloads = [];

  static bool _isHabitKey(String key) =>
      key == 'habits' || key == 'flutter.habits' || key.endsWith('.habits');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isHabitKey(key)) {
      habitWrites++;
      recordedHabitPayloads.add(value.toString());
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isHabitKey(key)) {
      habitRemoves++;
    }
    return super.remove(key);
  }
}

class _MutableLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _MutableAuthProvider extends AuthProvider {
  int _generation = 0;

  @override
  int get sessionGeneration => _generation;

  void switchAccount() {
    _generation++;
    notifyListeners();
  }
}

class _MutableUpdateService extends AppUpdateService {
  _MutableUpdateService()
    : super(repo: 'dq52099/duoyi', currentVersion: '1.0.0');
}

class _HabitConfirmPriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final double devicePixelRatio;

  const _HabitConfirmPriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
  });
}

const _scenarios = <_HabitConfirmPriorityScenario>[
  _HabitConfirmPriorityScenario(
    name: 'zh-portrait-320x844-scale2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _HabitConfirmPriorityScenario(
    name: 'en-portrait-320x844-scale2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _HabitConfirmPriorityScenario(
    name: 'zh-landscape-844x390-scale1-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _HabitConfirmPriorityScenario(
    name: 'en-landscape-844x390-scale1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
];

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

Future<void> _pumpThemeSwitchFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 3)),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _boundedPump(
  WidgetTester tester, {
  int maxPumps = 20,
  Duration step = const Duration(milliseconds: 30),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (!tester.binding.hasScheduledFrame) break;
  }
}

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 3),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
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
      final file = File('$explicitDir/habit-confirm-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scroll = find
      .descendant(
        of: find.byType(HabitDetailScreen),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 30));
  for (var step = 0; step < 100 && target.evaluate().isEmpty; step++) {
    await tester.drag(scroll, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await tester.pump(const Duration(milliseconds: 30));
}

void _assertBrandStyle(
  WidgetTester tester,
  String expectedBrandId, {
  required bool isDelete,
  required String stage,
}) {
  final dialogFinder = find.byType(AppDialog);
  expect(
    dialogFinder,
    findsOneWidget,
    reason: '$stage: AppDialog must be visible',
  );
  final dialogElement = tester.element(dialogFinder);
  final currentTheme = Theme.of(dialogElement);
  final refElement = tester.element(
    find.byKey(ValueKey('ref_theme_$expectedBrandId'), skipOffstage: false),
  );
  final refTheme = Theme.of(refElement);
  final expectedButtonStyle = appSecondaryFilledButtonStyle(refElement);
  final expectedSurfaceStyle = appSurfaceStyleOf(refElement);

  // 1. Primary color
  expect(
    currentTheme.colorScheme.primary,
    equals(refTheme.colorScheme.primary),
    reason: '$stage: ColorScheme.primary must match reference $expectedBrandId',
  );

  // 2. Error color
  expect(
    currentTheme.colorScheme.error,
    equals(refTheme.colorScheme.error),
    reason: '$stage: ColorScheme.error must match reference $expectedBrandId',
  );

  // 3. Surface style
  final surfaceStyle = appSurfaceStyleOf(dialogElement);
  if (expectedBrandId == 'liquidGlass') {
    expect(surfaceStyle, equals(AppSurfaceStyle.liquidGlass));
    expect(surfaceStyle, equals(expectedSurfaceStyle));
  } else {
    expect(surfaceStyle, isNot(equals(AppSurfaceStyle.liquidGlass)));
    expect(surfaceStyle, equals(expectedSurfaceStyle));
  }

  // 4. Material background
  final alertDialogFinder = find.descendant(
    of: dialogFinder,
    matching: find.byType(AlertDialog),
  );
  expect(alertDialogFinder, findsOneWidget);
  final dialogMaterial = tester.widget<Material>(
    find
        .descendant(of: alertDialogFinder, matching: find.byType(Material))
        .first,
  );
  final expectedDialogBg =
      refTheme.dialogTheme.backgroundColor ?? refTheme.colorScheme.surface;
  expect(
    dialogMaterial.color,
    equals(expectedDialogBg),
    reason: '$stage: Dialog background must match $expectedBrandId',
  );

  // 5. Action and icon styling
  if (isDelete) {
    final iconFinder = find.descendant(
      of: dialogFinder,
      matching: find.byIcon(Icons.delete_outline),
    );
    expect(iconFinder, findsOneWidget);
    expect(
      tester.widget<Icon>(iconFinder).color,
      equals(refTheme.colorScheme.error),
      reason:
          '$stage: Delete dialog icon must match error color ($expectedBrandId)',
    );

    final confirmFinder = find.descendant(
      of: dialogFinder,
      matching: find.byType(FilledButton),
    );
    expect(confirmFinder, findsOneWidget);
    final confirmBtn = tester.widget<FilledButton>(confirmFinder);
    expect(
      confirmBtn.style?.backgroundColor?.resolve({}),
      equals(refTheme.colorScheme.error),
      reason:
          '$stage: Delete button background must match error color ($expectedBrandId)',
    );
    expect(
      confirmBtn.style?.foregroundColor?.resolve({}),
      equals(refTheme.colorScheme.onError),
      reason:
          '$stage: Delete button foreground must match onError color ($expectedBrandId)',
    );
  } else {
    final iconFinder = find.descendant(
      of: dialogFinder,
      matching: find.byIcon(Icons.event_busy_outlined),
    );
    expect(iconFinder, findsOneWidget);
    expect(
      tester.widget<Icon>(iconFinder).color,
      equals(refTheme.colorScheme.primary),
      reason:
          '$stage: End dialog icon must match primary color ($expectedBrandId)',
    );

    final confirmFinder = find.descendant(
      of: dialogFinder,
      matching: find.byType(FilledButton),
    );
    expect(confirmFinder, findsOneWidget);
    final confirmBtn = tester.widget<FilledButton>(confirmFinder);
    final btnElement = tester.element(confirmFinder);
    final effectiveStyle =
        confirmBtn.style ?? Theme.of(btnElement).filledButtonTheme.style;
    final effectiveBg = effectiveStyle?.backgroundColor?.resolve({});
    final effectiveFg = effectiveStyle?.foregroundColor?.resolve({});
    final expectedBg = expectedButtonStyle.backgroundColor?.resolve({});
    final expectedFg = expectedButtonStyle.foregroundColor?.resolve({});
    expect(
      effectiveBg,
      equals(expectedBg),
      reason:
          '$stage: End button background must match AppSecondaryControlTheme filled button ($expectedBrandId)',
    );
    expect(
      effectiveFg,
      equals(expectedFg),
      reason:
          '$stage: End button foreground must match AppSecondaryControlTheme filled button ($expectedBrandId)',
    );
  }
}

Future<void> _assertDialogText(
  WidgetTester tester, {
  required String expectedTitle,
  required String expectedContent,
  required String expectedCancel,
  required String expectedConfirm,
}) async {
  final dialogFinder = find.byType(AppDialog);
  expect(dialogFinder, findsOneWidget);

  final titleFinder = find.descendant(
    of: dialogFinder,
    matching: find.text(expectedTitle),
  );
  await Scrollable.ensureVisible(tester.element(titleFinder));
  await tester.pump(const Duration(milliseconds: 20));
  await verifyRetainedDialogText(tester, titleFinder, expected: expectedTitle);

  final contentFinder = find.descendant(
    of: dialogFinder,
    matching: find.text(expectedContent),
  );
  await Scrollable.ensureVisible(tester.element(contentFinder));
  await tester.pump(const Duration(milliseconds: 20));
  await verifyRetainedDialogText(
    tester,
    contentFinder,
    expected: expectedContent,
  );

  final cancelFinder = find.descendant(
    of: find.byType(TextButton),
    matching: find.text(expectedCancel),
  );
  await Scrollable.ensureVisible(tester.element(cancelFinder));
  await tester.pump(const Duration(milliseconds: 20));
  await verifyRetainedDialogText(
    tester,
    cancelFinder,
    expected: expectedCancel,
  );

  final confirmFinder = find.descendant(
    of: find.byType(FilledButton),
    matching: find.text(expectedConfirm),
  );
  await Scrollable.ensureVisible(tester.element(confirmFinder));
  await tester.pump(const Duration(milliseconds: 20));
  await verifyRetainedDialogText(
    tester,
    confirmFinder,
    expected: expectedConfirm,
  );
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('paired HabitDetailScreen confirm live brand priority ${scenario.name}', (
      tester,
    ) async {
      I18n.setLocale(scenario.initialLocale);
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = originalShadows);

      final initialPrefs = <String, Object>{
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
      late final HabitProvider habits;
      late final ThemeProvider theme;
      late final _MutableLock lock;
      late final _MutableAuthProvider auth;
      late final _MutableUpdateService updater;
      final boundaryKey = GlobalKey();
      final navigatorKey = GlobalKey<NavigatorState>();

      final habitName = scenario.initialLocale == AppLocale.zh
          ? '每日深度冥想与专注习惯 Daily Mindful Focus Practice'
          : 'Daily Mindful Meditation Practice for Sustained Focus';
      final originalHabit = Habit(
        id: 'habit/priority-live-brand-confirm',
        name: habitName,
        targetCount: 5,
        colorValue: 0xFF2196F3,
        completions: {'2026-10-24': 2},
        startDate: DateTime(2026, 1, 1),
      );

      try {
        await tester.pump();
        await tester.runAsync(() async {
          habits = HabitProvider()..scheduler = scheduler;
          theme = ThemeProvider();
          lock = _MutableLock();
          auth = _MutableAuthProvider();
          updater = _MutableUpdateService();
          await habits
              .addHabit(originalHabit)
              .timeout(const Duration(seconds: 10));
          await theme.loadFromStorage().timeout(const Duration(seconds: 10));
        });
        expect(theme.brand.id, scenario.initialBrand);
        expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

        if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
            File('assets/fonts/DejaVuSans.ttf').existsSync()) {
          await tester.runAsync(() async {
            await loadWeeklyReviewScreenshotFonts(
              emojiFontPath:
                  'evidence/widget-detail-theme-20261020/fonts/NotoColorEmoji.ttf',
            ).timeout(const Duration(seconds: 5));
          });
        }

        await _drainAccountWrites(tester);

        final baselineHabitWrites = store.habitWrites;
        final baselineHabitRemoves = store.habitRemoves;
        final baselineSchedulerSyncs = scheduler.habitSyncs.length;

        void assertZeroMutations(String stage) {
          expect(
            store.habitWrites,
            baselineHabitWrites,
            reason:
                '$stage: storage writes must remain at baseline ($baselineHabitWrites)',
          );
          expect(
            store.habitRemoves,
            baselineHabitRemoves,
            reason:
                '$stage: storage removes must remain at baseline ($baselineHabitRemoves)',
          );
          expect(
            scheduler.habitSyncs.length,
            baselineSchedulerSyncs,
            reason:
                '$stage: scheduler syncs must remain at baseline ($baselineSchedulerSyncs)',
          );
          expect(
            habits.habits.single.endDate,
            isNull,
            reason: '$stage: habit endDate must remain null',
          );
          expect(
            habits.habits.single.name,
            originalHabit.name,
            reason: '$stage: habit name must remain unchanged',
          );
        }

        tester.view.physicalSize = Size(
          scenario.size.width * scenario.devicePixelRatio,
          scenario.size.height * scenario.devicePixelRatio,
        );
        tester.view.devicePixelRatio = scenario.devicePixelRatio;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AppLockProvider>.value(value: lock),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AppUpdateService>.value(value: updater),
            ],
            child: Consumer<ThemeProvider>(
              builder: (context, currentTheme, _) =>
                  ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, currentLocale, _) => MaterialApp(
                      navigatorKey: navigatorKey,
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
                            child: Scaffold(
                              body: Center(
                                child: Builder(
                                  builder: (routeContext) => TextButton(
                                    onPressed: () => TodayDetailRouter.open(
                                      routeContext,
                                      TodaySectionKind.habits,
                                      id: originalHabit.id,
                                    ),
                                    child: const Text('Open habit'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (final brand in [
                            AppBrands.defaultBrand,
                            AppBrands.liquidGlass,
                          ])
                            Offstage(
                              offstage: true,
                              child: Theme(
                                data: brand.theme,
                                child: Material(
                                  color:
                                      brand.theme.dialogTheme.backgroundColor ??
                                      brand.theme.colorScheme.surface,
                                  child: DefaultTextStyle(
                                    style:
                                        brand.theme.textTheme.bodyMedium ??
                                        const TextStyle(),
                                    child: AppSecondaryControlTheme(
                                      child: Builder(
                                        key: ValueKey('ref_theme_${brand.id}'),
                                        builder: (refContext) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
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

        // 1. Enter HabitDetailScreen via production TodayDetailRouter inside BrandBackground
        await tester.tap(find.text('Open habit'));
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final screenFinder = find.byType(HabitDetailScreen);
        expect(screenFinder, findsOneWidget);
        expect(find.byType(BrandRouteSurface), findsOneWidget);
        expect(find.byType(BrandBackground), findsWidgets);

        final initialScreenElement = tester.element(screenFinder);
        final initialScreenState = tester.state(screenFinder);
        final initialScreenRoute = ModalRoute.of(initialScreenElement);

        void assertScreenStateMaintained(String stage) {
          expect(
            tester.element(screenFinder),
            same(initialScreenElement),
            reason: '$stage: HabitDetailScreen Element must be retained',
          );
          expect(
            tester.state(screenFinder),
            same(initialScreenState),
            reason: '$stage: HabitDetailScreen State must be retained',
          );
          expect(
            ModalRoute.of(tester.element(screenFinder)),
            same(initialScreenRoute),
            reason: '$stage: HabitDetailScreen ModalRoute must be retained',
          );
        }

        // ===================================================================
        // PHASE 1: End Habit Confirmation
        // ===================================================================
        final endActionFinder = find.widgetWithText(
          OutlinedButton,
          HabitUiCopy.endHabitAction(scenario.initialLocale),
        );
        await _reveal(tester, endActionFinder);
        await tester.tap(endActionFinder);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final endDialogFinder = find.byType(AppDialog);
        expect(endDialogFinder, findsOneWidget);
        final initialEndDialogElement = tester.element(endDialogFinder);
        final initialEndDialogRoute = ModalRoute.of(initialEndDialogElement);

        // 1.1 Initial brand verification
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          isDelete: false,
          stage: 'End 1. initial brand',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.endConfirmTitle(scenario.initialLocale),
          expectedContent: HabitUiCopy.endConfirmContent(
            originalHabit.name,
            scenario.initialLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.initialLocale),
          expectedConfirm: HabitUiCopy.endHabitAction(scenario.initialLocale),
        );
        assertScreenStateMaintained('End 1. initial');
        assertZeroMutations('End 1. initial dialog open');
        await _capture(tester, boundaryKey, '${scenario.name}-end-01-initial');

        // 1.2 Live brand switch to targetBrand
        await tester.runAsync(() async {
          final switched = await theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(theme.brand.id, scenario.targetBrand);

        expect(find.byType(AppDialog), findsOneWidget);
        expect(
          tester.element(find.byType(AppDialog)),
          same(initialEndDialogElement),
          reason: 'End dialog Element must be retained across brand switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialEndDialogRoute),
          reason: 'End dialog ModalRoute must be retained across brand switch',
        );
        _assertBrandStyle(
          tester,
          scenario.targetBrand,
          isDelete: false,
          stage: 'End 2. after targetBrand switch',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.endConfirmTitle(scenario.initialLocale),
          expectedContent: HabitUiCopy.endConfirmContent(
            originalHabit.name,
            scenario.initialLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.initialLocale),
          expectedConfirm: HabitUiCopy.endHabitAction(scenario.initialLocale),
        );
        assertScreenStateMaintained('End 2. targetBrand');
        assertZeroMutations('End 2. targetBrand switch');
        await _capture(tester, boundaryKey, '${scenario.name}-end-02-switched');

        // 1.3 Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(theme.brand.id, scenario.initialBrand);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialEndDialogElement),
          reason: 'End dialog Element must be retained across brand roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialEndDialogRoute),
          reason:
              'End dialog ModalRoute must be retained across brand roundtrip',
        );
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          isDelete: false,
          stage: 'End 3. after brand roundtrip',
        );
        assertScreenStateMaintained('End 3. brand roundtrip');
        assertZeroMutations('End 3. brand roundtrip');
        await _capture(tester, boundaryKey, '${scenario.name}-end-03-returned');

        // 1.4 Live locale switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialEndDialogElement),
          reason: 'End dialog Element must be retained across locale switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialEndDialogRoute),
          reason: 'End dialog ModalRoute must be retained across locale switch',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.endConfirmTitle(scenario.alternateLocale),
          expectedContent: HabitUiCopy.endConfirmContent(
            originalHabit.name,
            scenario.alternateLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.alternateLocale),
          expectedConfirm: HabitUiCopy.endHabitAction(scenario.alternateLocale),
        );
        assertScreenStateMaintained('End 4. locale switch');
        assertZeroMutations('End 4. locale switch');
        await _capture(tester, boundaryKey, '${scenario.name}-end-04-locale');

        // 1.5 Live locale roundtrip back to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialEndDialogElement),
          reason: 'End dialog Element must be retained across locale roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialEndDialogRoute),
          reason:
              'End dialog ModalRoute must be retained across locale roundtrip',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.endConfirmTitle(scenario.initialLocale),
          expectedContent: HabitUiCopy.endConfirmContent(
            originalHabit.name,
            scenario.initialLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.initialLocale),
          expectedConfirm: HabitUiCopy.endHabitAction(scenario.initialLocale),
        );
        assertScreenStateMaintained('End 5. locale roundtrip');
        assertZeroMutations('End 5. locale roundtrip');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-end-05-locale-returned',
        );

        // 1.6 Cancel End Habit dialog: verify unchanged storage & identity
        final cancelEndBtn = find.descendant(
          of: find.byType(TextButton),
          matching: find.text(HabitUiCopy.actionCancel(scenario.initialLocale)),
        );
        await tester.ensureVisible(cancelEndBtn);
        await tester.tap(cancelEndBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(HabitDetailScreen), findsOneWidget);
        assertScreenStateMaintained('End 6. after cancel');
        assertZeroMutations('End 6. after cancel dismissal');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-end-06-cancelled',
        );

        // 1.7 Reopen End Habit confirmation and confirm: exactly once execution
        final endActionReopen = find.widgetWithText(
          OutlinedButton,
          HabitUiCopy.endHabitAction(scenario.initialLocale),
        );
        await _reveal(tester, endActionReopen);
        await tester.tap(endActionReopen);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(AppDialog), findsOneWidget);

        final confirmEndBtn = find.descendant(
          of: find.byType(FilledButton),
          matching: find.text(
            HabitUiCopy.endHabitAction(scenario.initialLocale),
          ),
        );
        await tester.ensureVisible(confirmEndBtn);
        await tester.tap(confirmEndBtn);
        await _drainAccountWrites(tester);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(HabitDetailScreen), findsOneWidget);
        expect(
          habits.habits.single.endDate,
          isNotNull,
          reason: 'Habit must be ended',
        );
        expect(
          store.habitWrites,
          baselineHabitWrites + 1,
          reason: 'Exactly one habit write must occur on confirmed end',
        );
        expect(
          scheduler.habitSyncs.length,
          baselineSchedulerSyncs + 1,
          reason: 'Exactly one scheduler sync must occur on confirmed end',
        );
        expect(
          find.text(HabitUiCopy.endedFeedback(scenario.initialLocale)),
          findsOneWidget,
          reason: 'Feedback snackbar must indicate habit ended',
        );
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-end-07-confirmed',
        );

        // ===================================================================
        // PHASE 2: Delete Habit Confirmation
        // ===================================================================
        // Capture new baseline AFTER End confirmed
        final postEndHabitWrites = store.habitWrites;
        final postEndHabitRemoves = store.habitRemoves;
        final postEndSchedulerSyncs = scheduler.habitSyncs.length;

        void assertZeroDeleteMutations(String stage) {
          expect(
            store.habitWrites,
            postEndHabitWrites,
            reason:
                '$stage: storage writes must remain at post-end baseline ($postEndHabitWrites)',
          );
          expect(
            store.habitRemoves,
            postEndHabitRemoves,
            reason:
                '$stage: storage removes must remain at post-end baseline ($postEndHabitRemoves)',
          );
          expect(
            scheduler.habitSyncs.length,
            postEndSchedulerSyncs,
            reason:
                '$stage: scheduler syncs must remain at post-end baseline ($postEndSchedulerSyncs)',
          );
          expect(
            habits.habits,
            hasLength(1),
            reason: '$stage: habit must remain intact in provider',
          );
          expect(
            habits.habits.single.name,
            originalHabit.name,
            reason: '$stage: habit name must remain unchanged',
          );
        }

        final deleteActionFinder = find.widgetWithText(
          OutlinedButton,
          HabitUiCopy.actionDelete(scenario.initialLocale),
        );
        await _reveal(tester, deleteActionFinder);
        await tester.tap(deleteActionFinder);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        final deleteDialogFinder = find.byType(AppDialog);
        expect(deleteDialogFinder, findsOneWidget);
        final initialDeleteDialogElement = tester.element(deleteDialogFinder);
        final initialDeleteDialogRoute = ModalRoute.of(
          initialDeleteDialogElement,
        );

        // 2.1 Initial brand verification for Delete
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          isDelete: true,
          stage: 'Delete 1. initial brand',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.deleteConfirmTitle(scenario.initialLocale),
          expectedContent: HabitUiCopy.deleteConfirmContent(
            originalHabit.name,
            scenario.initialLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.initialLocale),
          expectedConfirm: HabitUiCopy.actionDelete(scenario.initialLocale),
        );
        assertScreenStateMaintained('Delete 1. initial');
        assertZeroDeleteMutations('Delete 1. initial dialog open');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-01-initial',
        );

        // 2.2 Live brand switch to targetBrand
        await tester.runAsync(() async {
          final switched = await theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(theme.brand.id, scenario.targetBrand);

        expect(find.byType(AppDialog), findsOneWidget);
        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDeleteDialogElement),
          reason: 'Delete dialog Element must be retained across brand switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDeleteDialogRoute),
          reason:
              'Delete dialog ModalRoute must be retained across brand switch',
        );
        _assertBrandStyle(
          tester,
          scenario.targetBrand,
          isDelete: true,
          stage: 'Delete 2. after targetBrand switch',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.deleteConfirmTitle(scenario.initialLocale),
          expectedContent: HabitUiCopy.deleteConfirmContent(
            originalHabit.name,
            scenario.initialLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.initialLocale),
          expectedConfirm: HabitUiCopy.actionDelete(scenario.initialLocale),
        );
        assertScreenStateMaintained('Delete 2. targetBrand');
        assertZeroDeleteMutations('Delete 2. targetBrand switch');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-02-switched',
        );

        // 2.3 Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
        });
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);
        expect(theme.brand.id, scenario.initialBrand);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDeleteDialogElement),
          reason:
              'Delete dialog Element must be retained across brand roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDeleteDialogRoute),
          reason:
              'Delete dialog ModalRoute must be retained across brand roundtrip',
        );
        _assertBrandStyle(
          tester,
          scenario.initialBrand,
          isDelete: true,
          stage: 'Delete 3. after brand roundtrip',
        );
        assertScreenStateMaintained('Delete 3. brand roundtrip');
        assertZeroDeleteMutations('Delete 3. brand roundtrip');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-03-returned',
        );

        // 2.4 Live locale switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDeleteDialogElement),
          reason: 'Delete dialog Element must be retained across locale switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDeleteDialogRoute),
          reason:
              'Delete dialog ModalRoute must be retained across locale switch',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.deleteConfirmTitle(
            scenario.alternateLocale,
          ),
          expectedContent: HabitUiCopy.deleteConfirmContent(
            originalHabit.name,
            scenario.alternateLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.alternateLocale),
          expectedConfirm: HabitUiCopy.actionDelete(scenario.alternateLocale),
        );
        assertScreenStateMaintained('Delete 4. locale switch');
        assertZeroDeleteMutations('Delete 4. locale switch');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-04-locale',
        );

        // 2.5 Live locale roundtrip back to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _pumpThemeSwitchFrames(tester);
        expect(tester.takeException(), isNull);

        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDeleteDialogElement),
          reason:
              'Delete dialog Element must be retained across locale roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDeleteDialogRoute),
          reason:
              'Delete dialog ModalRoute must be retained across locale roundtrip',
        );
        await _assertDialogText(
          tester,
          expectedTitle: HabitUiCopy.deleteConfirmTitle(scenario.initialLocale),
          expectedContent: HabitUiCopy.deleteConfirmContent(
            originalHabit.name,
            scenario.initialLocale,
          ),
          expectedCancel: HabitUiCopy.actionCancel(scenario.initialLocale),
          expectedConfirm: HabitUiCopy.actionDelete(scenario.initialLocale),
        );
        assertScreenStateMaintained('Delete 5. locale roundtrip');
        assertZeroDeleteMutations('Delete 5. locale roundtrip');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-05-locale-returned',
        );

        // 2.6 Cancel Delete Habit dialog: verify habit preserved
        final cancelDeleteBtn = find.descendant(
          of: find.byType(TextButton),
          matching: find.text(HabitUiCopy.actionCancel(scenario.initialLocale)),
        );
        await tester.ensureVisible(cancelDeleteBtn);
        await tester.tap(cancelDeleteBtn);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(HabitDetailScreen), findsOneWidget);
        expect(
          habits.habits,
          hasLength(1),
          reason: 'Habit must not be deleted on cancel',
        );
        assertScreenStateMaintained('Delete 6. after cancel');
        assertZeroDeleteMutations('Delete 6. after cancel dismissal');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-06-cancelled',
        );

        // 2.7 Reopen Delete Habit confirmation and confirm: exactly once execution & pop
        final deleteActionReopen = find.widgetWithText(
          OutlinedButton,
          HabitUiCopy.actionDelete(scenario.initialLocale),
        );
        await _reveal(tester, deleteActionReopen);
        await tester.tap(deleteActionReopen);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(AppDialog), findsOneWidget);

        final confirmDeleteBtn = find.descendant(
          of: find.byType(FilledButton),
          matching: find.text(HabitUiCopy.actionDelete(scenario.initialLocale)),
        );
        await tester.ensureVisible(confirmDeleteBtn);
        final writesBeforeDelete = store.habitWrites;
        final syncsBeforeDelete = scheduler.habitSyncs.length;
        expect(writesBeforeDelete, postEndHabitWrites);
        expect(syncsBeforeDelete, postEndSchedulerSyncs);
        await tester.tap(confirmDeleteBtn);
        await _drainAccountWrites(tester);
        await _boundedPumpAndSettle(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(AppDialog), findsNothing);
        // Detail screen popped back to caller router home
        expect(find.byType(HabitDetailScreen), findsNothing);
        expect(find.text('Open habit'), findsOneWidget);
        expect(
          habits.habits,
          isEmpty,
          reason: 'Habit must be deleted after confirmation',
        );
        expect(
          store.habitWrites,
          postEndHabitWrites + 1,
          reason: 'Exactly one write to storage must occur on delete',
        );
        expect(
          store.habitRemoves,
          postEndHabitRemoves,
          reason: 'Storage removes must match post-end baseline',
        );
        expect(
          scheduler.habitSyncs.length,
          postEndSchedulerSyncs + 1,
          reason: 'Exactly one scheduler sync must occur on delete',
        );
        expect(
          find.text(HabitUiCopy.deletedFeedback(scenario.initialLocale)),
          findsOneWidget,
          reason: 'Feedback snackbar must indicate habit deleted',
        );
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-delete-07-confirmed',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _drainAccountWrites(tester);
        habits.dispose();
        theme.dispose();
        lock.dispose();
        auth.dispose();
        updater.dispose();
        tester.view.reset();
        debugDisableShadows = originalShadows;
        I18n.setLocale(initialGlobalLocale);
      }
    });
  }

  testWidgets(
    'Habit confirmation dialogs suppress actions when covered, locked, or session stale',
    (tester) async {
      final initialLocale = I18n.current;
      final originalShadows = debugDisableShadows;
      debugDisableShadows = false;

      SharedPreferences.setMockInitialValues({'active_brand': 'defaultBrand'});
      final store = _RecordingPreferencesStore({});
      final previousStore = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = store;

      final scheduler = RecordingReminderScheduler();
      late final HabitProvider habits;
      late final ThemeProvider theme;
      late final _MutableLock lock;
      late final _MutableAuthProvider auth;
      late final _MutableUpdateService updater;
      final navigatorKey = GlobalKey<NavigatorState>();

      try {
        final habit = Habit(
          id: 'habit/authority-suppression-guard',
          name: 'Daily Meditation Practice',
          targetCount: 3,
        );
        await tester.pump();
        await tester.runAsync(() async {
          habits = HabitProvider()..scheduler = scheduler;
          theme = ThemeProvider();
          lock = _MutableLock();
          auth = _MutableAuthProvider();
          updater = _MutableUpdateService();
          await habits.addHabit(habit).timeout(const Duration(seconds: 10));
          await theme.loadFromStorage().timeout(const Duration(seconds: 10));
        });
        await _drainAccountWrites(tester);

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AppLockProvider>.value(value: lock),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AppUpdateService>.value(value: updater),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              theme: theme.brand.theme,
              home: BrandBackground(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (routeContext) => TextButton(
                        onPressed: () => TodayDetailRouter.open(
                          routeContext,
                          TodaySectionKind.habits,
                          id: habit.id,
                        ),
                        child: const Text('Open habit'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _boundedPumpAndSettle(tester);

        // Open detail screen
        await tester.tap(find.text('Open habit'));
        await _boundedPumpAndSettle(tester);
        expect(find.byType(HabitDetailScreen), findsOneWidget);

        // 1. Open End confirmation dialog
        final endAction = find.widgetWithText(
          OutlinedButton,
          HabitUiCopy.endHabitAction(AppLocale.zh),
        );
        await _reveal(tester, endAction);
        await tester.tap(endAction);
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsOneWidget);

        // Capture actual callbacks while dialog is CURRENT before pushing covering route
        final endCancelBtnFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(
            TextButton,
            HabitUiCopy.actionCancel(AppLocale.zh),
          ),
        );
        expect(endCancelBtnFinder, findsOneWidget);
        final endCancelCallback = tester
            .widget<TextButton>(endCancelBtnFinder)
            .onPressed!;

        final endConfirmBtnFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(
            FilledButton,
            HabitUiCopy.endHabitAction(AppLocale.zh),
          ),
        );
        expect(endConfirmBtnFinder, findsOneWidget);
        final endConfirmCallback = tester
            .widget<FilledButton>(endConfirmBtnFinder)
            .onPressed!;

        // 1.1 Covered route guard: push a covering route
        unawaited(
          navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covering test route')),
            ),
          ),
        );
        await _boundedPumpAndSettle(tester);
        expect(find.text('Covering test route'), findsOneWidget);

        // Invoke captured callbacks while covered and assert route/mutation unchanged
        endCancelCallback();
        await _boundedPump(tester);
        expect(find.text('Covering test route'), findsOneWidget);
        expect(habits.habits.single.endDate, isNull);

        endConfirmCallback();
        await _boundedPump(tester);
        expect(find.text('Covering test route'), findsOneWidget);
        expect(habits.habits.single.endDate, isNull);

        // Pop the covering route; dialog becomes current again
        navigatorKey.currentState!.pop();
        await _boundedPumpAndSettle(tester);
        expect(find.text('Covering test route'), findsNothing);
        expect(find.byType(AppDialog), findsOneWidget);

        // 1.2 Lock guard: lock the app
        lock.setLocked(true);
        await tester.pump();

        endCancelCallback();
        await _boundedPump(tester);
        // Suppressed under lock: dialog remains open
        expect(find.byType(AppDialog), findsOneWidget);

        endConfirmCallback();
        await _boundedPump(tester);
        // Suppressed under lock: dialog remains open, habit not ended
        expect(find.byType(AppDialog), findsOneWidget);
        expect(habits.habits.single.endDate, isNull);

        lock.setLocked(false);
        await tester.pump();

        // Normal cancel works once unlocked
        endCancelCallback();
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsNothing);
        expect(habits.habits.single.endDate, isNull);

        // 2. Open Delete confirmation dialog
        final deleteAction = find.widgetWithText(
          OutlinedButton,
          HabitUiCopy.actionDelete(AppLocale.zh),
        );
        await _reveal(tester, deleteAction);
        await tester.tap(deleteAction);
        await _boundedPumpAndSettle(tester);
        expect(find.byType(AppDialog), findsOneWidget);

        // Capture delete callbacks while current
        final deleteCancelBtnFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(
            TextButton,
            HabitUiCopy.actionCancel(AppLocale.zh),
          ),
        );
        expect(deleteCancelBtnFinder, findsOneWidget);
        final deleteCancelCallback = tester
            .widget<TextButton>(deleteCancelBtnFinder)
            .onPressed!;

        final deleteConfirmBtnFinder = find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(
            FilledButton,
            HabitUiCopy.actionDelete(AppLocale.zh),
          ),
        );
        expect(deleteConfirmBtnFinder, findsOneWidget);
        final deleteConfirmCallback = tester
            .widget<FilledButton>(deleteConfirmBtnFinder)
            .onPressed!;

        // 2.1 Stale account and auth session generation:
        auth.switchAccount();
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await tester.pump();

        // Callback suppressed: habit is not deleted, dialog remains open
        deleteConfirmCallback();
        await _boundedPump(tester);
        expect(find.byType(AppDialog), findsOneWidget);
        expect(habits.habits, hasLength(1));

        deleteCancelCallback();
        await _boundedPump(tester);
        expect(find.byType(AppDialog), findsOneWidget);
        expect(habits.habits, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _drainAccountWrites(tester);
        habits.dispose();
        theme.dispose();
        lock.dispose();
        auth.dispose();
        updater.dispose();
        tester.view.reset();
        debugDisableShadows = originalShadows;
        SharedPreferencesStorePlatform.instance = previousStore;
        I18n.setLocale(initialLocale);
      }
    },
  );
}
