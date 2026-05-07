import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_config.dart';
import '../services/api_client.dart';

class AuthState {
  final String? userId;
  final String? username;
  final String? token;
  final bool isAdmin;

  const AuthState({
    this.userId,
    this.username,
    this.token,
    this.isAdmin = false,
  });

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'token': token,
        'is_admin': isAdmin,
      };

  factory AuthState.fromJson(Map<String, dynamic> j) => AuthState(
        userId: j['user_id'] as String?,
        username: j['username'] as String?,
        token: j['token'] as String?,
        isAdmin: j['is_admin'] == true,
      );
}

/// 登录态 + 服务器配置。
/// 普通用户不再感知 baseUrl，服务器地址由 [AppConfig.bakedServerUrl] 提供，
/// 仅管理员可通过 [setBaseUrlByAdmin] 覆盖并存入本地。
class AuthProvider extends ChangeNotifier {
  AuthState _state = const AuthState();
  String _baseUrl = '';
  Map<String, dynamic> _serverConfig = const {};
  late ApiClient _client;

  /// 拉取到 /api/config 之后会触发此回调，供 AiService / CloudSyncProvider 等订阅。
  void Function(Map<String, dynamic> cfg)? onServerConfigChanged;

  AuthState get state => _state;
  String get baseUrl => _baseUrl;
  Map<String, dynamic> get serverConfig => _serverConfig;
  bool get inviteCodeRequired => _serverConfig['invite_code_required'] == true;
  bool get registrationEnabled => _serverConfig['registration_enabled'] != false;
  bool get maintenanceMode => _serverConfig['maintenance_mode'] == true;
  String get maintenanceMessage =>
      (_serverConfig['maintenance_message'] ?? '').toString();
  ApiClient get client => _client;

  AuthProvider() {
    _client = ApiClient();
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    // 管理员覆盖值优先；没有则用 baked URL
    final adminOverride = prefs.getString('auth_base_url_admin') ?? '';
    _baseUrl = adminOverride.isNotEmpty
        ? adminOverride
        : AppConfig.bakedServerUrl;

    final raw = prefs.getString('auth_state');
    if (raw != null && raw.isNotEmpty) {
      try {
        _state = AuthState.fromJson(json.decode(raw));
      } catch (_) {}
    }
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    notifyListeners();
    await _refreshServerConfig();
  }

  Future<void> _refreshServerConfig() async {
    if (_baseUrl.isEmpty) return;
    try {
      final cfg = await _client.get('/api/config');
      _serverConfig = cfg;
      onServerConfigChanged?.call(cfg);
      notifyListeners();
    } catch (_) {
      // offline or server down — 保留旧配置
    }
  }

  /// 只有管理员可以调用。
  Future<void> setBaseUrlByAdmin(String url) async {
    _baseUrl = url.trim().isEmpty ? AppConfig.bakedServerUrl : url.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_baseUrl == AppConfig.bakedServerUrl) {
      await prefs.remove('auth_base_url_admin');
    } else {
      await prefs.setString('auth_base_url_admin', _baseUrl);
    }
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    notifyListeners();
    await _refreshServerConfig();
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_state', json.encode(_state.toJson()));
  }

  Future<void> register({
    required String username,
    required String password,
    String? inviteCode,
  }) async {
    final res = await _client.post('/api/auth/register', {
      'username': username,
      'password': password,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode,
    });
    _state = AuthState(
      userId: res['user_id'] as String?,
      username: res['username'] as String?,
      token: res['token'] as String?,
      isAdmin: res['is_admin'] == true,
    );
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    notifyListeners();
    await _refreshServerConfig();
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final res = await _client.post('/api/auth/login', {
      'username': username,
      'password': password,
    });
    _state = AuthState(
      userId: res['user_id'] as String?,
      username: res['username'] as String?,
      token: res['token'] as String?,
      isAdmin: res['is_admin'] == true,
    );
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    notifyListeners();
    await _refreshServerConfig();
  }

  Future<void> logout() async {
    try {
      if (_state.isLoggedIn) await _client.post('/api/auth/logout');
    } catch (_) {}
    _state = const AuthState();
    _client = ApiClient(baseUrl: _baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_state');
    notifyListeners();
  }

  /// 在 /api/auth/me 成功后更新最新角色。
  Future<void> refreshMe() async {
    if (!_state.isLoggedIn) return;
    try {
      final me = await _client.get('/api/auth/me');
      _state = AuthState(
        userId: (me['user_id'] ?? _state.userId) as String?,
        username: (me['username'] ?? _state.username) as String?,
        token: _state.token,
        isAdmin: me['is_admin'] == true,
      );
      await _persistState();
      notifyListeners();
    } catch (_) {}
  }
}
