import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

/// Synthetic test data generator for quadrant scroll clearance tests.
List<TodoItem> _createSyntheticTodos(int count) {
  final now = DateTime.now();
  return List.generate(
    count,
    (index) => TodoItem(
      id: 'fixture-quadrant-task-$index',
      title: '象限测试任务 ${index + 1}',
      quadrant: EisenhowerQuadrant.urgentImportant,
      priority: TodoPriority.values[index % TodoPriority.values.length],
      dueDate: now.add(Duration(hours: index + 1)),
    ),
  );
}

/// Recording provider tracking operation counts for gesture safety assertions.
class _RecordingTodoProvider extends TodoProvider {
  final List<Set<String>> deleteCalls = [];
  final List<Set<String>> completeCalls = [];

  @override
  Future<int> deleteTodos(Iterable<String> ids) {
    final snapshot = ids.toSet();
    deleteCalls.add(snapshot);
    return super.deleteTodos(snapshot);
  }

  @override
  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) {
    final snapshot = ids.toSet();
    completeCalls.add(snapshot);
    return super.completeTodos(
      snapshot,
      recordCompletionTime: recordCompletionTime,
    );
  }
}

/// Harness encapsulating providers and keys for QuadrantListScreen fixtures.
class _QuadrantHarness {
  final GlobalKey boundaryKey;
  final ThemeProvider theme;
  final AuthProvider auth;
  final _RecordingTodoProvider todoProvider;
  final ShareProvider shareProvider;
  final PreferencesProvider preferencesProvider;
  final AiService aiService;

  _QuadrantHarness({
    required this.boundaryKey,
    required this.theme,
    required this.auth,
    required this.todoProvider,
    required this.shareProvider,
    required this.preferencesProvider,
    required this.aiService,
  });

  Future<void> dispose() async {
    auth.dispose();
    theme.dispose();
    todoProvider.dispose();
    shareProvider.dispose();
    preferencesProvider.dispose();
    aiService.dispose();
  }
}

/// Bounded pump and settle helper ensuring frames settle within <= 5s.
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

/// Mounts [QuadrantListScreen] within the realistic provider, brand, locale,
/// and route surface hierarchy with live ThemeProvider support.
Future<_QuadrantHarness> _mountQuadrantScreen(
  WidgetTester tester, {
  required String initialBrand,
  required AppLocale initialLocale,
  required Size physicalSize,
  required double textScale,
  required ValueChanged<EisenhowerQuadrant>? onCreateTodo,
  List<TodoItem>? initialTodos,
}) async {
  SharedPreferences.setMockInitialValues({
    'active_brand': initialBrand,
    'theme_shop_state': jsonEncode({
      'activeBrand': initialBrand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'pref_show_completed_todos': true,
  });
  I18n.setLocale(initialLocale);

  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = AuthProvider(
    client: ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((_) async => fail('No fixture HTTP')),
    ),
  );

  final theme = ThemeProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });

  final todoProvider = _RecordingTodoProvider();
  final items = initialTodos ?? _createSyntheticTodos(15);
  for (final item in items) {
    await todoProvider.addTodo(item);
  }

  final shareProvider = ShareProvider();
  final preferencesProvider = PreferencesProvider();
  final aiService = AiService();

  final boundaryKey = GlobalKey();

  final harness = _QuadrantHarness(
    boundaryKey: boundaryKey,
    theme: theme,
    auth: auth,
    todoProvider: todoProvider,
    shareProvider: shareProvider,
    preferencesProvider: preferencesProvider,
    aiService: aiService,
  );

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _boundedPumpAndSettle(tester);
    await harness.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
        ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
        ChangeNotifierProvider<PreferencesProvider>.value(
          value: preferencesProvider,
        ),
        ChangeNotifierProvider<AiService>.value(value: aiService),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([theme, I18n.localeListenable]),
        builder: (context, _) => MaterialApp(
          locale: Locale(I18n.current == AppLocale.en ? 'en' : 'zh'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: boundaryKey, child: child!),
          ),
          home: BrandRouteSurface(
            remountOnLocaleChange: false,
            child: QuadrantListScreen(
              quadrant: EisenhowerQuadrant.urgentImportant,
              onCreateTodo: onCreateTodo,
            ),
          ),
        ),
      ),
    ),
  );
  await _boundedPumpAndSettle(tester);
  return harness;
}

