import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
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
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

// These are rendered-layout checks, not pixel goldens. Enable the optional
// evidence with DUOYI_CAPTURE_APP_UI_SCREENSHOT=1; all data below is synthetic.
const _profiles = [
  _Viewport('390-light', width: 390, textScale: 1, brandId: 'defaultBrand'),
  _Viewport('320-dark-1.6', width: 320, textScale: 1.6, brandId: 'starRail'),
];
const _todoTitle = '整理本周计划，确认下一步安排';
const _habitTitle = '阅读并记下一条收获';
const _eventTitle = '项目讨论与下周计划';
const _sessionTitle = '阅读与笔记整理';

enum _Page { login, mine, profile, todo, habit, calendar, focus }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const dndChannel = MethodChannel('duoyi/focus_dnd');
    messenger.setMockMethodCallHandler(
      dndChannel,
      (_) async => {'supported': false, 'accessGranted': false},
    );
    addTearDown(() => messenger.setMockMethodCallHandler(dndChannel, null));
  });

  for (final viewport in _profiles) {
    for (final page in _Page.values) {
      testWidgets('${page.name} content fits ${viewport.name}', (tester) async {
        final fixture = await _Fixture.create(
          viewport,
          signedIn: page != _Page.login,
        );
        await _pumpPage(tester, fixture, page, viewport);
        await _capture(tester, fixture, '${page.name}-${viewport.name}');

        switch (page) {
          case _Page.login:
            expect(find.byType(TextField), findsAtLeastNWidgets(2));
            expect(
              find.widgetWithText(FilledButton, I18n.tr('auth.login')),
              findsOneWidget,
            );
          case _Page.mine:
            expect(find.text('青禾 · 每天进步一点'), findsWidgets);
          case _Page.profile:
            final usernameField = find.widgetWithText(
              TextField,
              I18n.tr('auth.username'),
            );
            await _reveal(tester, usernameField);
            final username = tester.widget<TextField>(usernameField);
            expect(username.readOnly, isTrue);
            expect(username.controller?.text, 'qinghe_demo');
          case _Page.todo:
            expect(fixture.todos.todos, hasLength(3));
            expect(find.text(_todoTitle), findsWidgets);
          case _Page.habit:
            await _reveal(tester, find.text(_habitTitle));
            expect(find.text(_habitTitle), findsOneWidget);
          case _Page.calendar:
            await tester.tap(find.widgetWithText(Tab, '日'));
            await tester.pumpAndSettle();
            await _reveal(tester, find.text(_eventTitle));
            expect(find.text(_eventTitle), findsWidgets);
            final compactTitles = find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'calendar-compact-title-',
                  ),
            );
            expect(compactTitles, findsWidgets);
            for (final title in compactTitles.evaluate()) {
              expect(
                tester.getSize(find.byWidget(title.widget)).width,
                greaterThan(80),
                reason: 'Short events must retain room for their title',
              );
            }
            await _capture(tester, fixture, 'calendar-agenda-${viewport.name}');
          case _Page.focus:
            expect(find.text('25:00'), findsOneWidget);
            expect(fixture.pomodoro.state.isRunning, isFalse);
            expect(find.text('倒计时专注'), findsOneWidget);
            expect(find.text('尚未开始'), findsOneWidget);
            expect(find.text('专注中'), findsNothing);
            expect(find.text('剩余 100%'), findsOneWidget);
        }
        await _auditScrolling(tester, fixture, '${page.name}-${viewport.name}');
        await _unmount(tester);
      });
    }

    for (final page in [_Page.todo, _Page.habit, _Page.calendar]) {
      testWidgets('${page.name} empty state fits ${viewport.name}', (
        tester,
      ) async {
        final fixture = await _Fixture.create(viewport, populated: false);
        await _pumpPage(tester, fixture, page, viewport);

        if (page == _Page.calendar) {
          await tester.tap(find.widgetWithText(Tab, '日'));
          await tester.pumpAndSettle();
          expect(find.text(_eventTitle), findsNothing);
        } else {
          await _reveal(tester, find.byType(EmptyState));
          final empty = tester.widget<EmptyState>(find.byType(EmptyState));
          expect(empty.onAction, isNotNull);
          expect(empty.actionLabel, isNotEmpty);
        }
        expect(tester.takeException(), isNull);
        await _capture(tester, fixture, '${page.name}-empty-${viewport.name}');
        await _auditScrolling(
          tester,
          fixture,
          '${page.name}-empty-${viewport.name}',
        );
        await _unmount(tester);
      });
    }

    for (final page in [_Page.mine, _Page.profile]) {
      testWidgets('${page.name} guest state fits ${viewport.name}', (
        tester,
      ) async {
        final fixture = await _Fixture.create(viewport, signedIn: false);
        await _pumpPage(tester, fixture, page, viewport);
        expect(fixture.auth.state.isLoggedIn, isFalse);
        expect(find.text('qinghe_demo'), findsNothing);
        await _capture(tester, fixture, '${page.name}-guest-${viewport.name}');
        await _auditScrolling(
          tester,
          fixture,
          '${page.name}-guest-${viewport.name}',
        );
        await _unmount(tester);
      });
    }

    testWidgets('login busy and rejected states fit ${viewport.name}', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      final fixture = await _Fixture.create(
        viewport,
        signedIn: false,
        loginResponse: response.future,
      );
      await _pumpPage(tester, fixture, _Page.login, viewport);
      await tester.enterText(
        find.widgetWithText(TextField, I18n.tr('auth.account')),
        'qinghe_demo',
      );
      await tester.enterText(
        find.widgetWithText(TextField, I18n.tr('auth.password')),
        'fixture-password',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      final submit = find.widgetWithText(FilledButton, I18n.tr('auth.login'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _capture(tester, fixture, 'login-busy-${viewport.name}');

      response.complete(
        http.Response(
          jsonEncode({'detail': 'Invalid credentials'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('账号或密码错误，请重新输入'), findsOneWidget);
      expect(find.textContaining('Invalid credentials'), findsNothing);
      expect(find.textContaining('401'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, I18n.tr('auth.password')),
            )
            .controller
            ?.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, fixture, 'login-error-${viewport.name}');
      await _unmount(tester);
    });

    testWidgets('focus history retains task context at ${viewport.name}', (
      tester,
    ) async {
      final fixture = await _Fixture.create(viewport);
      await _pumpPage(tester, fixture, _Page.focus, viewport);
      await tester.tap(
        find.widgetWithText(Tab, fixture.theme.brand.strings.focusTabHistory),
      );
      await tester.pumpAndSettle();
      await _reveal(tester, find.text(_sessionTitle));
      expect(find.text(_sessionTitle), findsWidgets);
      expect(fixture.pomodoro.sessions.single.durationSeconds, 1500);
      expect(tester.takeException(), isNull);
      await _capture(tester, fixture, 'focus-history-${viewport.name}');
      await _auditScrolling(tester, fixture, 'focus-history-${viewport.name}');
      await _unmount(tester);
    });

    testWidgets(
      'habit check-in updates displayed progress at ${viewport.name}',
      (tester) async {
        final fixture = await _Fixture.create(viewport);
        await _pumpPage(tester, fixture, _Page.habit, viewport);
        final checkIn = find.text('打卡').first;
        await _reveal(tester, checkIn);
        await tester.tap(checkIn);
        await tester.pumpAndSettle();
        expect(fixture.habits.habits.first.todayCount(), 2);
        expect(fixture.habits.habits.first.isCompletedToday(), isTrue);
        expect(find.text('已达标'), findsWidgets);
        final completedButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '完成'),
        );
        expect(completedButton.onPressed, isNull);
        await _capture(tester, fixture, 'habit-checked-in-${viewport.name}');
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      },
    );
  }
}

