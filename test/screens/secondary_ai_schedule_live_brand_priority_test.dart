// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ai_schedule_ui_copy.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/reminder_issue_copy.dart'
    show NotificationIssueTitle;
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart'
    show AppDialog, appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _testInput = 'Buy fresh groceries tomorrow at 10am / 明天上午十点买菜';
const _testTitle = 'Buy fresh groceries / 买新鲜蔬菜水果';
const _testNotes = 'Get milk, bread, organic apples and coffee / 牛奶面包苹果咖啡';
const _testSubtask = 'Check market discount coupon / 查看超市优惠券';

const _syntheticOrigin = AuthState(
  userId: 'ai-schedule-synthetic-user',
  username: 'synthetic-schedule-account',
  token: 'synthetic-schedule-token',
);

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int todoWrites = 0;
  int calendarWrites = 0;
  int authWrites = 0;

  static bool _isTodoKey(String key) =>
      key == 'todos' || key == 'flutter.todos' || key.endsWith('.todos');

  static bool _isCalendarKey(String key) =>
      key == 'duoyi_local_calendar_events_v1' ||
      key == 'flutter.duoyi_local_calendar_events_v1' ||
      key.endsWith('.duoyi_local_calendar_events_v1');

  static bool _isAuthKey(String key) =>
      key == 'auth_state' ||
      key == 'flutter.auth_state' ||
      key.endsWith('.auth_state');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isTodoKey(key)) {
      todoWrites++;
    } else if (_isCalendarKey(key)) {
      calendarWrites++;
    } else if (_isAuthKey(key)) {
      authWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isTodoKey(key)) {
      todoWrites++;
    } else if (_isCalendarKey(key)) {
      calendarWrites++;
    } else if (_isAuthKey(key)) {
      authWrites++;
    }
    return super.remove(key);
  }
}

class _DeterministicAiService extends AiService {
  final AiScheduleDraft draft;
  int recognitions = 0;

  _DeterministicAiService(this.draft);

  @override
  bool get enabled => true;

  @override
  Future<AiScheduleDraft> createScheduleDraft(
    String input, {
    DateTime? now,
  }) async {
    recognitions++;
    return draft;
  }
}

class _RecordingCalendarProvider extends CalendarProvider {
  int addCalls = 0;

  @override
  Future<void> addLocalEvent(
    CalendarEvent event, {
    bool Function()? canWrite,
  }) async {
    addCalls++;
    await super.addLocalEvent(event, canWrite: canWrite);
  }
}

class _RecordingTodoProvider extends TodoProvider {
  int addTodoCalls = 0;

  @override
  Future<TodoReminderSyncResult?> addTodoWithResult(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
    bool Function()? canWrite,
  }) async {
    addTodoCalls++;
    return super.addTodoWithResult(
      todo,
      waitForReminderSync: waitForReminderSync,
      reportReminderScheduleFailure: reportReminderScheduleFailure,
      canWrite: canWrite,
    );
  }
}

class _SyntheticNotificationService extends NotificationService {
  int ensureReadyCalls = 0;

  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) async {
    ensureReadyCalls++;
    return true;
  }

  @override
  Future<void> scheduleCalendarReminder({
    required String calendarEventId,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool Function()? canContinue,
  }) async {}
}

