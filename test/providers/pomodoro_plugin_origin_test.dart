import 'dart:async';
import 'dart:convert';

// Exercise the actual FocusSoundService through its plugin boundary.
// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/focus_sound_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sound = FocusSoundService.instance;
  const dndChannel = MethodChannel('duoyi/focus_dnd');
  const foreground = MethodChannel('duoyi/focus_sound_foreground');
  const distraction = MethodChannel('duoyi/focus_distraction');
  late _AudioPlatform audio;
  late _Gate volumeGate;
  final global = _GlobalAudioPlatform();

  setUpAll(() {
    GlobalAudioplayersPlatformInterface.instance = global;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    audio = _AudioPlatform();
    AudioplayersPlatformInterface.instance = audio;
    volumeGate = _Gate();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(foreground, (_) async => null);
    messenger.setMockMethodCallHandler(dndChannel, (_) async => null);
    messenger.setMockMethodCallHandler(
      distraction,
      (call) async => call.method == 'setFocusBlocker' ? true : null,
    );
    sound.registerCustomTracks({
      'custom:seed': '/test/seed.wav',
      'custom:next': '/test/next.wav',
      'custom:bad': '/test/bad.wav',
    });
  });
  tearDown(() async {
    volumeGate.release();
    await AccountPreferenceWrites.drain();
    await sound.stop();
    sound.registerCustomTracks({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(foreground, null);
    messenger.setMockMethodCallHandler(dndChannel, null);
    messenger.setMockMethodCallHandler(distraction, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final cancel in ['reset', 'account', 'boundary', 'runtime']) {
    test(
      'held volume never starts a preview after $cancel invalidation',
      () async {
        final timer = await _timer();
        await sound.play('custom:seed');
        audio.holdVolume = volumeGate;
        final changing = timer.setFocusSoundVolume(0.8);
        await volumeGate.arrived.future;
        final resumes = audio.resumes;
        Future<void>? boundary;
        switch (cancel) {
          case 'reset':
            timer.resetLocalState();
          case 'account':
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          case 'boundary':
            boundary = AccountPreferenceWrites.boundary(() async {});
          case 'runtime':
            timer.startIfIdle();
            timer.toggleTimer();
        }
        volumeGate.release();
        expect(await changing, isFalse);
        if (boundary != null) await boundary;
        await _settle();
        expect(audio.resumes, resumes);
      },
    );
  }

  test(
    'preview checks ownership again after its second volume await',
    () async {
      final timer = await _timer();
      await sound.play('custom:seed');
      audio.volumeCallsBeforeHold = 1;
      audio.holdVolume = volumeGate;
      final changing = timer.setFocusSoundVolume(0.8);
      await volumeGate.arrived.future;
      final resumes = audio.resumes;
      timer.resetLocalState();
      volumeGate.release();
      expect(await changing, isFalse);
      await _settle();
      expect(audio.resumes, resumes);
    },
  );

  test('held running sound volume cannot restart after reset', () async {
    final timer = await _timer(soundId: 'custom:seed');
    timer.startIfIdle();
    await _until(() => sound.isPlaying);
    audio.holdVolume = volumeGate;
    final changing = timer.setWhiteNoiseSound('custom:next', preview: false);
    await volumeGate.arrived.future;
    final resumes = audio.resumes;
    timer.resetLocalState();
    volumeGate.release();
    expect(await changing, isFalse);
    await _settle();
    expect(audio.resumes, resumes);
    expect(sound.isPlaying, isFalse);
  });

  test(
    'old failed sound compensation cannot overwrite a newer queued sound',
    () async {
      final store = _HeldConfigStore();
      SharedPreferencesStorePlatform.instance = store;
      final timer = await _timer(soundId: 'custom:seed', resetStore: false);
      timer.startIfIdle();
      await _until(() => sound.isPlaying);
      final failure = _Gate();
      addTearDown(failure.release);
      addTearDown(store.gate.release);
      audio.failedSource = failure;
      final old = timer.setWhiteNoiseSound('custom:bad', preview: false);
      await _until(() => failure.arrived.isCompleted);
      store.holdConfig = true;
      final newer = timer.setWhiteNoiseSound('custom:next', preview: false);
      await _until(() => store.gate.arrived.isCompleted);
      failure.release();
      await _settle();
      store.gate.release();
      expect(await old, isFalse);
      expect(await newer, isTrue);
      expect(timer.config.whiteNoiseSound, 'custom:next');
      expect(store.payloads.map((p) => p['whiteNoiseSound']), [
        'custom:seed',
        'custom:bad',
        'custom:next',
      ]);
      addTearDown(store.gate.release);
    },
  );

  test(
    'late DND enable restores its own filter without publishing after reset',
    () async {
      final enable = _Gate();
      final restored = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(dndChannel, (call) async {
            switch (call.method) {
              case 'getStatus':
                return {
                  'supported': true,
                  'accessGranted': true,
                  'currentFilter': 1,
                };
              case 'enableDnd':
                await enable.wait();
                return {
                  'enabled': true,
                  'previousFilter': 1,
                  'currentFilter': 2,
                };
              case 'restoreDnd':
                restored.add((call.arguments as Map)['previousFilter'] as int);
                return true;
            }
            return null;
          });
      final timer = await _timer();
      await timer.setAutoEnableDnd(true);
      timer.startIfIdle();
      await enable.arrived.future;
      timer.resetLocalState();
      var notifications = 0;
      timer.addListener(() => notifications++);
      enable.release();
      await _until(() => restored.isNotEmpty);
      await _settle();
      expect(restored, [1]);
      expect(timer.focusDndActive, isFalse);
      expect(timer.focusDndStatus.supported, isFalse);
      expect(notifications, 0);
      addTearDown(enable.release);
    },
  );

  test('invalidated DND status cannot issue a late enable', () async {
    final status = _Gate();
    var holdStatus = false;
    var enables = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dndChannel, (call) async {
          if (call.method == 'getStatus') {
            if (holdStatus) await status.wait();
            return {
              'supported': true,
              'accessGranted': true,
              'currentFilter': 1,
            };
          }
          if (call.method == 'enableDnd') enables++;
          return null;
        });
    final timer = await _timer();
    await timer.setAutoEnableDnd(true);
    holdStatus = true;
    timer.startIfIdle();
    await status.arrived.future;
    timer.resetLocalState();
    status.release();
    await _settle();
    expect(enables, 0);
    expect(timer.focusDndStatus.supported, isFalse);
    addTearDown(status.release);
  });
}

Future<PomodoroProvider> _timer({
  String? soundId,
  bool resetStore = true,
}) async {
  if (resetStore) SharedPreferences.setMockInitialValues({});
  if (soundId != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pomodoro_config',
      jsonEncode({'whiteNoiseSound': soundId}),
    );
  }
  final timer = PomodoroProvider();
  await timer.loadFromStorage();
  addTearDown(() async {
    timer.dispose();
    await timer.waitForSnapshotWrites();
    await _settle();
  });
  return timer;
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    done(),
    isTrue,
    reason: 'The expected plugin operation did not settle',
  );
}

