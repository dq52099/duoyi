class AudioService {
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Future<void> toggle() async {
    _isPlaying = !_isPlaying;
  }

  Future<void> stop() async {
    _isPlaying = false;
  }

  void dispose() {
    _isPlaying = false;
  }
}