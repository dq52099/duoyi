// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
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
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/services/webdav_backup_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int businessWrites = 0;
  int businessRemoves = 0;
  final List<String> recordedBusinessKeys = <String>[];

  static bool _isThemeKey(String key) {
    final clean = key.startsWith('flutter.')
        ? key.substring('flutter.'.length)
        : key;
    return clean == 'active_brand' ||
        clean == 'theme_switch_count' ||
        clean == 'theme_shop_state' ||
        clean == 'theme_unlocked_brands' ||
        clean.startsWith('theme_') ||
        clean.startsWith('active_');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (!_isThemeKey(key)) {
      businessWrites++;
      recordedBusinessKeys.add('$key=$value');
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (!_isThemeKey(key)) {
      businessRemoves++;
      recordedBusinessKeys.add('remove:$key');
    }
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    businessWrites++;
    recordedBusinessKeys.add('clear');
    return super.clear();
  }
}

class _LiveBrandScenario {
  final String name;
  final AppLocale initialLocale;
  final AppLocale alternateLocale;
  final Size size;
  final double scale;

  const _LiveBrandScenario({
    required this.name,
    required this.initialLocale,
    required this.alternateLocale,
    required this.size,
    required this.scale,
  });
}

const _scenarios = <_LiveBrandScenario>[
  _LiveBrandScenario(
    name: 'zh-portrait-320x844-scale200',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
  ),
  _LiveBrandScenario(
    name: 'zh-landscape-568x320-scale200',
    initialLocale: AppLocale.zh,
    alternateLocale: AppLocale.en,
    size: Size(568, 320),
    scale: 2.0,
  ),
  _LiveBrandScenario(
    name: 'en-portrait-320x844-scale200',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
  ),
  _LiveBrandScenario(
    name: 'en-landscape-568x320-scale200',
    initialLocale: AppLocale.en,
    alternateLocale: AppLocale.zh,
    size: Size(568, 320),
    scale: 2.0,
  ),
];

Future<int> _boundedPumpAndSettle(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 50),
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
  Duration timeout = const Duration(seconds: 5),
]) {
  return tester.pumpAndSettle(duration, phase, timeout);
}

