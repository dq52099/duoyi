// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
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
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';
import '../support/retained_dialog_text_probe.dart';

class _MineLogoutPriorityScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final String initialBrand;
  final String targetBrand;
  final Size size;
  final double scale;
  final double devicePixelRatio;

  const _MineLogoutPriorityScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.initialBrand,
    required this.targetBrand,
    required this.size,
    required this.scale,
    required this.devicePixelRatio,
  });
}

const _scenarios = <_MineLogoutPriorityScenario>[
  _MineLogoutPriorityScenario(
    name: 'zh-portrait-320x844-dpr2-defaultBrand',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _MineLogoutPriorityScenario(
    name: 'en-portrait-320x844-dpr2-liquidGlass',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(320, 844),
    scale: 2.0,
    devicePixelRatio: 2.0,
  ),
  _MineLogoutPriorityScenario(
    name: 'zh-landscape-844x390-dpr1-liquidGlass',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    initialBrand: 'liquidGlass',
    targetBrand: 'defaultBrand',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
  _MineLogoutPriorityScenario(
    name: 'en-landscape-844x390-dpr1-defaultBrand',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    initialBrand: 'defaultBrand',
    targetBrand: 'liquidGlass',
    size: Size(844, 390),
    scale: 1.0,
    devicePixelRatio: 1.0,
  ),
];

class _MineFixture {
  final ThemeProvider theme;
  final AuthProvider auth;
  final UserProvider userProvider;
  final TodoProvider todoProvider;
  final HabitProvider habitProvider;
  final PomodoroProvider pomodoroProvider;
  final CloudSyncProvider cloudSync;
  final CalendarProvider calendar;
  final PreferencesProvider preferences;
  final AppLockProvider appLock;
  final AppUpdateService updater;
  final AchievementProvider achievement;
  final ShareProvider share;
  final TimeAuditProvider timeAudit;
  final NotificationService notificationService;
  final AiService aiService;
  final LocaleProvider localeProvider;
  final LocationReminderProvider locationReminder;
  final CalendarSyncProvider calendarSync;
  final AnniversaryProvider anniversary;
  final DiaryProvider diary;
  final GoalProvider goal;
  final CourseProvider course;
  final CountdownProvider countdown;
  final NoteProvider note;
  final List<String> requests;

  _MineFixture._({
    required this.theme,
    required this.auth,
    required this.userProvider,
    required this.todoProvider,
    required this.habitProvider,
    required this.pomodoroProvider,
    required this.cloudSync,
    required this.calendar,
    required this.preferences,
    required this.appLock,
    required this.updater,
    required this.achievement,
    required this.share,
    required this.timeAudit,
    required this.notificationService,
    required this.aiService,
    required this.localeProvider,
    required this.locationReminder,
    required this.calendarSync,
    required this.anniversary,
    required this.diary,
    required this.goal,
    required this.course,
    required this.countdown,
    required this.note,
    required this.requests,
  });

  static Future<_MineFixture> create({required String initialBrand}) async {
    final requests = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'mine-logout-user',
        username: 'logout-user',
        displayName: 'Logout User',
        token: 'synthetic-logout-token',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'synthetic-logout-token',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/auth/logout') {
            return http.Response(
              jsonEncode({'status': 'ok'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        }),
      ),
    );

    final theme = ThemeProvider();
    final userProvider = UserProvider();
    final todoProvider = TodoProvider();
    final habitProvider = HabitProvider();
    final pomodoroProvider = PomodoroProvider();
    final cloudSync = CloudSyncProvider();
    final calendar = CalendarProvider();
    final preferences = PreferencesProvider();
    final appLock = AppLockProvider();
    final updater = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: AppVersion.name,
    );
    final achievement = AchievementProvider();
    final share = ShareProvider();
    final timeAudit = TimeAuditProvider();
    final notificationService = NotificationService();
    final aiService = AiService();
    final localeProvider = LocaleProvider();
    final locationReminder = LocationReminderProvider();
    final calendarSync = CalendarSyncProvider();
    final anniversary = AnniversaryProvider();
    final diary = DiaryProvider();
    final goal = GoalProvider();
    final course = CourseProvider();
    final countdown = CountdownProvider();
    final note = NoteProvider();

    await theme.loadFromStorage();
    await preferences.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();

    return _MineFixture._(
      theme: theme,
      auth: auth,
      userProvider: userProvider,
      todoProvider: todoProvider,
      habitProvider: habitProvider,
      pomodoroProvider: pomodoroProvider,
      cloudSync: cloudSync,
      calendar: calendar,
      preferences: preferences,
      appLock: appLock,
      updater: updater,
      achievement: achievement,
      share: share,
      timeAudit: timeAudit,
      notificationService: notificationService,
      aiService: aiService,
      localeProvider: localeProvider,
      locationReminder: locationReminder,
      calendarSync: calendarSync,
      anniversary: anniversary,
      diary: diary,
      goal: goal,
      course: course,
      countdown: countdown,
      note: note,
      requests: requests,
    );
  }

  void dispose() {
    theme.dispose();
    auth.dispose();
    userProvider.dispose();
    todoProvider.dispose();
    habitProvider.dispose();
    pomodoroProvider.dispose();
    cloudSync.dispose();
    calendar.dispose();
    preferences.dispose();
    appLock.dispose();
    updater.dispose();
    achievement.dispose();
    share.dispose();
    timeAudit.dispose();
    notificationService.dispose();
    aiService.dispose();
    localeProvider.dispose();
    locationReminder.dispose();
    calendarSync.dispose();
    anniversary.dispose();
    diary.dispose();
    goal.dispose();
    course.dispose();
    countdown.dispose();
    note.dispose();
  }
}

