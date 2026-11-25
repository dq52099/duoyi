// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_detail_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../test_support/recording_reminder_scheduler.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int todoWrites = 0;
  int todoRemoves = 0;
  final List<String> recordedTodoPayloads = [];

  static bool _isTodoKey(String key) =>
      key == 'todos' || key == 'flutter.todos' || key.endsWith('.todos');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isTodoKey(key)) {
      todoWrites++;
      recordedTodoPayloads.add(value.toString());
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isTodoKey(key)) {
      todoRemoves++;
    }
    return super.remove(key);
  }
}

class _TodoDetailBrandScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final String initialBrand;
  final String targetBrand;
  final bool testExplicitSave;

  const _TodoDetailBrandScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.initialBrand,
    required this.targetBrand,
    this.testExplicitSave = false,
  });
}

const _scenarios = <_TodoDetailBrandScenario>[
  _TodoDetailBrandScenario(
    name: 'zh-landscape-scale20-discard',
    locale: AppLocale.zh,
    size: Size(568, 320),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    testExplicitSave: false,
  ),
  _TodoDetailBrandScenario(
    name: 'en-landscape-scale20-save',
    locale: AppLocale.en,
    size: Size(568, 320),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    testExplicitSave: true,
  ),
  _TodoDetailBrandScenario(
    name: 'zh-narrow-scale20-roundtrip',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    testExplicitSave: false,
  ),
  _TodoDetailBrandScenario(
    name: 'en-narrow-scale20-roundtrip',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    testExplicitSave: false,
  ),
];

