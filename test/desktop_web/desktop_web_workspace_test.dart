import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/almanac_locale_format.dart';
import 'package:duoyi/core/almanac_ui_copy.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/lunar_calendar.dart';
import 'package:duoyi/desktop_web/desktop_web_nav.dart';
import 'package:duoyi/desktop_web/desktop_web_tokens.dart';
import 'package:duoyi/desktop_web/desktop_web_workspace.dart';
import 'package:duoyi/desktop_web/views/desktop_almanac_view.dart';
import 'package:duoyi/desktop_web/views/desktop_embedded_page.dart';
import 'package:duoyi/desktop_web/views/desktop_habit_view.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/models/calendar_event.dart';
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
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/almanac_tools_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/holiday_calendar.dart';
import 'package:duoyi/widgets/sync_status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WorkspaceFixture {
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
  final DateTime today;

  _WorkspaceFixture(this.auth, this.today);

  static Future<_WorkspaceFixture> create({
    String brandId = 'defaultBrand',
    AppLocale locale = AppLocale.zh,
    bool populated = true,
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
    final fixture = _WorkspaceFixture(auth, today);
    await fixture.localeProvider.setLocale(locale);
    await fixture.theme.loadFromStorage();
    await fixture.theme.setBrand(brandId);
    await fixture.user.applyAccountSnapshot(
      username: 'desktop_tester',
      displayName: locale == AppLocale.en ? 'Desktop Tester' : '桌面工作区用户',
      avatarInitials: 'D',
    );

    if (populated) {
      await fixture.todos.addTodo(
        TodoItem(
          id: 'dw-todo-1',
          title: locale == AppLocale.en
              ? 'Review quarterly roadmap'
              : '整理本周规划并核对优先级',
          date: today,
          dueDate: today.add(const Duration(hours: 18)),
          listGroupName: locale == AppLocale.en ? 'Work' : '工作',
          priority: TodoPriority.high,
          quadrant: EisenhowerQuadrant.urgentImportant,
        ),
      );
      await fixture.todos.addTodo(
        TodoItem(
          id: 'dw-todo-2',
          title: locale == AppLocale.en
              ? 'Read design spec chapter'
              : '阅读桌面端交互规范',
          date: today.add(const Duration(days: 1)),
          listGroupName: locale == AppLocale.en ? 'Study' : '学习',
          priority: TodoPriority.medium,
          quadrant: EisenhowerQuadrant.notUrgentImportant,
        ),
      );
      await fixture.calendar.addLocalEvent(
        CalendarEvent(
          id: 'dw-evt-1',
          title: locale == AppLocale.en ? 'Design Sync' : '周度架构同步会',
          date: today,
          type: CalendarEventType.event,
          color: const Color(0xFF4CAF50),
          time: const TimeOfDay(hour: 10, minute: 30),
        ),
      );
    }

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
      child: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (_, currentLocale, _) => MaterialApp(
          locale: currentLocale.flutterLocale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: theme.brand.theme,
          home: child,
        ),
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

Future<void> _runDesktopWorkspaceTest(
  WidgetTester tester,
  _WorkspaceFixture fixture, {
  Size size = const Size(1440, 900),
  DesktopWebNavController? controller,
  DesktopWebDestination initialDestination = DesktopWebDestination.today,
  Widget? customHome,
  required Future<void> Function() body,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  final captured = <String>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final contextDesc = details.context?.toDescription() ?? '';
    final info = details.informationCollector
            ?.call()
            .map((node) => node.toStringDeep())
            .take(3)
            .join('\n') ??
        '';
    final stackTop =
        details.stack?.toString().split('\n').take(6).join('\n') ?? '';
    final entry = <String>[
      details.exceptionAsString(),
      if (contextDesc.isNotEmpty) 'Context: $contextDesc',
      if (info.isNotEmpty) info,
      if (stackTop.isNotEmpty) stackTop,
    ].join('\n');
    captured.add(entry);
    debugPrint('Captured FlutterError:\n$entry');
  };

  try {
    await tester.pumpWidget(
      fixture.wrapWithProviders(
        customHome ??
            DesktopWebWorkspace(
              initialDestination: initialDestination,
              controller: controller,
            ),
      ),
    );
    await _pumpSettledBounded(tester);
    await body();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  } finally {
    FlutterError.onError = previousOnError;
  }

  expect(
    tester.takeException(),
    isNull,
    reason: 'Expected zero unhandled exceptions during desktop workspace test',
  );
  expect(
    captured,
    isEmpty,
    reason: 'Expected zero FlutterError / RenderFlex overflow errors',
  );
}

Future<void> _pumpSettledBounded(WidgetTester tester) async {
  // DesktopFocusView starts a repeating halo animation when active; bounded
  // frame pumps work reliably across both calm and animated destinations.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
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
    addTearDown(() {
      MainShell.debugUseDesktopWebWorkspace = null;
      I18n.setLocale(AppLocale.zh);
    });
  });

  group('MainShell desktop workspace dispatch & regression safety', () {
    testWidgets(
      'mounts DesktopWebWorkspace >= 960px when enabled, keeps < 960px and false untouched',
      (tester) async {
        final fixture = await _WorkspaceFixture.create();

        MainShell.debugUseDesktopWebWorkspace = true;
        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          customHome: const MainShell(),
          body: () async {
            expect(find.byType(DesktopWebWorkspace), findsOneWidget);
            expect(
              find.byKey(const ValueKey('desktop_web_workspace')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('desktop_workspace_sidebar')),
              findsOneWidget,
            );

            tester.view.physicalSize = const Size(960, 800);
            await _pumpSettledBounded(tester);
            expect(find.byType(DesktopWebWorkspace), findsOneWidget);

            tester.view.physicalSize = const Size(840, 800);
            await _pumpSettledBounded(tester);
            expect(find.byType(DesktopWebWorkspace), findsNothing);

            MainShell.debugUseDesktopWebWorkspace = false;
            tester.view.physicalSize = const Size(1440, 900);
            await _pumpSettledBounded(tester);
            expect(find.byType(DesktopWebWorkspace), findsNothing);
          },
        );
      },
    );
  });

  group('Responsive themes & locales matrix (1440x900 & 1280x800)', () {
    final configs = <({
      String label,
      Size size,
      String brandId,
      bool dark,
      AppLocale locale,
    })>[
      (
        label: '1440x900 defaultBrand light zh',
        size: const Size(1440, 900),
        brandId: AppBrands.defaultBrand.id,
        dark: false,
        locale: AppLocale.zh,
      ),
      (
        label: '1440x900 defaultBrand dark zh',
        size: const Size(1440, 900),
        brandId: AppBrands.defaultBrand.id,
        dark: true,
        locale: AppLocale.zh,
      ),
      (
        label: '1440x900 liquidGlass en',
        size: const Size(1440, 900),
        brandId: AppBrands.liquidGlass.id,
        dark: false,
        locale: AppLocale.en,
      ),
      (
        label: '1280x800 defaultBrand light en',
        size: const Size(1280, 800),
        brandId: AppBrands.defaultBrand.id,
        dark: false,
        locale: AppLocale.en,
      ),
      (
        label: '1280x800 liquidGlass dark zh',
        size: const Size(1280, 800),
        brandId: AppBrands.liquidGlass.id,
        dark: true,
        locale: AppLocale.zh,
      ),
    ];

    for (final cfg in configs) {
      testWidgets('zero overflows across primary views in ${cfg.label}', (
        tester,
      ) async {
        final fixture = await _WorkspaceFixture.create(
          brandId: cfg.brandId,
          locale: cfg.locale,
        );
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
        )..setDarkModeOverride(cfg.dark);
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: cfg.size,
          controller: controller,
          body: () async {
            for (final dest in const [
              DesktopWebDestination.today,
              DesktopWebDestination.todo,
              DesktopWebDestination.habit,
              DesktopWebDestination.calendar,
              DesktopWebDestination.focus,
              DesktopWebDestination.almanac,
            ]) {
              final navFinder = find.byKey(
                ValueKey('desktop_nav_${dest.name}'),
              );
              await tester.ensureVisible(navFinder);
              await tester.tap(navFinder);
              await _pumpSettledBounded(tester);

              expect(controller.destination, dest);
              expect(
                find.byKey(const ValueKey('desktop_workspace_sidebar')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('desktop_workspace_topbar')),
                findsOneWidget,
              );
            }
          },
        );
      });
    }
  });

  group('Today Command Center & Todo 3-pane workspace', () {
    testWidgets(
      'Today inline quick-add creates todo & Todo 3-pane switches views and edits inspector',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            final todayQuickAdd = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText == '快速添加今日待办，按 Enter 创建...',
            );
            expect(todayQuickAdd, findsOneWidget);
            await tester.enterText(todayQuickAdd, '完成桌面端发布检查');
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await _pumpSettledBounded(tester);

            expect(
              fixture.todos.todos.any((t) => t.title == '完成桌面端发布检查'),
              isTrue,
            );

            final todoNav = find.byKey(const ValueKey('desktop_nav_todo'));
            await tester.ensureVisible(todoNav);
            await tester.tap(todoNav);
            await _pumpSettledBounded(tester);

            expect(find.text('全部待办'), findsWidgets);
            final todoQuickAdd = find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText == '输入待办标题，Enter 添加到当前清单...',
            );
            expect(todoQuickAdd, findsOneWidget);
            await tester.enterText(todoQuickAdd, '三栏视图新建事项');
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await _pumpSettledBounded(tester);

            expect(
              fixture.todos.todos.any((t) => t.title == '三栏视图新建事项'),
              isTrue,
            );

            await tester.tap(find.text('三栏视图新建事项').first);
            await _pumpSettledBounded(tester);

            final notesField = find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.hintText == '添加备注或细节...',
            );
            expect(notesField, findsOneWidget);
            await tester.enterText(notesField, '需要附带桌面截图说明');
            await tester.pump(const Duration(milliseconds: 100));

            for (final mode in const ['看板', '四象限', '列表']) {
              final modeFinder = find.text(mode).first;
              await tester.ensureVisible(modeFinder);
              await tester.tap(modeFinder);
              await _pumpSettledBounded(tester);
            }
          },
        );
      },
    );
  });

  group('Desktop Habit Matrix & Starter Templates', () {
    testWidgets(
      'empty starter templates add habit, 7-day matrix + check-in/undo + create dialog work cleanly',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(
          locale: AppLocale.zh,
          populated: false,
        );
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.habit,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            expect(
              find.byKey(const ValueKey('desktop_habit_view')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('desktop_habit_empty_state')),
              findsOneWidget,
            );
            final waterStarter = find.byKey(
              const ValueKey('desktop_habit_starter_habit.water'),
            );
            await tester.ensureVisible(waterStarter);
            await tester.tap(waterStarter);
            await _pumpSettledBounded(tester);

            expect(fixture.habits.habits, hasLength(1));
            final starterHabit = fixture.habits.habits.first;
            expect(
              find.byKey(const ValueKey('desktop_habit_metrics_bar')),
              findsOneWidget,
            );
            expect(
              find.byKey(ValueKey('desktop_habit_card_${starterHabit.id}')),
              findsOneWidget,
            );
            expect(
              find.byKey(ValueKey('desktop_habit_matrix_${starterHabit.id}')),
              findsOneWidget,
            );
            for (var weekday = 1; weekday <= 7; weekday++) {
              expect(
                find.byKey(
                  ValueKey('desktop_habit_dot_${starterHabit.id}_$weekday'),
                ),
                findsOneWidget,
              );
            }

            final checkInBtn = find.byKey(
              ValueKey('desktop_habit_checkin_${starterHabit.id}'),
            );
            await tester.ensureVisible(checkInBtn);
            await tester.tap(checkInBtn);
            await _pumpSettledBounded(tester);
            expect(fixture.habits.habits.first.todayCount(), 1);

            final undoBtn = find.byKey(
              ValueKey('desktop_habit_undo_${starterHabit.id}'),
            );
            expect(undoBtn, findsOneWidget);
            await tester.ensureVisible(undoBtn);
            await tester.tap(undoBtn);
            await _pumpSettledBounded(tester);
            expect(fixture.habits.habits.first.todayCount(), 0);

            final todayWeekday = DateTime.now().weekday;
            final todayDot = find.byKey(
              ValueKey('desktop_habit_dot_${starterHabit.id}_$todayWeekday'),
            );
            await tester.ensureVisible(todayDot);
            await tester.tap(todayDot);
            await _pumpSettledBounded(tester);
            expect(fixture.habits.habits.first.todayCount(), greaterThan(0));

            final heatmapToggle = find.byKey(
              const ValueKey('desktop_habit_filter_heatmap'),
            );
            await tester.ensureVisible(heatmapToggle);
            await tester.tap(heatmapToggle);
            await _pumpSettledBounded(tester);

            final addBtn = find.byKey(
              const ValueKey('desktop_habit_add_button'),
            ).first;
            await tester.ensureVisible(addBtn);
            await tester.tap(addBtn);
            await _pumpSettledBounded(tester);
            expect(find.byType(Dialog), findsOneWidget);

            await tester.enterText(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(TextField),
              ).first,
              '晚间复盘 10 分钟',
            );
            await tester.tap(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(FilledButton),
              ),
            );
            await _pumpSettledBounded(tester);

            expect(
              fixture.habits.habits.any((h) => h.name == '晚间复盘 10 分钟'),
              isTrue,
            );
            final todayFilter = find.byKey(
              const ValueKey('desktop_habit_filter_today'),
            );
            await tester.ensureVisible(todayFilter);
            await tester.tap(todayFilter);
            await _pumpSettledBounded(tester);
            final allFilter = find.byKey(
              const ValueKey('desktop_habit_filter_all'),
            );
            await tester.ensureVisible(allFilter);
            await tester.tap(allFilter);
            await _pumpSettledBounded(tester);
          },
        );
      },
    );
  });

  group('Calendar & Focus Studio inside persistent Desktop Shell', () {
    testWidgets(
      'Calendar switches month/week/day/year modes & Focus studio runs inside shell',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.calendar,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            expect(find.text('今天'), findsWidgets);
            expect(find.text('这一天的日记'), findsOneWidget);
            for (final modeLabel in const ['周', '日', '年', '月']) {
              final modeFinder = find.text(modeLabel).first;
              await tester.ensureVisible(modeFinder);
              await tester.tap(modeFinder);
              await _pumpSettledBounded(tester);
            }

            final focusNav = find.byKey(const ValueKey('desktop_nav_focus'));
            await tester.ensureVisible(focusNav);
            await tester.tap(focusNav);
            await _pumpSettledBounded(tester);

            expect(
              find.byKey(const ValueKey('desktop_workspace_sidebar')),
              findsOneWidget,
            );
            expect(find.text('白噪音氛围'), findsOneWidget);
            expect(find.text('专注计时'), findsOneWidget);
            expect(find.text('专注记录'), findsOneWidget);
            expect(find.text('专注自习室'), findsOneWidget);

            final chip45 = find.text('45 分钟').first;
            await tester.ensureVisible(chip45);
            await tester.tap(chip45);
            await _pumpSettledBounded(tester);
            expect(fixture.pomodoro.effectiveFocusDuration, 45 * 60);

            for (final tab in const ['专注记录', '专注自习室', '专注计时']) {
              final tabFinder = find.text(tab).first;
              await tester.ensureVisible(tabFinder);
              await tester.tap(tabFinder);
              await _pumpSettledBounded(tester);
            }
          },
        );
      },
    );
  });

  group('Desktop Almanac, Holiday Badges & Calendar Integration', () {
    testWidgets(
      'Sidebar, Today Almanac card, and Command Palette jump directly to DesktopAlmanacView',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            final todayAlmanacCard = find.byKey(
              const ValueKey('desktop_today_almanac_card'),
            );
            expect(todayAlmanacCard, findsOneWidget);
            await tester.ensureVisible(todayAlmanacCard);
            await tester.tap(todayAlmanacCard);
            await _pumpSettledBounded(tester);

            expect(controller.destination, DesktopWebDestination.almanac);
            expect(controller.focusedCalendarDate, fixture.today);
            expect(
              find.byKey(const ValueKey('desktop_almanac_view')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('desktop_embedded_almanac')),
              findsNothing,
            );

            final todayNav = find.byKey(const ValueKey('desktop_nav_today'));
            await tester.ensureVisible(todayNav);
            await tester.tap(todayNav);
            await _pumpSettledBounded(tester);
            expect(controller.destination, DesktopWebDestination.today);

            final searchBtn = find.byKey(
              const ValueKey('desktop_topbar_search_button'),
            );
            await tester.tap(searchBtn);
            await _pumpSettledBounded(tester);

            final paletteInput = find.byKey(
              const ValueKey('desktop_command_palette_input'),
            );
            expect(paletteInput, findsOneWidget);
            await tester.enterText(paletteInput, '万年历');
            await _pumpSettledBounded(tester);

            expect(
              find.byKey(const ValueKey('command_item_nav-almanac')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('command_item_cmd-almanac-auspicious')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('command_item_cmd-almanac-holidays')),
              findsOneWidget,
            );

            final toolsCmd = find.byKey(
              const ValueKey('command_item_cmd-almanac-tools'),
            );
            expect(toolsCmd, findsOneWidget);
            await tester.tap(toolsCmd);
            await _pumpSettledBounded(tester);

            expect(controller.destination, DesktopWebDestination.almanac);
            expect(controller.almanacTabIndex, 3);
            expect(
              find.text(AlmanacUiCopy.solarLunarConverterTitle),
              findsOneWidget,
            );
            expect(find.text(AlmanacUiCopy.intervalCalcTitle), findsOneWidget);
          },
        );
      },
    );

    testWidgets(
      'DesktopCalendarView shows holiday/makeup badges, ISO week, clickable Yi/Ji explanations, and opens DesktopAlmanacView',
      (tester) async {
        final targetDate = DateTime(2026, 10, 1);
        final oct1Detail = LunarCalendar.tryAlmanacDetail(targetDate)!;
        final rawYi = oct1Detail.suitable
            .trim()
            .split(RegExp(r'\s+'))
            .firstWhere((t) => t.isNotEmpty);
        final formattedYi = AlmanacLocaleFormat.formatActivityTerm(
          rawYi,
          AppLocale.zh,
        );
        final explanation = AlmanacToolsService.explainAlmanacTerm(
          rawYi,
          english: false,
        );

        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.calendar,
        )..focusCalendarDate(targetDate);
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            expect(find.text(AlmanacUiCopy.holidayTag), findsWidgets);
            expect(find.text(AlmanacUiCopy.makeupWorkdayTag), findsWidgets);
            expect(find.text('W40'), findsOneWidget);
            expect(
              find.text(AlmanacUiCopy.isoWeekBadge(40, AppLocale.zh)),
              findsWidgets,
            );

            final yiChip = find.text(formattedYi).first;
            await tester.ensureVisible(yiChip);
            await tester.tap(yiChip);
            await _pumpSettledBounded(tester);

            expect(
              find.text(AlmanacUiCopy.plainExplanationTitle),
              findsOneWidget,
            );
            expect(
              find.text(explanation.localizedExplanation(AppLocale.zh)),
              findsOneWidget,
            );

            final closeBtn = find.text(
              AlmanacUiCopy.dialogConfirm(locale: AppLocale.zh),
            );
            await tester.tap(closeBtn);
            await _pumpSettledBounded(tester);

            final yearBtn = find.text('年').first;
            await tester.ensureVisible(yearBtn);
            await tester.tap(yearBtn);
            await _pumpSettledBounded(tester);
            expect(find.text(AlmanacUiCopy.holidayTag), findsWidgets);
            expect(find.text(AlmanacUiCopy.makeupWorkdayTag), findsWidgets);

            final monthBtn = find.text('月').first;
            await tester.ensureVisible(monthBtn);
            await tester.tap(monthBtn);
            await _pumpSettledBounded(tester);

            final openAlmanacBtn = find.byKey(
              const ValueKey('desktop_calendar_open_almanac'),
            );
            await tester.ensureVisible(openAlmanacBtn);
            await tester.tap(openAlmanacBtn);
            await _pumpSettledBounded(tester);

            expect(controller.destination, DesktopWebDestination.almanac);
            expect(controller.focusedCalendarDate, targetDate);
            expect(
              find.byKey(const ValueKey('desktop_almanac_view')),
              findsOneWidget,
            );

            final expandHighlights = find.byKey(
              const ValueKey('almanac_highlights_expand_toggle'),
            );
            expect(expandHighlights, findsOneWidget);
            await tester.ensureVisible(expandHighlights);
            await tester.tap(expandHighlights);
            await _pumpSettledBounded(tester);
            expect(
              find.descendant(
                of: expandHighlights,
                matching: find.text(AlmanacUiCopy.collapseTerms),
              ),
              findsOneWidget,
            );
          },
        );
      },
    );

    testWidgets(
      'DesktopAlmanacView tabs 0-3 (Classical, Auspicious Finder, Holidays, Tools & BaZi) including leap month conversion',
      (tester) async {
        final seedDate = DateTime(2025, 6, 15);
        final seedDetail = LunarCalendar.tryAlmanacDetail(seedDate)!;
        final rawYi = seedDetail.suitable
            .trim()
            .split(RegExp(r'\s+'))
            .firstWhere((t) => t.isNotEmpty);

        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.almanac,
        )..focusCalendarDate(seedDate);
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            expect(find.byType(DesktopAlmanacView), findsOneWidget);
            expect(find.text('2025年'), findsOneWidget);
            expect(find.text('6月'), findsOneWidget);

            // Tab 0: Shichen selection & Yi/Ji plain-language dialog
            final shichen5 = find.byKey(const ValueKey('almanac_shichen_5'));
            await tester.ensureVisible(shichen5);
            await tester.tap(shichen5);
            await _pumpSettledBounded(tester);
            final shichenDetail = find.byKey(
              const ValueKey('almanac_shichen_detail'),
            );
            expect(shichenDetail, findsOneWidget);
            expect(
              find.descendant(
                of: shichenDetail,
                matching: find.textContaining('巳'),
              ),
              findsWidgets,
            );

            final yiTermKey = ValueKey(
              'almanac_term_${AlmanacUiCopy.auspiciousLabel}_$rawYi',
            );
            final yiChip = find.byKey(yiTermKey);
            await tester.ensureVisible(yiChip);
            await tester.tap(yiChip);
            await _pumpSettledBounded(tester);
            expect(
              find.text(AlmanacUiCopy.plainExplanationTitle),
              findsOneWidget,
            );
            await tester.tap(
              find.text(AlmanacUiCopy.dialogConfirm(locale: AppLocale.zh)),
            );
            await _pumpSettledBounded(tester);

            // Tab 1: Auspicious day finder -> click result jumps left calendar
            final tab1 = find.byKey(const ValueKey('almanac_tab_1'));
            await tester.tap(tab1);
            await _pumpSettledBounded(tester);

            final movingKey = AlmanacToolsService.presetActivities[1].key;
            await tester.tap(find.byKey(ValueKey('almanac_preset_$movingKey')));
            await _pumpSettledBounded(tester);
            await tester.tap(find.byKey(const ValueKey('almanac_range_365')));
            await _pumpSettledBounded(tester);
            await tester.tap(
              find.byKey(const ValueKey('almanac_auspicious_weekend_toggle')),
            );
            await _pumpSettledBounded(tester);

            final resultFinder = find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'almanac_auspicious_result_',
                  ),
            );
            expect(resultFinder, findsWidgets);
            final rawKey =
                (tester.widget(resultFinder.first).key! as ValueKey<String>)
                    .value;
            final parts = rawKey
                .replaceFirst('almanac_auspicious_result_', '')
                .split('-');
            final jumpedDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
            await tester.ensureVisible(resultFinder.first);
            await tester.tap(resultFinder.first);
            await _pumpSettledBounded(tester);
            expect(controller.focusedCalendarDate, jumpedDate);

            // Tab 2: Statutory holiday schedule & 2027 switch
            final tab2 = find.byKey(const ValueKey('almanac_tab_2'));
            await tester.tap(tab2);
            await _pumpSettledBounded(tester);

            final year2027 = find.byKey(
              const ValueKey('almanac_holiday_year_2027'),
            );
            await tester.ensureVisible(year2027);
            await tester.tap(year2027);
            await _pumpSettledBounded(tester);
            final schedules2027 = HolidayCalendar.schedulesForYear(2027);
            expect(schedules2027, isNotEmpty);
            expect(
              find.textContaining(
                schedules2027.first.localizedName(AppLocale.zh),
              ),
              findsWidgets,
            );

            // Tab 3: Date interval, offset, Solar/Lunar leap-month conversion, 24 terms & BaZi
            final tab3 = find.byKey(const ValueKey('almanac_tab_3'));
            await tester.tap(tab3);
            await _pumpSettledBounded(tester);

            final intervalToggle = find.byKey(
              const ValueKey('almanac_interval_inclusive_toggle'),
            );
            await tester.ensureVisible(intervalToggle);
            await tester.tap(intervalToggle);
            await _pumpSettledBounded(tester);

            final deltaField = find.byKey(
              const ValueKey('almanac_offset_delta_field'),
            );
            await tester.ensureVisible(deltaField);
            await tester.enterText(deltaField, '14');
            await _pumpSettledBounded(tester);
            final workdaysToggle = find.byKey(
              const ValueKey('almanac_offset_workdays_toggle'),
            );
            await tester.ensureVisible(workdaysToggle);
            await tester.tap(workdaysToggle);
            await _pumpSettledBounded(tester);

            // Test 2025 leap 6th month via direct Lunar->Solar converter
            final convLunarToSolar = find.byKey(
              const ValueKey('almanac_conv_lunar_to_solar'),
            );
            await tester.ensureVisible(convLunarToSolar);
            await tester.tap(convLunarToSolar);
            await _pumpSettledBounded(tester);

            final jumpLeapBtn = find.byKey(
              const ValueKey('almanac_conv_jump_leap_month'),
            );
            expect(jumpLeapBtn, findsOneWidget);
            await tester.ensureVisible(jumpLeapBtn);
            await tester.tap(jumpLeapBtn);
            await _pumpSettledBounded(tester);
            final leapSwitch = find.byKey(
              const ValueKey('almanac_conv_leap_switch'),
            );
            expect(leapSwitch, findsOneWidget);
            expect(tester.widget<Switch>(leapSwitch).value, isTrue);
            expect(find.textContaining('闰六月'), findsWidgets);

            expect(
              find.textContaining(AlmanacUiCopy.yearSolarTermsTitle),
              findsOneWidget,
            );
            expect(find.text(AlmanacUiCopy.baziTitle), findsOneWidget);
          },
        );
      },
    );

    testWidgets(
      'DesktopAlmanacView renders tab bar & all tabs cleanly in < 820px single-column mode',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(locale: AppLocale.en);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.almanac,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1000, 760),
          controller: controller,
          body: () async {
            for (var i = 0; i < 4; i++) {
              final tab = find.byKey(ValueKey('almanac_tab_$i'));
              expect(tab, findsOneWidget);
              await tester.ensureVisible(tab);
              await tester.tap(tab);
              await _pumpSettledBounded(tester);
            }
          },
        );
      },
    );
  });

  group('Embedded Secondary Pages & Account Overview', () {
    testWidgets(
      'all sidebar tool destinations embed inside shell and Account Overview opens Preferences cleanly',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1280, 800),
          controller: controller,
          body: () async {
            const embeddedDests = <DesktopWebDestination>[
              DesktopWebDestination.goals,
              DesktopWebDestination.notes,
              DesktopWebDestination.diary,
              DesktopWebDestination.stats,
              DesktopWebDestination.timeAudit,
              DesktopWebDestination.schedule,
              DesktopWebDestination.anniversary,
              DesktopWebDestination.countdown,
              DesktopWebDestination.themes,
              DesktopWebDestination.moreApps,
            ];

            for (final dest in embeddedDests) {
              final navFinder = find.byKey(
                ValueKey('desktop_nav_${dest.name}'),
              );
              await tester.ensureVisible(navFinder);
              await tester.tap(navFinder);
              await _pumpSettledBounded(tester);

              expect(
                find.byKey(const ValueKey('desktop_workspace_sidebar')),
                findsOneWidget,
                reason: 'Sidebar must stay visible while hosting ${dest.name}',
              );
              expect(
                find.byKey(ValueKey('desktop_embedded_${dest.name}')),
                findsOneWidget,
              );
            }

            final accountCard = find.byKey(
              const ValueKey('desktop_sidebar_account_card'),
            );
            await tester.ensureVisible(accountCard);
            await tester.tap(accountCard);
            await _pumpSettledBounded(tester);

            expect(
              find.byKey(const ValueKey('desktop_embedded_settings')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('desktop_account_overview_view')),
              findsOneWidget,
            );
            expect(find.byType(SyncStatusCard), findsOneWidget);

            final enSegment = find.text('English');
            await tester.ensureVisible(enSegment);
            await tester.tap(enSegment);
            await _pumpSettledBounded(tester);
            expect(
              find.text('Workspace Appearance & Language'),
              findsOneWidget,
            );

            final zhSegment = find.text('简体中文');
            await tester.ensureVisible(zhSegment);
            await tester.tap(zhSegment);
            await _pumpSettledBounded(tester);
            expect(find.text('桌面外观与语言'), findsOneWidget);

            final darkBtn = find.text('切换深色');
            await tester.ensureVisible(darkBtn);
            await tester.tap(darkBtn);
            await _pumpSettledBounded(tester);
            expect(controller.darkModeOverride, isTrue);

            final glassBtn = find.text('毛玻璃质感');
            await tester.ensureVisible(glassBtn);
            await tester.tap(glassBtn);
            await _pumpSettledBounded(tester);
            expect(controller.frostedOverride, isTrue);

            final prefsCard = find.byKey(
              const ValueKey('desktop_settings_card_preferences'),
            );
            await tester.ensureVisible(prefsCard);
            await tester.tap(prefsCard);
            await _pumpSettledBounded(tester);
            expect(find.byType(PreferencesScreen), findsOneWidget);

            Navigator.of(tester.element(find.byType(PreferencesScreen))).pop();
            await _pumpSettledBounded(tester);
            expect(find.byType(DesktopAccountOverviewView), findsOneWidget);
            expect(
              find.byKey(const ValueKey('desktop_workspace_sidebar')),
              findsOneWidget,
            );
          },
        );
      },
    );
  });

  group('Command Palette (Ctrl+K) & Static Workspace Guardrails', () {
    testWidgets(
      'Ctrl+K opens command palette, filters & navigates, and toggles dark mode',
      (tester) async {
        final fixture = await _WorkspaceFixture.create(locale: AppLocale.zh);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.calendar,
        );
        addTearDown(controller.dispose);

        await _runDesktopWorkspaceTest(
          tester,
          fixture,
          size: const Size(1440, 900),
          controller: controller,
          body: () async {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
            await _pumpSettledBounded(tester);

            expect(
              find.byKey(const ValueKey('desktop_command_palette_modal')),
              findsOneWidget,
            );

            final input = find.byKey(
              const ValueKey('desktop_command_palette_input'),
            );
            await tester.enterText(input, '习惯');
            await _pumpSettledBounded(tester);

            final navHabitCmd = find.byKey(
              const ValueKey('command_item_nav-habit'),
            );
            expect(navHabitCmd, findsOneWidget);
            await tester.tap(navHabitCmd);
            await _pumpSettledBounded(tester);

            expect(controller.destination, DesktopWebDestination.habit);
            expect(find.byType(DesktopHabitView), findsOneWidget);

            await tester.tap(
              find.byKey(const ValueKey('desktop_topbar_search_button')),
            );
            await _pumpSettledBounded(tester);
            expect(
              find.byKey(const ValueKey('desktop_command_palette_modal')),
              findsOneWidget,
            );

            final input2 = find.byKey(
              const ValueKey('desktop_command_palette_input'),
            );
            await tester.enterText(input2, 'dark');
            await _pumpSettledBounded(tester);

            final toggleDarkCmd = find.byKey(
              const ValueKey('command_item_cmd-toggle-dark'),
            );
            expect(toggleDarkCmd, findsOneWidget);
            await tester.tap(toggleDarkCmd);
            await _pumpSettledBounded(tester);
            expect(controller.darkModeOverride, isTrue);
          },
        );
      },
    );

    test(
      'all lib/desktop_web files have zero FontWeight.bold/w500..w900 and zero syncNow calls',
      () {
        final root = Directory('lib/desktop_web');
        expect(root.existsSync(), isTrue);
        final bannedWeight = RegExp(
          r'FontWeight\.(bold|w[5-9]00)|DesignTokens\.fontWeightMedium',
        );
        final bannedSync = RegExp(r'\bsyncNow\s*\(');

        for (final entity in root.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final source = entity.readAsStringSync();
          expect(
            bannedWeight.hasMatch(source),
            isFalse,
            reason: '${entity.path} must not contain banned bold weights',
          );
          expect(
            bannedSync.hasMatch(source),
            isFalse,
            reason: '${entity.path} must not invoke syncNow()',
          );
        }
      },
    );

    testWidgets(
      'defaultBrand uses iOS System Blue accents distinct from liquidGlass in light & dark',
      (tester) async {
        expect(DesignTokens.defaultPrimary, const Color(0xFF0066D6));
        expect(DesignTokens.defaultPrimarySoft, const Color(0xFFE5F1FF));
        expect(DesignTokens.defaultPrimaryPressed, const Color(0xFF0051AB));

        Future<({DesktopWebTokens tokens, Color primary})> resolveWorkspace(
          AppBrand brand, {
          required bool dark,
        }) async {
          late DesktopWebTokens resolved;
          final theme = DesktopWebTokens.buildWorkspaceTheme(
            brand: brand,
            darkOverride: dark,
            frostedOverride: brand.style == BrandStyle.liquidGlass,
          );
          await tester.pumpWidget(
            Theme(
              data: theme,
              child: Builder(
                builder: (context) {
                  resolved = DesktopWebTokens.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
          return (tokens: resolved, primary: theme.colorScheme.primary);
        }

        final defaultLight = await resolveWorkspace(
          AppBrands.defaultBrand,
          dark: false,
        );
        final defaultDark = await resolveWorkspace(
          AppBrands.defaultBrand,
          dark: true,
        );
        final glassLight = await resolveWorkspace(
          AppBrands.liquidGlass,
          dark: false,
        );
        final glassDark = await resolveWorkspace(
          AppBrands.liquidGlass,
          dark: true,
        );

        expect(defaultLight.tokens.accent, const Color(0xFF0066D6));
        expect(defaultLight.primary, const Color(0xFF0066D6));
        expect(
          defaultLight.tokens.accent.b,
          greaterThan(defaultLight.tokens.accent.r),
        );
        expect(defaultLight.tokens.accentForeground, Colors.white);

        expect(defaultDark.tokens.accent, const Color(0xFF0A84FF));
        expect(defaultDark.primary, const Color(0xFF0A84FF));
        expect(
          defaultDark.tokens.accent.b,
          greaterThan(defaultDark.tokens.accent.r),
        );
        expect(defaultDark.tokens.accentForeground, Colors.white);

        expect(
          AppBrands.defaultBrand.theme.colorScheme.primary,
          const Color(0xFF0066D6),
        );
        expect(
          AppBrands.defaultBrand.theme.colorScheme.primary,
          isNot(equals(AppBrands.liquidGlass.theme.colorScheme.primary)),
        );
        expect(
          defaultLight.tokens.accent,
          isNot(equals(glassLight.tokens.accent)),
        );
        expect(
          defaultDark.tokens.accent,
          isNot(equals(glassDark.tokens.accent)),
        );
        expect(defaultDark.primary, isNot(equals(glassDark.primary)));
      },
    );
  });
}
