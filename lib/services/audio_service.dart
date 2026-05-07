class AudioService {
  bool _isPlaying = false;
  String _currentSound = 'none';
  bool get isPlaying => _isPlaying;
  String get currentSound => _currentSound;

  Future<void> play(String sound) async {
    _currentSound = sound;
    _isPlaying = true;
    // Real implementation would play the specific sound file here
  }

  Future<void> toggle() async {
    _isPlaying = !_isPlaying;
  }

  Future<void> stop() async {
    _isPlaying = false;
    _currentSound = 'none';
  }

  void dispose() {
    _isPlaying = false;
  }
}