Future<void> _drainTodoWrites(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(
    () => AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5)),
  );
}

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

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));

  for (final scenario in _scenarios) {
    testWidgets('paired widget Todo detail live brand priority ${scenario.name}', (
      tester,
    ) async {
      final original = TodoItem(
        id: 'todo/live-brand-${scenario.name}',
        title: scenario.locale == AppLocale.zh
            ? '原始待办任务-保全测试'
            : 'Original Task Live Brand Test',
        notes: 'Baseline note content',
        quadrant: EisenhowerQuadrant.urgentImportant,
        tags: const ['brand-live-tag'],
        dueDate: DateTime(2027, 6, 15),
        timeTargetSeconds: 1200,
        subtasks: [Subtask(id: 'subtask-1', title: 'Subtask 1')],
      );

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

      final scheduler = RecordingReminderScheduler();
      final todos = TodoProvider()..scheduler = scheduler;
      final theme = ThemeProvider();
      final boundary = GlobalKey();
      final previousShadows = debugDisableShadows;

      try {
        I18n.setLocale(scenario.locale);
        debugDisableShadows = false;

        // Seed baseline data
        await todos.addTodo(original);
        await theme.loadFromStorage();
        expect(theme.brand.id, scenario.initialBrand);
        expect(theme.isBrandUnlocked(scenario.targetBrand), isTrue);

        // Drain initial seed writes to ensure clean isolation
        await _drainTodoWrites(tester);

        final preferences = await SharedPreferences.getInstance();
        final initialStoredTodos = preferences.getString('todos');
        expect(initialStoredTodos, isNotNull);

        // Take strict baseline snapshot after seed
        final baselineTodoWrites = store.todoWrites;
        final baselineTodoRemoves = store.todoRemoves;
        final baselineSchedulerSyncs = scheduler.todoSyncs.length;
        final baselineRevision = todos.revision;
        final baselineStoredTodos = preferences.getString('todos');

        void assertZeroTodoMutations({required String stage}) {
          expect(
            store.todoWrites,
            baselineTodoWrites,
            reason:
                '$stage: expected zero todo storage writes (actual=${store.todoWrites}, baseline=$baselineTodoWrites)',
          );
          expect(
            store.todoRemoves,
            baselineTodoRemoves,
            reason:
                '$stage: expected zero todo storage removes (actual=${store.todoRemoves}, baseline=$baselineTodoRemoves)',
          );
          expect(
            scheduler.todoSyncs.length,
            baselineSchedulerSyncs,
            reason:
                '$stage: expected zero scheduler syncs (actual=${scheduler.todoSyncs.length}, baseline=$baselineSchedulerSyncs)',
          );
          expect(
            todos.revision,
            baselineRevision,
            reason:
                '$stage: expected unchanged mutation revision (actual=${todos.revision}, baseline=$baselineRevision)',
          );
          expect(
            preferences.getString('todos'),
            baselineStoredTodos,
            reason:
                '$stage: expected SharedPreferences todos payload to remain identical to baseline',
          );
          expect(
            todos.todos.single.title,
            original.title,
            reason:
                '$stage: expected in-memory todo item title to remain original',
          );
        }

        await tester.runAsync(() => loadWeeklyReviewScreenshotFonts());

        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ],
            child: AnimatedBuilder(
              animation: Listenable.merge([theme, I18n.localeListenable]),
              builder: (context, _) => MaterialApp(
                locale: Locale(scenario.locale == AppLocale.en ? 'en' : 'zh'),
                supportedLocales: const [Locale('en'), Locale('zh')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: theme.brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => TodayDetailRouter.open(
                          context,
                          TodaySectionKind.todos,
                          id: original.id,
                        ),
                        child: const Text('Open task'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. Open the existing TodoDetailScreen via production router
        await tester.tap(find.text('Open task'));
        await _boundedPumpAndSettle(tester);

        final routeFinder = find.byType(TodoDetailScreen);
        expect(routeFinder, findsOneWidget);
        expect(find.byType(BrandRouteSurface), findsOneWidget);
        expect(find.byType(BrandBackground), findsOneWidget);
        expect(find.text(TodoDetailUiCopy.screenTitle), findsOneWidget);

        final initialRouteState = tester.state(routeFinder);
        final initialModalRoute = ModalRoute.of(tester.element(routeFinder));

        final titleField = _titleField();
        expect(titleField, findsOneWidget);
        final initialController = tester
            .widget<TextField>(titleField)
            .controller!;
        expect(initialController.text, original.title);

        assertZeroTodoMutations(stage: '1. after route open');
        await _capture(tester, boundary, '${scenario.name}-01-initial');
        if (scenario.size.width == 320) {
          _expectReadableAttachmentHeading(tester);
        }

        // 2. Enter uncommitted draft changes in title
        final draftTitle = scenario.locale == AppLocale.zh
            ? '草稿未保存待办-${scenario.name}'
            : 'Draft Unsaved Task ${scenario.name}';
        await tester.enterText(titleField, draftTitle);
        await _boundedPumpAndSettle(tester);

        expect(initialController.text, draftTitle);
        FocusManager.instance.primaryFocus?.unfocus();

        // Verify zero writes / zero scheduler calls / unchanged revision after draft edits
        assertZeroTodoMutations(stage: '2. after draft edit');
        await _capture(tester, boundary, '${scenario.name}-02-draft');

        // 3. Live brand switch to targetBrand
        await tester.runAsync(() async {
          final switched = await theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
        });
        await _boundedPumpAndSettle(tester);

        expect(theme.brand.id, scenario.targetBrand);
        final detailElementStage1 = tester.element(routeFinder);
        final themeStage1 = Theme.of(detailElementStage1);
        final expectedBrandStage1 = AppBrands.byId(scenario.targetBrand);
        expect(
          themeStage1.colorScheme.primary,
          equals(expectedBrandStage1.theme.colorScheme.primary),
        );
        if (scenario.targetBrand == 'liquidGlass') {
          expect(
            appSurfaceStyleOf(detailElementStage1),
            equals(AppSurfaceStyle.liquidGlass),
          );
        } else {
          expect(
            appSurfaceStyleOf(detailElementStage1),
            isNot(equals(AppSurfaceStyle.liquidGlass)),
          );
        }

        // Verify route/page state and controller draft retention
        expect(tester.state(routeFinder), same(initialRouteState));
        expect(
          ModalRoute.of(tester.element(routeFinder)),
          same(initialModalRoute),
        );
        expect(
          tester.widget<TextField>(titleField).controller,
          same(initialController),
        );
        expect(initialController.text, draftTitle);

        // Assert zero todo storage writes / removes / revision change across first brand switch
        assertZeroTodoMutations(
          stage: '3. after brand switch to ${scenario.targetBrand}',
        );
        await _capture(tester, boundary, '${scenario.name}-03-switched');
        if (scenario.size.width == 320) {
          _expectReadableAttachmentHeading(tester);
        }

        // 4. Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
        });
        await _boundedPumpAndSettle(tester);

        expect(theme.brand.id, scenario.initialBrand);
        final detailElementStage2 = tester.element(routeFinder);
        final themeStage2 = Theme.of(detailElementStage2);
        final expectedBrandStage2 = AppBrands.byId(scenario.initialBrand);
        expect(
          themeStage2.colorScheme.primary,
          equals(expectedBrandStage2.theme.colorScheme.primary),
        );
        if (scenario.initialBrand == 'liquidGlass') {
          expect(
            appSurfaceStyleOf(detailElementStage2),
            equals(AppSurfaceStyle.liquidGlass),
          );
        } else {
          expect(
            appSurfaceStyleOf(detailElementStage2),
            isNot(equals(AppSurfaceStyle.liquidGlass)),
          );
        }

        // Verify state, route and draft controller remain stable
        expect(tester.state(routeFinder), same(initialRouteState));
        expect(
          ModalRoute.of(tester.element(routeFinder)),
          same(initialModalRoute),
        );
        expect(
          tester.widget<TextField>(titleField).controller,
          same(initialController),
        );
        expect(initialController.text, draftTitle);

        // Assert zero todo storage writes / removes / revision change across brand roundtrip
        assertZeroTodoMutations(
          stage: '4. after brand roundtrip back to ${scenario.initialBrand}',
        );
        await _capture(tester, boundary, '${scenario.name}-04-reverted');
        if (scenario.size.width == 320) {
          _expectReadableAttachmentHeading(tester);
        }

        // 5. Verify explicit save vs Back/discard semantics
        if (scenario.testExplicitSave) {
          // Pre-save sanity: verify zero storage writes until explicit save
          assertZeroTodoMutations(stage: '5. pre-save check');

          final saveButton = find.widgetWithIcon(IconButton, Icons.check);
          expect(saveButton, findsOneWidget);
          await tester.tap(saveButton);
          await _drainTodoWrites(tester);
          await _boundedPumpAndSettle(tester);

          // Detail screen popped upon successful save
          expect(find.byType(TodoDetailScreen), findsNothing);
          expect(find.text('Open task'), findsOneWidget);

          // Verified: storage writes, scheduler sync, and mutation revision increment occur ONLY on explicit save!
          expect(
            store.todoWrites,
            greaterThan(baselineTodoWrites),
            reason: 'Explicit save must issue a storage write to todos',
          );
          expect(
            scheduler.todoSyncs.length,
            greaterThan(baselineSchedulerSyncs),
            reason:
                'Explicit save must invoke reminder scheduler sync for todos',
          );
          expect(
            todos.revision,
            greaterThan(baselineRevision),
            reason: 'Explicit save must advance TodoProvider mutation revision',
          );
          expect(
            preferences.getString('todos'),
            isNot(equals(baselineStoredTodos)),
            reason: 'Explicit save must update stored todos JSON payload',
          );
          final savedList =
              jsonDecode(preferences.getString('todos')!) as List<dynamic>;
          expect(savedList.single['title'], draftTitle);
          expect(todos.todos.single.title, draftTitle);

          await _capture(tester, boundary, '${scenario.name}-05-saved');
        } else {
          final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
          expect(backButton, findsOneWidget);

          // First tap Back -> discard confirmation dialog appears
          await tester.tap(backButton);
          await _boundedPumpAndSettle(tester);

          expect(find.byType(AppDialog), findsOneWidget);
          expect(
            find.text(TodoDetailUiCopy.discardDialogTitle),
            findsOneWidget,
          );
          assertZeroTodoMutations(stage: '5. discard dialog open');
          await _capture(
            tester,
            boundary,
            '${scenario.name}-05-discard-dialog',
          );

          // Tap Cancel -> dialog dismissed, draft and page state remain
          final cancelButton = find.widgetWithText(
            TextButton,
            TodoDetailUiCopy.cancel,
          );
          expect(cancelButton, findsOneWidget);
          await tester.tap(cancelButton);
          await _boundedPumpAndSettle(tester);

          expect(find.byType(AppDialog), findsNothing);
          expect(find.byType(TodoDetailScreen), findsOneWidget);
          expect(tester.state(routeFinder), same(initialRouteState));
          expect(initialController.text, draftTitle);

          // Verify zero storage writes after cancel
          assertZeroTodoMutations(stage: '6. after cancel discard');

          // Tap Back again -> Tap Discard -> route dismissed without saving
          await tester.tap(backButton);
          await _boundedPumpAndSettle(tester);
          expect(find.byType(AppDialog), findsOneWidget);

          final discardButton = find.widgetWithText(
            TextButton,
            TodoDetailUiCopy.discardAction,
          );
          expect(discardButton, findsOneWidget);
          await tester.tap(discardButton);
          await _boundedPumpAndSettle(tester);

          expect(find.byType(TodoDetailScreen), findsNothing);
          expect(find.text('Open task'), findsOneWidget);

          // Final check: storage, revision, and scheduler remain in pristine baseline state
          assertZeroTodoMutations(stage: '7. after confirming discard');

          await _capture(tester, boundary, '${scenario.name}-06-discarded');
        }

        expect(tester.takeException(), isNull);
      } finally {
        try {
          await _drainTodoWrites(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
        } finally {
          SharedPreferences.resetStatic();
          SharedPreferencesStorePlatform.instance = previousStore;
          todos.dispose();
          theme.dispose();
          tester.view.reset();
          debugDisableShadows = previousShadows;
          I18n.setLocale(originalLocale);
        }
      }
    });
  }
}

void _expectReadableAttachmentHeading(WidgetTester tester) {
  final heading = find.text(TodoDetailUiCopy.attachmentsSection);
  expect(heading, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: heading, matching: find.byType(RichText)),
  );
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    maxLines: paragraph.maxLines,
  )..layout(maxWidth: paragraph.size.width);
  try {
    expect(
      painter.computeLineMetrics(),
      hasLength(1),
      reason: 'The attachment heading must fit without splitting its word.',
    );
    expect(painter.didExceedMaxLines, isFalse);
  } finally {
    painter.dispose();
  }
  for (final tooltip in [
    TodoDetailUiCopy.pickFileTooltip,
    TodoDetailUiCopy.addLinkTooltip,
  ]) {
    final action = find.byTooltip(tooltip);
    expect(action.hitTestable(), findsOneWidget);
    final size = tester.getSize(action);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  }
}

Finder _titleField() => find.descendant(
  of: find.byType(TodoDetailScreen),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == TodoDetailUiCopy.taskTitleLabel,
  ),
);

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  final enabled =
      explicitDir != null ||
      Platform.environment['DUOYI_CAPTURE_TODO_DETAIL_BRAND'] == '1' ||
      Platform.environment['DUOYI_LIVE_SCREENSHOTS'] == '1';
  if (!enabled) return;
  await tester.pump();
  await tester.runAsync(() async {
    final context = key.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final targetDir =
          explicitDir ??
          'evidence/screenshots/widget-live-parallel-20261023/todo-detail-brand';
      final file = File('$targetDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