Future<int> _bounded5s(
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
  String name, {
  Finder? reveal,
  Finder? scrollable,
}) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  double? savedOffset;
  ScrollPosition? position;
  if (reveal != null &&
      scrollable != null &&
      scrollable.evaluate().isNotEmpty) {
    final scrollState = tester.state<ScrollableState>(scrollable);
    position = scrollState.position;
    savedOffset = position.pixels;
    if (reveal.evaluate().isEmpty) {
      await tester.scrollUntilVisible(reveal, 120, scrollable: scrollable);
      await _bounded5s(tester);
    }
  }

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final file = File('$explicitDir/ai-schedule-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });

  if (position != null && savedOffset != null) {
    position.jumpTo(
      savedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await _bounded5s(tester);
  }
}

Future<void> _assertPreview(WidgetTester tester, Finder scrollable) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  final savedOffset = position.pixels;
  if (find.text(_testTitle).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(_testTitle),
      120,
      scrollable: scrollable,
    );
    await _bounded5s(tester);
  }
  expect(find.text(_testTitle), findsOneWidget);
  expect(find.text(_testNotes), findsOneWidget);
  expect(find.text(_testSubtask), findsOneWidget);
  if ((position.pixels - savedOffset).abs() > 0.001) {
    position.jumpTo(
      savedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await _bounded5s(tester);
  }
}

Future<void> _assertInput(
  WidgetTester tester,
  Finder scrollable, {
  required AppBrand expectedBrand,
  required TextEditingController initialController,
  required String expectedText,
  required TextSelection expectedSelection,
}) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  final savedOffset = position.pixels;

  final predicate = find.byWidgetPredicate(
    (w) => w is TextField && identical(w.controller, initialController),
  );

  if (predicate.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -120,
      scrollable: scrollable,
    );
    await _bounded5s(tester);
  }

  expect(predicate, findsOneWidget);
  final inputElement = tester.element(predicate);
  expect(
    Theme.of(inputElement).colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
    reason:
        'Target control Theme.of colorScheme.primary must match expected brand',
  );

  final textField = tester.widget<TextField>(predicate);
  expect(
    identical(textField.controller, initialController),
    isTrue,
    reason:
        'TextEditingController identity must be preserved across live updates',
  );
  expect(textField.controller!.text, expectedText);
  expect(textField.controller!.selection, expectedSelection);

  if ((position.pixels - savedOffset).abs() > 0.001) {
    position.jumpTo(
      savedOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    await _bounded5s(tester);
  }
}

enum _ScheduleContractOutcome { cancel, create }

class _ScheduleLiveBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final _ScheduleContractOutcome outcome;

  const _ScheduleLiveBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    required this.outcome,
  });
}

