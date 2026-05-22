import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_config.dart';
import '../services/api_client.dart';

class AuthState {
  final String? userId;
  final String? username;
  final String? email;
  final bool emailVerified;
  final String? displayName;
  final String? avatar;
  final String? bio;
  final String? token;
  final bool isAdmin;

  const AuthState({
    this.userId,
    this.username,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.avatar,
    this.bio,
    this.token,
    this.isAdmin = false,
  });

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'email': email,
    'email_verified': emailVerified,
    'display_name': displayName,
    'avatar': avatar,
    'bio': bio,
    'token': token,
    'is_admin': isAdmin,
  };

  factory AuthState.fromJson(Map<String, dynamic> j) => AuthState(
    userId: j['user_id'] as String?,
    username: j['username'] as String?,
    email: j['email'] as String?,
    emailVerified: j['email_verified'] == true,
    displayName: j['display_name'] as String?,
    avatar: j['avatar'] as String?,
    bio: j['bio'] as String?,
    token: j['token'] as String?,
    isAdmin: j['is_admin'] == true,
  );

  AuthState copyWith({
    String? userId,
    String? username,
    String? email,
    bool? emailVerified,
    String? displayName,
    String? avatar,
    String? bio,
    String? token,
    bool? isAdmin,
  }) => AuthState(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    token: token ?? this.token,
    isAdmin: isAdmin ?? this.isAdmin,
  );
}

/// 登录态 + 连接到服务器的 ApiClient。
///
/// 服务器地址完全由 [AppConfig.bakedServerUrl] 决定，不可在运行时修改。
/// 对于历史版本在本地留下的 `auth_base_url_admin` 键，启动时会清理掉。
class AuthProvider extends ChangeNotifier {
  AuthState _state = const AuthState();
  late String _baseUrl;
  Map<String, dynamic> _serverConfig = const {};
  late ApiClient _client;

  /// 拉取到 /api/config 之后会触发，供 AiService / CloudSyncProvider 订阅。
  void Function(Map<String, dynamic> cfg)? onServerConfigChanged;
  Future<void> Function(AuthState state)? onAccountProfileChanged;
  Future<void> Function()? onAccountLoggedOut;

  AuthState get state => _state;
  String get baseUrl => _baseUrl;
  Map<String, dynamic> get serverConfig => _serverConfig;
  bool get inviteCodeRequired =>
      _serverConfig['invite_code_required'] == true ||
      _serverConfig['registration_invite_required'] == true;
  bool get registrationEnabled =>
      _serverConfig['registration_enabled'] != false &&
      _serverConfig['allow_public_registration'] != false;
  bool get registrationEmailRequired =>
      _serverConfig['registration_email_required'] == true;
  bool get maintenanceMode => _serverConfig['maintenance_mode'] == true;
  String get maintenanceMessage =>
      (_serverConfig['maintenance_message'] ?? '').toString();
  ApiClient get client => _client;

  AuthProvider({
    ApiClient? client,
    AuthState initialState = const AuthState(),
    String? baseUrl,
  }) {
    _state = initialState;
    _baseUrl = baseUrl ?? client?.baseUrl ?? AppConfig.bakedServerUrl;
    _client = client ?? ApiClient(baseUrl: _baseUrl, token: _state.token);
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    // 清理旧版本可能遗留的本地服务器覆盖；当前策略不允许 APP 内改地址。
    await prefs.remove('auth_base_url');
    await prefs.remove('auth_base_url_admin');

    _baseUrl = AppConfig.bakedServerUrl;

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
    if (_baseUrl.isEmpty) {
      // 同域相对路径下也可以拉 /api/config
    }
    try {
      final cfg = await _client.get('/api/config');
      _serverConfig = cfg;
      onServerConfigChanged?.call(cfg);
      notifyListeners();
    } catch (_) {
      // offline or server down — 保留旧配置
    }
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_state', json.encode(_state.toJson()));
  }

