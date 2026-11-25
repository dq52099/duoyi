import 'dart:async';
import 'dart:io';

// Promoted after host-reviewed complete-suite and serial timezone acceptance.
// ignore_for_file: depend_on_referenced_packages

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_feedback_visual.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    group(brand, () {
      testWidgets(
        'retained rejected language save translates Retry and preserves its target',
        (tester) async {
          final fixture = _Fixture(brand)..store.rejectNextLocaleWrite = true;
          try {
            await fixture.mount(tester);
            await tester.ensureVisible(
              find.text(NotificationUiCopy.tabLanguage),
            );
            await tester.tap(find.text(NotificationUiCopy.tabLanguage));
            await tester.pumpAndSettle();
            await tester.tap(find.text(I18n.tr('settings.language.en')));
            await tester.pumpAndSettle();
            expect(fixture.store.localeWrites, ['en']);
            await _expectRetained(
              tester,
              fixture,
              () => NotificationUiCopy.localeSaveFailed,
              caseName: 'language-save-retry',
              action: () => I18n.tr('action.retry'),
            );
            // The displayed language is now Chinese. Retry still belongs to the
            // original rejected English selection, rather than the current locale.
            await tester.tap(
              find.descendant(
                of: find.byType(SnackBar),
                matching: find.text(I18n.tr('action.retry')),
              ),
            );
            await tester.pumpAndSettle();
            expect(fixture.store.localeWrites, ['en', 'en']);
            expect(fixture.locale.locale, AppLocale.en);
            expect(
              (await fixture.store.getAll())['flutter.duoyi_locale_v1'],
              'en',
            );
            expect(find.byType(SnackBar), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.close(tester);
          }
        },
      );

      testWidgets(
        'delayed Retry rejection survives original feedback dismissal',
        (tester) async {
          final fixture = _Fixture(brand)..store.rejectNextLocaleWrite = true;
          try {
            await fixture.mount(tester);
            await tester.ensureVisible(
              find.text(NotificationUiCopy.tabLanguage),
            );
            await tester.tap(find.text(NotificationUiCopy.tabLanguage));
            await tester.pumpAndSettle();
            await tester.tap(find.text(I18n.tr('settings.language.en')));
            await tester.pumpAndSettle();
            final route = tester.element(find.byType(IntegrationsScreen));
            final gate = Completer<bool>();
            fixture.store.localeWriteGate = gate;
            await tester.tap(find.text(I18n.tr('action.retry')));
            await tester.pumpAndSettle();
            expect(find.byType(SnackBar), findsNothing);
            expect(fixture.store.localeWrites, ['en', 'en']);
            // The operation outlives the entire dismissal animation and a
            // further locale change. Its feedback must use the live route.
            I18n.setLocale(AppLocale.zh);
            await tester.pump();
            gate.complete(false);
            await tester.pumpAndSettle();
            expect(
              tester.element(find.byType(IntegrationsScreen)),
              same(route),
            );
            await _expectRetained(
              tester,
              fixture,
              () => NotificationUiCopy.localeSaveFailed,
              caseName: 'delayed-language-retry',
              action: () => I18n.tr('action.retry'),
            );
            await tester.tap(find.text(I18n.tr('action.retry')));
            await tester.pumpAndSettle();
            expect(fixture.store.localeWrites, ['en', 'en', 'en']);
            expect(
              (await fixture.store.getAll())['flutter.duoyi_locale_v1'],
              'en',
            );
            expect(find.byType(SnackBar), findsNothing);
          } finally {
            await fixture.close(tester);
          }
        },
      );

      for (final hitCount in [-1, 0, 2]) {
        testWidgets(
          'retained manual-location feedback preserves result $hitCount without repeating engine or notification',
          (tester) async {
            final fixture = _Fixture(brand)..locations.nextHitCount = hitCount;
            try {
              await fixture.mount(tester);
              await tester.ensureVisible(
                find.text(NotificationUiCopy.tabLocation),
              );
              await tester.tap(find.text(NotificationUiCopy.tabLocation));
              await tester.pumpAndSettle();
              final manualTest = find.widgetWithText(
                OutlinedButton,
                NotificationUiCopy.testCurrentLocationAction,
              );
              await tester.ensureVisible(manualTest);
              await tester.pumpAndSettle();
              expect(manualTest.hitTestable(), findsOneWidget);
              await tester.tap(manualTest);
              await tester.pumpAndSettle();
              if (hitCount >= 0) {
                await tester.enterText(
                  find.widgetWithText(
                    TextField,
                    NotificationUiCopy.latitudeLabel,
                  ),
                  '39.9',
                );
                await tester.enterText(
                  find.widgetWithText(
                    TextField,
                    NotificationUiCopy.longitudeLabel,
                  ),
                  '116.4',
                );
              }
              await tester.tap(
                find.widgetWithText(
                  FilledButton,
                  NotificationUiCopy.testButton,
                ),
              );
              await tester.pumpAndSettle();
              final expectedCalls = hitCount < 0 ? 0 : 1;
              final expectedNotifications = hitCount > 0 ? hitCount : 0;
              expect(fixture.locations.calls, expectedCalls);
              expect(
                fixture.notifications.hits,
                hasLength(expectedNotifications),
              );
              // Subsequent state is distinct from the already reported outcome.
              fixture.locations.nextHitCount = 7;
              await _expectRetained(
                tester,
                fixture,
                () => hitCount < 0
                    ? NotificationUiCopy.validCoordinatesRequired
                    : hitCount == 0
                    ? NotificationUiCopy.locationNoHits
                    : NotificationUiCopy.locationTriggeredHits(hitCount),
                caseName: 'manual-location-$hitCount',
                verify: () {
                  expect(fixture.locations.calls, expectedCalls);
                  expect(
                    fixture.notifications.hits,
                    hasLength(expectedNotifications),
                  );
                  expect(fixture.locations.literalTitle, 'Synthetic 用户标题');
                },
              );
            } finally {
              await fixture.close(tester);
            }
          },
        );
      }

      testWidgets(
        'retained missing OAuth fields translates without exchanging or persisting',
        (tester) async {
          final fixture = _Fixture(brand);
          try {
            await fixture.mount(tester);
            final add = find.widgetWithText(
              FilledButton,
              NotificationUiCopy.addAccountAction,
            );
            await tester.ensureVisible(add);
            await tester.tap(add);
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(
                FilledButton,
                NotificationUiCopy.saveAndSyncAction,
              ),
            );
            await tester.pumpAndSettle();
            await _expectRetained(
              tester,
              fixture,
              () => NotificationUiCopy.oauthFieldsRequired,
              caseName: 'oauth-required-fields',
            );
            expect(fixture.calendar.callbackLoads, 0);
            expect(fixture.store.mutations, 0);
          } finally {
            await fixture.close(tester);
          }
        },
      );

      testWidgets(
        'retained OAuth state rejection translates without rehandling callback',
        (tester) async {
          final fixture = _Fixture(brand);
          try {
            await fixture.mount(
              tester,
              callback: Uri.parse(
                'duoyi://oauth/calendar?state=synthetic-wrong&code=synthetic-code',
              ),
            );
            expect(fixture.calendar.callbackLoads, 1);
            await _expectRetained(
              tester,
              fixture,
              () => NotificationUiCopy.oauthStateMismatch,
              caseName: 'oauth-state-rejection',
              verify: () => expect(fixture.calendar.callbackLoads, 1),
            );
            expect(
              find.text(NotificationUiCopy.addOauthDialogTitle),
              findsNothing,
            );
            expect(fixture.store.mutations, 0);
          } finally {
            await fixture.close(tester);
          }
        },
      );

      for (final fails in [false, true]) {
        testWidgets(
          'retained OAuth ${fails ? 'failure' : 'success'} translates without replaying exchange',
          (tester) async {
            final fixture = _Fixture(brand);
            if (fails) {
              fixture.calendar.exchangeError = Exception(
                'synthetic network failure',
              );
            }
            try {
              await fixture.mount(tester);
              final add = find.widgetWithText(
                FilledButton,
                NotificationUiCopy.addAccountAction,
              );
              await tester.ensureVisible(add);
              await tester.tap(add);
              await tester.pumpAndSettle();
              await tester.enterText(
                find.widgetWithText(
                  TextField,
                  NotificationUiCopy.displayNameLabel,
                ),
                'Synthetic 用户日历',
              );
              await tester.enterText(
                find.widgetWithText(TextField, 'Client ID'),
                'synthetic-client',
              );
              final code = find.widgetWithText(
                TextField,
                NotificationUiCopy.authCodeLabel,
              );
              await tester.ensureVisible(code);
              await tester.enterText(code, 'synthetic-code');
              await tester.tap(
                find.widgetWithText(
                  FilledButton,
                  NotificationUiCopy.saveAndSyncAction,
                ),
              );
              await tester.pumpAndSettle();
              expect(fixture.calendar.exchanges, 1);
              expect(fixture.calendar.pendingClears, fails ? 0 : 1);
              await _expectRetained(
                tester,
                fixture,
                () => fails
                    ? NotificationUiCopy.formatOauthConnectError(
                        fixture.calendar.exchangeError,
                      )
                    : NotificationUiCopy.oauthConnected,
                caseName: 'oauth-${fails ? 'failure' : 'success'}',
                verify: () {
                  expect(fixture.calendar.exchanges, 1);
                  expect(fixture.calendar.pendingClears, fails ? 0 : 1);
                  expect(fixture.calendar.submittedName, 'Synthetic 用户日历');
                  expect(fixture.calendar.submittedCode, 'synthetic-code');
                },
              );
              expect(fixture.store.mutations, 0);
            } finally {
              await fixture.close(tester);
            }
          },
        );
      }
    });
  }
}

