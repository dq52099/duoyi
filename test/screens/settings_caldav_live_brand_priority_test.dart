// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
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

enum _ScenarioOutcome { cancel, save }

class _BrandPriorityScenario {
  final String name;
  final AppLocale locale;
  final Size size;
  final double scale;
  final _ScenarioOutcome outcome;

  const _BrandPriorityScenario({
    required this.name,
    required this.locale,
    required this.size,
    required this.scale,
    required this.outcome,
  });
}

const _scenarios = <_BrandPriorityScenario>[
  _BrandPriorityScenario(
    name: 'zh-portrait-320x844-cancel',
    locale: AppLocale.zh,
    size: Size(320, 844),
    scale: 2.0,
    outcome: _ScenarioOutcome.cancel,
  ),
  _BrandPriorityScenario(
    name: 'zh-landscape-568x320-save',
    locale: AppLocale.zh,
    size: Size(568, 320),
    scale: 2.0,
    outcome: _ScenarioOutcome.save,
  ),
  _BrandPriorityScenario(
    name: 'en-portrait-320x844-cancel',
    locale: AppLocale.en,
    size: Size(320, 844),
    scale: 2.0,
    outcome: _ScenarioOutcome.cancel,
  ),
  _BrandPriorityScenario(
    name: 'en-landscape-568x320-save',
    locale: AppLocale.en,
    size: Size(568, 320),
    scale: 2.0,
    outcome: _ScenarioOutcome.save,
  ),
];

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int calDavWrites = 0;
  int calDavRemoves = 0;
  int themeWrites = 0;
  final List<String> recordedBusinessKeys = [];

  static bool _isThemeKey(String key) {
    final clean = key.startsWith('flutter.') ? key.substring(8) : key;
    return clean == 'active_brand' ||
        clean == 'theme_shop_state' ||
        clean == 'theme_unlocked_brands' ||
        clean == 'active_widget_background_brand';
  }

  static bool _isCalDavKey(String key) {
    final clean = key.startsWith('flutter.') ? key.substring(8) : key;
    return clean == 'duoyi_caldav_write_target_v1';
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isCalDavKey(key)) {
      calDavWrites++;
      recordedBusinessKeys.add(key);
    } else if (_isThemeKey(key)) {
      themeWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isCalDavKey(key)) {
      calDavRemoves++;
    }
    return super.remove(key);
  }
}

class _ControlledCalendarSyncProvider extends CalendarSyncProvider {
  _ControlledCalendarSyncProvider({CalDavWriteTarget? initialTarget})
    : _currentTarget = initialTarget,
      _writeZone = Zone.current;

  CalDavWriteTarget? _currentTarget;
  final Zone _writeZone;
  Future<void>? pendingSave;
  int configureCalls = 0;
  int clearCalls = 0;
  CalDavWriteTarget? lastConfiguredTarget;

  @override
  CalDavWriteTarget? get writeTarget => _currentTarget;

  @override
  Future<void> saveWriteTarget(CalDavWriteTarget target) {
    configureCalls++;
    lastConfiguredTarget = target;
    _currentTarget = target;
    final result = _writeZone.run<Future<void>>(
      () => super.saveWriteTarget(target),
    );
    pendingSave = result;
    return result;
  }

