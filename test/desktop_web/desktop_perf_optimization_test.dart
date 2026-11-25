import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/desktop_web/desktop_command_palette.dart';
import 'package:duoyi/desktop_web/desktop_sidebar.dart';
import 'package:duoyi/desktop_web/desktop_topbar.dart';
import 'package:duoyi/desktop_web/desktop_web_nav.dart';
import 'package:duoyi/desktop_web/desktop_web_tokens.dart';
import 'package:duoyi/desktop_web/desktop_web_workspace.dart';
import 'package:duoyi/desktop_web/views/desktop_almanac_view.dart';
import 'package:duoyi/desktop_web/views/desktop_focus_view.dart';
import 'package:duoyi/desktop_web/views/desktop_habit_view.dart';
import 'package:duoyi/desktop_web/views/desktop_today_view.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/result_states.dart' show LoadingState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PerfTestFixture {
  final TodoProvider todos = TodoProvider();
  final HabitProvider habits = HabitProvider();
  final CalendarProvider calendar = CalendarProvider();
  final PomodoroProvider pomodoro = PomodoroProvider();
  final ThemeProvider theme = ThemeProvider();
  final CloudSyncProvider cloudSync = CloudSyncProvider();
  late final SyncStatusController syncStatus = SyncStatusController(
    source: cloudSync,
  );
  final UserProvider user = UserProvider();
  final PreferencesProvider preferences = PreferencesProvider();
  final QuickCaptureTemplateProvider quickTemplates =
      QuickCaptureTemplateProvider();
  final LocaleProvider localeProvider = LocaleProvider();
  final CountdownProvider countdown = CountdownProvider();
  final NoteProvider note = NoteProvider();
  final AnniversaryProvider anniversary = AnniversaryProvider();
  final DiaryProvider diary = DiaryProvider();
  final GoalProvider goal = GoalProvider();
  final CourseProvider course = CourseProvider();
  final AppLockProvider appLock = AppLockProvider();
  final AchievementProvider achievement = AchievementProvider();
  final CustomFocusSoundProvider customSound = CustomFocusSoundProvider();
  final FocusRoomProvider focusRoom = FocusRoomProvider();
  final ShareProvider share = ShareProvider();
  final TimeAuditProvider timeAudit = TimeAuditProvider();
  final LocationReminderProvider locationReminder = LocationReminderProvider();
  final CalendarSyncProvider calendarSync = CalendarSyncProvider();
  final NotificationService notifications = NotificationService();
  final AiService ai = AiService();
  final AppUpdateService appUpdate = AppUpdateService(
    repo: 'dq52099/duoyi',
    currentVersion: AppVersion.name,
  );
  final AuthProvider auth;

  _PerfTestFixture(this.auth);

  static Future<_PerfTestFixture> create({
    String brandId = 'liquidGlass',
    AppLocale locale = AppLocale.zh,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'active_brand': brandId,
      'theme_unlocked_brands': <String>[
        AppBrands.defaultBrand.id,
        AppBrands.liquidGlass.id,
        brandId,
      ],
    });
    I18n.setLocale(locale);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final auth = AuthProvider(
      initialState: const AuthState(),
      client: ApiClient(
        baseUrl: 'https://duoyi.example.test',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'offline test fixture'}),
            404,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    final fixture = _PerfTestFixture(auth);
    await fixture.localeProvider.setLocale(locale);
    await fixture.theme.loadFromStorage();
    await fixture.theme.setBrand(brandId);
    await fixture.todos.addTodo(
      TodoItem(
        id: 'perf-todo-1',
        title: '整理季度规划',
        date: today,
        dueDate: today.add(const Duration(hours: 18)),
        priority: TodoPriority.high,
      ),
    );
    await fixture.note.addOrUpdateNotePersisted(
      NoteItem(
        id: 'perf-note-1',
        content: '季度复盘会议纪要',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await fixture.habits.addHabit(
      Habit(
        id: 'perf-habit-1',
        name: '每日阅读',
        icon: Icons.book.codePoint.toString(),
      ),
    );
    addTearDown(fixture.dispose);
    return fixture;
  }

  Widget wrapWithProviders(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider<HabitProvider>.value(value: habits),
        ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<CloudSyncProvider>.value(value: cloudSync),
        ChangeNotifierProvider<SyncStatusController>.value(value: syncStatus),
        ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
        ChangeNotifierProvider<UserProvider>.value(value: user),
        ChangeNotifierProvider<CountdownProvider>.value(value: countdown),
        ChangeNotifierProvider<NoteProvider>.value(value: note),
        ChangeNotifierProvider<AnniversaryProvider>.value(value: anniversary),
        ChangeNotifierProvider<DiaryProvider>.value(value: diary),
        ChangeNotifierProvider<GoalProvider>.value(value: goal),
        ChangeNotifierProvider<CourseProvider>.value(value: course),
        ChangeNotifierProvider<AppLockProvider>.value(value: appLock),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: quickTemplates,
        ),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
        ChangeNotifierProvider<AchievementProvider>.value(value: achievement),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: customSound,
        ),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: focusRoom),
        ChangeNotifierProvider<ShareProvider>.value(value: share),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<LocationReminderProvider>.value(
          value: locationReminder,
        ),
        ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendarSync),
        ChangeNotifierProvider<NotificationService>.value(value: notifications),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
        ChangeNotifierProvider<AppUpdateService>.value(value: appUpdate),
      ],
      child: MaterialApp(
        locale: localeProvider.locale.flutterLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: theme.brand.theme,
        home: child,
      ),
    );
  }

  void dispose() {
    syncStatus.dispose();
    todos.dispose();
    habits.dispose();
    calendar.dispose();
    pomodoro.dispose();
    theme.dispose();
    cloudSync.dispose();
    user.dispose();
    preferences.dispose();
    quickTemplates.dispose();
    localeProvider.dispose();
    countdown.dispose();
    note.dispose();
    anniversary.dispose();
    diary.dispose();
    goal.dispose();
    course.dispose();
    appLock.dispose();
    achievement.dispose();
    customSound.dispose();
    focusRoom.dispose();
    share.dispose();
    timeAudit.dispose();
    locationReminder.dispose();
    calendarSync.dispose();
    notifications.dispose();
    ai.dispose();
    appUpdate.dispose();
    auth.dispose();
  }
}