Future<void> _boundedPump(
  WidgetTester tester, {
  int maxPumps = 20,
  Duration step = const Duration(milliseconds: 30),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (!tester.binding.hasScheduledFrame) break;
  }
}

Future<void> _settleConfirmedLogout(
  WidgetTester tester,
  _MineFixture fixture, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 40));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await AccountPreferenceWrites.drain().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    });
    if (!fixture.auth.state.isLoggedIn &&
        fixture.requests.contains('POST /api/auth/logout')) {
      break;
    }
  }
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final explicitDir =
      Platform.environment['DUOYI_RETAINED_DIALOG_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;
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
      final file = File('$explicitDir/mine-logout-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final initialGlobalLocale = I18n.current;
  tearDown(() => I18n.setLocale(initialGlobalLocale));

  for (final scenario in _scenarios) {
    testWidgets('MineScreen logout live brand priority ${scenario.name}', (
      tester,
    ) async {
      final originalLocale = I18n.current;
      final originalShadows = debugDisableShadows;
      final boundaryKey = GlobalKey();
      final referenceKeyDefault = GlobalKey();
      final referenceKeyLiquidGlass = GlobalKey();

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

      _MineFixture? fixture;

      try {
        debugDisableShadows = false;
        I18n.setLocale(scenario.initialLocale);

        // All providers constructed and initialized inside tester.runAsync
        await tester.runAsync(() async {
          fixture = await _MineFixture.create(
            initialBrand: scenario.initialBrand,
          );
        });

        expect(fixture!.theme.brand.id, scenario.initialBrand);
        expect(fixture!.theme.isBrandUnlocked(scenario.targetBrand), isTrue);

        // Logical size is scenario.size; physicalSize = size * devicePixelRatio
        tester.view.physicalSize = Size(
          scenario.size.width * scenario.devicePixelRatio,
          scenario.size.height * scenario.devicePixelRatio,
        );
        tester.view.devicePixelRatio = scenario.devicePixelRatio;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(
                value: fixture!.theme,
              ),
              ChangeNotifierProvider<AuthProvider>.value(value: fixture!.auth),
              ChangeNotifierProvider<UserProvider>.value(
                value: fixture!.userProvider,
              ),
              ChangeNotifierProvider<TodoProvider>.value(
                value: fixture!.todoProvider,
              ),
              ChangeNotifierProvider<HabitProvider>.value(
                value: fixture!.habitProvider,
              ),
              ChangeNotifierProvider<PomodoroProvider>.value(
                value: fixture!.pomodoroProvider,
              ),
              ChangeNotifierProvider<CloudSyncProvider>.value(
                value: fixture!.cloudSync,
              ),
              ChangeNotifierProvider<CalendarProvider>.value(
                value: fixture!.calendar,
              ),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: fixture!.preferences,
              ),
              ChangeNotifierProvider<AppLockProvider>.value(
                value: fixture!.appLock,
              ),
              ChangeNotifierProvider<AppUpdateService>.value(
                value: fixture!.updater,
              ),
              ChangeNotifierProvider<AchievementProvider>.value(
                value: fixture!.achievement,
              ),
              ChangeNotifierProvider<ShareProvider>.value(
                value: fixture!.share,
              ),
              ChangeNotifierProvider<TimeAuditProvider>.value(
                value: fixture!.timeAudit,
              ),
              ChangeNotifierProvider<NotificationService>.value(
                value: fixture!.notificationService,
              ),
              ChangeNotifierProvider<AiService>.value(
                value: fixture!.aiService,
              ),
              ChangeNotifierProvider<LocaleProvider>.value(
                value: fixture!.localeProvider,
              ),
              ChangeNotifierProvider<LocationReminderProvider>.value(
                value: fixture!.locationReminder,
              ),
              ChangeNotifierProvider<CalendarSyncProvider>.value(
                value: fixture!.calendarSync,
              ),
              ChangeNotifierProvider<AnniversaryProvider>.value(
                value: fixture!.anniversary,
              ),
              ChangeNotifierProvider<DiaryProvider>.value(
                value: fixture!.diary,
              ),
              ChangeNotifierProvider<GoalProvider>.value(value: fixture!.goal),
              ChangeNotifierProvider<CourseProvider>.value(
                value: fixture!.course,
              ),
              ChangeNotifierProvider<CountdownProvider>.value(
                value: fixture!.countdown,
              ),
              ChangeNotifierProvider<NoteProvider>.value(value: fixture!.note),
            ],
            child: Consumer<ThemeProvider>(
              builder: (context, currentTheme, _) =>
                  ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, currentLocale, _) {
                      return MaterialApp(
                        debugShowCheckedModeBanner: false,
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
                        home: Stack(
                          children: [
                            const BrandBackground(
                              child: MineScreen(useShellBackground: true),
                            ),
                            Offstage(
                              offstage: true,
                              child: Theme(
                                data: AppBrands.defaultBrand.theme,
                                child: Builder(
                                  key: referenceKeyDefault,
                                  builder: (context) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            Offstage(
                              offstage: true,
                              child: Theme(
                                data: AppBrands.liquidGlass.theme,
                                child: Builder(
                                  key: referenceKeyLiquidGlass,
                                  builder: (context) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ),
        );

        await _boundedPump(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(MineScreen), findsOneWidget);

        // Assert actual MediaQuery size, devicePixelRatio and textScaler
        final media = MediaQuery.of(tester.element(find.byType(MineScreen)));
        expect(
          media.size.width,
          closeTo(scenario.size.width, 0.001),
          reason: 'Logical width must match scenario specification',
        );
        expect(
          media.size.height,
          closeTo(scenario.size.height, 0.001),
          reason: 'Logical height must match scenario specification',
        );
        expect(
          media.devicePixelRatio,
          closeTo(scenario.devicePixelRatio, 0.001),
          reason: 'Device pixel ratio must match scenario specification',
        );
        expect(
          media.textScaler.scale(10.0),
          closeTo(scenario.scale * 10.0, 0.001),
          reason: 'Text scaler must match scenario specification',
        );

        // 1. Open actual _confirmLogout via mine_top_logout_button
        final logoutBtnFinder = find.byKey(
          const ValueKey('mine_top_logout_button'),
        );
        expect(logoutBtnFinder, findsOneWidget);
        await tester.ensureVisible(logoutBtnFinder);
        await _boundedPump(tester, maxPumps: 4);
        await tester.tap(logoutBtnFinder);
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);

        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);
        final initialDialogElement = tester.element(dialogFinder);
        final initialDialogRoute = ModalRoute.of(initialDialogElement);
        expect(initialDialogRoute, isNotNull);

        void assertBrandStyle(String expectedBrandId, String stage) {
          final dialogElement = tester.element(find.byType(AppDialog));
          final currentTheme = Theme.of(dialogElement);
          final refContext = expectedBrandId == 'liquidGlass'
              ? referenceKeyLiquidGlass.currentContext!
              : referenceKeyDefault.currentContext!;
          final refTheme = Theme.of(refContext);
          final expectedButtonStyle = appSecondaryFilledButtonStyle(refContext);
          final expectedSurfaceStyle = appSurfaceStyleOf(refContext);

          expect(
            currentTheme.colorScheme.primary,
            equals(refTheme.colorScheme.primary),
            reason:
                '$stage: ColorScheme.primary must match independent reference $expectedBrandId',
          );

          final surfaceStyle = appSurfaceStyleOf(dialogElement);
          if (expectedBrandId == 'liquidGlass') {
            expect(
              surfaceStyle,
              equals(AppSurfaceStyle.liquidGlass),
              reason: '$stage: surfaceStyle must equal liquidGlass',
            );
            expect(surfaceStyle, equals(expectedSurfaceStyle));
          } else {
            expect(
              surfaceStyle,
              isNot(equals(AppSurfaceStyle.liquidGlass)),
              reason:
                  '$stage: surfaceStyle must not equal liquidGlass for $expectedBrandId',
            );
            expect(surfaceStyle, equals(expectedSurfaceStyle));
          }

          final confirmBtn = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, I18n.tr('auth.logout')),
          );
          expect(
            confirmBtn.style?.backgroundColor?.resolve({}),
            equals(expectedButtonStyle.backgroundColor?.resolve({})),
            reason:
                '$stage: Confirm button background color must match independent reference $expectedBrandId',
          );
          expect(
            confirmBtn.style?.foregroundColor?.resolve({}),
            equals(expectedButtonStyle.foregroundColor?.resolve({})),
            reason:
                '$stage: Confirm button foreground color must match independent reference $expectedBrandId',
          );
          expect(
            confirmBtn.style?.shape?.resolve({}),
            equals(expectedButtonStyle.shape?.resolve({})),
            reason:
                '$stage: Confirm button shape must match independent reference $expectedBrandId',
          );
        }

        Future<void> assertDialogReachabilityAndBounds(String stage) async {
          for (final key in [
            'mine.logout.confirm_title',
            'mine.logout.confirm_content',
          ]) {
            final label = I18n.tr(key);
            await verifyRetainedDialogText(
              tester,
              find.text(label),
              expected: label,
            );
          }
          for (final action in [
            find.widgetWithText(TextButton, I18n.tr('action.cancel')),
            find.widgetWithText(FilledButton, I18n.tr('auth.logout')),
          ]) {
            await tester.ensureVisible(action);
            await _boundedPump(tester, maxPumps: 4);
            expect(action.hitTestable(), findsOneWidget, reason: stage);
            expect(tester.getSize(action).height, greaterThanOrEqualTo(34));
            final text = find.descendant(
              of: action,
              matching: find.byType(Text),
            );
            await verifyRetainedDialogText(
              tester,
              text,
              expected: tester.widget<Text>(text).data!,
            );
          }
          expect(tester.takeException(), isNull, reason: stage);
        }

        assertBrandStyle(scenario.initialBrand, '1. initial brand');
        await assertDialogReachabilityAndBounds('1. initial dialog');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-01-initial-dialog',
        );

        // 2. Live brand switch to targetBrand
        await tester.runAsync(() async {
          final switched = await fixture!.theme.setBrand(scenario.targetBrand);
          expect(switched, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );
        });
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);
        expect(fixture!.theme.brand.id, scenario.targetBrand);

        expect(find.byType(AppDialog), findsOneWidget);
        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDialogElement),
          reason:
              'Dialog Element identity must be preserved across live brand switch',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDialogRoute),
          reason:
              'Dialog ModalRoute identity must be preserved across live brand switch',
        );

        assertBrandStyle(
          scenario.targetBrand,
          '2. after switch to ${scenario.targetBrand}',
        );
        await assertDialogReachabilityAndBounds('2. after targetBrand switch');
        await _capture(tester, boundaryKey, '${scenario.name}-02-target-brand');

        // 3. Live brand roundtrip back to initialBrand
        await tester.runAsync(() async {
          final reverted = await fixture!.theme.setBrand(scenario.initialBrand);
          expect(reverted, isTrue);
          await AccountPreferenceWrites.drain().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );
        });
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);
        expect(fixture!.theme.brand.id, scenario.initialBrand);

        expect(find.byType(AppDialog), findsOneWidget);
        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDialogElement),
          reason:
              'Dialog Element identity must be preserved across live brand roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDialogRoute),
          reason:
              'Dialog ModalRoute identity must be preserved across live brand roundtrip',
        );

        assertBrandStyle(
          scenario.initialBrand,
          '3. after roundtrip to ${scenario.initialBrand}',
        );
        await assertDialogReachabilityAndBounds('3. after brand roundtrip');
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-03-roundtrip-brand',
        );

        // 4. Live locale switch to alternateLocale
        I18n.setLocale(scenario.alternateLocale);
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(AppDialog), findsOneWidget);
        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDialogElement),
          reason:
              'Dialog Element identity must be preserved across live locale change',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDialogRoute),
          reason:
              'Dialog ModalRoute identity must be preserved across live locale change',
        );

        expect(
          find.text(
            I18n.trForLocale(
              'mine.logout.confirm_title',
              scenario.alternateLocale,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            I18n.trForLocale(
              'mine.logout.confirm_content',
              scenario.alternateLocale,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            TextButton,
            I18n.trForLocale('action.cancel', scenario.alternateLocale),
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            FilledButton,
            I18n.trForLocale('auth.logout', scenario.alternateLocale),
          ),
          findsOneWidget,
        );
        await assertDialogReachabilityAndBounds(
          '4. after switch to alternateLocale',
        );
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-04-alternate-locale',
        );

        // 5. Live locale roundtrip back to initialLocale
        I18n.setLocale(scenario.initialLocale);
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);

        expect(find.byType(AppDialog), findsOneWidget);
        expect(
          tester.element(find.byType(AppDialog)),
          same(initialDialogElement),
          reason:
              'Dialog Element identity must be preserved across live locale roundtrip',
        );
        expect(
          ModalRoute.of(tester.element(find.byType(AppDialog))),
          same(initialDialogRoute),
          reason:
              'Dialog ModalRoute identity must be preserved across live locale roundtrip',
        );

        expect(
          find.text(
            I18n.trForLocale(
              'mine.logout.confirm_title',
              scenario.initialLocale,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            I18n.trForLocale(
              'mine.logout.confirm_content',
              scenario.initialLocale,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            TextButton,
            I18n.trForLocale('action.cancel', scenario.initialLocale),
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            FilledButton,
            I18n.trForLocale('auth.logout', scenario.initialLocale),
          ),
          findsOneWidget,
        );
        await assertDialogReachabilityAndBounds(
          '5. after roundtrip to initialLocale',
        );
        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-05-roundtrip-locale',
        );

        // 6. Cancel through the real button and assert zero logout API calls, unchanged token/user identity and no cleanup
        final cancelAction = find.widgetWithText(
          TextButton,
          I18n.tr('action.cancel'),
        );
        expect(cancelAction, findsOneWidget);
        final generationBeforeCancel =
            AccountLocalDataCleaner.accountDataGeneration;
        final userIdBeforeCancel = fixture!.auth.state.userId;
        final tokenBeforeCancel = fixture!.auth.state.token;

        await tester.ensureVisible(cancelAction);
        await _boundedPump(tester, maxPumps: 4);
        await tester.tap(cancelAction);
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);

        // Dialog dismissed, parent MineScreen remains mounted
        expect(find.byType(AppDialog), findsNothing);
        expect(find.byType(MineScreen), findsOneWidget);

        // Assert zero logout API calls, unchanged token/user identity and no cleanup
        expect(
          fixture!.requests.where((path) => path.contains('/logout')),
          isEmpty,
          reason: 'Cancel action must make zero logout API calls',
        );
        expect(
          fixture!.auth.state.isLoggedIn,
          isTrue,
          reason: 'User must remain logged in after cancel',
        );
        expect(
          fixture!.auth.state.userId,
          equals(userIdBeforeCancel),
          reason: 'User ID must remain unchanged after cancel',
        );
        expect(
          fixture!.auth.state.token,
          equals(tokenBeforeCancel),
          reason: 'Token must remain unchanged after cancel',
        );
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          equals(generationBeforeCancel),
          reason: 'Account local data cleaner must not be triggered on cancel',
        );

        await _capture(tester, boundaryKey, '${scenario.name}-06-cancelled');

        // 7. Separately reopened current confirmation: verify exactly one call and real completion
        final logoutBtnReopen = find.byKey(
          const ValueKey('mine_top_logout_button'),
        );
        expect(logoutBtnReopen, findsOneWidget);
        await tester.ensureVisible(logoutBtnReopen);
        await _boundedPump(tester, maxPumps: 4);
        await tester.tap(logoutBtnReopen);
        await _boundedPump(tester);
        expect(tester.takeException(), isNull);

        final reopenedDialog = find.byType(AppDialog);
        expect(reopenedDialog, findsOneWidget);

        final confirmReopened = find.widgetWithText(
          FilledButton,
          I18n.tr('auth.logout'),
        );
        expect(confirmReopened, findsOneWidget);
        await tester.ensureVisible(confirmReopened);
        await _boundedPump(tester, maxPumps: 4);
        await tester.tap(confirmReopened);

        // Bounded real-async drain/pump loop until genuine authenticated state is logged out
        // and expected mock request is recorded
        await _settleConfirmedLogout(tester, fixture!);

        expect(tester.takeException(), isNull);
        expect(
          fixture!.requests.where((path) => path == 'POST /api/auth/logout'),
          hasLength(1),
          reason:
              'Separately confirmed logout must issue exactly one logout API request',
        );
        expect(
          fixture!.auth.state.isLoggedIn,
          isFalse,
          reason: 'Auth state must be logged out after confirmed logout',
        );
        expect(find.byType(AppDialog), findsNothing);
        expect(
          find.text(I18n.tr('mine.logout.done')),
          findsOneWidget,
          reason: 'Success feedback snackbar must be displayed',
        );

        await _capture(
          tester,
          boundaryKey,
          '${scenario.name}-07-logout-complete',
        );
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          for (var f = 0; f < 4; f++) {
            await tester.pump(const Duration(milliseconds: 30));
          }
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 3),
              onTimeout: () {},
            );
          });
        } catch (_) {}
        try {
          fixture?.dispose();
        } catch (_) {}
        tester.view.reset();
        debugDisableShadows = originalShadows;
        I18n.setLocale(originalLocale);
      }
    });
  }
}
