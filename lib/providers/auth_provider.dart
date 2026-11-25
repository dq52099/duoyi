import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_config.dart';
import '../services/account_local_data_cleaner.dart';
import '../core/oauth_calendar_storage.dart';
import '../core/oauth_calendar_inventory.dart';
import '../core/account_preference_writes.dart';
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

class AccountLocalDataCleanupBlockedException implements Exception {
  final String message;

  const AccountLocalDataCleanupBlockedException(this.message);

  @override
  String toString() => message;
}

/// Binds a form or local asynchronous action to its originating login session.
///
/// Obtain it before opening a picker/dialog and pass it to account mutations.
/// Profile refreshes keep it valid; account lifecycle changes invalidate it.
/// It does not replace a view's mounted check or cancel a dispatched request.
final class AuthSessionLease {
  final AuthProvider _owner;
  final ApiClient _client;
  final int _epoch;
  final String? _userId;
  final String? _token;

  AuthSessionLease._(this._owner, this._client, this._epoch, AuthState state)
    : _userId = state.userId,
      _token = state.token;
}

/// Guest authority requires verified storage hydration and exact owner absence.
/// A default AuthState alone is not evidence of a prepared guest workspace.
final class AuthGuestWorkspaceLease {
  final AuthProvider _owner;
  final ApiClient _client;
  final int _epoch;
  AuthGuestWorkspaceLease._(this._owner, this._client, this._epoch);
}

final class AuthOAuthScopeInitializationTicket {
  AuthOAuthScopeInitializationTicket._();
  @override
  String toString() => 'AuthOAuthScopeInitializationTicket';
}

final class AuthOAuthScopeInitializationOutcome {
  final AuthOAuthScopeInitializationTicket? ticket;
  final bool Function() _originalCurrent;
  AuthOAuthScopeInitializationOutcome._(this.ticket, this._originalCurrent);
  bool get isCurrent => _originalCurrent();
}

final class _AuthOAuthInitializationBinding {
  final AuthOAuthScopeInitializationTicket ticket =
      AuthOAuthScopeInitializationTicket._();
  final OAuthScopeInitializationTicket coreTicket;
  final SharedPreferences preferences;
  final bool account;
  final bool Function() resourcesCurrent;
  _AuthOAuthInitializationBinding(
    this.coreTicket,
    this.preferences,
    this.account,
    this.resourcesCurrent,
  );
}

/// Only the real Auth issuer can wrap a verified durable guest identity.
/// Consumers must still reload and compare [workspace] inside the storage lane.
final class AuthGuestOAuthScopeLease {
  final AuthGuestWorkspaceLease _guest;
  final int _preparation;
  final OAuthScopedWorkspaceSnapshot workspace;
  AuthGuestOAuthScopeLease._(this._guest, this._preparation, this.workspace);
}

final class _VerifiedGuestAuthStorage {
  final SharedPreferences preferences;
  final Object? authState;
  _VerifiedGuestAuthStorage(this.preferences, this.authState);
}

/// Recovery-only authority. Ordinary OAuth remains unavailable until the
/// exact original diagnostic has been restored and independently validated.
final class AuthGuestOAuthReconciliationLease {
  final AuthGuestWorkspaceLease _guest;
  final int _preparation;
  final _VerifiedGuestAuthStorage _evidence;
  final OAuthScopedReconciliationSnapshot recovery;
  const AuthGuestOAuthReconciliationLease._(
    this._guest,
    this._preparation,
    this._evidence,
    this.recovery,
  );
}

final class _VerifiedAccountAuthStorage {
  final SharedPreferences preferences;
  final Object? authState;
  final String accountOwner;
  const _VerifiedAccountAuthStorage(
    this.preferences,
    this.authState,
    this.accountOwner,
  );
}

/// Only Auth can issue this capability after checked account storage preparation.
final class AuthOAuthScopeLease {
  final AuthGuestOAuthScopeLease? _guest;
  final AuthSessionLease? _session;
  final _VerifiedAccountAuthStorage? _evidence;
  final int _preparation;
  final OAuthScopedWorkspaceSnapshot workspace;
  AuthOAuthScopeLease._guest(AuthGuestOAuthScopeLease guest)
    : _guest = guest,
      _session = null,
      _evidence = null,
      _preparation = 0,
      workspace = guest.workspace;
  const AuthOAuthScopeLease._account(
    this._session,
    this._evidence,
    this._preparation,
    this.workspace,
  ) : _guest = null;
}

final class AuthOAuthReconciliationLease {
  final AuthOAuthScopeLease _lease;
  final OAuthScopedReconciliationSnapshot recovery;
  const AuthOAuthReconciliationLease._(this._lease, this.recovery);
}

/// 登录态 + 连接到服务器的 ApiClient。
///
/// 服务器地址完全由 [AppConfig.bakedServerUrl] 决定，不可在运行时修改。
/// 对于历史版本在本地留下的 `auth_base_url_admin` 键，启动时会清理掉。
class AuthProvider extends ChangeNotifier {
  static const Object _uncheckedAuthState = Object();
  AuthState _state = const AuthState();
  late String _baseUrl;
  Map<String, dynamic> _serverConfig = const {};
  late ApiClient _client;
  int _stateMutationSerial = 0;
  int _sessionEpoch = 0;
  int _successfulAccountTransitionRevision = 0;
  bool _isDisposed = false;
  bool _accountTransitionInProgress = false;
  bool _localAccountDataBlocked = false;
  bool _authStorageReady = false;
  bool _verifiedGuestOwnerAbsence = false;
  _VerifiedGuestAuthStorage? _verifiedGuestAuthStorage;
  OAuthScopedWorkspaceSnapshot? _preparedGuestOAuthScope;
  int _guestOAuthPreparation = 0;
  int _guestOAuthPreparationRequest = 0;
  _VerifiedAccountAuthStorage? _verifiedAccountAuthStorage;
  OAuthScopedWorkspaceSnapshot? _preparedAccountOAuthScope;
  int _accountOAuthPreparation = 0;
  int _accountOAuthPreparationRequest = 0;
  _AuthOAuthInitializationBinding? _oauthInitialization;
  String? _verifiedWidgetOwnerIdentity;
  Future<void> _accountWritebackTail = Future<void>.value();
  int _refreshMeRequestSerial = 0;
  int _lastAppliedRefreshMeRequestSerial = 0;
  static const _refreshMeMinInterval = Duration(seconds: 30);
  Future<void>? _refreshMeInFlight;
  DateTime? _lastRefreshMeAt;
  String? _lastRefreshMeToken;
  int _lastRefreshMeMutationSerial = -1;
  static const _serverConfigRefreshTtl = Duration(seconds: 30);
  Future<void>? _serverConfigRefreshInFlight;
  DateTime? _lastServerConfigRefreshAt;

  /// 拉取到 /api/config 之后会触发，供 AiService / CloudSyncProvider 订阅。
  void Function(Map<String, dynamic> cfg)? onServerConfigChanged;
  Future<void> Function(AuthState state)? onAccountProfileChanged;
  Future<void> Function(Map<String, dynamic> payload)? onAccountPayloadChanged;
  Future<void> Function(AuthState previous, AuthState next)?
  onAccountIdentityChanging;
  Future<void> Function()? onBeforeAccountLogout;
  Future<void> Function()? onAccountLoggedOut;

  /// Synchronously revokes a widget writer before an account owner write.
  void Function()? onWidgetPublicationAuthorityRevoked;

  AuthState get state => _state;

  /// Invalidates retained UI authority across guest/login/logout transitions.
  int get sessionGeneration => _sessionEpoch;

  /// Advances only after every required transition write/cleanup has succeeded.
  int get successfulAccountTransitionRevision =>
      _successfulAccountTransitionRevision;
  bool get isAccountTransitionInProgress => _accountTransitionInProgress;
  bool get isLocalAccountDataBlocked => _localAccountDataBlocked;
  bool get isGuestWorkspaceReady =>
      _authStorageReady &&
      _verifiedGuestOwnerAbsence &&
      !_state.isLoggedIn &&
      !_isDisposed &&
      !_accountTransitionInProgress &&
      !_localAccountDataBlocked;

  AuthGuestWorkspaceLease captureGuestWorkspaceLease() {
    if (!isGuestWorkspaceReady) {
      throw const ApiException('账号已发生变化，请在当前账号重试操作。');
    }
    return AuthGuestWorkspaceLease._(this, _client, _sessionEpoch);
  }

  bool isGuestWorkspaceLeaseCurrent(AuthGuestWorkspaceLease lease) =>
      isGuestWorkspaceReady &&
      identical(lease._owner, this) &&
      identical(lease._client, _client) &&
      lease._epoch == _sessionEpoch;

