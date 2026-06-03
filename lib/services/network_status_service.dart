import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络状态监听服务
///
/// 提供实时网络连接状态监控，区分WiFi、移动网络、离线等状态。
/// 用于云同步的智能重试和离线提示。
class NetworkStatusService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  List<ConnectivityResult> _connectivityResults = [ConnectivityResult.none];
  DateTime? _lastOnlineTime;
  DateTime? _lastOfflineTime;
  int _offlineCount = 0;

  NetworkStatusService() {
    _init();
  }

  Future<void> _init() async {
    try {
      _connectivityResults = await _connectivity.checkConnectivity();
    } catch (e) {
      debugPrint('[NetworkStatus] Failed to check initial connectivity: $e');
      _connectivityResults = [ConnectivityResult.none];
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        debugPrint('[NetworkStatus] Connectivity stream error: $error');
      },
    );
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasOnline = isOnline;
    _connectivityResults = results;
    final isNowOnline = isOnline;

    if (!wasOnline && isNowOnline) {
      _lastOnlineTime = DateTime.now();
      _offlineCount = 0;
      debugPrint('[NetworkStatus] Network connected: $connectionType');
    } else if (wasOnline && !isNowOnline) {
      _lastOfflineTime = DateTime.now();
      _offlineCount++;
      debugPrint('[NetworkStatus] Network disconnected');
    }

    notifyListeners();
  }

  /// 是否在线（有任何可用的网络连接）
  bool get isOnline {
    return _connectivityResults.any((result) => result != ConnectivityResult.none);
  }

  /// 是否离线
  bool get isOffline => !isOnline;

  /// 当前连接类型的描述
  String get connectionType {
    if (_connectivityResults.contains(ConnectivityResult.wifi)) {
      return 'WiFi';
    } else if (_connectivityResults.contains(ConnectivityResult.mobile)) {
      return '移动网络';
    } else if (_connectivityResults.contains(ConnectivityResult.ethernet)) {
      return '以太网';
    } else if (_connectivityResults.contains(ConnectivityResult.vpn)) {
      return 'VPN';
    } else {
      return '离线';
    }
  }

  /// 是否使用WiFi连接
  bool get isWifi => _connectivityResults.contains(ConnectivityResult.wifi);

  /// 是否使用移动网络
  bool get isMobile => _connectivityResults.contains(ConnectivityResult.mobile);

  /// 上次在线时间
  DateTime? get lastOnlineTime => _lastOnlineTime;

  /// 上次离线时间
  DateTime? get lastOfflineTime => _lastOfflineTime;

  /// 离线次数（每次恢复在线后重置）
  int get offlineCount => _offlineCount;

  /// 当前离线持续时间（秒）
  int get offlineDurationSeconds {
    if (isOnline || _lastOfflineTime == null) return 0;
    return DateTime.now().difference(_lastOfflineTime!).inSeconds;
  }

  /// 是否应该显示离线提示（离线超过3秒）
  bool get shouldShowOfflineWarning {
    return isOffline && offlineDurationSeconds >= 3;
  }

  /// 手动刷新网络状态
  Future<void> refresh() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _onConnectivityChanged(results);
    } catch (e) {
      debugPrint('[NetworkStatus] Failed to refresh connectivity: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