Future<void> _pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channels = <String>[
      'duoyi/focus_dnd',
      'duoyi/focus_sound_foreground',
      'duoyi/focus_distraction',
      'duoyi/platform_info',
    ];
    for (final name in channels) {
      final ch = MethodChannel(name);
      messenger.setMockMethodCallHandler(
        ch,
        (_) async => name == 'duoyi/focus_dnd'
            ? <String, dynamic>{'supported': false, 'accessGranted': false}
            : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(ch, null));
    }
    addTearDown(() => I18n.setLocale(AppLocale.zh));
  });

  testWidgets(
    'DesktopTodayView and DesktopAlmanacView render zero BackdropFilters in scrollables even in LiquidGlass',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fixture = await _PerfTestFixture.create(
        brandId: AppBrands.liquidGlass.id,
      );
      final controller = DesktopWebNavController(
        initialDestination: DesktopWebDestination.today,
        frostedOverride: true,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        fixture.wrapWithProviders(DesktopWebWorkspace(controller: controller)),
      );
      await _pumpBounded(tester);

      expect(find.byType(DesktopTodayView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DesktopTodayView),
          matching: find.byType(DesktopPanelCard),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopTodayView),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );

      // Static chrome (sidebar / topbar) stays isolated in RepaintBoundary.
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(DesktopTopBar), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('desktop_workspace_sidebar')),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('desktop_workspace_topbar')),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      expect(DesktopWebTokens.webChromeBlurSigma, lessThanOrEqualTo(8.0));

      controller.navigateTo(DesktopWebDestination.almanac);
      await _pumpBounded(tester);

      expect(find.byType(DesktopAlmanacView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DesktopAlmanacView),
          matching: find.byType(DesktopPanelCard),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopAlmanacView),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'DesktopWebWorkspace disables TickerMode on Offstage primaryStack and avoids Opacity saveLayer',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fixture = await _PerfTestFixture.create(
        brandId: AppBrands.defaultBrand.id,
      );
      final controller = DesktopWebNavController(
        initialDestination: DesktopWebDestination.focus,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        fixture.wrapWithProviders(DesktopWebWorkspace(controller: controller)),
      );
      await _pumpBounded(tester);

      // Start the focus timer so DesktopFocusView._haloCtrl runs while active.
      fixture.pomodoro.startIfIdle();
      await _pumpBounded(tester);
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      final stackFinder = find.descendant(
        of: find.byType(DesktopWebWorkspace),
        matching: find.byType(IndexedStack, skipOffstage: false),
        skipOffstage: false,
      );
      expect(stackFinder, findsOneWidget);

      final activeTickerMode = tester.widget<TickerMode>(
        find
            .ancestor(of: stackFinder, matching: find.byType(TickerMode))
            .first,
      );
      expect(activeTickerMode.enabled, isTrue);

      // Stage transition and DesktopFocusView must not use Opacity widgets.
      expect(
        find.descendant(
          of: find.byType(DesktopFocusView),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      // Navigate to an embedded page -> primaryStack goes Offstage with TickerMode(enabled: false).
      controller.navigateTo(DesktopWebDestination.notes);
      await _pumpBounded(tester);

      final offstageWidget = tester.widget<Offstage>(
        find
            .ancestor(
              of: stackFinder,
              matching: find.byType(Offstage, skipOffstage: false),
            )
            .first,
      );
      expect(offstageWidget.offstage, isTrue);

      final offstageTickerMode = tester.widget<TickerMode>(
        find
            .ancestor(
              of: stackFinder,
              matching: find.byType(TickerMode, skipOffstage: false),
            )
            .first,
      );
      expect(offstageTickerMode.enabled, isFalse);

      // After stage transition settles, background _haloCtrl ticks are completely muted.
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.binding.transientCallbackCount, 0);

      fixture.pomodoro.resetTimer();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'LoadingState _ShimmerBar uses RepaintBoundary + DecoratedBox gradient and zero ShaderMask',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingState(message: '加载中...', lines: 3),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        find.descendant(
          of: find.byType(LoadingState),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LoadingState),
          matching: find.byType(RepaintBoundary),
        ),
        findsAtLeastNWidgets(3),
      );

      final decoratedBoxes = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(LoadingState),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradientCount = decoratedBoxes.where((box) {
        final dec = box.decoration;
        return dec is BoxDecoration && dec.gradient is LinearGradient;
      }).length;
      expect(gradientCount, 3);
    },
  );

  testWidgets(
    'Desktop command palette debounces input and never re-runs GlobalSearch on ArrowUp/ArrowDown',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fixture = await _PerfTestFixture.create(
        brandId: AppBrands.defaultBrand.id,
      );
      final controller = DesktopWebNavController(
        initialDestination: DesktopWebDestination.today,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        fixture.wrapWithProviders(DesktopWebWorkspace(controller: controller)),
      );
      await _pumpBounded(tester);

      controller.openCommandPalette();
      await _pumpBounded(tester);

      final input = find.byKey(const ValueKey('desktop_command_palette_input'));
      expect(input, findsOneWidget);

      debugDesktopCommandPaletteSearchCount = 0;

      // Rapid keystrokes within 120ms debounce window should not trigger search yet.
      await tester.enterText(input, '季');
      await tester.pump(const Duration(milliseconds: 40));
      expect(debugDesktopCommandPaletteSearchCount, 0);

      await tester.enterText(input, '季度');
      await tester.pump(const Duration(milliseconds: 40));
      expect(debugDesktopCommandPaletteSearchCount, 0);

      // Once 120ms debounce expires, GlobalSearch runs exactly once.
      await tester.pump(const Duration(milliseconds: 140));
      expect(debugDesktopCommandPaletteSearchCount, 1);
      expect(
        find.byKey(const ValueKey('command_item_search-todo-perf-todo-1')),
        findsOneWidget,
      );

      // Keyboard arrow navigation must hit memoized results without re-running search.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(debugDesktopCommandPaletteSearchCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'DesktopHabitView renders lazy CustomScrollView + SliverList instead of eager Column',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fixture = await _PerfTestFixture.create(
        brandId: AppBrands.defaultBrand.id,
      );
      final controller = DesktopWebNavController(
        initialDestination: DesktopWebDestination.habit,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        fixture.wrapWithProviders(DesktopWebWorkspace(controller: controller)),
      );
      await _pumpBounded(tester);

      expect(find.byType(DesktopHabitView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DesktopHabitView),
          matching: find.byType(CustomScrollView),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DesktopHabitView),
          matching: find.byType(SliverList),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
