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

import '../core/account_preference_writes.dart';
import '../core/ics_subscription_storage.dart';
import '../core/oauth_calendar_storage.dart';
import '../core/oauth_calendar_inventory.dart';
import '../core/oauth_pending_authorization.dart';
import '../core/oauth_calendar_workspace_codec.dart';
import '../core/oauth_authorization_input.dart';
import '../core/oauth_refresh_journal.dart';
import '../providers/auth_provider.dart';
import '../models/calendar_event.dart';
import 'account_local_data_cleaner.dart';
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

enum IcsRefreshStatus {
  refreshed,
  httpFailure,
  invalidCalendar,
  storageFailure,
  canceled,
}

class IcsRefreshResult {
  final String subscriptionId;
  final IcsRefreshStatus status;
  final int eventCount;
  final Object? error;

  const IcsRefreshResult(
    this.subscriptionId,
    this.status, {
    this.eventCount = 0,
    this.error,
  });
  bool get isSuccess => status == IcsRefreshStatus.refreshed;
}

enum OAuthSyncStatus {
  refreshed,
  canceled,
  unavailable,
  httpFailure,
  invalidCalendar,
  storageFailure,
  localCommitRequired,
  dispatchUnknown,
}

final class OAuthSyncResult {
  final String sourceId;
  final OAuthSyncStatus status;
  final int eventCount;
  final OAuthLocalCommitReceipt? receipt;
  final OAuthSyncStatus? diagnosticStatus;

  const OAuthSyncResult(
    this.sourceId,
    this.status, {
    this.eventCount = 0,
    this.receipt,
    this.diagnosticStatus,
  });

  bool get isSuccess => status == OAuthSyncStatus.refreshed;
}

final class _OAuthHttpFailure extends StateError {
  _OAuthHttpFailure() : super('OAuth calendar request failed');
}

final class _OAuthSyncStorageFailure implements Exception {
  const _OAuthSyncStorageFailure();
}

final class OAuthRefreshDispatchUnknown implements Exception {
  const OAuthRefreshDispatchUnknown();
  @override
  String toString() => 'OAuth refresh outcome requires explicit reconnect';
}

/// Read-only recovery state; credentials and stored receipt handles stay private.
final class OAuthRefreshRecoveryState {
  final String sourceId;
  final OAuthRefreshPhase phase;
  const OAuthRefreshRecoveryState(this.sourceId, this.phase);
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

final _ownedOAuthRows = Expando<OAuthOwnedSourceRecord>();

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
  }) {
    final result = OAuthCalendarAccount(
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
    _ownedOAuthRows[result] = _ownedOAuthRows[this];
    return result;
  }

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
    String authorizationCode = '',
    OAuthAuthorizationInput? authorizationInput,
    String? expectedState,
    required String codeVerifier,
    String clientSecret = '',
    String calendarId = 'primary',
    int colorValue = 0xFF5E97F6,
    http.Client? client,
    String? accountId,
  }) async {
    final code = _resolveAuthorizationCode(
      authorizationCode,
      authorizationInput,
      redirectUri,
      expectedState,
    );
    final token = await _postToken(
      provider: provider,
      body: {
        'client_id': clientId,
        if (clientSecret.trim().isNotEmpty)
          'client_secret': clientSecret.trim(),
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': codeVerifier,
      },
      client: client,
    );
    final refreshToken = token['refresh_token'] as String? ?? '';
    if (refreshToken.isEmpty) {
      throw const FormatException(
        'OAuth 响应缺少 refresh_token，请确认已请求 offline access',
      );
    }
    return OAuthCalendarAccount(
      id: accountId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      provider: provider,
      displayName: displayName,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      calendarId: calendarId.trim().isEmpty ? 'primary' : calendarId.trim(),
      accessToken: token['access_token'] as String,
      refreshToken: refreshToken,
      expiresAt: _expiresAt(token),
      scope: token['scope'] as String? ?? provider.defaultScope,
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
      accessToken: token['access_token'] as String,
      refreshToken: token['refresh_token'] as String? ?? account.refreshToken,
      expiresAt: _expiresAt(token),
      scope: token['scope'] as String? ?? account.scope,
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
        throw _OAuthHttpFailure();
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map || decoded.containsKey('error')) {
        throw const FormatException('Invalid OAuth token response');
      }
      final token = Map<String, dynamic>.from(decoded);
      final access = token['access_token'];
      if (access is! String || access.trim().isEmpty) {
        throw const FormatException('OAuth response missing access_token');
      }
      if (token.containsKey('refresh_token') &&
          (token['refresh_token'] is! String ||
              (token['refresh_token'] as String).trim().isEmpty)) {
        throw const FormatException('Invalid OAuth refresh_token');
      }
      if (token.containsKey('scope') &&
          (token['scope'] is! String ||
              (token['scope'] as String).trim().isEmpty)) {
        throw const FormatException('Invalid OAuth scope');
      }
      final expiry = token['expires_in'];
      if (token.containsKey('expires_in') &&
          (expiry is! num ||
              !expiry.isFinite ||
              expiry <= 0 ||
              expiry != expiry.truncateToDouble() ||
              expiry > 315360000)) {
        throw const FormatException('Invalid OAuth token expiry');
      }
      final type = token['token_type'];
      if (type != null && (type is! String || type.toLowerCase() != 'bearer')) {
        throw const FormatException('Unsupported OAuth token type');
      }
      return token;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static DateTime _expiresAt(Map<String, dynamic> token) {
    final seconds = (token['expires_in'] as num?)?.toInt() ?? 3600;
    return DateTime.now().add(Duration(seconds: seconds));
  }

  static String _resolveAuthorizationCode(
    String raw,
    OAuthAuthorizationInput? explicitInput,
    String redirectUri,
    String? expectedState,
  ) {
    if (explicitInput != null && raw.isNotEmpty) {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.malformedCode,
      );
    }
    return (explicitInput ?? OAuthAuthorizationInput.manualCode(raw))
        .resolveCode(
          registeredRedirectUri: redirectUri,
          expectedState: expectedState,
        );
  }
}

class OAuthLocalCommitReceipt {
  final String handle;
  final bool isRefresh;
  const OAuthLocalCommitReceipt._(this.handle, this.isRefresh);

  @override
  String toString() => 'OAuthLocalCommitReceipt';
}

class OAuthLocalCommitRequired implements Exception {
  final OAuthLocalCommitReceipt receipt;
  const OAuthLocalCommitRequired(this.receipt);

  @override
  String toString() => 'OAuth credentials need a local save retry';
}

/// Captured by the real issuer before enrollment or the first asynchronous hop.
/// The durable record remains data; this issuer lease supplies authority.
final class _OAuthAction {
  final AuthProvider auth;
  final AuthOAuthScopeLease lease;
  final bool Function() localCurrent;
  const _OAuthAction(this.auth, this.lease, this.localCurrent);
  OAuthScopedWorkspaceSnapshot get workspace => lease.workspace;
  bool get scopeCurrent => auth.isOAuthScopeLeaseCurrent(lease);
  bool get scopeRetainable => auth.isOAuthScopeLeaseRetainable(lease);
  bool call() => scopeCurrent && localCurrent();
}

class _OAuthCredentialCandidate {
  final OAuthLocalCommitReceipt receipt;
  final OAuthCalendarAccount account;
  final int owner;
  final int writes;
  final int epoch;
  final int reset;
  final int source;
  final SharedPreferences store;
  final _OAuthAction authority;
  final OAuthOwnedSourceRecord? originalSource;
  final OAuthOwnedPendingAuthorization? pending;
  final OAuthOwnedRefreshJournal? refresh;
  bool committed = false;

  _OAuthCredentialCandidate(
    this.account, {
    required bool refreshing,
    required this.owner,
    required this.writes,
    required this.epoch,
    required this.reset,
    required this.store,
    required this.authority,
    this.originalSource,
    this.pending,
    this.refresh,
    String? receiptHandle,
    int? expectedSource,
  }) : receipt = OAuthLocalCommitReceipt._(
         receiptHandle ?? OAuthCalendarClient.generateCodeVerifier(),
         refreshing,
       ),
       source =
           expectedSource ?? OAuthCalendarStorage.sourceRevision(account.id);

  bool get retainable =>
      authority.scopeRetainable &&
      owner == AccountLocalDataCleaner.accountDataGeneration &&
      writes == AccountPreferenceWrites.generation &&
      epoch == OAuthCalendarStorage.epoch &&
      reset == OAuthCalendarStorage.resetRevision &&
      source == OAuthCalendarStorage.sourceRevision(account.id) &&
      !AccountPreferenceWrites.isBoundaryActive;

  bool get eligible => retainable && authority.scopeCurrent;
}

class CalendarSyncProvider extends ChangeNotifier {
  CalendarSyncProvider({
    this.calDavWriterFactory,
    this.oauthHttpClient,
    this.authProvider,
  }) {
    _observedOAuthAuthority = _tryCaptureOAuthOrigin(null);
    _observedOAuthStorageState = _oauthObservableStorageState;
    authProvider?.addListener(_onOAuthAuthorityChanged);
    OAuthCalendarStorage.addStateListener(_onOAuthStorageChanged);
  }

  /// Borrowed issuer. A provider without it supports ICS/CalDAV only.
  final AuthProvider? authProvider;
  _OAuthAction? _publishedOAuthAuthority;
  _OAuthAction? _observedOAuthAuthority;
  (OAuthStorageIndeterminate?, bool, AuthOAuthScopeInitializationTicket?)?
      _observedOAuthStorageState;

  (OAuthStorageIndeterminate?, bool, AuthOAuthScopeInitializationTicket?)
      get _oauthObservableStorageState => (
        OAuthCalendarStorage.failure,
        oauthStorageNeedsReconciliation,
        captureOAuthScopeInitializationTicket(isCurrent: () => true),
      );

  bool get isOAuthReady => _tryCaptureOAuthOrigin(null) != null;

  /// Explicit preparation is outside consumer enrollment. Ordinary load never
  /// creates a scope, clears legacy rows or repairs an uncertain initializer.
  Future<void> prepareOAuthScope({
    bool initialize = false,
    bool confirm = false,
    bool Function()? isCurrent,
    AuthOAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
  }) async {
    if (initialize && confirm) throw ArgumentError('Choose one scope action');
    if ((!confirm &&
            (expectedInitialization != null ||
                requireExpectedInitialization)) ||
        (requireExpectedInitialization && expectedInitialization == null)) {
      throw ArgumentError(
        'Confirmation requires the original initialization ticket',
      );
    }
    final caller = _captureIcsOrigin(isCurrent);
    if (!caller()) throw const AccountPreferenceWriteCanceled();
    final auth = authProvider;
    if (auth == null) throw const OAuthScopedWorkspaceUnavailable();
    if (!initialize && !confirm && isOAuthReady) return;
    if (confirm) {
      if (expectedInitialization != null) {
        final outcome = await auth.confirmOAuthScopeInitializationWithOutcome(
          isCurrent: caller,
          expectedInitialization: expectedInitialization,
        );
        if (!caller() || !outcome.isCurrent) {
          throw const AccountPreferenceWriteCanceled();
        }
        if (outcome.ticket != null) {
          throw const OAuthScopeInitializationPending();
        }
      } else {
        await auth.confirmOAuthScopeInitialization(
          isCurrent: caller,
          requireExpectedInitialization: requireExpectedInitialization,
        );
      }
    } else if (initialize) {
      await auth.initializeOAuthScope(isCurrent: caller);
    } else {
      await auth.restoreOAuthScope(isCurrent: caller);
    }
    if (!caller()) throw const AccountPreferenceWriteCanceled();
    if (!isOAuthReady) throw const OAuthScopedWorkspaceUnavailable();
  }

  Future<AuthOAuthScopeInitializationTicket?> initializeOAuthScopeWithTicket({
    required bool Function() isCurrent,
  }) async {
    final caller = _captureIcsOrigin(isCurrent);
    if (!caller()) throw const AccountPreferenceWriteCanceled();
    final auth = authProvider;
    if (auth == null) throw const OAuthScopedWorkspaceUnavailable();
    final outcome = await auth.initializeOAuthScopeWithOutcome(
      isCurrent: caller,
    );
    if (!caller() || !outcome.isCurrent) {
      throw const AccountPreferenceWriteCanceled();
    }
    final ticket = outcome.ticket;
    if (ticket == null) {
      if (!isOAuthReady) throw const OAuthScopedWorkspaceUnavailable();
    } else if (!identical(
      ticket,
      auth.captureOAuthScopeInitializationTicket(isCurrent: caller),
    )) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return ticket;
  }

  AuthOAuthScopeInitializationTicket? captureOAuthScopeInitializationTicket({
    required bool Function() isCurrent,
  }) {
    final caller = _captureIcsOrigin(isCurrent);
    if (!caller()) return null;
    return authProvider?.captureOAuthScopeInitializationTicket(
      isCurrent: caller,
    );
  }

  void _clearOAuthProjection() {
    _oauthAccounts.clear();
    _eventsByOAuthAccount.clear();
    _observedPendingOAuthAttempt = null;
    _publishedOAuthAuthority = null;
  }

  void _onOAuthStorageChanged() {
    if (authProvider == null) {
      return;
    }
    _onOAuthAuthorityChanged(storageChanged: true);
  }