Future<void> _expectRetained(
  WidgetTester tester,
  _Fixture fixture,
  String Function() message, {
  required String caseName,
  String Function()? action,
  VoidCallback? verify,
}) async {
  final snack = find.byType(SnackBar);
  expect(snack, findsOneWidget);
  final retainedSnack = tester.element(snack);
  final retainedRoute = tester.element(find.byType(IntegrationsScreen));
  final mutationCount = fixture.store.mutations;
  if (action != null) expect(tester.widget<SnackBar>(snack).persist, isTrue);
  expect(
    find.descendant(of: snack, matching: find.text(message())),
    findsOneWidget,
  );
  for (final next in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
    I18n.setLocale(next);
    await tester.pump();
    expect(tester.element(snack), same(retainedSnack));
    expect(
      tester.element(find.byType(IntegrationsScreen)),
      same(retainedRoute),
    );
    expect(
      find.descendant(of: snack, matching: find.text(message())),
      findsOneWidget,
    );
    if (action != null) {
      expect(
        find.descendant(of: snack, matching: find.text(action())),
        findsOneWidget,
      );
    }
    await verifyRetainedFeedbackVisual(
      tester,
      screen: 'integrations',
      brand: fixture.brand,
      caseName: caseName,
      message: message(),
      action: action?.call(),
    );
    expect(fixture.store.mutations, mutationCount);
    verify?.call();
    expect(tester.takeException(), isNull);
  }
  if (action != null) {
    // In this SDK a SnackBar with an action is persistent by default. Moving
    // its live label into content must preserve the original action lifetime.
    final duration = tester.widget<SnackBar>(snack).duration;
    await tester.pump(duration + const Duration(seconds: 1));
    expect(tester.element(snack), same(retainedSnack));
    expect(
      find.descendant(of: snack, matching: find.text(action())),
      findsOneWidget,
    );
    expect(fixture.store.mutations, mutationCount);
  }
}

