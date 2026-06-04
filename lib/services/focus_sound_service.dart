import 'dart:async';

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
  FocusSoundService._() {
    _foregroundChannel.setMethodCallHandler(_handleForegroundMethodCall);
  }

  /// 单例实例。
  static final FocusSoundService instance = FocusSoundService._();
  static const MethodChannel _foregroundChannel = MethodChannel(
    'duoyi/focus_sound_foreground',
  );

  final List<AudioPlayer> _players = <AudioPlayer>[];
  final Map<String, String> _customTrackPaths = <String, String>{};
  WidgetsBinding? _lifecycleBinding;
  Future<void> Function()? onForegroundStopRequested;

  String _currentSound = 'none';
  bool _isPlaying = false;
  int _playbackGeneration = 0;
  static const double defaultVolume = 1.0;
  static const double minimumAudibleVolume = 0.4;
  static const double minimumPreviewVolume = minimumAudibleVolume;
  double _volume = defaultVolume;

  static final AudioContext _focusAudioContext = AudioContextConfig(
    focus: AudioContextConfigFocus.gain,
    respectSilence: false,
    stayAwake: true,
  ).build();

  static AudioContext get mediaAudioContext => _focusAudioContext;

  @visibleForTesting
  static AudioContext get focusAudioContext => _focusAudioContext;

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
  /// 未知 id 不抛异常，但会返回 false，供 UI 提示用户当前选择没有发声。
  Future<bool> play(String sound) async {
    return _play(sound, ++_playbackGeneration);
  }

  Future<bool> playFile(String soundId, String filePath) async {
    if (filePath.isEmpty) return false;
    return _playSources(soundId, <Source>[
      DeviceFileSource(filePath),
    ], ++_playbackGeneration);
  }

  Future<bool> previewFile(String soundId, String filePath) async {
    if (filePath.isEmpty) return false;
    return _playSources(
      soundId,
      <Source>[DeviceFileSource(filePath)],
      ++_playbackGeneration,
      startForegroundService: false,
    );
  }

  Future<bool> previewAsset(String soundId, String assetPath) async {
    if (assetPath.isEmpty) return false;
    return _playSources(
      soundId,
      <Source>[AssetSource(assetPath)],
      ++_playbackGeneration,
      startForegroundService: false,
    );
  }

  Future<bool> preview(
    String sound, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    _volume = _volume.clamp(minimumPreviewVolume, 1.0).toDouble();
    final generation = ++_playbackGeneration;
    final started = await _play(sound, generation);
    if (!started || duration <= Duration.zero) return started;
    unawaited(
      Future<void>.delayed(duration).then((_) async {
        if (generation == _playbackGeneration &&
            _isPlaying &&
            _currentSound != FocusSoundCatalog.none) {
          await stop();
        }
      }),
    );
    return true;
  }

  Future<bool> _play(String sound, int generation) async {
    final customPath = _customTrackPaths[sound];
    if (customPath != null && customPath.isNotEmpty) {
      return _playSources(sound, <Source>[
        DeviceFileSource(customPath),
      ], generation);
    }
    if (sound.startsWith('custom:')) {
      return false;
    }
    final normalizedInput = FocusSoundCatalog.normalizeForPlayback(sound);
    if (normalizedInput == FocusSoundCatalog.none) {
      await stop();
      return true;
    }
    final assets = FocusSoundCatalog.assetsFor(normalizedInput);
    if (assets.isEmpty) {
      return false;
    }
    final normalizedSound = FocusSoundCatalog.trackIdsFor(
      normalizedInput,
    ).join('+');
    return _playSources(
      normalizedSound,
      assets.map(AssetSource.new).toList(growable: false),
      generation,
    );
  }

  Future<bool> _playSources(
    String normalizedSound,
    List<Source> sources,
    int generation, {
    bool startForegroundService = true,
  }) async {
    if (_isPlaying && _currentSound == normalizedSound) {
      await _applyVolumeToPlayers(_volume);
      return true;
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
        return false;
      }
      _players.addAll(nextPlayers);
      _currentSound = normalizedSound;
      _isPlaying = true;
      await _applyVolumeToPlayers(_volume);
      if (startForegroundService) {
        await _startForegroundService();
      }
      return true;
    } catch (e, st) {
      debugPrint(
        '[FocusSoundService] failed to play $normalizedSound: $e\n$st',
      );
      await _disposePlayers(nextPlayers);
      await stop();
      return false;
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

  /// 设置目标音量，自动 clamp 到 `[minimumAudibleVolume, 1]`。
  Future<void> setVolume(double v) async {
    _volume = v.clamp(minimumAudibleVolume, 1.0).toDouble();
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
    onForegroundStopRequested = null;
    await _stopPlayers();
    await _stopForegroundService();
    _isPlaying = false;
    _currentSound = 'none';
  }

  Future<void> _handleForegroundMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'stopRequested':
        final handler = onForegroundStopRequested;
        if (handler != null) {
          await handler();
        } else {
          await stop();
        }
        return;
      default:
        throw MissingPluginException('No handler for ${call.method}');
    }
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
