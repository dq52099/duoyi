import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// FocusSoundService
///
/// 真实白噪音播放服务（基于 `audioplayers`），供专注模式 / 番茄钟驱动。
///
/// 关键行为：
/// - 使用 [ReleaseMode.loop] + [PlayerMode.lowLatency] 实现无缝循环。
/// - [play] 传入 `'none'` 等价于 [stop]。
/// - [fadeIn] / [fadeOut] 按线性 ramp 调整音量；[fadeOut] 完成后调用 [stop]。
/// - [bindLifecycle] 是生命周期挂载点占位，具体前后台策略由 PomodoroProvider
///   在 Task 16 接入时补齐。
///
/// Requirements: 5.2, 5.3, 5.4, 5.9
class FocusSoundService {
  FocusSoundService._();

  /// 单例实例。
  static final FocusSoundService instance = FocusSoundService._();

  final AudioPlayer _player = AudioPlayer();

  String _currentSound = 'none';
  bool _isPlaying = false;
  double _volume = 1.0;

  /// 当前正在播放的音轨 id（`'none'` 表示未播）。
  String get currentSound => _currentSound;

  /// 是否正在播放。
  bool get isPlaying => _isPlaying;

  /// 当前音量，范围 `0.0`..`1.0`。
  double get volume => _volume;

  /// 音轨 id -> asset 相对路径（相对于 `assets/`）。
  ///
  /// `AudioPlayer.play(AssetSource(path))` 的 `path` 不含前导 `assets/`。
  static const Map<String, String> _assetMap = <String, String>{
    'rain': 'sounds/white_noise/rain.mp3',
    'forest': 'sounds/white_noise/forest.mp3',
    'cafe': 'sounds/white_noise/cafe.mp3',
    'waves': 'sounds/white_noise/waves.mp3',
  };

  /// 切换音轨；传入 `'none'` 等价于 [stop]。
  ///
  /// 未知 id 静默忽略（不抛异常、不改变当前状态）。
  Future<void> play(String sound) async {
    if (sound == 'none') {
      await stop();
      return;
    }
    final String? asset = _assetMap[sound];
    if (asset == null) {
      return;
    }
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setVolume(_volume);
      await _player.play(AssetSource(asset));
      _currentSound = sound;
      _isPlaying = true;
    } catch (e, st) {
      debugPrint('[FocusSoundService] failed to play $sound: $e\n$st');
      await stop();
    }
  }

  /// 停止播放并把状态复位到 `'none'`。
  Future<void> stop() async {
    if (!_isPlaying && _currentSound == 'none') {
      return;
    }
    await _player.stop();
    _currentSound = 'none';
    _isPlaying = false;
  }

  /// 设置音量，自动 clamp 到 `[0, 1]`。
  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
  }

  /// 淡入：从 0 线性升至当前 [volume]。仅在正在播放时生效。
  Future<void> fadeIn(Duration d) async {
    if (!_isPlaying) {
      return;
    }
    const int steps = 10;
    final double target = _volume;
    final int stepMs = d.inMilliseconds <= 0 ? 0 : d.inMilliseconds ~/ steps;
    for (int i = 0; i <= steps; i++) {
      await _player.setVolume(target * (i / steps));
      if (stepMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }
    // ramp 结束后恢复目标音量，避免浮点误差
    await _player.setVolume(target);
  }

  /// 淡出：从当前 [volume] 线性降至 0，结束后调用 [stop]。
  ///
  /// `fadeOut` 完成后 [volume] 字段保持原值（供下一次 [play] 使用），
  /// 只是 `_player` 端的音量被重置。
  Future<void> fadeOut(Duration d) async {
    if (!_isPlaying) {
      return;
    }
    const int steps = 10;
    final double start = _volume;
    final int stepMs = d.inMilliseconds <= 0 ? 0 : d.inMilliseconds ~/ steps;
    for (int i = steps; i >= 0; i--) {
      await _player.setVolume(start * (i / steps));
      if (stepMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }
    await stop();
    _volume = start;
  }

  /// 绑定生命周期监听。
  ///
  /// 目前为占位：前后台切换策略由 [PomodoroProvider] 在 Task 16 接入时补齐
  /// （例如通过 [WidgetsBindingObserver] 监听 `AppLifecycleState`）。
  void bindLifecycle(WidgetsBinding binding) {
    // no-op
  }

  /// 释放底层播放器资源。
  Future<void> dispose() async {
    await _player.dispose();
    _isPlaying = false;
    _currentSound = 'none';
  }
}