class _Fixture {
  _Fixture(this.brand);
  final String brand;
  final theme = ThemeProvider();
  final previousStore = SharedPreferencesStorePlatform.instance;
  late final store = _TrackingStore(brand);
  final locale = LocaleProvider();
  final calendar = _Calendar();
  final locations = _Locations();
  final notifications = _Notifications();

  Future<void> mount(WidgetTester tester, {Uri? callback}) async {
    if (Platform.environment['DUOYI_CAPTURE_RETAINED_FEEDBACK'] == '1') {
      await tester.runAsync(loadRetainedFeedbackFonts);
    }
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = store;
    await theme.loadFromStorage();
    expect(theme.brand.id, brand);
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendar),
          ChangeNotifierProvider<LocationReminderProvider>.value(
            value: locations,
          ),
          ChangeNotifierProvider<NotificationService>.value(
            value: notifications,
          ),
        ],
        child: MaterialApp(
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: RepaintBoundary(
              key: retainedFeedbackCaptureKey,
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => BrandRouteSurface(
                      child: IntegrationsScreen(
                        initialOAuthCallbackUri: callback,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open synthetic extensions'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open synthetic extensions'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(store.mutations, 0);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    theme.dispose();
    locale.dispose();
    calendar.dispose();
    locations.dispose();
    notifications.dispose();
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousStore;
  }
}

class _TrackingStore extends InMemorySharedPreferencesStore {
  _TrackingStore(String brand)
    : super.withData({
        'flutter.duoyi_locale_v1': 'zh',
        'flutter.active_brand': brand,
      });
  int mutations = 0;
  bool rejectNextLocaleWrite = false;
  Completer<bool>? localeWriteGate;
  final localeWrites = <String>[];
  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    mutations++;
    if (key == 'flutter.duoyi_locale_v1') {
      localeWrites.add(value.toString());
      if (rejectNextLocaleWrite) {
        rejectNextLocaleWrite = false;
        return Future.value(false);
      }
      if (localeWriteGate case final gate?) {
        localeWriteGate = null;
        return gate.future;
      }
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations++;
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations++;
    return super.clear();
  }
}

class _Calendar extends CalendarSyncProvider {
  int callbackLoads = 0;
  int exchanges = 0;
  int pendingClears = 0;
  Object? exchangeError;
  String? submittedName;
  String? submittedCode;
  @override
  Future<Map<String, String>> loadPendingOAuthAuthorization(
    {bool Function()? isCurrent}) async {
    callbackLoads++;
    return {'state': 'synthetic-expected'};
  }

  @override
  Future<void> clearPendingOAuthAuthorization(
    {String? expectedAttemptId, bool Function()? isCurrent}) async {
    pendingClears++;
  }

  @override
  Future<OAuthCalendarAccount> addOAuthAccountFromCode({
    required OAuthCalendarProvider provider,
    required String displayName,
    required String clientId,
    required String redirectUri,
    String authorizationCode = '',
    OAuthAuthorizationInput? authorizationInput,
    String? expectedState,
    String? expectedAttemptId,
    required String codeVerifier,
    String clientSecret = '',
    String calendarId = 'primary',
    int colorValue = 0xFF5E97F6,
    bool Function()? isCurrent,
  }) async {
    exchanges++;
    submittedName = displayName;
    submittedCode = authorizationCode;
    if (exchangeError != null) throw exchangeError!;
    return OAuthCalendarAccount(
      id: 'synthetic-calendar',
      provider: provider,
      displayName: displayName,
      clientId: clientId,
      redirectUri: redirectUri,
      accessToken: 'synthetic-access',
      refreshToken: 'synthetic-refresh',
      expiresAt: DateTime(2026, 10, 21),
    );
  }
}

class _Locations extends LocationReminderProvider {
  int calls = 0;
  int nextHitCount = 0;
  final literalTitle = 'Synthetic 用户标题';
  @override
  Future<List<LocationReminderHit>> ingestFix(
    LocationFix fix, {
    bool Function()? isCurrent,
  }) async {
    calls++;
    return List.generate(
      nextHitCount,
      (index) => LocationReminderHit(
        reminder: LocationReminder(
          id: 'synthetic-$index',
          title: literalTitle,
          latitude: fix.latitude,
          longitude: fix.longitude,
        ),
        triggeredBy: LocationTrigger.enter,
        fix: fix,
      ),
    );
  }
}

class _Notifications extends NotificationService {
  final hits = <LocationReminderHit>[];
  @override
  void notifyLocationReminderHit(
    LocationReminderHit hit, {
    bool showSystemNotification = true,
  }) => hits.add(hit);
}
