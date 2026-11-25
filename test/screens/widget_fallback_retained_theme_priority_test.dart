// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/today_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/rendered_control_contrast.dart';
import '../support/weekly_review_screenshot_font.dart';

/// Bounded pump-and-settle helper matching existing repo retained runtime tests.
Future<int> _boundedPumpAndSettle(
  WidgetTester tester, {
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
}) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

/// Test double simulating recoverable todo provider data loading and mutation.
class _RecoverableTodos extends TodoProvider {
  bool failReads = false;
  int reads = 0;
  final List<TodoItem> _items = [];

  void setItem(TodoItem item) {
    _items.clear();
    _items.add(item);
    notifyListeners();
  }

  void clearItems() {
    _items.clear();
    notifyListeners();
  }

  @override
  List<TodoItem> get todos {
    reads++;
    if (failReads) throw StateError('synthetic-private-error');
    return [..._items, ...super.todos];
  }
}

/// Helper harness configuring multi-providers, routing, dynamic brand/locale and layout boundaries.
class _TestHarness {
  final ThemeProvider theme;
  final AuthProvider auth;
  final PreferencesProvider preferences;
  final _RecoverableTodos todos;
  final CourseProvider courses;
  final AnniversaryProvider anniversaries;
  final GoalProvider goals;
  final HabitProvider habits;
  final NoteProvider notes;
  final DiaryProvider diary;
  final ShareProvider share;
  final GlobalKey boundaryKey = GlobalKey();

  _TestHarness({
    required this.theme,
    required this.auth,
    required this.preferences,
    required this.todos,
    required this.courses,
    required this.anniversaries,
    required this.goals,
    required this.habits,
    required this.notes,
    required this.diary,
    required this.share,
  });

  static Future<_TestHarness> create(
    WidgetTester tester, {
    String brand = 'defaultBrand',
    AppLocale locale = AppLocale.zh,
  }) async {
    SharedPreferences.setMockInitialValues({
      'active_brand': brand,
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    });
    I18n.setLocale(locale);
    final theme = ThemeProvider();
    final auth = AuthProvider();
    final preferences = PreferencesProvider();
    final todos = _RecoverableTodos();
    final courses = CourseProvider();
    final anniversaries = AnniversaryProvider();
    final goals = GoalProvider();
    final habits = HabitProvider();
    final notes = NoteProvider();
    final diary = DiaryProvider();
    final share = ShareProvider();

    await tester.runAsync(theme.loadFromStorage);
    return _TestHarness(
      theme: theme,
      auth: auth,
      preferences: preferences,
      todos: todos,
      courses: courses,
      anniversaries: anniversaries,
      goals: goals,
      habits: habits,
      notes: notes,
      diary: diary,
      share: share,
    );
  }

  void dispose() {
    for (final provider in <ChangeNotifier>[
      theme,
      auth,
      preferences,
      todos,
      courses,
      anniversaries,
      goals,
      habits,
      notes,
      diary,
      share,
    ]) {
      provider.dispose();
    }
  }

  Widget buildApp({
    required Widget home,
    double scale = 1.0,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider<CourseProvider>.value(value: courses),
        ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversaries),
        ChangeNotifierProvider<GoalProvider>.value(value: goals),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<DiaryProvider>.value(value: diary),
        ChangeNotifierProvider<ShareProvider>.value(value: share),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) =>
            ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, currentLocale, _) => MaterialApp(
            theme: themeProvider.brand.theme,
            locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: RepaintBoundary(key: boundaryKey, child: child!),
            ),
            home: home,
          ),
        ),
      ),
    );
  }
}

