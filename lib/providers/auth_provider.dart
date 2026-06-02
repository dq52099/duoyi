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
  final int coinBalance;
  final int lifetimeCoins;
  final String? token;
  final bool isAdmin;
  final List<String>? adminPermissions;

  const AuthState({
    this.userId,
    this.username,
    this.email,
    this.emailVerified = false,
    this.displayName,
    this.avatar,
    this.bio,
    this.coinBalance = 0,
    this.lifetimeCoins = 0,
    this.token,
    this.isAdmin = false,
    this.adminPermissions,
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
    'coin_balance': coinBalance,
    'lifetime_coins': lifetimeCoins,
    'token': token,
    'is_admin': isAdmin,
    if (adminPermissions != null) 'admin_permissions': adminPermissions,
  };

  factory AuthState.fromJson(Map<String, dynamic> j) => AuthState(
    userId: j['user_id'] as String?,
    username: j['username'] as String?,
    email: j['email'] as String?,
    emailVerified: j['email_verified'] == true,
    displayName: j['display_name'] as String?,
    avatar: j['avatar'] as String?,
    bio: j['bio'] as String?,
    coinBalance: _intFromJson(j['coin_balance']),
    lifetimeCoins: _intFromJson(j['lifetime_coins']),
    token: j['token'] as String?,
    isAdmin: j['is_admin'] == true,
    adminPermissions: j.containsKey('admin_permissions')
        ? _stringListFromJson(j['admin_permissions'])
        : null,
  );

  AuthState copyWith({
    String? userId,
    String? username,
    String? email,
    bool? emailVerified,
    String? displayName,
    String? avatar,
    String? bio,
    int? coinBalance,
    int? lifetimeCoins,
    String? token,
    bool? isAdmin,
    List<String>? adminPermissions,
  }) => AuthState(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    email: email ?? this.email,
    emailVerified: emailVerified ?? this.emailVerified,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
    bio: bio ?? this.bio,
    coinBalance: coinBalance ?? this.coinBalance,
    lifetimeCoins: lifetimeCoins ?? this.lifetimeCoins,
    token: token ?? this.token,
    isAdmin: isAdmin ?? this.isAdmin,
    adminPermissions: adminPermissions ?? this.adminPermissions,
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
  int _stateMutationSerial = 0;
  int _refreshMeRequestSerial = 0;
  int _lastAppliedRefreshMeRequestSerial = 0;

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
      _serverConfig['registration_email_required'] != false;
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

  Future<void> loadFromStorage({bool refreshServerConfig = true}) async {
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
    if (refreshServerConfig) {
      await refreshServerConfigFromServer();
    }
  }

  Future<void> refreshServerConfigFromServer() async {
    if (_baseUrl.isEmpty) {
      // 同域相对路径下也可以拉 /api/config
    }
    try {
      final cfg = await _client.get('/api/config');
      if (jsonEncode(_serverConfig) == jsonEncode(cfg)) return;
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

  void _markAccountMutation(String reason) {
    _stateMutationSerial++;
    debugPrint(
      '[auth-sync] mutation=$_stateMutationSerial reason=$reason '
      'user=${_state.userId ?? '-'} coin=${_state.coinBalance} '
      'lifetime=${_state.lifetimeCoins}',
    );
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
    _markAccountMutation('register');
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
    await refreshServerConfigFromServer();
  }

  Future<Map<String, dynamic>> sendEmailCode({
    required String email,
    String purpose = 'login',
  }) async {
    final body = {'email': email, 'purpose': purpose};
    final result = await _postFirstAvailable(const [
      '/api/auth/email-code',
      '/api/auth/email-code/send',
      '/api/auth/email_code',
      '/api/auth/email_code/send',
      '/api/auth/email/send',
      '/api/auth/email/send-code',
      '/api/auth/send-email-code',
      '/api/auth/send-email_code',
      '/api/email-code',
      '/api/email-code/send',
      '/api/email_code',
      '/api/email_code/send',
      '/api/email/send',
      '/api/email/send-code',
      '/api/send-email-code',
      '/api/send-email_code',
    ], body);
    _throwIfEmailCodeNotDelivered(result);
    return result;
  }

  Future<Map<String, dynamic>> sendBindEmailCode({
    required String email,
  }) async {
    final result = await _postFirstAvailable(
      const [
        '/api/me/email-code',
        '/api/me/email-code/send',
        '/api/me/email_code',
        '/api/me/email_code/send',
        '/api/me/email/send',
        '/api/me/email/send-code',
        '/api/auth/email-code',
        '/api/auth/email-code/send',
        '/api/auth/email_code',
        '/api/auth/email_code/send',
        '/api/auth/email/send',
        '/api/auth/email/send-code',
        '/api/auth/send-email-code',
        '/api/auth/send-email_code',
        '/api/email-code',
        '/api/email-code/send',
        '/api/email_code',
        '/api/email_code/send',
        '/api/email/send',
        '/api/email/send-code',
        '/api/send-email-code',
        '/api/send-email_code',
        '/api/user/email-code',
        '/api/user/email-code/send',
        '/api/user/email_code',
        '/api/user/email_code/send',
        '/api/user/email/send',
        '/api/user/email/send-code',
        '/api/account/email-code',
        '/api/account/email-code/send',
        '/api/account/email_code',
        '/api/account/email_code/send',
        '/api/account/email/send',
        '/api/account/email/send-code',
      ],
      {'email': email, 'purpose': 'bind'},
    );
    _throwIfEmailCodeNotDelivered(result);
    return result;
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
    _markAccountMutation('login');
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
    await refreshServerConfigFromServer();
  }

  Future<void> emailLogin({required String email, required String code}) async {
    final res = await _postFirstAvailable(
      const [
        '/api/auth/email-login',
        '/api/auth/email/login',
        '/api/auth/login/email',
        '/api/auth/email-code-login',
        '/api/auth/login/email-code',
        '/api/auth/email_code_login',
        '/api/auth/login/email_code',
        '/api/user/email-login',
        '/api/user/login/email-code',
        '/api/user/email_code_login',
        '/api/user/login/email_code',
        '/api/account/email-login',
        '/api/account/email_code_login',
        '/api/email-login',
        '/api/email/login',
        '/api/login/email',
        '/api/email-code-login',
        '/api/login/email-code',
        '/api/email_code_login',
        '/api/login/email_code',
      ],
      {'email': email, 'code': code, 'email_code': code},
    );
    _state = _stateFromAuthResponse(res);
    _markAccountMutation('email_login');
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
    await refreshServerConfigFromServer();
  }

  Future<void> logout() async {
    try {
      if (_state.isLoggedIn) {
        await _sendFirstAvailable(
          const ['POST'],
          const [
            '/api/auth/logout',
            '/api/logout',
            '/api/me/logout',
            '/api/user/logout',
            '/api/account/logout',
            '/api/auth/signout',
            '/api/auth/sign-out',
          ],
          null,
          featureName: '退出登录',
        );
      }
    } catch (_) {}
    await _clearLocalSession();
  }

  Future<void> _clearLocalSession() async {
    _state = const AuthState();
    _markAccountMutation('logout');
    _client = ApiClient(baseUrl: _baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_state');
    await _notifyAccountLoggedOut();
    notifyListeners();
  }

  Future<void> refreshMe({String reason = 'manual'}) async {
    if (!_state.isLoggedIn) return;
    final requestId = ++_refreshMeRequestSerial;
    final mutationSerialAtStart = _stateMutationSerial;
    final tokenAtStart = _state.token;
    final userIdAtStart = _state.userId;
    debugPrint(
      '[auth-sync] refreshMe#$requestId start reason=$reason '
      'mutation=$mutationSerialAtStart user=${userIdAtStart ?? '-'}',
    );
    try {
      final me = await _getFirstAvailable(const ['/api/auth/me', '/api/me']);
      if (requestId != _refreshMeRequestSerial ||
          requestId < _lastAppliedRefreshMeRequestSerial) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: older response');
        return;
      }
      if (!_state.isLoggedIn || _state.token != tokenAtStart) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: token changed');
        return;
      }
      if (userIdAtStart != null &&
          _state.userId != null &&
          _state.userId != userIdAtStart) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: user changed');
        return;
      }
      if (_stateMutationSerial != mutationSerialAtStart) {
        debugPrint(
          '[auth-sync] refreshMe#$requestId skipped: newer account mutation '
          '$_stateMutationSerial > $mutationSerialAtStart',
        );
        return;
      }
      final nextState = _stateFromAuthResponse(me, keepToken: true);
      _lastAppliedRefreshMeRequestSerial = requestId;
      if (_authStatesEqual(_state, nextState)) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: unchanged');
        return;
      }
      _state = nextState;
      await _persistState();
      await _notifyAccountProfileChanged();
      debugPrint(
        '[auth-sync] refreshMe#$requestId applied '
        'coin=${_state.coinBalance} lifetime=${_state.lifetimeCoins}',
      );
      notifyListeners();
    } on ApiException catch (e) {
      if (_isAuthExpired(e)) {
        await _clearLocalSession();
      } else {
        debugPrint('[auth-sync] refreshMe#$requestId failed: ${e.message}');
      }
    } catch (e, st) {
      debugPrint('[auth-sync] refreshMe#$requestId failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> applyServerAccountSnapshot(
    Map<dynamic, dynamic> data, {
    String reason = 'server_snapshot',
    String? expectedToken,
    String? expectedUserId,
  }) async {
    if (!_state.isLoggedIn) return;
    if (expectedToken != null && _state.token != expectedToken) {
      debugPrint('[auth-sync] $reason skipped: token changed');
      return;
    }
    if (expectedUserId != null &&
        _state.userId != null &&
        _state.userId != expectedUserId) {
      debugPrint('[auth-sync] $reason skipped: user changed');
      return;
    }
    final nextState = _stateFromAuthResponse(
      Map<String, dynamic>.from(data),
      keepToken: true,
    );
    if (expectedUserId != null &&
        nextState.userId != null &&
        nextState.userId != expectedUserId) {
      debugPrint('[auth-sync] $reason skipped: response user mismatch');
      return;
    }
    if (_authStatesEqual(_state, nextState)) {
      debugPrint('[auth-sync] $reason skipped: unchanged');
      return;
    }
    _state = nextState;
    _markAccountMutation(reason);
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<Map<String, dynamic>> applyThemeShopItem({
    required String itemType,
    required String itemId,
    required String title,
  }) async {
    if (!_state.isLoggedIn) {
      throw const ApiException('请先登录后再使用主题商店');
    }
    final tokenAtStart = _state.token;
    final userIdAtStart = _state.userId;
    final res = await _client.post('/api/theme-shop/apply', {
      'item_type': itemType,
      'item_id': itemId,
      'title': title,
      'activate': true,
    });
    await applyServerAccountSnapshot(
      res,
      reason: 'theme_shop_apply',
      expectedToken: tokenAtStart,
      expectedUserId: userIdAtStart,
    );
    return res;
  }

  Future<void> updateProfile({String? displayName, String? bio}) async {
    final payload = <String, Object?>{};
    if (displayName != null) {
      payload['display_name'] = displayName;
      payload['displayName'] = displayName;
    }
    if (bio != null) payload['bio'] = bio;
    final res = await _sendFirstAvailable(
      const ['PATCH', 'POST', 'PUT'],
      const [
        '/api/me/profile',
        '/api/auth/profile',
        '/api/profile',
        '/api/user/profile',
        '/api/account/profile',
      ],
      payload,
      featureName: '个人资料',
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    _markAccountMutation('update_profile');
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<void> bindEmail({required String email, required String code}) async {
    final body = {
      'email': email,
      'code': code,
      'email_code': code,
      'emailCode': code,
    };
    final res = await _sendFirstAvailable(
      const ['POST', 'PATCH', 'PUT'],
      const [
        '/api/me/email',
        '/api/me/email/bind',
        '/api/me/bind-email',
        '/api/auth/email',
        '/api/auth/bind-email',
        '/api/auth/email/bind',
        '/api/email',
        '/api/email/bind',
        '/api/bind-email',
        '/api/user/email',
        '/api/user/email/bind',
        '/api/user/bind-email',
        '/api/account/email',
        '/api/account/email/bind',
      ],
      body,
      featureName: '邮箱绑定',
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    _markAccountMutation('bind_email');
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _sendFirstAvailable(
      const ['POST'],
      const ['/api/me/password', '/api/auth/change-password'],
      {
        'current_password': currentPassword,
        'currentPassword': currentPassword,
        'old_password': currentPassword,
        'new_password': newPassword,
        'newPassword': newPassword,
        'password': newPassword,
      },
      featureName: '密码修改',
    );
    await _clearLocalSession();
  }

  Future<void> uploadAvatarBytes({
    required String filename,
    required Uint8List bytes,
  }) async {
    final res = await _uploadFirstAvailable(
      const [
        '/api/me/avatar',
        '/api/me/profile/avatar',
        '/api/auth/profile/avatar',
        '/api/auth/avatar',
        '/api/profile/avatar',
        '/api/avatar',
        '/api/user/profile/avatar',
        '/api/user/avatar',
        '/api/account/profile/avatar',
        '/api/account/avatar',
      ],
      fieldName: 'avatar',
      fieldNameFallbacks: const ['file', 'image'],
      filename: filename,
      bytes: bytes,
      featureName: '头像上传',
    );
    _state = _stateFromAuthResponse(res, keepToken: true);
    _markAccountMutation('upload_avatar');
    await _persistState();
    await _notifyAccountProfileChanged();
    notifyListeners();
  }

  Future<Map<String, dynamic>> requestPasswordReset({required String account}) {
    final trimmed = account.trim();
    return _postFirstAvailable(
      const [
        '/api/auth/password-reset',
        '/api/auth/password-reset/request',
        '/api/auth/reset-password',
        '/api/auth/reset-password/request',
        '/api/auth/forgot-password',
        '/api/auth/forgot-password/request',
        '/api/password-reset',
        '/api/password-reset/request',
      ],
      {
        'username': trimmed,
        'account': trimmed,
        'identifier': trimmed,
        if (_looksLikeEmail(trimmed)) 'email': trimmed,
      },
    );
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
    await _postFirstAvailable(const [
      '/api/auth/password-reset/confirm',
      '/api/auth/reset-password/confirm',
      '/api/auth/forgot-password/confirm',
      '/api/password-reset/confirm',
    ], body);
  }

  AuthState _stateFromAuthResponse(
    Map<String, dynamic> data, {
    bool keepToken = false,
  }) {
    final source = data['user'] ?? data['profile'] ?? data['data'];
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
      username: _stringField(
        payload,
        'username',
        _stringField(payload, 'identifier', _state.username),
      ),
      email: _stringField(payload, 'email', _state.email),
      emailVerified: _boolField(
        payload,
        'email_verified',
        _boolField(payload, 'emailVerified', _state.emailVerified),
      ),
      displayName: _stringField(
        payload,
        'display_name',
        _stringField(payload, 'displayName', _state.displayName),
      ),
      avatar: _avatarField(
        payload,
        'avatar',
        _avatarField(
          payload,
          'avatar_url',
          _avatarField(
            payload,
            'avatarUrl',
            _avatarField(
              payload,
              'url',
              _avatarField(payload, 'path', _state.avatar),
            ),
          ),
        ),
      ),
      bio: _stringField(payload, 'bio', _state.bio),
      coinBalance: _intField(
        payload,
        'coin_balance',
        _intField(payload, 'coinBalance', _state.coinBalance),
      ),
      lifetimeCoins: _intField(
        payload,
        'lifetime_coins',
        _intField(payload, 'lifetimeCoins', _state.lifetimeCoins),
      ),
      token: keepToken
          ? _state.token
          : _stringField(payload, 'token', _state.token),
      isAdmin: _boolField(
        payload,
        'is_admin',
        _boolField(payload, 'isAdmin', _state.isAdmin),
      ),
      adminPermissions: payload.containsKey('admin_permissions')
          ? _stringListFromJson(payload['admin_permissions'])
          : payload.containsKey('permissions')
          ? _stringListFromJson(payload['permissions'])
          : _state.adminPermissions,
    );
  }

  String? _stringField(
    Map<String, dynamic> data,
    String key,
    String? fallback,
  ) {
    if (!data.containsKey(key)) return fallback;
    final value = data[key];
    if (value == null) return null;
    return value.toString();
  }

  bool _boolField(Map<String, dynamic> data, String key, bool fallback) {
    if (!data.containsKey(key)) return fallback;
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (['true', '1', 'yes', 'y'].contains(normalized)) return true;
      if (['false', '0', 'no', 'n'].contains(normalized)) return false;
    }
    return fallback;
  }

  String? _avatarField(
    Map<String, dynamic> data,
    String key,
    String? fallback,
  ) {
    final value = _stringField(data, key, fallback);
    if (value == null || value.isEmpty) return value;
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    if (uri.hasScheme || !value.startsWith('/')) return value;
    if (_baseUrl.isEmpty) return value;
    var normalizedBase = _baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    var normalizedValue = value;
    if (_hasBackendApiPrefix(normalizedValue) &&
        normalizedBase.endsWith(
          String.fromCharCodes(const [47, 97, 112, 105]),
        )) {
      normalizedValue = normalizedValue.substring(4);
    }
    return '$normalizedBase$normalizedValue';
  }

  bool _hasBackendApiPrefix(String value) {
    if (value.length < 4) return false;
    return value.codeUnitAt(0) == 47 &&
        value.codeUnitAt(1) == 97 &&
        value.codeUnitAt(2) == 112 &&
        value.codeUnitAt(3) == 105 &&
        (value.length == 4 || value.codeUnitAt(4) == 47);
  }

  Future<Map<String, dynamic>> _postFirstAvailable(
    List<String> paths,
    Object? body,
  ) {
    return _sendFirstAvailable(const ['POST'], paths, body, featureName: '账号');
  }

  Future<Map<String, dynamic>> _getFirstAvailable(List<String> paths) async {
    ApiException? last404;
    for (final path in paths) {
      try {
        return await _client.requestWithoutRouteDiagnosis('GET', path);
      } on ApiException catch (e) {
        if (!_isRouteMissing(e)) rethrow;
        last404 = e;
      }
    }
    throw last404 ?? const ApiException('404: 接口不存在');
  }

  Future<Map<String, dynamic>> _sendFirstAvailable(
    List<String> methods,
    List<String> paths,
    Object? body, {
    String featureName = '账号资料',
  }) async {
    ApiException? last404;
    for (final path in paths) {
      for (final method in methods) {
        try {
          return switch (method) {
            'POST' => await _client.requestWithoutRouteDiagnosis(
              'POST',
              path,
              body,
            ),
            'PUT' => await _client.requestWithoutRouteDiagnosis(
              'PUT',
              path,
              body,
            ),
            'PATCH' => await _client.requestWithoutRouteDiagnosis(
              'PATCH',
              path,
              body,
            ),
            _ => await _client.requestWithoutRouteDiagnosis(method, path, body),
          };
        } on ApiException catch (e) {
          if (!_isRouteMissing(e)) rethrow;
          last404 = e;
        }
      }
    }
    throw await _client.missingRoutesException(
      featureName: featureName,
      paths: paths,
      fallback: last404,
    );
  }

  Future<Map<String, dynamic>> _uploadFirstAvailable(
    List<String> paths, {
    required String fieldName,
    List<String> fieldNameFallbacks = const [],
    required String filename,
    required Uint8List bytes,
    String featureName = '文件上传',
  }) async {
    ApiException? last404;
    ApiException? lastRecoverableUploadError;
    final fieldNames = [
      fieldName,
      for (final fallback in fieldNameFallbacks)
        if (fallback != fieldName) fallback,
    ];
    for (final path in paths) {
      for (final method in const ['POST', 'PATCH', 'PUT']) {
        for (final uploadFieldName in fieldNames) {
          try {
            return await _client.uploadBytes(
              path,
              method: method,
              fieldName: uploadFieldName,
              filename: filename,
              bytes: bytes,
              diagnoseMissingRoute: false,
            );
          } on ApiException catch (e) {
            if (_isRouteMissing(e)) {
              last404 = e;
              break;
            }
            if (_isRecoverableUploadFieldError(e)) {
              lastRecoverableUploadError = e;
              continue;
            }
            rethrow;
          }
        }
      }
    }
    if (lastRecoverableUploadError != null) throw lastRecoverableUploadError;
    throw await _client.missingRoutesException(
      featureName: featureName,
      paths: paths,
      fallback: last404,
    );
  }

  int _intField(Map<String, dynamic> data, String key, int fallback) {
    if (!data.containsKey(key)) return fallback;
    final value = data[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
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

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

List<String> _stringListFromJson(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

bool _authStatesEqual(AuthState left, AuthState right) {
  return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

bool _isRouteMissing(ApiException error) {
  final message = error.message.trimLeft();
  if (message.startsWith('405:')) {
    final detail = message.substring(4).split('\n').first.trim().toLowerCase();
    return detail == 'method not allowed' ||
        detail == '{"detail":"method not allowed"}';
  }
  if (!message.startsWith('404:')) return false;
  final detail = message.substring(4).split('\n').first.trim().toLowerCase();
  return detail == 'not found' ||
      detail == '{"detail":"not found"}' ||
      detail == '接口不存在' ||
      detail == 'route not found';
}

bool _isRecoverableUploadFieldError(ApiException error) {
  final message = error.message.trim().toLowerCase();
  if (!(message.startsWith('400:') || message.startsWith('422:'))) {
    return false;
  }
  return message.contains('头像文件不能为空') ||
      message.contains('file required') ||
      message.contains('field required') ||
      message.contains('missing field') ||
      message.contains('missing required');
}

bool _isAuthExpired(ApiException error) {
  final message = error.message.trim().toLowerCase();
  return message.startsWith('401:') ||
      message.startsWith('403:') ||
      message.contains('token expired') ||
      message.contains('invalid token') ||
      message.contains('account disabled') ||
      message.contains('user not found') ||
      message.contains('账号已禁用') ||
      message.contains('用户不存在') ||
      message.contains('登录已过期');
}

void _throwIfEmailCodeNotDelivered(Map<String, dynamic> result) {
  if (result['sent'] != false || _nonEmptyString(result['dev_code']) != null) {
    return;
  }
  final message =
      _nonEmptyString(result['message']) ??
      _nonEmptyString(result['detail']) ??
      '验证码邮件发送失败，请稍后重试或联系管理员检查邮箱服务。';
  throw ApiException(message);
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