  void _onOAuthAuthorityChanged({bool storageChanged = false}) {
    if (_disposed) return;
    final previous = _observedOAuthAuthority;
    final next = _tryCaptureOAuthOrigin(null);
    final changed = !identical(previous?.workspace, next?.workspace);
    _observedOAuthAuthority = next;
    final storageState = _oauthObservableStorageState;
    final storageStateChanged = _observedOAuthStorageState != storageState;
    // Update before calling observers so a repeated delayed event is harmless.
    _observedOAuthStorageState = storageState;
    var revoked = false;
    if (_publishedOAuthAuthority != null &&
        !_publishedOAuthAuthority!.scopeCurrent) {
      _clearOAuthProjection();
      revoked = true;
    }
    if (changed ||
        revoked ||
        storageStateChanged ||
        (storageChanged && next != null)) {
      notifyListeners();
    }
  }

  /// Borrowed transport: the provider never closes this client.
  final http.Client? oauthHttpClient;

  static final Map<String, _OAuthCredentialCandidate> _oauthCandidates = {};
  static final Map<SharedPreferences, Set<String>> _oauthDispatchedCodes =
      Map<SharedPreferences, Set<String>>.identity();
  static final Map<SharedPreferences, Set<String>> _oauthRefreshing =
      Map.identity();
  String? _observedPendingOAuthAttempt;
  SharedPreferences? _oauthBackingStore;

  bool get oauthStorageNeedsReconciliation =>
      OAuthCalendarStorage.failure != null ||
      (_oauthBackingStore != null &&
          OAuthCalendarStorage.isAccountRetiring(_oauthBackingStore!));

  static void _retireOAuthStore(SharedPreferences preferences) {
    _oauthCandidates.removeWhere(
      (_, candidate) => identical(candidate.store, preferences),
    );
    _oauthDispatchedCodes.remove(preferences);
    _oauthRefreshing.remove(preferences);
  }

  @visibleForTesting
  final CalDavWriter Function(CalDavWriteTarget, bool Function())?
  calDavWriterFactory;
  int _targetRevision = 0;
  int _pendingTargetWrites = 0;
  bool get isUpdatingWriteTarget => _pendingTargetWrites > 0;
  bool _pushInProgress = false;
  bool _testInProgress = false;

  int get writeTargetRevision => _targetRevision;
  bool _disposed = false;
  int _icsLifetimeGeneration = 0;
  int _syncRun = 0;
  final Map<String, ({IcsRefreshResult result, int revision})> _icsResults = {};
  int? _icsResultsAccount;
  Map<String, IcsRefreshResult> get icsRefreshResults {
    if (_icsResultsAccount != AccountLocalDataCleaner.accountDataGeneration) {
      return const {};
    }
    return Map.unmodifiable({
      for (final entry in _icsResults.entries)
        if (entry.value.revision ==
            IcsSubscriptionStorage.sourceRevision(entry.key))
          entry.key: entry.value.result,
    });
  }

  void _recordIcsResult(IcsRefreshResult result, int revision) {
    if (result.status == IcsRefreshStatus.canceled ||
        revision !=
            IcsSubscriptionStorage.sourceRevision(result.subscriptionId)) {
      return;
    }
    final account = AccountLocalDataCleaner.accountDataGeneration;
    if (_icsResultsAccount != account) _icsResults.clear();
    _icsResultsAccount = account;
    _icsResults[result.subscriptionId] = (result: result, revision: revision);
  }

  int get icsLifetimeGeneration => _icsLifetimeGeneration;
  bool get icsStorageNeedsReconciliation =>
      IcsSubscriptionStorage.failure != null;
  IcsStorageIndeterminate? get icsStorageFailure =>
      IcsSubscriptionStorage.failure;
  // These preference keys are shared by every provider instance. Rollback must
  // finish before a replacement instance can publish another configuration.
  static Future<void> _targetWriteTail = Future<void>.value();

  @override
  void dispose() {
    authProvider?.removeListener(_onOAuthAuthorityChanged);
    OAuthCalendarStorage.removeStateListener(_onOAuthStorageChanged);
    _disposed = true;
    _targetRevision++;
    _icsLifetimeGeneration++;
    _syncRun++;
    super.dispose();
  }

  Future<T> _queueTargetWrite<T>(Future<T> Function() operation) {
    final result = _targetWriteTail.then((_) => operation());
    _targetWriteTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static const _subscriptionsKey = 'duoyi_ics_subscriptions_v1';
  static const _eventsKeyPrefix = 'duoyi_ics_events_';
  static const _oauthAccountsKey = OAuthCalendarStorage.accountsKey;
  static const _oauthEventsKeyPrefix = OAuthCalendarStorage.eventsKeyPrefix;
  static const _pendingOAuthAuthorizationKey =
      OAuthCalendarStorage.pendingAuthorizationKey;
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
  String? _lastCalDavError;
  int? _lastCalDavErrorAccount;
  final List<CalDavWriteConflict> _lastCalDavConflicts = [];

  List<IcsSubscription> get subscriptions =>
      List<IcsSubscription>.unmodifiable(_subscriptions);

  List<OAuthCalendarAccount> get oauthAccounts =>
      List<OAuthCalendarAccount>.unmodifiable(
        _publishedOAuthAuthority?.scopeCurrent == true
            ? _oauthAccounts
            : const [],
      );

  bool get isSyncing => _syncing;

  bool get isTestingWriteTarget => _testingWriteTarget;

  CalDavWriteTarget? get writeTarget => _writeTarget;

  String? get lastError => _lastError;

  String? get lastCalDavError =>
      _lastCalDavErrorAccount == AccountLocalDataCleaner.accountDataGeneration
      ? _lastCalDavError
      : null;

  void _recordCalDavError(String? error) {
    _lastCalDavError = error;
    _lastCalDavErrorAccount = AccountLocalDataCleaner.accountDataGeneration;
  }

  List<CalDavWriteConflict> get lastCalDavConflicts =>
      List<CalDavWriteConflict>.unmodifiable(_lastCalDavConflicts);

  /// 所有订阅汇总后的只读事件。
  List<CalendarEvent> allEvents() {
    final out = <CalendarEvent>[];
    for (final sub in _subscriptions.where((sub) => sub.enabled)) {
      out.addAll(_eventsBySubscription[sub.id] ?? const []);
    }
    for (final account in oauthAccounts.where((account) => account.enabled)) {
      out.addAll(_eventsByOAuthAccount[account.id] ?? const []);
    }
    return out;
  }

  bool Function() _captureIcsOrigin(bool Function()? isCurrent) {
    final lifetime = _icsLifetimeGeneration;
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final writes = AccountPreferenceWrites.generation;
    final epoch = IcsSubscriptionStorage.epoch;
    return () {
      try {
        return !_disposed &&
            lifetime == _icsLifetimeGeneration &&
            account == AccountLocalDataCleaner.accountDataGeneration &&
            writes == AccountPreferenceWrites.generation &&
            epoch == IcsSubscriptionStorage.epoch &&
            !AccountPreferenceWrites.isBoundaryActive &&
            (isCurrent?.call() ?? true);
      } catch (_) {
        return false;
      }
    };
  }

  Future<T> _withIcsStorage<T>(
    Future<T> Function(SharedPreferences, bool Function()) operation, {
    bool Function()? isCurrent,
    bool allowUncertain = false,
  }) {
    final origin = _captureIcsOrigin(isCurrent);
    final epoch = IcsSubscriptionStorage.epoch;
    if (AccountPreferenceWrites.isBoundaryActive) {
      return Future<T>.error(const AccountPreferenceWriteCanceled());
    }
    return AccountPreferenceWrites.runResult<T>(
      (token) => IcsSubscriptionStorage.run(
        () async {
          bool current() => token.isCurrent && origin();
          if (!current()) throw const AccountPreferenceWriteCanceled();
          final prefs = await SharedPreferences.getInstance();
          if (!current()) throw const AccountPreferenceWriteCanceled();
          await prefs.reload();
          if (!current()) throw const AccountPreferenceWriteCanceled();
          return operation(prefs, current);
        },
        epoch: epoch,
        allowUncertain: allowUncertain,
      ),
      canceledResult: () => throw const AccountPreferenceWriteCanceled(),
    ).then<T>(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        if (error is IcsStorageIndeterminate && origin()) notifyListeners();
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  List<IcsSubscription> _readIcsSubscriptions(SharedPreferences prefs) {
    final raw = prefs.getString(_subscriptionsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid subscriptions');
    final rows = <IcsSubscription>[];
    final ids = <String>{};
    for (final value in decoded) {
      if (value is! Map) throw const FormatException('Invalid subscription');
      final sub = IcsSubscription.fromJson(Map<String, dynamic>.from(value));
      if (sub.id.isEmpty || !ids.add(sub.id)) {
        throw const FormatException('Invalid subscription identity');
      }
      rows.add(sub);
    }
    return rows;
  }

  Map<String, List<CalendarEvent>> _readIcsEvents(
    SharedPreferences prefs,
    List<IcsSubscription> subscriptions,
  ) {
    final result = <String, List<CalendarEvent>>{};
    for (final sub in subscriptions) {
      final raw = prefs.getString('$_eventsKeyPrefix${sub.id}');
      if (raw == null) continue;
      try {
        final list = jsonDecode(raw) as List;
        result[sub.id] = list
            .whereType<Map>()
            .map(
              (value) => _calendarEventFromJson(
                Map<String, dynamic>.from(value),
                Color(sub.colorValue),
              ),
            )
            .whereType<CalendarEvent>()
            .toList();
      } catch (error) {
        debugPrint('[CalendarSync] load cached events failed: $error');
      }
    }
    return result;
  }

  void _publishIcs(
    List<IcsSubscription> rows,
    Map<String, List<CalendarEvent>> events,
  ) {
    _subscriptions
      ..clear()
      ..addAll(rows);
    _eventsBySubscription
      ..clear()
      ..addAll(events);
  }

  Future<void> loadFromStorage({bool Function()? isCurrent}) async {
    final origin = _captureIcsOrigin(isCurrent);
    final oauthOrigin = _tryCaptureOAuthOrigin(isCurrent);
    final targetRevision = _targetRevision;
    final targetAtStart = _writeTarget;
    await _withIcsStorage<void>((prefs, current) async {
      final rows = _readIcsSubscriptions(prefs);
      final events = _readIcsEvents(prefs, rows);
      final rawTarget = prefs.getString(_calDavWriteTargetKey);
      CalDavWriteTarget? target;
      var targetDecoded = true;
      try {
        if (rawTarget != null && rawTarget.isNotEmpty) {
          target = CalDavWriteTarget.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawTarget) as Map),
          );
        }
      } catch (error) {
        targetDecoded = false;
        debugPrint('[CalendarSync] load CalDAV target failed: $error');
      }
      if (!current()) throw const AccountPreferenceWriteCanceled();
      _publishIcs(rows, events);
      if (targetDecoded &&
          targetRevision == _targetRevision &&
          identical(targetAtStart, _writeTarget)) {
        _writeTarget = target;
      }
      notifyListeners();
    }, isCurrent: origin);
    // Do not hold the ICS lane while waiting for OAuth settlement. Its own
    // lane prevents peers from publishing an issued transaction or rollback,
    // and refuses reads while OAuth storage remains indeterminate.
    if (oauthOrigin == null) {
      _clearOAuthProjection();
      return;
    }
    await _withOAuthStorage<void>(oauthOrigin, (prefs, current) async {
      late List<OAuthCalendarAccount> rows;
      try {
        rows = _readOAuthAccounts(prefs, oauthOrigin);
      } catch (_) {
        debugPrint('[CalendarSync] invalid stored OAuth accounts');
        return;
      }
      if (!current()) throw const AccountPreferenceWriteCanceled();
      _publishOAuth(prefs, rows, oauthOrigin);
      _restoreOAuthReceipt(prefs, oauthOrigin);
      notifyListeners();
    });
  }

  void resetLocalState() {
    OAuthCalendarStorage.invalidateReset();
    _targetRevision++;
    _icsLifetimeGeneration++;
    _syncRun++;
    _icsResults.clear();
    _icsResultsAccount = null;
    _subscriptions.clear();
    _clearOAuthProjection();
    _eventsBySubscription.clear();
    _eventsByOAuthAccount.clear();
    _writeTarget = null;
    _syncing = false;
    _testingWriteTarget = false;
    _lastError = null;
    _lastCalDavError = null;
    _lastCalDavErrorAccount = null;
    _lastCalDavConflicts.clear();
    // resetLocalState already publishes this boundary synchronously.
    _observedOAuthAuthority = _tryCaptureOAuthOrigin(null);
    _observedOAuthStorageState = _oauthObservableStorageState;
    if (!_disposed) notifyListeners();
  }

  bool _sameIcsConfiguration(IcsSubscription a, IcsSubscription b) =>
      a.id == b.id &&
      a.name == b.name &&
      a.url == b.url &&
      a.colorValue == b.colorValue &&
      a.enabled == b.enabled;

  Future<void> _mutateSubscription(
    String id,
    IcsSubscription? draft, {
    required bool adding,
    bool Function()? isCurrent,
  }) => _withIcsStorage<void>((prefs, current) async {
    final epoch = IcsSubscriptionStorage.epoch;
    final rows = _readIcsSubscriptions(prefs);
    final index = rows.indexWhere((sub) => sub.id == id);
    final previous = index < 0 ? null : rows[index];
    final deleting = draft == null;
    var changed = false;
    var removeCache = deleting;
    if (adding && previous != null) {
      if (!_sameIcsConfiguration(previous, draft!)) {
        throw StateError('Subscription identity collision');
      }
    } else if (deleting) {
      if (index >= 0) {
        rows.removeAt(index);
        changed = true;
      }
    } else if (adding) {
      rows.add(draft);
      changed = true;
    } else {
      if (previous == null) throw const AccountPreferenceWriteCanceled();
      removeCache = previous.url != draft.url;
      final next = IcsSubscription(
        id: draft.id,
        name: draft.name,
        url: draft.url,
        colorValue: draft.colorValue,
        enabled: draft.enabled,
        lastSyncedAt: removeCache ? null : previous.lastSyncedAt,
      );
      changed = !_sameIcsConfiguration(previous, next);
      rows[index] = next;
    }
    final cacheKey = '$_eventsKeyPrefix$id';
    final events = _readIcsEvents(prefs, rows);
    if (removeCache) events.remove(id);
    final transaction = AccountPreferenceTransaction(prefs, current);
    var issued = false;
    try {
      if (changed) {
        await transaction.setString(
          _subscriptionsKey,
          jsonEncode(rows.map((sub) => sub.toJson()).toList()),
        );
      }
      if (removeCache && prefs.containsKey(cacheKey)) {
        await transaction.remove(cacheKey);
      }
      await transaction.reload();
      if (changed &&
          prefs.getString(_subscriptionsKey) !=
              jsonEncode(rows.map((sub) => sub.toJson()).toList())) {
        throw StateError('Subscription readback failed');
      }
      if (removeCache && prefs.containsKey(cacheKey)) {
        throw StateError('Cache removal readback failed');
      }
      issued = transaction.changedKeys.isNotEmpty;
      transaction.commit();
      if (changed) IcsSubscriptionStorage.sourceChanged(id);
      if (changed) _icsResults.remove(id);
      _publishIcs(rows, events);
    } catch (error) {
      await IcsSubscriptionStorage.compensateLocked(
        prefs,
        transaction,
        error,
        epoch: epoch,
      );
      rethrow;
    }
    if (issued) notifyListeners();
  }, isCurrent: isCurrent);

  Future<void> addSubscription(
    IcsSubscription sub, {
    bool Function()? isCurrent,
  }) => _mutateSubscription(sub.id, sub, adding: true, isCurrent: isCurrent);

  Future<void> updateSubscription(
    IcsSubscription sub, {
    bool Function()? isCurrent,
  }) => _mutateSubscription(sub.id, sub, adding: false, isCurrent: isCurrent);

  Future<void> removeSubscription(String id, {bool Function()? isCurrent}) =>
      _mutateSubscription(id, null, adding: false, isCurrent: isCurrent);

  Future<void> reconcileIcsStorage({bool Function()? isCurrent}) =>
      _withIcsStorage<void>(
        (prefs, current) async {
          await IcsSubscriptionStorage.reconcileLocked(prefs, current);
          if (!current()) throw const AccountPreferenceWriteCanceled();
          final rows = _readIcsSubscriptions(prefs);
          _publishIcs(rows, _readIcsEvents(prefs, rows));
          notifyListeners();
        },
        isCurrent: isCurrent,
        allowUncertain: true,
      );

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
    String authorizationCode = '',
    OAuthAuthorizationInput? authorizationInput,
    String? expectedState,
    String? expectedAttemptId,
    required String codeVerifier,
    String clientSecret = '',
    String calendarId = 'primary',
    int colorValue = 0xFF5E97F6,
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    final code = OAuthCalendarClient._resolveAuthorizationCode(
      authorizationCode,
      authorizationInput,
      redirectUri,
      expectedState,
    );
    final owner = AccountLocalDataCleaner.accountDataGeneration;
    final reset = OAuthCalendarStorage.resetRevision;
    final writes = AccountPreferenceWrites.generation;
    final epoch = OAuthCalendarStorage.epoch;
    late SharedPreferences store;
    late OAuthOwnedPendingAuthorization dispatchedAttempt;
    final accountId = OAuthCalendarClient.generateCodeVerifier();
    final fingerprint = sha256
        .convert(
          utf8.encode(jsonEncode([provider.name, clientId, redirectUri, code])),
        )
        .toString();
    await _withOAuthStorage<void>(origin, (prefs, current) async {
      store = prefs;
      final pending = _readOAuthPending(prefs, origin);
      if (pending == null ||
          (expectedAttemptId != null &&
              pending.attemptId != expectedAttemptId) ||
          !pending.canDispatchAt(DateTime.now()) ||
          pending.draft['provider'] != provider.name ||
          pending.draft['displayName'] != displayName ||
          pending.draft['clientId'] != clientId ||
          pending.draft['clientSecret'] != clientSecret ||
          pending.draft['redirectUri'] != redirectUri ||
          pending.draft['calendarId'] != calendarId ||
          pending.draft['codeVerifier'] != codeVerifier ||
          (expectedState != null && pending.draft['state'] != expectedState)) {
        throw const AccountPreferenceWriteCanceled();
      }
      final dispatched = _oauthDispatchedCodes.putIfAbsent(
        prefs,
        () => <String>{},
      );
      if (dispatched.contains(fingerprint)) {
        throw StateError(
          'OAuth authorization already dispatched; recover its local commit',
        );
      }
      dispatchedAttempt = pending.dispatched(
        fingerprint: fingerprint,
        accountId: accountId,
      );
      // Confirm the durable claim before HTTP. An interrupted/unknown response
      // remains dispatched across process restart and cannot replay the code.
      await _commitOwnedOAuth(
        prefs,
        {_pendingOAuthAuthorizationKey: dispatchedAttempt.encode()},
        current,
        origin,
      );
      dispatched.add(fingerprint);
    });
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    final account = await OAuthCalendarClient.exchangeAuthorizationCode(
      provider: provider,
      displayName: displayName,
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      authorizationCode: authorizationCode,
      authorizationInput: authorizationInput,
      expectedState: expectedState,
      codeVerifier: codeVerifier,
      calendarId: calendarId,
      colorValue: colorValue,
      accountId: accountId,
      client: oauthHttpClient,
    );
    _ownedOAuthRows[account] = OAuthOwnedSourceRecord.create(
      scope: origin.workspace.record,
      account: account.toJson(),
    );
    final candidate = _OAuthCredentialCandidate(
      account,
      refreshing: false,
      owner: owner,
      reset: reset,
      writes: writes,
      epoch: epoch,
      store: store,
      authority: origin,
      pending: dispatchedAttempt,
    );
    // Returned credentials can survive route/provider disposal for explicit
    // recovery, but cannot be adopted by a new account/reset incarnation.
    if (candidate.retainable) {
      _oauthCandidates[candidate.receipt.handle] = candidate;
    }
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    await _stageOAuthReceived(candidate, origin);
    final committed = await _commitOAuthCandidate(candidate, origin);
    await _syncOAuthAccount(
      committed,
      isCurrent: origin.call,
      authority: origin,
      expectedSource: candidate.source,
    );
    if (!origin() || !candidate.eligible) {
      throw const AccountPreferenceWriteCanceled();
    }
    final latest = await _withOAuthStorage<OAuthCalendarAccount>(
      origin,
      (prefs, current) async => _readOAuthAccounts(prefs, origin).firstWhere(
        (row) => row.id == account.id,
        orElse: () => throw const AccountPreferenceWriteCanceled(),
      ),
      condition: () => candidate.eligible,
    );
    if (!origin() || !candidate.eligible) {
      throw const AccountPreferenceWriteCanceled();
    }
    return latest;
  }