  @override
  Future<void> clearWriteTarget() async {
    clearCalls++;
    _currentTarget = null;
    return _writeZone.run(() => super.clearWriteTarget());
  }
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

Future<void> _drainPreferences(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.runAsync(() async {
    await AccountPreferenceWrites.drain().timeout(const Duration(seconds: 5));
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final explicitDir =
      Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (explicitDir == null || explicitDir.isEmpty) return;
  await tester.pump(const Duration(milliseconds: 20));
  await tester.runAsync(() async {
    final context = key.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('$explicitDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Finder _verticalScrollable() => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

Finder _fieldByLabel(String label) => find.descendant(
  of: find.byType(AppDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalLocale = I18n.current;

  for (final scenario in _scenarios) {
    testWidgets(
      'CalDAV live brand priority roundtrip defaultBrand <-> liquidGlass ${scenario.name}',
      (tester) async {
        const originalTarget = CalDavWriteTarget(
          collectionUrl: 'https://caldav.original.example/calendars/default/',
          authorizationHeader: 'Basic b3JpZ2luYWwtdXNlcjpvcmlnaW5hbC1wYXNz',
          enabled: true,
          conflictPolicy: CalDavConflictPolicy.skipRemoteChanges,
        );
        final initialTargetJson = jsonEncode(originalTarget.toJson());

        final initialPrefs = <String, Object>{
          'active_brand': 'defaultBrand',
          'theme_shop_state': jsonEncode({
            'activeBrand': 'defaultBrand',
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          'pref_app_timezone_mode': 'fixed',
          'pref_app_timezone_iana': 'Asia/Shanghai',
          'duoyi_caldav_write_target_v1': initialTargetJson,
        };

        SharedPreferences.setMockInitialValues(initialPrefs);
        final store = _RecordingPreferencesStore({
          for (final entry in initialPrefs.entries)
            if (!entry.key.startsWith('flutter.'))
              'flutter.${entry.key}': entry.value
            else
              entry.key: entry.value,
        });
        final originalStore = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = store;

        final originalShadows = debugDisableShadows;
        debugDisableShadows = false;
        I18n.setLocale(scenario.locale);

        late final _ControlledCalendarSyncProvider sync;
        final theme = ThemeProvider();
        final locale = LocaleProvider();
        final locations = LocationReminderProvider();
        final notifications = NotificationService();
        PreferencesProvider? preferences;

        try {
          await tester.runAsync(() async {
            sync = _ControlledCalendarSyncProvider(
              initialTarget: originalTarget,
            );
            preferences = PreferencesProvider();
            await theme.loadFromStorage().timeout(const Duration(seconds: 5));
            await preferences!.loadFromStorage().timeout(
              const Duration(seconds: 5),
            );
            await loadWeeklyReviewScreenshotFonts().timeout(
              const Duration(seconds: 5),
            );
          });

          expect(theme.brand.id, 'defaultBrand');
          expect(theme.isBrandUnlocked('liquidGlass'), isTrue);

          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;

          final boundaryKey = GlobalKey();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<CalendarSyncProvider>.value(value: sync),
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<LocaleProvider>.value(value: locale),
                ChangeNotifierProvider<LocationReminderProvider>.value(
                  value: locations,
                ),
                ChangeNotifierProvider<NotificationService>.value(
                  value: notifications,
                ),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences!,
                ),
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
                    child: RepaintBoundary(key: boundaryKey, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                remountOnLocaleChange: false,
                                child: IntegrationsScreen(),
                              ),
                            ),
                          ),
                          child: const Text('Open integrations'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _boundedPumpAndSettle(tester);

          // 1. Open IntegrationsScreen via real production route
          await tester.tap(find.text('Open integrations'));
          await _boundedPumpAndSettle(tester);

          expect(find.byType(IntegrationsScreen), findsOneWidget);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          expect(find.byType(BrandBackground), findsOneWidget);

          final screenElement = tester.element(find.byType(IntegrationsScreen));
          final screenModalRoute = ModalRoute.of(screenElement);
          expect(screenModalRoute, isNotNull);

          // 2. Locate and open the existing iCloud CalDAV configuration dialog
          final iCloudButton = find.widgetWithText(OutlinedButton, 'iCloud');
          await tester.scrollUntilVisible(
            iCloudButton,
            150,
            scrollable: _verticalScrollable(),
          );
          await tester.ensureVisible(iCloudButton);
          await _boundedPumpAndSettle(tester);
          await tester.tap(iCloudButton);
          await _boundedPumpAndSettle(tester);

          expect(find.byType(AppDialog), findsOneWidget);
          expect(
            find.text(NotificationUiCopy.iCloudDialogTitle),
            findsOneWidget,
          );

          final dialogElement = tester.element(find.byType(AppDialog));
          final dialogModalRoute = ModalRoute.of(dialogElement);
          expect(dialogModalRoute, isNotNull);

          final urlField = _fieldByLabel(NotificationUiCopy.iCloudUrlLabel);
          final usernameField = _fieldByLabel('Apple ID');
          final passwordField = _fieldByLabel(
            NotificationUiCopy.appSpecificPasswordLabel,
          );

          expect(urlField, findsOneWidget);
          expect(usernameField, findsOneWidget);
          expect(passwordField, findsOneWidget);

          final urlController = tester.widget<TextField>(urlField).controller!;
          final usernameController = tester
              .widget<TextField>(usernameField)
              .controller!;
          final passwordController = tester
              .widget<TextField>(passwordField)
              .controller!;

          expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

          // 3. Enter synthetic draft values and set explicit text selections
          final draftUrl =
              'https://p12-caldav.icloud.com/123456789/calendars/work-${scenario.name}/';
          final draftUsername = 'synthetic.${scenario.locale.name}@icloud.test';
          const draftPassword = 'abcd-efgh-ijkl-mnop';

          await tester.ensureVisible(urlField);
          await tester.enterText(urlField, draftUrl);
          await tester.ensureVisible(usernameField);
          await tester.enterText(usernameField, draftUsername);
          await tester.ensureVisible(passwordField);
          await tester.enterText(passwordField, draftPassword);

          urlController.selection = const TextSelection(
            baseOffset: 8,
            extentOffset: 20,
          );
          usernameController.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 9,
          );
          passwordController.selection = const TextSelection(
            baseOffset: 5,
            extentOffset: 14,
          );
          await _boundedPumpAndSettle(tester);

          FocusManager.instance.primaryFocus?.unfocus();
          await _boundedPumpAndSettle(tester);

          expect(urlController.text, draftUrl);
          expect(usernameController.text, draftUsername);
          expect(passwordController.text, draftPassword);
          expect(
            urlController.selection,
            const TextSelection(baseOffset: 8, extentOffset: 20),
          );
          expect(
            usernameController.selection,
            const TextSelection(baseOffset: 0, extentOffset: 9),
          );
          expect(
            passwordController.selection,
            const TextSelection(baseOffset: 5, extentOffset: 14),
          );
          expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

          // Pre-switch invariant: zero configure calls and zero CalDAV business writes
          expect(sync.configureCalls, 0);
          expect(sync.clearCalls, 0);
          expect(store.calDavWrites, 0);
          expect(store.calDavRemoves, 0);

          await _capture(tester, boundaryKey, '${scenario.name}-01-draft');

          // 4. Live brand switch 1: defaultBrand -> liquidGlass while SAME dialog and draft remain mounted
          await tester.runAsync(() async {
            final switched = await theme.setBrand('liquidGlass');
            expect(switched, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);

          expect(theme.brand.id, 'liquidGlass');
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('active_brand'), 'liquidGlass');

          final dialogElementStage1 = tester.element(find.byType(AppDialog));
          expect(
            Theme.of(dialogElementStage1).colorScheme.primary,
            equals(AppBrands.liquidGlass.theme.colorScheme.primary),
          );
          expect(
            appSurfaceStyleOf(dialogElementStage1),
            equals(AppSurfaceStyle.liquidGlass),
          );

          // Verify route, screen, dialog and controller identities preserved
          expect(find.byType(AppDialog), findsOneWidget);
          expect(find.byType(IntegrationsScreen), findsOneWidget);
          expect(
            ModalRoute.of(tester.element(find.byType(AppDialog))),
            same(dialogModalRoute),
          );
          expect(
            ModalRoute.of(tester.element(find.byType(IntegrationsScreen))),
            same(screenModalRoute),
          );
          expect(
            tester.element(find.byType(IntegrationsScreen)),
            same(screenElement),
          );

          expect(
            tester.widget<TextField>(urlField).controller,
            same(urlController),
          );
          expect(
            tester.widget<TextField>(usernameField).controller,
            same(usernameController),
          );
          expect(
            tester.widget<TextField>(passwordField).controller,
            same(passwordController),
          );

          // Verify draft text and selections preserved across brand switch
          expect(urlController.text, draftUrl);
          expect(usernameController.text, draftUsername);
          expect(passwordController.text, draftPassword);
          expect(
            urlController.selection,
            const TextSelection(baseOffset: 8, extentOffset: 20),
          );
          expect(
            usernameController.selection,
            const TextSelection(baseOffset: 0, extentOffset: 9),
          );
          expect(
            passwordController.selection,
            const TextSelection(baseOffset: 5, extentOffset: 14),
          );

          expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

          // Verify localized labels
          expect(
            find.text(NotificationUiCopy.iCloudDialogTitle),
            findsOneWidget,
          );
          expect(find.text(NotificationUiCopy.saveAction), findsOneWidget);
          expect(find.text(I18n.tr('action.cancel')), findsOneWidget);

          // Zero business writes across brand switch 1
          expect(sync.configureCalls, 0);
          expect(sync.clearCalls, 0);
          expect(store.calDavWrites, 0);
          expect(store.calDavRemoves, 0);
          expect(
            prefs.getString('duoyi_caldav_write_target_v1'),
            equals(initialTargetJson),
          );

          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-02-liquid-glass',
          );

          // 5. Live brand switch 2: liquidGlass -> defaultBrand (roundtrip revert)
          await tester.runAsync(() async {
            final reverted = await theme.setBrand('defaultBrand');
            expect(reverted, isTrue);
            await AccountPreferenceWrites.drain().timeout(
              const Duration(seconds: 5),
            );
          });
          await _boundedPumpAndSettle(tester);

          expect(theme.brand.id, 'defaultBrand');
          expect(prefs.getString('active_brand'), 'defaultBrand');

          final dialogElementStage2 = tester.element(find.byType(AppDialog));
          expect(
            Theme.of(dialogElementStage2).colorScheme.primary,
            equals(AppBrands.defaultBrand.theme.colorScheme.primary),
          );
          expect(
            appSurfaceStyleOf(dialogElementStage2),
            isNot(equals(AppSurfaceStyle.liquidGlass)),
          );

          // Verify route, screen, dialog and controller identities preserved across roundtrip
          expect(find.byType(AppDialog), findsOneWidget);
          expect(find.byType(IntegrationsScreen), findsOneWidget);
          expect(
            ModalRoute.of(tester.element(find.byType(AppDialog))),
            same(dialogModalRoute),
          );
          expect(
            ModalRoute.of(tester.element(find.byType(IntegrationsScreen))),
            same(screenModalRoute),
          );
          expect(
            tester.element(find.byType(IntegrationsScreen)),
            same(screenElement),
          );

          expect(
            tester.widget<TextField>(urlField).controller,
            same(urlController),
          );
          expect(
            tester.widget<TextField>(usernameField).controller,
            same(usernameController),
          );
          expect(
            tester.widget<TextField>(passwordField).controller,
            same(passwordController),
          );

          expect(urlController.text, draftUrl);
          expect(usernameController.text, draftUsername);
          expect(passwordController.text, draftPassword);
          expect(
            urlController.selection,
            const TextSelection(baseOffset: 8, extentOffset: 20),
          );
          expect(
            usernameController.selection,
            const TextSelection(baseOffset: 0, extentOffset: 9),
          );
          expect(
            passwordController.selection,
            const TextSelection(baseOffset: 5, extentOffset: 14),
          );

          expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

          expect(
            find.text(NotificationUiCopy.iCloudDialogTitle),
            findsOneWidget,
          );
          expect(find.text(NotificationUiCopy.saveAction), findsOneWidget);
          expect(find.text(I18n.tr('action.cancel')), findsOneWidget);

          // Zero business writes across roundtrip
          expect(sync.configureCalls, 0);
          expect(sync.clearCalls, 0);
          expect(store.calDavWrites, 0);
          expect(store.calDavRemoves, 0);
          expect(
            prefs.getString('duoyi_caldav_write_target_v1'),
            equals(initialTargetJson),
          );

          await _capture(
            tester,
            boundaryKey,
            '${scenario.name}-03-reverted-default',
          );

          // Keep the actual open dialog and drafts through a locale roundtrip.
          for (final nextLocale in [
            scenario.locale == AppLocale.en ? AppLocale.zh : AppLocale.en,
            scenario.locale,
          ]) {
            I18n.setLocale(nextLocale);
            await _boundedPumpAndSettle(tester);
            expect(tester.takeException(), isNull);
            expect(
              ModalRoute.of(tester.element(find.byType(AppDialog))),
              same(dialogModalRoute),
            );
            expect(
              tester.element(find.byType(IntegrationsScreen)),
              same(screenElement),
            );
            for (final field in [
              (
                urlController,
                draftUrl,
                const TextSelection(baseOffset: 8, extentOffset: 20),
                NotificationUiCopy.iCloudUrlLabel,
              ),
              (
                usernameController,
                draftUsername,
                const TextSelection(baseOffset: 0, extentOffset: 9),
                'Apple ID',
              ),
              (
                passwordController,
                draftPassword,
                const TextSelection(baseOffset: 5, extentOffset: 14),
                NotificationUiCopy.appSpecificPasswordLabel,
              ),
            ]) {
              final currentField = find.descendant(
                of: find.byType(AppDialog),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is TextField &&
                      identical(widget.controller, field.$1),
                ),
              );
              expect(currentField, findsOneWidget);
              final input = tester.widget<TextField>(currentField);
              expect(input.controller, same(field.$1));
              expect(input.decoration?.labelText, field.$4);
              expect(field.$1.text, field.$2);
              expect(field.$1.selection, field.$3);
              if (identical(field.$1, passwordController)) {
                expect(input.obscureText, isTrue);
              }
            }
            expect(
              find.text(NotificationUiCopy.iCloudDialogTitle),
              findsOneWidget,
            );
            expect(find.text(NotificationUiCopy.saveAction), findsOneWidget);
            expect(find.text(I18n.tr('action.cancel')), findsOneWidget);
            expect(sync.configureCalls, 0);
            expect(sync.clearCalls, 0);
            expect(store.calDavWrites, 0);
            expect(store.calDavRemoves, 0);
            expect(
              prefs.getString('duoyi_caldav_write_target_v1'),
              initialTargetJson,
            );
            await _capture(
              tester,
              boundaryKey,
              '${scenario.name}-03-locale-${nextLocale.name}',
            );
          }

          // 6. Explicit outcome: Cancel preserves original config vs Save commits one controlled call
          if (scenario.outcome == _ScenarioOutcome.cancel) {
            final cancelButton = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.cancel'),
              ),
            );
            expect(cancelButton.hitTestable(), findsOneWidget);
            await tester.ensureVisible(cancelButton);
            await tester.tap(cancelButton);
            await _boundedPumpAndSettle(tester);

            // Dialog dismissed, IntegrationsScreen preserved
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(IntegrationsScreen), findsOneWidget);

            // Cancel preserves original configuration without any write or sync calls
            expect(sync.configureCalls, 0);
            expect(sync.clearCalls, 0);
            expect(sync.writeTarget, equals(originalTarget));
            expect(store.calDavWrites, 0);
            expect(store.calDavRemoves, 0);
            expect(
              prefs.getString('duoyi_caldav_write_target_v1'),
              equals(initialTargetJson),
            );

            await _capture(
              tester,
              boundaryKey,
              '${scenario.name}-04-cancelled',
            );
          } else {
            final saveButton = find.descendant(
              of: find.byType(AppDialog),
              matching: find.widgetWithText(
                FilledButton,
                NotificationUiCopy.saveAction,
              ),
            );
            expect(saveButton.hitTestable(), findsOneWidget);
            await tester.ensureVisible(saveButton);
            await tester.tap(saveButton);
            expect(sync.pendingSave, isNotNull);
            await tester.runAsync(
              () => sync.pendingSave!.timeout(const Duration(seconds: 5)),
            );
            await _drainPreferences(tester);
            await _boundedPumpAndSettle(tester);

            // Dialog dismissed upon save, IntegrationsScreen preserved
            expect(find.byType(AppDialog), findsNothing);
            expect(find.byType(IntegrationsScreen), findsOneWidget);

            // Commits exactly one controlled local configure call with exact draft
            expect(sync.configureCalls, 1);
            expect(sync.clearCalls, 0);
            expect(sync.lastConfiguredTarget, isNotNull);
            expect(sync.lastConfiguredTarget!.collectionUrl, draftUrl);
            expect(
              sync.lastConfiguredTarget!.authorizationHeader,
              CalDavCredentialHelper.basicAuthorizationHeader(
                username: draftUsername,
                password: draftPassword,
              ),
            );
            expect(sync.lastConfiguredTarget!.enabled, isFalse);
            expect(
              sync.lastConfiguredTarget!.conflictPolicy,
              CalDavConflictPolicy.skipRemoteChanges,
            );

            // Business write committed to SharedPreferences
            expect(store.calDavWrites, 1);
            final savedTargetRaw = prefs.getString(
              'duoyi_caldav_write_target_v1',
            );
            expect(savedTargetRaw, isNotNull);
            final savedMap =
                jsonDecode(savedTargetRaw!) as Map<String, dynamic>;
            expect(savedMap['collectionUrl'], draftUrl);
            expect(
              savedMap['authorizationHeader'],
              CalDavCredentialHelper.basicAuthorizationHeader(
                username: draftUsername,
                password: draftPassword,
              ),
            );

            await _capture(tester, boundaryKey, '${scenario.name}-04-saved');
          }

          // Assert zero leaked exceptions, no raw private errors in UI
          expect(tester.takeException(), isNull);
          expect(find.textContaining('PRIVATE'), findsNothing);
          expect(find.textContaining('Exception'), findsNothing);
        } finally {
          try {
            await _drainPreferences(tester);
            await tester.pumpWidget(const SizedBox.shrink());
            await _boundedPumpAndSettle(tester);
          } finally {
            debugDisableShadows = originalShadows;
            I18n.setLocale(originalLocale);
            tester.view.reset();
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = originalStore;
            sync.dispose();
            theme.dispose();
            locale.dispose();
            locations.dispose();
            notifications.dispose();
            preferences?.dispose();
          }
        }
      },
    );
  }
}