  Future<void> register({
    required String username,
    required String password,
    String? email,
    String? emailCode,
    String? displayName,
    String? inviteCode,
  }) async {
    final res = await _client.post('/api/auth/register', {
      'username': username,
      'password': password,
      if (email != null && email.isNotEmpty) 'email': email,
      if (emailCode != null && emailCode.isNotEmpty) 'email_code': emailCode,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
      if (inviteCode != null && inviteCode.isNotEmpty) ...{
        'invite_code': inviteCode,
        'invitation_code': inviteCode,
      },
    });
    _state = _stateFromAuthResponse(res);
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
    await _refreshServerConfig();
  }

  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) {
    return _client.post('/api/auth/email-code', {
      'email': email,
      'purpose': purpose,
    });
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final res = await _client.post('/api/auth/login', {
      'username': username,
      'account': username,
      if (_looksLikeEmail(username)) 'email': username,
      'password': password,
    });
    _state = _stateFromAuthResponse(res);
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
    await _refreshServerConfig();
  }

  Future<void> emailLogin({required String email, required String code}) async {
    final res = await _client.post('/api/auth/email-login', {
      'email': email,
      'code': code,
    });
    _state = _stateFromAuthResponse(res);
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    await _notifyAccountProfileChanged();
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
    await _notifyAccountLoggedOut();
    notifyListeners();
  }

  Future<void> refreshMe() async {
    if (!_state.isLoggedIn) return;
    try {
      final me = await _client.get('/api/auth/me');
      _state = _stateFromAuthResponse(me, keepToken: true);
      await _persistState();
      await _notifyAccountProfileChanged();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateProfile({
    required String username,
    String? email,
    String? emailCode,
    String? displayName,
    String? avatar,
    String? bio,
  }) async {
    final res = await _client.patch('/api/auth/profile', {
      'username': username,
      'email': email,
      if (emailCode != null && emailCode.isNotEmpty) 'email_code': emailCode,
      'display_name': displayName,
      'avatar': avatar,
      'bio': bio,
    });
    _state = _stateFromAuthResponse(res, keepToken: true);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post('/api/auth/change-password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  Future<void> uploadAvatarBytes({
    required String filename,
    required Uint8List bytes,
  }) async {
    final res = await _client.uploadBytes(
      '/api/auth/avatar',
      fieldName: 'avatar',
      filename: filename,
      bytes: bytes,
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<Map<String, dynamic>> requestPasswordReset({required String account}) {
    final trimmed = account.trim();
    return _client.post('/api/auth/password-reset/request', {
      'username': trimmed,
      'account': trimmed,
      'identifier': trimmed,
      if (_looksLikeEmail(trimmed)) 'email': trimmed,
    });
  }

  Future<void> confirmPasswordReset({
    String? token,
    String? account,
    String? email,
    String? code,
    required String newPassword,
  }) async {
    final body = <String, dynamic>{
      'password': newPassword,
      'new_password': newPassword,
    };
    final identifier = (email != null && email.isNotEmpty) ? email : account;
    if (identifier != null &&
        identifier.isNotEmpty &&
        code != null &&
        code.isNotEmpty) {
      body['account'] = identifier;
      body['identifier'] = identifier;
      body['email'] = email;
      if (email == null && _looksLikeEmail(identifier)) {
        body['email'] = identifier;
      }
      body['code'] = code;
    } else {
      body['token'] = token ?? code ?? '';
    }
    await _client.post('/api/auth/password-reset/confirm', body);
  }

  AuthState _stateFromAuthResponse(
    Map<String, dynamic> data, {
    bool keepToken = false,
  }) {
    final source = data['user'];
    final payload = source is Map<String, dynamic>
        ? source
        : source is Map
        ? Map<String, dynamic>.from(source)
        : data;
    return AuthState(
      userId: _stringField(
        payload,
        'user_id',
        _stringField(payload, 'id', _state.userId),
      ),
      username: _stringField(payload, 'username', _state.username),
      email: _stringField(payload, 'email', _state.email),
      emailVerified: payload.containsKey('email_verified')
          ? payload['email_verified'] == true
          : _state.emailVerified,
      displayName: _stringField(payload, 'display_name', _state.displayName),
      avatar: _stringField(
        payload,
        'avatar',
        _stringField(payload, 'avatar_url', _state.avatar),
      ),
      bio: _stringField(payload, 'bio', _state.bio),
      token: keepToken
          ? _state.token
          : _stringField(payload, 'token', _state.token),
      isAdmin: payload.containsKey('is_admin')
          ? payload['is_admin'] == true
          : _state.isAdmin,
    );
  }

  String? _stringField(
    Map<String, dynamic> data,
    String key,
    String? fallback,
  ) {
    if (!data.containsKey(key)) return fallback;
    return data[key] as String?;
  }

  Future<void> _notifyAccountProfileChanged() async {
    if (!_state.isLoggedIn) return;
    final callback = onAccountProfileChanged;
    if (callback == null) return;
    try {
      await callback(_state);
    } catch (e, st) {
      debugPrint('[auth] account profile sync failed: $e\n$st');
    }
  }

  Future<void> _notifyAccountLoggedOut() async {
    final callback = onAccountLoggedOut;
    if (callback == null) return;
    try {
      await callback();
    } catch (e, st) {
      debugPrint('[auth] account logout cleanup failed: $e\n$st');
    }
  }
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}