/// Optional environment-controlled screenshot capture utility.
/// Output restricted strictly to evidence/screenshots/widget-live-parallel-20261023/quadrant-scroll/.
Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_SECONDARY_SCREENSHOTS'] ??
      (Platform.environment['DUOYI_CAPTURE_SCREENSHOTS'] == '1'
          ? 'evidence/screenshots/widget-live-parallel-20261023/quadrant-scroll'
          : null);
  if (explicitDir == null || explicitDir.isEmpty) return;

  await tester.runAsync(() async {
    final render =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (render == null) return;
    final image = await render.toImage(pixelRatio: 1.0);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final file = File('$explicitDir/$filename.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(byteData.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// Measured geometric clearance values between FAB and the last task row.
class ClearanceMeasurement {
  final Rect fabRect;
  final Rect lastTileRect;
  final bool overlaps;
  final double verticalOverlap;
  final double horizontalOverlap;
  final double clearance;

  const ClearanceMeasurement({
    required this.fabRect,
    required this.lastTileRect,
    required this.overlaps,
    required this.verticalOverlap,
    required this.horizontalOverlap,
    required this.clearance,
  });

  @override
  String toString() =>
      'ClearanceMeasurement(overlaps: $overlaps, clearance: $clearance, verticalOverlap: $verticalOverlap, horizontalOverlap: $horizontalOverlap, fabRect: $fabRect, lastTileRect: $lastTileRect)';
}

/// Measures the geometric overlap and clearance between FAB and last task tile.
ClearanceMeasurement _measureFabClearance(
  WidgetTester tester, {
  required Finder fabFinder,
  required Finder lastTileFinder,
}) {
  expect(
    fabFinder,
    findsOneWidget,
    reason: 'FAB must be present to measure clearance',
  );
  expect(
    lastTileFinder,
    findsOneWidget,
    reason: 'Last tile must be visible to measure clearance',
  );

  final fabRect = tester.getRect(fabFinder);
  final lastTileRect = tester.getRect(lastTileFinder);

  final overlaps = fabRect.overlaps(lastTileRect);
  final clearance = fabRect.top - lastTileRect.bottom;

  final verticalOverlap = overlaps
      ? (math.min(fabRect.bottom, lastTileRect.bottom) -
            math.max(fabRect.top, lastTileRect.top))
      : 0.0;

  final horizontalOverlap = overlaps
      ? (math.min(fabRect.right, lastTileRect.right) -
            math.max(fabRect.left, lastTileRect.left))
      : 0.0;

  final measurement = ClearanceMeasurement(
    fabRect: fabRect,
    lastTileRect: lastTileRect,
    overlaps: overlaps,
    verticalOverlap: verticalOverlap,
    horizontalOverlap: horizontalOverlap,
    clearance: clearance,
  );
  debugPrint('Measured FAB clearance: $measurement');
  return measurement;
}

/// Finds the _TodoTile widget containing the given title string.
Finder _findTodoTile(String title) {
  return find.ancestor(
    of: find.text(title),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_TodoTile',
    ),
  );
}

/// Uses bounded real drag gestures until current actual maxScrollExtent is reached
/// within tolerance, followed by explicitly revealing the final row.
Future<void> _scrollToBottom(
  WidgetTester tester, {
  required Finder targetItem,
  double tolerance = 1.0,
  int maxDrags = 20,
}) async {
  final scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);

  for (var i = 0; i < maxDrags; i++) {
    final state = tester.state<ScrollableState>(scrollable);
    final remaining = state.position.maxScrollExtent - state.position.pixels;
    if (remaining <= tolerance) break;

    final dragDistance = math.min(remaining + 40.0, 320.0);
    await tester.drag(find.byType(ListView), Offset(0, -dragDistance));
    await tester.pump(const Duration(milliseconds: 50));
    await _boundedPumpAndSettle(tester);
  }

  // Explicitly ensure the target row is revealed in the viewport
  await tester.scrollUntilVisible(targetItem, 80, scrollable: scrollable);
  await _boundedPumpAndSettle(tester);

  // If there is still unconsumed extent to reach absolute bottom:
  final state = tester.state<ScrollableState>(scrollable);
  final remaining = state.position.maxScrollExtent - state.position.pixels;
  if (remaining > tolerance) {
    await tester.drag(find.byType(ListView), Offset(0, -remaining));
    await tester.pump(const Duration(milliseconds: 50));
    await _boundedPumpAndSettle(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    SharedPreferences.setMockInitialValues({'active_brand': 'defaultBrand'});
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  testWidgets(
    'quadrant-scroll: portrait (390x844) 200% text FAB occlusion with live brand & locale switch',
    (tester) async {
      EisenhowerQuadrant? createdQuadrant;

      final harness = await _mountQuadrantScreen(
        tester,
        initialBrand: 'defaultBrand',
        initialLocale: AppLocale.zh,
        physicalSize: const Size(390, 844),
        textScale: 2.0,
        onCreateTodo: (q) => createdQuadrant = q,
      );

      // Verify initial state
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);
      expect(
        find.text(
          TodoBoardUiCopy.quadrantLabel(EisenhowerQuadrant.urgentImportant),
        ),
        findsOneWidget,
      );
      expect(harness.theme.brand.id, 'defaultBrand');
      expect(harness.theme.isBrandUnlocked('defaultBrand'), isTrue);
      expect(harness.theme.isBrandUnlocked('liquidGlass'), isTrue);

      final initialRouteState = tester.state(find.byType(QuadrantListScreen));
      final initialModalRoute = ModalRoute.of(
        tester.element(find.byType(QuadrantListScreen)),
      );

      final lastTileFinder = _findTodoTile(
        harness.todoProvider.todos.last.title,
      );

      // Real scroll gesture down to the last item
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final scrollError = tester.takeException();
      expect(
        scrollError,
        isNull,
        reason:
            'Real scroll gesture should not produce layout-time setState failure',
      );

      final scrollState = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      final initialOffsetSnapshot = scrollState.position.pixels;
      final initialMaxExtentSnapshot = scrollState.position.maxScrollExtent;
      expect(
        initialOffsetSnapshot,
        greaterThan(0),
        reason: 'List must be scrolled',
      );
      expect(
        initialOffsetSnapshot,
        closeTo(initialMaxExtentSnapshot, 1.0),
        reason: 'List must reach bottom extent within tolerance',
      );

      // Desired invariant: FAB must not occlude the last item, clearance must be non-negative
      final measurement = _measureFabClearance(
        tester,
        fabFinder: fabFinder,
        lastTileFinder: lastTileFinder,
      );
      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        'baseline-portrait-before-clearance-assertion',
      );

      expect(
        measurement.overlaps,
        isFalse,
        reason:
            'Desired invariant: FAB must not occlude the last task row when scrolled to bottom',
      );
      expect(
        measurement.clearance,
        greaterThanOrEqualTo(0.0),
        reason:
            'Desired invariant: clearance between last row and FAB must be non-negative (safe margin)',
      );

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '01-portrait-fab-clearance-default-zh',
      );

      // Live Brand Switch: defaultBrand -> liquidGlass
      expect(harness.theme.isBrandUnlocked('liquidGlass'), isTrue);
      await tester.runAsync(() async {
        final switched = await harness.theme.setBrand('liquidGlass');
        expect(switched, isTrue);
      });
      await _boundedPumpAndSettle(tester);

      expect(harness.theme.brand.id, 'liquidGlass');
      expect(
        tester.state(find.byType(QuadrantListScreen)),
        same(initialRouteState),
        reason:
            'Mounted state of QuadrantListScreen must be retained across brand switch',
      );
      expect(
        ModalRoute.of(tester.element(find.byType(QuadrantListScreen))),
        same(initialModalRoute),
        reason: 'ModalRoute must remain identical across brand switch',
      );

      final scrollStateAfterBrand = tester.state<ScrollableState>(
        find.byType(Scrollable),
      );
      expect(
        scrollStateAfterBrand.position.pixels,
        closeTo(initialOffsetSnapshot, 1.0),
        reason:
            'Scroll offset must be preserved across brand switch at equivalent layout',
      );

      // Recompute extent and reveal final row in new brand styling
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final glassMeasurement = _measureFabClearance(
        tester,
        fabFinder: fabFinder,
        lastTileFinder: lastTileFinder,
      );
      expect(
        glassMeasurement.overlaps,
        isFalse,
        reason:
            'Desired invariant: FAB must not occlude last row under liquidGlass',
      );
      expect(
        glassMeasurement.clearance,
        greaterThanOrEqualTo(0.0),
        reason:
            'Desired invariant: clearance must remain non-negative under liquidGlass',
      );

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '02-portrait-fab-clearance-liquidGlass-zh',
      );

      // Live Locale Switch: zh -> en
      I18n.setLocale(AppLocale.en);
      await _boundedPumpAndSettle(tester);

      expect(
        find.text(
          TodoBoardUiCopy.quadrantLabel(EisenhowerQuadrant.urgentImportant),
        ),
        findsOneWidget,
      );
      expect(
        tester.state(find.byType(QuadrantListScreen)),
        same(initialRouteState),
        reason:
            'QuadrantListScreen implements LocaleStatePreservingRoute and retains state',
      );

      // Recompute extent and reveal final row in English locale
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final localeMeasurement = _measureFabClearance(
        tester,
        fabFinder: fabFinder,
        lastTileFinder: lastTileFinder,
      );
      expect(
        localeMeasurement.overlaps,
        isFalse,
        reason:
            'Desired invariant: FAB must not occlude last row in English locale',
      );
      expect(
        localeMeasurement.clearance,
        greaterThanOrEqualTo(0.0),
        reason: 'Desired invariant: clearance must be non-negative in English',
      );

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '03-portrait-fab-clearance-liquidGlass-en',
      );

      // Revert Brand and Locale
      expect(harness.theme.isBrandUnlocked('defaultBrand'), isTrue);
      await tester.runAsync(() async {
        final reverted = await harness.theme.setBrand('defaultBrand');
        expect(reverted, isTrue);
      });
      I18n.setLocale(AppLocale.zh);
      await _boundedPumpAndSettle(tester);

      expect(harness.theme.brand.id, 'defaultBrand');
      expect(
        tester.state(find.byType(QuadrantListScreen)),
        same(initialRouteState),
      );

      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final revertedMeasurement = _measureFabClearance(
        tester,
        fabFinder: fabFinder,
        lastTileFinder: lastTileFinder,
      );
      expect(revertedMeasurement.overlaps, isFalse);
      expect(revertedMeasurement.clearance, greaterThanOrEqualTo(0.0));

      // Real FAB trigger check
      await tester.tap(fabFinder);
      await tester.pump();

      expect(
        createdQuadrant,
        EisenhowerQuadrant.urgentImportant,
        reason: 'FAB callback must deliver current quadrant to onCreateTodo',
      );
    },
  );

  testWidgets(
    'quadrant-scroll: landscape (844x390) 200% text FAB occlusion with live orientation resize',
    (tester) async {
      final harness = await _mountQuadrantScreen(
        tester,
        initialBrand: 'liquidGlass',
        initialLocale: AppLocale.en,
        physicalSize: const Size(844, 390),
        textScale: 2.0,
        onCreateTodo: (_) {},
      );

      expect(harness.theme.isBrandUnlocked('liquidGlass'), isTrue);
      final initialRouteState = tester.state(find.byType(QuadrantListScreen));
      expect(
        find.text(
          TodoBoardUiCopy.quadrantLabel(EisenhowerQuadrant.urgentImportant),
        ),
        findsOneWidget,
      );

      final lastTileFinder = _findTodoTile(
        harness.todoProvider.todos.last.title,
      );

      // Real scroll to bottom in landscape orientation
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final scrollError = tester.takeException();
      expect(
        scrollError,
        isNull,
        reason:
            'Landscape scrolling should not produce layout-time setState errors',
      );

      final fabFinder = find.byType(FloatingActionButton);
      final measurement = _measureFabClearance(
        tester,
        fabFinder: fabFinder,
        lastTileFinder: lastTileFinder,
      );
      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        'baseline-landscape-before-clearance-assertion',
      );

      expect(
        measurement.overlaps,
        isFalse,
        reason:
            'Desired invariant: in landscape 844x390, FAB must not occlude the last tile',
      );
      expect(
        measurement.clearance,
        greaterThanOrEqualTo(0.0),
        reason: 'Desired invariant: landscape clearance must be non-negative',
      );

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '04-landscape-fab-clearance-liquidGlass-en',
      );

      // Live window resize from landscape (844x390) to portrait (390x844)
      tester.view.physicalSize = const Size(390, 844);
      await _boundedPumpAndSettle(tester);

      final resizeError = tester.takeException();
      expect(
        resizeError,
        isNull,
        reason:
            'Window resize while scrolled must not trigger layout-time setState errors',
      );
      expect(
        tester.state(find.byType(QuadrantListScreen)),
        same(initialRouteState),
        reason: 'State retained through window resize',
      );

      // Recompute extent in portrait dimensions and reveal final row
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final portraitMeasurement = _measureFabClearance(
        tester,
        fabFinder: fabFinder,
        lastTileFinder: lastTileFinder,
      );
      expect(
        portraitMeasurement.overlaps,
        isFalse,
        reason:
            'Desired invariant: FAB must not occlude last row after resizing to portrait',
      );
      expect(portraitMeasurement.clearance, greaterThanOrEqualTo(0.0));

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '05-resized-portrait-liquidGlass-en',
      );
    },
  );

  testWidgets(
    'quadrant-scroll: batch mode comparison baseline removes FAB and displays action bar',
    (tester) async {
      final harness = await _mountQuadrantScreen(
        tester,
        initialBrand: 'defaultBrand',
        initialLocale: AppLocale.zh,
        physicalSize: const Size(390, 844),
        textScale: 2.0,
        onCreateTodo: (_) {},
      );

      // Enter batch mode
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await _boundedPumpAndSettle(tester);

      // In batch mode, FAB is removed and bottomNavigationBar is present
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'FAB must be removed in batch mode',
      );
      final batchBarFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_TodoBatchActionBar',
      );
      expect(
        batchBarFinder,
        findsOneWidget,
        reason: 'Batch action bar mounted in bottomNavigationBar',
      );
      expect(find.text('已选择 0 项'), findsOneWidget);

      final lastTileFinder = _findTodoTile(
        harness.todoProvider.todos.last.title,
      );

      // Scroll to bottom
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      expect(lastTileFinder, findsOneWidget);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'No FAB present in batch mode, hence zero FAB occlusion',
      );

      final batchBarRect = tester.getRect(batchBarFinder);
      final lastTileRect = tester.getRect(lastTileFinder);
      expect(
        batchBarRect.overlaps(lastTileRect),
        isFalse,
        reason:
            'Scaffold bottomNavigationBar automatically reserves body height so batch bar does not occlude last tile',
      );

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '06-batch-mode-no-fab-baseline',
      );

      // Select item and verify batch bar updates
      await tester.tap(find.text(harness.todoProvider.todos.last.title));
      await _boundedPumpAndSettle(tester);
      expect(find.text('已选择 1 项'), findsOneWidget);

      // Exit batch mode
      await tester.tap(find.byIcon(Icons.close));
      await _boundedPumpAndSettle(tester);

      expect(
        find.byType(FloatingActionButton),
        findsOneWidget,
        reason: 'FAB returns upon exiting batch mode',
      );

      // Recompute extent and reveal final row
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      final revertedMeasurement = _measureFabClearance(
        tester,
        fabFinder: find.byType(FloatingActionButton),
        lastTileFinder: lastTileFinder,
      );
      expect(
        revertedMeasurement.overlaps,
        isFalse,
        reason:
            'Desired invariant: FAB must not occlude the last item upon returning to standard mode',
      );
      expect(revertedMeasurement.clearance, greaterThanOrEqualTo(0.0));
    },
  );

  testWidgets(
    'quadrant-scroll: no-FAB comparison baseline (onCreateTodo == null) exhibits zero occlusion',
    (tester) async {
      final harness = await _mountQuadrantScreen(
        tester,
        initialBrand: 'liquidGlass',
        initialLocale: AppLocale.zh,
        physicalSize: const Size(390, 844),
        textScale: 2.0,
        onCreateTodo: null,
      );

      // Verify FAB is completely absent when onCreateTodo is null
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason:
            'When onCreateTodo is null, FloatingActionButton is not created',
      );

      final lastTileFinder = _findTodoTile(
        harness.todoProvider.todos.last.title,
      );

      // Scroll to bottom
      await _scrollToBottom(tester, targetItem: lastTileFinder);

      expect(lastTileFinder, findsOneWidget);
      expect(
        find.byType(FloatingActionButton),
        findsNothing,
        reason: 'No FAB in view hierarchy, zero occlusion on the bottom item',
      );

      await _captureScreenshot(
        tester,
        harness.boundaryKey,
        '07-no-fab-null-callback-baseline',
      );

      // Live Brand Switch to defaultBrand
      expect(harness.theme.isBrandUnlocked('defaultBrand'), isTrue);
      await tester.runAsync(() async {
        final switched = await harness.theme.setBrand('defaultBrand');
        expect(switched, isTrue);
      });
      await _boundedPumpAndSettle(tester);

      expect(harness.theme.brand.id, 'defaultBrand');
      expect(find.byType(FloatingActionButton), findsNothing);
    },
  );

  testWidgets(
    'quadrant-scroll: real swipe gesture and scroll notification interaction check',
    (tester) async {
      final harness = await _mountQuadrantScreen(
        tester,
        initialBrand: 'defaultBrand',
        initialLocale: AppLocale.zh,
        physicalSize: const Size(390, 844),
        textScale: 2.0,
        onCreateTodo: (_) {},
        initialTodos: _createSyntheticTodos(15),
      );

      final revisionBefore = harness.todoProvider.revision;
      final initialTodosSnapshot = List<TodoItem>.from(
        harness.todoProvider.todos,
      );

      final swipeTitle = harness.todoProvider.todos.first.title;
      final row = _findTodoTile(swipeTitle);
      await tester.ensureVisible(row);
      await _boundedPumpAndSettle(tester);

      // Open swipe actions horizontally on the first task tile
      await tester.drag(row, const Offset(-130, 0));
      await _boundedPumpAndSettle(tester);

      // Prove delete action is actually visible before vertical drag
      final deleteAction = find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('todo_swipe_delete_button')),
      );
      expect(
        deleteAction,
        findsOneWidget,
        reason: 'Delete swipe action button must be visible when swipe is open',
      );

      final listFinder = find.byType(ListView);
      final scrollableFinder = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      expect(scrollableFinder, findsOneWidget);
      final scrollPosition = tester
          .state<ScrollableState>(scrollableFinder)
          .position;
      expect(scrollPosition.maxScrollExtent, greaterThan(0));
      final offsetBefore = scrollPosition.pixels;

      // Trigger vertical scroll gesture on list
      await tester.drag(listFinder, const Offset(0, -48));
      await _boundedPumpAndSettle(tester);

      // Verify nonempty offset advances while row remains mounted
      expect(
        scrollPosition.pixels,
        greaterThan(offsetBefore),
        reason: 'Vertical scroll offset must advance after drag',
      );
      expect(
        row,
        findsOneWidget,
        reason: 'Task row must remain mounted after scroll',
      );
      expect(
        find.descendant(of: row, matching: find.text(swipeTitle)),
        findsOneWidget,
      );

      // Prove delete action is absent afterwards
      expect(
        deleteAction,
        findsNothing,
        reason: 'Swipe actions must close upon vertical scroll',
      );

      // Verify provider revision, content, and operation counts unchanged
      expect(
        harness.todoProvider.revision,
        revisionBefore,
        reason: 'Provider revision must remain unchanged',
      );
      expect(
        harness.todoProvider.todos.length,
        initialTodosSnapshot.length,
        reason: 'Todo count must remain unchanged',
      );
      expect(
        harness.todoProvider.deleteCalls,
        isEmpty,
        reason: 'No delete operations should be invoked',
      );
      expect(
        harness.todoProvider.completeCalls,
        isEmpty,
        reason: 'No complete operations should be invoked',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