const _scenarios = <_ScheduleLiveBrandScenario>[
  _ScheduleLiveBrandScenario(
    name: 'zh-portrait-320x844-cancel',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _ScheduleContractOutcome.cancel,
  ),
  _ScheduleLiveBrandScenario(
    name: 'en-portrait-320x844-create',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    outcome: _ScheduleContractOutcome.create,
  ),
  _ScheduleLiveBrandScenario(
    name: 'zh-landscape-844x390-create',
    locale: AppLocale.zh,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    outcome: _ScheduleContractOutcome.create,
  ),
  _ScheduleLiveBrandScenario(
    name: 'en-landscape-844x390-cancel',
    locale: AppLocale.en,
    size: Size(844, 390),
    scale: 1.6,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    outcome: _ScheduleContractOutcome.cancel,
  ),
];

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets(
      'ai schedule live brand priority ${scenario.initialBrand} <-> ${scenario.targetBrand} ${scenario.name}',
      (tester) async {
        final originalLocale = I18n.current;
        final originalShadows = debugDisableShadows;
        final originalTimeZoneReader =
            LocalTimezoneResolver.debugSystemTimeZoneReader;
        final previousStore = SharedPreferencesStorePlatform.instance;

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
          AccountLocalDataCleaner.accountDataOwnerKey:
              'id:ai-schedule-synthetic-user',
          'flutter.${AccountLocalDataCleaner.accountDataOwnerKey}':
              'id:ai-schedule-synthetic-user',
          'auth_state': jsonEncode(_syntheticOrigin.toJson()),
          'flutter.auth_state': jsonEncode(_syntheticOrigin.toJson()),
        };

        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = store;
        LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
            'Asia/Shanghai';

        final auth = AuthProvider(
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            token: _syntheticOrigin.token,
            httpClient: MockClient((_) async {
              fail(
                'AiSchedule live brand priority fixture must not issue an HTTP request',
              );
            }),
          ),
          initialState: _syntheticOrigin,
        );

        final aiDraft = AiScheduleDraft(
          type: AiScheduleType.todo,
          title: _testTitle,
          notes: _testNotes,
          startAt: DateTime(2026, 10, 24, 10, 0),
          subtasks: const [_testSubtask],
          reminderEnabled: false,
          source: AiScheduleSource.ai,
        );

        final aiService = _DeterministicAiService(aiDraft);
        final calendarProvider = _RecordingCalendarProvider();
        final todoProvider = _RecordingTodoProvider();
        final notificationService = _SyntheticNotificationService();
        final theme = ThemeProvider();
        late final PreferencesProvider preferences;

        try {
          I18n.setLocale(scenario.locale);
          debugDisableShadows = false;

          await tester.runAsync(() async {
            preferences = PreferencesProvider();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await todoProvider.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await calendarProvider.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          await _drainAccountWrites(tester);

          expect(theme.brand.id, scenario.initialBrand);
          expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

          final baselineTodoWrites = store.todoWrites;
          final baselineCalendarWrites = store.calendarWrites;
          final baselineAuthWrites = store.authWrites;
          final baselineAccountGeneration =
              AccountLocalDataCleaner.accountDataGeneration;

          void assertZeroBusinessWrites(String stage) {
            expect(
              todoProvider.addTodoCalls,
              0,
              reason: '$stage: expected zero TodoProvider addTodo calls',
            );
            expect(
              todoProvider.todos.length,
              0,
              reason: '$stage: expected zero memory todos',
            );
            expect(
              calendarProvider.addCalls,
              0,
              reason: '$stage: expected zero CalendarProvider add calls',
            );
            expect(
              calendarProvider.localEvents.length,
              0,
              reason: '$stage: expected zero memory calendar events',
            );
            expect(
              store.todoWrites,
              baselineTodoWrites,
              reason:
                  '$stage: expected zero storage todo writes (actual=${store.todoWrites}, baseline=$baselineTodoWrites)',
            );
            expect(
              store.calendarWrites,
              baselineCalendarWrites,
              reason:
                  '$stage: expected zero storage calendar writes (actual=${store.calendarWrites}, baseline=$baselineCalendarWrites)',
            );
            expect(
              store.authWrites,
              baselineAuthWrites,
              reason:
                  '$stage: expected zero auth writes (actual=${store.authWrites}, baseline=$baselineAuthWrites)',
            );
            expect(
              AccountLocalDataCleaner.accountDataGeneration,
              baselineAccountGeneration,
              reason: '$stage: expected account generation to be preserved',
            );
          }

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundaryKey = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
                ChangeNotifierProvider<AiService>.value(value: aiService),
                ChangeNotifierProvider<CalendarProvider>.value(
                  value: calendarProvider,
                ),
                ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
                ChangeNotifierProvider<NotificationService>.value(
                  value: notificationService,
                ),
              ],
              child: Consumer<ThemeProvider>(
                builder: (context, currentTheme, _) =>
                    ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (context, currentLocale, _) => MaterialApp(
                        locale: Locale(
                          currentLocale == AppLocale.en ? 'en' : 'zh',
                        ),
                        supportedLocales: const [Locale('en'), Locale('zh')],
                        localizationsDelegates:
                            GlobalMaterialLocalizations.delegates,
                        theme: currentTheme.brand.theme,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(scenario.scale),
                          ),
                          child: RepaintBoundary(
                            key: boundaryKey,
                            child: child!,
                          ),
                        ),
                        home: Builder(
                          builder: (context) => Scaffold(
                            body: Center(
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const BrandRouteSurface(
                                      remountOnLocaleChange: false,
                                      child: AiScheduleScreen(),
                                    ),
                                  ),
                                ),
                                child: const Text('Open AI schedule'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          );

          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          // 1. Open the mounted AiScheduleScreen
          final openBtn = find.text('Open AI schedule');
          await tester.ensureVisible(openBtn);
          expect(openBtn.hitTestable(), findsOneWidget);
          await tester.tap(openBtn);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          final screenFinder = find.byType(AiScheduleScreen);
          expect(screenFinder, findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);

          final initialScreenState = tester.state(screenFinder);
          final initialRoute = ModalRoute.of(tester.element(screenFinder));
          expect(initialRoute, isNotNull);

          final fieldFinder = find.byType(TextField).first;
          expect(fieldFinder, findsOneWidget);
          final initialController = tester
              .widget<TextField>(fieldFinder)
              .controller!;
          expect(initialController.text, isEmpty);

          assertZeroBusinessWrites('1. after route open');
          await _capture(tester, boundaryKey, '${scenario.name}-01-initial');

          // 2. Enter uncommitted draft into input field and exercise selection
          await tester.ensureVisible(fieldFinder);
          await _bounded5s(tester);
          expect(fieldFinder.hitTestable(), findsOneWidget);
          await tester.tap(fieldFinder);
          await tester.enterText(fieldFinder, _testInput);

          const draftSelection = TextSelection(baseOffset: 2, extentOffset: 12);
          initialController.selection = draftSelection;
          await tester.pump();
          expect(initialController.text, _testInput);
          expect(initialController.selection, draftSelection);

          // Exercise deselect / reselect on meaningful input text selection
          // (AiScheduleScreen presents a single generated draft rather than a multi-select task list;
          // user draft selection retention is exercised on the input TextEditingController selection range)
          initialController.selection = const TextSelection.collapsed(
            offset: 0,
          );
          await tester.pump();
          expect(initialController.selection.isCollapsed, isTrue);

          initialController.selection = draftSelection;
          await tester.pump();
          expect(initialController.selection, draftSelection);

          FocusManager.instance.primaryFocus?.unfocus();
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          assertZeroBusinessWrites('2. after draft edit and deselect/reselect');
          await _capture(tester, boundaryKey, '${scenario.name}-02-draft');

          // 3. Start analysis by visible hit-testable tap on recognize button
          final recognizeBtn = find.widgetWithText(
            FilledButton,
            AiScheduleUiCopy.recognize,
          );
          final scrollableFinder = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;

          await tester.scrollUntilVisible(
            recognizeBtn,
            120,
            scrollable: scrollableFinder,
          );
          await tester.ensureVisible(recognizeBtn);
          await _bounded5s(tester);
          expect(recognizeBtn.hitTestable(), findsOneWidget);

          await tester.tap(recognizeBtn);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(
            aiService.recognitions,
            1,
            reason: 'Explicit tap must trigger AI draft recognition once',
          );
          await _assertPreview(tester, scrollableFinder);
          assertZeroBusinessWrites('3. after analysis complete');
          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-03-analyzed',
            reveal: find.text(_testTitle),
            scrollable: scrollableFinder,
          );

          // 4. Retain a meaningful nonzero scroll offset before theme switch
          final scrollState = tester.state<ScrollableState>(scrollableFinder);
          scrollState.position.jumpTo(32.0);
          await _bounded5s(tester);
          final baselineScrollOffset = scrollState.position.pixels;
          expect(baselineScrollOffset, greaterThan(0.0));

          // 5. Live brand switch to targetBrand (liquidGlass or defaultBrand)
          await tester.runAsync(() async {
            final switched = await theme.setBrand(scenario.targetBrand);
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.targetBrand);

          final switchedElement = tester.element(screenFinder);
          final switchedTheme = Theme.of(switchedElement);
          final expectedTargetBrand = AppBrands.byId(scenario.targetBrand);
          expect(
            switchedTheme.colorScheme.primary,
            equals(expectedTargetBrand.theme.colorScheme.primary),
            reason: 'Theme.of colorScheme.primary must match target brand',
          );

          if (scenario.targetBrand == 'liquidGlass') {
            expect(
              appSurfaceStyleOf(switchedElement),
              equals(AppSurfaceStyle.liquidGlass),
              reason: 'liquidGlass brand must supply liquidGlass surface style',
            );
          } else {
            expect(
              appSurfaceStyleOf(switchedElement),
              equals(AppSurfaceStyle.ios),
              reason: 'defaultBrand must have iOS surface style',
            );
          }

          // Assert exact retained meaningful nonzero scroll offset
          final afterThemeScroll = tester.state<ScrollableState>(
            scrollableFinder,
          );
          expect(
            afterThemeScroll.position.pixels,
            closeTo(baselineScrollOffset, 0.001),
            reason:
                'Scroll offset must be exactly retained across theme change to ${scenario.targetBrand}',
          );

          // Assert State and ModalRoute identity retention
          expect(
            identical(tester.state(screenFinder), initialScreenState),
            isTrue,
            reason:
                'AiScheduleScreen State identity must be preserved across targetBrand switch',
          );
          expect(
            identical(ModalRoute.of(switchedElement), initialRoute),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across targetBrand switch',
          );

          // Assert target control (input field) mounted theme, controller, text, and selection
          await _assertInput(
            tester,
            scrollableFinder,
            expectedBrand: expectedTargetBrand,
            initialController: initialController,
            expectedText: _testInput,
            expectedSelection: draftSelection,
          );

          // Assert task preview/title/notes/subtasks retained
          await _assertPreview(tester, scrollableFinder);

          // Assert no analysis replay or writes on theme switch
          expect(
            aiService.recognitions,
            1,
            reason: 'Theme switch must not re-trigger recognition',
          );
          assertZeroBusinessWrites(
            '4. after live brand switch to ${scenario.targetBrand}',
          );
          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-04-target-brand',
            reveal: find.text(_testTitle),
            scrollable: scrollableFinder,
          );

          // 6. Live brand roundtrip back to initialBrand
          await tester.runAsync(() async {
            final reverted = await theme.setBrand(scenario.initialBrand);
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          expect(theme.brand.id, scenario.initialBrand);

          final revertedElement = tester.element(screenFinder);
          final revertedTheme = Theme.of(revertedElement);
          final expectedInitialBrand = AppBrands.byId(scenario.initialBrand);
          expect(
            revertedTheme.colorScheme.primary,
            equals(expectedInitialBrand.theme.colorScheme.primary),
            reason: 'Theme.of colorScheme.primary must revert to initial brand',
          );

          if (scenario.initialBrand == 'liquidGlass') {
            expect(
              appSurfaceStyleOf(revertedElement),
              equals(AppSurfaceStyle.liquidGlass),
              reason: 'Reverting to liquidGlass must restore its surface style',
            );
          } else {
            expect(
              appSurfaceStyleOf(revertedElement),
              equals(AppSurfaceStyle.ios),
              reason:
                  'Reverting to defaultBrand must restore iOS surface style',
            );
          }

          final afterThemeBackScroll = tester.state<ScrollableState>(
            scrollableFinder,
          );
          expect(
            afterThemeBackScroll.position.pixels,
            closeTo(baselineScrollOffset, 0.001),
            reason:
                'Scroll offset must be exactly retained across theme roundtrip back to ${scenario.initialBrand}',
          );

          expect(
            identical(tester.state(screenFinder), initialScreenState),
            isTrue,
            reason:
                'AiScheduleScreen State identity must be preserved across theme roundtrip',
          );
          expect(
            identical(ModalRoute.of(revertedElement), initialRoute),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across theme roundtrip',
          );

          await _assertInput(
            tester,
            scrollableFinder,
            expectedBrand: expectedInitialBrand,
            initialController: initialController,
            expectedText: _testInput,
            expectedSelection: draftSelection,
          );

          await _assertPreview(tester, scrollableFinder);

          expect(
            aiService.recognitions,
            1,
            reason: 'Theme roundtrip must not re-trigger recognition',
          );
          assertZeroBusinessWrites(
            '5. after live brand roundtrip back to ${scenario.initialBrand}',
          );
          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-05-reverted-brand',
            reveal: find.text(_testTitle),
            scrollable: scrollableFinder,
          );

          // 7. Live locale switch to alternative locale
          final altLocale = scenario.locale == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          final beforeLocale = tester
              .state<ScrollableState>(scrollableFinder)
              .position
              .pixels;
          I18n.setLocale(altLocale);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);

          // Localized labels updated in place
          expect(find.text(AiScheduleUiCopy.screenTitle), findsOneWidget);

          final afterLocaleScroll = tester.state<ScrollableState>(
            scrollableFinder,
          );
          expect(
            afterLocaleScroll.position.pixels,
            closeTo(
              beforeLocale.clamp(
                afterLocaleScroll.position.minScrollExtent,
                afterLocaleScroll.position.maxScrollExtent,
              ),
              0.01,
            ),
            reason: 'Scroll offset must observe normal locale scroll clamping',
          );

          expect(
            identical(tester.state(screenFinder), initialScreenState),
            isTrue,
            reason:
                'State identity must be preserved across live locale change',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(screenFinder)),
              initialRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across live locale change',
          );

          await _assertInput(
            tester,
            scrollableFinder,
            expectedBrand: expectedInitialBrand,
            initialController: initialController,
            expectedText: _testInput,
            expectedSelection: draftSelection,
          );

          await _assertPreview(tester, scrollableFinder);

          expect(
            aiService.recognitions,
            1,
            reason: 'Locale switch must not re-trigger recognition',
          );
          assertZeroBusinessWrites('6. after switch to alternative locale');
          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-06-alt-locale',
            reveal: find.text(_testTitle),
            scrollable: scrollableFinder,
          );

          // 8. Live locale switch back to initial locale
          final beforeLocaleBack = tester
              .state<ScrollableState>(scrollableFinder)
              .position
              .pixels;
          I18n.setLocale(scenario.locale);
          await _bounded5s(tester);
          expect(tester.takeException(), isNull);
          final localeBackPosition = tester
              .state<ScrollableState>(scrollableFinder)
              .position;
          expect(
            localeBackPosition.pixels,
            closeTo(
              beforeLocaleBack.clamp(
                localeBackPosition.minScrollExtent,
                localeBackPosition.maxScrollExtent,
              ),
              0.01,
            ),
          );

          expect(find.text(AiScheduleUiCopy.screenTitle), findsOneWidget);

          expect(
            identical(tester.state(screenFinder), initialScreenState),
            isTrue,
            reason:
                'State identity must be preserved across locale revert back',
          );
          expect(
            identical(
              ModalRoute.of(tester.element(screenFinder)),
              initialRoute,
            ),
            isTrue,
            reason:
                'ModalRoute identity must be preserved across locale revert back',
          );

          await _assertInput(
            tester,
            scrollableFinder,
            expectedBrand: expectedInitialBrand,
            initialController: initialController,
            expectedText: _testInput,
            expectedSelection: draftSelection,
          );

          await _assertPreview(tester, scrollableFinder);

          expect(
            aiService.recognitions,
            1,
            reason: 'Locale revert back must not re-trigger recognition',
          );
          assertZeroBusinessWrites('7. after switch back to initial locale');
          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-07-reverted-locale',
            reveal: find.text(_testTitle),
            scrollable: scrollableFinder,
          );

          // 9. Explicit outcome: Cancel/back vs Create
          if (scenario.outcome == _ScheduleContractOutcome.cancel) {
            final back = find.byType(BackButton);
            await tester.ensureVisible(back);
            await _bounded5s(tester);
            expect(back.hitTestable(), findsOneWidget);

            await tester.tap(back);
            await _bounded5s(tester);
            expect(tester.takeException(), isNull);

            expect(find.byType(AiScheduleScreen), findsNothing);
            expect(find.text('Open AI schedule'), findsOneWidget);

            // Zero create writes strictly enforced
            assertZeroBusinessWrites('8. after explicit cancel/back');
            expect(todoProvider.todos, isEmpty);
            expect(calendarProvider.localEvents, isEmpty);

            await _capture(
              tester,
              boundaryKey,
              '${scenario.name}-08-cancelled',
            );
          } else {
            final createButton = find.widgetWithText(
              FilledButton,
              AiScheduleUiCopy.create,
            );
            await tester.scrollUntilVisible(
              createButton,
              150,
              scrollable: scrollableFinder,
            );
            await tester.ensureVisible(createButton);
            await _bounded5s(tester);
            expect(createButton.hitTestable(), findsOneWidget);

            await tester.tap(createButton);
            await _drainAccountWrites(tester);
            await _bounded5s(tester);
            expect(tester.takeException(), isNull);

            // Open completion dialog displayed
            expect(find.byType(AppDialog), findsOneWidget);
            final doneButton = find
                .widgetWithText(FilledButton, AiScheduleUiCopy.done)
                .last;
            await tester.ensureVisible(doneButton);
            await _bounded5s(tester);
            expect(doneButton.hitTestable(), findsOneWidget);

            await tester.tap(doneButton);
            await _drainAccountWrites(tester);
            await _bounded5s(tester);
            expect(tester.takeException(), isNull);

            // Dialog popped and AiScheduleScreen popped back to Home
            expect(find.byType(AiScheduleScreen), findsNothing);
            expect(find.text('Open AI schedule'), findsOneWidget);

            // Exactly one recorded TodoProvider write
            expect(
              todoProvider.addTodoCalls,
              1,
              reason:
                  'Explicit Create must execute exactly one TodoProvider write',
            );
            expect(
              todoProvider.todos.length,
              1,
              reason: 'TodoProvider must have exactly one persisted todo',
            );
            expect(todoProvider.todos.first.title, _testTitle);
            expect(todoProvider.todos.first.notes, _testNotes);
            final persisted =
                jsonDecode(
                      (await SharedPreferences.getInstance()).getString(
                        'todos',
                      )!,
                    )
                    as List<dynamic>;
            expect(persisted, hasLength(1));
            expect(
              (persisted.single as Map<String, dynamic>)['title'],
              _testTitle,
            );
            expect(
              (persisted.single as Map<String, dynamic>)['notes'],
              _testNotes,
            );

            expect(
              store.todoWrites,
              greaterThan(baselineTodoWrites),
              reason: 'Storage todos must be updated on create',
            );
            expect(
              calendarProvider.addCalls,
              0,
              reason: 'Todo creation must not write to CalendarProvider',
            );
            expect(
              calendarProvider.localEvents,
              isEmpty,
              reason: 'CalendarProvider must remain empty',
            );
            expect(
              store.calendarWrites,
              baselineCalendarWrites,
              reason: 'Calendar storage writes must remain zero',
            );
            expect(
              AccountLocalDataCleaner.accountDataGeneration,
              baselineAccountGeneration,
              reason: 'Account data generation must be preserved',
            );

            await _capture(tester, boundaryKey, '${scenario.name}-08-created');
          }

          expect(tester.takeException(), isNull);
        } finally {
          try {
            await _drainAccountWrites(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await _bounded5s(tester);
          } finally {
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = previousStore;
            LocalTimezoneResolver.debugSystemTimeZoneReader =
                originalTimeZoneReader;
            auth.dispose();
            aiService.dispose();
            calendarProvider.dispose();
            todoProvider.dispose();
            notificationService.dispose();
            theme.dispose();
            preferences.dispose();
            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(originalLocale);
          }
        }
      },
    );
  }
}
