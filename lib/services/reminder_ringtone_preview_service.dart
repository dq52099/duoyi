import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'focus_sound_service.dart';

class ReminderRingtonePreviewService {
  ReminderRingtonePreviewService._();

  static final ReminderRingtonePreviewService instance =
      ReminderRingtonePreviewService._();

  static const Duration defaultDuration = Duration(seconds: 3);

  Timer? _stopTimer;
  int _generation = 0;
  AudioPlayer? _player;
  String? _focusPreviewSoundId;

  @visibleForTesting
  static AudioContext get previewAudioContext =>
      FocusSoundService.mediaAudioContext;

  Future<bool> preview({
    required String soundName,
    required int volumePercent,
    Duration duration = defaultDuration,
  }) async {
    final generation = ++_generation;
    await _stopActivePreview();
    final assetPath = assetPathFor(soundName);
    final volume = (volumePercent.clamp(40, 80) / 100).toDouble();
    try {
      final focusPreviewStarted = await _playWithFocusMediaPath(
        soundName: soundName,
        assetPath: assetPath,
        volume: volume,
      );
      if (focusPreviewStarted) {
        if (generation != _generation) {
          await _stopActivePreview();
          return false;
        }
        _stopTimer = Timer(duration, () {
          if (generation == _generation) unawaited(stop());
        });
        return true;
      }
      var player = AudioPlayer();
      _player = player;
      final started = await _playSource(
        player,
        AssetSource(assetPath),
        volume: volume,
      );
      if (!started) {
        await player.dispose();
        final cachedSource = await _deviceFileSourceForAsset(assetPath);
        player = AudioPlayer();
        _player = player;
        final fileStarted = await _playSource(
          player,
          cachedSource,
          volume: volume,
        );
        if (!fileStarted) {
          throw StateError('asset and cached file preview both failed');
        }
      }
      if (generation != _generation) {
        await _stopActivePreview();
        return false;
      }
      _stopTimer = Timer(duration, () {
        if (generation == _generation) unawaited(stop());
      });
      return true;
    } catch (e, st) {
      debugPrint(
        '[ReminderRingtonePreviewService] asset media preview failed $soundName '
        'asset=$assetPath volume=$volumePercent: $e\n$st',
      );
      await _stopActivePreview();
      return false;
    }
  }

  Future<bool> _playWithFocusMediaPath({
    required String soundName,
    required String assetPath,
    required double volume,
  }) async {
    final focus = FocusSoundService.instance;
    final activeFocusSound = focus.currentSound;
    final activeFocusPlayback =
        focus.isPlaying && !activeFocusSound.startsWith('reminder_preview_');
    if (activeFocusPlayback) return false;
    final previewId = 'reminder_preview_$soundName';
    try {
      await focus.setVolume(volume);
      final started = await focus.previewAsset(previewId, assetPath);
      if (!started) return false;
      _focusPreviewSoundId = previewId;
      return true;
    } catch (e, st) {
      debugPrint(
        '[ReminderRingtonePreviewService] focus media preview failed '
        '$soundName asset=$assetPath volume=$volume: $e\n$st',
      );
      return false;
    }
  }

  Future<bool> _playSource(
    AudioPlayer player,
    Source source, {
    required double volume,
  }) async {
    try {
      await player.setAudioContext(previewAudioContext);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.play(
        source,
        volume: volume,
        ctx: previewAudioContext,
        mode: PlayerMode.mediaPlayer,
      );
      return true;
    } catch (e, st) {
      debugPrint(
        '[ReminderRingtonePreviewService] source preview failed '
        '${source.runtimeType}: $e\n$st',
      );
      return false;
    }
  }

  Future<DeviceFileSource> _deviceFileSourceForAsset(String assetPath) async {
    final bundlePath = 'assets/$assetPath';
    final data = await rootBundle.load(bundlePath);
    final tempDir = await getTemporaryDirectory();
    final safeName = assetPath.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File('${tempDir.path}/duoyi_reminder_preview_$safeName');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final exists = await file.exists();
    final currentLength = exists ? await file.length() : -1;
    if (!exists || currentLength != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return DeviceFileSource(file.path);
  }

  Future<void> stop() async {
    _generation++;
    await _stopActivePreview();
  }

  Future<void> _stopActivePreview() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    final focusPreviewSoundId = _focusPreviewSoundId;
    _focusPreviewSoundId = null;
    if (focusPreviewSoundId != null &&
        FocusSoundService.instance.currentSound == focusPreviewSoundId) {
      try {
        await FocusSoundService.instance.stop();
      } catch (e, st) {
        debugPrint(
          '[ReminderRingtonePreviewService] focus preview stop failed: $e\n$st',
        );
      }
    }
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (e, st) {
      debugPrint('[ReminderRingtonePreviewService] stop failed: $e\n$st');
    }
    try {
      await player.dispose();
    } catch (e, st) {
      debugPrint('[ReminderRingtonePreviewService] dispose failed: $e\n$st');
    }
  }

  @visibleForTesting
  static String assetPathFor(String soundName) {
    return 'sounds/reminders/duoyi_$soundName.wav';
  }
}