  _OAuthAction? _tryCaptureOAuthOrigin(bool Function()? caller) {
    final auth = authProvider;
    if (auth == null || _disposed) return null;
    try {
      final lease = auth.captureOAuthScopeLease();
      return _OAuthAction(auth, lease, _captureIcsOrigin(caller));
    } catch (_) {
      return null;
    }
  }

  _OAuthAction _captureOAuthOrigin(bool Function()? caller) =>
      _tryCaptureOAuthOrigin(caller) ??
      (throw const OAuthScopedWorkspaceUnavailable());

  Future<T> _withOAuthStorage<T>(
    _OAuthAction origin,
    Future<T> Function(SharedPreferences, bool Function()) operation, {
    bool recovering = false,
    bool Function()? condition,
    void Function(SharedPreferences, T)? afterReadback,
  }) {
    final epoch = OAuthCalendarStorage.epoch;
    if (!origin() || !(condition?.call() ?? true)) {
      return Future<T>.error(const AccountPreferenceWriteCanceled());
    }
    return AccountPreferenceWrites.runResult<T>(
      (token) => OAuthCalendarStorage.run<T>(
        () async {
          bool runtimeCurrent() =>
              origin() && token.isCurrent && (condition?.call() ?? true);
          if (!runtimeCurrent()) throw const AccountPreferenceWriteCanceled();
          final prefs = await SharedPreferences.getInstance();
          if (!runtimeCurrent()) throw const AccountPreferenceWriteCanceled();
          await prefs.reload();
          if (!runtimeCurrent()) throw const AccountPreferenceWriteCanceled();
          try {
            OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
              origin.workspace,
              prefs,
            );
            OAuthCalendarInventory.validate(prefs, origin.workspace.record);
          } catch (error) {
            if (identical(_publishedOAuthAuthority?.auth, origin.auth) &&
                _publishedOAuthAuthority?.workspace.rawRecord ==
                    origin.workspace.rawRecord) {
              _clearOAuthProjection();
              if (!_disposed) notifyListeners();
            }
            rethrow;
          }
          bool current() {
            if (!runtimeCurrent()) return false;
            try {
              OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
                origin.workspace,
                prefs,
              );
              return true;
            } catch (_) {
              _revokeOAuthProjection(origin);
              return false;
            }
          }

          _oauthBackingStore = prefs;
          OAuthCalendarStorage.registerAccountClearListener(_retireOAuthStore);
          try {
            final result = await operation(prefs, current);
            if (!current()) throw const AccountPreferenceWriteCanceled();
            await prefs.reload();
            if (!current()) throw const AccountPreferenceWriteCanceled();
            OAuthCalendarInventory.validate(prefs, origin.workspace.record);
            afterReadback?.call(prefs, result);
            if (!current()) throw const AccountPreferenceWriteCanceled();
            return result;
          } on OAuthStorageIndeterminate {
            _revokeOAuthProjection(origin);
            rethrow;
          } on OAuthWorkspaceCodecException {
            _revokeOAuthProjection(origin);
            rethrow;
          } on OAuthScopedWorkspaceUnavailable {
            _revokeOAuthProjection(origin);
            rethrow;
          }
        },
        epoch: epoch,
        recovering: recovering,
        isCurrent: () =>
            origin() && token.isCurrent && (condition?.call() ?? true),
      ),
      canceledResult: () => throw const AccountPreferenceWriteCanceled(),
    );
  }

  void _revokeOAuthProjection(_OAuthAction origin) {
    if (identical(_publishedOAuthAuthority?.auth, origin.auth) &&
        _publishedOAuthAuthority?.workspace.rawRecord ==
            origin.workspace.rawRecord) {
      _clearOAuthProjection();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _commitOwnedOAuth(
    SharedPreferences prefs,
    Map<String, Object?> changes,
    bool Function() current,
    _OAuthAction origin,
  ) => OAuthCalendarStorage.commitLocked(
    prefs,
    changes,
    current,
    scopedWorkspace: origin.workspace,
    validateReadback: () {
      OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
        origin.workspace,
        prefs,
      );
      OAuthCalendarInventory.validate(prefs, origin.workspace.record);
    },
  );

  List<OAuthCalendarAccount> _readOAuthAccounts(
    SharedPreferences prefs,
    _OAuthAction origin,
  ) {
    OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
      origin.workspace,
      prefs,
    );
    final records = OAuthCalendarInventory.validate(
      prefs,
      origin.workspace.record,
    );
    return records.map((record) {
      final account = OAuthCalendarAccount.fromJson(
        Map<String, dynamic>.from(record.account),
      );
      _ownedOAuthRows[account] = record;
      return account;
    }).toList();
  }

  OAuthOwnedSourceRecord _sourceRecord(OAuthCalendarAccount account) =>
      _ownedOAuthRows[account] ?? (throw const OAuthWorkspaceCodecException());

  void _requireSameOAuthSource(
    OAuthCalendarAccount original,
    OAuthCalendarAccount current, {
    bool credentials = false,
  }) {
    final expected = _sourceRecord(original);
    final actual = _sourceRecord(current);
    if (original.id != current.id ||
        expected.scopedOwner != actual.scopedOwner ||
        expected.oauthIncarnation != actual.oauthIncarnation ||
        expected.sourceIncarnation != actual.sourceIncarnation ||
        (credentials &&
            expected.credentialRevision != actual.credentialRevision)) {
      throw const AccountPreferenceWriteCanceled();
    }
  }

  String _encodeOAuthAccounts(
    List<OAuthCalendarAccount> rows,
    _OAuthAction origin,
  ) => jsonEncode(
    rows.map((row) {
      final base = _sourceRecord(row);
      if (base.scopedOwner != origin.workspace.record.scopedOwner ||
          base.oauthIncarnation != origin.workspace.record.oauthIncarnation) {
        throw const AccountPreferenceWriteCanceled();
      }
      final next = base.withAccount(row.toJson());
      _ownedOAuthRows[row] = next;
      return next.toJson();
    }).toList(),
  );

  void _publishOAuth(
    SharedPreferences prefs,
    List<OAuthCalendarAccount> rows,
    _OAuthAction origin,
  ) {
    OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
      origin.workspace,
      prefs,
    );
    OAuthCalendarInventory.validate(prefs, origin.workspace.record);
    final events = <String, List<CalendarEvent>>{};
    final byId = {for (final row in rows) row.id: row};
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(_oauthEventsKeyPrefix),
    )) {
      final row = byId[key.substring(_oauthEventsKeyPrefix.length)];
      final raw = prefs.get(key);
      if (row == null || raw is! String) {
        throw const OAuthWorkspaceCodecException();
      }
      final cache = OAuthOwnedEventsRecord.parse(
        raw,
        source: _sourceRecord(row),
      );
      if (cache == null) throw const OAuthWorkspaceCodecException();
      events[row.id] = cache.events.map((value) {
        final event = _calendarEventFromJson(
          Map<String, dynamic>.from(value),
          Color(row.colorValue),
        );
        if (event == null) throw const OAuthWorkspaceCodecException();
        return event;
      }).toList();
    }
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    _oauthAccounts
      ..clear()
      ..addAll(rows);
    _eventsByOAuthAccount
      ..clear()
      ..addAll(events);
    _publishedOAuthAuthority = origin;
  }

  List<OAuthLocalCommitReceipt> get oauthLocalCommitReceipts {
    _oauthCandidates.removeWhere((_, candidate) => !candidate.retainable);
    final authority = _tryCaptureOAuthOrigin(null);
    return List.unmodifiable(
      _oauthCandidates.values
          .where(
            (candidate) =>
                !candidate.committed &&
                candidate.eligible &&
                authority != null &&
                identical(candidate.authority.auth, authority.auth) &&
                candidate.authority.workspace.rawRecord ==
                    authority.workspace.rawRecord &&
                identical(candidate.store, _oauthBackingStore),
          )
          .map((candidate) => candidate.receipt),
    );
  }

  Future<OAuthCalendarAccount> retryOAuthLocalCommit(
    OAuthLocalCommitReceipt receipt, {
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    final candidate = _oauthCandidates[receipt.handle];
    if (candidate == null ||
        !identical(candidate.receipt, receipt) ||
        !candidate.eligible) {
      throw const AccountPreferenceWriteCanceled();
    }
    await _stageOAuthReceived(candidate, origin);
    return _commitOAuthCandidate(candidate, origin);
  }

  Future<void> reconcileOAuthStorage({bool Function()? isCurrent}) async {
    if (OAuthCalendarStorage.failure != null) {
      final auth = authProvider;
      if (auth == null || _disposed) {
        throw const OAuthScopedWorkspaceUnavailable();
      }
      final recovery = auth.captureOAuthReconciliationLease();
      final localCurrent = _captureIcsOrigin(isCurrent);
      final epoch = OAuthCalendarStorage.epoch;
      bool current() =>
          localCurrent() && auth.isOAuthReconciliationLeaseCurrent(recovery);
      if (!current()) throw const AccountPreferenceWriteCanceled();
      await AccountPreferenceWrites.runResult<void>(
        (token) => OAuthCalendarStorage.run<void>(
          () async {
            bool admitted() => token.isCurrent && current();
            if (!admitted()) throw const AccountPreferenceWriteCanceled();
            final prefs = await SharedPreferences.getInstance();
            if (!admitted()) throw const AccountPreferenceWriteCanceled();
            await prefs.reload();
            if (!admitted()) throw const AccountPreferenceWriteCanceled();
            OAuthCalendarStorage.ensureScopedReconciliationCurrentLocked(
              recovery.recovery,
              prefs,
            );
            await OAuthCalendarStorage.reconcileLocked(
              prefs,
              admitted,
              validateReadback: () {
                OAuthCalendarStorage.ensureScopedReconciliationCurrentLocked(
                  recovery.recovery,
                  prefs,
                );
                OAuthCalendarInventory.validate(
                  prefs,
                  recovery.recovery.workspace.record,
                );
              },
            );
          },
          epoch: epoch,
          recovering: true,
          isCurrent: () => token.isCurrent && current(),
        ),
        canceledResult: () => throw const AccountPreferenceWriteCanceled(),
      );
      if (!localCurrent() || !auth.isOAuthReconciliationSettled(recovery)) {
        throw const AccountPreferenceWriteCanceled();
      }
      // Restoration is distinct from receipt adoption and projection loading.
      notifyListeners();
      return;
    }
    final origin = _captureOAuthOrigin(isCurrent);
    await _withOAuthStorage<void>(
      origin,
      (prefs, current) => OAuthCalendarStorage.reconcileLocked(prefs, current),
      recovering: true,
    );
    if (origin()) notifyListeners();
  }

  OAuthOwnedPendingAuthorization? _readOAuthPending(
    SharedPreferences prefs,
    _OAuthAction origin,
  ) {
    if (!prefs.containsKey(_pendingOAuthAuthorizationKey)) return null;
    final raw = prefs.get(_pendingOAuthAuthorizationKey);
    final record = raw is String
        ? OAuthOwnedPendingAuthorization.parse(
            raw,
            scope: origin.workspace.record,
          )
        : null;
    if (record == null) throw const OAuthWorkspaceCodecException();
    return record;
  }

  void _requireCandidateAttempt(
    _OAuthCredentialCandidate candidate,
    OAuthOwnedPendingAuthorization? current,
  ) {
    final expected = candidate.pending;
    if (expected == null) return;
    if (current != null &&
        (jsonEncode(current.draft) != jsonEncode(expected.draft) ||
            current.savedAt != expected.savedAt ||
            (current.phase == OAuthPendingPhase.received &&
                current.receivedSource?.encode() !=
                    _sourceRecord(candidate.account).encode()))) {
      throw const AccountPreferenceWriteCanceled();
    }
    if (current == null ||
        current.attemptId != expected.attemptId ||
        current.scopedOwner != expected.scopedOwner ||
        current.oauthIncarnation != expected.oauthIncarnation ||
        current.codeFingerprint != expected.codeFingerprint ||
        current.sourceAccountId != expected.sourceAccountId ||
        (current.phase != OAuthPendingPhase.dispatched &&
            current.phase != OAuthPendingPhase.received) ||
        (current.phase == OAuthPendingPhase.received &&
            current.receiptHandle != candidate.receipt.handle)) {
      throw const AccountPreferenceWriteCanceled();
    }
  }

  Future<void> _stageOAuthReceived(
    _OAuthCredentialCandidate candidate,
    _OAuthAction origin,
  ) async {
    if (!identical(candidate.authority.auth, origin.auth) ||
        candidate.authority.workspace.rawRecord != origin.workspace.rawRecord) {
      throw const AccountPreferenceWriteCanceled();
    }
    if (candidate.committed) return;
    if (candidate.refresh != null) {
      try {
        await _withOAuthStorage<void>(origin, (prefs, current) async {
          // A peer may finish while this staging operation waits in the lane.
          // Installation is still read back by _commitOAuthCandidate below.
          if (candidate.committed) return;
          final actual = _readOAuthRefresh(prefs, origin);
          final wanted = candidate.refresh!;
          if (actual == null ||
              actual.operationId != wanted.operationId ||
              actual.receiptHandle != candidate.receipt.handle ||
              actual.dispatchedAt != wanted.dispatchedAt ||
              actual.originalSource.encode() !=
                  wanted.originalSource.encode()) {
            throw const AccountPreferenceWriteCanceled();
          }
          if (actual.phase == OAuthRefreshPhase.received) {
            if (actual.encode() != wanted.encode()) {
              throw const AccountPreferenceWriteCanceled();
            }
            return;
          }
          await _commitOwnedOAuth(
            prefs,
            {OAuthCalendarStorage.refreshJournalKey: wanted.encode()},
            current,
            origin,
          );
        }, condition: () => candidate.eligible);
      } on OAuthStorageIndeterminate {
        rethrow;
      } on AccountPreferenceWriteCanceled {
        rethrow;
      } on OAuthScopedWorkspaceUnavailable {
        rethrow;
      } on OAuthWorkspaceCodecException {
        rethrow;
      } catch (_) {
        if (!origin() || !candidate.eligible) {
          throw const AccountPreferenceWriteCanceled();
        }
        throw OAuthLocalCommitRequired(candidate.receipt);
      }
      return;
    }
    if (candidate.pending == null) return;
    try {
      await _withOAuthStorage<void>(origin, (prefs, current) async {
        // Recheck after serialized admission, before reading a consumed claim.
        if (candidate.committed) return;
        final pending = _readOAuthPending(prefs, origin);
        _requireCandidateAttempt(candidate, pending);
        if (pending!.phase == OAuthPendingPhase.received) return;
        final received = pending.received(
          source: _sourceRecord(candidate.account),
          handle: candidate.receipt.handle,
        );
        await _commitOwnedOAuth(
          prefs,
          {_pendingOAuthAuthorizationKey: received.encode()},
          current,
          origin,
        );
      }, condition: () => candidate.eligible);
    } on AccountPreferenceWriteCanceled {
      rethrow;
    } on OAuthScopedWorkspaceUnavailable {
      rethrow;
    } on OAuthWorkspaceCodecException {
      rethrow;
    } catch (_) {
      if (!origin() || !candidate.eligible) {
        throw const AccountPreferenceWriteCanceled();
      }
      throw OAuthLocalCommitRequired(candidate.receipt);
    }
  }

  void _restoreOAuthReceipt(SharedPreferences prefs, _OAuthAction origin) {
    final refresh = _readOAuthRefresh(prefs, origin);
    if (refresh?.phase == OAuthRefreshPhase.received) {
      final previous = _oauthCandidates[refresh!.receiptHandle];
      if (previous == null ||
          !previous.eligible ||
          !identical(previous.store, prefs) ||
          !identical(previous.authority.auth, origin.auth) ||
          !identical(previous.authority.workspace, origin.workspace) ||
          previous.refresh?.encode() != refresh.encode()) {
        final source = refresh.returnedSource!;
        final account = OAuthCalendarAccount.fromJson(
          Map<String, dynamic>.from(source.account),
        );
        _ownedOAuthRows[account] = source;
        _oauthCandidates[refresh.receiptHandle] = _OAuthCredentialCandidate(
          account,
          refreshing: true,
          owner: AccountLocalDataCleaner.accountDataGeneration,
          writes: AccountPreferenceWrites.generation,
          epoch: OAuthCalendarStorage.epoch,
          reset: OAuthCalendarStorage.resetRevision,
          store: prefs,
          authority: origin,
          originalSource: refresh.originalSource,
          refresh: refresh,
          receiptHandle: refresh.receiptHandle,
        );
      }
    }
    final pending = _readOAuthPending(prefs, origin);
    if (pending?.phase != OAuthPendingPhase.received) return;
    final source = pending!.receivedSource!;
    final handle = pending.receiptHandle!;
    final previous = _oauthCandidates[handle];
    if (previous != null &&
        previous.eligible &&
        identical(previous.store, prefs) &&
        identical(previous.authority.auth, origin.auth) &&
        identical(previous.authority.workspace, origin.workspace) &&
        previous.pending != null &&
        _sourceRecord(previous.account).encode() == source.encode()) {
      // Retained candidates keep their dispatched preimage while disk moves
      // to received. Preserve the exact object under its original issuer.
      _requireCandidateAttempt(previous, pending);
      return;
    }
    final account = OAuthCalendarAccount.fromJson(
      Map<String, dynamic>.from(source.account),
    );
    _ownedOAuthRows[account] = source;
    _oauthCandidates[handle] = _OAuthCredentialCandidate(
      account,
      refreshing: false,
      owner: AccountLocalDataCleaner.accountDataGeneration,
      writes: AccountPreferenceWrites.generation,
      epoch: OAuthCalendarStorage.epoch,
      reset: OAuthCalendarStorage.resetRevision,
      store: prefs,
      authority: origin,
      pending: pending,
      receiptHandle: handle,
    );
  }

  void _requireSettledOAuthSource(
    SharedPreferences prefs,
    _OAuthAction origin,
    String id,
  ) {
    final refresh = _readOAuthRefresh(prefs, origin);
    if (refresh?.sourceAccountId == id) {
      // A retained live result must be explicitly saved before installation.
      if (refresh!.phase == OAuthRefreshPhase.received) {
        _restoreOAuthReceipt(prefs, origin);
      }
      final candidate = _oauthCandidates[refresh.receiptHandle];
      if (candidate != null &&
          candidate.eligible &&
          !candidate.committed &&
          identical(candidate.store, prefs) &&
          identical(candidate.authority.auth, origin.auth) &&
          candidate.authority.workspace.rawRecord ==
              origin.workspace.rawRecord &&
          candidate.refresh?.operationId == refresh.operationId) {
        throw OAuthLocalCommitRequired(candidate.receipt);
      }
      throw const OAuthRefreshDispatchUnknown();
    }
    final pending = _readOAuthPending(prefs, origin);
    if (pending?.phase != OAuthPendingPhase.received ||
        pending?.sourceAccountId != id) {
      return;
    }
    _restoreOAuthReceipt(prefs, origin);
    final candidate = _oauthCandidates[pending!.receiptHandle];
    if (candidate == null || !candidate.eligible) {
      throw const AccountPreferenceWriteCanceled();
    }
    throw OAuthLocalCommitRequired(candidate.receipt);
  }

  OAuthOwnedRefreshJournal? _readOAuthRefresh(
    SharedPreferences prefs,
    _OAuthAction origin,
  ) {
    if (!prefs.containsKey(OAuthCalendarStorage.refreshJournalKey)) return null;
    final raw = prefs.get(OAuthCalendarStorage.refreshJournalKey);
    final result = raw is String
        ? OAuthOwnedRefreshJournal.parse(raw, scope: origin.workspace.record)
        : null;
    if (result == null) throw const OAuthWorkspaceCodecException();
    return result;
  }

  Future<OAuthRefreshRecoveryState?> loadOAuthRefreshRecovery({
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    return _withOAuthStorage<OAuthRefreshRecoveryState?>(origin, (
      prefs,
      current,
    ) async {
      final refresh = _readOAuthRefresh(prefs, origin);
      if (refresh == null) return null;
      _restoreOAuthReceipt(prefs, origin);
      return OAuthRefreshRecoveryState(refresh.sourceAccountId, refresh.phase);
    });
  }

  Future<OAuthCalendarAccount> _commitOAuthCandidate(
    _OAuthCredentialCandidate candidate,
    _OAuthAction origin, {
    bool preserveStorageFailure = false,
    bool Function()? operationCurrent,
  }) async {
    bool eligible() => candidate.eligible && (operationCurrent?.call() ?? true);
    late OAuthCalendarAccount confirmed;
    try {
      confirmed = await _withOAuthStorage<OAuthCalendarAccount>(origin, (
        prefs,
        current,
      ) async {
        if (!identical(candidate.store, prefs) ||
            !identical(candidate.authority.auth, origin.auth) ||
            candidate.authority.workspace.rawRecord !=
                origin.workspace.rawRecord) {
          throw const AccountPreferenceWriteCanceled();
        }
        final rows = _readOAuthAccounts(prefs, origin);
        if (!candidate.committed) {
          _requireCandidateAttempt(candidate, _readOAuthPending(prefs, origin));
        }
        final index = rows.indexWhere((row) => row.id == candidate.account.id);
        if (candidate.originalSource != null && candidate.refresh == null) {
          if (index < 0) throw const AccountPreferenceWriteCanceled();
          _requireSameOAuthSource(
            candidate.account,
            rows[index],
            credentials: !candidate.committed,
          );
        }
        if (candidate.committed) {
          if (index < 0) throw const AccountPreferenceWriteCanceled();
          _requireSameOAuthSource(candidate.account, rows[index]);
          if (!current()) throw const AccountPreferenceWriteCanceled();
          _publishOAuth(prefs, rows, origin);
          return rows[index];
        }
        var alreadyInstalled = false;
        if (candidate.receipt.isRefresh) {
          if (index < 0) throw const AccountPreferenceWriteCanceled();
          final expected = candidate.refresh;
          final saved = _readOAuthRefresh(prefs, origin);
          if (expected == null ||
              saved == null ||
              saved.phase != OAuthRefreshPhase.received ||
              saved.encode() != expected.encode()) {
            throw const AccountPreferenceWriteCanceled();
          }
          final actual = _sourceRecord(rows[index]);
          alreadyInstalled = saved.matchesReturnedSource(actual);
          if (!alreadyInstalled && !saved.matchesOriginalSource(actual)) {
            throw const AccountPreferenceWriteCanceled();
          }
          if (!alreadyInstalled) {
            rows[index] = candidate.account;
            // Install the fixed source bytes once. Other rows stay byte exact.
            await _commitOwnedOAuth(
              prefs,
              {
                _oauthAccountsKey: jsonEncode(
                  rows.map((row) => _sourceRecord(row).toJson()).toList(),
                ),
              },
              current,
              origin,
            );
            alreadyInstalled = true;
          }
        } else {
          if (index >= 0) {
            if (candidate.pending == null ||
                _sourceRecord(rows[index]).encode() !=
                    _sourceRecord(candidate.account).encode()) {
              throw const AccountPreferenceWriteCanceled();
            }
            alreadyInstalled = true;
            // Resume an exact accounts-written/pending-not-consumed crash.
            // Preserve the already installed row rather than installing twice.
          } else {
            rows.add(candidate.account);
          }
        }
        await _commitOwnedOAuth(
          prefs,
          {
            if (!alreadyInstalled)
              _oauthAccountsKey: _encodeOAuthAccounts(rows, origin),
            if (candidate.pending != null) _pendingOAuthAuthorizationKey: null,
            if (candidate.refresh != null)
              OAuthCalendarStorage.refreshJournalKey: null,
          },
          current,
          origin,
        );
        candidate.committed = true;
        if (!current()) throw const AccountPreferenceWriteCanceled();
        _publishOAuth(prefs, rows, origin);
        return rows.firstWhere((row) => row.id == candidate.account.id);
      }, condition: eligible);
    } on OAuthStorageIndeterminate catch (error) {
      if (preserveStorageFailure) rethrow;
      // A matching diagnostic revokes ordinary reads and commits, while the
      // original caller may still receive its opaque local-recovery receipt.
      // Run caller callbacks before the final identity checks: they can revoke
      // the issuer or generations synchronously even when returning true.
      var canReportReceipt = false;
      final reportingLifetime = _icsLifetimeGeneration;
      final reportingIcsEpoch = IcsSubscriptionStorage.epoch;
      try {
        final localCurrent = origin.localCurrent();
        final requestCurrent = operationCurrent?.call() ?? true;
        canReportReceipt =
            localCurrent &&
            requestCurrent &&
            !_disposed &&
            reportingLifetime == _icsLifetimeGeneration &&
            reportingIcsEpoch == IcsSubscriptionStorage.epoch &&
            identical(error, OAuthCalendarStorage.failure) &&
            OAuthCalendarStorage.hasMatchingScopedReconciliation(
              origin.workspace,
            ) &&
            origin.scopeRetainable &&
            candidate.retainable &&
            identical(candidate.authority.auth, origin.auth) &&
            identical(candidate.authority.workspace, origin.workspace) &&
            candidate.authority.workspace.rawRecord ==
                origin.workspace.rawRecord &&
            !candidate.committed &&
            identical(_oauthCandidates[candidate.receipt.handle], candidate);
      } catch (_) {
        // A throwing caller cannot receive a recovery result.
      }
      if (!canReportReceipt) {
        throw const AccountPreferenceWriteCanceled();
      }
      throw OAuthLocalCommitRequired(candidate.receipt);
    } on AccountPreferenceWriteCanceled {
      rethrow;
    } on OAuthScopedWorkspaceUnavailable {
      throw const AccountPreferenceWriteCanceled();
    } on OAuthWorkspaceCodecException {
      throw const AccountPreferenceWriteCanceled();
    } catch (_) {
      if (!origin() || !eligible()) {
        throw const AccountPreferenceWriteCanceled();
      }
      throw OAuthLocalCommitRequired(candidate.receipt);
    }
    if (!origin() || !eligible()) {
      throw const AccountPreferenceWriteCanceled();
    }
    notifyListeners();
    if (!origin() || !eligible()) {
      throw const AccountPreferenceWriteCanceled();
    }
    return confirmed;
  }

  Future<Map<String, String>> savePendingOAuthAuthorization({
    required OAuthCalendarProvider provider,
    required String displayName,
    required String clientId,
    required String clientSecret,
    required String redirectUri,
    required String calendarId,
    required String codeVerifier,
    required String state,
    String? expectedAttemptId,
    bool requireExpectedAttempt = false,
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    final observed = _observedPendingOAuthAttempt;
    final compareAttempt = requireExpectedAttempt || expectedAttemptId != null;
    final pending = OAuthOwnedPendingAuthorization.create(
      scope: origin.workspace.record,
      attemptId: OAuthCalendarClient.generateCodeVerifier(),
      savedAt: DateTime.now(),
      draft: {
        'provider': provider.name,
        'displayName': displayName,
        'clientId': clientId,
        'clientSecret': clientSecret,
        'redirectUri': redirectUri,
        'calendarId': calendarId,
        'codeVerifier': codeVerifier,
        'state': state,
      },
    );
    return _withOAuthStorage<Map<String, String>>(origin, (
      prefs,
      current,
    ) async {
      final previous = _readOAuthPending(prefs, origin);
      if (compareAttempt && previous?.attemptId != expectedAttemptId) {
        throw const AccountPreferenceWriteCanceled();
      }
      if (previous != null &&
          (previous.phase != OAuthPendingPhase.prepared ||
              previous.attemptId !=
                  (compareAttempt ? expectedAttemptId : observed))) {
        throw const AccountPreferenceWriteCanceled();
      }
      await _commitOwnedOAuth(
        prefs,
        {_pendingOAuthAuthorizationKey: pending.encode()},
        current,
        origin,
      );
      _observedPendingOAuthAttempt = pending.attemptId;
      return _oauthPendingSnapshot(pending);
    });
  }

  Map<String, String> _oauthPendingSnapshot(
    OAuthOwnedPendingAuthorization pending,
  ) => Map.unmodifiable({
    ...pending.draft,
    'attemptId': pending.attemptId,
    'savedAt': pending.savedAt.toIso8601String(),
    'phase': pending.phase.name,
  });

  Future<Map<String, String>> loadPendingOAuthAuthorization({
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    return _withOAuthStorage<Map<String, String>>(origin, (
      prefs,
      current,
    ) async {
      final pending = _readOAuthPending(prefs, origin);
      if (pending == null) return const <String, String>{};
      _observedPendingOAuthAttempt = pending.attemptId;
      _restoreOAuthReceipt(prefs, origin);
      return _oauthPendingSnapshot(pending);
    });
  }

  Future<void> clearPendingOAuthAuthorization({
    String? expectedAttemptId,
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    final attempt = expectedAttemptId ?? _observedPendingOAuthAttempt;
    if (attempt == null) return;
    await _withOAuthStorage<void>(origin, (prefs, current) async {
      final pending = _readOAuthPending(prefs, origin);
      if (pending == null || pending.attemptId != attempt) return;
      // Dispatched attempts need explicit reconnect; received credentials need
      // an explicit local commit. A stale modal must not erase their recovery.
      if (pending.phase != OAuthPendingPhase.prepared) {
        throw const AccountPreferenceWriteCanceled();
      }
      await _commitOwnedOAuth(
        prefs,
        {_pendingOAuthAuthorizationKey: null},
        current,
        origin,
      );
      if (_observedPendingOAuthAttempt == attempt) {
        _observedPendingOAuthAttempt = null;
      }
    });
  }

  Future<void> updateOAuthAccount(
    OAuthCalendarAccount account, {
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    final visible = _oauthAccounts
        .where((row) => row.id == account.id)
        .firstOrNull;
    if (visible != null) _requireSameOAuthSource(account, visible);
    final base = _sourceRecord(account);
    bool changed(String key, Object? value) => base.account[key] != value;
    final metadataOnly =
        !changed('clientId', account.clientId) &&
        !changed('clientSecret', account.clientSecret) &&
        !changed('redirectUri', account.redirectUri) &&
        !changed('calendarId', account.calendarId) &&
        !changed('scope', account.scope) &&
        !changed('enabled', account.enabled);
    var source = OAuthCalendarStorage.sourceRevision(account.id);
    bool currentAction() =>
        origin() && source == OAuthCalendarStorage.sourceRevision(account.id);
    await _withOAuthStorage<void>(origin, (prefs, current) async {
      final rows = _readOAuthAccounts(prefs, origin);
      final index = rows.indexWhere((row) => row.id == account.id);
      if (index < 0) throw const AccountPreferenceWriteCanceled();
      _requireSameOAuthSource(account, rows[index]);
      _requireSettledOAuthSource(prefs, origin, account.id);
      if (metadataOnly) {
        OAuthCalendarStorage.metadataChanged(account.id);
      } else {
        OAuthCalendarStorage.sourceChanged(account.id);
      }
      source = OAuthCalendarStorage.sourceRevision(account.id);
      final originalSource = _sourceRecord(rows[index]);
      // Apply only changes relative to the caller's captured source. A stale
      // pause object must not replace a peer's name, colour or rotated tokens.
      rows[index] = rows[index].copyWith(
        displayName: changed('displayName', account.displayName)
            ? account.displayName
            : null,
        colorValue: changed('colorValue', account.colorValue)
            ? account.colorValue
            : null,
        clientId: changed('clientId', account.clientId)
            ? account.clientId
            : null,
        clientSecret: changed('clientSecret', account.clientSecret)
            ? account.clientSecret
            : null,
        redirectUri: changed('redirectUri', account.redirectUri)
            ? account.redirectUri
            : null,
        calendarId: changed('calendarId', account.calendarId)
            ? account.calendarId
            : null,
        scope: changed('scope', account.scope) ? account.scope : null,
        enabled: changed('enabled', account.enabled) ? account.enabled : null,
      );
      final encoded = _encodeOAuthAccounts(rows, origin);
      await _commitOwnedOAuth(
        prefs,
        {
          _oauthAccountsKey: encoded,
          if (_sourceRecord(rows[index]).sourceIncarnation !=
              originalSource.sourceIncarnation)
            '$_oauthEventsKeyPrefix${account.id}': null,
        },
        current,
        origin,
      );
      _publishOAuth(prefs, rows, origin);
    }, condition: currentAction);
    if (origin()) notifyListeners();
  }

  Future<void> removeOAuthAccount(
    String id, {
    OAuthCalendarAccount? expectedAccount,
    bool Function()? isCurrent,
  }) async {
    final origin = _captureOAuthOrigin(isCurrent);
    if (!origin()) throw const AccountPreferenceWriteCanceled();
    final original =
        expectedAccount ??
        _oauthAccounts.where((row) => row.id == id).firstOrNull;
    if (original == null) throw const AccountPreferenceWriteCanceled();
    if (original.id != id) throw const AccountPreferenceWriteCanceled();
    var source = OAuthCalendarStorage.sourceRevision(id);
    await _withOAuthStorage<void>(origin, (prefs, current) async {
      final rows = _readOAuthAccounts(prefs, origin);
      final actual = rows.where((row) => row.id == id).firstOrNull;
      if (actual == null) throw const AccountPreferenceWriteCanceled();
      _requireSameOAuthSource(original, actual);
      if (expectedAccount != null &&
          _sourceRecord(original).encode() != _sourceRecord(actual).encode()) {
        throw const AccountPreferenceWriteCanceled();
      }
      _requireSettledOAuthSource(prefs, origin, id);
      OAuthCalendarStorage.sourceChanged(id);
      source = OAuthCalendarStorage.sourceRevision(id);
      rows.removeWhere((row) => row.id == id);
      await _commitOwnedOAuth(
        prefs,
        {
          _oauthAccountsKey: _encodeOAuthAccounts(rows, origin),
          '$_oauthEventsKeyPrefix$id': null,
        },
        current,
        origin,
      );
      _publishOAuth(prefs, rows, origin);
    }, condition: () => source == OAuthCalendarStorage.sourceRevision(id));
    if (origin()) notifyListeners();
  }

  Future<void> saveWriteTarget(CalDavWriteTarget target) =>
      _storeTarget(target);

  Future<void> clearWriteTarget() => _storeTarget(null);

  Future<void> _storeTarget(CalDavWriteTarget? target) {
    if (_disposed) {
      return Future<void>.error(const AccountPreferenceWriteCanceled());
    }
    final revision = ++_targetRevision;
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    _pendingTargetWrites++;
    notifyListeners();
    return _queueTargetWrite(
      () => AccountPreferenceWrites.runResult<void>((token) async {
        bool current() =>
            !_disposed &&
            token.isCurrent &&
            revision == _targetRevision &&
            AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation);
        if (!current()) throw const AccountPreferenceWriteCanceled();
        final prefs = await SharedPreferences.getInstance();
        final transaction = AccountPreferenceTransaction(prefs, current);
        try {
          if (target == null) {
            await transaction.remove(_calDavWriteTargetKey);
          } else {
            await transaction.setString(
              _calDavWriteTargetKey,
              jsonEncode(target.toJson()),
            );
          }
          transaction.commit();
          _writeTarget = target;
          notifyListeners();
        } catch (_) {
          await transaction.rollback(canceledBeforeCleanup: true);
          rethrow;
        }
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
    ).whenComplete(() {
      _pendingTargetWrites--;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> testWriteTarget({bool Function()? isCurrent}) async {
    final target = _writeTarget;
    final revision = _targetRevision;
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    bool current() =>
        !_disposed &&
        revision == _targetRevision &&
        identical(target, _writeTarget) &&
        !isUpdatingWriteTarget &&
        !AccountPreferenceWrites.isBoundaryActive &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
        (isCurrent?.call() ?? true);
    void ensureCurrent() {
      if (!current()) throw const AccountPreferenceWriteCanceled();
    }

    if (_testInProgress || _pushInProgress || !current()) return;
    if (target == null || !target.isConfigured) {
      _lastError = 'CalDAV 写回目标未配置';
      _recordCalDavError(_lastError);
      notifyListeners();
      return;
    }
    _testInProgress = true;
    _testingWriteTarget = true;
    _lastError = null;
    _recordCalDavError(null);
    notifyListeners();
    try {
      final writer =
          calDavWriterFactory?.call(target, current) ??
          HttpCalDavWriter(
            collectionUrl: target.collectionUrl,
            headers: <String, String>{
              'Authorization': target.authorizationHeader,
            },
            isCurrent: current,
          );
      ensureCurrent();
      final now = DateTime.now().toUtc();
      final uid = await writer.createEvent(
        summary: '多仪 CalDAV 写回测试',
        start: now.add(const Duration(minutes: 5)),
        end: now.add(const Duration(minutes: 10)),
        description: '这是一条自动创建后立即删除的连通性测试事件。',
      );
      ensureCurrent();
      await writer.deleteEvent(uid);
      ensureCurrent();
      await _queueTargetWrite(
        () => AccountPreferenceWrites.runResult<void>((token) async {
          bool mayCommit() => token.isCurrent && current();
          if (!mayCommit()) throw const AccountPreferenceWriteCanceled();
          final prefs = await SharedPreferences.getInstance();
          final transaction = AccountPreferenceTransaction(prefs, mayCommit);
          final updated = target.copyWith(
            enabled: true,
            lastTestedAt: DateTime.now(),
          );
          try {
            await transaction.setString(
              _calDavWriteTargetKey,
              jsonEncode(updated.toJson()),
            );
            transaction.commit();
            _writeTarget = updated;
            notifyListeners();
          } catch (_) {
            await transaction.rollback(canceledBeforeCleanup: true);
            rethrow;
          }
        }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
      );
    } on AccountPreferenceWriteCanceled {
      // A dispatched test event may remain remotely; never restore old credentials.
    } catch (e, st) {
      if (current()) {
        debugPrint('[CalendarSync] CalDAV write target test failed: $e\n$st');
        _lastError = e.toString();
        _recordCalDavError(_lastError);
      }
    } finally {
      _testInProgress = false;
      if (!_disposed) {
        _testingWriteTarget = false;
        notifyListeners();
      }
    }
  }

  Future<int> pushEventsToCalDav(
    Iterable<CalendarEvent> events, {
    bool Function()? isCurrent,
  }) async {
    final target = _writeTarget;
    final revision = _targetRevision;
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    bool current() =>
        !_disposed &&
        revision == _targetRevision &&
        identical(target, _writeTarget) &&
        !isUpdatingWriteTarget &&
        !AccountPreferenceWrites.isBoundaryActive &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
        (isCurrent?.call() ?? true);
    void ensureCurrent() {
      if (!current()) throw const AccountPreferenceWriteCanceled();
    }

    ensureCurrent();
    if (_pushInProgress || _testInProgress) {
      throw StateError('CalDAV write already in progress');
    }
    if (target == null || !target.isConfigured) {
      throw StateError('CalDAV write target is not configured');
    }
    final snapshot = List<CalendarEvent>.of(events);
    _pushInProgress = true;
    _lastError = null;
    _recordCalDavError(null);
    _lastCalDavConflicts.clear();
    notifyListeners();
    final conflicts = <CalDavWriteConflict>[];
    var count = 0;
    try {
      final writer =
          calDavWriterFactory?.call(target, current) ??
          HttpCalDavWriter(
            collectionUrl: target.collectionUrl,
            headers: <String, String>{
              'Authorization': target.authorizationHeader,
            },
            isCurrent: current,
          );
      final prefs = await SharedPreferences.getInstance();
      ensureCurrent();
      final previousUids =
          prefs.getStringList(_calDavPushedUidsKey)?.toSet() ?? <String>{};
      final previousEtags = _decodeStringMap(
        prefs.getString(_calDavPushedEtagsKey),
      );
      final currentUids = <String>{};
      final currentEtags = <String, String>{};
      for (final event in snapshot) {
        ensureCurrent();
        final start = _eventStart(event);
        final end = _eventEnd(event, start);
        final uid = _calDavUidFor(event);
        final previousEtag = previousEtags[uid];
        if (target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges &&
            previousEtag != null) {
          final remoteEtag = await writer.remoteEtag(uid);
          ensureCurrent();
          if (remoteEtag != null && remoteEtag != previousEtag) {
            conflicts.add(
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
        ensureCurrent();
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
        ensureCurrent();
        final nextEtag = await writer.remoteEtag(uid);
        ensureCurrent();
        currentUids.add(uid);
        if (nextEtag != null) currentEtags[uid] = nextEtag;
        count++;
      }
      for (final staleUid in previousUids.difference(currentUids)) {
        ensureCurrent();
        final previousEtag = previousEtags[staleUid];
        if (target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges &&
            previousEtag != null) {
          final remoteEtag = await writer.remoteEtag(staleUid);
          ensureCurrent();
          if (remoteEtag != null && remoteEtag != previousEtag) {
            conflicts.add(
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
        ensureCurrent();
        await writer.deleteEvent(
          staleUid,
          ifMatch:
              target.conflictPolicy == CalDavConflictPolicy.skipRemoteChanges
              ? previousEtag
              : null,
        );
        ensureCurrent();
      }
      await _queueTargetWrite(
        () => AccountPreferenceWrites.runResult<void>((token) async {
          bool mayCommit() => token.isCurrent && current();
          final transaction = AccountPreferenceTransaction(prefs, mayCommit);
          final updated = target.copyWith(
            enabled: true,
            lastTestedAt: DateTime.now(),
          );
          try {
            await transaction.setStringList(
              _calDavPushedUidsKey,
              currentUids.toList()..sort(),
            );
            await transaction.setString(
              _calDavPushedEtagsKey,
              jsonEncode(currentEtags),
            );
            await transaction.setString(
              _calDavWriteTargetKey,
              jsonEncode(updated.toJson()),
            );
            transaction.commit();
            _writeTarget = updated;
            _lastCalDavConflicts
              ..clear()
              ..addAll(conflicts);
            notifyListeners();
          } catch (_) {
            await transaction.rollback(canceledBeforeCleanup: true);
            rethrow;
          }
        }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
      );
      return count;
    } on AccountPreferenceWriteCanceled {
      rethrow;
    } on CalDavConflictException catch (e) {
      ensureCurrent();
      _lastCalDavConflicts
        ..clear()
        ..addAll(conflicts)
        ..add(CalDavWriteConflict(uid: e.uid, title: e.uid, reason: '远端事件已变更'));
      notifyListeners();
      return count;
    } catch (e, st) {
      if (current()) {
        debugPrint('[CalendarSync] push CalDAV events failed: $e\n$st');
        _lastError = e.toString();
        _recordCalDavError(_lastError);
        notifyListeners();
      }
      rethrow;
    } finally {
      _pushInProgress = false;
    }
  }

  /// Refreshes a frozen source list; only its owning run may publish state.
  Future<void> syncAll({bool Function()? isCurrent}) async {
    if (_syncing || _disposed || AccountPreferenceWrites.isBoundaryActive) {
      return;
    }
    final origin = _captureIcsOrigin(isCurrent);
    final oauthOrigin = _tryCaptureOAuthOrigin(isCurrent);
    if (!origin()) return;
    final run = ++_syncRun;
    bool current() => run == _syncRun && origin();
    bool oauthCurrent() => current() && (oauthOrigin?.call() ?? false);
    final accounts = _oauthAccounts
        .where((account) => account.enabled)
        .map(
          (account) => (
            account: account,
            revision: OAuthCalendarStorage.sourceRevision(account.id),
          ),
        )
        .toList();
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final subscriptions =
          await _withIcsStorage<
            List<({IcsSubscription subscription, int revision})>
          >((prefs, admitted) async {
            final rows = _readIcsSubscriptions(prefs);
            _publishIcs(rows, _readIcsEvents(prefs, rows));
            return rows
                .where((sub) => sub.enabled)
                .map(
                  (sub) => (
                    subscription: sub,
                    revision: IcsSubscriptionStorage.sourceRevision(sub.id),
                  ),
                )
                .toList();
          }, isCurrent: current);
      for (final snapshot in subscriptions) {
        if (!current()) return;
        final result = await _refreshIcs(
          snapshot.subscription,
          current,
          source: snapshot.revision,
        );
        if (!current()) return;
        _recordIcsResult(result, snapshot.revision);
        if (!result.isSuccess && result.status != IcsRefreshStatus.canceled) {
          _lastError = result.error?.toString() ?? result.status.name;
        }
      }
      for (final snapshot in accounts) {
        if (!oauthCurrent()) return;
        await _syncOAuthAccount(
          snapshot.account,
          isCurrent: oauthCurrent,
          authority: oauthOrigin,
          expectedSource: snapshot.revision,
        );
      }
    } catch (error) {
      if (current()) _lastError = error.toString();
    } finally {
      if (current()) {
        _syncing = false;
        notifyListeners();
      } else if (!_disposed && run == _syncRun) {
        // Release only this run's flag without publishing outgoing feedback.
        _syncing = false;
      }
    }
  }

  Future<IcsRefreshResult> syncSubscription(
    String id, {
    bool Function()? isCurrent,
  }) async {
    if (_syncing || _disposed || AccountPreferenceWrites.isBoundaryActive) {
      return IcsRefreshResult(id, IcsRefreshStatus.canceled);
    }
    final origin = _captureIcsOrigin(isCurrent);
    if (!origin()) return IcsRefreshResult(id, IcsRefreshStatus.canceled);
    final run = ++_syncRun;
    bool current() => run == _syncRun && origin();
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final snapshot =
          await _withIcsStorage<({IcsSubscription subscription, int revision})>(
            (prefs, admitted) async {
              final rows = _readIcsSubscriptions(prefs);
              final index = rows.indexWhere(
                (row) => row.id == id && row.enabled,
              );
              if (index < 0) throw const AccountPreferenceWriteCanceled();
              _publishIcs(rows, _readIcsEvents(prefs, rows));
              return (
                subscription: rows[index],
                revision: IcsSubscriptionStorage.sourceRevision(id),
              );
            },
            isCurrent: current,
          );
      final result = await _refreshIcs(
        snapshot.subscription,
        current,
        source: snapshot.revision,
      );
      if (current()) _recordIcsResult(result, snapshot.revision);
      if (current() &&
          !result.isSuccess &&
          result.status != IcsRefreshStatus.canceled) {
        _lastError = result.error?.toString() ?? result.status.name;
      }
      return result;
    } on AccountPreferenceWriteCanceled {
      return IcsRefreshResult(id, IcsRefreshStatus.canceled);
    } catch (error) {
      if (current()) _lastError = error.toString();
      return IcsRefreshResult(
        id,
        IcsRefreshStatus.storageFailure,
        error: error,
      );
    } finally {
      if (current()) {
        _syncing = false;
        notifyListeners();
      } else if (!_disposed && run == _syncRun) {
        _syncing = false;
      }
    }
  }

  Future<IcsRefreshResult> _refreshIcs(
    IcsSubscription sub,
    bool Function() origin, {
    required int source,
  }) async {
    if (!origin() || source != IcsSubscriptionStorage.sourceRevision(sub.id)) {
      return IcsRefreshResult(sub.id, IcsRefreshStatus.canceled);
    }
    final request = IcsSubscriptionStorage.beginRequest(sub.id);
    bool current() =>
        origin() &&
        source == IcsSubscriptionStorage.sourceRevision(sub.id) &&
        IcsSubscriptionStorage.ownsRequest(sub.id, request);
    var committing = false;
    try {
      if (!current()) throw const AccountPreferenceWriteCanceled();
      final response = await http
          .get(Uri.parse(sub.url))
          .timeout(const Duration(seconds: 20));
      if (!current()) throw const AccountPreferenceWriteCanceled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return IcsRefreshResult(
          sub.id,
          IcsRefreshStatus.httpFailure,
          error: StateError('Calendar HTTP status ${response.statusCode}'),
        );
      }
      final events = IcsParser.parseValidated(
        response.body,
        subscriptionId: sub.id,
        color: Color(sub.colorValue),
      );
      final cache = jsonEncode(events.map(_calendarEventToJson).toList());
      committing = true;
      await _withIcsStorage<void>((prefs, admitted) async {
        final epoch = IcsSubscriptionStorage.epoch;
        final rows = _readIcsSubscriptions(prefs);
        final index = rows.indexWhere((row) => row.id == sub.id);
        if (index < 0 ||
            !rows[index].enabled ||
            !_sameIcsConfiguration(rows[index], sub)) {
          throw const AccountPreferenceWriteCanceled();
        }
        final nextEvents = _readIcsEvents(prefs, rows)..[sub.id] = events;
        rows[index] = rows[index].copyWith(lastSyncedAt: DateTime.now());
        final list = jsonEncode(rows.map((row) => row.toJson()).toList());
        final key = '$_eventsKeyPrefix${sub.id}';
        final transaction = AccountPreferenceTransaction(prefs, admitted);
        try {
          await transaction.setString(key, cache);
          await transaction.setString(_subscriptionsKey, list);
          await transaction.reload();
          if (prefs.getString(key) != cache ||
              prefs.getString(_subscriptionsKey) != list) {
            throw StateError('Calendar refresh readback failed');
          }
          transaction.commit();
          _publishIcs(rows, nextEvents);
        } catch (error) {
          await IcsSubscriptionStorage.compensateLocked(
            prefs,
            transaction,
            error,
            epoch: epoch,
          );
          rethrow;
        }
      }, isCurrent: current);
      if (!current()) throw const AccountPreferenceWriteCanceled();
      notifyListeners();
      return IcsRefreshResult(
        sub.id,
        IcsRefreshStatus.refreshed,
        eventCount: events.length,
      );
    } on AccountPreferenceWriteCanceled {
      return IcsRefreshResult(sub.id, IcsRefreshStatus.canceled);
    } on FormatException catch (error) {
      return IcsRefreshResult(
        sub.id,
        committing
            ? IcsRefreshStatus.storageFailure
            : IcsRefreshStatus.invalidCalendar,
        error: error,
      );
    } catch (error) {
      if (!current()) {
        return IcsRefreshResult(sub.id, IcsRefreshStatus.canceled);
      }
      return IcsRefreshResult(
        sub.id,
        committing
            ? IcsRefreshStatus.storageFailure
            : IcsRefreshStatus.httpFailure,
        error: error,
      );
    }
  }

  /// Refreshes the exact loaded OAuth source without refreshing ICS or peers.
  Future<OAuthSyncResult> syncOAuthAccount(
    String id, {
    required bool Function() isCurrent,
    OAuthCalendarAccount? expectedAccount,
  }) async {
    final caller = _captureIcsOrigin(isCurrent);
    if (!caller() || _syncing) {
      return OAuthSyncResult(id, OAuthSyncStatus.canceled);
    }
    final origin = _tryCaptureOAuthOrigin(caller);
    if (origin == null) {
      return OAuthSyncResult(id, OAuthSyncStatus.unavailable);
    }
    final account = _oauthAccounts.where((row) => row.id == id).firstOrNull;
    if (account == null || !account.enabled) {
      return OAuthSyncResult(id, OAuthSyncStatus.unavailable);
    }
    try {
      if (expectedAccount != null) {
        _requireSameOAuthSource(expectedAccount, account, credentials: true);
      }
      final source = _sourceRecord(account);
      if (source.scopedOwner != origin.workspace.record.scopedOwner ||
          source.oauthIncarnation != origin.workspace.record.oauthIncarnation) {
        return OAuthSyncResult(id, OAuthSyncStatus.canceled);
      }
      if (expectedAccount != null) {
        final expected = _sourceRecord(expectedAccount);
        if (expected.encode() != source.encode() ||
            !_sameOAuthSyncPayload(expectedAccount, expected)) {
          return OAuthSyncResult(id, OAuthSyncStatus.canceled);
        }
      }
      bool Function()? originalCurrent;
      final result = await _syncOAuthAccount(
        account,
        authority: origin,
        expectedSource: OAuthCalendarStorage.sourceRevision(id),
        expectedOpening: expectedAccount == null
            ? null
            : _sourceRecord(expectedAccount),
        onOutcomeReady: (current) => originalCurrent = current,
      );
      if (originalCurrent?.call() != true) {
        return OAuthSyncResult(id, OAuthSyncStatus.canceled);
      }
      if (result.isSuccess) {
        notifyListeners();
        if (originalCurrent?.call() != true) {
          return OAuthSyncResult(id, OAuthSyncStatus.canceled);
        }
      }
      return result;
    } on AccountPreferenceWriteCanceled {
      return OAuthSyncResult(id, OAuthSyncStatus.canceled);
    } on OAuthWorkspaceCodecException {
      return OAuthSyncResult(id, OAuthSyncStatus.unavailable);
    }
  }

  bool _sameOAuthSyncPayload(
    OAuthCalendarAccount account,
    OAuthOwnedSourceRecord record,
  ) {
    final payload = account.toJson();
    return _oauthSyncKeys.every((key) => payload[key] == record.account[key]);
  }

  bool _sameOAuthSyncConfiguration(
    OAuthOwnedSourceRecord original,
    OAuthOwnedSourceRecord current,
  ) =>
      original.scopedOwner == current.scopedOwner &&
      original.oauthIncarnation == current.oauthIncarnation &&
      original.sourceIncarnation == current.sourceIncarnation &&
      original.credentialRevision == current.credentialRevision &&
      _oauthSyncKeys.every(
        (key) => original.account[key] == current.account[key],
      );

  static const _oauthSyncKeys = [
    'provider',
    'clientId',
    'clientSecret',
    'redirectUri',
    'calendarId',
    'enabled',
    'scope',
    'accessToken',
    'refreshToken',
    'expiresAt',
  ];

  Future<OAuthSyncResult> _syncOAuthAccount(
    OAuthCalendarAccount snapshot, {
    bool Function()? isCurrent,
    int? expectedSource,
    _OAuthAction? authority,
    OAuthOwnedSourceRecord? expectedOpening,
    void Function(bool Function())? onOutcomeReady,
  }) async {
    final origin = authority ?? _captureOAuthOrigin(isCurrent);
    final source =
        expectedSource ?? OAuthCalendarStorage.sourceRevision(snapshot.id);
    bool credentialCurrent() =>
        origin() && source == OAuthCalendarStorage.sourceRevision(snapshot.id);
    // Reject an obsolete outer run before allocating shared request ownership.
    // It must not invalidate a current peer's response while waiting for ICS.
    if (!credentialCurrent()) {
      return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
    }
    int? request;
    final owner = AccountLocalDataCleaner.accountDataGeneration;
    final reset = OAuthCalendarStorage.resetRevision;
    final writes = AccountPreferenceWrites.generation;
    final epoch = OAuthCalendarStorage.epoch;
    bool current() {
      final ownedRequest = request;
      return credentialCurrent() &&
          (ownedRequest == null ||
              OAuthCalendarStorage.ownsRequest(snapshot.id, ownedRequest));
    }

    late SharedPreferences store;
    OAuthOwnedRefreshJournal? dispatchedRefresh;
    var networkStarted = false;
    var fetchingEvents = false;
    var committing = false;
    bool resultCurrent() {
      final ownedRequest = request;
      return current() ||
          (committing &&
              origin.localCurrent() &&
              origin.scopeRetainable &&
              source == OAuthCalendarStorage.sourceRevision(snapshot.id) &&
              (ownedRequest == null ||
                  OAuthCalendarStorage.ownsRequest(snapshot.id, ownedRequest)));
    }

    onOutcomeReady?.call(resultCurrent);
    try {
      var account = await _withOAuthStorage<OAuthCalendarAccount>(
        origin,
        (prefs, admitted) async {
          store = prefs;
          final rows = _readOAuthAccounts(prefs, origin);
          final matches = rows.where(
            (row) => row.id == snapshot.id && row.enabled,
          );
          if (matches.isEmpty) throw const AccountPreferenceWriteCanceled();
          _requireSameOAuthSource(snapshot, matches.single, credentials: true);
          if (!_sameOAuthSyncConfiguration(
            _sourceRecord(snapshot),
            _sourceRecord(matches.single),
          )) {
            throw const AccountPreferenceWriteCanceled();
          }
          if (expectedOpening != null &&
              expectedOpening.encode() !=
                  _sourceRecord(matches.single).encode()) {
            throw const AccountPreferenceWriteCanceled();
          }
          _requireSettledOAuthSource(prefs, origin, snapshot.id);
          if (matches.single.expiresAt.isBefore(
                DateTime.now().add(const Duration(minutes: 2)),
              ) &&
              _readOAuthRefresh(prefs, origin) != null) {
            // Another source owns the single refresh slot. Refuse before this
            // source obtains request ownership; its remote outcome is known.
            throw const AccountPreferenceWriteCanceled();
          }
          return matches.single;
        },
        condition: current,
        afterReadback: (prefs, admittedAccount) {
          final fresh = _readOAuthAccounts(
            prefs,
            origin,
          ).where((row) => row.id == snapshot.id && row.enabled).firstOrNull;
          if (fresh == null ||
              _sourceRecord(fresh).encode() !=
                  _sourceRecord(admittedAccount).encode()) {
            throw const AccountPreferenceWriteCanceled();
          }
          _requireSettledOAuthSource(prefs, origin, snapshot.id);
          if (fresh.expiresAt.isBefore(
                DateTime.now().add(const Duration(minutes: 2)),
              ) &&
              _readOAuthRefresh(prefs, origin) != null) {
            throw const AccountPreferenceWriteCanceled();
          }
          final receipts = _oauthCandidates.values.where(
            (candidate) =>
                identical(candidate.store, store) &&
                identical(candidate.authority.auth, origin.auth) &&
                identical(candidate.authority.workspace, origin.workspace) &&
                candidate.eligible &&
                !candidate.committed &&
                candidate.account.id == admittedAccount.id,
          );
          if (receipts.isNotEmpty) {
            throw OAuthLocalCommitRequired(receipts.first.receipt);
          }
          if (!current()) throw const AccountPreferenceWriteCanceled();
          if (_oauthRefreshing[store]?.contains(admittedAccount.id) == true) {
            throw const AccountPreferenceWriteCanceled();
          }
          // The final readback, source exclusion and request allocation occur
          // in the same lane; a peer claim cannot interleave between them.
          request = OAuthCalendarStorage.beginRequest(snapshot.id);
        },
      );
      if (!current()) {
        throw const AccountPreferenceWriteCanceled();
      }
      if (account.expiresAt.isBefore(
        DateTime.now().add(const Duration(minutes: 2)),
      )) {
        if (!current()) throw const AccountPreferenceWriteCanceled();
        await _withOAuthStorage<void>(origin, (prefs, admitted) async {
          final fresh = _readOAuthAccounts(
            prefs,
            origin,
          ).where((row) => row.id == account.id && row.enabled).firstOrNull;
          if (fresh == null) throw const AccountPreferenceWriteCanceled();
          _requireSameOAuthSource(account, fresh, credentials: true);
          _requireSettledOAuthSource(prefs, origin, account.id);
          if (_readOAuthRefresh(prefs, origin) != null) {
            throw const AccountPreferenceWriteCanceled();
          }
          final original = _sourceRecord(fresh);
          if (original.encode() != _sourceRecord(account).encode()) {
            throw const AccountPreferenceWriteCanceled();
          }
          final claim = OAuthOwnedRefreshJournal.createDispatched(
            scope: origin.workspace.record,
            operationId: OAuthCalendarClient.generateCodeVerifier(),
            receiptHandle: OAuthCalendarClient.generateCodeVerifier(),
            originalSource: original,
            dispatchedAt: DateTime.now().toUtc(),
          );
          await _commitOwnedOAuth(
            prefs,
            {OAuthCalendarStorage.refreshJournalKey: claim.encode()},
            admitted,
            origin,
          );
          dispatchedRefresh = claim;
        }, condition: current);
        if (!current()) throw const AccountPreferenceWriteCanceled();
        final refreshing = _oauthRefreshing.putIfAbsent(
          store,
          () => <String>{},
        );
        if (!refreshing.add(account.id)) {
          throw StateError('OAuth credential refresh already in progress');
        }
        try {
          networkStarted = true;
          final renewed = await OAuthCalendarClient.refreshAccessToken(
            account,
            client: oauthHttpClient,
          );
          final fixed = renewed.copyWith(expiresAt: renewed.expiresAt.toUtc());
          final target = dispatchedRefresh!.originalSource.withAccount(
            fixed.toJson(),
          );
          _ownedOAuthRows[fixed] = target;
          final received = dispatchedRefresh!.received(
            returnedSource: target,
            receivedAt: DateTime.now().toUtc(),
          );
          final candidate = _OAuthCredentialCandidate(
            fixed,
            refreshing: true,
            owner: owner,
            reset: reset,
            writes: writes,
            epoch: epoch,
            store: store,
            expectedSource: source,
            authority: origin,
            originalSource: dispatchedRefresh!.originalSource,
            refresh: received,
            receiptHandle: received.receiptHandle,
          );
          if (candidate.retainable) {
            _oauthCandidates[candidate.receipt.handle] = candidate;
          }
          // Save-only authority retains the original issuer and source while
          // UI/request cancellation must still prevent installation/events.
          final saveOrigin = _OAuthAction(
            origin.auth,
            origin.lease,
            () => true,
          );
          committing = true;
          try {
            await _stageOAuthReceived(candidate, saveOrigin);
          } on OAuthStorageIndeterminate {
            rethrow;
          } on AccountPreferenceWriteCanceled {
            rethrow;
          } catch (_) {
            if (!current() || !candidate.eligible) {
              throw const AccountPreferenceWriteCanceled();
            }
            throw OAuthLocalCommitRequired(candidate.receipt);
          }
          if (!current()) {
            throw const AccountPreferenceWriteCanceled();
          }
          committing = true;
          account = await _commitOAuthCandidate(
            candidate,
            origin,
            preserveStorageFailure: true,
            operationCurrent: current,
          );
          committing = false;
        } finally {
          refreshing.remove(account.id);
          if (refreshing.isEmpty &&
              identical(_oauthRefreshing[store], refreshing)) {
            _oauthRefreshing.remove(store);
          }
        }
      }
      if (!current()) throw const AccountPreferenceWriteCanceled();
      networkStarted = true;
      fetchingEvents = true;
      final events = await _fetchOAuthEvents(
        account,
        isCurrent: current,
        authority: origin,
      );
      fetchingEvents = false;
      committing = true;
      await _withOAuthStorage<void>(origin, (prefs, admitted) async {
        final rows = _readOAuthAccounts(prefs, origin);
        final index = rows.indexWhere(
          (row) => row.id == account.id && row.enabled,
        );
        if (index < 0) throw const AccountPreferenceWriteCanceled();
        _requireSameOAuthSource(account, rows[index], credentials: true);
        _requireSettledOAuthSource(prefs, origin, account.id);
        rows[index] = rows[index].copyWith(lastSyncedAt: DateTime.now());
        await _commitOwnedOAuth(
          prefs,
          {
            '$_oauthEventsKeyPrefix${account.id}':
                OAuthOwnedEventsRecord.create(
                  source: _sourceRecord(rows[index]),
                  events: events.map(_calendarEventToJson).toList(),
                ).encode(),
            _oauthAccountsKey: _encodeOAuthAccounts(rows, origin),
          },
          admitted,
          origin,
        );
        if (!admitted()) throw const AccountPreferenceWriteCanceled();
        _publishOAuth(prefs, rows, origin);
      }, condition: current);
      committing = false;
      if (!current()) throw const AccountPreferenceWriteCanceled();
      return OAuthSyncResult(
        snapshot.id,
        OAuthSyncStatus.refreshed,
        eventCount: events.length,
      );
    } on AccountPreferenceWriteCanceled {
      // Obsolete requests do not publish an error in their successor's state.
      return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
    } on OAuthLocalCommitRequired catch (error) {
      if (!current()) {
        return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
      }
      _lastError = 'OAuth credentials require local confirmation';
      return OAuthSyncResult(
        snapshot.id,
        OAuthSyncStatus.localCommitRequired,
        receipt: error.receipt,
      );
    } on OAuthRefreshDispatchUnknown {
      if (!current()) {
        return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
      }
      _lastError = OAuthSyncStatus.dispatchUnknown.name;
      return OAuthSyncResult(snapshot.id, OAuthSyncStatus.dispatchUnknown);
    } on OAuthScopedWorkspaceUnavailable {
      return OAuthSyncResult(snapshot.id, OAuthSyncStatus.unavailable);
    } on OAuthStorageIndeterminate {
      if (!resultCurrent()) {
        return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
      }
      _lastError = OAuthSyncStatus.storageFailure.name;
      return OAuthSyncResult(snapshot.id, OAuthSyncStatus.storageFailure);
    } on _OAuthSyncStorageFailure {
      if (!current()) {
        return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
      }
      _lastError = OAuthSyncStatus.storageFailure.name;
      return OAuthSyncResult(snapshot.id, OAuthSyncStatus.storageFailure);
    } on FormatException {
      if (!current()) {
        return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
      }
      final status = committing || !networkStarted
          ? OAuthSyncStatus.storageFailure
          : fetchingEvents
          ? OAuthSyncStatus.invalidCalendar
          : dispatchedRefresh != null
          ? OAuthSyncStatus.dispatchUnknown
          : OAuthSyncStatus.httpFailure;
      _lastError = status.name;
      return OAuthSyncResult(
        snapshot.id,
        status,
        diagnosticStatus: status == OAuthSyncStatus.dispatchUnknown
            ? OAuthSyncStatus.httpFailure
            : null,
      );
    } catch (error) {
      if (!current()) {
        return OAuthSyncResult(snapshot.id, OAuthSyncStatus.canceled);
      }
      final status = committing || !networkStarted
          ? OAuthSyncStatus.storageFailure
          : dispatchedRefresh != null && !fetchingEvents
          ? OAuthSyncStatus.dispatchUnknown
          : OAuthSyncStatus.httpFailure;
      _lastError = status.name;
      return OAuthSyncResult(
        snapshot.id,
        status,
        diagnosticStatus: status == OAuthSyncStatus.dispatchUnknown
            ? OAuthSyncStatus.httpFailure
            : null,
      );
    }
  }

  Future<List<CalendarEvent>> _fetchOAuthEvents(
    OAuthCalendarAccount account, {
    required bool Function() isCurrent,
    required _OAuthAction authority,
  }) async {
    Future<void> ensureCurrent() async {
      if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
      try {
        await _withOAuthStorage<void>(authority, (prefs, current) async {
          final row = _readOAuthAccounts(
            prefs,
            authority,
          ).where((row) => row.id == account.id && row.enabled).firstOrNull;
          if (row == null) throw const AccountPreferenceWriteCanceled();
          _requireSameOAuthSource(account, row, credentials: true);
          _requireSettledOAuthSource(prefs, authority, account.id);
        }, condition: isCurrent);
      } on AccountPreferenceWriteCanceled {
        rethrow;
      } on OAuthStorageIndeterminate {
        rethrow;
      } catch (_) {
        throw const _OAuthSyncStorageFailure();
      }
    }

    final now = DateTime.now();
    final timeMin = now.subtract(const Duration(days: 30)).toUtc();
    final timeMax = now.add(const Duration(days: 180)).toUtc();
    final google = account.provider == OAuthCalendarProvider.google;
    final first = google
        ? _googleEventsUri(account, timeMin, timeMax)
        : _outlookEventsUri(account, timeMin, timeMax);
    Uri? next = first;
    final visited = <String>{};
    final events = <CalendarEvent>[];
    while (next != null) {
      await ensureCurrent();
      if (!visited.add(next.toString())) {
        throw const FormatException('Repeated OAuth calendar page');
      }
      final client = oauthHttpClient ?? http.Client();
      late http.Response response;
      try {
        response = await client
            .get(
              next,
              headers: {
                'Authorization': 'Bearer ${account.accessToken}',
                'Accept': 'application/json',
                if (!google) 'Prefer': 'outlook.timezone="UTC"',
              },
            )
            .timeout(const Duration(seconds: 20));
      } finally {
        if (oauthHttpClient == null) client.close();
      }
      await ensureCurrent();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _OAuthHttpFailure();
      }
      final decoded = jsonDecode(response.body);
      final key = google ? 'items' : 'value';
      if (decoded is! Map ||
          decoded.containsKey('error') ||
          decoded[key] is! List) {
        throw const FormatException('Invalid OAuth calendar collection');
      }
      for (final value in decoded[key] as List) {
        if (value is! Map) {
          throw const FormatException('Invalid OAuth calendar event');
        }
        final item = Map<String, dynamic>.from(value);
        final event = google
            ? _googleEventToCalendarEvent(item, account)
            : _outlookEventToCalendarEvent(item, account);
        if (event != null) {
          events.add(event);
        } else if (!(google
            ? item['status'] == 'cancelled'
            : item['isCancelled'] == true)) {
          throw const FormatException('Invalid OAuth calendar event');
        }
      }
      final continuation =
          decoded[google ? 'nextPageToken' : '@odata.nextLink'];
      if (continuation == null || continuation == '') {
        next = null;
      } else {
        if (continuation is! String || continuation.trim().isEmpty) {
          throw const FormatException('Invalid OAuth calendar continuation');
        }
        if (google) {
          next = first.replace(
            queryParameters: {
              ...first.queryParameters,
              'pageToken': continuation,
            },
          );
        } else {
          final link = Uri.tryParse(continuation);
          // Never forward the bearer token to a foreign origin in a nextLink.
          if (link == null ||
              link.scheme != 'https' ||
              link.host != first.host ||
              link.port != first.port ||
              link.userInfo.isNotEmpty ||
              link.fragment.isNotEmpty ||
              link.path != first.path) {
            throw const FormatException(
              'Untrusted OAuth calendar continuation',
            );
          }
          next = link;
        }
      }
    }
    await ensureCurrent();
    return events;
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

  static List<CalendarEvent> parseValidated(
    String body, {
    required String subscriptionId,
    required Color color,
  }) {
    final lines = _unfold(
      body.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n')),
    );
    if (lines.isEmpty ||
        lines.first.trim().toUpperCase() != 'BEGIN:VCALENDAR' ||
        lines.last.trim().toUpperCase() != 'END:VCALENDAR') {
      throw const FormatException('Calendar envelope missing');
    }
    final stack = <String>[];
    final events = <CalendarEvent>[];
    var eventStart = -1;
    var version = false;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim().toUpperCase();
      if (line.startsWith('BEGIN:')) {
        final component = line.substring(6);
        if (component.isEmpty ||
            (component == 'VCALENDAR' && stack.isNotEmpty) ||
            (index > 0 && stack.isEmpty)) {
          throw const FormatException('Invalid calendar component');
        }
        if (component == 'VEVENT') {
          if (stack.length != 1 || stack.single != 'VCALENDAR') {
            throw const FormatException('Invalid event nesting');
          }
          eventStart = index + 1;
        }
        stack.add(component);
      } else if (line.startsWith('END:')) {
        final component = line.substring(4);
        if (stack.isEmpty || stack.last != component) {
          throw const FormatException('Unbalanced calendar component');
        }
        if (component == 'VEVENT') {
          final event = _parseEvent(
            lines.sublist(eventStart, index),
            subscriptionId: subscriptionId,
            color: color,
            allowUntitled: true,
          );
          if (event == null) {
            throw const FormatException('Invalid calendar event');
          }
          events.add(event);
          eventStart = -1;
        }
        stack.removeLast();
      } else {
        if (stack.isEmpty || !line.contains(':')) {
          throw const FormatException('Invalid calendar property');
        }
        if (stack.length == 1 && line == 'VERSION:2.0') version = true;
      }
    }
    if (stack.isNotEmpty || !version) {
      throw const FormatException('Incomplete calendar');
    }
    return events;
  }

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
    bool allowUntitled = false,
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
    if (uid == null ||
        uid.isEmpty ||
        dtStart == null ||
        (!allowUntitled && summary == null)) {
      return null;
    }
    return CalendarEvent(
      id: 'ics_${subscriptionId}_$uid',
      title: summary ?? '',
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
