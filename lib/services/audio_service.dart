import 'focus_sound_service.dart';

/// @deprecated Task 15.4：旧的 `AudioService` 只是一个假的内存开关，
/// 不播放任何音频。新代码请直接使用 [FocusSoundService.instance]。
///
/// 本文件保留作为兼容 shim，把调用原样转发到真实的 [FocusSoundService]，
/// 以防旧代码（或第三方补丁）意外引用到旧类。后续可删除。
@Deprecated('Use FocusSoundService.instance instead (Task 15.4).')
class AudioService {
  final FocusSoundService _delegate = FocusSoundService.instance;

  bool get isPlaying => _delegate.isPlaying;
  String get currentSound => _delegate.currentSound;

  Future<void> play(String sound) => _delegate.play(sound);

  /// 兼容旧 API：toggle = 播放中则 stop，否则 play 当前音轨。
  /// 对齐旧语义并不重要，这里保持"只停不起"的保守行为。
  Future<void> toggle() async {
    if (_delegate.isPlaying) {
      await _delegate.stop();
    }
  }

  Future<void> stop() => _delegate.stop();

  Future<void> dispose() async {
    // 不释放 FocusSoundService 单例；旧 shim 不拥有其生命周期。
  }
}
