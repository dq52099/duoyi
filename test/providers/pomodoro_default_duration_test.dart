import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<String?> Function()? timezoneReader;

  setUp(() {
    timezoneReader = LocalTimezoneResolver.debugSystemTimeZoneReader;
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await AccountPreferenceWrites.drain();
    LocalTimezoneResolver.debugSystemTimeZoneReader = timezoneReader;
  });

  test(
    'fresh config follows a hydrated preference without writing config',
    () async {
      final f = await _fixture(minutes: 45);
      expect(f.timer.config.focusDurationUsesDefault, isTrue);
      expect(f.timer.effectiveFocusDuration, 2700);
      expect(f.timer.state.totalSeconds, 2700);
      final revision = f.timer.persistedRevision;
      await f.preferences.setDefaultPomodoroMinutes(30);
      expect(f.timer.state.totalSeconds, 1800);
      expect(f.timer.state.remainingSeconds, 1800);
      expect(f.timer.persistedRevision, revision);
      expect(f.store.configPayloads, isEmpty);
    },
  );

  for (final duration in [1500, 2700]) {
    test('legacy explicit $duration ignores preference changes', () async {
      final f = await _fixture(
        minutes: 45,
        config: {'focusDuration': duration},
      );
      expect(f.timer.config.focusDurationUsesDefault, isFalse);
      expect(f.timer.state.totalSeconds, duration);
      await f.preferences.setDefaultPomodoroMinutes(60);
      expect(f.timer.state.totalSeconds, duration);
      expect(f.timer.effectiveFocusDuration, duration);
      expect(f.store.configPayloads, isEmpty);
    });
  }

  test(
    'saving unrelated sound options retains inherited duration mode',
    () async {
      final f = await _fixture(minutes: 45);
      await f.timer.setFocusSoundVolume(0.8, preview: false);
      expect(f.timer.config.focusDurationUsesDefault, isTrue);
      expect(f.store.configPayloads.single['focusDurationUsesDefault'], isTrue);
      await f.preferences.setDefaultPomodoroMinutes(35);
      expect(f.timer.state.totalSeconds, 2100);
      expect(f.store.configPayloads, hasLength(1));
    },
  );

  for (final roundTrip in _heldConfigRoundTrips) {
    test(
      'held ${roundTrip.name} config change keeps the final intent',
      () async {
        final f = await _fixture(minutes: 45);
        final revision = f.timer.persistedRevision;
        f.store.holdNextConfig = true;

        final firstWrite = roundTrip.first(f.timer);
        await f.store.configStarted.future;
        final finalWrite = roundTrip.last(f.timer);
        f.store.configRelease.complete();
        await Future.wait([firstWrite, finalWrite]);

        expect(f.store.configPayloads, hasLength(2));
        roundTrip.expectFinal(f.timer, f.store.configPayloads.last);
        expect(f.timer.persistedRevision, revision + 2);
      },
    );
  }

  test('unchanged config setters do not persist or notify', () async {
    final f = await _fixture(minutes: 45);
    var notifications = 0;
    f.timer.addListener(() => notifications++);
    final revision = f.timer.persistedRevision;
    final config = f.timer.config;

    final noOps = <Future<void> Function()>[
      () => f.timer.setAutoEnableDnd(config.autoEnableDnd),
      () => f.timer.setStrictFocusMode(config.strictFocusMode),
      () => f.timer.setMonitorDistractingApps(config.monitorDistractingApps),
      () => f.timer.setFocusRoomId(config.focusRoomId),
      () => f.timer.setDistractingAppPackages(
        List<String>.of(config.distractingAppPackages),
      ),
      () async {
        await f.timer.setWhiteNoiseSound(
          config.whiteNoiseSound,
          preview: false,
        );
      },
      () async {
        await f.timer.setFocusSoundVolume(
          config.focusSoundVolume,
          preview: false,
        );
      },
    ];

    for (final noOp in noOps) {
      await noOp();
    }

    expect(f.store.configPayloads, isEmpty);
    expect(f.timer.persistedRevision, revision);
    expect(notifications, 0);
  });

  test('explicit selection and return to defaults are durable', () async {
    final f = await _fixture(minutes: 45);
    await f.timer.setFocusDuration(1500);
    expect(f.timer.config.focusDurationUsesDefault, isFalse);
    await f.preferences.setDefaultPomodoroMinutes(30);
    expect(f.timer.state.totalSeconds, 1500);
    await f.timer.useDefaultFocusDuration();
    expect(f.timer.config.focusDurationUsesDefault, isTrue);
    expect(f.timer.state.totalSeconds, 1800);
    expect(f.store.configPayloads.last['focusDurationUsesDefault'], isTrue);
    await f.timer.loadFromStorage();
    expect(f.timer.effectiveFocusDuration, 1800);
  });

  for (final paused in [false, true]) {
    test(
      'default changes preserve a ${paused ? 'paused' : 'running'} phase',
      () async {
        final f = await _fixture(minutes: 45);
        f.timer.startIfIdle();
        await f.timer.waitForSnapshotWrites();
        if (paused) {
          f.timer.toggleTimer();
          await f.timer.waitForSnapshotWrites();
        }
        final state = f.timer.state;
        final anchor = f.timer.focusTimerEndsAtMillis;
        await f.preferences.setDefaultPomodoroMinutes(60);
        expect(f.timer.state.totalSeconds, state.totalSeconds);
        expect(f.timer.state.remainingSeconds, state.remainingSeconds);
        expect(f.timer.state.isRunning, state.isRunning);
        expect(f.timer.focusTimerEndsAtMillis, anchor);
        expect(f.timer.effectiveFocusDuration, 3600);
        f.timer.resetTimer();
        expect(f.timer.state.totalSeconds, 3600);
      },
    );
  }

  test('break and count-up phases survive a default change', () async {
    final f = await _fixture(minutes: 45);
    f.timer.skipSession();
    final breakState = f.timer.state;
    await f.preferences.setDefaultPomodoroMinutes(30);
    expect(f.timer.state.type, PomodoroType.shortBreak);
    expect(f.timer.state.totalSeconds, breakState.totalSeconds);
    f.timer.skipSession();
    expect(f.timer.state.totalSeconds, 1800);
    f.timer.setCountUpMode(true);
    final countUpState = f.timer.state;
    await f.preferences.setDefaultPomodoroMinutes(60);
    expect(f.timer.state.isCountUp, isTrue);
    expect(f.timer.state.totalSeconds, countUpState.totalSeconds);
    expect(f.timer.state.remainingSeconds, countUpState.remainingSeconds);
  });

  test(
    'authoritative inherited config reload updates only an untouched draft',
    () async {
      final f = await _fixture(minutes: 45, config: {'focusDuration': 1500});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pomodoro_config',
        jsonEncode({'focusDuration': 1500, 'focusDurationUsesDefault': true}),
      );
      await f.timer.loadFromStorage();
      expect(f.timer.state.totalSeconds, 2700);
      f.timer.startIfIdle();
      f.timer.toggleTimer();
      final state = f.timer.state;
      await f.preferences.setDefaultPomodoroMinutes(60);
      await f.timer.loadFromStorage();
      expect(f.timer.state.totalSeconds, state.totalSeconds);
      expect(f.timer.state.remainingSeconds, state.remainingSeconds);
    },
  );

  test(
    'reset never reapplies an old account default before source hydration',
    () async {
      final f = await _fixture(minutes: 45);
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      f.timer.resetLocalState();
      expect(f.timer.state.totalSeconds, 1500);
      await f.preferences.setDefaultPomodoroMinutes(60);
      expect(f.timer.state.totalSeconds, 1500);
      f.preferences.resetLocalState();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pref_default_pomodoro_minutes', 30);
      await f.preferences.loadFromStorage();
      expect(f.timer.state.totalSeconds, 1800);
    },
  );

  for (final paused in [false, true]) {
    final phase = paused ? 'paused' : 'running';

    test(
      'Preferences reset invalidates its default during a $phase phase',
      () async {
        final f = await _fixture(minutes: 45);
        await _expectInvalidatedDefaultPreservesPhase(
          f,
          paused: paused,
          invalidate: () async => f.preferences.resetLocalState(),
        );
      },
    );

    test(
      'attaching an unhydrated Preferences source resets the default during a $phase phase',
      () async {
        final f = await _fixture(minutes: 45);
        final replacement = PreferencesProvider();
        addTearDown(replacement.dispose);
        await _expectInvalidatedDefaultPreservesPhase(
          f,
          paused: paused,
          invalidate: () async => f.timer.attachPreferences(replacement),
        );
      },
    );

    test(
      'account generation invalidates its default during a $phase phase',
      () async {
        final f = await _fixture(minutes: 45);
        await _expectInvalidatedDefaultPreservesPhase(
          f,
          paused: paused,
          invalidate: () async =>
              AccountLocalDataCleaner.invalidateInFlightAccountWrites(),
        );
      },
    );
  }

  test(
    'a rejected duration save retains the committed config and timer',
    () async {
      final f = await _fixture(minutes: 45);
      f.store.rejectNextConfig = true;
      await expectLater(f.timer.setFocusDuration(1500), throwsStateError);
      expect(f.timer.config.focusDurationUsesDefault, isTrue);
      expect(f.timer.state.totalSeconds, 2700);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pomodoro_config'), isNull);
    },
  );

  test(
    'timer started during a held config save keeps its active anchor',
    () async {
      final f = await _fixture(minutes: 45);
      f.store.holdNextConfig = true;
      final saving = f.timer.setFocusDuration(1500);
      await f.store.configStarted.future;
      f.timer.startIfIdle();
      final anchor = f.timer.focusTimerEndsAtMillis;
      f.store.configRelease.complete();
      await saving;
      expect(f.timer.state.totalSeconds, 2700);
      expect(f.timer.focusTimerEndsAtMillis, anchor);
      expect(f.timer.effectiveFocusDuration, 1500);
    },
  );

  test(
    'cleanup drains a held config save without publishing it to the next account',
    () async {
      final f = await _fixture(minutes: 45);
      f.store.holdNextConfig = true;
      final saving = f.timer.setFocusDuration(1500);
      await f.store.configStarted.future;
      final cleanup = AccountPreferenceWrites.boundary(() async {
        f.timer.resetLocalState();
        await AccountLocalDataCleaner.clearSharedPreferences();
      });
      f.store.configRelease.complete();
      await saving;
      await cleanup;
      expect(f.timer.state.totalSeconds, 1500);
      expect(f.timer.config.focusDurationUsesDefault, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pomodoro_config'), isNull);
    },
  );
}

