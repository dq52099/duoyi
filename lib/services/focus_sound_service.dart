import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/focus_sound_catalog.dart';

/// FocusSoundService
///
/// 真实白噪音播放服务（基于 `audioplayers`），供专注模式 / 番茄钟驱动。
///
/// 关键行为：
/// - 使用 [ReleaseMode.loop] + [PlayerMode.lowLatency] 实现无缝循环。
/// - [play] 传入 `'none'` 等价于 [stop]。
/// - [fadeIn] / [fadeOut] 按线性 ramp 调整音量；[fadeOut] 完成后调用 [stop]。
/// - [bindLifecycle] 监听 Flutter 生命周期；播放中进入后台/锁屏时会再次确认
///   Android mediaPlayback 前台服务，降低白噪音被系统回收的概率。
///
/// Requirements: 5.2, 5.3, 5.4, 5.9
class FocusSoundService with WidgetsBindingObserver {
  FocusSoundService._();

  /// 单例实例。
  static final FocusSoundService instance = FocusSoundService._();
  static const MethodChannel _foregroundChannel = MethodChannel(
    'duoyi/focus_sound_foreground',
  );

  final List<AudioPlayer> _players = <AudioPlayer>[];
  final Map<String, String> _customTrackPaths = <String, String>{};
  WidgetsBinding? _lifecycleBinding;

  String _currentSound = 'none';
  bool _isPlaying = false;
  int _playbackGeneration = 0;
  static const double defaultVolume = 0.95;
  double _volume = defaultVolume;

