import 'dart:io';

import 'package:duoyi/services/focus_sound_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const foregroundChannel = MethodChannel('duoyi/focus_sound_foreground');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(foregroundChannel, (_) async => null);
  });

  tearDown(() async {
    await FocusSoundService.instance.setVolume(FocusSoundService.defaultVolume);
    await FocusSoundService.instance.dispose();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(foregroundChannel, null);
  });

  test('volume is clamped to an audible preview floor', () async {
    expect(
      FocusSoundService.minimumPreviewVolume,
      FocusSoundService.minimumAudibleVolume,
    );

    await FocusSoundService.instance.setVolume(0.01);

    expect(
      FocusSoundService.instance.volume,
      FocusSoundService.minimumAudibleVolume,
    );

    await FocusSoundService.instance.setVolume(0.75);
    expect(FocusSoundService.instance.volume, 0.75);

    await FocusSoundService.instance.setVolume(3);
    expect(FocusSoundService.instance.volume, 1.0);
  });

  test('preview reports startup failure to callers', () {
    final source = File(
      'lib/services/focus_sound_service.dart',
    ).readAsStringSync();

    expect(source, contains('Future<bool> preview('));
    expect(
      source,
      contains(
        '_volume = _volume.clamp(minimumPreviewVolume, 1.0).toDouble();',
      ),
    );
    expect(source, contains('final started = await _play(sound, generation);'));
    expect(source, contains('if (!started || duration <= Duration.zero)'));
    expect(source, contains('return false;'));
  });

  test('reminder previews use the same media asset playback primitives', () {
    final source = File(
      'lib/services/focus_sound_service.dart',
    ).readAsStringSync();
    final reminderPreview = File(
      'lib/services/reminder_ringtone_preview_service.dart',
    ).readAsStringSync();

    expect(source, contains('Future<bool> previewFile('));
    expect(source, contains('Future<bool> previewAsset('));
    expect(source, contains('startForegroundService: false'));
    expect(source, contains('DeviceFileSource(filePath)'));
    expect(source, contains('AssetSource(assetPath)'));
    expect(reminderPreview, contains('AudioPlayer? _player'));
    expect(reminderPreview, contains('AssetSource(assetPath)'));
    expect(reminderPreview, contains('FocusSoundService.mediaAudioContext'));
  });

  test(
    'missing custom focus sounds report preview failure instead of silence',
    () async {
      final started = await FocusSoundService.instance.preview(
        'custom:missing-file',
        duration: Duration.zero,
      );

      expect(started, isFalse);
      expect(FocusSoundService.instance.currentSound, 'none');
      expect(FocusSoundService.instance.isPlaying, isFalse);
    },
  );

  test('focus sound selection starts an automatic preview', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final goalEditScreen = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains(
        'Future<bool> setWhiteNoiseSound(String sound, {bool preview = true})',
      ),
    );
    expect(provider, contains('return _previewWhiteNoiseSound(normalized);'));
    expect(screen, contains('Future<void> previewSound(String value) async'));
    expect(
      screen,
      contains(
        'final started = await FocusSoundService.instance.preview(value);',
      ),
    );
    expect(screen, contains('onChanged: (value) =>'));
    expect(screen, contains('previewSound(value ?? FocusSoundCatalog.none)'));
    expect(
      screen,
      contains('final previewStarted = await provider.setWhiteNoiseSound('),
    );
    expect(
      goalEditScreen,
      contains('await FocusSoundService.instance.stop();'),
    );
    expect(
      goalEditScreen,
      contains('final started = await FocusSoundService.instance.preview(id);'),
    );
  });

  test('focus sound volume changes are persisted and previewed', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final model = File('lib/models/pomodoro.dart').readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();

    expect(model, contains('double focusSoundVolume'));
    expect(model, contains("'focusSoundVolume': focusSoundVolume"));
    expect(model, contains("json['focusSoundVolume']"));
    expect(provider, contains('Future<bool> setFocusSoundVolume('));
    expect(provider, contains('_config.focusSoundVolume = normalized'));
    expect(provider, contains('await _sound.setVolume(normalized)'));
    expect(
      provider,
      contains('return _previewWhiteNoiseSound(_focusSoundPreviewFallback);'),
    );
    expect(provider, contains('FocusSoundCatalog.tracks.first.id'));
    expect(
      screen,
      contains('const volumeOptions = <double>[0.4, 0.6, 0.8, 1.0]'),
    );
    expect(screen, contains('.setFocusSoundVolume(value)'));
    expect(screen, contains('专注音量预览启动失败'));
  });

  test('foreground notification stop is routed back to Dart audio state', () {
    final service = File(
      'lib/services/focus_sound_service.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final foregroundService = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/services/FocusSoundForegroundService.kt',
    ).readAsStringSync();

    expect(service, contains('_foregroundChannel.setMethodCallHandler'));
    expect(service, contains("case 'stopRequested':"));
    expect(service, contains('onForegroundStopRequested'));
    expect(service, contains('await stop();'));
    expect(provider, contains('handleFocusForegroundStopRequested'));
    expect(
      provider,
      contains(
        'await setWhiteNoiseSound(FocusSoundCatalog.none, preview: false);',
      ),
    );
    expect(
      mainActivity,
      contains('FocusSoundForegroundService.stopRequestCallback'),
    );
    expect(mainActivity, contains('invokeMethod("stopRequested", null)'));
    expect(foregroundService, contains('stopRequestCallback?.invoke()'));
    expect(
      foregroundService,
      isNot(
        contains('if (intent?.action == actionStop) {\n            stopSelf()'),
      ),
    );
  });
}
