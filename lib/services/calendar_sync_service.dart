/// 第三方日历 ICS 订阅服务。
///
/// 支持只读订阅符合 RFC 5545 的 .ics URL。覆盖 Google Calendar Public iCal、
/// Outlook Public Subscribe、CalDAV 服务器 export 端点、企业 iCal feeds。
///
/// 设计：
/// - 后台 HTTP GET → 解析 VEVENT → 转换为本地 CalendarEvent 视图模型。
/// - 不写入 Todo/Goal 等原始模块；只把订阅事件并入日历聚合。
/// - 失败优雅降级；保留上次缓存。
/// - 不做双向同步；写操作（创建/编辑日程）仍在多仪本地。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calendar_event.dart';
import 'caldav_writer.dart';

class IcsSubscription {
  final String id;
  final String name;
  final String url;
  final int colorValue;
  final bool enabled;
  final DateTime? lastSyncedAt;

  const IcsSubscription({
    required this.id,
    required this.name,
    required this.url,
    this.colorValue = 0xFF42A5F5,
    this.enabled = true,
    this.lastSyncedAt,
  });

  IcsSubscription copyWith({
    String? name,
    String? url,
    int? colorValue,
    bool? enabled,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) => IcsSubscription(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    colorValue: colorValue ?? this.colorValue,
    enabled: enabled ?? this.enabled,
    lastSyncedAt: clearLastSyncedAt
        ? null
        : (lastSyncedAt ?? this.lastSyncedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'colorValue': colorValue,
    'enabled': enabled,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  factory IcsSubscription.fromJson(Map<String, dynamic> json) =>
      IcsSubscription(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '订阅',
        url: json['url']?.toString() ?? '',
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF42A5F5,
        enabled: json['enabled'] != false,
        lastSyncedAt: DateTime.tryParse(json['lastSyncedAt']?.toString() ?? ''),
      );
}

class CalDavWriteTarget {
  final String collectionUrl;
  final String authorizationHeader;
  final bool enabled;
  final CalDavConflictPolicy conflictPolicy;
  final DateTime? lastTestedAt;

  const CalDavWriteTarget({
    required this.collectionUrl,
    required this.authorizationHeader,
    this.enabled = false,
    this.conflictPolicy = CalDavConflictPolicy.skipRemoteChanges,
    this.lastTestedAt,
  });

  bool get isConfigured =>
      collectionUrl.trim().isNotEmpty && authorizationHeader.trim().isNotEmpty;

  CalDavWriteTarget copyWith({
    String? collectionUrl,
    String? authorizationHeader,
    bool? enabled,
    CalDavConflictPolicy? conflictPolicy,
    DateTime? lastTestedAt,
    bool clearLastTestedAt = false,
  }) => CalDavWriteTarget(
    collectionUrl: collectionUrl ?? this.collectionUrl,
    authorizationHeader: authorizationHeader ?? this.authorizationHeader,
    enabled: enabled ?? this.enabled,
    conflictPolicy: conflictPolicy ?? this.conflictPolicy,
    lastTestedAt: clearLastTestedAt
        ? null
        : (lastTestedAt ?? this.lastTestedAt),
  );

  Map<String, dynamic> toJson() => {
    'collectionUrl': collectionUrl,
    'authorizationHeader': authorizationHeader,
    'enabled': enabled,
    'conflictPolicy': conflictPolicy.name,
    'lastTestedAt': lastTestedAt?.toIso8601String(),
  };

  factory CalDavWriteTarget.fromJson(Map<String, dynamic> json) =>
      CalDavWriteTarget(
        collectionUrl: json['collectionUrl']?.toString() ?? '',
        authorizationHeader: json['authorizationHeader']?.toString() ?? '',
        enabled: json['enabled'] == true,
        conflictPolicy: CalDavConflictPolicy.fromName(
          json['conflictPolicy']?.toString(),
        ),
        lastTestedAt: DateTime.tryParse(json['lastTestedAt']?.toString() ?? ''),
      );
}

enum CalDavConflictPolicy {
  skipRemoteChanges,
  overwriteRemote;

  static CalDavConflictPolicy fromName(String? name) {
    return CalDavConflictPolicy.values.firstWhere(
      (policy) => policy.name == name,
      orElse: () => CalDavConflictPolicy.skipRemoteChanges,
    );
  }
}

class CalDavWriteConflict {
  final String uid;
  final String title;
  final String reason;

  const CalDavWriteConflict({
    required this.uid,
    required this.title,
    required this.reason,
  });
}

class CalDavCredentialHelper {
  const CalDavCredentialHelper._();

  static const iCloudCollectionUrlHint =
      'https://pXX-caldav.icloud.com/<dsid>/calendars/<calendar-id>/';

  static const iCloudSetupCopy =
      '使用 Apple ID 和 App 专用密码生成 Basic Authorization，'
      '集合 URL 需填 iCloud 日历的 CalDAV calendar collection 地址。';

  static String basicAuthorizationHeader({
    required String username,
    required String password,
  }) {
    final raw = '${username.trim()}:${password.trim()}';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }
}

enum OAuthCalendarProvider {
  google,
  outlook;

  String get label => switch (this) {
    OAuthCalendarProvider.google => 'Google Calendar',
    OAuthCalendarProvider.outlook => 'Outlook Calendar',
  };

  String get authEndpoint => switch (this) {
    OAuthCalendarProvider.google =>
      'https://accounts.google.com/o/oauth2/v2/auth',
    OAuthCalendarProvider.outlook =>
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
  };

  String get tokenEndpoint => switch (this) {
    OAuthCalendarProvider.google => 'https://oauth2.googleapis.com/token',
    OAuthCalendarProvider.outlook =>
      'https://login.microsoftonline.com/common/oauth2/v2.0/token',
  };

  String get defaultScope => switch (this) {
    OAuthCalendarProvider.google =>
      'https://www.googleapis.com/auth/calendar.readonly',
    OAuthCalendarProvider.outlook => 'offline_access Calendars.Read',
  };

  static OAuthCalendarProvider fromName(String? name) {
    return OAuthCalendarProvider.values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => OAuthCalendarProvider.google,
    );
  }
}

class OAuthCalendarAccount {
  final String id;
  final OAuthCalendarProvider provider;
  final String displayName;
  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final String calendarId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String scope;
  final int colorValue;
  final bool enabled;
  final DateTime? lastSyncedAt;

  OAuthCalendarAccount({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.clientId,
    required this.redirectUri,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.clientSecret = '',
    this.calendarId = 'primary',
    String? scope,
    this.colorValue = 0xFF5E97F6,
    this.enabled = true,
    this.lastSyncedAt,
  }) : scope = scope ?? provider.defaultScope;

  OAuthCalendarAccount copyWith({
    String? displayName,
    String? clientId,
    String? clientSecret,
    String? redirectUri,
    String? calendarId,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? scope,
    int? colorValue,
    bool? enabled,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) => OAuthCalendarAccount(
    id: id,
    provider: provider,
    displayName: displayName ?? this.displayName,
    clientId: clientId ?? this.clientId,
    clientSecret: clientSecret ?? this.clientSecret,
    redirectUri: redirectUri ?? this.redirectUri,
    calendarId: calendarId ?? this.calendarId,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    expiresAt: expiresAt ?? this.expiresAt,
    scope: scope ?? this.scope,
    colorValue: colorValue ?? this.colorValue,
    enabled: enabled ?? this.enabled,
    lastSyncedAt: clearLastSyncedAt
        ? null
        : (lastSyncedAt ?? this.lastSyncedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider.name,
    'displayName': displayName,
    'clientId': clientId,
    'clientSecret': clientSecret,
    'redirectUri': redirectUri,
    'calendarId': calendarId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'scope': scope,
    'colorValue': colorValue,
    'enabled': enabled,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  factory OAuthCalendarAccount.fromJson(Map<String, dynamic> json) =>
      OAuthCalendarAccount(
        id: json['id']?.toString() ?? '',
        provider: OAuthCalendarProvider.fromName(json['provider']?.toString()),
        displayName: json['displayName']?.toString() ?? 'OAuth 日历',
        clientId: json['clientId']?.toString() ?? '',
        clientSecret: json['clientSecret']?.toString() ?? '',
        redirectUri:
            json['redirectUri']?.toString() ?? 'duoyi://oauth/calendar',
        calendarId: json['calendarId']?.toString() ?? 'primary',
        accessToken: json['accessToken']?.toString() ?? '',
        refreshToken: json['refreshToken']?.toString() ?? '',
        expiresAt:
            DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        scope: json['scope']?.toString(),
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF5E97F6,
        enabled: json['enabled'] != false,
        lastSyncedAt: DateTime.tryParse(json['lastSyncedAt']?.toString() ?? ''),
      );
}

class OAuthCalendarClient {
  const OAuthCalendarClient._();

  static String generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(48, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String codeChallengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Uri authorizationUri({
    required OAuthCalendarProvider provider,
    required String clientId,
    required String redirectUri,
    required String codeVerifier,
    String? state,
    String? scope,
  }) {
    final params = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope ?? provider.defaultScope,
      'code_challenge': codeChallengeFor(codeVerifier),
      'code_challenge_method': 'S256',
    };
    if (state != null && state.isNotEmpty) params['state'] = state;
    if (provider == OAuthCalendarProvider.google) {
      params['access_type'] = 'offline';
      params['prompt'] = 'consent';
      params['include_granted_scopes'] = 'true';
    } else {
      params['response_mode'] = 'query';
      params['prompt'] = 'select_account';
    }
    return Uri.parse(provider.authEndpoint).replace(queryParameters: params);
  }

  static Future<OAuthCalendarAccount> exchangeAuthorizationCode({
    required OAuthCalendarProvider provider,
    required String displayName,
    required String clientId,
    required String redirectUri,
    required String authorizationCode,
    required String codeVerifier,
    String clientSecret = '',
    String calendarId = 'primary',
    int colorValue = 0xFF5E97F6,
    http.Client? client,
  }) async {
    final token = await _postToken(
      provider: provider,
      body: {
        'client_id': clientId,
        if (clientSecret.trim().isNotEmpty)
          'client_secret': clientSecret.trim(),
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code': _extractAuthorizationCode(authorizationCode),
        'code_verifier': codeVerifier,
      },
      client: client,
    );
    final refreshToken = token['refresh_token']?.toString() ?? '';
    if (refreshToken.isEmpty) {
      throw const FormatException(
        'OAuth 响应缺少 refresh_token，请确认已请求 offline access',
      );
    }
    return OAuthCalendarAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      provider: provider,
      displayName: displayName,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      calendarId: calendarId.trim().isEmpty ? 'primary' : calendarId.trim(),
      accessToken: token['access_token']?.toString() ?? '',
      refreshToken: refreshToken,
      expiresAt: _expiresAt(token),
      scope: token['scope']?.toString() ?? provider.defaultScope,
      colorValue: colorValue,
    );
  }

  static Future<OAuthCalendarAccount> refreshAccessToken(
    OAuthCalendarAccount account, {
    http.Client? client,
  }) async {
    final token = await _postToken(
      provider: account.provider,
      body: {
        'client_id': account.clientId,
        if (account.clientSecret.trim().isNotEmpty)
          'client_secret': account.clientSecret.trim(),
        'grant_type': 'refresh_token',
        'refresh_token': account.refreshToken,
      },
      client: client,
    );
    return account.copyWith(
      accessToken: token['access_token']?.toString() ?? account.accessToken,
      refreshToken: token['refresh_token']?.toString() ?? account.refreshToken,
      expiresAt: _expiresAt(token),
      scope: token['scope']?.toString() ?? account.scope,
    );
  }

  static Future<Map<String, dynamic>> _postToken({
    required OAuthCalendarProvider provider,
    required Map<String, String> body,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final resp = await httpClient
          .post(
            Uri.parse(provider.tokenEndpoint),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('OAuth token failed: ${resp.statusCode} ${resp.body}');
      }
      return Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static DateTime _expiresAt(Map<String, dynamic> token) {
    final seconds = (token['expires_in'] as num?)?.toInt() ?? 3600;
    return DateTime.now().add(Duration(seconds: seconds - 60));
  }

  static String _extractAuthorizationCode(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.queryParameters['code']?.isNotEmpty == true) {
      return uri.queryParameters['code']!;
    }
    return text;
  }
}

class CalendarSyncProvider extends ChangeNotifier {
  static const _subscriptionsKey = 'duoyi_ics_subscriptions_v1';
  static const _eventsKeyPrefix = 'duoyi_ics_events_';
  static const _oauthAccountsKey = 'duoyi_oauth_calendar_accounts_v1';
  static const _oauthEventsKeyPrefix = 'duoyi_oauth_calendar_events_';
  static const _pendingOAuthAuthorizationKey =
      'duoyi_oauth_calendar_pending_authorization_v1';
  static const _calDavWriteTargetKey = 'duoyi_caldav_write_target_v1';
  static const _calDavPushedUidsKey = 'duoyi_caldav_pushed_uids_v1';
  static const _calDavPushedEtagsKey = 'duoyi_caldav_pushed_etags_v1';

  final List<IcsSubscription> _subscriptions = [];
  final List<OAuthCalendarAccount> _oauthAccounts = [];
  final Map<String, List<CalendarEvent>> _eventsBySubscription = {};
  final Map<String, List<CalendarEvent>> _eventsByOAuthAccount = {};
  CalDavWriteTarget? _writeTarget;
  bool _syncing = false;
  bool _testingWriteTarget = false;
  String? _lastError;
  final List<CalDavWriteConflict> _lastCalDavConflicts = [];

  List<IcsSubscription> get subscriptions =>
      List<IcsSubscription>.unmodifiable(_subscriptions);

  List<OAuthCalendarAccount> get oauthAccounts =>
      List<OAuthCalendarAccount>.unmodifiable(_oauthAccounts);

  bool get isSyncing => _syncing;

  bool get isTestingWriteTarget => _testingWriteTarget;

  CalDavWriteTarget? get writeTarget => _writeTarget;

  String? get lastError => _lastError;

  List<CalDavWriteConflict> get lastCalDavConflicts =>
      List<CalDavWriteConflict>.unmodifiable(_lastCalDavConflicts);

  /// 所有订阅汇总后的只读事件。
  List<CalendarEvent> allEvents() {
    final out = <CalendarEvent>[];
    for (final list in _eventsBySubscription.values) {
      out.addAll(list);
    }
    for (final list in _eventsByOAuthAccount.values) {
      out.addAll(list);
    }
    return out;
  }

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subscriptionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _subscriptions
          ..clear()
          ..addAll(
            list.whereType<Map>().map(
              (m) => IcsSubscription.fromJson(Map<String, dynamic>.from(m)),
            ),
          );
      } catch (e) {
        debugPrint('[CalendarSync] load subscriptions failed: $e');
      }
    }
    for (final sub in _subscriptions) {
      final cached = prefs.getString('$_eventsKeyPrefix${sub.id}');
      if (cached == null) continue;
      try {
        final list = jsonDecode(cached) as List;
        _eventsBySubscription[sub.id] = list
            .whereType<Map>()
            .map(
              (m) => _calendarEventFromJson(
                Map<String, dynamic>.from(m),
                Color(sub.colorValue),
              ),
            )
            .whereType<CalendarEvent>()
            .toList();
      } catch (e) {
        debugPrint('[CalendarSync] load cached events failed: $e');
      }
    }
    final rawOAuthAccounts = prefs.getString(_oauthAccountsKey);
    if (rawOAuthAccounts != null && rawOAuthAccounts.isNotEmpty) {
      try {
        final list = jsonDecode(rawOAuthAccounts) as List;
        _oauthAccounts
          ..clear()
          ..addAll(
            list.whereType<Map>().map(
              (m) =>
                  OAuthCalendarAccount.fromJson(Map<String, dynamic>.from(m)),
            ),
          );
      } catch (e) {
        debugPrint('[CalendarSync] load OAuth calendar accounts failed: $e');
      }
    }
    for (final account in _oauthAccounts) {
      final cached = prefs.getString('$_oauthEventsKeyPrefix${account.id}');
      if (cached == null) continue;
      try {
        final list = jsonDecode(cached) as List;
        _eventsByOAuthAccount[account.id] = list
            .whereType<Map>()
            .map(
              (m) => _calendarEventFromJson(
                Map<String, dynamic>.from(m),
                Color(account.colorValue),
              ),
            )
            .whereType<CalendarEvent>()
            .toList();
      } catch (e) {
        debugPrint('[CalendarSync] load cached OAuth events failed: $e');
      }
    }
    final rawWriteTarget = prefs.getString(_calDavWriteTargetKey);
    if (rawWriteTarget != null && rawWriteTarget.isNotEmpty) {
      try {
        _writeTarget = CalDavWriteTarget.fromJson(
          Map<String, dynamic>.from(jsonDecode(rawWriteTarget) as Map),
        );
      } catch (e) {
        debugPrint('[CalendarSync] load CalDAV write target failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> addSubscription(IcsSubscription sub) async {
    _subscriptions.add(sub);
    await _save();
    notifyListeners();
  }

  Future<void> updateSubscription(IcsSubscription sub) async {
    final i = _subscriptions.indexWhere((s) => s.id == sub.id);
    if (i < 0) return;
    _subscriptions[i] = sub;
    await _save();
    notifyListeners();
  }

  Future<void> removeSubscription(String id) async {
    _subscriptions.removeWhere((s) => s.id == id);
    _eventsBySubscription.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_eventsKeyPrefix$id');
    await _save();
    notifyListeners();
  }

  Uri buildOAuthAuthorizationUri({
    required OAuthCalendarProvider provider,
    required String clientId,
    required String redirectUri,
    required String codeVerifier,
    String? state,
    String? scope,
  }) {
    return OAuthCalendarClient.authorizationUri(
      provider: provider,
      clientId: clientId,
      redirectUri: redirectUri,
      codeVerifier: codeVerifier,
      state: state,
      scope: scope,
    );
  }

  Future<OAuthCalendarAccount> addOAuthAccountFromCode({
    required OAuthCalendarProvider provider,
    required String displayName,
    required String clientId,
    required String redirectUri,
    required String authorizationCode,
    required String codeVerifier,
    String clientSecret = '',
    String calendarId = 'primary',
    int colorValue = 0xFF5E97F6,
  }) async {
    final account = await OAuthCalendarClient.exchangeAuthorizationCode(
      provider: provider,
      displayName: displayName,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      authorizationCode: authorizationCode,
      codeVerifier: codeVerifier,
      calendarId: calendarId,
      colorValue: colorValue,
    );
    _oauthAccounts.add(account);
    await _saveOAuthAccounts();
    notifyListeners();
    await _syncOAuthAccount(account);
    notifyListeners();
    return account;
  }

  Future<void> savePendingOAuthAuthorization({
    required OAuthCalendarProvider provider,
    required String displayName,
    required String clientId,
    required String clientSecret,
    required String redirectUri,
    required String calendarId,
    required String codeVerifier,
    required String state,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingOAuthAuthorizationKey,
      jsonEncode({
        'provider': provider.name,
        'displayName': displayName,
        'clientId': clientId,
        'clientSecret': clientSecret,
        'redirectUri': redirectUri,
        'calendarId': calendarId,
        'codeVerifier': codeVerifier,
        'state': state,
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<Map<String, String>> loadPendingOAuthAuthorization() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingOAuthAuthorizationKey);
    if (raw == null || raw.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> clearPendingOAuthAuthorization() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingOAuthAuthorizationKey);
  }

  Future<void> updateOAuthAccount(OAuthCalendarAccount account) async {
    final i = _oauthAccounts.indexWhere((a) => a.id == account.id);
    if (i < 0) return;
    _oauthAccounts[i] = account;
    await _saveOAuthAccounts();
    notifyListeners();
  }

  Future<void> removeOAuthAccount(String id) async {
    _oauthAccounts.removeWhere((a) => a.id == id);
    _eventsByOAuthAccount.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_oauthEventsKeyPrefix$id');
    await _saveOAuthAccounts();
    notifyListeners();
  }

  Future<void> saveWriteTarget(CalDavWriteTarget target) async {
    _writeTarget = target;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_calDavWriteTargetKey, jsonEncode(target.toJson()));
    notifyListeners();
  }

  Future<void> clearWriteTarget() async {
    _writeTarget = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_calDavWriteTargetKey);
    notifyListeners();
  }

  Future<void> testWriteTarget() async {
    final target = _writeTarget;
    if (target == null || !target.isConfigured) {
      _lastError = 'CalDAV 写回目标未配置';
      notifyListeners();
      return;
    }
    if (_testingWriteTarget) return;
    _testingWriteTarget = true;
    _lastError = null;
    notifyListeners();
    try {
      final writer = HttpCalDavWriter(
        collectionUrl: target.collectionUrl,
        headers: <String, String>{'Authorization': target.authorizationHeader},
      );
      final now = DateTime.now().toUtc();
      final uid = await writer.createEvent(
        summary: '多仪 CalDAV 写回测试',
        start: now.add(const Duration(minutes: 5)),
        end: now.add(const Duration(minutes: 10)),
        description: '这是一条自动创建后立即删除的连通性测试事件。',
      );
      await writer.deleteEvent(uid);
      await saveWriteTarget(
        target.copyWith(enabled: true, lastTestedAt: DateTime.now()),
      );
    } catch (e, st) {
      debugPrint('[CalendarSync] CalDAV write target test failed: $e\n$st');
      _lastError = e.toString();
    } finally {
      _testingWriteTarget = false;
      notifyListeners();
    }
  }

  Future<int> pushEventsToCalDav(Iterable<CalendarEvent> events) async {
    final target = _writeTarget;
    if (target == null || !target.isConfigured) {
      _lastError = 'CalDAV 写回目标未配置';
      _lastCalDavConflicts.clear();
      notifyListeners();
      return 0;
    }
    _lastError = null;
    _lastCalDavConflicts.clear();
    notifyListeners();
    final writer = HttpCalDavWriter(
      collectionUrl: target.collectionUrl,
      headers: <String, String>{'Authorization': target.authorizationHeader},
    );
    var count = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previousUids =
          prefs.getStringList(_calDavPushedUidsKey)?.toSet() ?? <String>{};
      final previousEtags = _decodeStringMap(
        prefs.getString(_calDavPushedEtagsKey),
      );
      final currentUids = <String>{};
      final currentEtags = <String, String>{};
      for (final event in events) {
        final start = _eventStart(event);
        final end = _eventEnd(event, start);
        final uid = _calDavUidFor(event);
        final previousEtag = previousEtags[uid];
        if (target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges &&
            previousEtag != null) {
          final remoteEtag = await writer.remoteEtag(uid);
          if (remoteEtag != null && remoteEtag != previousEtag) {
            _lastCalDavConflicts.add(
              CalDavWriteConflict(
                uid: uid,
                title: event.title,
                reason: '远端事件已被修改，已跳过本地写回',
              ),
            );
            currentUids.add(uid);
            currentEtags[uid] = previousEtag;
            continue;
          }
        }
        await writer.updateEvent(
          uid: uid,
          summary: event.title,
          start: start,
          end: end,
          description: event.subtitle,
          ifMatch:
              target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges
              ? previousEtag
              : null,
        );
        final nextEtag = await writer.remoteEtag(uid);
        currentUids.add(uid);
        if (nextEtag != null) currentEtags[uid] = nextEtag;
        count++;
      }
      for (final staleUid in previousUids.difference(currentUids)) {
        final previousEtag = previousEtags[staleUid];
        if (target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges &&
            previousEtag != null) {
          final remoteEtag = await writer.remoteEtag(staleUid);
          if (remoteEtag != null && remoteEtag != previousEtag) {
            _lastCalDavConflicts.add(
              CalDavWriteConflict(
                uid: staleUid,
                title: staleUid,
                reason: '远端事件已被修改，已跳过删除',
              ),
            );
            currentUids.add(staleUid);
            currentEtags[staleUid] = previousEtag;
            continue;
          }
        }
        await writer.deleteEvent(
          staleUid,
          ifMatch:
              target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges
              ? previousEtag
              : null,
        );
      }
      await prefs.setStringList(
        _calDavPushedUidsKey,
        currentUids.toList()..sort(),
      );
      await prefs.setString(_calDavPushedEtagsKey, jsonEncode(currentEtags));
      await saveWriteTarget(
        target.copyWith(enabled: true, lastTestedAt: DateTime.now()),
      );
      if (_lastCalDavConflicts.isNotEmpty) notifyListeners();
      return count;
    } on CalDavConflictException catch (e) {
      _lastCalDavConflicts.add(
        CalDavWriteConflict(uid: e.uid, title: e.uid, reason: '远端事件已变更'),
      );
      notifyListeners();
      return count;
    } catch (e, st) {
      debugPrint('[CalendarSync] push CalDAV events failed: $e\n$st');
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// 拉取所有启用的订阅，更新缓存。
  Future<void> syncAll() async {
    if (_syncing) return;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      for (final sub in _subscriptions.where((s) => s.enabled)) {
        await _syncOne(sub);
      }
      for (final account in _oauthAccounts.where((a) => a.enabled)) {
        await _syncOAuthAccount(account);
      }
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncOne(IcsSubscription sub) async {
    try {
      final resp = await http
          .get(Uri.parse(sub.url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('[CalendarSync] ${sub.url} returned ${resp.statusCode}');
        return;
      }
      final events = IcsParser.parse(
        resp.body,
        subscriptionId: sub.id,
        color: Color(sub.colorValue),
      );
      _eventsBySubscription[sub.id] = events;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_eventsKeyPrefix${sub.id}',
        jsonEncode(events.map(_calendarEventToJson).toList()),
      );
      final idx = _subscriptions.indexWhere((s) => s.id == sub.id);
      if (idx >= 0) {
        _subscriptions[idx] = _subscriptions[idx].copyWith(
          lastSyncedAt: DateTime.now(),
        );
        await _save();
      }
    } catch (e, st) {
      debugPrint('[CalendarSync] sync ${sub.url} failed: $e\n$st');
      _lastError = e.toString();
    }
  }

  Future<void> _syncOAuthAccount(OAuthCalendarAccount account) async {
    try {
      var nextAccount = account;
      if (account.expiresAt.isBefore(
        DateTime.now().add(const Duration(minutes: 2)),
      )) {
        nextAccount = await OAuthCalendarClient.refreshAccessToken(account);
        final i = _oauthAccounts.indexWhere((a) => a.id == account.id);
        if (i >= 0) _oauthAccounts[i] = nextAccount;
        await _saveOAuthAccounts();
      }
      final events = await _fetchOAuthEvents(nextAccount);
      _eventsByOAuthAccount[nextAccount.id] = events;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_oauthEventsKeyPrefix${nextAccount.id}',
        jsonEncode(events.map(_calendarEventToJson).toList()),
      );
      final idx = _oauthAccounts.indexWhere((a) => a.id == nextAccount.id);
      if (idx >= 0) {
        _oauthAccounts[idx] = nextAccount.copyWith(
          lastSyncedAt: DateTime.now(),
        );
        await _saveOAuthAccounts();
      }
    } catch (e, st) {
      debugPrint(
        '[CalendarSync] sync OAuth ${account.provider.name}/${account.displayName} failed: $e\n$st',
      );
      _lastError = e.toString();
    }
  }

  Future<List<CalendarEvent>> _fetchOAuthEvents(
    OAuthCalendarAccount account,
  ) async {
    final now = DateTime.now();
    final timeMin = now.subtract(const Duration(days: 30)).toUtc();
    final timeMax = now.add(const Duration(days: 180)).toUtc();
    final uri = account.provider == OAuthCalendarProvider.google
        ? _googleEventsUri(account, timeMin, timeMax)
        : _outlookEventsUri(account, timeMin, timeMax);
    final resp = await http
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer ${account.accessToken}',
            'Accept': 'application/json',
            if (account.provider == OAuthCalendarProvider.outlook)
              'Prefer': 'outlook.timezone="UTC"',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        '${account.provider.label} events failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final decoded = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    final items = (decoded['items'] ?? decoded['value']) as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => account.provider == OAuthCalendarProvider.google
              ? _googleEventToCalendarEvent(
                  Map<String, dynamic>.from(item),
                  account,
                )
              : _outlookEventToCalendarEvent(
                  Map<String, dynamic>.from(item),
                  account,
                ),
        )
        .whereType<CalendarEvent>()
        .toList();
  }

  Uri _googleEventsUri(
    OAuthCalendarAccount account,
    DateTime timeMin,
    DateTime timeMax,
  ) {
    return Uri(
      scheme: 'https',
      host: 'www.googleapis.com',
      pathSegments: [
        'calendar',
        'v3',
        'calendars',
        account.calendarId.trim().isEmpty ? 'primary' : account.calendarId,
        'events',
      ],
      queryParameters: {
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'timeMin': timeMin.toIso8601String(),
        'timeMax': timeMax.toIso8601String(),
        'maxResults': '2500',
      },
    );
  }

  Uri _outlookEventsUri(
    OAuthCalendarAccount account,
    DateTime timeMin,
    DateTime timeMax,
  ) {
    final calendarId = account.calendarId.trim();
    return Uri(
      scheme: 'https',
      host: 'graph.microsoft.com',
      pathSegments: calendarId.isEmpty || calendarId == 'primary'
          ? ['v1.0', 'me', 'calendar', 'calendarView']
          : ['v1.0', 'me', 'calendars', calendarId, 'calendarView'],
      queryParameters: {
        'startDateTime': timeMin.toIso8601String(),
        'endDateTime': timeMax.toIso8601String(),
        r'$top': '1000',
        r'$orderby': 'start/dateTime',
      },
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _subscriptionsKey,
      jsonEncode(_subscriptions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _saveOAuthAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _oauthAccountsKey,
      jsonEncode(_oauthAccounts.map((a) => a.toJson()).toList()),
    );
  }

  DateTime _eventStart(CalendarEvent event) {
    final time = event.time;
    if (time == null) {
      return DateTime(event.date.year, event.date.month, event.date.day);
    }
    return DateTime(
      event.date.year,
      event.date.month,
      event.date.day,
      time.hour,
      time.minute,
    );
  }

  DateTime _eventEnd(CalendarEvent event, DateTime start) {
    if (event.endDate != null) {
      final end = event.endDate!;
      return DateTime(end.year, end.month, end.day, end.hour, end.minute);
    }
    return start.add(
      event.time == null ? const Duration(days: 1) : const Duration(hours: 1),
    );
  }

  String _calDavUidFor(CalendarEvent event) {
    final raw = 'duoyi-${event.id}-${event.type.name}';
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    return '$safe@duoyi.local';
  }
}

Map<String, String> _decodeStringMap(String? raw) {
  if (raw == null || raw.isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, String>{};
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  } catch (_) {
    return <String, String>{};
  }
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

Map<String, Object?> _calendarEventToJson(CalendarEvent e) => {
  'id': e.id,
  'title': e.title,
  'date': e.date.toIso8601String(),
  'endDate': e.endDate?.toIso8601String(),
  'subtitle': e.subtitle,
  'colorValue': e.color.toARGB32(),
  'sourceId': e.sourceId,
  'timeHour': e.time?.hour,
  'timeMinute': e.time?.minute,
};

CalendarEvent? _calendarEventFromJson(Map<String, dynamic> json, Color color) {
  try {
    final id = json['id']?.toString() ?? '';
    final isExternalCalendarEvent =
        id.startsWith('ics_') || id.startsWith('oauth_');
    return CalendarEvent(
      id: id,
      title: json['title']?.toString() ?? '',
      date: DateTime.parse(json['date'] as String),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
      subtitle: json['subtitle']?.toString(),
      type: CalendarEventType.timeEntry,
      color: color,
      sourceId: isExternalCalendarEvent ? null : json['sourceId']?.toString(),
      time: (json['timeHour'] != null && json['timeMinute'] != null)
          ? TimeOfDay(
              hour: (json['timeHour'] as num).toInt(),
              minute: (json['timeMinute'] as num).toInt(),
            )
          : null,
    );
  } catch (_) {
    return null;
  }
}

CalendarEvent? _googleEventToCalendarEvent(
  Map<String, dynamic> item,
  OAuthCalendarAccount account,
) {
  if (item['status']?.toString() == 'cancelled') return null;
  final eventId = item['id']?.toString() ?? '';
  if (eventId.isEmpty) return null;
  final startMap = _asStringMap(item['start']);
  final endMap = _asStringMap(item['end']);
  final start = _parseOAuthDateTime(startMap['dateTime'] ?? startMap['date']);
  if (start == null) return null;
  final end = _parseOAuthDateTime(endMap['dateTime'] ?? endMap['date']);
  final allDay = startMap['dateTime'] == null;
  final location = item['location']?.toString().trim() ?? '';
  final organizer = _asStringMap(item['organizer'])['displayName'] ?? '';
  final subtitle = [
    account.provider.label,
    if (location.isNotEmpty) location,
    if (organizer.isNotEmpty) organizer,
  ].join(' · ');
  final title = item['summary']?.toString().trim();
  return CalendarEvent(
    id: 'oauth_${account.provider.name}_${account.id}_$eventId',
    title: title == null || title.isEmpty ? '(无标题)' : title,
    date: start,
    endDate: end,
    subtitle: subtitle,
    type: CalendarEventType.timeEntry,
    color: Color(account.colorValue),
    time: allDay ? null : TimeOfDay.fromDateTime(start),
  );
}

CalendarEvent? _outlookEventToCalendarEvent(
  Map<String, dynamic> item,
  OAuthCalendarAccount account,
) {
  if (item['isCancelled'] == true) return null;
  final eventId = item['id']?.toString() ?? '';
  if (eventId.isEmpty) return null;
  final startMap = _asStringMap(item['start']);
  final endMap = _asStringMap(item['end']);
  final start = _parseOAuthDateTime(
    startMap['dateTime'],
    timeZone: startMap['timeZone']?.toString(),
  );
  if (start == null) return null;
  final end = _parseOAuthDateTime(
    endMap['dateTime'],
    timeZone: endMap['timeZone']?.toString(),
  );
  final isAllDay = item['isAllDay'] == true;
  final location = _asStringMap(item['location'])['displayName']?.trim() ?? '';
  final organizer =
      _asStringMap(_asStringMap(item['organizer'])['emailAddress'])['name'] ??
      '';
  final subtitle = [
    account.provider.label,
    if (location.isNotEmpty) location,
    if (organizer.isNotEmpty) organizer,
  ].join(' · ');
  final title = item['subject']?.toString().trim();
  return CalendarEvent(
    id: 'oauth_${account.provider.name}_${account.id}_$eventId',
    title: title == null || title.isEmpty ? '(无标题)' : title,
    date: start,
    endDate: end,
    subtitle: subtitle,
    type: CalendarEventType.timeEntry,
    color: Color(account.colorValue),
    time: isAllDay ? null : TimeOfDay.fromDateTime(start),
  );
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

DateTime? _parseOAuthDateTime(Object? value, {String? timeZone}) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final hasOffset = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(raw);
    final shouldTreatAsUtc =
        !hasOffset && (timeZone ?? '').toUpperCase() == 'UTC';
    final parsed = DateTime.parse(shouldTreatAsUtc ? '${raw}Z' : raw);
    return parsed.isUtc ? parsed.toLocal() : parsed;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// ICS parser (RFC 5545 subset)
// ---------------------------------------------------------------------------

class IcsParser {
  IcsParser._();

  static List<CalendarEvent> parse(
    String body, {
    required String subscriptionId,
    required Color color,
  }) {
    // 折行处理：以空格/Tab 开头的下一行属于上一行
    final lines = _unfold(body.split(RegExp(r'\r?\n')));
    final events = <CalendarEvent>[];
    int i = 0;
    while (i < lines.length) {
      if (lines[i].trim().toUpperCase() == 'BEGIN:VEVENT') {
        final endIdx = lines.indexWhere(
          (l) => l.trim().toUpperCase() == 'END:VEVENT',
          i,
        );
        if (endIdx < 0) break;
        final ev = _parseEvent(
          lines.sublist(i + 1, endIdx),
          subscriptionId: subscriptionId,
          color: color,
        );
        if (ev != null) events.add(ev);
        i = endIdx + 1;
      } else {
        i++;
      }
    }
    return events;
  }

  static List<String> _unfold(List<String> raw) {
    final out = <String>[];
    for (final line in raw) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (out.isNotEmpty) {
          out[out.length - 1] = out.last + line.substring(1);
        }
      } else {
        out.add(line);
      }
    }
    return out;
  }

  static CalendarEvent? _parseEvent(
    List<String> body, {
    required String subscriptionId,
    required Color color,
  }) {
    String? uid;
    String? summary;
    String? location;
    DateTime? dtStart;
    DateTime? dtEnd;
    bool allDay = false;
    for (final line in body) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).toUpperCase();
      final value = line.substring(colon + 1);
      if (key == 'UID') {
        uid = value;
      } else if (key == 'SUMMARY') {
        summary = _unescape(value);
      } else if (key == 'LOCATION') {
        location = _unescape(value);
      } else if (key.startsWith('DTSTART')) {
        final pair = _parseDate(key, value);
        dtStart = pair?.value;
        allDay = pair?.allDay ?? false;
      } else if (key.startsWith('DTEND')) {
        final pair = _parseDate(key, value);
        dtEnd = pair?.value;
      }
    }
    if (uid == null || summary == null || dtStart == null) return null;
    return CalendarEvent(
      id: 'ics_${subscriptionId}_$uid',
      title: summary,
      subtitle: location,
      date: dtStart,
      endDate: dtEnd,
      type: CalendarEventType.timeEntry,
      color: color,
      time: allDay ? null : TimeOfDay.fromDateTime(dtStart),
    );
  }

  static String _unescape(String s) {
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', r'\');
  }

  /// 解析 DTSTART / DTEND；支持：
  /// - `YYYYMMDDTHHMMSSZ`（UTC）
  /// - `YYYYMMDDTHHMMSS`（本地）
  /// - `YYYYMMDD`（全天）
  static _DateParse? _parseDate(String key, String value) {
    final raw = value.trim();
    if (raw.length == 8) {
      final y = int.tryParse(raw.substring(0, 4));
      final m = int.tryParse(raw.substring(4, 6));
      final d = int.tryParse(raw.substring(6, 8));
      if (y == null || m == null || d == null) return null;
      return _DateParse(DateTime(y, m, d), true);
    }
    if (raw.length >= 15) {
      final y = int.tryParse(raw.substring(0, 4));
      final mo = int.tryParse(raw.substring(4, 6));
      final d = int.tryParse(raw.substring(6, 8));
      final h = int.tryParse(raw.substring(9, 11));
      final mi = int.tryParse(raw.substring(11, 13));
      final s = int.tryParse(raw.substring(13, 15));
      if (y == null ||
          mo == null ||
          d == null ||
          h == null ||
          mi == null ||
          s == null) {
        return null;
      }
      final isUtc = raw.endsWith('Z');
      final dt = isUtc
          ? DateTime.utc(y, mo, d, h, mi, s).toLocal()
          : DateTime(y, mo, d, h, mi, s);
      return _DateParse(dt, false);
    }
    return null;
  }
}

class _DateParse {
  final DateTime value;
  final bool allDay;
  const _DateParse(this.value, this.allDay);
}