Future<void> _drainAsyncWork(WidgetTester tester) async {
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

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    maxScrolls: 40,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.ensureVisible(finder);
  await _boundedPumpAndSettle(tester);
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  final enabled =
      explicitDir != null ||
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
          explicitDir ?? 'evidence/screenshots/settings-live-parallel-20261023';
      final file = File('$targetDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

bool _fontsInitialized = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Seed/mock WebDav static Future state using existing setUpAll patterns to avoid fake-zone deadlock.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await WebDavBackupService.loadConfig();
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final scenario in _scenarios) {
    testWidgets('settings backup import live brand priority ${scenario.name}', (
      tester,
    ) async {
      final initialPrefs = <String, Object>{
        'active_brand': 'defaultBrand',
        'theme_shop_state': jsonEncode({
          'activeBrand': 'defaultBrand',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }),
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.active_brand': 'defaultBrand',
        'flutter.theme_shop_state': jsonEncode({
          'activeBrand': 'defaultBrand',
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

      int clipboardWrites = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardWrites++;
            }
            return null;
          });

      final originalLocale = I18n.current;
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
          'Asia/Shanghai';

      final theme = ThemeProvider();
      final todos = TodoProvider();
      final locale = LocaleProvider();
      final auth = AuthProvider();
      final achievements = AchievementProvider();
      final preferences = PreferencesProvider();
      final notifications = NotificationService();
      final calendarSync = CalendarSyncProvider();
      final locationReminders = LocationReminderProvider();
      final habits = HabitProvider();
      final pomodoro = PomodoroProvider();
      final notes = NoteProvider();
      final anniversaries = AnniversaryProvider();
      final diary = DiaryProvider();
      final goals = GoalProvider();
      final courses = CourseProvider();
      final users = UserProvider();
      final timeAudit = TimeAuditProvider();
      final shares = ShareProvider();
      final calendar = CalendarProvider();
      final countdowns = CountdownProvider();
      final quickCaptureTemplates = QuickCaptureTemplateProvider();

      final allProviders = <ChangeNotifier>[
        theme,
        todos,
        locale,
        auth,
        achievements,
        preferences,
        notifications,
        calendarSync,
        locationReminders,
        habits,
        pomodoro,
        notes,
        anniversaries,
        diary,
        goals,
        courses,
        users,
        timeAudit,
        shares,
        calendar,
        countdowns,
        quickCaptureTemplates,
      ];

      final boundary = GlobalKey();
      bool completed = false;

      try {
        I18n.setLocale(scenario.initialLocale);

        if (!_fontsInitialized) {
          await tester.runAsync(loadWeeklyReviewScreenshotFonts);
          _fontsInitialized = true;
        }

        await theme.loadFromStorage();
        expect(theme.brand.id, 'defaultBrand');
        expect(theme.isBrandUnlocked('defaultBrand'), isTrue);
        expect(theme.isBrandUnlocked('liquidGlass'), isTrue);

        await _drainAsyncWork(tester);

        final initialPreferences = await SharedPreferences.getInstance();
        expect(initialPreferences.getString('active_brand'), 'defaultBrand');
        expect(store.businessWrites, 0);
        expect(store.businessRemoves, 0);

        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
              ChangeNotifierProvider<TodoProvider>.value(value: todos),
              ChangeNotifierProvider<LocaleProvider>.value(value: locale),
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<PreferencesProvider>.value(
                value: preferences,
              ),
              ChangeNotifierProvider<AchievementProvider>.value(
                value: achievements,
              ),
              ChangeNotifierProvider<NotificationService>.value(
                value: notifications,
              ),
              ChangeNotifierProvider<CalendarSyncProvider>.value(
                value: calendarSync,
              ),
              ChangeNotifierProvider<LocationReminderProvider>.value(
                value: locationReminders,
              ),
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
              ChangeNotifierProvider<NoteProvider>.value(value: notes),
              ChangeNotifierProvider<AnniversaryProvider>.value(
                value: anniversaries,
              ),
              ChangeNotifierProvider<DiaryProvider>.value(value: diary),
              ChangeNotifierProvider<GoalProvider>.value(value: goals),
              ChangeNotifierProvider<CourseProvider>.value(value: courses),
              ChangeNotifierProvider<UserProvider>.value(value: users),
              ChangeNotifierProvider<TimeAuditProvider>.value(value: timeAudit),
              ChangeNotifierProvider<ShareProvider>.value(value: shares),
              ChangeNotifierProvider<CalendarProvider>.value(value: calendar),
              ChangeNotifierProvider<CountdownProvider>.value(
                value: countdowns,
              ),
              ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
                value: quickCaptureTemplates,
              ),
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
                  ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: const BrandRouteSurface(
                  remountOnLocaleChange: false,
                  child: BackupScreen(initialMode: BackupEntryMode.restore),
                ),
              ),
            ),
          ),
        );
        await _boundedPumpAndSettle(tester);

        final screenFinder = find.byType(BackupScreen);
        expect(screenFinder, findsOneWidget);

        // 1. Reveal and tap Merge Import button to open dialog
        final mergeButton = find.text(DataSettingsUiCopy.mergeImportButton);
        await _reveal(tester, mergeButton);
        await tester.tap(mergeButton);
        await _boundedPumpAndSettle(tester);

        final dialogFinder = find.byType(AppDialog);
        expect(dialogFinder, findsOneWidget);
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text(DataSettingsUiCopy.importDialogTitle(true)),
          ),
          findsOneWidget,
        );

        // 2. Enter harmless synthetic JSON draft and set selection
        final input = find.descendant(
          of: dialogFinder,
          matching: find.byType(TextField),
        );
        expect(input, findsOneWidget);
        final draftJson =
            '{"app":"duoyi","schema":1,"draft":"synthetic_backup_${scenario.name}"}';
        await tester.enterText(input, draftJson);
        await _boundedPumpAndSettle(tester);

        final controller = tester.widget<TextField>(input).controller!;
        expect(controller.text, draftJson);

        const draftSelection = TextSelection(baseOffset: 2, extentOffset: 16);
        controller.selection = draftSelection;
        await tester.pump();
        expect(controller.selection, draftSelection);

        // Record identities before switch
        final initialScreenState = tester.state(screenFinder);
        final initialScreenModalRoute = ModalRoute.of(
          tester.element(screenFinder),
        );
        final initialDialogModalRoute = ModalRoute.of(
          tester.element(dialogFinder),
        );
        final initialController = tester.widget<TextField>(input).controller;

        // Check localized labels before brand switch
        if (scenario.initialLocale == AppLocale.zh) {
          expect(
            find.descendant(of: dialogFinder, matching: find.text('合并导入')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: dialogFinder, matching: find.text('取消')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: dialogFinder, matching: find.text('确认导入')),
            findsOneWidget,
          );
        } else {
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text('Merge Import'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: dialogFinder, matching: find.text('Cancel')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text('Confirm Import'),
            ),
            findsOneWidget,
          );
        }

        expect(store.businessWrites, 0);
        expect(clipboardWrites, 0);
        await _capture(tester, boundary, '${scenario.name}-01-draft-initial');

        // 3. Live brand switch: defaultBrand -> liquidGlass and live locale update
        await tester.runAsync(() async {
          final switched = await theme.setBrand('liquidGlass');
          expect(switched, isTrue);
        });
        I18n.setLocale(scenario.alternateLocale);
        await _drainAsyncWork(tester);
        await _boundedPumpAndSettle(tester);

        expect(theme.brand.id, 'liquidGlass');
        final currentPrefs = await SharedPreferences.getInstance();
        expect(currentPrefs.getString('active_brand'), 'liquidGlass');

        final dialogTheme1 = Theme.of(tester.element(dialogFinder));
        expect(
          dialogTheme1.colorScheme.primary,
          AppBrands.liquidGlass.theme.colorScheme.primary,
        );
        expect(
          appSurfaceStyleOf(tester.element(dialogFinder)),
          AppSurfaceStyle.liquidGlass,
        );

        // Check localized labels after first switch
        if (scenario.alternateLocale == AppLocale.zh) {
          expect(
            find.descendant(of: dialogFinder, matching: find.text('合并导入')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(TextButton, '取消'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(FilledButton, '确认导入'),
            ),
            findsOneWidget,
          );
        } else {
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text('Merge Import'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(TextButton, 'Cancel'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(FilledButton, 'Confirm Import'),
            ),
            findsOneWidget,
          );
        }

        // Verify state, route, controller, text, and selection retention
        expect(tester.state(screenFinder), same(initialScreenState));
        expect(
          ModalRoute.of(tester.element(screenFinder)),
          same(initialScreenModalRoute),
        );
        expect(
          ModalRoute.of(tester.element(dialogFinder)),
          same(initialDialogModalRoute),
        );
        expect(
          tester.widget<TextField>(input).controller,
          same(initialController),
        );
        expect(controller.text, draftJson);
        expect(controller.selection, draftSelection);

        expect(store.businessWrites, 0);
        expect(clipboardWrites, 0);
        await _capture(tester, boundary, '${scenario.name}-02-switched-glass');

        // 4. Live brand roundtrip: liquidGlass -> defaultBrand and revert locale
        await tester.runAsync(() async {
          final reverted = await theme.setBrand('defaultBrand');
          expect(reverted, isTrue);
        });
        I18n.setLocale(scenario.initialLocale);
        await _drainAsyncWork(tester);
        await _boundedPumpAndSettle(tester);

        expect(theme.brand.id, 'defaultBrand');
        expect(currentPrefs.getString('active_brand'), 'defaultBrand');

        final dialogTheme2 = Theme.of(tester.element(dialogFinder));
        expect(
          dialogTheme2.colorScheme.primary,
          AppBrands.defaultBrand.theme.colorScheme.primary,
        );
        expect(
          appSurfaceStyleOf(tester.element(dialogFinder)),
          isNot(equals(AppSurfaceStyle.liquidGlass)),
        );

        // Check localized labels restored to initialLocale
        if (scenario.initialLocale == AppLocale.zh) {
          expect(
            find.descendant(of: dialogFinder, matching: find.text('合并导入')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(TextButton, '取消'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(FilledButton, '确认导入'),
            ),
            findsOneWidget,
          );
        } else {
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.text('Merge Import'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(TextButton, 'Cancel'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: dialogFinder,
              matching: find.widgetWithText(FilledButton, 'Confirm Import'),
            ),
            findsOneWidget,
          );
        }

        // Verify state, route, controller, text, and selection retention after roundtrip
        expect(tester.state(screenFinder), same(initialScreenState));
        expect(
          ModalRoute.of(tester.element(screenFinder)),
          same(initialScreenModalRoute),
        );
        expect(
          ModalRoute.of(tester.element(dialogFinder)),
          same(initialDialogModalRoute),
        );
        expect(
          tester.widget<TextField>(input).controller,
          same(initialController),
        );
        expect(controller.text, draftJson);
        expect(controller.selection, draftSelection);

        expect(store.businessWrites, 0);
        expect(clipboardWrites, 0);
        await _capture(
          tester,
          boundary,
          '${scenario.name}-03-reverted-default',
        );

        // 5. Explicit Cancel: closes only dialog, parent route remains mounted
        final cancelButton = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
        );
        expect(cancelButton, findsOneWidget);
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);

        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
        }
        await _boundedPumpAndSettle(tester);

        // Dialog must be closed
        expect(find.byType(AppDialog), findsNothing);

        // Parent BackupScreen route remains mounted with its original state
        expect(find.byType(BackupScreen), findsOneWidget);
        expect(tester.state(screenFinder), same(initialScreenState));
        expect(
          ModalRoute.of(tester.element(screenFinder)),
          same(initialScreenModalRoute),
        );

        // Invariants: No import attempted and zero business mutations
        expect(
          store.businessWrites,
          0,
          reason:
              'Expected zero business data/storage writes; actual: ${store.recordedBusinessKeys}',
        );
        expect(store.businessRemoves, 0);
        expect(clipboardWrites, 0, reason: 'Expected zero clipboard writes');
        expect(todos.todos, isEmpty);
        expect(currentPrefs.getString('todos'), isNull);
        expect(currentPrefs.getString('user_profile'), isNull);
        expect(tester.takeException(), isNull);

        await _capture(
          tester,
          boundary,
          '${scenario.name}-04-dialog-closed-parent-mounted',
        );

        completed = true;
      } finally {
        try {
          await _drainAsyncWork(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await _boundedPumpAndSettle(tester);
        } finally {
          for (final provider in allProviders) {
            provider.dispose();
          }
          tester.view.reset();
          debugDisableShadows = previousShadows;
          I18n.setLocale(originalLocale);
          LocalTimezoneResolver.debugSystemTimeZoneReader = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          SharedPreferences.resetStatic();
          SharedPreferencesStorePlatform.instance = previousStore;
        }
      }

      expect(
        completed,
        isTrue,
        reason:
            'Scenario ${scenario.name} must complete without unhandled exception or skip',
      );
    });
  }
}
