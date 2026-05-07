import 'dart:async';

/// Web / unsupported-platform 空实现。
class SystemTrayService {
  final _onActivate = StreamController<String>.broadcast();
  Stream<String> get onActivate => _onActivate.stream;
  bool get isRegistered => false;

  Future<void> init() async {}
  void simulateActivate(String actionId) => _onActivate.add(actionId);
  void dispose() => _onActivate.close();
}