Future<_Fixture> _fixture({
  required int minutes,
  Map<String, dynamic>? config,
}) async {
  final store = _ConfigStore({
    'flutter.pref_default_pomodoro_minutes': minutes,
    if (config != null) 'flutter.pomodoro_config': jsonEncode(config),
  });
  SharedPreferencesStorePlatform.instance = store;
  final preferences = PreferencesProvider();
  await preferences.loadFromStorage();
  final timer = PomodoroProvider()..attachPreferences(preferences);
  await timer.loadFromStorage();
  addTearDown(() async {
    if (!store.configRelease.isCompleted) store.configRelease.complete();
    await AccountPreferenceWrites.drain();
    timer.dispose();
    await timer.waitForSnapshotWrites();
    preferences.dispose();
  });
  return _Fixture(timer, preferences, store);
}

class _Fixture {
  final PomodoroProvider timer;
  final PreferencesProvider preferences;
  final _ConfigStore store;
  _Fixture(this.timer, this.preferences, this.store);
}

class _ConfigStore extends InMemorySharedPreferencesStore {
  _ConfigStore(super.data) : super.withData();
  final List<Map<String, dynamic>> configPayloads = [];
  bool rejectNextConfig = false;
  bool holdNextConfig = false;
  final configStarted = Completer<void>();
  final configRelease = Completer<void>();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.pomodoro_config') {
      configPayloads.add(
        Map<String, dynamic>.from(jsonDecode(value as String)),
      );
      if (holdNextConfig) {
        holdNextConfig = false;
        configStarted.complete();
        await configRelease.future;
      }
      final result = await super.setValue(type, key, value);
      if (rejectNextConfig) {
        rejectNextConfig = false;
        return false;
      }
      return result;
    }
    return super.setValue(type, key, value);
  }
}