/// Asserts that rendered text has not exceeded its layout bounds or line limits.
void _assertCompleteText(
  WidgetTester tester,
  Finder textFinder, {
  required String role,
}) {
  expect(textFinder, findsOneWidget, reason: '$role not found');
  final rich = find.descendant(of: textFinder, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(
    rich.evaluate().isEmpty ? textFinder : rich,
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$role exceeded max lines',
  );
  expect(
    paragraph.textSize.width <= paragraph.size.width + 0.5,
    isTrue,
    reason:
        '$role width ${paragraph.textSize.width} exceeds box ${paragraph.size.width}',
  );
  expect(
    paragraph.textSize.height <= paragraph.size.height + 0.5,
    isTrue,
    reason:
        '$role height ${paragraph.textSize.height} exceeds box ${paragraph.size.height}',
  );
}

/// Verifies actual theme id, resolved inherited colors, observable fallback surface,
/// button foreground/background, rendered contrast, 44px touch targets, and route identity.
void _assertFallbackThemeEvidence(
  WidgetTester tester, {
  required Element initialElement,
  required String expectedBrandId,
  required Finder retryFinder,
  required Finder backFinder,
}) {
  // 1. Route Element identity strictly preserved
  final currentScaffold = tester.element(find.byType(Scaffold).last);
  expect(
    currentScaffold,
    same(initialElement),
    reason:
        'Fallback Scaffold element identity must be preserved across live theme changes',
  );

  // 2. Inherited Theme and resolved colors from element context
  final theme = Theme.of(currentScaffold);
  final expectedBrand = AppBrands.byId(expectedBrandId);
  expect(
    theme.colorScheme.primary,
    equals(expectedBrand.theme.colorScheme.primary),
    reason: 'Inherited primary color must match $expectedBrandId',
  );

  // 3. AppSurfaceStyle extension from Theme
  final surfaceStyle = appSurfaceStyleOf(currentScaffold);
  if (expectedBrandId == 'liquidGlass') {
    expect(
      surfaceStyle,
      equals(AppSurfaceStyle.liquidGlass),
      reason: 'Surface style must equal liquidGlass',
    );
  } else {
    expect(
      surfaceStyle,
      equals(AppSurfaceStyle.ios),
      reason: 'Surface style must equal ios for defaultBrand',
    );
  }

  // 4. Observable BrandBackground backdrop evidence
  final brandBackgroundFinder = find.byType(BrandBackground);
  expect(brandBackgroundFinder, findsOneWidget);
  if (expectedBrandId == 'liquidGlass') {
    expect(
      find.descendant(
        of: brandBackgroundFinder,
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
      reason: 'LiquidGlass must render custom backdrop painter',
    );
  }

  // 5. Observable button surface and foreground evidence
  final retryElement = tester.element(retryFinder);
  final expectedButtonStyle = appSecondaryFilledButtonStyle(retryElement);
  final expectedButtonBg =
      expectedButtonStyle.backgroundColor?.resolve(const <WidgetState>{});
  expect(
    expectedButtonBg,
    isNotNull,
    reason:
        'Resolved appSecondaryFilledButtonStyle background must not be null',
  );

  final retryMaterial = tester.widget<Material>(
    find
        .descendant(
          of: retryFinder,
          matching: find.byType(Material),
        )
        .first,
  );
  expect(
    retryMaterial.color,
    equals(expectedButtonBg),
    reason:
        'Rendered retry button Material color must match resolved appSecondaryFilledButtonStyle background for $expectedBrandId',
  );

  // 6. Rendered contrast (WCAG AA >= 4.5:1) and 44px touch target validation
  expectReadableControl(tester, retryFinder);
  expectControlTouchTarget(tester, retryFinder);
  expectControlTouchTarget(tester, backFinder);
}

/// Captures screenshots to DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR using existing helper conventions.
Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('$explicitDir/widget-fallback-retained-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<Map<String, Object?>> _snapshotPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return {for (final key in prefs.getKeys()) key: prefs.get(key)};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_brand': 'defaultBrand',
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    });
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
  });

  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    testWidgets(
      'fallback retains live theme and locale dynamically, semantic 44px targets and complete text at 320px 200% ($initialBrand)',
      (tester) async {
        final harness = await _TestHarness.create(
          tester,
          brand: initialBrand,
          locale: AppLocale.zh,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
          await tester.runAsync(
            () => AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            ),
          );
          harness.dispose();
        });

        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.runAsync(loadWeeklyReviewScreenshotFonts);

        harness.todos.failReads = true;
        const targetId = 'todo-fail-retained-narrow';

        await tester.pumpWidget(
          harness.buildApp(
            scale: 2.0,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('open-detail-btn'),
                    onPressed: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: targetId,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await _boundedPumpAndSettle(tester);

        // Open fallback route
        await tester.tap(find.byKey(const ValueKey('open-detail-btn')));
        await _boundedPumpAndSettle(tester);

        expect(find.byType(BrandRouteSurface), findsOneWidget);
        expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);

        final initialFallbackElement =
            tester.element(find.byType(Scaffold).last);

        // Scope action buttons to fallback Wrap container (AppEmptyState action classes)
        final fallbackWrap = find.descendant(
          of: find.byType(Scaffold).last,
          matching: find.byType(Wrap),
        );
        expect(fallbackWrap, findsOneWidget);

        final retryBtnFinder = find.descendant(
          of: fallbackWrap,
          matching: find.widgetWithText(
            FilledButton,
            I18n.tr('action.retry'),
          ),
        );
        final backBtnFinder = find.descendant(
          of: fallbackWrap,
          matching: find.widgetWithText(
            FilledButton,
            I18n.tr('action.back'),
          ),
        );

        // Verify AppBar navigation back is an IconButton, distinct from body FilledButton
        final appBarBackFinder = find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        );
        expect(appBarBackFinder, findsOneWidget);

        // Verify initial theme evidence under initialBrand
        _assertFallbackThemeEvidence(
          tester,
          initialElement: initialFallbackElement,
          expectedBrandId: initialBrand,
          retryFinder: retryBtnFinder,
          backFinder: backBtnFinder,
        );

        // Verify complete text at 320px width at 200% text scale
        _assertCompleteText(
          tester,
          find.text(TodayUiCopy.detailTitle('todos')),
          role: 'title zh',
        );
        _assertCompleteText(
          tester,
          find.text(TodayUiCopy.detailOpenFailed),
          role: 'body zh',
        );
        _assertCompleteText(
          tester,
          find.descendant(
            of: retryBtnFinder,
            matching: find.text(I18n.tr('action.retry')),
          ),
          role: 'retry btn zh',
        );
        _assertCompleteText(
          tester,
          find.descendant(
            of: backBtnFinder,
            matching: find.text(I18n.tr('action.back')),
          ),
          role: 'back btn zh',
        );

        await _capture(
          tester,
          harness.boundaryKey,
          'mounted-$initialBrand-zh-320px200pct',
        );

        // Live brand switch while mounted (real-I/O via tester.runAsync)
        final alternateBrand = initialBrand == 'defaultBrand'
            ? 'liquidGlass'
            : 'defaultBrand';
        await tester.runAsync(() async {
          final switched = await harness.theme.setBrand(alternateBrand);
          expect(switched, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _boundedPumpAndSettle(tester);

        // Element identity and observable theme evidence under alternateBrand
        _assertFallbackThemeEvidence(
          tester,
          initialElement: initialFallbackElement,
          expectedBrandId: alternateBrand,
          retryFinder: retryBtnFinder,
          backFinder: backBtnFinder,
        );
        await _capture(
          tester,
          harness.boundaryKey,
          'mounted-$alternateBrand-zh-retained',
        );

        // Live locale switch while mounted: zh -> en
        I18n.setLocale(AppLocale.en);
        await _boundedPumpAndSettle(tester);

        expect(
          tester.element(find.byType(Scaffold).last),
          same(initialFallbackElement),
        );
        expect(
          find.text(TodayUiCopy.detailOpenFailed),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);

        final enRetryBtn = find.descendant(
          of: fallbackWrap,
          matching: find.widgetWithText(FilledButton, 'Retry'),
        );
        final enBackBtn = find.descendant(
          of: fallbackWrap,
          matching: find.widgetWithText(FilledButton, 'Back'),
        );

        _assertFallbackThemeEvidence(
          tester,
          initialElement: initialFallbackElement,
          expectedBrandId: alternateBrand,
          retryFinder: enRetryBtn,
          backFinder: enBackBtn,
        );

        _assertCompleteText(
          tester,
          find.text(TodayUiCopy.detailTitle('todos')),
          role: 'title en',
        );
        _assertCompleteText(
          tester,
          find.text(TodayUiCopy.detailOpenFailed),
          role: 'body en',
        );
        _assertCompleteText(
          tester,
          find.descendant(of: enRetryBtn, matching: find.text('Retry')),
          role: 'retry btn en',
        );
        _assertCompleteText(
          tester,
          find.descendant(of: enBackBtn, matching: find.text('Back')),
          role: 'back btn en',
        );

        await _capture(
          tester,
          harness.boundaryKey,
          'mounted-$alternateBrand-en-retained',
        );

        // Live locale switch back to zh
        I18n.setLocale(AppLocale.zh);
        await _boundedPumpAndSettle(tester);
        expect(
          tester.element(find.byType(Scaffold).last),
          same(initialFallbackElement),
        );
        expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);

        // Restore initial brand (real-I/O via tester.runAsync)
        await tester.runAsync(() async {
          final reverted = await harness.theme.setBrand(initialBrand);
          expect(reverted, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          );
        });
        await _boundedPumpAndSettle(tester);

        _assertFallbackThemeEvidence(
          tester,
          initialElement: initialFallbackElement,
          expectedBrandId: initialBrand,
          retryFinder: retryBtnFinder,
          backFinder: backBtnFinder,
        );

        // Back returns directly to source route
        await tester.tap(backBtnFinder);
        await _boundedPumpAndSettle(tester);

        expect(find.byKey(const ValueKey('open-detail-btn')), findsOneWidget);
        expect(find.byType(BrandRouteSurface), findsNothing);
      },
    );
  }

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets(
      'retry target arrives later replaces route with real detail, source remains once, zero extra writes ($brand)',
      (tester) async {
        final harness = await _TestHarness.create(
          tester,
          brand: brand,
          locale: AppLocale.zh,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
          await tester.runAsync(
            () => AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            ),
          );
          harness.dispose();
        });

        harness.todos.failReads = true;
        const targetId = 'todo-target-late-arrived-100';

        await tester.pumpWidget(
          harness.buildApp(
            scale: 1.0,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('open-detail-btn'),
                    onPressed: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: targetId,
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await _boundedPumpAndSettle(tester);

        final baselinePrefs = await _snapshotPrefs();

        // Open fallback
        await tester.tap(find.byKey(const ValueKey('open-detail-btn')));
        await _boundedPumpAndSettle(tester);

        expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);
        final fallbackWrap = find.descendant(
          of: find.byType(Scaffold).last,
          matching: find.byType(Wrap),
        );
        final retryFinder = find.descendant(
          of: fallbackWrap,
          matching: find.widgetWithText(
            FilledButton,
            I18n.tr('action.retry'),
          ),
        );
        expect(retryFinder, findsOneWidget);

        // Target item arrives later in provider
        harness.todos.failReads = false;
        harness.todos.setItem(
          TodoItem(id: targetId, title: 'Late Arrived Target Todo Item'),
        );

        // Tap retry on fallback
        await tester.tap(retryFinder);
        await _boundedPumpAndSettle(tester);

        // Verify route replacement to TodoDetailScreen
        expect(find.text(TodayUiCopy.detailOpenFailed), findsNothing);
        expect(find.byType(TodoDetailScreen), findsOneWidget);

        final detailScreen = tester.widget<TodoDetailScreen>(
          find.byType(TodoDetailScreen),
        );
        expect(detailScreen.todoId, targetId);
        expect(find.text('Late Arrived Target Todo Item'), findsOneWidget);

        // Verify zero extra writes during navigation / retry
        final currentPrefs = await _snapshotPrefs();
        expect(currentPrefs, equals(baselinePrefs));

        // Verify source route remains once
        Navigator.of(tester.element(find.byType(TodoDetailScreen))).pop();
        await _boundedPumpAndSettle(tester);

        expect(find.byType(TodoDetailScreen), findsNothing);
        expect(find.byType(BrandRouteSurface), findsNothing);
        expect(find.byKey(const ValueKey('open-detail-btn')), findsOneWidget);
        expect(
          ModalRoute.of(
            tester.element(find.byKey(const ValueKey('open-detail-btn'))),
          )?.isFirst,
          isTrue,
        );

        final afterPopPrefs = await _snapshotPrefs();
        expect(afterPopPrefs, equals(baselinePrefs));
      },
    );
  }

  testWidgets(
    'stale captured callbacks are guarded after cover, account invalidation, locale change, and route replacement',
    (tester) async {
      final harness = await _TestHarness.create(
        tester,
        brand: 'defaultBrand',
        locale: AppLocale.zh,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _boundedPumpAndSettle(tester);
        await tester.runAsync(
          () => AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          ),
        );
        harness.dispose();
      });

      harness.todos.failReads = true;
      const targetId = 'todo-stale-callback-guard';

      await tester.pumpWidget(
        harness.buildApp(
          scale: 1.0,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-detail-btn'),
                  onPressed: () => TodayDetailRouter.open(
                    context,
                    TodaySectionKind.todos,
                    id: targetId,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _boundedPumpAndSettle(tester);

      await tester.tap(find.byKey(const ValueKey('open-detail-btn')));
      await _boundedPumpAndSettle(tester);

      expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);

      final fallbackWrap = find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Wrap),
      );
      expect(fallbackWrap, findsOneWidget);

      // Capture stale callback closures
      final capturedRetry = tester
          .widget<FilledButton>(
            find.descendant(
              of: fallbackWrap,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.retry'),
              ),
            ),
          )
          .onPressed!;
      final capturedBack = tester
          .widget<FilledButton>(
            find.descendant(
              of: fallbackWrap,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.back'),
              ),
            ),
          )
          .onPressed!;

      // Guard 1: Stale callbacks under covering route
      final coverKey = UniqueKey();
      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(child: Text('CoveringRouteSurface', key: coverKey)),
        ),
      );
      unawaited(
        Navigator.of(tester.element(find.byType(Scaffold).last)).push(
          coveringRoute,
        ),
      );
      await _boundedPumpAndSettle(tester);

      expect(find.byKey(coverKey), findsOneWidget);
      expect(coveringRoute.isCurrent, isTrue);

      final readsBeforeCoveredRetry = harness.todos.reads;
      capturedRetry();
      await _boundedPumpAndSettle(tester);

      expect(find.byKey(coverKey), findsOneWidget);
      expect(coveringRoute.isCurrent, isTrue);
      expect(harness.todos.reads, readsBeforeCoveredRetry);

      capturedBack();
      await _boundedPumpAndSettle(tester);

      expect(find.byKey(coverKey), findsOneWidget);
      expect(coveringRoute.isCurrent, isTrue);

      // Pop covering route normally
      Navigator.of(tester.element(find.byKey(coverKey))).pop();
      await _boundedPumpAndSettle(tester);

      expect(find.byKey(coverKey), findsNothing);
      expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);

      // Guard 2: Stale callbacks under account invalidation
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await _boundedPumpAndSettle(tester);

      expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);
      expect(find.text(I18n.tr('action.retry')), findsNothing);

      final readsBeforeInvalidatedRetry = harness.todos.reads;
      capturedRetry();
      await _boundedPumpAndSettle(tester);

      expect(harness.todos.reads, readsBeforeInvalidatedRetry);
      expect(find.text(TodayUiCopy.detailSourceChanged), findsOneWidget);

      // Dismiss invalidated route via real back button
      await tester.tap(
        find.descendant(
          of: find.descendant(
            of: find.byType(Scaffold).last,
            matching: find.byType(Wrap),
          ),
          matching: find.widgetWithText(FilledButton, I18n.tr('action.back')),
        ),
      );
      await _boundedPumpAndSettle(tester);
      expect(find.byKey(const ValueKey('open-detail-btn')), findsOneWidget);

      // Guard 3: Locale change & route replacement
      // Fresh open with valid account generation
      harness.todos.failReads = true;
      await tester.tap(find.byKey(const ValueKey('open-detail-btn')));
      await _boundedPumpAndSettle(tester);

      expect(find.text(TodayUiCopy.detailOpenFailed), findsOneWidget);

      final postOpenWrap = find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Wrap),
      );
      final preReplacementRetry = tester
          .widget<FilledButton>(
            find.descendant(
              of: postOpenWrap,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.retry'),
              ),
            ),
          )
          .onPressed!;
      final preReplacementBack = tester
          .widget<FilledButton>(
            find.descendant(
              of: postOpenWrap,
              matching: find.widgetWithText(
                FilledButton,
                I18n.tr('action.back'),
              ),
            ),
          )
          .onPressed!;

      // Change locale while mounted
      I18n.setLocale(AppLocale.en);
      await _boundedPumpAndSettle(tester);

      expect(
        find.text(TodayUiCopy.detailOpenFailed),
        findsOneWidget,
      );

      // Target arrives and retry executes
      harness.todos.failReads = false;
      harness.todos.setItem(
        TodoItem(id: targetId, title: 'Locale Migrated Target Todo'),
      );

      preReplacementRetry();
      await _boundedPumpAndSettle(tester);

      // Route has been replaced to TodoDetailScreen
      expect(find.byType(TodoDetailScreen), findsOneWidget);
      expect(find.text('Locale Migrated Target Todo'), findsOneWidget);

      // Guard 4: Invoking pre-replacement callbacks must not pop or mutate new route
      preReplacementRetry();
      await _boundedPumpAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(TodoDetailScreen), findsOneWidget);

      preReplacementBack();
      await _boundedPumpAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(TodoDetailScreen), findsOneWidget);

      // Real back pop returns directly to source route
      Navigator.of(tester.element(find.byType(TodoDetailScreen))).pop();
      await _boundedPumpAndSettle(tester);

      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-detail-btn')), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byKey(const ValueKey('open-detail-btn'))),
        )?.isFirst,
        isTrue,
      );
    },
  );

  testWidgets(
    'missing target fallback opens list, guards stale callbacks across cover and replacement',
    (tester) async {
      final harness = await _TestHarness.create(
        tester,
        brand: 'defaultBrand',
        locale: AppLocale.zh,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _boundedPumpAndSettle(tester);
        await tester.runAsync(
          () => AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 5),
          ),
        );
        harness.dispose();
      });

      harness.todos.failReads = false;
      const targetId = 'todo-item-nonexistent';

      await tester.pumpWidget(
        harness.buildApp(
          scale: 1.0,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open-detail-btn'),
                  onPressed: () => TodayDetailRouter.open(
                    context,
                    TodaySectionKind.todos,
                    id: targetId,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await _boundedPumpAndSettle(tester);

      final baselinePrefs = await _snapshotPrefs();

      // Open missing item fallback
      await tester.tap(find.byKey(const ValueKey('open-detail-btn')));
      await _boundedPumpAndSettle(tester);

      expect(
        find.text(TodayUiCopy.detailMissing('todos')),
        findsOneWidget,
      );

      final fallbackWrap = find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Wrap),
      );
      expect(fallbackWrap, findsOneWidget);

      final listBtnFinder = find.descendant(
        of: fallbackWrap,
        matching: find.widgetWithText(
          FilledButton,
          TodayUiCopy.detailOpenList,
        ),
      );
      final backBtnFinder = find.descendant(
        of: fallbackWrap,
        matching: find.widgetWithText(
          FilledButton,
          I18n.tr('action.back'),
        ),
      );
      expect(listBtnFinder, findsOneWidget);
      expect(backBtnFinder, findsOneWidget);

      expectControlTouchTarget(tester, listBtnFinder);
      expectControlTouchTarget(tester, backBtnFinder);

      final capturedOpenList =
          tester.widget<FilledButton>(listBtnFinder).onPressed!;
      final capturedBack =
          tester.widget<FilledButton>(backBtnFinder).onPressed!;

      // Guard under covering route
      final coverKey = UniqueKey();
      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(child: Text('MissingFallbackCover', key: coverKey)),
        ),
      );
      unawaited(
        Navigator.of(tester.element(find.byType(Scaffold).last)).push(
          coveringRoute,
        ),
      );
      await _boundedPumpAndSettle(tester);

      expect(find.byKey(coverKey), findsOneWidget);
      capturedOpenList();
      await _boundedPumpAndSettle(tester);
      expect(find.byKey(coverKey), findsOneWidget);

      capturedBack();
      await _boundedPumpAndSettle(tester);
      expect(find.byKey(coverKey), findsOneWidget);

      Navigator.of(tester.element(find.byKey(coverKey))).pop();
      await _boundedPumpAndSettle(tester);
      expect(
        find.text(TodayUiCopy.detailMissing('todos')),
        findsOneWidget,
      );

      // Tap View list to replace with TodoScreen
      await tester.tap(listBtnFinder);
      await _boundedPumpAndSettle(tester);

      expect(find.byType(TodoScreen), findsOneWidget);
      expect(
        find.text(TodayUiCopy.detailMissing('todos')),
        findsNothing,
      );

      // Stale callback invocation after replacement
      capturedOpenList();
      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(TodoScreen), findsOneWidget);

      capturedBack();
      await _boundedPumpAndSettle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(TodoScreen), findsOneWidget);

      // Return to source route once
      Navigator.of(tester.element(find.byType(TodoScreen))).pop();
      await _boundedPumpAndSettle(tester);

      expect(find.byType(TodoScreen), findsNothing);
      expect(find.byKey(const ValueKey('open-detail-btn')), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byKey(const ValueKey('open-detail-btn'))),
        )?.isFirst,
        isTrue,
      );

      final finalPrefs = await _snapshotPrefs();
      expect(finalPrefs, equals(baselinePrefs));
    },
  );
}