  AuthGuestOAuthScopeLease captureGuestOAuthScopeLease() {
    final guest = captureGuestWorkspaceLease();
    final scope = _preparedGuestOAuthScope;
    if (scope == null ||
        !OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(scope)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return AuthGuestOAuthScopeLease._(guest, _guestOAuthPreparation, scope);
  }

  bool isGuestOAuthScopeLeaseCurrent(AuthGuestOAuthScopeLease lease) =>
      isGuestWorkspaceLeaseCurrent(lease._guest) &&
      lease._preparation == _guestOAuthPreparation &&
      identical(lease.workspace, _preparedGuestOAuthScope) &&
      OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(lease.workspace);

  /// Retention never grants adoption, publication, HTTP or ordinary writes.
  bool isGuestOAuthScopeLeaseRetainable(AuthGuestOAuthScopeLease lease) =>
      isGuestWorkspaceLeaseCurrent(lease._guest) &&
      lease._preparation == _guestOAuthPreparation &&
      identical(lease.workspace, _preparedGuestOAuthScope) &&
      (OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(lease.workspace) ||
          OAuthCalendarStorage.hasMatchingScopedReconciliation(
            lease.workspace,
          ));

  AuthGuestOAuthReconciliationLease captureGuestOAuthReconciliationLease() {
    final guest = captureGuestWorkspaceLease();
    final scope = _preparedGuestOAuthScope;
    final evidence = _verifiedGuestAuthStorage;
    if (scope == null || evidence == null) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return AuthGuestOAuthReconciliationLease._(
      guest,
      _guestOAuthPreparation,
      evidence,
      OAuthCalendarStorage.captureScopedReconciliation(scope),
    );
  }

  bool _isGuestOAuthReconciliationIdentityCurrent(
    AuthGuestOAuthReconciliationLease lease,
  ) =>
      isGuestWorkspaceLeaseCurrent(lease._guest) &&
      lease._preparation == _guestOAuthPreparation &&
      identical(lease._evidence, _verifiedGuestAuthStorage) &&
      identical(lease.recovery.workspace, _preparedGuestOAuthScope);

  bool isGuestOAuthReconciliationLeaseCurrent(
    AuthGuestOAuthReconciliationLease lease,
  ) =>
      _isGuestOAuthReconciliationIdentityCurrent(lease) &&
      OAuthCalendarStorage.isScopedReconciliationRuntimeCurrent(lease.recovery);

  bool isGuestOAuthReconciliationSettled(
    AuthGuestOAuthReconciliationLease lease,
  ) =>
      _isGuestOAuthReconciliationIdentityCurrent(lease) &&
      OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(
        lease.recovery.workspace,
      );

  Future<void> restoreGuestOAuthScope({bool Function()? isCurrent}) =>
      _prepareGuestOAuthScope(isCurrent: isCurrent);
  Future<void> initializeGuestOAuthScope({bool Function()? isCurrent}) =>
      _prepareGuestOAuthScope(initialize: true, isCurrent: isCurrent);
  Future<void> confirmGuestOAuthScopeInitialization({
    bool Function()? isCurrent,
    AuthOAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
  }) => _prepareGuestOAuthScope(
    confirm: true,
    isCurrent: isCurrent,
    expectedInitialization: expectedInitialization,
    requireExpectedInitialization: requireExpectedInitialization,
  );

  AuthOAuthScopeLease _captureAccountOAuthIdentity() {
    final session = captureSessionLease();
    final evidence = _verifiedAccountAuthStorage;
    final scope = _preparedAccountOAuthScope;
    if (!_authStorageReady ||
        evidence == null ||
        scope == null ||
        evidence.accountOwner != _stableAccountIdentity(_state)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return AuthOAuthScopeLease._account(
      session,
      evidence,
      _accountOAuthPreparation,
      scope,
    );
  }

  AuthOAuthScopeLease captureOAuthScopeLease() {
    if (!_state.isLoggedIn) {
      return AuthOAuthScopeLease._guest(captureGuestOAuthScopeLease());
    }
    final lease = _captureAccountOAuthIdentity();
    if (!isOAuthScopeLeaseCurrent(lease)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return lease;
  }

  bool _isAccountOAuthIdentityCurrent(AuthOAuthScopeLease lease) =>
      lease._session != null &&
      isSessionLeaseCurrent(lease._session) &&
      _authStorageReady &&
      identical(lease._evidence, _verifiedAccountAuthStorage) &&
      lease._evidence?.accountOwner == _stableAccountIdentity(_state) &&
      lease._preparation == _accountOAuthPreparation &&
      identical(lease.workspace, _preparedAccountOAuthScope);

  bool isOAuthScopeLeaseCurrent(AuthOAuthScopeLease lease) =>
      lease._guest != null
      ? isGuestOAuthScopeLeaseCurrent(lease._guest)
      : _isAccountOAuthIdentityCurrent(lease) &&
            OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(
              lease.workspace,
            );

  bool isOAuthScopeLeaseRetainable(AuthOAuthScopeLease lease) =>
      lease._guest != null
      ? isGuestOAuthScopeLeaseRetainable(lease._guest)
      : _isAccountOAuthIdentityCurrent(lease) &&
            (OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(
                  lease.workspace,
                ) ||
                OAuthCalendarStorage.hasMatchingScopedReconciliation(
                  lease.workspace,
                ));

  AuthOAuthReconciliationLease captureOAuthReconciliationLease() {
    final AuthOAuthScopeLease lease;
    if (_state.isLoggedIn) {
      lease = _captureAccountOAuthIdentity();
    } else {
      final recovery = captureGuestOAuthReconciliationLease();
      lease = AuthOAuthScopeLease._guest(
        AuthGuestOAuthScopeLease._(
          recovery._guest,
          recovery._preparation,
          recovery.recovery.workspace,
        ),
      );
    }
    if (!isOAuthScopeLeaseRetainable(lease)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return AuthOAuthReconciliationLease._(
      lease,
      OAuthCalendarStorage.captureScopedReconciliation(lease.workspace),
    );
  }

  bool isOAuthReconciliationLeaseCurrent(AuthOAuthReconciliationLease lease) =>
      isOAuthScopeLeaseRetainable(lease._lease) &&
      OAuthCalendarStorage.isScopedReconciliationRuntimeCurrent(lease.recovery);

  bool isOAuthReconciliationSettled(AuthOAuthReconciliationLease lease) =>
      isOAuthScopeLeaseCurrent(lease._lease);

  Future<void> restoreOAuthScope({bool Function()? isCurrent}) =>
      _state.isLoggedIn
      ? _prepareAccountOAuthScope(isCurrent: isCurrent)
      : restoreGuestOAuthScope(isCurrent: isCurrent);
  Future<void> initializeOAuthScope({bool Function()? isCurrent}) =>
      _state.isLoggedIn
      ? _prepareAccountOAuthScope(initialize: true, isCurrent: isCurrent)
      : initializeGuestOAuthScope(isCurrent: isCurrent);
  Future<void> confirmOAuthScopeInitialization({
    bool Function()? isCurrent,
    AuthOAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
  }) {
    final binding = _requireOAuthInitialization(
      expectedInitialization,
      requireExpectedInitialization,
    );
    return (binding?.account ?? _state.isLoggedIn)
        ? _prepareAccountOAuthScope(
            confirm: true,
            isCurrent: isCurrent,
            expectedInitialization: expectedInitialization,
            requireExpectedInitialization: requireExpectedInitialization,
          )
        : confirmGuestOAuthScopeInitialization(
            isCurrent: isCurrent,
            expectedInitialization: expectedInitialization,
            requireExpectedInitialization: requireExpectedInitialization,
          );
  }

  _AuthOAuthInitializationBinding? _requireOAuthInitialization(
    AuthOAuthScopeInitializationTicket? expected,
    bool required,
  ) {
    if (required && expected == null) {
      throw ArgumentError('The original initialization ticket is required');
    }
    if (expected == null) return null;
    final binding = _oauthInitialization;
    if (binding == null ||
        !identical(binding.ticket, expected) ||
        !binding.resourcesCurrent() ||
        !OAuthCalendarStorage.isScopeInitializationRuntimeCurrent(
          binding.coreTicket,
          binding.preferences,
        )) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return binding;
  }

  AuthOAuthScopeInitializationTicket? captureOAuthScopeInitializationTicket({
    required bool Function() isCurrent,
  }) {
    final binding = _oauthInitialization;
    if (!_oauthCallerCurrent(isCurrent) ||
        binding == null ||
        !binding.resourcesCurrent() ||
        !OAuthCalendarStorage.isScopeInitializationRuntimeCurrent(
          binding.coreTicket,
          binding.preferences,
        )) {
      return null;
    }
    return binding.ticket;
  }

  Future<AuthOAuthScopeInitializationTicket?> initializeOAuthScopeWithTicket({
    required bool Function() isCurrent,
  }) async {
    final outcome = await initializeOAuthScopeWithOutcome(isCurrent: isCurrent);
    if (!outcome.isCurrent) throw const AccountPreferenceWriteCanceled();
    return outcome.ticket;
  }

  /// Carries the original completion predicate through consumer await boundaries.
  Future<AuthOAuthScopeInitializationOutcome> initializeOAuthScopeWithOutcome({
    required bool Function() isCurrent,
  }) => _prepareOAuthScopeWithOutcome(initialize: true, isCurrent: isCurrent);

  Future<AuthOAuthScopeInitializationOutcome>
  confirmOAuthScopeInitializationWithOutcome({
    required bool Function() isCurrent,
    required AuthOAuthScopeInitializationTicket expectedInitialization,
  }) => _prepareOAuthScopeWithOutcome(
    confirm: true,
    isCurrent: isCurrent,
    expectedInitialization: expectedInitialization,
  );

  Future<AuthOAuthScopeInitializationOutcome> _prepareOAuthScopeWithOutcome({
    bool initialize = false,
    bool confirm = false,
    required bool Function() isCurrent,
    AuthOAuthScopeInitializationTicket? expectedInitialization,
  }) async {
    final initialization = _requireOAuthInitialization(
      expectedInitialization,
      confirm,
    );
    bool Function()? originalOutcomeCurrent;
    void captureOutcome(bool Function() current) =>
        originalOutcomeCurrent = current;
    try {
      if (initialization?.account ?? _state.isLoggedIn) {
        await _prepareAccountOAuthScope(
          initialize: initialize,
          confirm: confirm,
          isCurrent: isCurrent,
          expectedInitialization: expectedInitialization,
          requireExpectedInitialization: confirm,
          returnPendingTicket: true,
          onOutcomeReady: captureOutcome,
        );
      } else {
        await _prepareGuestOAuthScope(
          initialize: initialize,
          confirm: confirm,
          isCurrent: isCurrent,
          expectedInitialization: expectedInitialization,
          requireExpectedInitialization: confirm,
          returnPendingTicket: true,
          onOutcomeReady: captureOutcome,
        );
      }
      if (!_oauthCallerCurrent(isCurrent) ||
          originalOutcomeCurrent?.call() != true) {
        throw const AccountPreferenceWriteCanceled();
      }
      return AuthOAuthScopeInitializationOutcome._(
        null,
        originalOutcomeCurrent!,
      );
    } on OAuthScopeInitializationPending catch (pending) {
      if (!_oauthCallerCurrent(isCurrent) ||
          (originalOutcomeCurrent != null && !originalOutcomeCurrent!())) {
        throw const AccountPreferenceWriteCanceled();
      }
      if (originalOutcomeCurrent == null) rethrow;
      final binding = _oauthInitialization;
      if (pending.ticket == null ||
          binding == null ||
          !identical(binding.coreTicket, pending.ticket) ||
          !binding.resourcesCurrent() ||
          !OAuthCalendarStorage.isScopeInitializationRuntimeCurrent(
            binding.coreTicket,
            binding.preferences,
          )) {
        rethrow;
      }
      return AuthOAuthScopeInitializationOutcome._(
        binding.ticket,
        () =>
            originalOutcomeCurrent!() &&
            identical(_oauthInitialization, binding) &&
            binding.resourcesCurrent() &&
            OAuthCalendarStorage.isScopeInitializationRuntimeCurrent(
              binding.coreTicket,
              binding.preferences,
            ),
      );
    }
  }

  static bool _oauthCallerCurrent(bool Function()? isCurrent) {
    try {
      return isCurrent?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _prepareAccountOAuthScope({
    bool initialize = false,
    bool confirm = false,
    bool Function()? isCurrent,
    AuthOAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
    bool returnPendingTicket = false,
    void Function(bool Function())? onOutcomeReady,
  }) async {
    if (!_oauthCallerCurrent(isCurrent)) {
      throw const AccountPreferenceWriteCanceled();
    }
    final initialization = _requireOAuthInitialization(
      expectedInitialization,
      requireExpectedInitialization,
    );
    if (initialization != null && !initialization.account) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    final session = captureSessionLease();
    final evidence = _verifiedAccountAuthStorage;
    if (!_authStorageReady ||
        evidence == null ||
        evidence.accountOwner != _stableAccountIdentity(_state)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    final failure = OAuthCalendarStorage.failure;
    if (failure != null) throw failure;
    final preferences = evidence.preferences;
    final originalOwner = preferences.get(OAuthCalendarStorage.scopeOwnerKey);
    var preparation = _accountOAuthPreparation;
    final request = ++_accountOAuthPreparationRequest;
    final epoch = OAuthCalendarStorage.epoch;
    final reset = OAuthCalendarStorage.resetRevision;
    final writes = AccountPreferenceWrites.generation;
    final accounts = AccountLocalDataCleaner.accountDataGeneration;
    bool resourcesCurrent() =>
        isSessionLeaseCurrent(session) &&
        identical(evidence, _verifiedAccountAuthStorage) &&
        preparation == _accountOAuthPreparation &&
        epoch == OAuthCalendarStorage.epoch &&
        reset == OAuthCalendarStorage.resetRevision &&
        writes == AccountPreferenceWrites.generation &&
        accounts == AccountLocalDataCleaner.accountDataGeneration;
    bool current() =>
        _oauthCallerCurrent(isCurrent) &&
        resourcesCurrent() &&
        request == _accountOAuthPreparationRequest;
    var authorityChanged = false;
    OAuthScopedWorkspaceSnapshot? completedScope;
    OAuthScopeInitializationPending? initializationPending;
    try {
      await _queueAccountWriteback(() async {
        await AccountPreferenceWrites.runResult<void>((token) {
          bool admitted() =>
              token.isCurrent &&
              current() &&
              (initialization == null || initialization.resourcesCurrent());
          return OAuthCalendarStorage.run<void>(
            () async {
              final singleton = await SharedPreferences.getInstance();
              if (!admitted() || !identical(singleton, preferences)) {
                throw const AccountPreferenceWriteCanceled();
              }
              await preferences.reload();
              if (!admitted()) throw const AccountPreferenceWriteCanceled();
              if (preferences.get('auth_state') != evidence.authState ||
                  preferences.get(
                        AccountLocalDataCleaner.accountDataOwnerKey,
                      ) !=
                      evidence.accountOwner ||
                  (!confirm &&
                      preferences.get(OAuthCalendarStorage.scopeOwnerKey) !=
                          originalOwner) ||
                  !(initialize || confirm
                      ? OAuthCalendarStorage.isEmptyAccountScopeLocked(
                          preferences,
                          expectedAccountOwner: evidence.accountOwner,
                          allowExistingOwner: true,
                        )
                      : _canRestoreAccountOAuthInventoryLocked(
                          preferences,
                          evidence.accountOwner,
                        ))) {
                throw const OAuthScopedWorkspaceUnavailable();
              }
              if (!confirm) {
                OAuthCalendarStorage.ensureAccountAdmissionLocked(preferences);
              }
              if (initialization == null) {
                preparation = ++_accountOAuthPreparation;
              }
              _preparedAccountOAuthScope = null;
              authorityChanged = true;
              final OAuthScopedWorkspaceSnapshot? scope;
              try {
                if (confirm) {
                  scope =
                      await OAuthCalendarStorage.confirmAccountScopeInitializationLocked(
                        preferences,
                        expectedAuthState: evidence.authState,
                        expectedAccountOwner: evidence.accountOwner,
                        isCurrent: admitted,
                        expectedInitialization: initialization?.coreTicket,
                        requireExpectedInitialization: initialization != null,
                      );
                } else if (initialize) {
                  scope =
                      await OAuthCalendarStorage.initializeEmptyAccountScopeLocked(
                        preferences,
                        expectedAuthState: evidence.authState,
                        expectedAccountOwner: evidence.accountOwner,
                        isCurrent: admitted,
                      );
                } else {
                  scope = OAuthCalendarStorage.readScopedWorkspaceLocked(
                    preferences,
                    expectedAuthState: evidence.authState,
                    expectedAccountOwner: evidence.accountOwner,
                  );
                }
              } on OAuthScopeInitializationPending catch (pending) {
                if (initialize &&
                    pending.ticket != null &&
                    resourcesCurrent() &&
                    OAuthCalendarStorage.isScopeInitializationRuntimeCurrent(
                      pending.ticket!,
                      preferences,
                    )) {
                  _oauthInitialization = _AuthOAuthInitializationBinding(
                    pending.ticket!,
                    preferences,
                    true,
                    resourcesCurrent,
                  );
                }
                if (!_oauthCallerCurrent(isCurrent) ||
                    (initialization != null && !current())) {
                  throw const AccountPreferenceWriteCanceled();
                }
                if (!returnPendingTicket && initialization == null) rethrow;
                initializationPending = pending;
                return;
              }
              if (!admitted()) throw const AccountPreferenceWriteCanceled();
              if (scope == null) throw const OAuthScopedWorkspaceUnavailable();
              OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
                scope,
                preferences,
              );
              OAuthCalendarInventory.validate(preferences, scope.record);
              if (initialization != null) {
                preparation = ++_accountOAuthPreparation;
              }
              _oauthInitialization = null;
              _preparedAccountOAuthScope = scope;
              completedScope = scope;
            },
            epoch: epoch,
            isCurrent: admitted,
          );
        }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
      });
    } finally {
      // Notify after leaving both queues. A listener may start a fresh action,
      // but cannot prolong the caller or the scope that was just revoked.
      if (authorityChanged && !_isDisposed) notifyListeners();
    }
    if (initializationPending != null) {
      if (!current()) throw const AccountPreferenceWriteCanceled();
      onOutcomeReady?.call(current);
      throw initializationPending!;
    }
    if (!current() ||
        completedScope == null ||
        !identical(completedScope, _preparedAccountOAuthScope) ||
        !OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(
          completedScope!,
        )) {
      throw const AccountPreferenceWriteCanceled();
    }
    final originalScope = completedScope!;
    onOutcomeReady?.call(
      () =>
          current() &&
          identical(originalScope, _preparedAccountOAuthScope) &&
          OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(originalScope),
    );
  }

  Future<void> _prepareGuestOAuthScope({
    bool initialize = false,
    bool confirm = false,
    bool Function()? isCurrent,
    AuthOAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
    bool returnPendingTicket = false,
    void Function(bool Function())? onOutcomeReady,
  }) async {
    if (!_oauthCallerCurrent(isCurrent)) {
      throw const AccountPreferenceWriteCanceled();
    }
    // Capture originating Auth/client/session/store before the first await.
    final initialization = _requireOAuthInitialization(
      expectedInitialization,
      requireExpectedInitialization,
    );
    if (initialization != null && initialization.account) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    final guest = captureGuestWorkspaceLease();
    final evidence = _verifiedGuestAuthStorage;
    if (evidence == null) throw const OAuthScopedWorkspaceUnavailable();
    // An unsuccessful ordinary prepare must not destroy the original private
    // scope evidence needed by this issuer's matching-diagnostic recovery.
    final failure = OAuthCalendarStorage.failure;
    if (failure != null) throw failure;
    final preferences = evidence.preferences;
    final originalOwner = preferences.get(OAuthCalendarStorage.scopeOwnerKey);
    var preparation = _guestOAuthPreparation;
    final request = ++_guestOAuthPreparationRequest;
    final epoch = OAuthCalendarStorage.epoch;
    final reset = OAuthCalendarStorage.resetRevision;
    final writeGeneration = AccountPreferenceWrites.generation;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool resourcesCurrent() =>
        isGuestWorkspaceLeaseCurrent(guest) &&
        identical(_verifiedGuestAuthStorage, evidence) &&
        preparation == _guestOAuthPreparation &&
        epoch == OAuthCalendarStorage.epoch &&
        reset == OAuthCalendarStorage.resetRevision &&
        writeGeneration == AccountPreferenceWrites.generation &&
        accountGeneration == AccountLocalDataCleaner.accountDataGeneration;
    bool current() =>
        _oauthCallerCurrent(isCurrent) &&
        resourcesCurrent() &&
        request == _guestOAuthPreparationRequest;
    var authorityChanged = false;
    OAuthScopedWorkspaceSnapshot? completedScope;
    OAuthScopeInitializationPending? initializationPending;
    try {
      await _queueAccountWriteback(() async {
        // Enroll here, outside any consumer write. Login may drain this operation
        // without waiting for a write that itself waits on the Auth tail.
        await AccountPreferenceWrites.runResult<void>((token) {
          bool admitted() =>
              current() &&
              token.isCurrent &&
              (initialization == null || initialization.resourcesCurrent());
          return OAuthCalendarStorage.run<void>(
            () async {
              final singleton = await SharedPreferences.getInstance();
              if (!admitted() || !identical(singleton, preferences)) {
                throw const AccountPreferenceWriteCanceled();
              }
              await preferences.reload();
              if (!admitted()) throw const AccountPreferenceWriteCanceled();
              if (preferences.get('auth_state') != evidence.authState ||
                  preferences.containsKey(
                    AccountLocalDataCleaner.accountDataOwnerKey,
                  ) ||
                  (!confirm &&
                      preferences.get(OAuthCalendarStorage.scopeOwnerKey) !=
                          originalOwner) ||
                  !(initialize || confirm
                      ? OAuthCalendarStorage.isEmptyGuestScopeLocked(
                          preferences,
                          allowExistingOwner: true,
                        )
                      : _canRestoreGuestOAuthInventoryLocked(preferences))) {
                throw const OAuthScopedWorkspaceUnavailable();
              }
              // Prior owned writes have now settled in this lane. If one became
              // indeterminate, run() refused admission before reaching this
              // revocation, leaving its original issuer evidence recoverable.
              if (!confirm) {
                OAuthCalendarStorage.ensureAccountAdmissionLocked(preferences);
              }
              if (initialization == null) {
                preparation = ++_guestOAuthPreparation;
              }
              _preparedGuestOAuthScope = null;
              authorityChanged = true;
              final OAuthScopedWorkspaceSnapshot? scope;
              try {
                if (confirm) {
                  scope =
                      await OAuthCalendarStorage.confirmGuestScopeInitializationLocked(
                        preferences,
                        expectedAuthState: evidence.authState,
                        isCurrent: admitted,
                        expectedInitialization: initialization?.coreTicket,
                        requireExpectedInitialization: initialization != null,
                      );
                } else if (initialize) {
                  scope =
                      await OAuthCalendarStorage.initializeEmptyGuestScopeLocked(
                        preferences,
                        expectedAuthState: evidence.authState,
                        isCurrent: admitted,
                      );
                } else {
                  scope = OAuthCalendarStorage.readScopedWorkspaceLocked(
                    preferences,
                    expectedAuthState: evidence.authState,
                  );
                }
              } on OAuthScopeInitializationPending catch (pending) {
                if (initialize &&
                    pending.ticket != null &&
                    resourcesCurrent() &&
                    OAuthCalendarStorage.isScopeInitializationRuntimeCurrent(
                      pending.ticket!,
                      preferences,
                    )) {
                  _oauthInitialization = _AuthOAuthInitializationBinding(
                    pending.ticket!,
                    preferences,
                    false,
                    resourcesCurrent,
                  );
                }
                if (!_oauthCallerCurrent(isCurrent) ||
                    (initialization != null && !current())) {
                  throw const AccountPreferenceWriteCanceled();
                }
                if (!returnPendingTicket && initialization == null) rethrow;
                initializationPending = pending;
                return;
              }
              if (!admitted()) throw const AccountPreferenceWriteCanceled();
              if (scope == null) throw const OAuthScopedWorkspaceUnavailable();
              OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
                scope,
                preferences,
              );
              if (initialization != null) {
                preparation = ++_guestOAuthPreparation;
              }
              _oauthInitialization = null;
              _preparedGuestOAuthScope = scope;
              completedScope = scope;
            },
            epoch: epoch,
            isCurrent: admitted,
          );
        }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
      });
    } finally {
      if (authorityChanged && !_isDisposed) notifyListeners();
    }
    if (initializationPending != null) {
      if (!current()) throw const AccountPreferenceWriteCanceled();
      onOutcomeReady?.call(current);
      throw initializationPending!;
    }
    if (!current() ||
        completedScope == null ||
        !identical(completedScope, _preparedGuestOAuthScope) ||
        !OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(
          completedScope!,
        )) {
      throw const AccountPreferenceWriteCanceled();
    }
    final originalScope = completedScope!;
    onOutcomeReady?.call(
      () =>
          current() &&
          identical(originalScope, _preparedGuestOAuthScope) &&
          OAuthCalendarStorage.isScopedWorkspaceRuntimeCurrent(originalScope),
    );
  }

  /// Available only after auth and owner writes report success and the owner
  /// readback matches the current stable identity.
  /// The widget publisher must also check its captured account generation.
  String? get validatedWidgetAccountIdentity {
    if (_isDisposed ||
        _accountTransitionInProgress ||
        _localAccountDataBlocked ||
        !_state.isLoggedIn) {
      return null;
    }
    final current = _stableAccountIdentity(_state);
    return current != null && current == _verifiedWidgetOwnerIdentity
        ? current
        : null;
  }

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

  AuthSessionLease captureSessionLease() {
    if (_isDisposed ||
        _accountTransitionInProgress ||
        _localAccountDataBlocked) {
      throw const ApiException('账号已发生变化，请在当前账号重试操作。');
    }
    if (!_state.isLoggedIn) {
      throw const ApiException('请先登录后再操作。');
    }
    return AuthSessionLease._(this, _client, _sessionEpoch, _state);
  }

  bool isSessionLeaseCurrent(AuthSessionLease lease) {
    return !_isDisposed &&
        !_accountTransitionInProgress &&
        !_localAccountDataBlocked &&
        _state.isLoggedIn &&
        identical(lease._owner, this) &&
        identical(lease._client, _client) &&
        lease._epoch == _sessionEpoch &&
        lease._token == _state.token &&
        // Legacy sessions may acquire their user ID during the first refresh.
        (lease._userId == null || lease._userId == _state.userId);
  }

  void requireCurrentSessionLease(AuthSessionLease lease) {
    if (!isSessionLeaseCurrent(lease)) {
      throw const ApiException('账号已发生变化，请在当前账号重试操作。');
    }
  }

  void _guardSessionLease(AuthSessionLease? lease) {
    if (lease != null) requireCurrentSessionLease(lease);
  }

  void _requireNotDisposed() {
    if (_isDisposed) {
      throw const ApiException('账号已发生变化，请在当前账号重试操作。');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _revokeGuestWorkspaceReadiness();
    _verifiedWidgetOwnerIdentity = null;
    _sessionEpoch++;
    _stateMutationSerial++;
    _refreshMeInFlight = null;
    _serverConfigRefreshInFlight = null;
    super.dispose();
  }

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
    if (_isDisposed || _accountTransitionInProgress) {
      throw const ApiException('账号正在切换，请稍后重试。');
    }
    // Readonly rehydration cannot revoke the only original issuer evidence
    // while a matching transaction still needs explicit reconciliation.
    final failure = OAuthCalendarStorage.failure;
    if (failure != null) throw failure;
    final claimSession = _sessionEpoch;
    final claimMutation = _stateMutationSerial;
    final claimClient = _client;
    final hydrationOAuthEpoch = OAuthCalendarStorage.epoch;
    final hydrationOAuthReset = OAuthCalendarStorage.resetRevision;
    final hydrationWriteGeneration = AccountPreferenceWrites.generation;
    final hydrationAccountGeneration =
        AccountLocalDataCleaner.accountDataGeneration;
    bool canClaim() =>
        !_isDisposed &&
        !_accountTransitionInProgress &&
        claimSession == _sessionEpoch &&
        claimMutation == _stateMutationSerial &&
        identical(claimClient, _client) &&
        hydrationOAuthReset == OAuthCalendarStorage.resetRevision &&
        hydrationWriteGeneration == AccountPreferenceWrites.generation &&
        hydrationAccountGeneration ==
            AccountLocalDataCleaner.accountDataGeneration;
    // Claim only after already-issued OAuth writes settle. Readonly hydration
    // must not turn their failed rollback into an unreachable old diagnostic.
    await OAuthCalendarStorage.run<void>(
      () async {
        if (!canClaim()) throw const AccountPreferenceWriteCanceled();
        // Remain closed if admitted hydration or its cleanup barrier fails.
        _localAccountDataBlocked = true;
        _verifiedWidgetOwnerIdentity = null;
        _accountTransitionInProgress = true;
        _sessionEpoch++;
        _markAccountMutation('storage_hydration');
      },
      epoch: hydrationOAuthEpoch,
      isCurrent: canClaim,
    );
    final hydrationEpoch = _sessionEpoch;
    final hydrationMutation = _stateMutationSerial;
    final hydrationClient = _client;
    bool hydrationCurrent() =>
        !_isDisposed &&
        hydrationEpoch == _sessionEpoch &&
        hydrationMutation == _stateMutationSerial &&
        identical(hydrationClient, _client);
    // Readonly hydration cannot adopt authority created after this request.
    // Ordinary retirement/recovery keeps its own transition authority below.
    bool readonlyHydrationCurrent() =>
        hydrationCurrent() &&
        hydrationOAuthEpoch == OAuthCalendarStorage.epoch &&
        hydrationOAuthReset == OAuthCalendarStorage.resetRevision &&
        hydrationWriteGeneration == AccountPreferenceWrites.generation &&
        hydrationAccountGeneration ==
            AccountLocalDataCleaner.accountDataGeneration;
    notifyListeners();
    try {
      await _queueAccountWriteback(
        () => _loadFromStorageNow(
          readonlyHydrationCurrent: readonlyHydrationCurrent,
          hydrationOAuthEpoch: hydrationOAuthEpoch,
        ),
      );
      if (!_isDisposed && !_localAccountDataBlocked) {
        _successfulAccountTransitionRevision++;
      }
    } finally {
      _accountTransitionInProgress = false;
      if (!_isDisposed) notifyListeners();
    }
    if (refreshServerConfig) {
      await refreshServerConfigFromServer();
    }
  }

  Future<void> _loadFromStorageNow({
    required bool Function() readonlyHydrationCurrent,
    required int hydrationOAuthEpoch,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;
    await prefs.reload();
    _requireNotDisposed();
    final originalAuth = prefs.get('auth_state');
    final verifiedGuest = _decodeVerifiedGuestState(originalAuth);
    final hasOAuth = prefs.getKeys().any(OAuthCalendarStorage.isOAuthScopeKey);
    AuthState? verifiedAccount;
    if (originalAuth is String) {
      try {
        final value = jsonDecode(originalAuth);
        if (value is Map<String, dynamic> &&
            value['token'] is String &&
            (value['token'] as String).isNotEmpty) {
          final decoded = AuthState.fromJson(value);
          if (decoded.isLoggedIn) verifiedAccount = decoded;
        }
      } catch (_) {}
    }
    final accountOwner = verifiedAccount == null
        ? null
        : _stableAccountIdentity(verifiedAccount);
    // A same-account cold restore classifies private data before any owner
    // write or normalization. Invalid owned bytes remain available for recovery.
    if (hasOAuth &&
        verifiedAccount != null &&
        accountOwner != null &&
        prefs.get(AccountLocalDataCleaner.accountDataOwnerKey) ==
            accountOwner &&
        !OAuthCalendarStorage.isAccountRetiring(prefs)) {
      final loadedAccount = verifiedAccount;
      final inventory = {
        for (final key in prefs.getKeys().where(
          OAuthCalendarStorage.isOAuthScopeKey,
        ))
          key: AccountPreferenceTransaction.freezeValue(prefs.get(key)),
      };
      try {
        await OAuthCalendarStorage.run<void>(
          () async {
            await prefs.reload();
            if (!readonlyHydrationCurrent() ||
                prefs.get('auth_state') != originalAuth ||
                !_canRestoreAccountOAuthInventoryLocked(prefs, accountOwner) ||
                inventory.length !=
                    prefs
                        .getKeys()
                        .where(OAuthCalendarStorage.isOAuthScopeKey)
                        .length ||
                !inventory.entries.every(
                  (e) =>
                      prefs.containsKey(e.key) &&
                      AccountPreferenceTransaction.valuesEqual(
                        prefs.get(e.key),
                        e.value,
                      ),
                )) {
              throw const OAuthScopedWorkspaceUnavailable();
            }
            final scope = OAuthCalendarStorage.readScopedWorkspaceLocked(
              prefs,
              expectedAuthState: originalAuth,
              expectedAccountOwner: accountOwner,
            );
            if (!readonlyHydrationCurrent()) {
              throw const OAuthScopedWorkspaceUnavailable();
            }
            if (scope != null) {
              OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
                scope,
                prefs,
              );
            }
            _baseUrl = AppConfig.bakedServerUrl;
            _state = loadedAccount;
            _client = ApiClient(baseUrl: _baseUrl, token: loadedAccount.token);
            _verifiedAccountAuthStorage = _VerifiedAccountAuthStorage(
              prefs,
              originalAuth,
              accountOwner,
            );
            _preparedAccountOAuthScope = scope;
            _verifiedWidgetOwnerIdentity = accountOwner;
            _authStorageReady = true;
            _localAccountDataBlocked = false;
          },
          epoch: hydrationOAuthEpoch,
          isCurrent: readonlyHydrationCurrent,
        );
      } catch (_) {
        _blockLocalAccountData();
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
      }
      return;
    }
    // Narrow no-owner exception: strictly owned guest rows/cache (or an empty
    // container) hydrate without sanitation. Legacy unbound data stays blocked.
    if (verifiedGuest != null &&
        hasOAuth &&
        !prefs.containsKey('auth_base_url') &&
        !prefs.containsKey('auth_base_url_admin') &&
        _canRestoreGuestOAuthInventoryLocked(prefs)) {
      final originalInventory = {
        for (final key in prefs.getKeys().where(
          OAuthCalendarStorage.isOAuthScopeKey,
        ))
          key: AccountPreferenceTransaction.freezeValue(prefs.get(key)),
      };
      try {
        await OAuthCalendarStorage.run<void>(
          () async {
            await prefs.reload();
            if (!readonlyHydrationCurrent() ||
                prefs.get('auth_state') != originalAuth ||
                !_canRestoreGuestOAuthInventoryLocked(prefs) ||
                prefs
                        .getKeys()
                        .where(OAuthCalendarStorage.isOAuthScopeKey)
                        .length !=
                    originalInventory.length ||
                !originalInventory.entries.every(
                  (e) =>
                      prefs.containsKey(e.key) &&
                      AccountPreferenceTransaction.valuesEqual(
                        prefs.get(e.key),
                        e.value,
                      ),
                )) {
              throw const OAuthScopedWorkspaceUnavailable();
            }
            final scope = OAuthCalendarStorage.readScopedWorkspaceLocked(
              prefs,
              expectedAuthState: originalAuth,
            );
            if (!readonlyHydrationCurrent()) {
              throw const OAuthScopedWorkspaceUnavailable();
            }
            if (scope != null) {
              OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
                scope,
                prefs,
              );
            }
            // All readbacks and the original private hydration ticket settled.
            // Publish synchronously before replacing its captured client.
            _baseUrl = AppConfig.bakedServerUrl;
            _state = verifiedGuest;
            _client = ApiClient(baseUrl: _baseUrl);
            _verifiedGuestAuthStorage = _VerifiedGuestAuthStorage(
              prefs,
              originalAuth,
            );
            _preparedGuestOAuthScope = scope;
            _authStorageReady = true;
            _verifiedGuestOwnerAbsence = true;
            _localAccountDataBlocked = false;
          },
          epoch: hydrationOAuthEpoch,
          isCurrent: readonlyHydrationCurrent,
        );
      } catch (_) {
        _blockLocalAccountData();
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
      }
      return;
    }
    // Unowned OAuth data outside the strict read-only branch cannot acquire
    // authority through ordinary startup normalization. Explicit retirement
    // keeps the recovery path below and its own original authority.
    if (hasOAuth &&
        !prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) &&
        !OAuthCalendarStorage.isAccountRetiring(prefs)) {
      _blockLocalAccountData();
      throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
    }
    // 清理旧版本可能遗留的本地服务器覆盖；当前策略不允许 APP 内改地址。
    await prefs.remove('auth_base_url');
    _requireNotDisposed();
    await prefs.remove('auth_base_url_admin');
    _requireNotDisposed();

    _baseUrl = AppConfig.bakedServerUrl;

    final raw = prefs.getString('auth_state');
    var loadedState = const AuthState();
    if (raw != null && raw.isNotEmpty) {
      try {
        loadedState = AuthState.fromJson(json.decode(raw));
      } catch (_) {}
    }
    await _recoverOAuthRetirementBeforeOwnerMutation(prefs);
    // Never manufacture an account owner that makes unowned legacy OAuth
    // credentials look eligible for migration into the loaded account.
    if (!prefs.containsKey(OAuthCalendarStorage.retirementFenceKey) &&
        !prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) &&
        prefs.getKeys().any(OAuthCalendarStorage.isOAuthScopeKey)) {
      _blockLocalAccountData();
      throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
    }
    if (loadedState.isLoggedIn) {
      await _clearStoredAccountDataIfOwnerMismatched(prefs, loadedState);
    } else {
      await _clearResidualAccountDataIfSignedOut(prefs);
    }
    if (_isDisposed) return;
    _state = loadedState;
    _client = ApiClient(baseUrl: _baseUrl, token: _state.token);
    await _persistAccountDataOwner(prefs, _state, expectedAuthState: raw);
    _requireNotDisposed();
    _localAccountDataBlocked = false;
  }

  // Pure inventory validation. Identity parsing cannot supply Auth authority;
  // both callers still hold their original private ticket and storage CAS.
  bool _canRestoreGuestOAuthInventoryLocked(SharedPreferences preferences) {
    if (OAuthCalendarStorage.isEmptyGuestScopeLocked(
      preferences,
      allowExistingOwner: true,
    )) {
      return true;
    }
    if (preferences.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) ||
        OAuthCalendarStorage.isAccountRetiring(preferences)) {
      return false;
    }
    final scope = OAuthScopedOwnerRecord.parse(
      preferences.get(OAuthCalendarStorage.scopeOwnerKey),
    );
    if (scope == null || scope.scopeKind != 'guest') return false;
    try {
      OAuthCalendarInventory.validate(preferences, scope);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _canRestoreAccountOAuthInventoryLocked(
    SharedPreferences preferences,
    String owner,
  ) {
    if (OAuthCalendarStorage.isAccountRetiring(preferences) ||
        preferences.get(AccountLocalDataCleaner.accountDataOwnerKey) != owner) {
      return false;
    }
    final raw = preferences.get(OAuthCalendarStorage.scopeOwnerKey);
    if (!preferences.containsKey(OAuthCalendarStorage.scopeOwnerKey)) {
      return OAuthCalendarStorage.isEmptyAccountScopeLocked(
        preferences,
        expectedAccountOwner: owner,
      );
    }
    final scope = OAuthScopedOwnerRecord.parse(raw);
    if (scope == null ||
        scope.scopeKind != 'account' ||
        !scope.matchesAccountOwner(owner)) {
      return false;
    }
    try {
      OAuthCalendarInventory.validate(preferences, scope);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Explicit guest sanitation is separate from full-account logout cleanup.
  /// It cannot adopt an account found during its queued storage preparation.
  Future<void> prepareGuestOAuthWorkspace() async {
    _requireNotDisposed();
    if (_state.isLoggedIn || _accountTransitionInProgress) {
      throw const ApiException('账号正在切换，请稍后重试。');
    }
    _accountTransitionInProgress = true;
    _localAccountDataBlocked = true;
    _revokeGuestWorkspaceReadiness();
    _sessionEpoch++;
    _markAccountMutation('guest_oauth_preparation');
    notifyListeners();
    try {
      await _queueAccountWriteback(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        _requireNotDisposed();
        final raw = prefs.get('auth_state');
        if (prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) ||
            _storedAuthIsLoggedIn(raw)) {
          throw const AccountLocalDataCleanupBlockedException(
            '账号归属未能安全保存，请重试。',
          );
        }
        await _retireOAuthScope(
          prefs,
          OAuthScopeRetirementPurpose.explicitReconnect,
        );
        await prefs.reload();
        _requireNotDisposed();
        if (prefs.get('auth_state') != raw ||
            _state.isLoggedIn ||
            prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey)) {
          throw const AccountLocalDataCleanupBlockedException(
            '账号归属未能安全保存，请重试。',
          );
        }
        await _persistAccountDataOwner(prefs, _state, expectedAuthState: raw);
        _localAccountDataBlocked = false;
      });
    } catch (_) {
      _blockLocalAccountData();
      rethrow;
    } finally {
      _accountTransitionInProgress = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  bool _storedAuthIsLoggedIn(Object? raw) {
    if (raw == null) return false;
    if (raw is! String) {
      throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
    }
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) throw const FormatException();
      return AuthState.fromJson(value).isLoggedIn;
    } catch (_) {
      throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
    }
  }

  static AuthState? _decodeVerifiedGuestState(Object? raw) {
    if (raw == null) return const AuthState();
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final state = AuthState.fromJson(decoded);
      return state.isLoggedIn ? null : state;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recoverOAuthRetirementBeforeOwnerMutation(
    SharedPreferences prefs,
  ) async {
    final inspection = OAuthCalendarStorage.inspectRetirementLocked(prefs);
    if (inspection.fullPending) return;
    if (inspection.scopedPending) {
      if (!inspection.scopedRecoverable) {
        _blockLocalAccountData();
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
      }
      await _retireOAuthScope(
        prefs,
        OAuthScopeRetirementPurpose.resumeKnownScope,
      );
      await prefs.reload();
    } else if (inspection.runtimePending) {
      _blockLocalAccountData();
      throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
    }
  }

  Future<void> _retireOAuthScope(
    SharedPreferences prefs,
    OAuthScopeRetirementPurpose purpose,
  ) async {
    final epoch = _sessionEpoch;
    final generation = _stateMutationSerial;
    bool current() =>
        !_isDisposed &&
        _accountTransitionInProgress &&
        _sessionEpoch == epoch &&
        _stateMutationSerial == generation;
    String? owner(String key) {
      if (!prefs.containsKey(key)) return null;
      final value = prefs.get(key);
      if (value is! String) {
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
      }
      return value;
    }

    try {
      if (!current()) throw const OAuthAccountRetirementPending();
      final request = OAuthScopeRetirementRequest(
        preferences: prefs,
        expectedAccountOwner: owner(
          AccountLocalDataCleaner.accountDataOwnerKey,
        ),
        expectedScopedOwner: owner(OAuthCalendarStorage.scopeOwnerKey),
        purpose: purpose,
        isCurrent: current,
      );
      await AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
        request,
        () async {},
      );
      if (!current()) throw const OAuthAccountRetirementPending();
    } catch (_) {
      _blockLocalAccountData();
      throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
    }
  }

  Future<void> refreshServerConfigFromServer({bool force = false}) {
    if (_isDisposed) return Future<void>.value();
    final inFlight = _serverConfigRefreshInFlight;
    if (inFlight != null) return inFlight;
    final lastRefreshAt = _lastServerConfigRefreshAt;
    if (!force &&
        _serverConfig.isNotEmpty &&
        lastRefreshAt != null &&
        DateTime.now().difference(lastRefreshAt) < _serverConfigRefreshTtl) {
      return Future.value();
    }
    final future = _refreshServerConfigFromServerNow();
    _serverConfigRefreshInFlight = future;
    return future.whenComplete(() {
      if (_serverConfigRefreshInFlight == future) {
        _serverConfigRefreshInFlight = null;
      }
    });
  }

  Future<void> _refreshServerConfigFromServerNow() async {
    if (_baseUrl.isEmpty) {
      // 同域相对路径下也可以拉 /api/config
    }
    try {
      final cfg = await _client.get('/api/config');
      if (_isDisposed) return;
      _lastServerConfigRefreshAt = DateTime.now();
      if (jsonEncode(_serverConfig) == jsonEncode(cfg)) return;
      _serverConfig = cfg;
      onServerConfigChanged?.call(cfg);
      if (!_isDisposed) notifyListeners();
    } catch (_) {
      // offline or server down — 保留旧配置
    }
  }

  void _refreshServerConfigInBackground(String reason) {
    unawaited(
      refreshServerConfigFromServer().catchError((Object e, StackTrace st) {
        debugPrint(
          '[auth] server config refresh after $reason failed: $e\n$st',
        );
      }),
    );
  }

  Future<void> _queueAccountWriteback(Future<void> Function() task) {
    final result = _accountWritebackTail.then((_) => task());
    // A failed update must not prevent a later cleanup or retry from running.
    _accountWritebackTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  bool _isCurrentAccountWriteback(
    AuthState state,
    int generation, {
    bool allowTransition = false,
  }) {
    return !_isDisposed &&
        (allowTransition || !_accountTransitionInProgress) &&
        generation == _stateMutationSerial &&
        state.token == _state.token &&
        state.userId == _state.userId;
  }

  Future<bool> _persistState(
    AuthState state,
    int generation, {
    bool allowTransition = false,
    bool Function()? storageCurrent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    bool isCurrent() =>
        (storageCurrent?.call() ?? true) &&
        _isCurrentAccountWriteback(
          state,
          generation,
          allowTransition: allowTransition,
        );
    if (!isCurrent()) return false;
    _revokeGuestWorkspaceReadiness();
    _revokeVerifiedWidgetOwnerIdentity();
    final encoded = json.encode(state.toJson());
    try {
      await prefs.reload();
      if (!isCurrent()) return false;
      OAuthCalendarStorage.ensureAccountAdmissionLocked(prefs);
      if (!await prefs.setString('auth_state', encoded)) {
        throw const AccountLocalDataCleanupBlockedException('账号状态未能安全保存，请重试。');
      }
      await prefs.reload();
      if (!isCurrent()) return false;
      if (prefs.get('auth_state') != encoded) {
        throw const AccountLocalDataCleanupBlockedException('账号状态未能安全保存，请重试。');
      }
    } catch (_) {
      _blockLocalAccountData();
      rethrow;
    }
    if (!isCurrent()) return false;
    await _persistAccountDataOwner(
      prefs,
      state,
      expectedAuthState: encoded,
      storageCurrent: storageCurrent,
    );
    if (!isCurrent()) return false;
    _localAccountDataBlocked = false;
    return true;
  }

  Future<bool> _persistAndNotifyAccount(
    Map<String, dynamic> payload, {
    bool allowTransition = false,
  }) async {
    final state = _state;
    final generation = _stateMutationSerial;
    bool isCurrent() => _isCurrentAccountWriteback(
      state,
      generation,
      allowTransition: allowTransition,
    );
    if (!await _persistState(
      state,
      generation,
      allowTransition: allowTransition,
    )) {
      return false;
    }
    if (!isCurrent()) return false;
    await _notifyAccountPayloadChanged(payload);
    if (!isCurrent()) return false;
    await _notifyAccountProfileChanged(state);
    return isCurrent();
  }

  Future<void> _applyAuthenticatedResponse(
    Map<String, dynamic> payload, {
    required ApiClient requestClient,
    required int generation,
    required String reason,
  }) async {
    _guardAccountRequest(requestClient, generation);
    // Claim the transition before queuing. A cloud writeback must never queue
    // a refresh behind this transition while cleanup waits for that writeback.
    _accountTransitionInProgress = true;
    _verifiedWidgetOwnerIdentity = null;
    _sessionEpoch++;
    _markAccountMutation(reason);
    notifyListeners();
    try {
      await _queueAccountWriteback(() async {
        _requireNotDisposed();
        final previousState = _state;
        final nextState = _stateFromAuthResponse(
          payload,
          fallbackState: const AuthState(),
        );
        await _notifyAccountIdentityChanging(previousState, nextState);
        _requireNotDisposed();
        _state = nextState;
        _client = ApiClient(baseUrl: _baseUrl, token: nextState.token);
        if (await _persistAndNotifyAccount(payload, allowTransition: true)) {
          _successfulAccountTransitionRevision++;
        }
      });
    } finally {
      _accountTransitionInProgress = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> _applyProfileResponse(
    Map<String, dynamic> payload, {
    required ApiClient requestClient,
    required int generation,
    required String reason,
  }) {
    _guardAccountRequest(requestClient, generation);
    return _queueAccountWriteback(() async {
      _guardAccountRequest(requestClient, generation);
      await _applyOrdinaryProfileState(
        _stateFromAuthResponse(payload, keepToken: true),
        payload,
        reason: reason,
        isCurrent: () =>
            !_isDisposed &&
            !_accountTransitionInProgress &&
            identical(requestClient, _client) &&
            generation == _stateMutationSerial,
      );
    });
  }

  /// Wait for issued OAuth writes before changing same-account Auth preimages.
  /// Notifications remain outside the lane because they may enroll new writes.
  Future<void> _applyOrdinaryProfileState(
    AuthState next,
    Map<String, dynamic> payload, {
    required String reason,
    required bool Function() isCurrent,
  }) async {
    final epoch = OAuthCalendarStorage.epoch;
    final reset = OAuthCalendarStorage.resetRevision;
    final writes = AccountPreferenceWrites.generation;
    final accounts = AccountLocalDataCleaner.accountDataGeneration;
    bool resourcesCurrent() =>
        epoch == OAuthCalendarStorage.epoch &&
        reset == OAuthCalendarStorage.resetRevision &&
        writes == AccountPreferenceWrites.generation &&
        accounts == AccountLocalDataCleaner.accountDataGeneration;
    var persisted = false;
    await AccountPreferenceWrites.runResult<void>((token) {
      bool storageCurrent() => token.isCurrent && resourcesCurrent();
      return OAuthCalendarStorage.run<void>(
        () async {
          if (!isCurrent() || !storageCurrent()) {
            throw const AccountPreferenceWriteCanceled();
          }
          final originalScope = _preparedAccountOAuthScope;
          final evidence = _verifiedAccountAuthStorage;
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          if (!isCurrent() || !storageCurrent()) {
            throw const AccountPreferenceWriteCanceled();
          }
          if (originalScope != null) {
            OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
              originalScope,
              prefs,
            );
            OAuthCalendarInventory.validate(prefs, originalScope.record);
            if (evidence == null ||
                !identical(evidence.preferences, prefs) ||
                evidence.accountOwner != _stableAccountIdentity(next)) {
              throw const OAuthScopedWorkspaceUnavailable();
            }
          }
          _state = next;
          _markAccountMutation(reason);
          persisted = await _persistState(
            next,
            _stateMutationSerial,
            storageCurrent: storageCurrent,
          );
          if (!storageCurrent()) throw const AccountPreferenceWriteCanceled();
          if (persisted && originalScope != null) {
            final updated = _verifiedAccountAuthStorage;
            if (updated == null) throw const OAuthScopedWorkspaceUnavailable();
            final scope = OAuthCalendarStorage.readScopedWorkspaceLocked(
              prefs,
              expectedAuthState: updated.authState,
              expectedAccountOwner: updated.accountOwner,
            );
            if (scope == null ||
                scope.record.encode() != originalScope.record.encode()) {
              throw const OAuthScopedWorkspaceUnavailable();
            }
            OAuthCalendarInventory.validate(prefs, scope.record);
            _preparedAccountOAuthScope = scope;
          }
        },
        epoch: epoch,
        isCurrent: () => isCurrent() && storageCurrent(),
      );
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
    if (!resourcesCurrent()) throw const AccountPreferenceWriteCanceled();
    if (!persisted ||
        _isDisposed ||
        _accountTransitionInProgress ||
        !identical(_state, next)) {
      return;
    }
    await _notifyAccountPayloadChanged(payload);
    if (!resourcesCurrent() ||
        _isDisposed ||
        _accountTransitionInProgress ||
        !identical(_state, next)) {
      return;
    }
    await _notifyAccountProfileChanged(next);
    if (!_isDisposed &&
        resourcesCurrent() &&
        !_accountTransitionInProgress &&
        identical(_state, next)) {
      notifyListeners();
    }
  }

  void _markAccountMutation(String reason) {
    _revokeGuestWorkspaceReadiness();
    _stateMutationSerial++;
    _refreshMeInFlight = null;
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
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
    final res = await requestClient.post('/api/auth/register', {
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
    _guardAccountRequest(requestClient, generation);
    await _applyAuthenticatedResponse(
      res,
      requestClient: requestClient,
      generation: generation,
      reason: 'register',
    );
    _refreshServerConfigInBackground('register');
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
    AuthSessionLease? sessionLease,
  }) async {
    _guardSessionLease(sessionLease);
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
    _guardSessionLease(sessionLease);
    _throwIfEmailCodeNotDelivered(result);
    return result;
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
    final res = await requestClient.post('/api/auth/login', {
      'username': username,
      'account': username,
      if (_looksLikeEmail(username)) 'email': username,
      'password': password,
    });
    _guardAccountRequest(requestClient, generation);
    await _applyAuthenticatedResponse(
      res,
      requestClient: requestClient,
      generation: generation,
      reason: 'login',
    );
    _refreshServerConfigInBackground('login');
  }

  Future<void> emailLogin({required String email, required String code}) async {
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
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
    await _applyAuthenticatedResponse(
      res,
      requestClient: requestClient,
      generation: generation,
      reason: 'email_login',
    );
    _refreshServerConfigInBackground('email_login');
  }

  Future<void> logout() async {
    if (_isDisposed) return;
    if (_accountTransitionInProgress) return;
    if (!_state.isLoggedIn) {
      await _clearLocalSession();
      return;
    }

    // Finish the local account cleanup barrier before asking the server to
    // revoke this token. A blocked cleanup must leave the still-valid session
    // intact so the user can retry later.
    final tokenAtStart = _state.token;
    final clientAtStart = _client;
    final sessionEpochAtStart = _sessionEpoch;
    await _notifyBeforeAccountLogout();
    if (_isDisposed ||
        _accountTransitionInProgress ||
        _state.token != tokenAtStart ||
        !identical(clientAtStart, _client) ||
        _sessionEpoch != sessionEpochAtStart) {
      return;
    }
    _accountTransitionInProgress = true;
    _verifiedWidgetOwnerIdentity = null;
    _sessionEpoch++;
    _markAccountMutation('logout_cleanup');
    notifyListeners();
    try {
      await _accountWritebackTail;
      _requireNotDisposed();
      await _logoutAfterCleanup();
      _successfulAccountTransitionRevision++;
    } finally {
      _accountTransitionInProgress = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> _logoutAfterCleanup() async {
    _requireNotDisposed();
    final logoutClient = _client;
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      await _notifyAccountLoggedOut();
    } catch (e, st) {
      if (e is AccountLocalDataCleanupBlockedException) {
        debugPrint('[auth] account logout cleanup blocked: $e');
        Error.throwWithStackTrace(e, st);
      }
      cleanupError = e;
      cleanupStackTrace = st;
      await _clearAccountScopedPreferencesAfterLogoutCleanupFailure();
    }
    _requireNotDisposed();
    try {
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
        client: logoutClient,
      );
    } catch (_) {}

    await _resetLocalSession();
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  }

  Future<void> _clearLocalSession() async {
    if (_isDisposed || _accountTransitionInProgress) return;
    _accountTransitionInProgress = true;
    _verifiedWidgetOwnerIdentity = null;
    _sessionEpoch++;
    _markAccountMutation('session_cleanup');
    notifyListeners();
    try {
      await _accountWritebackTail;
      _requireNotDisposed();
      await _clearLocalSessionAfterCleanup();
      _successfulAccountTransitionRevision++;
    } finally {
      _accountTransitionInProgress = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> _clearLocalSessionAfterCleanup() async {
    _requireNotDisposed();
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      await _notifyAccountLoggedOut();
    } catch (e, st) {
      if (e is AccountLocalDataCleanupBlockedException) {
        debugPrint('[auth] account logout cleanup blocked: $e');
        Error.throwWithStackTrace(e, st);
      }
      cleanupError = e;
      cleanupStackTrace = st;
      await _clearAccountScopedPreferencesAfterLogoutCleanupFailure();
    }
    _requireNotDisposed();
    await _resetLocalSession();
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  }

  Future<void> _resetLocalSession() async {
    if (_isDisposed) return;
    SharedPreferences? clearedStore;
    try {
      final prefs = await SharedPreferences.getInstance();
      _requireNotDisposed();
      await prefs.reload();
      _requireNotDisposed();
      if (OAuthCalendarStorage.isAccountRetiring(prefs)) {
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全清除，请重试。');
      }
      if (!await prefs.remove('auth_state')) {
        throw const AccountLocalDataCleanupBlockedException('登录状态未能安全清除，请重试。');
      }
      _requireNotDisposed();
      if (!await prefs.remove(AccountLocalDataCleaner.accountDataOwnerKey)) {
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全清除，请重试。');
      }
      await prefs.reload();
      _requireNotDisposed();
      if (prefs.containsKey('auth_state') ||
          prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) ||
          OAuthCalendarStorage.isAccountRetiring(prefs)) {
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全清除，请重试。');
      }
      clearedStore = prefs;
    } catch (_) {
      _blockLocalAccountData();
      rethrow;
    }
    _verifiedWidgetOwnerIdentity = null;
    _state = const AuthState();
    _markAccountMutation('logout');
    _client = ApiClient(baseUrl: _baseUrl);
    _verifiedGuestAuthStorage = _VerifiedGuestAuthStorage(clearedStore, null);
    _authStorageReady = true;
    _verifiedGuestOwnerAbsence = true;
    _localAccountDataBlocked = false;
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _notifyBeforeAccountLogout() async {
    final callback = onBeforeAccountLogout;
    if (callback == null) return;
    try {
      await callback();
    } catch (e, st) {
      debugPrint('[auth] account logout preflight failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> _clearAccountScopedPreferencesAfterLogoutCleanupFailure() async {
    _requireNotDisposed();
    try {
      await AccountLocalDataCleaner.clearSharedPreferences();
    } catch (e, st) {
      debugPrint('[auth] fallback account prefs cleanup failed: $e\n$st');
    }
  }

  Future<void> _clearStoredAccountDataIfOwnerMismatched(
    SharedPreferences prefs,
    AuthState loadedState,
  ) async {
    if (OAuthCalendarStorage.isAccountRetiring(prefs)) {
      await _notifyAccountIdentityChanging(
        const AuthState(),
        loadedState,
        force: true,
      );
      return;
    }
    final storedOwner = prefs
        .getString(AccountLocalDataCleaner.accountDataOwnerKey)
        ?.trim();
    final currentOwner = _stableAccountIdentity(loadedState);
    if (storedOwner == null || storedOwner.isEmpty) {
      if (currentOwner == null) return;
      if (!_unownedStoredAccountDataLooksMismatched(prefs, loadedState)) return;
      debugPrint('[auth] clearing unowned local account data after mismatch');
      if (onAccountIdentityChanging == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
        return;
      }
      await _notifyAccountIdentityChanging(
        const AuthState(),
        loadedState,
        force: true,
      );
      return;
    }
    if (currentOwner == null) {
      debugPrint('[auth] clearing account data with unknown stored owner');
      if (onAccountIdentityChanging == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
        return;
      }
      await _notifyAccountIdentityChanging(const AuthState(), loadedState);
      return;
    }
    if (storedOwner == currentOwner ||
        _isUsernameOwnerRefinement(storedOwner, loadedState)) {
      return;
    }
    debugPrint(
      '[auth] stored account data owner mismatch: $storedOwner -> $currentOwner',
    );
    if (onAccountIdentityChanging == null) {
      await AccountLocalDataCleaner.clearSharedPreferences();
      return;
    }
    await _notifyAccountIdentityChanging(const AuthState(), loadedState);
  }

  Future<void> _clearResidualAccountDataIfSignedOut(
    SharedPreferences prefs,
  ) async {
    if (OAuthCalendarStorage.isAccountRetiring(prefs)) {
      await _notifyAccountLoggedOut();
      return;
    }
    final storedOwner = prefs
        .getString(AccountLocalDataCleaner.accountDataOwnerKey)
        ?.trim();
    // Unowned account-scoped keys are the guest workspace. Keep them across
    // restarts so a later login can adopt them as an intentional import.
    if (storedOwner == null || storedOwner.isEmpty) return;
    if (!_hasStoredAccountScopedData(prefs)) return;
    debugPrint('[auth] clearing residual account data while signed out');
    if (onAccountLoggedOut == null) {
      await AccountLocalDataCleaner.clearSharedPreferences();
      return;
    }
    try {
      await _notifyAccountLoggedOut();
    } catch (e, st) {
      if (e is AccountLocalDataCleanupBlockedException) {
        debugPrint('[auth] residual account cleanup blocked: $e');
        Error.throwWithStackTrace(e, st);
      }
      await _clearAccountScopedPreferencesAfterLogoutCleanupFailure();
      rethrow;
    }
  }

  bool _hasStoredAccountScopedData(SharedPreferences prefs) {
    final keys = prefs.getKeys();
    return keys.any(
      (key) =>
          AccountLocalDataCleaner.accountScopedKeys.contains(key) ||
          AccountLocalDataCleaner.accountScopedPrefixes.any(key.startsWith),
    );
  }

  bool _unownedStoredAccountDataLooksMismatched(
    SharedPreferences prefs,
    AuthState state,
  ) {
    return _storedProfileLooksDifferent(prefs, state) ||
        _storedRewardsLookDifferent(prefs, state);
  }

  bool _storedProfileLooksDifferent(SharedPreferences prefs, AuthState state) {
    final raw = prefs.getString('user_profile');
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final storedEmail = decoded['email']?.toString().trim().toLowerCase();
      final currentEmail = state.email?.trim().toLowerCase();
      if (storedEmail != null &&
          storedEmail.isNotEmpty &&
          currentEmail != null &&
          currentEmail.isNotEmpty &&
          storedEmail != currentEmail) {
        return true;
      }
      final storedName = decoded['username']?.toString().trim().toLowerCase();
      final currentNameSource = state.displayName?.trim().isNotEmpty == true
          ? state.displayName
          : state.username;
      final currentName = currentNameSource?.trim().toLowerCase();
      if (storedName != null &&
          storedName.isNotEmpty &&
          storedName != '用户' &&
          currentName != null &&
          currentName.isNotEmpty &&
          storedName != currentName) {
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _storedRewardsLookDifferent(SharedPreferences prefs, AuthState state) {
    final raw = prefs.getString('duoyi_virtual_rewards');
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final balance = _intFromJson(
        decoded['balance'] ?? decoded['coin_balance'],
      );
      final lifetime = _intFromJson(
        decoded['lifetime'] ?? decoded['lifetime_coins'],
      );
      if (balance != state.coinBalance &&
          (balance != 0 || state.coinBalance != 0)) {
        return true;
      }
      if (lifetime != state.lifetimeCoins &&
          (lifetime != 0 || state.lifetimeCoins != 0)) {
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> _persistAccountDataOwner(
    SharedPreferences prefs,
    AuthState state, {
    Object? expectedAuthState = _uncheckedAuthState,
    bool Function()? storageCurrent,
  }) async {
    if (!(storageCurrent?.call() ?? true)) {
      throw const AccountPreferenceWriteCanceled();
    }
    _revokeGuestWorkspaceReadiness();
    _revokeVerifiedWidgetOwnerIdentity();
    final owner = _stableAccountIdentity(state);
    try {
      await prefs.reload();
      _requireNotDisposed();
      void checkAuthState() {
        if (!(storageCurrent?.call() ?? true)) {
          throw const AccountPreferenceWriteCanceled();
        }
        if (!identical(expectedAuthState, _uncheckedAuthState) &&
            prefs.get('auth_state') != expectedAuthState) {
          throw const AccountLocalDataCleanupBlockedException(
            '账号归属未能安全保存，请重试。',
          );
        }
      }

      checkAuthState();
      if (OAuthCalendarStorage.isAccountRetiring(prefs)) {
        throw const AccountLocalDataCleanupBlockedException('账号归属未能安全保存，请重试。');
      }
      if (state.isLoggedIn && owner != null) {
        // This write must not turn an unowned legacy OAuth collection into
        // account-owned data. Guest adoption retires it before reaching here.
        if (!prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey) &&
            prefs.getKeys().any(OAuthCalendarStorage.isOAuthScopeKey)) {
          throw const AccountLocalDataCleanupBlockedException(
            '账号归属未能安全保存，请重试。',
          );
        }
        final saved = await prefs.setString(
          AccountLocalDataCleaner.accountDataOwnerKey,
          owner,
        );
        await prefs.reload();
        _requireNotDisposed();
        checkAuthState();
        if (!saved ||
            OAuthCalendarStorage.isAccountRetiring(prefs) ||
            prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey) !=
                owner) {
          throw const AccountLocalDataCleanupBlockedException(
            '账号归属未能安全保存，请重试。',
          );
        }
        _verifiedWidgetOwnerIdentity = owner;
        _verifiedAccountAuthStorage = _VerifiedAccountAuthStorage(
          prefs,
          AccountPreferenceTransaction.freezeValue(prefs.get('auth_state')),
          owner,
        );
      } else {
        final removed = await prefs.remove(
          AccountLocalDataCleaner.accountDataOwnerKey,
        );
        await prefs.reload();
        _requireNotDisposed();
        checkAuthState();
        if (!removed ||
            OAuthCalendarStorage.isAccountRetiring(prefs) ||
            prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey)) {
          throw const AccountLocalDataCleanupBlockedException(
            '账号归属未能安全清除，请重试。',
          );
        }
        _verifiedGuestOwnerAbsence = !state.isLoggedIn;
      }
      _authStorageReady = true;
      if (_verifiedGuestOwnerAbsence &&
          _decodeVerifiedGuestState(prefs.get('auth_state')) != null) {
        _verifiedGuestAuthStorage = _VerifiedGuestAuthStorage(
          prefs,
          AccountPreferenceTransaction.freezeValue(prefs.get('auth_state')),
        );
      }
    } catch (_) {
      _blockLocalAccountData();
      rethrow;
    }
  }

  void _revokeVerifiedWidgetOwnerIdentity() {
    if (_verifiedWidgetOwnerIdentity == null) return;
    _verifiedWidgetOwnerIdentity = null;
    if (!_isDisposed) onWidgetPublicationAuthorityRevoked?.call();
  }

  void _blockLocalAccountData() {
    final wasBlocked = _localAccountDataBlocked;
    _localAccountDataBlocked = true;
    _revokeGuestWorkspaceReadiness();
    _verifiedWidgetOwnerIdentity = null;
    if (!_isDisposed && !wasBlocked) notifyListeners();
  }

  void _revokeGuestWorkspaceReadiness() {
    _oauthInitialization = null;
    _authStorageReady = false;
    _verifiedGuestOwnerAbsence = false;
    _verifiedGuestAuthStorage = null;
    _preparedGuestOAuthScope = null;
    _guestOAuthPreparation++;
    _verifiedAccountAuthStorage = null;
    _preparedAccountOAuthScope = null;
    _accountOAuthPreparation++;
  }

  Future<void> refreshMe({String reason = 'manual', bool force = false}) {
    if (_isDisposed || !_state.isLoggedIn || _accountTransitionInProgress) {
      return Future<void>.value();
    }
    final inFlight = _refreshMeInFlight;
    if (inFlight != null) return inFlight;
    final now = DateTime.now();
    final lastRefreshAt = _lastRefreshMeAt;
    if (!force &&
        _lastRefreshMeToken == _state.token &&
        _lastRefreshMeMutationSerial == _stateMutationSerial &&
        lastRefreshAt != null &&
        now.difference(lastRefreshAt) < _refreshMeMinInterval) {
      debugPrint('[auth-sync] refreshMe skipped: throttled reason=$reason');
      return Future<void>.value();
    }
    final future = _refreshMeNow(reason: reason);
    _refreshMeInFlight = future;
    return future.whenComplete(() {
      if (_refreshMeInFlight == future) {
        _refreshMeInFlight = null;
      }
    });
  }

  Future<void> _refreshMeNow({required String reason}) async {
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
      _lastRefreshMeAt = DateTime.now();
      _lastRefreshMeToken = tokenAtStart;
      _lastRefreshMeMutationSerial = mutationSerialAtStart;
      // Cloud sync may await this refresh while a transition drains sync.
      // Do not enqueue behind that transition, even if the HTTP already ended.
      if (_isDisposed ||
          _accountTransitionInProgress ||
          _state.token != tokenAtStart ||
          _stateMutationSerial != mutationSerialAtStart) {
        return;
      }
      await _queueAccountWriteback(() async {
        if (_isDisposed) return;
        if (requestId != _refreshMeRequestSerial ||
            requestId < _lastAppliedRefreshMeRequestSerial) {
          debugPrint(
            '[auth-sync] refreshMe#$requestId skipped: older response',
          );
          return;
        }
        if (!_state.isLoggedIn ||
            _state.token != tokenAtStart ||
            _accountTransitionInProgress) {
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
          await _notifyAccountPayloadChanged(me);
          debugPrint('[auth-sync] refreshMe#$requestId skipped: unchanged');
          return;
        }
        await _applyOrdinaryProfileState(
          nextState,
          me,
          reason: 'refresh_me',
          isCurrent: () =>
              !_isDisposed &&
              !_accountTransitionInProgress &&
              _state.token == tokenAtStart &&
              _stateMutationSerial == mutationSerialAtStart &&
              requestId == _refreshMeRequestSerial,
        );
        if (identical(_state, nextState)) {
          _lastRefreshMeMutationSerial = _stateMutationSerial;
          debugPrint(
            '[auth-sync] refreshMe#$requestId applied '
            'coin=${_state.coinBalance} lifetime=${_state.lifetimeCoins}',
          );
        }
      });
    } on ApiException catch (e) {
      if (_isDisposed ||
          _accountTransitionInProgress ||
          !_state.isLoggedIn ||
          _state.token != tokenAtStart ||
          _stateMutationSerial != mutationSerialAtStart ||
          requestId != _refreshMeRequestSerial) {
        debugPrint('[auth-sync] refreshMe#$requestId skipped: stale error');
        return;
      }
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
    if (_isDisposed || !_state.isLoggedIn || _accountTransitionInProgress) {
      return;
    }
    final requestClient = _client;
    final generation = _stateMutationSerial;
    await _queueAccountWriteback(() async {
      if (_isDisposed ||
          _accountTransitionInProgress ||
          !identical(requestClient, _client) ||
          generation != _stateMutationSerial ||
          !_state.isLoggedIn) {
        return;
      }
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
        await _notifyAccountPayloadChanged(Map<String, dynamic>.from(data));
        debugPrint('[auth-sync] $reason skipped: unchanged');
        return;
      }
      await _applyOrdinaryProfileState(
        nextState,
        Map<String, dynamic>.from(data),
        reason: reason,
        isCurrent: () =>
            !_isDisposed &&
            !_accountTransitionInProgress &&
            identical(requestClient, _client) &&
            generation == _stateMutationSerial,
      );
    });
  }

  Future<Map<String, dynamic>> applyThemeShopItem({
    required String itemType,
    required String itemId,
    required String title,
  }) async {
    if (!_state.isLoggedIn) {
      throw const ApiException('请先登录后再使用主题商店');
    }
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
    final tokenAtStart = _state.token;
    final userIdAtStart = _state.userId;
    final res = await requestClient.post('/api/theme-shop/apply', {
      'item_type': itemType,
      'item_id': itemId,
      'title': title,
      'activate': true,
    });
    _guardAccountRequest(requestClient, generation);
    await applyServerAccountSnapshot(
      res,
      reason: 'theme_shop_apply',
      expectedToken: tokenAtStart,
      expectedUserId: userIdAtStart,
    );
    if (_accountTransitionInProgress ||
        !identical(requestClient, _client) ||
        _state.token != tokenAtStart ||
        _state.userId != userIdAtStart) {
      throw const ApiException('账号已发生变化，请在当前账号重试操作。');
    }
    return res;
  }

  Future<void> updateProfile({
    String? displayName,
    String? bio,
    AuthSessionLease? sessionLease,
  }) async {
    _guardSessionLease(sessionLease);
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
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
    await _applyProfileResponse(
      res,
      requestClient: requestClient,
      generation: generation,
      reason: 'update_profile',
    );
    _guardSessionLease(sessionLease);
  }

  Future<void> bindEmail({
    required String email,
    required String code,
    AuthSessionLease? sessionLease,
  }) async {
    _guardSessionLease(sessionLease);
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
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
    await _applyProfileResponse(
      res,
      requestClient: requestClient,
      generation: generation,
      reason: 'bind_email',
    );
    _guardSessionLease(sessionLease);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    AuthSessionLease? sessionLease,
  }) async {
    _guardSessionLease(sessionLease);
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
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
    _guardAccountRequest(requestClient, generation);
    _guardSessionLease(sessionLease);
    await _clearLocalSession();
  }

  Future<void> uploadAvatarBytes({
    required String filename,
    required Uint8List bytes,
    AuthSessionLease? sessionLease,
  }) async {
    _guardSessionLease(sessionLease);
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
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
    await _applyProfileResponse(
      res,
      requestClient: requestClient,
      generation: generation,
      reason: 'upload_avatar',
    );
    _guardSessionLease(sessionLease);
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
    AuthState? fallbackState,
  }) {
    final fallback = fallbackState ?? _state;
    final source = data['user'] ?? data['profile'] ?? data['data'];
    final payload = source is Map<String, dynamic>
        ? source
        : source is Map
        ? Map<String, dynamic>.from(source)
        : data;
    final rootToken = _stringField(
      data,
      'token',
      _stringField(data, 'access_token', fallback.token),
    );
    final rewardsPayload = _mapField(data, const [
      'virtual_rewards',
      'virtualRewards',
      'rewards',
    ]);
    final rootCoinBalance = _intField(
      data,
      'coin_balance',
      _intField(
        data,
        'coinBalance',
        rewardsPayload == null
            ? fallback.coinBalance
            : _intField(
                rewardsPayload,
                'balance',
                _intField(rewardsPayload, 'coin_balance', fallback.coinBalance),
              ),
      ),
    );
    final rootLifetimeCoins = _intField(
      data,
      'lifetime_coins',
      _intField(
        data,
        'lifetimeCoins',
        rewardsPayload == null
            ? fallback.lifetimeCoins
            : _intField(
                rewardsPayload,
                'lifetime',
                _intField(
                  rewardsPayload,
                  'lifetime_coins',
                  fallback.lifetimeCoins,
                ),
              ),
      ),
    );
    return AuthState(
      userId: _stringField(
        payload,
        'user_id',
        _stringField(payload, 'id', fallback.userId),
      ),
      username: _stringField(
        payload,
        'username',
        _stringField(payload, 'identifier', fallback.username),
      ),
      email: _stringField(payload, 'email', fallback.email),
      emailVerified: _boolField(
        payload,
        'email_verified',
        _boolField(payload, 'emailVerified', fallback.emailVerified),
      ),
      displayName: _stringField(
        payload,
        'display_name',
        _stringField(payload, 'displayName', fallback.displayName),
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
              _avatarField(payload, 'path', fallback.avatar),
            ),
          ),
        ),
      ),
      bio: _stringField(payload, 'bio', fallback.bio),
      coinBalance: _intField(
        payload,
        'coin_balance',
        _intField(payload, 'coinBalance', rootCoinBalance),
      ),
      lifetimeCoins: _intField(
        payload,
        'lifetime_coins',
        _intField(payload, 'lifetimeCoins', rootLifetimeCoins),
      ),
      token: keepToken
          ? fallback.token
          : _stringField(
              payload,
              'token',
              _stringField(payload, 'access_token', rootToken),
            ),
      isAdmin: _boolField(
        payload,
        'is_admin',
        _boolField(payload, 'isAdmin', fallback.isAdmin),
      ),
      adminPermissions: payload.containsKey('admin_permissions')
          ? _stringListFromJson(payload['admin_permissions'])
          : payload.containsKey('permissions')
          ? _stringListFromJson(payload['permissions'])
          : fallback.adminPermissions,
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
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
    ApiException? last404;
    for (final path in paths) {
      try {
        _guardAccountRequest(requestClient, generation);
        final result = await requestClient.requestWithoutRouteDiagnosis(
          'GET',
          path,
        );
        _guardAccountRequest(requestClient, generation);
        return result;
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
    ApiClient? client,
  }) async {
    final requestClient = client ?? _client;
    final generation = _stateMutationSerial;
    ApiException? last404;
    for (final path in paths) {
      for (final method in methods) {
        try {
          _requireNotDisposed();
          if (client == null) _guardAccountRequest(requestClient, generation);
          final result = switch (method) {
            'POST' => await requestClient.requestWithoutRouteDiagnosis(
              'POST',
              path,
              body,
            ),
            'PUT' => await requestClient.requestWithoutRouteDiagnosis(
              'PUT',
              path,
              body,
            ),
            'PATCH' => await requestClient.requestWithoutRouteDiagnosis(
              'PATCH',
              path,
              body,
            ),
            _ => await requestClient.requestWithoutRouteDiagnosis(
              method,
              path,
              body,
            ),
          };
          _requireNotDisposed();
          if (client == null) _guardAccountRequest(requestClient, generation);
          return result;
        } on ApiException catch (e) {
          if (!_isRouteMissing(e)) rethrow;
          last404 = e;
        }
      }
    }
    _requireNotDisposed();
    throw await requestClient.missingRoutesException(
      featureName: featureName,
      paths: paths,
      fallback: last404,
    );
  }

  void _guardAccountRequest(ApiClient requestClient, int generation) {
    if (_isDisposed ||
        _accountTransitionInProgress ||
        !identical(requestClient, _client) ||
        generation != _stateMutationSerial) {
      throw const ApiException('账号已发生变化，请在当前账号重试操作。');
    }
  }

  Future<Map<String, dynamic>> _uploadFirstAvailable(
    List<String> paths, {
    required String fieldName,
    List<String> fieldNameFallbacks = const [],
    required String filename,
    required Uint8List bytes,
    String featureName = '文件上传',
  }) async {
    final requestClient = _client;
    final generation = _stateMutationSerial;
    _guardAccountRequest(requestClient, generation);
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
            _guardAccountRequest(requestClient, generation);
            final result = await requestClient.uploadBytes(
              path,
              method: method,
              fieldName: uploadFieldName,
              filename: filename,
              bytes: bytes,
              diagnoseMissingRoute: false,
            );
            _guardAccountRequest(requestClient, generation);
            return result;
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
    _guardAccountRequest(requestClient, generation);
    throw await requestClient.missingRoutesException(
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

  Map<String, dynamic>? _mapField(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    for (final wrapperKey in const ['user', 'profile', 'data', 'payload']) {
      final wrapper = data[wrapperKey];
      if (wrapper is Map<String, dynamic>) {
        final nested = _mapField(wrapper, keys);
        if (nested != null) return nested;
      } else if (wrapper is Map) {
        final nested = _mapField(Map<String, dynamic>.from(wrapper), keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Future<void> _notifyAccountProfileChanged(AuthState state) async {
    if (_isDisposed || !state.isLoggedIn) return;
    final callback = onAccountProfileChanged;
    if (callback == null) return;
    try {
      await callback(state);
    } catch (e, st) {
      debugPrint('[auth] account profile sync failed: $e\n$st');
    }
  }

  Future<void> _notifyAccountPayloadChanged(
    Map<String, dynamic> payload,
  ) async {
    if (_isDisposed || !_state.isLoggedIn) return;
    final callback = onAccountPayloadChanged;
    if (callback == null) return;
    try {
      await callback(payload);
    } catch (e, st) {
      debugPrint('[auth] account payload sync failed: $e\n$st');
    }
  }

  Future<void> _notifyAccountIdentityChanging(
    AuthState previous,
    AuthState next, {
    bool force = false,
  }) async {
    _requireNotDisposed();
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _requireNotDisposed();
      await _recoverOAuthRetirementBeforeOwnerMutation(prefs);
      if (!previous.isLoggedIn &&
          next.isLoggedIn &&
          !prefs.containsKey(OAuthCalendarStorage.retirementFenceKey) &&
          !prefs.containsKey(AccountLocalDataCleaner.accountDataOwnerKey)) {
        await _retireOAuthScope(
          prefs,
          OAuthScopeRetirementPurpose.guestAdoption,
        );
      }
    }
    if (!force &&
        !await _shouldClearLocalAccountDataBeforeApplying(previous, next)) {
      return;
    }
    _requireNotDisposed();
    final callback = onAccountIdentityChanging;
    try {
      if (callback == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
      } else {
        await AccountLocalDataCleaner.runAccountRetirement(() async {
          await callback(previous, next);
          _requireNotDisposed();
          // Keep user writes suspended through the app and final cleanup passes.
          await AccountLocalDataCleaner.clearSharedPreferences();
        });
      }
    } catch (e, st) {
      debugPrint('[auth] account switch cleanup failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> _notifyAccountLoggedOut() async {
    _requireNotDisposed();
    final callback = onAccountLoggedOut;
    try {
      if (callback == null) {
        await AccountLocalDataCleaner.clearSharedPreferences();
      } else {
        await AccountLocalDataCleaner.runAccountRetirement(() async {
          await callback();
          _requireNotDisposed();
          await AccountLocalDataCleaner.clearSharedPreferences();
        });
      }
    } catch (e, st) {
      debugPrint('[auth] account logout cleanup failed: $e\n$st');
      rethrow;
    }
  }

  Future<bool> _shouldClearLocalAccountDataBeforeApplying(
    AuthState previous,
    AuthState next,
  ) async {
    if (!next.isLoggedIn) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (OAuthCalendarStorage.isAccountRetiring(prefs)) return true;
    final storedOwner = prefs
        .getString(AccountLocalDataCleaner.accountDataOwnerKey)
        ?.trim();
    final nextOwner = _stableAccountIdentity(next);
    if (storedOwner != null &&
        storedOwner.isNotEmpty &&
        storedOwner != nextOwner) {
      // Ownership metadata remains authoritative even if auth_state is
      // absent or corrupt. A different account must not inherit that data.
      return true;
    }
    if (!previous.isLoggedIn) {
      // With no account owner, local data belongs to the guest workspace and
      // is accepted as the initial guest import.
      return false;
    }
    if (previous.token != next.token) return true;
    final previousIdentity = _stableAccountIdentity(previous);
    final nextIdentity = _stableAccountIdentity(next);
    if (previousIdentity != null && nextIdentity != null) {
      return previousIdentity != nextIdentity;
    }
    return previous.token != next.token;
  }

  String? _stableAccountIdentity(AuthState state) {
    final userId = state.userId?.trim();
    if (userId != null && userId.isNotEmpty) return 'id:$userId';
    final username = state.username?.trim().toLowerCase();
    if (username != null && username.isNotEmpty) return 'username:$username';
    final email = state.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) return 'email:$email';
    return null;
  }

  /// Legacy sessions may gain their server ID after the username owner was
  /// saved. A crash between the auth and owner writes leaves this exact pair.
  bool _isUsernameOwnerRefinement(String storedOwner, AuthState state) {
    if (!state.isLoggedIn || state.userId?.trim().isNotEmpty != true) {
      return false;
    }
    final username = state.username?.trim().toLowerCase();
    return username != null &&
        username.isNotEmpty &&
        storedOwner == 'username:$username';
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