typedef _ConfigSetter = Future<void> Function(PomodoroProvider timer);

class _HeldConfigRoundTrip {
  final String name;
  final _ConfigSetter first;
  final _ConfigSetter last;
  final void Function(PomodoroProvider timer, Map<String, dynamic> payload)
  expectFinal;

  const _HeldConfigRoundTrip({
    required this.name,
    required this.first,
    required this.last,
    required this.expectFinal,
  });
}

final _heldConfigRoundTrips = <_HeldConfigRoundTrip>[
  _HeldConfigRoundTrip(
    name: 'DND',
    first: (timer) => timer.setAutoEnableDnd(true),
    last: (timer) => timer.setAutoEnableDnd(false),
    expectFinal: (timer, payload) {
      expect(timer.config.autoEnableDnd, isFalse);
      expect(payload['autoEnableDnd'], isFalse);
    },
  ),
  _HeldConfigRoundTrip(
    name: 'strict mode',
    first: (timer) => timer.setStrictFocusMode(true),
    last: (timer) => timer.setStrictFocusMode(false),
    expectFinal: (timer, payload) {
      expect(timer.config.strictFocusMode, isFalse);
      expect(payload['strictFocusMode'], isFalse);
    },
  ),
  _HeldConfigRoundTrip(
    name: 'monitor',
    first: (timer) => timer.setMonitorDistractingApps(true),
    last: (timer) => timer.setMonitorDistractingApps(false),
    expectFinal: (timer, payload) {
      expect(timer.config.monitorDistractingApps, isFalse);
      expect(payload['monitorDistractingApps'], isFalse);
    },
  ),
  _HeldConfigRoundTrip(
    name: 'room',
    first: (timer) => timer.setFocusRoomId('deep_work_room'),
    last: (timer) => timer.setFocusRoomId(null),
    expectFinal: (timer, payload) {
      expect(timer.config.focusRoomId, isNull);
      expect(payload['focusRoomId'], isNull);
    },
  ),
  _HeldConfigRoundTrip(
    name: 'packages',
    first: (timer) => timer.setDistractingAppPackages([
      'com.example.mail',
      'com.example.video',
    ]),
    last: (timer) => timer.setDistractingAppPackages(const []),
    expectFinal: (timer, payload) {
      expect(timer.config.distractingAppPackages, isEmpty);
      expect(payload['distractingAppPackages'], isEmpty);
    },
  ),
  _HeldConfigRoundTrip(
    name: 'sound',
    first: (timer) async {
      await timer.setWhiteNoiseSound('rain', preview: false);
    },
    last: (timer) async {
      await timer.setWhiteNoiseSound('none', preview: false);
    },
    expectFinal: (timer, payload) {
      expect(timer.config.whiteNoiseSound, 'none');
      expect(payload['whiteNoiseSound'], 'none');
    },
  ),
  _HeldConfigRoundTrip(
    name: 'volume',
    first: (timer) async {
      await timer.setFocusSoundVolume(0.8, preview: false);
    },
    last: (timer) async {
      await timer.setFocusSoundVolume(0.6, preview: false);
    },
    expectFinal: (timer, payload) {
      expect(timer.config.focusSoundVolume, 0.6);
      expect(payload['focusSoundVolume'], 0.6);
    },
  ),
];

Future<void> _expectInvalidatedDefaultPreservesPhase(
  _Fixture f, {
  required bool paused,
  required Future<void> Function() invalidate,
}) async {
  expect(f.timer.defaultFocusMinutes, 45);
  f.timer.startIfIdle();
  await f.timer.waitForSnapshotWrites();
  if (paused) {
    f.timer.toggleTimer();
    await f.timer.waitForSnapshotWrites();
  }

  final before = f.timer.state;
  final anchor = f.timer.focusTimerEndsAtMillis;
  await invalidate();

  expect(f.timer.defaultFocusMinutes, 25);
  expect(f.timer.state.totalSeconds, before.totalSeconds);
  expect(f.timer.state.remainingSeconds, before.remainingSeconds);
  expect(f.timer.state.isRunning, before.isRunning);
  expect(f.timer.focusTimerEndsAtMillis, anchor);

  f.timer.resetTimer();
  expect(f.timer.state.totalSeconds, 25 * 60);
  expect(f.timer.state.remainingSeconds, 25 * 60);
}
