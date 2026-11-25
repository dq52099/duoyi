import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ai_schedule_ui_copy.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:duoyi/widgets/surface_components.dart' show appSurfaceStyleOf;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _syntheticOrigin = AuthState(
  userId: 'ai-schedule-synthetic-user',
  username: 'synthetic-schedule-account',
  token: 'synthetic-schedule-token',
);

const _testTitle = 'Team design sync / 团队设计同步';
const _testNotes = 'Weekly architecture review / 周架构评审';
const _testInput = '明天上午十点团队会议 / Team meeting tomorrow 10am';

class _PendingAiService extends AiService {
  final AiScheduleDraft draft;
  Completer<AiScheduleDraft>? completer;
  int recognitions = 0;

  _PendingAiService(this.draft);

  @override
  bool get enabled => true;

  @override
  Future<AiScheduleDraft> createScheduleDraft(String input, {DateTime? now}) {
    recognitions++;
    completer = Completer<AiScheduleDraft>();
    return completer!.future;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadWeeklyReviewScreenshotFonts();
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
  });

  final cases = [
    (
      fromBrand: 'defaultBrand',
      toBrand: 'liquidGlass',
      fromLocale: AppLocale.zh,
      toLocale: AppLocale.en,
      size: const Size(320, 844),
    ),
    (
      fromBrand: 'defaultBrand',
      toBrand: 'liquidGlass',
      fromLocale: AppLocale.zh,
      toLocale: AppLocale.en,
      size: const Size(568, 320),
    ),
    (
      fromBrand: 'defaultBrand',
      toBrand: 'liquidGlass',
      fromLocale: AppLocale.en,
      toLocale: AppLocale.zh,
      size: const Size(320, 844),
    ),
    (
      fromBrand: 'defaultBrand',
      toBrand: 'liquidGlass',
      fromLocale: AppLocale.en,
      toLocale: AppLocale.zh,
      size: const Size(568, 320),
    ),
    (
      fromBrand: 'liquidGlass',
      toBrand: 'defaultBrand',
      fromLocale: AppLocale.zh,
      toLocale: AppLocale.en,
      size: const Size(320, 844),
    ),
    (
      fromBrand: 'liquidGlass',
      toBrand: 'defaultBrand',
      fromLocale: AppLocale.zh,
      toLocale: AppLocale.en,
      size: const Size(568, 320),
    ),
    (
      fromBrand: 'liquidGlass',
      toBrand: 'defaultBrand',
      fromLocale: AppLocale.en,
      toLocale: AppLocale.zh,
      size: const Size(320, 844),
    ),
    (
      fromBrand: 'liquidGlass',
      toBrand: 'defaultBrand',
      fromLocale: AppLocale.en,
      toLocale: AppLocale.zh,
      size: const Size(568, 320),
    ),
  ];

  for (final c in cases) {
    testWidgets(
      'live loading brand ${c.fromBrand}->${c.toBrand} locale ${c.fromLocale.name}->${c.toLocale.name} ${c.size.width.toInt()}x${c.size.height.toInt()} 200% font',
      (tester) async {
        final initialBrand = c.fromBrand;
        final targetBrand = c.toBrand;
        final initialLocale = c.fromLocale;
        final targetLocale = c.toLocale;
        final size = c.size;

        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        AuthProvider? auth;
        _PendingAiService? ai;
        CalendarProvider? events;
        TodoProvider? todos;
        NotificationService? notifications;
        ThemeProvider? theme;

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await AccountPreferenceWrites.drain();
          auth?.dispose();
          ai?.dispose();
          events?.dispose();
          todos?.dispose();
          notifications?.dispose();
          theme?.dispose();
        });

        SharedPreferences.setMockInitialValues({
          'auth_state': jsonEncode(_syntheticOrigin.toJson()),
          AccountLocalDataCleaner.accountDataOwnerKey:
              'id:${_syntheticOrigin.userId}',
          'active_brand': initialBrand,
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        });
        I18n.setLocale(initialLocale);

        final prefs = await SharedPreferences.getInstance();
        auth = AuthProvider(
          initialState: _syntheticOrigin,
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            token: _syntheticOrigin.token,
            httpClient: MockClient((_) async => http.Response('{}', 200)),
          ),
        );
        ai = _PendingAiService(
          AiScheduleDraft(
            type: AiScheduleType.calendar,
            title: _testTitle,
            notes: _testNotes,
            startAt: DateTime(2100, 10, 13, 15),
            endAt: DateTime(2100, 10, 13, 16),
            reminderEnabled: false,
          ),
        );
        events = CalendarProvider();
        todos = TodoProvider();
        notifications = NotificationService();
        theme = ThemeProvider();

        var themeLoaded = false;
        final loadFuture = theme.loadFromStorage().whenComplete(
          () => themeLoaded = true,
        );
        for (var i = 0; i < 50 && !themeLoaded; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await loadFuture;

        final navKey = GlobalKey<NavigatorState>();
        final repaintBoundaryKey = GlobalKey();

        Widget buildApp() => RepaintBoundary(
          key: repaintBoundaryKey,
          child: MaterialApp(
            navigatorKey: navKey,
            theme: theme!.brand.theme,
            locale: I18n.current.flutterLocale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const BrandRouteSurface(child: AiScheduleScreen()),
                    ),
                  ),
                  child: const Text('Open AI'),
                ),
              ),
            ),
          ),
        );

        Future<void> captureState(String stateTag) async {
          final captureDir = Platform.environment['DUOYI_RETAINED_CAPTURE'];
          if (captureDir == null || captureDir.trim().isEmpty) return;
          final dir = Directory(captureDir.trim());
          final boundary =
              repaintBoundaryKey.currentContext?.findRenderObject()
                  as RenderRepaintBoundary?;
          if (boundary == null) return;
          final fileName =
              'ai_schedule_loading_${c.fromBrand}_to_${c.toBrand}_${c.fromLocale.name}_to_${c.toLocale.name}_${c.size.width.toInt()}x${c.size.height.toInt()}_$stateTag.png';

          await tester.runAsync(() async {
            ui.Image? image;
            try {
              image = await boundary.toImage(pixelRatio: 1.0);
              final byteData = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (byteData == null) return;
              final pngBytes = byteData.buffer.asUint8List();
              if (!dir.existsSync()) {
                dir.createSync(recursive: true);
              }
              final file = File('${dir.path}/$fileName');
              await file.writeAsBytes(pngBytes);
            } finally {
              image?.dispose();
            }
          });
        }

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<AiService>.value(value: ai),
              ChangeNotifierProvider<CalendarProvider>.value(value: events),
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
              ChangeNotifierProvider<NotificationService>.value(
                value: notifications,
              ),
            ],
            child: AnimatedBuilder(
              animation: Listenable.merge([theme, I18n.localeListenable]),
              builder: (context, child) => buildApp(),
            ),
          ),
        );

        // Open AI schedule screen with bounded pump for route transition (~350ms)
        await tester.pump();
        await tester.tap(find.text('Open AI'));
        await tester.pump();
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byType(AiScheduleScreen), findsOneWidget);
        final screenStateBefore = tester.state(find.byType(AiScheduleScreen));
        final screenElementBefore = tester.element(
          find.byType(AiScheduleScreen),
        );
        final routeBefore = ModalRoute.of(screenElementBefore)!;
        expect(routeBefore.isCurrent, isTrue);
        expect(theme.brand.id, initialBrand);
        expect(
          appSurfaceStyleOf(screenElementBefore),
          theme.brand.theme.extension<AppSurfaceStyle>(),
        );

        // Input text and explicit selection
        final inputFinder = find.byType(TextField).first;
        await tester.enterText(inputFinder, _testInput);
        await tester.pump(const Duration(milliseconds: 50));

        final textFieldBefore = tester.widget<TextField>(inputFinder);
        final controller = textFieldBefore.controller!;
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 8,
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.text, _testInput);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );

        // Trigger recognition
        FocusManager.instance.primaryFocus?.unfocus();
        final recognizeFinder = find.widgetWithText(
          FilledButton,
          AiScheduleUiCopy.recognize,
        );
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            recognizeFinder,
            100,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(recognizeFinder);
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(recognizeFinder.hitTestable(), findsOneWidget);
        await tester.tap(recognizeFinder);

        // Bounded pump for pending async call (do NOT pumpAndSettle)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Assert single call and pending Future
        expect(ai.recognitions, 1);
        expect(ai.completer, isNotNull);
        expect(ai.completer!.isCompleted, isFalse);

        // Assert recognize button disabled while loading with recognizing text
        final loadingButtonFinder = find.widgetWithText(
          FilledButton,
          AiScheduleUiCopy.recognizing,
        );
        expect(loadingButtonFinder, findsOneWidget);
        final buttonWhileLoading = tester.widget<FilledButton>(
          loadingButtonFinder,
        );
        expect(buttonWhileLoading.enabled, isFalse);
        expect(buttonWhileLoading.onPressed, isNull);

        // Assert spinner visible
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Reveal and capture loading state
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            loadingButtonFinder,
            50,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(loadingButtonFinder);
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await captureState('loading');

        // Extra tap on disabled button does not trigger additional calls
        await tester.tap(loadingButtonFinder, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 50));
        expect(ai.recognitions, 1);

        // Hot switch theme
        var brandSwitched = false;
        final brandFuture = theme
            .setBrand(targetBrand)
            .whenComplete(() => brandSwitched = true);
        for (var i = 0; i < 50 && !brandSwitched; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(await brandFuture, isTrue);

        // Bounded pump past kThemeAnimationDuration (200ms) to finish color interpolation
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 20)); // 300ms total
        }
        expect(theme.brand.id, targetBrand);

        // Hot switch locale
        I18n.setLocale(targetLocale);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(I18n.current, targetLocale);

        // Assert Screen State, route, controller, text and selection preserved
        final currentScreenState = tester.state(find.byType(AiScheduleScreen));
        expect(identical(currentScreenState, screenStateBefore), isTrue);

        final currentTextField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(identical(currentTextField.controller, controller), isTrue);
        expect(controller.text, _testInput);
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );

        final currentElement = tester.element(find.byType(AiScheduleScreen));
        final currentRoute = ModalRoute.of(currentElement)!;
        expect(identical(currentRoute, routeBefore), isTrue);
        expect(currentRoute.isCurrent, isTrue);

        // Assert no extra AI calls and no storage writes
        expect(ai.recognitions, 1);
        expect(events.localEvents, isEmpty);
        expect(todos.todos, isEmpty);
        expect(
          prefs.getStringList('duoyi_local_calendar_events_v1') ?? [],
          isEmpty,
        );
        expect(prefs.getString('todos') ?? '[]', '[]');

        // Button copy reflects new locale recognizing text, disabled, spinner visible
        final loadingButtonAfterSwitchFinder = find.widgetWithText(
          FilledButton,
          AiScheduleUiCopy.recognizing,
        );
        expect(loadingButtonAfterSwitchFinder, findsOneWidget);
        final buttonAfterSwitch = tester.widget<FilledButton>(
          loadingButtonAfterSwitchFinder,
        );
        expect(buttonAfterSwitch.enabled, isFalse);
        expect(buttonAfterSwitch.onPressed, isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Actual surface and theme followed
        final screenTheme = Theme.of(currentElement);
        expect(
          screenTheme.colorScheme.primary,
          theme.brand.theme.colorScheme.primary,
        );
        expect(screenTheme.brightness, theme.brand.theme.brightness);
        expect(
          appSurfaceStyleOf(currentElement),
          theme.brand.theme.extension<AppSurfaceStyle>(),
        );

        // Reveal and capture switched loading state
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            loadingButtonAfterSwitchFinder,
            50,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(loadingButtonAfterSwitchFinder);
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await captureState('loading_switched');

        // Complete controlled draft and verify restoration
        ai.completer!.complete(ai.draft);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        // Clear spinner
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // Single draft generated and displayed: scroll until title is visible in ListView
        expect(ai.recognitions, 1);
        final titleFinder = find.text(_testTitle);
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            titleFinder,
            100,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(titleFinder);
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(titleFinder, findsOneWidget);

        // Independently scroll until create button is visible and assert enabled
        final createButtonFinder = find.widgetWithText(
          FilledButton,
          AiScheduleUiCopy.create,
        );
        if (find.byType(Scrollable).evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            createButtonFinder,
            100,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(createButtonFinder);
        for (var i = 0; i < 7; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(createButtonFinder.hitTestable(), findsOneWidget);
        final createBtn = tester.widget<FilledButton>(createButtonFinder);
        expect(createBtn.enabled, isTrue);
        expect(createBtn.onPressed, isNotNull);

        // Storage writes remain empty (creation not tapped)
        expect(events.localEvents, isEmpty);
        expect(todos.todos, isEmpty);
        expect(
          prefs.getStringList('duoyi_local_calendar_events_v1') ?? [],
          isEmpty,
        );
        expect(prefs.getString('todos') ?? '[]', '[]');

        // Capture completed state
        await captureState('completed');

        // No uncaught exceptions
        expect(tester.takeException(), isNull);
      },
    );
  }
}
