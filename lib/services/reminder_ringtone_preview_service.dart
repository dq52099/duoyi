import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'focus_sound_service.dart';

class ReminderRingtonePreviewService {
  ReminderRingtonePreviewService._();

  static final ReminderRingtonePreviewService instance =
      ReminderRingtonePreviewService._();

  static const Duration defaultDuration = Duration(seconds: 3);

  Timer? _stopTimer;
  int _generation = 0;
  AudioPlayer? _player;

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
      final player = AudioPlayer();
      _player = player;
      await player.setAudioContext(previewAudioContext);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.play(
        AssetSource(assetPath),
        volume: volume,
        ctx: previewAudioContext,
        mode: PlayerMode.mediaPlayer,
      );
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

  Future<void> stop() async {
    _generation++;
    await _stopActivePreview();
  }

  Future<void> _stopActivePreview() async {
    _stopTimer?.cancel();
    _stopTimer = null;
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
