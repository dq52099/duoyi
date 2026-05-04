import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';

class AuthState {
  final String? userId;
  final String? username;
  final String? token;
  final bool isAdmin;

  const AuthState({this.userId, this.username, this.token, this.isAdmin = false});

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

class AuthProvider extends ChangeNotifier {
  AuthState _state = const AuthState();
  String _baseUrl = '';
  bool _inviteRequired = false;
  late ApiClient _client;

  AuthState get state => _state;
  String get baseUrl => _baseUrl;
  bool get inviteCodeRequired => _inviteRequired;
  ApiClient get client => _client;

  AuthProvider() {
    _client = ApiClient();
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('auth_base_url') ?? '';
    final raw = prefs.getString('auth_state');
    if (raw != null && raw.isNotEmpty) {
      try {
        _state = AuthState.fromJson(json.decode(raw));
      } catch (_) {}
    }
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    notifyListeners();
    // Best effort: refresh feature flag from server
    if (_baseUrl.isNotEmpty) {
      try {
        final cfg = await _client.get('/api/config');
        _inviteRequired = cfg['invite_code_required'] == true;
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_base_url', _baseUrl);
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    notifyListeners();
    try {
      final cfg = await _client.get('/api/config');
      _inviteRequired = cfg['invite_code_required'] == true;
      notifyListeners();
    } catch (_) {}
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
    if (_baseUrl.isEmpty) throw const ApiException('请先在设置里填写服务器地址');
    final res = await _client.post('/api/auth/register', {
      'username': username,
      'password': password,
      if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
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
  }

  Future<void> login({required String username, required String password}) async {
    if (_baseUrl.isEmpty) throw const ApiException('请先在设置里填写服务器地址');
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
}
