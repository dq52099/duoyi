import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';
import 'package:duoyi/desktop_web/desktop_sidebar.dart';
import 'package:duoyi/desktop_web/desktop_topbar.dart';
import 'package:duoyi/desktop_web/desktop_web_nav.dart';
import 'package:duoyi/desktop_web/desktop_web_tokens.dart';
import 'package:duoyi/desktop_web/desktop_web_workspace.dart';
import 'package:duoyi/desktop_web/views/desktop_embedded_page.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
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
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StylePolishFixture {
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

  _StylePolishFixture(this.auth, this.today);

  static Future<_StylePolishFixture> create({
    String brandId = 'defaultBrand',
    AppLocale locale = AppLocale.en,
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
    final fixture = _StylePolishFixture(auth, today);
    await fixture.localeProvider.setLocale(locale);
    await fixture.theme.loadFromStorage();
    await fixture.theme.setBrand(brandId);
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

Future<void> _pumpBounded(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<String> _extractCalls(String source, String prefix) {
  final calls = <String>[];
  var index = 0;
  while (true) {
    final start = source.indexOf(prefix, index);
    if (start < 0) break;
    var depth = 0;
    var i = start + prefix.length - 1;
    for (; i < source.length; i++) {
      final ch = source[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) {
          calls.add(source.substring(start, i + 1));
          index = i + 1;
          break;
        }
      }
    }
    if (depth != 0) break;
  }
  return calls;
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

  group('Desktop shell style polish regressions', () {
    testWidgets(
      'EN guest sidebar and account overview render Local Workspace without 用户 or 我',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fixture = await _StylePolishFixture.create(locale: AppLocale.en);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          fixture.wrapWithProviders(
            Scaffold(
              body: Row(
                children: [
                  DesktopSidebar(controller: controller),
                  Expanded(
                    child: DesktopAccountOverviewView(controller: controller),
                  ),
                ],
              ),
            ),
          ),
        );
        await _pumpBounded(tester);

        expect(
          find.descendant(
            of: find.byType(DesktopSidebar),
            matching: find.text('Local Workspace'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(DesktopSidebar),
            matching: find.text('L'),
          ),
          findsOneWidget,
        );
        expect(find.text('用户'), findsNothing);
        expect(find.text('我'), findsNothing);

        expect(
          find.descendant(
            of: find.byType(DesktopAccountOverviewView),
            matching: find.text('Local Workspace'),
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Topbar renders non-duplicated breadcrumb and expands subtitle without premature truncation',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fixture = await _StylePolishFixture.create(locale: AppLocale.en);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.notes,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          fixture.wrapWithProviders(
            DesktopWebWorkspace(controller: controller),
          ),
        );
        await _pumpBounded(tester);

        final topbar = find.byType(DesktopTopBar);
        expect(topbar, findsOneWidget);
        expect(
          find.descendant(
            of: topbar,
            matching: find.text('Insights & Records'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: topbar, matching: find.text('Notes')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: topbar,
            matching: find.textContaining('Insights & Records / Notes'),
          ),
          findsNothing,
        );

        const expectedSubtitle = 'Quick notes & organized library';
        final subtitleFinder = find.descendant(
          of: topbar,
          matching: find.text(expectedSubtitle),
        );
        expect(subtitleFinder, findsOneWidget);
        final subtitleParagraph = tester.renderObject<RenderParagraph>(
          subtitleFinder,
        );
        expect(subtitleParagraph.didExceedMaxLines, isFalse);

        // Verify a standalone DesktopTopBar with a long date subtitle does not truncate prematurely.
        final standaloneCtrl = DesktopWebNavController(
          initialDestination: DesktopWebDestination.almanac,
        )..setTopBarSpec(
            DesktopWebDestination.almanac,
            const DesktopTopBarSpec(
              title: 'Almanac',
              breadcrumb: 'Insights & Records',
              subtitle: 'Nov 24, 2026 · Month 10, Day 15',
            ),
          );
        addTearDown(standaloneCtrl.dispose);

        await tester.pumpWidget(
          fixture.wrapWithProviders(
            Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 1032,
                  child: DesktopTopBar(controller: standaloneCtrl),
                ),
              ),
            ),
          ),
        );
        await _pumpBounded(tester);

        final longSubtitleFinder = find.text('Nov 24, 2026 · Month 10, Day 15');
        expect(longSubtitleFinder, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(longSubtitleFinder).didExceedMaxLines,
          isFalse,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'DesktopEmbeddedHostScope.isHosted returns true inside DesktopEmbeddedPage and false outside',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        late bool hostedOutside;
        late bool hostedInsideScope;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (outsideCtx) {
                hostedOutside = DesktopEmbeddedHostScope.isHosted(outsideCtx);
                return DesktopEmbeddedHostScope(
                  child: Builder(
                    builder: (insideCtx) {
                      hostedInsideScope = DesktopEmbeddedHostScope.isHosted(
                        insideCtx,
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        );
        expect(hostedOutside, isFalse);
        expect(hostedInsideScope, isTrue);

        final fixture = await _StylePolishFixture.create(locale: AppLocale.en);
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.notes,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          fixture.wrapWithProviders(
            DesktopWebScope(
              controller: controller,
              child: Scaffold(
                body: DesktopEmbeddedPage(
                  destination: DesktopWebDestination.notes,
                  controller: controller,
                ),
              ),
            ),
          ),
        );
        await _pumpBounded(tester);

        final noteElement = tester.element(find.byType(NoteScreen));
        expect(DesktopEmbeddedHostScope.isHosted(noteElement), isTrue);
        expect(
          find.descendant(
            of: find.byType(DesktopEmbeddedPage),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'DesktopWebTokens.metricValueStyle carries FontFeature.tabularFigures and 2-layer shadows',
      (tester) async {
        late DesktopWebTokens tokens;
        final theme = DesktopWebTokens.buildWorkspaceTheme(
          brand: AppBrands.defaultBrand,
          darkOverride: false,
          frostedOverride: false,
        );
        await tester.pumpWidget(
          Theme(
            data: theme,
            child: Builder(
              builder: (context) {
                tokens = DesktopWebTokens.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          tokens.metricValueStyle.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(tokens.canvasBackground, const Color(0xFFF6F7F9));
        expect(tokens.cardShadow, hasLength(2));
      },
    );

    testWidgets(
      'frostedOverride: false respects non-glass even when activeBrand is liquidGlass',
      (tester) async {
        final fixture = await _StylePolishFixture.create(
          brandId: AppBrands.liquidGlass.id,
          locale: AppLocale.en,
        );
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
          frostedOverride: false,
        );
        addTearDown(controller.dispose);

        late DesktopWebTokens tokensWithScope;
        final themeWithOverrideOff = DesktopWebTokens.buildWorkspaceTheme(
          brand: AppBrands.liquidGlass,
          frostedOverride: false,
        );

        await tester.pumpWidget(
          fixture.wrapWithProviders(
            Theme(
              data: themeWithOverrideOff,
              child: DesktopWebScope(
                controller: controller,
                child: Builder(
                  builder: (context) {
                    tokensWithScope = DesktopWebTokens.of(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        expect(tokensWithScope.isLiquidGlass, isFalse);

        late DesktopWebTokens tokensWithoutScope;
        await tester.pumpWidget(
          fixture.wrapWithProviders(
            Theme(
              data: themeWithOverrideOff,
              child: Builder(
                builder: (context) {
                  tokensWithoutScope = DesktopWebTokens.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(tokensWithoutScope.isLiquidGlass, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Command Palette renders grouped sections with command_item_ keys intact and focusable cards/tiles',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fixture = await _StylePolishFixture.create(locale: AppLocale.en);
        await fixture.todos.addTodo(
          TodoItem(
            id: 'polish-todo-1',
            title: 'Quarterly polish audit',
            date: fixture.today,
          ),
        );
        final controller = DesktopWebNavController(
          initialDestination: DesktopWebDestination.today,
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          fixture.wrapWithProviders(
            DesktopWebWorkspace(controller: controller),
          ),
        );
        await _pumpBounded(tester);

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('desktop_nav_today')),
            matching: find.byType(FocusableActionDetector),
          ),
          findsOneWidget,
        );

        controller.openCommandPalette();
        await _pumpBounded(tester);

        final paletteModal = find.byKey(
          const ValueKey('desktop_command_palette_modal'),
        );
        expect(paletteModal, findsOneWidget);
        final paletteList = find.descendant(
          of: paletteModal,
          matching: find.byType(ListView),
        );
        final paletteScroll = find.descendant(
          of: paletteList,
          matching: find.byType(Scrollable),
        );
        expect(
          find.descendant(
            of: paletteList,
            matching: find.text('Quick Create'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: paletteModal,
            matching: find.byKey(const ValueKey('command_item_create-todo')),
          ),
          findsOneWidget,
        );

        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('command_item_nav-today')),
          120,
          scrollable: paletteScroll,
        );
        expect(
          find.descendant(
            of: paletteList,
            matching: find.text('Navigate'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: paletteModal,
            matching: find.byKey(const ValueKey('command_item_nav-today')),
          ),
          findsOneWidget,
        );

        final input = find.byKey(
          const ValueKey('desktop_command_palette_input'),
        );
        await tester.enterText(input, 'Quarterly');
        await tester.pump(const Duration(milliseconds: 160));
        await _pumpBounded(tester);

        expect(
          find.descendant(
            of: paletteList,
            matching: find.text('Instant Create'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: paletteList,
            matching: find.text('Search Results'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('command_item_instant-todo')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('command_item_search-todo-polish-todo-1')),
          findsOneWidget,
        );

        await tester.enterText(input, 'converter');
        await tester.pump(const Duration(milliseconds: 160));
        await _pumpBounded(tester);
        expect(
          find.descendant(
            of: paletteList,
            matching: find.text('Almanac Tools'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('command_item_cmd-almanac-tools')),
          findsOneWidget,
        );

        await tester.enterText(input, 'dark');
        await tester.pump(const Duration(milliseconds: 160));
        await _pumpBounded(tester);
        expect(
          find.descendant(
            of: paletteList,
            matching: find.text('Appearance'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('command_item_cmd-toggle-dark')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    test(
      'Desktop shell files obey zero bold weight, <= 0.6 borders, and zero Opacity saveLayers in workspace',
      () {
        final ownedFiles = <String>[
          'lib/desktop_web/desktop_embedded_scope.dart',
          'lib/desktop_web/desktop_web_tokens.dart',
          'lib/desktop_web/desktop_web_workspace.dart',
          'lib/desktop_web/desktop_sidebar.dart',
          'lib/desktop_web/desktop_topbar.dart',
          'lib/desktop_web/desktop_command_palette.dart',
          'lib/desktop_web/views/desktop_embedded_page.dart',
        ];
        final bannedWeight = RegExp(
          r'FontWeight\.(bold|w[5-9]00)|DesignTokens\.fontWeightMedium',
        );
        final widthRegex = RegExp(r'width:\s*([0-9]+(?:\.[0-9]+)?)');

        for (final path in ownedFiles) {
          final source = File(path).readAsStringSync();
          expect(
            bannedWeight.hasMatch(source),
            isFalse,
            reason: '$path must not use banned bold weights',
          );
          for (final call in [
            ..._extractCalls(source, 'Border.all('),
            ..._extractCalls(source, 'BorderSide('),
          ]) {
            final match = widthRegex.firstMatch(call);
            if (match != null) {
              expect(
                double.parse(match.group(1)!),
                lessThanOrEqualTo(0.6),
                reason: '$path border width must stay <= 0.6 in:\n$call',
              );
            }
          }
        }

        final workspaceSrc = File(
          'lib/desktop_web/desktop_web_workspace.dart',
        ).readAsStringSync();
        expect(RegExp(r'\bOpacity\s*\(').hasMatch(workspaceSrc), isFalse);
      },
    );
  });
}
