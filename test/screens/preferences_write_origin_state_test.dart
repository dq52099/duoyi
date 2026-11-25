// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/settings_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/settings_picker_tile.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _firstDayKey = 'flutter.pref_first_day_of_week';
const _pomodoroLengthKey = 'flutter.pref_default_pomodoro_minutes';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    await AccountPreferenceWrites.drain();
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'a held failure after route cover leaves the covering route feedback alone',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      fixture.store.holdNext(_firstDayKey);

      await _selectSunday(tester);
      await fixture.waitForHeldWrite(tester);
      await fixture.coverWithFeedback(tester, 'Covering route feedback');

      await fixture.releaseAndDrain(tester, saved: false);
      expect(find.text('Covering route feedback'), findsOneWidget);
      expect(find.text(SettingsUiCopy.saveFailed), findsNothing);

      // If the old route queued a snackbar behind this one, removing the
      // covering route's message exposes the stale notification.
      fixture.messengerKey.currentState!.hideCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(SettingsUiCopy.saveFailed), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a same-account held save commits after the settings route is covered',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      fixture.store.holdNext(_firstDayKey);

      await _selectSunday(tester);
      await fixture.waitForHeldWrite(tester);
      await fixture.coverWithFeedback(tester, 'Covering route');

      await fixture.releaseAndDrain(tester, saved: true);
      final persisted = await SharedPreferences.getInstance();
      expect(persisted.getInt('pref_first_day_of_week'), DateTime.sunday);
      expect(fixture.preferences.firstDayOfWeek, DateTime.sunday);
      expect(find.text('Covering route'), findsOneWidget);
      expect(find.text(SettingsUiCopy.saveFailed), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in AppLocale.values) {
    testWidgets('a current-route write failure is visible in ${locale.name}', (
      tester,
    ) async {
      final fixture = await _Fixture.create(tester, locale: locale);
      fixture.store.rejectNext(_firstDayKey);

      await _selectSunday(tester);
      await fixture.drainWrites(tester);

      expect(find.text(SettingsUiCopy.saveFailed), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'a closed picker callback cannot pop the next route or write its selection',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      final staleOptionTap = await _captureSundayOptionTap(tester);
      final firstDayTitle = find.text(I18n.tr('preferences.first_day.title'));
      final firstDayTile = find
          .ancestor(
            of: firstDayTitle,
            matching: find.byType(SettingsPickerTile<int>),
          )
          .first;
      final staleSelection = tester
          .widget<SettingsPickerTile<int>>(firstDayTile)
          .onSelected;

      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await fixture.cover(tester, 'New route after picker close');

      await staleSelection(DateTime.sunday);
      staleOptionTap();
      await tester.pumpAndSettle();

      expect(find.text('New route after picker close'), findsOneWidget);
      expect(find.byType(AppModalSheet), findsNothing);
      expect(fixture.store.writesFor(_firstDayKey), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final invalidation in [
    'account data generation',
    'auth session',
    'app lock access',
    'forced update access',
    'preferences provider identity',
  ]) {
    testWidgets('a retained picker selection rejects $invalidation', (
      tester,
    ) async {
      final fixture = await _Fixture.create(tester);
      final staleOptionTap = await _captureSundayOptionTap(tester);

      switch (invalidation) {
        case 'account data generation':
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          fixture.preferences.resetLocalState();
          await tester.pump();
          break;
        case 'auth session':
          final oldSession = fixture.auth.captureSessionLease();
          final oldGeneration = fixture.auth.sessionGeneration;
          var hydrationSettled = false;
          Object? hydrationError;
          StackTrace? hydrationStack;
          // These in-memory futures originate in the fake async zone. Drive
          // that queue before waiting, rather than crossing into runAsync.
          final hydration = fixture.auth
              .loadFromStorage(refreshServerConfig: false)
              .then<void>(
                (_) => hydrationSettled = true,
                onError: (Object error, StackTrace stack) {
                  hydrationError = error;
                  hydrationStack = stack;
                  hydrationSettled = true;
                },
              );
          for (var frame = 0; frame < 20 && !hydrationSettled; frame++) {
            await tester.pump();
          }
          expect(
            hydrationSettled,
            isTrue,
            reason: 'In-memory auth hydration must settle in the fake queue',
          );
          await hydration;
          if (hydrationError != null) {
            Error.throwWithStackTrace(hydrationError!, hydrationStack!);
          }
          expect(fixture.auth.sessionGeneration, isNot(oldGeneration));
          expect(fixture.auth.isSessionLeaseCurrent(oldSession), isFalse);
          await tester.pump();
          break;
        case 'app lock access':
          await tester.runAsync(() => fixture.lock.setPin('2468'));
          fixture.lock.lock();
          await tester.pump();
          break;
        case 'forced update access':
          fixture.updater.setMustUpdate(true);
          await tester.pump();
          break;
        case 'preferences provider identity':
          final replacement = PreferencesProvider();
          await replacement.loadFromStorage();
          await fixture.replacePreferences(tester, replacement);
          await tester.pump();
          break;
      }

      staleOptionTap();
      await tester.pumpAndSettle();
      await fixture.drainWrites(tester);

      expect(fixture.store.writesFor(_firstDayKey), isEmpty);
      expect(find.text(SettingsUiCopy.saveFailed), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a slider write failure after cover does not surface feedback', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    fixture.store.holdNext(_pomodoroLengthKey);

    final sliderFinder = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 5,
    );
    await tester.scrollUntilVisible(
      sliderFinder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    tester.widget<Slider>(sliderFinder).onChangeStart!(25);
    tester.widget<Slider>(sliderFinder).onChanged!(45);
    await tester.pump();
    tester.widget<Slider>(sliderFinder).onChangeEnd!(45);
    await fixture.waitForHeldWrite(tester);
    await fixture.coverWithFeedback(tester, 'Covering slider route feedback');

    await fixture.releaseAndDrain(tester, saved: false);
    expect(find.text('Covering slider route feedback'), findsOneWidget);
    expect(find.text(SettingsUiCopy.saveFailed), findsNothing);
    fixture.messengerKey.currentState!.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text(SettingsUiCopy.saveFailed), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final invalidation in ['account reset', 'provider replacement']) {
    testWidgets(
      'an old slider callback cannot borrow a new drag after $invalidation',
      (tester) async {
        final fixture = await _Fixture.create(tester);
        final sliderFinder = find.byWidgetPredicate(
          (widget) => widget is Slider && widget.min == 5,
        );
        await tester.scrollUntilVisible(
          sliderFinder,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        final oldSlider = tester.widget<Slider>(sliderFinder);
        oldSlider.onChangeStart!(25);
        oldSlider.onChanged!(75);
        await tester.pump();
        if (invalidation == 'account reset') {
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          fixture.preferences.resetLocalState();
        } else {
          final replacement = PreferencesProvider();
          await replacement.loadFromStorage();
          await fixture.replacePreferences(tester, replacement);
        }
        await tester.pump();
        final newSlider = tester.widget<Slider>(sliderFinder);
        newSlider.onChangeStart!(25);
        newSlider.onChanged!(45);
        await tester.pump();

        oldSlider.onChanged!(90);
        oldSlider.onChangeEnd!(75);
        await tester.pump();
        expect(fixture.store.writesFor(_pomodoroLengthKey), isEmpty);
        expect(tester.widget<Slider>(sliderFinder).value, 45);

        tester.widget<Slider>(sliderFinder).onChangeEnd!(45);
        await fixture.drainWrites(tester);
        expect(fixture.store.writesFor(_pomodoroLengthKey), hasLength(1));
        expect(fixture.preferences.defaultPomodoroMinutes, 45);
        expect(tester.widget<Slider>(sliderFinder).value, 45);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Future<void> _selectSunday(WidgetTester tester) async {
  final title = find.text(I18n.tr('preferences.first_day.title'));
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
  final sunday = find.descendant(
    of: find.byType(AppModalSheet),
    matching: find.text(I18n.tr('weekday.sun')),
  );
  await tester.ensureVisible(sunday);
  await tester.tap(sunday);
  await tester.pumpAndSettle();
}

Future<VoidCallback> _captureSundayOptionTap(WidgetTester tester) async {
  final title = find.text(I18n.tr('preferences.first_day.title'));
  await tester.ensureVisible(title);
  await tester.tap(title);
  await tester.pumpAndSettle();
  final sunday = find.descendant(
    of: find.byType(AppModalSheet),
    matching: find.text(I18n.tr('weekday.sun')),
  );
  final option = find
      .ancestor(of: sunday, matching: find.byType(InkWell))
      .first;
  return tester.widget<InkWell>(option).onTap!;
}

class _Fixture {
  _Fixture._(this.store);

  final _ControlledPreferencesStore store;
  final ThemeProvider theme = ThemeProvider();
  final AuthProvider auth = AuthProvider(
    initialState: const AuthState(userId: 'settings-user-A', token: 'token-A'),
  );
  final AppLockProvider lock = AppLockProvider();
  final _TestUpdateService updater = _TestUpdateService();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  PreferencesProvider preferences = PreferencesProvider();
  final List<PreferencesProvider> _retiredPreferences = [];
  bool _mounted = false;
  bool _disposed = false;

  static Future<_Fixture> create(
    WidgetTester tester, {
    AppLocale locale = AppLocale.zh,
  }) async {
    final previousTimezoneReader =
        LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _ControlledPreferencesStore();
    SharedPreferencesStorePlatform.instance = store;
    I18n.setLocale(locale);
    final fixture = _Fixture._(store);
    await fixture.theme.loadFromStorage();
    await fixture.preferences.loadFromStorage();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await fixture._pump(tester);
    addTearDown(() => fixture._tearDown(tester, previousTimezoneReader));
    return fixture;
  }

  Future<void> _pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AppUpdateService>.value(value: updater),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          debugShowCheckedModeBanner: false,
          theme: theme.brand.theme,
          home: const PersonalizationSettingsScreen(),
        ),
      ),
    );
    _mounted = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> replacePreferences(
    WidgetTester tester,
    PreferencesProvider next,
  ) async {
    _retiredPreferences.add(preferences);
    preferences = next;
    await _pump(tester);
  }

  Future<void> waitForHeldWrite(WidgetTester tester) async {
    await tester.runAsync(
      () => store.started.future.timeout(const Duration(seconds: 3)),
    );
    await tester.pump();
  }

  Future<void> drainWrites(WidgetTester tester) async {
    await tester.runAsync(() async {
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
  }

  Future<void> releaseAndDrain(
    WidgetTester tester, {
    required bool saved,
  }) async {
    await tester.runAsync(() async {
      store.releaseHeld(saved: saved);
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> cover(WidgetTester tester, String label) async {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Center(child: Text(label))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> coverWithFeedback(WidgetTester tester, String label) async {
    await cover(tester, 'Covered settings route');
    messengerKey.currentState!.showSnackBar(
      SnackBar(duration: const Duration(seconds: 20), content: Text(label)),
    );
    await tester.pump();
  }

  Future<void> _tearDown(
    WidgetTester tester,
    Future<String?> Function()? previousTimezoneReader,
  ) async {
    if (_disposed) return;
    _disposed = true;
    store.releaseHeld(saved: false);
    if (_mounted) {
      await tester.pump();
      await tester.runAsync(() async {
        await AccountPreferenceWrites.drain();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(AccountPreferenceWrites.drain);
    }
    LocalTimezoneResolver.debugSystemTimeZoneReader = previousTimezoneReader;
    theme.dispose();
    for (final provider in _retiredPreferences) {
      provider.dispose();
    }
    preferences.dispose();
    lock.dispose();
    auth.dispose();
    updater.dispose();
    tester.view.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  }
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore() : super.withData(<String, Object>{});

  String? _holdKey;
  Completer<void>? _started;
  Completer<bool>? _release;
  final Set<String> _rejectOnce = {};
  final List<String> _writes = [];

  Completer<void> get started => _started!;

  void holdNext(String key) {
    _holdKey = key;
    _started = Completer<void>();
    _release = Completer<bool>();
  }

  void rejectNext(String key) {
    _rejectOnce.add(key);
  }

  List<String> writesFor(String key) =>
      _writes.where((write) => write == key).toList(growable: false);

  void releaseHeld({required bool saved}) {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete(saved);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == _firstDayKey || key == _pomodoroLengthKey) {
      _writes.add(key);
    }
    if (key == _holdKey) {
      final started = _started;
      final release = _release;
      if (started != null && !started.isCompleted) {
        started.complete();
        if (!await release!.future) return false;
      }
      _holdKey = null;
      _started = null;
      _release = null;
    }
    if (_rejectOnce.remove(key)) return false;
    return super.setValue(valueType, key, value);
  }
}

class _TestUpdateService extends AppUpdateService {
  _TestUpdateService() : super(repo: 'dq52099/duoyi', currentVersion: '1.0.0');

  void setMustUpdate(bool value) {
    debugSetUpdatePolicyForTest(
      latestVersion: value ? '2.0.0' : null,
      minimumSupportedVersion: value ? '2.0.0' : null,
      forceUpdateRequired: value,
    );
    notifyListeners();
  }
}
