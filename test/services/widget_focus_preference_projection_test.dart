import 'dart:io';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/brand_strings.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_focus_projection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<String?> Function()? previousTimezoneReader;

  setUp(() {
    previousTimezoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() async {
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = previousTimezoneReader;
    await AccountPreferenceWrites.drain();
  });

  test('starts with the hydrated 45-minute default in both locales', () async {
    final fixture = await _openFixture(defaultMinutes: 45);

    expect(fixture.pomodoro.effectiveFocusDuration, 45 * 60);
    expect(fixture.pomodoro.state.totalSeconds, 45 * 60);
    expect(
      nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.zh),
      '45 分钟专注',
    );
    expect(
      nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.en),
      '45-min focus',
    );
  });

  for (final phase in _FocusPhase.values) {
    test(
      'default change alters the widget signature without resetting ${phase.name}',
      () async {
        final fixture = await _openFixture(defaultMinutes: 45);
        final pomodoro = fixture.pomodoro;
        _preparePhase(pomodoro, phase);

        final before = pomodoro.state;
        final beforeSignature = pomodoroWidgetChangeSignature(pomodoro);
        final beforeEndsAt = pomodoro.focusTimerEndsAtMillis;
        final beforeStartedAt = pomodoro.focusTimerStartedAtMillis;

        await fixture.preferences.setDefaultPomodoroMinutes(60);

        expect(pomodoro.effectiveFocusDuration, 60 * 60);
        expect(pomodoroWidgetChangeSignature(pomodoro), isNot(beforeSignature));
        expect(nextFocusWidgetLabel(pomodoro, locale: AppLocale.zh), '60 分钟专注');
        expect(
          nextFocusWidgetLabel(pomodoro, locale: AppLocale.en),
          '60-min focus',
        );
        expect(pomodoro.state.type, before.type);
        expect(pomodoro.state.isRunning, before.isRunning);
        expect(pomodoro.state.isCountUp, before.isCountUp);

        switch (phase) {
          case _FocusPhase.idle:
            expect(pomodoro.state.totalSeconds, 60 * 60);
            expect(pomodoro.state.remainingSeconds, 60 * 60);
            expect(pomodoro.focusTimerEndsAtMillis, 0);
            expect(pomodoro.focusTimerStartedAtMillis, 0);
            break;
          case _FocusPhase.running:
            expect(pomodoro.state.totalSeconds, before.totalSeconds);
            expect(pomodoro.focusTimerEndsAtMillis, beforeEndsAt);
            expect(pomodoro.focusTimerStartedAtMillis, beforeStartedAt);
            break;
          case _FocusPhase.paused:
          case _FocusPhase.breakTime:
            expect(pomodoro.state.totalSeconds, before.totalSeconds);
            expect(pomodoro.state.remainingSeconds, before.remainingSeconds);
            expect(pomodoro.focusTimerEndsAtMillis, beforeEndsAt);
            expect(pomodoro.focusTimerStartedAtMillis, beforeStartedAt);
            break;
          case _FocusPhase.countUpRunning:
            expect(pomodoro.state.totalSeconds, before.totalSeconds);
            expect(pomodoro.state.remainingSeconds, before.remainingSeconds);
            expect(pomodoro.focusTimerEndsAtMillis, beforeEndsAt);
            expect(pomodoro.focusTimerStartedAtMillis, beforeStartedAt);
            break;
        }
      },
    );
  }

  test(
    'explicit 25 minutes ignores later changes to the app default',
    () async {
      final fixture = await _openFixture(defaultMinutes: 45);
      await fixture.pomodoro.setFocusDuration(25 * 60);
      expect(fixture.pomodoro.config.focusDurationUsesDefault, isFalse);

      final signature = pomodoroWidgetChangeSignature(fixture.pomodoro);
      final zhLabel = nextFocusWidgetLabel(
        fixture.pomodoro,
        locale: AppLocale.zh,
      );
      final enLabel = nextFocusWidgetLabel(
        fixture.pomodoro,
        locale: AppLocale.en,
      );
      expect(zhLabel, '25 分钟专注');
      expect(enLabel, '25-min focus');

      await fixture.preferences.setDefaultPomodoroMinutes(60);

      expect(pomodoroWidgetChangeSignature(fixture.pomodoro), signature);
      expect(
        nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.zh),
        zhLabel,
      );
      expect(
        nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.en),
        enLabel,
      );
    },
  );

  test(
    'repeating the same preference value keeps the projection stable',
    () async {
      final fixture = await _openFixture(defaultMinutes: 45);
      final initialSignature = pomodoroWidgetChangeSignature(fixture.pomodoro);
      final initialLabel = nextFocusWidgetLabel(
        fixture.pomodoro,
        locale: AppLocale.en,
      );

      await fixture.preferences.setDefaultPomodoroMinutes(45);
      expect(pomodoroWidgetChangeSignature(fixture.pomodoro), initialSignature);
      expect(
        nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.en),
        initialLabel,
      );

      await fixture.preferences.setDefaultPomodoroMinutes(60);
      final changedSignature = pomodoroWidgetChangeSignature(fixture.pomodoro);
      final changedLabel = nextFocusWidgetLabel(
        fixture.pomodoro,
        locale: AppLocale.en,
      );
      expect(changedLabel, '60-min focus');
      expect(
        nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.zh),
        '60 分钟专注',
      );
      await fixture.preferences.setDefaultPomodoroMinutes(60);
      expect(pomodoroWidgetChangeSignature(fixture.pomodoro), changedSignature);
      expect(
        nextFocusWidgetLabel(fixture.pomodoro, locale: AppLocale.en),
        changedLabel,
      );
    },
  );

  test(
    'HomeWidgetService writes the projected locale label to its payload',
    () async {
      const channel = MethodChannel('home_widget');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final stored = <String, Object?>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map?;
        switch (call.method) {
          case 'setAppGroupId':
            return true;
          case 'getWidgetData':
            return stored[args!['id']];
          case 'saveWidgetData':
            stored[args!['id'] as String] = args['data'];
            return true;
          case 'updateWidget':
            return true;
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      HomeWidgetService.supportedForTesting = true;
      addTearDown(() => HomeWidgetService.supportedForTesting = null);
      HomeWidgetService.resetAccountCache();
      expect(await HomeWidgetService.waitForAccountClear(), isTrue);

      final fixture = await _openFixture(defaultMinutes: 45);
      final themeProvider = ThemeProvider();
      final theme = HomeWidgetThemePayload.fromThemeProvider(themeProvider);
      addTearDown(themeProvider.dispose);
      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        final label = nextFocusWidgetLabel(fixture.pomodoro, locale: locale);
        expect(
          await HomeWidgetService.push(
            todoCount: 0,
            habitPercent: 0,
            pomodoroToday: 0,
            focusMinutesToday: 0,
            strings: BrandStrings.defaultBrand,
            nextFocusLabel: label,
            theme: theme,
            force: true,
          ),
          isTrue,
        );
        expect(stored['next_focus_label'], label);
      }
    },
  );

  test('main uses both focus projection helpers', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source,
      matches(RegExp(r'pomodoroWidgetChangeSignature\(provider\)')),
    );
    expect(
      source,
      matches(RegExp(r'nextFocusWidgetLabel\(p,\s*locale:\s*I18n\.current\)')),
    );
  });
}