  static final AudioContext _focusAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.gain,
    respectSilence: false,
    stayAwake: true,
  ).build();

  /// 当前正在播放的音轨 id（`'none'` 表示未播）。
  String get currentSound => _currentSound;

  /// 是否正在播放。
  bool get isPlaying => _isPlaying;

  /// 当前音量，范围 `0.0`..`1.0`。
  double get volume => _volume;

  /// 音轨 id -> asset 相对路径（相对于 `assets/`）。
  static Map<String, String> get assetMap => FocusSoundCatalog.assetMap;

  void registerCustomTracks(Map<String, String> tracks) {
    _customTrackPaths
      ..clear()
      ..addAll(tracks);
  }

  /// 切换音轨；传入 `'none'` 等价于 [stop]。
  ///
  /// 未知 id 静默忽略（不抛异常、不改变当前状态）。
  Future<void> play(String sound) async {
    final customPath = _customTrackPaths[sound];
    if (customPath != null && customPath.isNotEmpty) {
      final generation = ++_playbackGeneration;
      await _playSources(sound, <Source>[
        DeviceFileSource(customPath),
      ], generation);
      return;
    }
    final normalizedInput = FocusSoundCatalog.normalizeForPlayback(sound);
    if (normalizedInput == FocusSoundCatalog.none) {
      await stop();
      return;
    }
    final generation = ++_playbackGeneration;
    final assets = FocusSoundCatalog.assetsFor(normalizedInput);
    if (assets.length != 1) {
      return;
    }
    final normalizedSound = FocusSoundCatalog.trackIdsFor(
      normalizedInput,
    ).join('+');
    await _playSources(normalizedSound, <Source>[
      AssetSource(assets.single),
    ], generation);
  }

  Future<void> _playSources(
    String normalizedSound,
    List<Source> sources,
    int generation,
  ) async {
    if (_isPlaying && _currentSound == normalizedSound) {
      await _applyVolumeToPlayers(_volume);
      return;
    }
    await _stopPlayers();
    final nextPlayers = <AudioPlayer>[];
    try {
      for (final source in sources) {
        final player = AudioPlayer();
        nextPlayers.add(player);
        await player.setAudioContext(_focusAudioContext);
        await player.setReleaseMode(ReleaseMode.loop);
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await player.play(
          source,
          volume: _volume,
          ctx: _focusAudioContext,
          mode: PlayerMode.mediaPlayer,
        );
      }
      if (generation != _playbackGeneration) {
        await _disposePlayers(nextPlayers);
        return;
      }
      _players.addAll(nextPlayers);
      _currentSound = normalizedSound;
      _isPlaying = true;
      await _applyVolumeToPlayers(_volume);
      await _startForegroundService();
    } catch (e, st) {
      debugPrint(
        '[FocusSoundService] failed to play $normalizedSound: $e\n$st',
      );
      await _disposePlayers(nextPlayers);
      await stop();
    }
  }

  /// 停止播放并把状态复位到 `'none'`。
  Future<void> stop() async {
    _playbackGeneration++;
    if (!_isPlaying && _currentSound == 'none') {
      return;
    }
    await _stopPlayers();
    await _stopForegroundService();
    _currentSound = 'none';
    _isPlaying = false;
  }

  /// 设置音量，自动 clamp 到 `[0, 1]`。
  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    await _applyVolumeToPlayers(_volume);
  }

  Future<void> _applyVolumeToPlayers(double volume) async {
    await Future.wait(_players.map((player) => player.setVolume(volume)));
  }

  Future<void> _stopPlayers() async {
    final players = List<AudioPlayer>.of(_players);
    _players.clear();
    await _disposePlayers(players);
  }

  Future<void> _disposePlayers(List<AudioPlayer> players) async {
    await Future.wait(players.map((player) => player.stop()));
    await Future.wait(players.map((player) => player.dispose()));
  }

  /// 淡入：从 0 线性升至当前 [volume]。仅在正在播放时生效。
  Future<void> fadeIn(Duration d) async {
    if (!_isPlaying) {
      return;
    }
    final generation = _playbackGeneration;
    const int steps = 10;
    final double target = _volume;
    final int stepMs = d.inMilliseconds <= 0 ? 0 : d.inMilliseconds ~/ steps;
    for (int i = 0; i <= steps; i++) {
      if (generation != _playbackGeneration) return;
      await _applyVolumeToPlayers(target * (i / steps));
      if (stepMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }
    if (generation != _playbackGeneration) return;
    // ramp 结束后恢复目标音量，避免浮点误差
    await _applyVolumeToPlayers(target);
  }

  /// 淡出：从当前 [volume] 线性降至 0，结束后调用 [stop]。
  ///
  /// `fadeOut` 完成后 [volume] 字段保持原值（供下一次 [play] 使用），
  /// 只是 `_player` 端的音量被重置。
  Future<void> fadeOut(Duration d) async {
    if (!_isPlaying) {
      return;
    }
    final generation = _playbackGeneration;
    const int steps = 10;
    final double start = _volume;
    final int stepMs = d.inMilliseconds <= 0 ? 0 : d.inMilliseconds ~/ steps;
    for (int i = steps; i >= 0; i--) {
      if (generation != _playbackGeneration) {
        await _applyVolumeToPlayers(_volume);
        return;
      }
      await _applyVolumeToPlayers(start * (i / steps));
      if (stepMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }
    if (generation != _playbackGeneration) {
      await _applyVolumeToPlayers(_volume);
      return;
    }
    await stop();
    _volume = start;
  }

  /// 绑定生命周期监听。幂等；重复绑定同一个 binding 不会重复注册 observer。
  void bindLifecycle(WidgetsBinding binding) {
    if (identical(_lifecycleBinding, binding)) {
      return;
    }
    _lifecycleBinding?.removeObserver(this);
    _lifecycleBinding = binding;
    binding.addObserver(this);
  }

  void unbindLifecycle() {
    _lifecycleBinding?.removeObserver(this);
    _lifecycleBinding = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isPlaying) {
          // ignore: discarded_futures
          _startForegroundService();
        } else {
          // ignore: discarded_futures
          _stopForegroundService();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_isPlaying) {
          // ignore: discarded_futures
          _startForegroundService();
        }
        break;
    }
  }

  /// 释放底层播放器资源。
  Future<void> dispose() async {
    unbindLifecycle();
    await _stopPlayers();
    await _stopForegroundService();
    _isPlaying = false;
    _currentSound = 'none';
  }

  Future<void> _startForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _foregroundChannel.invokeMethod<void>('start');
    } catch (e, st) {
      debugPrint('[FocusSoundService] foreground start failed: $e\n$st');
    }
  }

  Future<void> _stopForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _foregroundChannel.invokeMethod<void>('stop');
    } catch (e, st) {
      debugPrint('[FocusSoundService] foreground stop failed: $e\n$st');
    }
  }
}