class _Gate {
  final arrived = Completer<void>();
  final finished = Completer<void>();
  Future<void> wait() {
    if (!arrived.isCompleted) arrived.complete();
    return finished.future;
  }

  void release() {
    if (!finished.isCompleted) finished.complete();
  }
}

class _HeldConfigStore extends InMemorySharedPreferencesStore {
  _HeldConfigStore() : super.withData({});
  final gate = _Gate();
  final payloads = <Map<String, dynamic>>[];
  bool holdConfig = false;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.pomodoro_config') {
      payloads.add(Map<String, dynamic>.from(jsonDecode(value as String)));
      if (holdConfig) {
        holdConfig = false;
        await gate.wait();
      }
    }
    return super.setValue(type, key, value);
  }
}

class _AudioPlatform extends AudioplayersPlatformInterface {
  final events = <String, StreamController<AudioEvent>>{};
  int resumes = 0;
  int volumeCallsBeforeHold = 0;
  _Gate? holdVolume;
  _Gate? failedSource;
  @override
  Future<void> create(String id) async {
    events[id] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Stream<AudioEvent> getEventStream(String id) => events[id]!.stream;
  @override
  Future<void> dispose(String id) async {
    await events.remove(id)?.close();
  }

  @override
  Future<void> resume(String id) async {
    resumes++;
  }

  @override
  Future<void> setVolume(String id, double volume) async {
    final gate = holdVolume;
    if (gate != null) {
      if (volumeCallsBeforeHold > 0) {
        volumeCallsBeforeHold--;
      } else {
        holdVolume = null;
        await gate.wait();
      }
    }
  }

  @override
  Future<void> setSourceUrl(
    String id,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    if (url.endsWith('/bad.wav') && failedSource != null) {
      await failedSource!.wait();
      // Finish both sides of AudioPlayer's preparation Future.wait so the
      // intentional platform rejection is delivered without its 30s timeout.
      events[id]!.add(
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
      );
      throw PlatformException(code: 'test-playback-rejected');
    }
    events[id]!.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<int?> getCurrentPosition(String id) async => 0;
  @override
  Future<int?> getDuration(String id) async => 10000;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _GlobalAudioPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