void _preparePhase(PomodoroProvider pomodoro, _FocusPhase phase) {
  switch (phase) {
    case _FocusPhase.idle:
      break;
    case _FocusPhase.running:
      pomodoro.startIfIdle();
      break;
    case _FocusPhase.paused:
      pomodoro.startIfIdle();
      pomodoro.toggleTimer();
      break;
    case _FocusPhase.breakTime:
      pomodoro.skipSession();
      break;
    case _FocusPhase.countUpRunning:
      pomodoro.setCountUpMode(true);
      pomodoro.startIfIdle();
      break;
  }
}

Future<_ProjectionFixture> _openFixture({required int defaultMinutes}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'pref_default_pomodoro_minutes': defaultMinutes,
  });
  final preferences = PreferencesProvider();
  await preferences.loadFromStorage();
  final pomodoro = PomodoroProvider()..attachPreferences(preferences);
  await pomodoro.loadFromStorage();
  addTearDown(() async {
    await AccountPreferenceWrites.drain();
    pomodoro.dispose();
    await pomodoro.waitForSnapshotWrites();
    preferences.dispose();
  });
  return _ProjectionFixture(preferences, pomodoro);
}

enum _FocusPhase { idle, running, paused, breakTime, countUpRunning }

class _ProjectionFixture {
  final PreferencesProvider preferences;
  final PomodoroProvider pomodoro;

  const _ProjectionFixture(this.preferences, this.pomodoro);
}