class _Viewport {
  final String name;
  final double width;
  final double textScale;
  final String brandId;

  const _Viewport(
    this.name, {
    required this.width,
    required this.textScale,
    required this.brandId,
  });
}

class _Fixture {
  final captureKey = GlobalKey();
  final todos = TodoProvider();
  final habits = HabitProvider();
  final calendar = CalendarProvider();
  final pomodoro = PomodoroProvider();
  final theme = ThemeProvider();
  final user = UserProvider();
  final AuthProvider auth;
  final DateTime today;

  _Fixture(this.auth, this.today);

  static Future<_Fixture> create(
    _Viewport viewport, {
    bool signedIn = true,
    bool populated = true,
    Future<http.Response>? loginResponse,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_brand', viewport.brandId);
    await prefs.setStringList('theme_unlocked_brands', [viewport.brandId]);
    final now = DateTime.now();
    final auth = AuthProvider(
      initialState: signedIn
          ? const AuthState(
              userId: 'ui-fixture-user',
              username: 'qinghe_demo',
              displayName: '青禾 · 每天进步一点',
              email: 'qinghe@example.test',
              emailVerified: true,
              avatar: '青',
              bio: '把计划写下来，让每一步都更清楚。',
              coinBalance: 128,
              lifetimeCoins: 256,
              token: 'synthetic-ui-fixture-token',
            )
          : const AuthState(),
      client: ApiClient(
        baseUrl: 'https://duoyi.example.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/login' && loginResponse != null) {
            return loginResponse;
          }
          return http.Response(
            jsonEncode({'detail': 'Fixture endpoint unavailable'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    final fixture = _Fixture(auth, DateTime(now.year, now.month, now.day));
    addTearDown(fixture.dispose);
    await fixture.theme.loadFromStorage();
    await fixture.user.applyAccountSnapshot(
      username: signedIn ? 'qinghe_demo' : 'local_demo',
      displayName: signedIn ? '青禾 · 每天进步一点' : '我的本地计划',
      avatarInitials: signedIn ? '青' : '我',
    );
    if (!populated) return fixture;

    await fixture.todos.addTodo(
      TodoItem(
        id: 'ui-todo-plan',
        title: _todoTitle,
        date: fixture.today,
        dueDate: fixture.today.add(const Duration(hours: 18)),
        listGroupName: '工作',
        priority: TodoPriority.high,
        quadrant: EisenhowerQuadrant.urgentImportant,
      ),
    );
    await fixture.todos.addTodo(
      TodoItem(
        id: 'ui-todo-read',
        title: '读完一章书，记录三个要点',
        date: fixture.today,
        listGroupName: '学习',
        tags: ['阅读'],
        subtasks: [
          Subtask(title: '阅读'),
          Subtask(title: '整理笔记'),
        ],
      ),
    );
    await fixture.todos.addTodo(
      TodoItem(
        id: 'ui-todo-done',
        title: '准备今天的资料',
        date: fixture.today,
        isCompleted: true,
        completedAt: now,
      ),
    );
    final habit = Habit(
      id: 'ui-habit-reading',
      name: _habitTitle,
      targetCount: 2,
      icon: Icons.menu_book_outlined.codePoint.toString(),
      category: '学习',
      createdAt: fixture.today.subtract(const Duration(days: 20)),
    );
    habit.completions[habit.dateKey(fixture.today)] = 1;
    await fixture.habits.addHabit(habit);
    await fixture.calendar.addLocalEvent(
      CalendarEvent(
        id: 'ui-event-review',
        title: _eventTitle,
        date: fixture.today.add(const Duration(hours: 14)),
        endDate: fixture.today.add(const Duration(hours: 15)),
        time: const TimeOfDay(hour: 14, minute: 0),
        type: CalendarEventType.event,
        color: const Color(0xFF4169E1),
        note: '整理进度与需要协助的事项',
      ),
    );
    await fixture.pomodoro.debugAddSessionsForTest([
      PomodoroSession(
        id: 'ui-session-reading',
        startTime: fixture.today.add(const Duration(hours: 9)),
        endTime: fixture.today.add(const Duration(hours: 9, minutes: 25)),
        durationSeconds: 1500,
        type: PomodoroType.focus,
        taskName: _sessionTitle,
        tag: '学习',
      ),
    ]);
    return fixture;
  }

  void dispose() {
    todos.dispose();
    habits.dispose();
    calendar.dispose();
    pomodoro.dispose();
    theme.dispose();
    user.dispose();
    auth.dispose();
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Fixture fixture,
  _Page page,
  _Viewport viewport,
) async {
  tester.view.physicalSize = Size(viewport.width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    // Keep the original layout creator chain when takeException below turns
    // an overflow into a test failure, so the production source is traceable.
    debugPrint(details.toString());
    previousErrorHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousErrorHandler);
  // Use the same font metrics with and without PNG capture: Ahem would give
  // misleading width failures for Chinese copy at 1.6x text scale.
  await tester.runAsync(_loadReadableFonts);
  final pageKey = GlobalKey();
  final screen = switch (page) {
    _Page.login => LoginScreen(key: pageKey),
    _Page.mine => MineScreen(key: pageKey),
    _Page.profile => ProfileScreen(key: pageKey),
    _Page.todo => TodoScreen(key: pageKey),
    _Page.habit => HabitScreen(key: pageKey),
    _Page.calendar => CalendarScreen(key: pageKey, initialDate: fixture.today),
    _Page.focus => PomodoroScreen(key: pageKey),
  };
  final theme = fixture.theme.brand.theme;
  final evidenceTheme = theme.copyWith(
    textTheme: theme.textTheme.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    ),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: fixture.todos),
        ChangeNotifierProvider<HabitProvider>.value(value: fixture.habits),
        ChangeNotifierProvider<CalendarProvider>.value(value: fixture.calendar),
        ChangeNotifierProvider<PomodoroProvider>.value(value: fixture.pomodoro),
        ChangeNotifierProvider<ThemeProvider>.value(value: fixture.theme),
        ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
        ChangeNotifierProvider<UserProvider>.value(value: fixture.user),
        ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
        ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
        ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
        ChangeNotifierProvider(create: (_) => CountdownProvider()),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
        ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => AchievementProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
        ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
        ChangeNotifierProvider(
          create: (_) => AppUpdateService(
            repo: 'dq52099/duoyi',
            currentVersion: AppVersion.name,
          ),
        ),
      ],
      child: MaterialApp(
        theme: evidenceTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(viewport.textScale)),
          child: RepaintBoundary(key: fixture.captureKey, child: child!),
        ),
        home: BrandRouteSurface(child: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (Platform.environment['DUOYI_DIAGNOSE_APP_UI_FONTS'] == '1' &&
      (page == _Page.habit || page == _Page.calendar)) {
    for (final element in find.byType(RichText).evaluate()) {
      final rich = element.widget as RichText;
      final text = rich.text.toPlainText();
      if (text == '打卡' || text.contains('年')) {
        debugPrint('UI_FONT ${page.name}: $text; ${rich.text.toStringDeep()}');
      }
    }
  }
  expect(tester.takeException(), isNull);
  final context = pageKey.currentContext!;
  expect(MediaQuery.sizeOf(context), Size(viewport.width, 844));
  expect(MediaQuery.textScalerOf(context).scale(10), 10 * viewport.textScale);
  expect(
    Theme.of(context).brightness,
    viewport.brandId == 'defaultBrand' ? Brightness.light : Brightness.dark,
  );
}

Iterable<ScrollableState> _verticalScrollables(WidgetTester tester) {
  return tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where(
        (state) =>
            state.mounted &&
            axisDirectionToAxis(state.widget.axisDirection) == Axis.vertical &&
            state.position.hasContentDimensions,
      );
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; finder.evaluate().isEmpty && attempt < 16; attempt++) {
    final scrollables = _verticalScrollables(tester).toList();
    var advanced = false;
    for (final state in scrollables) {
      final position = state.position;
      if (position.pixels >= position.maxScrollExtent) continue;
      position.jumpTo(
        (position.pixels + 240).clamp(0.0, position.maxScrollExtent),
      );
      advanced = true;
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (!advanced) break;
  }
  expect(finder, findsWidgets);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _auditScrolling(
  WidgetTester tester,
  _Fixture fixture,
  String name,
) async {
  final scrollables = _verticalScrollables(tester).toList();
  var didScroll = false;
  for (final state in scrollables) {
    if (!state.mounted) continue;
    final position = state.position;
    if (position.maxScrollExtent <= 0) continue;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    for (var step = 0; step < 20; step++) {
      final target = (position.pixels + 260).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (target <= position.pixels) break;
      position.jumpTo(target);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      didScroll = true;
    }
  }
  expect(tester.takeException(), isNull);
  if (didScroll) await _capture(tester, fixture, '$name-scrolled');
}

bool get _captureEnabled =>
    Platform.environment['DUOYI_CAPTURE_APP_UI_SCREENSHOT'] == '1';

bool _fontsReady = false;

Future<void> _loadReadableFonts() async {
  if (_fontsReady) return;
  await loadWidgetPolishScreenshotFonts();
  // Some component themes keep explicit family names or inherit the test
  // font. Register both Latin and CJK faces under those same names so button
  // and calendar labels use the same metrics and glyphs as the main text.
  final cjk = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  final latinFile = File(
    Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  );
  final latin = latinFile.existsSync()
      ? ByteData.sublistView(latinFile.readAsBytesSync())
      : null;
  for (final family in [
    'Ahem',
    'Roboto',
    'monospace',
    'sans-serif',
    'DuoyiScreenshotLatin',
    'DroidSansFallbackFull',
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(cjk));
    if (latin != null) loader.addFont(Future.value(latin));
    await loader.load();
  }
  _fontsReady = true;
}

Future<void> _capture(
  WidgetTester tester,
  _Fixture fixture,
  String name,
) async {
  if (!_captureEnabled) return;
  await tester.runAsync(() async {
    final boundary =
        fixture.captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/app-ui-upgrade-20261006/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}
