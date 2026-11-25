// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
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
}

enum _ReportMode { empty, positive, negative, flat }

class _TodayProductivityScenario {
  final String name;
  final Size size;
  final double scale;
  final AppLocale initialLocale;
  final AppLocale targetLocale;
  final String initialBrand;
  final String targetBrand;
  final _ReportMode reportMode;

  const _TodayProductivityScenario({
    required this.name,
    required this.size,
    required this.scale,
    required this.initialLocale,
    required this.targetLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.reportMode,
  });
}

const _scenarios = <_TodayProductivityScenario>[
  // English at 320 scale 2 for both brands
  _TodayProductivityScenario(
    name: 'portrait-320x844-scale2-en-defaultBrand-positive',
    size: Size(320, 844),
    scale: 2.0,
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    reportMode: _ReportMode.positive,
  ),
  _TodayProductivityScenario(
    name: 'portrait-320x844-scale2-en-liquidGlass-negative',
    size: Size(320, 844),
    scale: 2.0,
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    reportMode: _ReportMode.negative,
  ),
  // Chinese at 320 scale 2 for both brands
  _TodayProductivityScenario(
    name: 'portrait-320x844-scale2-zh-defaultBrand-flat',
    size: Size(320, 844),
    scale: 2.0,
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    reportMode: _ReportMode.flat,
  ),
  _TodayProductivityScenario(
    name: 'portrait-320x844-scale2-zh-liquidGlass-positive',
    size: Size(320, 844),
    scale: 2.0,
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    reportMode: _ReportMode.positive,
  ),
  // Preservation checks: normal 390 scale 1 and wide 1024 scale 1
  _TodayProductivityScenario(
    name: 'normal-390x844-scale1-en-defaultBrand-positive',
    size: Size(390, 844),
    scale: 1.0,
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    reportMode: _ReportMode.positive,
  ),
  _TodayProductivityScenario(
    name: 'wide-1024x720-scale1-en-liquidGlass-empty',
    size: Size(1024, 720),
    scale: 1.0,
    initialLocale: AppLocale.en,
    targetLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    reportMode: _ReportMode.empty,
  ),
  _TodayProductivityScenario(
    name: 'landscape-844x390-scale1-zh-defaultBrand-flat',
    size: Size(844, 390),
    scale: 1.0,
    initialLocale: AppLocale.zh,
    targetLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    reportMode: _ReportMode.flat,
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
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'] ??
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
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
      final file = File('$explicitDir/today-productivity-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

int _matchLineCount(RenderParagraph paragraph, int start, int end) {
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
  );
  if (boxes.isEmpty) {
    fail(
      'No layout boxes found for selection [$start, $end] in text: "${paragraph.text.toPlainText()}"',
    );
  }
  final lineTops = <double>[];
  for (final box in boxes) {
    if (lineTops.every((top) => (top - box.top).abs() > 0.5)) {
      lineTops.add(box.top);
    }
  }
  return lineTops.length;
}

void _assertCompleteLatinWords(WidgetTester tester, Finder parentFinder) {
  final richTexts = find.descendant(
    of: parentFinder,
    matching: find.byType(RichText),
  );
  expect(richTexts, findsWidgets);
  final latinWordRegex = RegExp(r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*");
  for (final richText in richTexts.evaluate()) {
    final paragraph = richText.renderObject as RenderParagraph;
    final text = paragraph.text.toPlainText();
    for (final match in latinWordRegex.allMatches(text)) {
      final word = match.group(0)!;
      final lines = _matchLineCount(paragraph, match.start, match.end);
      expect(
        lines,
        equals(1),
        reason:
            'Word "$word" at [${match.start}, ${match.end}] split across $lines lines in paragraph "$text"',
      );
    }
  }
}

Future<void> _assertCardParagraphsInsideViewport(
  WidgetTester tester,
  Finder parentFinder,
  Finder scrollableFinder,
) async {
  final richTexts = find.descendant(
    of: parentFinder,
    matching: find.byType(RichText),
  );
  expect(richTexts, findsWidgets);

  for (final richText in richTexts.evaluate()) {
    final paragraph = richText.renderObject as RenderParagraph;
    final fullText = paragraph.text.toPlainText();
    if (fullText.trim().isEmpty) continue;

    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'Paragraph "$fullText" exceeded maxLines',
    );

    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: fullText.length),
    );
    expect(
      boxes,
      isNotEmpty,
      reason: 'Boxes must not be empty for "$fullText"',
    );

    final scroll = Scrollable.maybeOf(richText);
    final viewport = tester.getRect(scrollableFinder);

    for (final box in boxes) {
      if (scroll != null) {
        final global = Rect.fromPoints(
          paragraph.localToGlobal(Offset(box.left, box.top)),
          paragraph.localToGlobal(Offset(box.right, box.bottom)),
        );
        final delta = global.center.dy - viewport.center.dy;
        final position = scroll.position;
        position.jumpTo(
          (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }

      final actual = Rect.fromPoints(
        paragraph.localToGlobal(Offset(box.left, box.top)),
        paragraph.localToGlobal(Offset(box.right, box.bottom)),
      );

      expect(
        actual.left,
        greaterThanOrEqualTo(viewport.left - 0.5),
        reason:
            'Glyph box for "$fullText" (${actual.left}) clips viewport left (${viewport.left})',
      );
      expect(
        actual.right,
        lessThanOrEqualTo(viewport.right + 0.5),
        reason:
            'Glyph box for "$fullText" (${actual.right}) clips viewport right (${viewport.right})',
      );
      expect(
        actual.top,
        greaterThanOrEqualTo(viewport.top - 0.5),
        reason:
            'Glyph box for "$fullText" (${actual.top}) clips viewport top (${viewport.top})',
      );
      expect(
        actual.bottom,
        lessThanOrEqualTo(viewport.bottom + 0.5),
        reason:
            'Glyph box for "$fullText" (${actual.bottom}) clips viewport bottom (${viewport.bottom})',
      );
    }
  }
}

class _TodayFixture {
  late final SharedPreferences prefs;
  late final ThemeProvider theme;
  late final PreferencesProvider preferences;
  late final TodoProvider todoProvider;
  late final HabitProvider habitProvider;
  late final PomodoroProvider pomodoroProvider;
  late final TimeAuditProvider timeAuditProvider;
  late final DiaryProvider diaryProvider;
  late final AnniversaryProvider anniversaryProvider;
  late final CourseProvider courseProvider;
  late final GoalProvider goalProvider;
  late final UserProvider userProvider;
  late final AuthProvider authProvider;
  late final AppLockProvider lockProvider;
  late final CloudSyncProvider cloudSyncProvider;
  late final CalendarProvider calendarProvider;
  late final CountdownProvider countdownProvider;
  late final NoteProvider noteProvider;
  late final AchievementProvider achievementProvider;
  late final ShareProvider shareProvider;
  late final NotificationService notificationService;
  late final AiService aiService;
  late final LocaleProvider localeProvider;
  late final LocationReminderProvider locationReminderProvider;
  late final CalendarSyncProvider calendarSyncProvider;
  late final AppUpdateService updateService;

  final navigatorKey = GlobalKey<NavigatorState>();
  final boundaryKey = GlobalKey();
  bool _installed = false;
  bool _disposed = false;

  Future<void> mount(
    WidgetTester tester, {
    required Size size,
    required double scale,
    required _ReportMode reportMode,
  }) async {
    if (!_installed) {
      _installed = true;
      await tester.runAsync(() async {
        prefs = await SharedPreferences.getInstance();
        theme = ThemeProvider();
        preferences = PreferencesProvider();
        todoProvider = TodoProvider();
        habitProvider = HabitProvider();
        pomodoroProvider = PomodoroProvider();
        timeAuditProvider = TimeAuditProvider();
        diaryProvider = DiaryProvider();
        anniversaryProvider = AnniversaryProvider();
        courseProvider = CourseProvider();
        goalProvider = GoalProvider();
        userProvider = UserProvider();
        authProvider = AuthProvider();
        lockProvider = AppLockProvider();
        cloudSyncProvider = CloudSyncProvider();
        calendarProvider = CalendarProvider();
        countdownProvider = CountdownProvider();
        noteProvider = NoteProvider();
        achievementProvider = AchievementProvider();
        shareProvider = ShareProvider();
        notificationService = NotificationService();
        aiService = AiService();
        localeProvider = LocaleProvider();
        locationReminderProvider = LocationReminderProvider();
        calendarSyncProvider = CalendarSyncProvider();
        updateService = AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: '1.0.0',
        );

        await theme.loadFromStorage().timeout(const Duration(seconds: 5));
        await preferences.loadFromStorage().timeout(const Duration(seconds: 5));
        if (File('assets/fonts/DroidSansFallbackFull.ttf').existsSync() &&
            File('assets/fonts/DejaVuSans.ttf').existsSync()) {
          await loadWeeklyReviewScreenshotFonts().timeout(
            const Duration(seconds: 5),
          );
        }
      });
      await _drainAccountWrites(tester);
    }

    _populateReport(reportMode);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
          ChangeNotifierProvider<PomodoroProvider>.value(
            value: pomodoroProvider,
          ),
          ChangeNotifierProvider<TimeAuditProvider>.value(
            value: timeAuditProvider,
          ),
          ChangeNotifierProvider<DiaryProvider>.value(value: diaryProvider),
          ChangeNotifierProvider<AnniversaryProvider>.value(
            value: anniversaryProvider,
          ),
          ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AppLockProvider>.value(value: lockProvider),
          ChangeNotifierProvider<CloudSyncProvider>.value(
            value: cloudSyncProvider,
          ),
          ChangeNotifierProvider<CalendarProvider>.value(
            value: calendarProvider,
          ),
          ChangeNotifierProvider<CountdownProvider>.value(
            value: countdownProvider,
          ),
          ChangeNotifierProvider<NoteProvider>.value(value: noteProvider),
          ChangeNotifierProvider<AchievementProvider>.value(
            value: achievementProvider,
          ),
          ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
          ChangeNotifierProvider<NotificationService>.value(
            value: notificationService,
          ),
          ChangeNotifierProvider<AiService>.value(value: aiService),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LocationReminderProvider>.value(
            value: locationReminderProvider,
          ),
          ChangeNotifierProvider<CalendarSyncProvider>.value(
            value: calendarSyncProvider,
          ),
          ChangeNotifierProvider<AppUpdateService>.value(value: updateService),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, currentTheme, _) =>
              ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) => MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: currentTheme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Stack(
                    children: [
                      const BrandBackground(
                        child: TodayScreen(key: ValueKey('today-screen-root')),
                      ),
                      for (final b in [
                        AppBrands.defaultBrand,
                        AppBrands.liquidGlass,
                      ])
                        Offstage(
                          offstage: true,
                          child: Theme(
                            data: b.theme,
                            child: Builder(
                              key: ValueKey('ref_theme_${b.id}'),
                              builder: (refContext) => const SizedBox.shrink(),
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
  }

  void _populateReport(_ReportMode mode) {
    todoProvider.todos.clear();
    pomodoroProvider.sessions.clear();
    habitProvider.habits.clear();

    final now = DateTime.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final weekStart = todayKey.subtract(Duration(days: todayKey.weekday - 1));
    final prevWeekStart = weekStart.subtract(const Duration(days: 7));

    switch (mode) {
      case _ReportMode.empty:
        break;
      case _ReportMode.positive:
        todoProvider.todos.addAll([
          TodoItem(
            id: 'todo-current-1',
            title: 'Report Task 1',
            date: todayKey,
            createdAt: weekStart,
            completedAt: now,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-current-2',
            title: 'Report Task 2',
            date: todayKey,
            createdAt: weekStart,
            completedAt: now,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-current-3',
            title: 'Report Task 3',
            date: todayKey,
            createdAt: weekStart,
            completedAt: now,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-current-4',
            title: 'Report Task 4',
            date: todayKey,
            createdAt: weekStart,
            completedAt: now,
            isCompleted: true,
          ),
        ]);
        pomodoroProvider.sessions.addAll([
          PomodoroSession(
            id: 'pomo-current-1',
            type: PomodoroType.focus,
            startTime: now.subtract(const Duration(minutes: 50)),
            endTime: now,
            durationSeconds: 3000,
          ),
          PomodoroSession(
            id: 'pomo-current-2',
            type: PomodoroType.focus,
            startTime: now.subtract(const Duration(minutes: 25)),
            endTime: now,
            durationSeconds: 1500,
          ),
        ]);
        habitProvider.habits.add(
          Habit(
            id: 'habit-current-1',
            name: 'Habit 1',
            startDate: prevWeekStart,
            currentStreak: 3,
            weeklyTarget: 7,
            completions: {
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}':
                  2,
            },
          ),
        );
        break;
      case _ReportMode.negative:
        todoProvider.todos.addAll([
          TodoItem(
            id: 'todo-prev-1',
            title: 'Prev Task 1',
            date: prevWeekStart,
            createdAt: prevWeekStart,
            completedAt: prevWeekStart,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-prev-2',
            title: 'Prev Task 2',
            date: prevWeekStart,
            createdAt: prevWeekStart,
            completedAt: prevWeekStart,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-prev-3',
            title: 'Prev Task 3',
            date: prevWeekStart,
            createdAt: prevWeekStart,
            completedAt: prevWeekStart,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-prev-4',
            title: 'Prev Task 4',
            date: prevWeekStart,
            createdAt: prevWeekStart,
            completedAt: prevWeekStart,
            isCompleted: true,
          ),
        ]);
        pomodoroProvider.sessions.addAll([
          PomodoroSession(
            id: 'pomo-prev-1',
            type: PomodoroType.focus,
            startTime: prevWeekStart,
            endTime: prevWeekStart.add(const Duration(minutes: 50)),
            durationSeconds: 3000,
          ),
          PomodoroSession(
            id: 'pomo-prev-2',
            type: PomodoroType.focus,
            startTime: prevWeekStart.add(const Duration(minutes: 55)),
            endTime: prevWeekStart.add(const Duration(minutes: 80)),
            durationSeconds: 1500,
          ),
        ]);
        break;
      case _ReportMode.flat:
        todoProvider.todos.addAll([
          TodoItem(
            id: 'todo-flat-current',
            title: 'Flat Task',
            date: todayKey,
            createdAt: weekStart,
            completedAt: now,
            isCompleted: true,
          ),
          TodoItem(
            id: 'todo-flat-prev',
            title: 'Flat Prev Task',
            date: prevWeekStart,
            createdAt: prevWeekStart,
            completedAt: prevWeekStart,
            isCompleted: true,
          ),
        ]);
        pomodoroProvider.sessions.addAll([
          PomodoroSession(
            id: 'pomo-flat-current',
            type: PomodoroType.focus,
            startTime: now.subtract(const Duration(minutes: 25)),
            endTime: now,
            durationSeconds: 1500,
          ),
          PomodoroSession(
            id: 'pomo-flat-prev',
            type: PomodoroType.focus,
            startTime: prevWeekStart,
            endTime: prevWeekStart.add(const Duration(minutes: 25)),
            durationSeconds: 1500,
          ),
        ]);
        break;
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _drainAccountWrites(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _boundedPumpAndSettle(tester);
    } finally {
      tester.view.reset();
      if (_installed) {
        theme.dispose();
        preferences.dispose();
        todoProvider.dispose();
        habitProvider.dispose();
        pomodoroProvider.dispose();
        timeAuditProvider.dispose();
        diaryProvider.dispose();
        anniversaryProvider.dispose();
        courseProvider.dispose();
        goalProvider.dispose();
        userProvider.dispose();
        authProvider.dispose();
        lockProvider.dispose();
        cloudSyncProvider.dispose();
        calendarProvider.dispose();
        countdownProvider.dispose();
        noteProvider.dispose();
        achievementProvider.dispose();
        shareProvider.dispose();
        notificationService.dispose();
        aiService.dispose();
        localeProvider.dispose();
        locationReminderProvider.dispose();
        calendarSyncProvider.dispose();
        updateService.dispose();
      }
    }
  }
}

void main() {
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('today productivity reflow priority layout ${scenario.name}', (
      tester,
    ) async {
      I18n.setLocale(scenario.initialLocale);

      final initialPrefs = <String, Object>{
        'pref_app_timezone_mode': 'fixed',
        'pref_app_timezone_iana': 'Asia/Shanghai',
        'active_brand': scenario.initialBrand,
        'theme_shop_state': jsonEncode({
          'activeBrand': scenario.initialBrand,
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.pref_app_timezone_mode': 'fixed',
        'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
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
      SharedPreferencesStorePlatform.instance = store;

      final fixture = _TodayFixture();

      try {
        await fixture.mount(
          tester,
          size: scenario.size,
          scale: scenario.scale,
          reportMode: scenario.reportMode,
        );

        expect(fixture.theme.brand.id, scenario.initialBrand);

        final screenFinder = find.byKey(const ValueKey('today-screen-root'));
        expect(screenFinder, findsOneWidget);
        final initialScreenElement = tester.element(screenFinder);
        final initialRoute = ModalRoute.of(initialScreenElement);
        expect(initialRoute, isNotNull);

        final scrollableFinder = find
            .descendant(of: screenFinder, matching: find.byType(Scrollable))
            .first;
        expect(scrollableFinder, findsOneWidget);
        final initialScrollableState = tester.state<ScrollableState>(
          scrollableFinder,
        );

        final productivityCardFinder = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_TodayProductivityCard',
        );
        expect(productivityCardFinder, findsOneWidget);

        // Scroll card into initial viewport
        await tester.ensureVisible(productivityCardFinder);
        await _boundedPumpAndSettle(tester);

        // 1. Assert real trend direction and data values
        switch (scenario.reportMode) {
          case _ReportMode.empty:
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.byIcon(Icons.trending_flat),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.text('0'),
              ),
              findsWidgets,
            );
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.text(I18n.tr('today.productivity.flat')),
              ),
              findsOneWidget,
            );
            break;
          case _ReportMode.positive:
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.byIcon(Icons.trending_up),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.textContaining('+'),
              ),
              findsOneWidget,
            );
            break;
          case _ReportMode.negative:
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.byIcon(Icons.trending_down),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.textContaining('-'),
              ),
              findsOneWidget,
            );
            break;
          case _ReportMode.flat:
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.byIcon(Icons.trending_flat),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: productivityCardFinder,
                matching: find.text(I18n.tr('today.productivity.flat')),
              ),
              findsOneWidget,
            );
            break;
        }

        // 2. Check complete Latin words: exact regex match offsets, no split across lines
        _assertCompleteLatinWords(tester, productivityCardFinder);

        // 3. Check paragraph/glyph boxes against true ancestor scrollable viewport
        await _assertCardParagraphsInsideViewport(
          tester,
          productivityCardFinder,
          scrollableFinder,
        );

        // 4. Verify themed reference colors with skipOffstage: false
        final cardElement = tester.element(productivityCardFinder);
        final cardTheme = Theme.of(cardElement);
        final initialRefTheme = Theme.of(
          tester.element(
            find.byKey(
              ValueKey('ref_theme_${scenario.initialBrand}'),
              skipOffstage: false,
            ),
          ),
        );
        expect(
          cardTheme.colorScheme.primary,
          initialRefTheme.colorScheme.primary,
        );

        await _capture(tester, fixture.boundaryKey, '${scenario.name}-initial');

        // 5. Live switched intermediate state: perform word/glyph & retention checks
        await tester.runAsync(() async {
          expect(await fixture.theme.setBrand(scenario.targetBrand), isTrue);
        });
        I18n.setLocale(scenario.targetLocale);
        await _boundedPumpAndSettle(tester);

        expect(tester.element(screenFinder), same(initialScreenElement));
        expect(ModalRoute.of(tester.element(screenFinder)), same(initialRoute));
        expect(
          tester.state<ScrollableState>(scrollableFinder),
          same(initialScrollableState),
        );

        final targetRefTheme = Theme.of(
          tester.element(
            find.byKey(
              ValueKey('ref_theme_${scenario.targetBrand}'),
              skipOffstage: false,
            ),
          ),
        );
        expect(
          Theme.of(tester.element(productivityCardFinder)).colorScheme.primary,
          targetRefTheme.colorScheme.primary,
        );

        _assertCompleteLatinWords(tester, productivityCardFinder);
        await _assertCardParagraphsInsideViewport(
          tester,
          productivityCardFinder,
          scrollableFinder,
        );

        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-switched',
        );

        // 6. Complete roundtrip back to initialBrand & initialLocale
        await tester.runAsync(() async {
          expect(await fixture.theme.setBrand(scenario.initialBrand), isTrue);
        });
        I18n.setLocale(scenario.initialLocale);
        await _boundedPumpAndSettle(tester);

        expect(tester.element(screenFinder), same(initialScreenElement));
        expect(ModalRoute.of(tester.element(screenFinder)), same(initialRoute));
        expect(
          tester.state<ScrollableState>(scrollableFinder),
          same(initialScrollableState),
        );

        expect(
          Theme.of(tester.element(productivityCardFinder)).colorScheme.primary,
          initialRefTheme.colorScheme.primary,
        );

        _assertCompleteLatinWords(tester, productivityCardFinder);
        await _assertCardParagraphsInsideViewport(
          tester,
          productivityCardFinder,
          scrollableFinder,
        );

        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-roundtrip',
        );

        // 7. Tap card to open weekly review / StatisticsScreen once
        await tester.tap(productivityCardFinder);
        await _boundedPumpAndSettle(tester);

        expect(find.byType(StatisticsScreen), findsOneWidget);
        await _capture(
          tester,
          fixture.boundaryKey,
          '${scenario.name}-review-opened',
        );

        // Pop back to TodayScreen and verify element restoration
        fixture.navigatorKey.currentState?.pop();
        await _boundedPumpAndSettle(tester);

        expect(find.byType(StatisticsScreen), findsNothing);
        expect(find.byType(TodayScreen), findsOneWidget);
        expect(tester.element(screenFinder), same(initialScreenElement));

        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }
}
