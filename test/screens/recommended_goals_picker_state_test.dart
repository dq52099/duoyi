import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/screens/goal_screen.dart';
import 'package:duoyi/screens/recommended_goals_picker.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

const _captureEnvKey = 'DUOYI_CAPTURE_RECOMMENDED_GOALS_SCREENSHOTS';
const _screenshotDirectory = 'evidence/screenshots/recommended-goals-20261015';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Open picker changes locale and preserves category and list position',
    (tester) async {
      final fixture = await _mountPicker(tester, size: const Size(320, 568));
      await _openPicker(tester);

      final picker = find.byType(RecommendedGoalsPicker);
      final pickerState = tester.state<State<RecommendedGoalsPicker>>(picker);
      await tester.tap(_category('study'));
      await tester.pumpAndSettle();

      final list = _goalList('study');
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollable);
      await tester.drag(list, const Offset(0, -32));
      await tester.pumpAndSettle();
      final scrollOffset = scrollState.position.pixels;
      expect(scrollOffset, greaterThan(0));
      await _captureScreenshot(tester, fixture, 'locale-zh-study-scrolled');

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      await _captureScreenshot(tester, fixture, 'locale-en-study-scrolled');

      expect(
        tester.state<State<RecommendedGoalsPicker>>(picker),
        same(pickerState),
      );
      expect(tester.state<ScrollableState>(scrollable), same(scrollState));
      expect(scrollState.position.pixels, closeTo(scrollOffset, 0.1));
      expect(find.text('Recommended goals'), findsOneWidget);

      final selectedCategory = tester.widget<ChoiceChip>(_category('study'));
      expect(selectedCategory.selected, isTrue);
      expect((selectedCategory.label as Text).data, 'Study');

      final readingCard = _goalCard('rec.study.read_30min');
      expect(readingCard, findsOneWidget);
      final cardCopy = tester
          .widgetList<Text>(
            find.descendant(of: readingCard, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .toList();
      expect(cardCopy, contains('Read 30 minutes'));
      expect(cardCopy.length, greaterThan(4));
      for (final text in cardCopy) {
        expect(text, isNot(matches(_cjk)), reason: 'English card copy: $text');
      }
      expect(
        tester.widget<IconButton>(_addButton('rec.study.read_30min')).tooltip,
        'Add to goals',
      );
      expect(fixture.goals.goals, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Held acknowledged apply disables repeats and reports success once',
    (tester) async {
      final fixture = await _mountPicker(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await _openPicker(tester);

      fixture.store.armHold();
      await _addGoal(tester, 'rec.recommend.drink_water');
      await _waitForHeldWrite(tester, fixture.store);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(
        tester
            .widget<IconButton>(_addButton('rec.recommend.drink_water'))
            .onPressed,
        isNull,
      );
      expect(find.byTooltip('Adding…'), findsOneWidget);
      expect(
        find.descendant(
          of: _goalCard('rec.recommend.drink_water'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await _captureScreenshot(tester, fixture, 'apply-adding');

      await tester.tap(_addButton('rec.recommend.drink_water'));
      await tester.pump();
      expect(fixture.store.goalWriteAttempts, 1);
      expect(find.byType(SnackBar), findsNothing);

      await _releaseHeldWrite(tester, fixture);
      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      expect(find.text('Added to your goals'), findsOneWidget);
      expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
      await _captureScreenshot(tester, fixture, 'apply-success');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed apply keeps picker available for retry without success feedback',
    (tester) async {
      final fixture = await _mountPicker(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await _openPicker(tester);
      fixture.store.failNextGoalWrite = true;

      await _addGoal(tester, 'rec.recommend.drink_water');
      await tester.pumpAndSettle();
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
      expect(find.text('Could not add goal. Try again.'), findsOneWidget);
      expect(find.text('Added to your goals'), findsNothing);
      await _captureScreenshot(tester, fixture, 'apply-failed');
      expect(tester.takeException(), isNull);

      await _addGoal(tester, 'rec.recommend.drink_water');
      await tester.pumpAndSettle();
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 2);
      expect(fixture.goals.goals, hasLength(1));
      expect(find.text('Added to your goals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Same-frame cover and return cancels held apply feedback and write',
    (tester) async {
      final fixture = await _mountPicker(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await _openPicker(tester);

      fixture.store.armHold();
      await _addGoal(tester, 'rec.recommend.drink_water');
      await _waitForHeldWrite(tester, fixture.store);

      final pickerRoute = fixture.routeGate.currentRoute;
      final revision = fixture.routeGate.routeRevision.value;
      final navigator = fixture.navigator.currentState!;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Temporary cover')),
          ),
        ),
      );
      navigator.pop();
      expect(fixture.routeGate.routeRevision.value, revision + 2);
      await _pumpFrames(tester, count: 20);

      expect(fixture.routeGate.currentRoute, same(pickerRoute));
      expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
      await _releaseHeldWrite(tester, fixture);

      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Recommended goals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Dismissed picker ignores a late held apply completion', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await _openPicker(tester);

    final pickerRoute = fixture.routeGate.currentRoute;
    fixture.store.armHold();
    await _addGoal(tester, 'rec.recommend.drink_water');
    await _waitForHeldWrite(tester, fixture.store);
    fixture.navigator.currentState!.pop();
    await _pumpFrames(tester, count: 35);

    // iOS Material transitions use a 500ms animation in this SDK.
    // Keep the write held until the route has actually been disposed.
    expect(fixture.routeGate.currentRoute, isNot(same(pickerRoute)));
    expect(find.byType(RecommendedGoalsPicker), findsNothing);
    await _releaseHeldWrite(tester, fixture);

    expect(find.byType(RecommendedGoalsPicker), findsNothing);
    expect(
      find.byKey(const ValueKey('open-recommended-goals')),
      findsOneWidget,
    );
    expect(fixture.goals.goals, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(RecommendedGoalsPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retained View action cannot pop a route covering the picker', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await _openPicker(tester);

    await _addGoal(tester, 'rec.recommend.drink_water');
    await tester.pumpAndSettle();
    await _drainWrites(tester);
    expect(find.text('Added to your goals'), findsOneWidget);
    final view = tester.widget<TextButton>(
      find.byKey(const ValueKey('recommended-goal-view')),
    );
    final retainedView = view.onPressed!;

    final cover = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Newer route')),
    );
    unawaited(fixture.navigator.currentState!.push(cover));
    await tester.pumpAndSettle();
    expect(fixture.routeGate.currentRoute, same(cover));

    retainedView();
    await tester.pumpAndSettle();

    expect(fixture.routeGate.currentRoute, same(cover));
    expect(find.text('Newer route'), findsOneWidget);
    expect(fixture.goals.goals, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('View returns GoalItem through a typed picker route', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();

    final routeResult = fixture.navigator.currentState!.push<GoalItem>(
      MaterialPageRoute<GoalItem>(
        builder: (_) => const RecommendedGoalsPicker(),
      ),
    );
    await tester.pumpAndSettle();
    await _addGoal(tester, 'rec.recommend.drink_water');
    await tester.pumpAndSettle();
    await _drainWrites(tester);

    final view = tester.widget<TextButton>(
      find.byKey(const ValueKey('recommended-goal-view')),
    );
    view.onPressed!();
    await tester.pumpAndSettle();

    final result = await routeResult;
    expect(result, isA<GoalItem>());
    expect(result!.title, isNotEmpty);
    expect(find.byType(RecommendedGoalsPicker), findsNothing);

    fixture.goals.resetLocalState();
    await tester.runAsync(AccountLocalDataCleaner.clearSharedPreferences);
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.containsKey('duoyi_goals'), isFalse);
    expect(fixture.goals.goals, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GoalScreen opens templates and shows the added goal on return', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester, useGoalScreen: true);
    I18n.setLocale(AppLocale.en);
    await tester.pump();

    await tester.tap(find.byTooltip('Recommended templates'));
    await tester.pumpAndSettle();
    expect(find.byType(RecommendedGoalsPicker), findsOneWidget);

    await _addGoal(tester, 'rec.recommend.drink_water');
    await tester.pumpAndSettle();
    await _drainWrites(tester);
    expect(find.text('Added to your goals'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recommended-goal-view')));
    await tester.pumpAndSettle();

    expect(find.byType(RecommendedGoalsPicker), findsNothing);
    expect(find.byType(GoalScreen), findsOneWidget);
    expect(find.text('Drink water daily'), findsOneWidget);
    expect(fixture.goals.goals, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Held apply rejects account reset before storage acknowledgement',
    (tester) async {
      final fixture = await _mountPicker(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await _openPicker(tester);
      fixture.store.armHold();

      await _addGoal(tester, 'rec.recommend.drink_water');
      await _waitForHeldWrite(tester, fixture.store);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      fixture.goals.resetLocalState();
      await tester.pump();

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      I18n.setLocale(AppLocale.en);
      await _pumpFrames(tester, count: 20);
      expect(
        find.text('Page state changed. Return and reopen this page.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(_addButton('rec.recommend.drink_water'))
            .onPressed,
        isNull,
      );
      await _releaseHeldWrite(tester, fixture);
      await tester.runAsync(AccountLocalDataCleaner.clearSharedPreferences);
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();

      expect(fixture.goals.goals, isEmpty);
      expect(preferences.containsKey('duoyi_goals'), isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Held apply rejects same-frame lock then unlock', (tester) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await _openPicker(tester);
    fixture.store.armHold();

    await _addGoal(tester, 'rec.recommend.drink_water');
    await _waitForHeldWrite(tester, fixture.store);
    final accessGeneration = fixture.lock.accessGeneration;

    fixture.lock.setLocked(true);
    fixture.lock.setLocked(false);
    expect(fixture.lock.isLocked, isFalse);
    expect(fixture.lock.accessGeneration, accessGeneration + 2);
    await _pumpFrames(tester, count: 3);
    await _releaseHeldWrite(tester, fixture);

    expect(fixture.goals.goals, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Old add callback rejects same-frame lock cycle while rebuilt add still works',
    (tester) async {
      final fixture = await _mountPicker(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await _openPicker(tester);
      final addFinder = _addButton('rec.recommend.drink_water');
      final oldAdd = tester.widget<IconButton>(addFinder).onPressed!;

      fixture.lock.setLocked(true);
      fixture.lock.setLocked(false);
      expect(fixture.lock.isLocked, isFalse);
      await _pumpFrames(tester, count: 3);
      await tester.pumpAndSettle();
      await _afterCallback(tester, oldAdd);
      await tester.pumpAndSettle();
      await _drainWrites(tester);

      expect(fixture.store.goalWriteAttempts, 0);
      expect(fixture.goals.goals, isEmpty);
      expect(find.byType(SnackBar), findsNothing);

      expect(tester.widget<IconButton>(addFinder).onPressed, isNotNull);
      await _addGoal(tester, 'rec.recommend.drink_water');
      await tester.pumpAndSettle();
      await _drainWrites(tester);
      expect(fixture.store.goalWriteAttempts, 1);
      expect(fixture.goals.goals, hasLength(1));
      expect(find.text('Added to your goals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Old add callback rejects same-frame cover and return', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await _openPicker(tester);
    final oldAdd = tester
        .widget<IconButton>(_addButton('rec.recommend.drink_water'))
        .onPressed!;
    final revision = fixture.routeGate.routeRevision.value;
    final navigator = fixture.navigator.currentState!;

    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Same-frame cover')),
        ),
      ),
    );
    navigator.pop();
    expect(fixture.routeGate.routeRevision.value, revision + 2);
    await tester.pumpAndSettle();

    await _afterCallback(tester, oldAdd);
    await tester.pumpAndSettle();
    await _drainWrites(tester);

    expect(fixture.store.goalWriteAttempts, 0);
    expect(fixture.goals.goals, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(RecommendedGoalsPicker), findsOneWidget);

    expect(
      tester
          .widget<IconButton>(_addButton('rec.recommend.drink_water'))
          .onPressed,
      isNotNull,
    );
    await _addGoal(tester, 'rec.recommend.drink_water');
    await tester.pumpAndSettle();
    await _drainWrites(tester);
    expect(fixture.store.goalWriteAttempts, 1);
    expect(fixture.goals.goals, hasLength(1));
    expect(find.text('Added to your goals'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retained category callback is inert after picker disposal', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    await _openPicker(tester);
    final oldSelect = tester.widget<ChoiceChip>(_category('study')).onSelected!;

    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(RecommendedGoalsPicker), findsNothing);

    oldSelect(true);
    await tester.pumpAndSettle();

    expect(fixture.store.goalWriteAttempts, 0);
    expect(find.byType(RecommendedGoalsPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Replacing access authority expires the page and its retained Add',
    (tester) async {
      final fixture = await _mountPicker(tester);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await _openPicker(tester);
      final oldAdd = tester
          .widget<IconButton>(_addButton('rec.recommend.drink_water'))
          .onPressed!;
      final replacement = _PickerLock();
      addTearDown(replacement.dispose);
      fixture.lockSource.value = replacement;
      await tester.pumpAndSettle();
      await _afterCallback(tester, oldAdd);
      await _drainWrites(tester);
      expect(fixture.goals.goals, isEmpty);
      expect(
        find.text('Page state changed. Return and reopen this page.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(_addButton('rec.recommend.drink_water'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Expired page Back respects access and then returns safely', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await _openPicker(tester);
    fixture.goals.resetLocalState();
    await tester.pumpAndSettle();
    await _captureScreenshot(tester, fixture, 'page-expired');
    final oldBack = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Back to goals'))
        .onPressed!;
    fixture.lock.setLocked(true);
    await _afterCallback(tester, oldBack);
    await tester.pumpAndSettle();
    expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
    fixture.lock.setLocked(false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Back to goals'));
    await tester.pumpAndSettle();
    expect(find.byType(RecommendedGoalsPicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Account invalidation removes only this page success feedback', (
    tester,
  ) async {
    final fixture = await _mountPicker(tester);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    await _openPicker(tester);
    await _addGoal(tester, 'rec.recommend.drink_water');
    await tester.pumpAndSettle();
    expect(find.text('Added to your goals'), findsOneWidget);
    fixture.goals.resetLocalState();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.text('Page state changed. Return and reopen this page.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final layout in <_LayoutCase>[
    const _LayoutCase(
      name: '320px iOS viewport with keyboard inset',
      fileName: 'phone-320x844',
      size: Size(320, 844),
      keyboardInset: 290,
    ),
    const _LayoutCase(
      name: 'landscape iOS viewport with keyboard inset',
      fileName: 'landscape-568x320',
      size: Size(568, 320),
      keyboardInset: 110,
    ),
  ]) {
    testWidgets('Picker stays usable in ${layout.name} at text scale 1.3', (
      tester,
    ) async {
      I18n.setLocale(AppLocale.en);
      final fixture = await _mountPicker(
        tester,
        size: layout.size,
        textScale: 1.3,
        keyboardInset: layout.keyboardInset,
      );
      await _openPicker(tester);

      expect(find.text('Recommended goals'), findsOneWidget);
      expect(_goalList('recommend'), findsOneWidget);
      await _captureScreenshot(
        tester,
        fixture,
        'layout-${layout.fileName}-top',
      );
      await tester.scrollUntilVisible(
        _goalCard('rec.recommend.daily_review'),
        160,
        scrollable: find.descendant(
          of: _goalList('recommend'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(_goalCard('rec.recommend.daily_review'), findsOneWidget);
      await _captureScreenshot(
        tester,
        fixture,
        'layout-${layout.fileName}-scrolled',
      );
      expect(tester.takeException(), isNull);
    });
  }
}

final _cjk = RegExp(r'[\u3400-\u9fff]');

Finder _category(String category) =>
    find.byKey(ValueKey('recommended-category-$category'));

Finder _goalList(String category) =>
    find.byKey(PageStorageKey<String>('recommended-goal-list-$category'));

Finder _goalCard(String id) => find.byKey(ValueKey('recommended-goal-$id'));

Finder _addButton(String id) => find.byKey(ValueKey('recommended-add-$id'));

bool get _captureScreenshots => Platform.environment[_captureEnvKey] == '1';

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-recommended-goals')));
  await tester.pumpAndSettle();
  expect(find.byType(RecommendedGoalsPicker), findsOneWidget);
}

Future<_Fixture> _mountPicker(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboardInset = 0,
  bool useGoalScreen = false,
}) async {
  final fixture = _Fixture();
  if (_captureScreenshots) {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
  }
  SharedPreferencesStorePlatform.instance = fixture.store;
  await tester.runAsync(fixture.goals.loadFromStorage);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    if (!fixture.store.release.isCompleted) fixture.store.release.complete();
    // Flush continuations registered in the test zone before a real async drain.
    await _pumpFrames(tester, count: 5);
    await tester.runAsync(() async {
      await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.routeGate.dispose();
    fixture.goals.dispose();
    fixture.lock.dispose();
    fixture.lockSource.dispose();
    tester.view.reset();
  });

  final baseTheme = AppBrands.defaultBrand.theme;
  final theme = _captureScreenshots
      ? baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
          snackBarTheme: baseTheme.snackBarTheme.copyWith(
            contentTextStyle: baseTheme.snackBarTheme.contentTextStyle
                ?.copyWith(
                  fontFamily: 'DuoyiScreenshotLatin',
                  fontFamilyFallback: const ['DuoyiScreenshot'],
                ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: baseTheme.textButtonTheme.style?.copyWith(
              textStyle: WidgetStatePropertyAll(
                baseTheme.textTheme.labelLarge?.copyWith(
                  fontFamily: 'DuoyiScreenshotLatin',
                  fontFamilyFallback: const ['DuoyiScreenshot'],
                ),
              ),
            ),
          ),
          primaryTextTheme: baseTheme.primaryTextTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
            fontFamilyFallback: const ['DuoyiScreenshot'],
          ),
        )
      : baseTheme;
  await tester.pumpWidget(
    ValueListenableBuilder<AppLockProvider>(
      valueListenable: fixture.lockSource,
      builder: (context, lock, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<GoalProvider>.value(value: fixture.goals),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ],
        child: MaterialApp(
          navigatorKey: fixture.navigator,
          navigatorObservers: [fixture.routeGate],
          theme: theme.copyWith(platform: TargetPlatform.iOS),
          builder: (context, child) => RepaintBoundary(
            key: fixture.screenshotBoundary,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: keyboardInset),
              ),
              child: child!,
            ),
          ),
          home: useGoalScreen
              ? const GoalScreen()
              : Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        key: const ValueKey('open-recommended-goals'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const RecommendedGoalsPicker(),
                          ),
                        ),
                        child: const Text('Open recommended goals'),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _waitForHeldWrite(WidgetTester tester, _GoalStore store) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (store.started.isCompleted) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (store.started.isCompleted) return;
  }
  expect(store.started.isCompleted, isTrue, reason: 'held goal write started');
}

Future<void> _addGoal(WidgetTester tester, String id) async {
  final callback = tester.widget<IconButton>(_addButton(id)).onPressed;
  expect(callback, isNotNull, reason: 'Add is enabled for $id');
  await _afterCallback(tester, callback!);
}

Future<void> _afterCallback(WidgetTester tester, VoidCallback callback) async {
  await tester.runAsync(() async {
    callback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

Future<void> _drainWrites(WidgetTester tester) async {
  await tester.runAsync(AccountPreferenceWrites.drain);
  await tester.pumpAndSettle();
}

Future<void> _releaseHeldWrite(WidgetTester tester, _Fixture fixture) async {
  if (!fixture.store.release.isCompleted) fixture.store.release.complete();
  await _pumpFrames(tester, count: 5);
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpFrames(WidgetTester tester, {required int count}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  _Fixture fixture,
  String name,
) async {
  if (!_captureScreenshots) return;
  await tester.runAsync(() async {
    final boundary =
        fixture.screenshotBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$_screenshotDirectory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _Fixture {
  final goals = GoalProvider();
  final lock = _PickerLock();
  late final lockSource = ValueNotifier<AppLockProvider>(lock);
  final store = _GoalStore();
  final navigator = GlobalKey<NavigatorState>();
  final routeGate = AppAccessRouteGate();
  final screenshotBoundary = GlobalKey();
}

class _GoalStore extends InMemorySharedPreferencesStore {
  _GoalStore() : super.withData(<String, Object>{});

  int goalWriteAttempts = 0;
  bool holdNextGoalWrite = false;
  bool failNextGoalWrite = false;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();

  void armHold() {
    holdNextGoalWrite = true;
    started = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_goals') {
      goalWriteAttempts++;
      if (holdNextGoalWrite) {
        holdNextGoalWrite = false;
        started.complete();
        await release.future;
      }
      if (failNextGoalWrite) {
        failNextGoalWrite = false;
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

class _PickerLock extends AppLockProvider {
  bool _locked = false;
  int _accessGeneration = 0;

  @override
  bool get isLocked => _locked;

  @override
  int get accessGeneration => _accessGeneration;

  void setLocked(bool value) {
    if (_locked == value) return;
    _locked = value;
    _accessGeneration++;
    notifyListeners();
  }
}

class _LayoutCase {
  const _LayoutCase({
    required this.name,
    required this.fileName,
    required this.size,
    required this.keyboardInset,
  });

  final String name;
  final String fileName;
  final Size size;
  final double keyboardInset;
}
