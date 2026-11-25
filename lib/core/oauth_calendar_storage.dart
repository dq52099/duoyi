import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_preference_writes.dart';

/// One local OAuth writer per process. Network requests never hold this lane.
class OAuthCalendarStorage {
  OAuthCalendarStorage._();

  static Future<void>? _tail;
  static int _epoch = 0;
  static int _resetRevision = 0;
  static OAuthStorageIndeterminate? _failure;
  static final Map<String, int> _sources = {};
  static final Map<String, int> _requests = {};
  static const retirementFenceKey = 'duoyi_oauth_calendar_retirement_fence_v1';
  static const scopeRetirementFenceKey =
      'duoyi_oauth_calendar_scope_retirement_v1';
  static const scopeOwnerKey = 'duoyi_oauth_calendar_scope_owner_v1';
  static const accountsKey = 'duoyi_oauth_calendar_accounts_v1';
  static const eventsKeyPrefix = 'duoyi_oauth_calendar_events_';
  static const pendingAuthorizationKey =
      'duoyi_oauth_calendar_pending_authorization_v1';
  static const refreshJournalKey = 'duoyi_oauth_calendar_refresh_journal_v1';
  static const _accountOwnerKey = 'duoyi_account_data_owner_v1';
  static final Set<OAuthAccountRetirementAnnouncement> _announcements =
      Set.identity();
  static final Object _defaultStoreDomain = Object();
  static int _retirementSequence = 0;
  static final Map<SharedPreferences, OAuthRetirementSession> _retirements =
      Map.identity();
  static final Set<void Function(SharedPreferences)> _clearListeners = {};
  static final Set<void Function()> _stateListeners = {};
  static bool _stateNotificationPending = false;

  static void addStateListener(void Function() listener) =>
      _stateListeners.add(listener);
  static void removeStateListener(void Function() listener) =>
      _stateListeners.remove(listener);

  static void _notifyStateChanged() {
    if (_stateNotificationPending || _stateListeners.isEmpty) return;
    _stateNotificationPending = true;
    scheduleMicrotask(() {
      _stateNotificationPending = false;
      _deliverStateChanged();
    });
  }

  static void _deliverStateChanged() {
    for (final listener in List<void Function()>.of(_stateListeners)) {
      if (!_stateListeners.contains(listener)) continue;
      // Observers cannot interrupt storage settlement or grant authority.
      try {
        listener();
      } catch (_) {}
    }
  }

  static final Map<SharedPreferences, _GuestScopeInitialization>
  _guestInitializations = Map.identity();
  static const _accountsKey = accountsKey;

  /// Runtime classification for an already-issued initializer; never adoption.
  static bool isScopeInitializationRuntimeCurrent(
    OAuthScopeInitializationTicket ticket,
    SharedPreferences preferences,
  ) {
    final candidate = _guestInitializations[preferences];
    if (candidate == null ||
        !identical(candidate.ticket, ticket) ||
        candidate.epoch != _epoch ||
        candidate.reset != _resetRevision ||
        candidate.generation != AccountPreferenceWrites.generation) {
      return false;
    }
    try {
      _requireScopePreimages(
        preferences,
        expectedAuthState: candidate.authState,
        expectedAccountOwner: candidate.accountOwner,
      );
      final inventory = _guestEmptyInventory(preferences);
      return _isEmptyScopeLocked(
            preferences,
            allowExistingOwner: true,
            expectedAccountOwner: candidate.accountOwner,
          ) &&
          inventory.length == candidate.inventory.length &&
          candidate.inventory.entries.every(
            (entry) =>
                inventory.containsKey(entry.key) &&
                AccountPreferenceTransaction.valuesEqual(
                  inventory[entry.key],
                  entry.value,
                ),
          ) &&
          (!preferences.containsKey(scopeOwnerKey) ||
              preferences.get(scopeOwnerKey) == candidate.raw);
    } catch (_) {
      return false;
    }
  }

  /// Cleanup announces intent before its first await. Failure to obtain the
  /// store must not let a fresh action treat an uncompleted cleanup as settled.
  static OAuthAccountRetirementAnnouncement announceAccountRetirement({
    SharedPreferences? store,
  }) {
    final announcement = OAuthAccountRetirementAnnouncement._(
      store ?? _defaultStoreDomain,
      ++_retirementSequence,
      false,
    );
    _announcements.add(announcement);
    _notifyStateChanged();
    return announcement;
  }

  static OAuthAccountRetirementAnnouncement announceOAuthScopeRetirement({
    required SharedPreferences store,
  }) {
    final announcement = OAuthAccountRetirementAnnouncement._(
      store,
      ++_retirementSequence,
      true,
    );
    _announcements.add(announcement);
    _notifyStateChanged();
    return announcement;
  }

  static void failAccountRetirementAnnouncement(
    OAuthAccountRetirementAnnouncement announcement,
  ) {
    if (_announcements.contains(announcement)) announcement._failed = true;
  }

  static bool _hasRetirementAnnouncement(SharedPreferences preferences) =>
      _announcements.any(
        (ticket) =>
            ticket._boundStore == null ||
            identical(ticket._boundStore, preferences),
      );

  static bool isAccountRetiring(SharedPreferences preferences) =>
      _hasRetirementAnnouncement(preferences) ||
      _retirements.containsKey(preferences) ||
      preferences.containsKey(retirementFenceKey) ||
      preferences.containsKey(scopeRetirementFenceKey);

  /// Classification only: callers must reload first. This never grants writes
  /// or turns a malformed scoped intent into permission to clear all data.
  static OAuthRetirementInspection inspectRetirementLocked(
    SharedPreferences preferences,
  ) {
    final full = preferences.containsKey(retirementFenceKey);
    final scoped = preferences.containsKey(scopeRetirementFenceKey);
    final marker = _OAuthScopeMarker.parse(
      preferences.get(scopeRetirementFenceKey),
    );
    final runtime =
        _hasRetirementAnnouncement(preferences) ||
        _retirements.containsKey(preferences);
    return OAuthRetirementInspection._(
      fullPending: full,
      scopedPending: scoped,
      runtimePending: runtime,
      scopedRecoverable:
          scoped && !full && marker != null && marker.matches(preferences),
    );
  }

  static bool isOAuthScopeKey(String key) =>
      key.startsWith('duoyi_oauth_calendar_') &&
      key != retirementFenceKey &&
      key != scopeRetirementFenceKey;

  static void ensureAccountAdmissionLocked(SharedPreferences preferences) {
    if (isAccountRetiring(preferences)) {
      throw const OAuthAccountRetirementPending();
    }
    if (_guestInitializations.containsKey(preferences)) {
      throw const OAuthScopeInitializationPending();
    }
  }

  /// Only the absent or strictly empty legacy account container is empty.
  /// Presence of a pending authorization, cache or unknown sidecar rejects it.
  /// This classifies disk data; it does not issue Auth authority.
  static bool isEmptyGuestScopeLocked(
    SharedPreferences preferences, {
    bool allowExistingOwner = false,
  }) => _isEmptyScopeLocked(
    preferences,
    allowExistingOwner: allowExistingOwner,
    expectedAccountOwner: null,
  );

  static bool isEmptyAccountScopeLocked(
    SharedPreferences preferences, {
    required String expectedAccountOwner,
    bool allowExistingOwner = false,
  }) => _isEmptyScopeLocked(
    preferences,
    allowExistingOwner: allowExistingOwner,
    expectedAccountOwner: expectedAccountOwner,
  );

  static bool _isEmptyScopeLocked(
    SharedPreferences preferences, {
    required bool allowExistingOwner,
    required String? expectedAccountOwner,
  }) {
    if (isAccountRetiring(preferences) ||
        (expectedAccountOwner == null
            ? preferences.containsKey(_accountOwnerKey)
            : expectedAccountOwner.trim().isEmpty ||
                  preferences.get(_accountOwnerKey) != expectedAccountOwner)) {
      return false;
    }
    for (final key in preferences.getKeys().where(isOAuthScopeKey)) {
      if (key == scopeOwnerKey && allowExistingOwner) continue;
      if (key != _accountsKey) return false;
      final raw = preferences.get(key);
      if (raw is! String) return false;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List || decoded.isNotEmpty) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  static void _requireScopePreimages(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required String? expectedAccountOwner,
  }) {
    if (expectedAccountOwner != null && expectedAccountOwner.trim().isEmpty) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    if (isAccountRetiring(preferences)) {
      throw const OAuthAccountRetirementPending();
    }
    if (_failure != null) throw _failure!;
    if (!AccountPreferenceTransaction.valuesEqual(
          preferences.get('auth_state'),
          expectedAuthState,
        ) ||
        (expectedAccountOwner == null
            ? preferences.containsKey(_accountOwnerKey)
            : preferences.get(_accountOwnerKey) != expectedAccountOwner)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
  }

  /// Caller holds the lane and has authoritatively reloaded this exact store.
  /// A snapshot proves identity only, never ownership of legacy account rows.
  static OAuthScopedWorkspaceSnapshot? readScopedWorkspaceLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    String? expectedAccountOwner,
  }) {
    ensureAccountAdmissionLocked(preferences);
    _requireScopePreimages(
      preferences,
      expectedAuthState: expectedAuthState,
      expectedAccountOwner: expectedAccountOwner,
    );
    if (!preferences.containsKey(scopeOwnerKey)) return null;
    final raw = preferences.get(scopeOwnerKey);
    final record = OAuthScopedOwnerRecord.parse(raw);
    if (record == null || !record.matchesAccountOwner(expectedAccountOwner)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return OAuthScopedWorkspaceSnapshot._(
      preferences,
      record,
      raw as String,
      expectedAuthState,
      expectedAccountOwner,
      _epoch,
      _resetRevision,
      AccountPreferenceWrites.generation,
    );
  }

  static bool _isScopedWorkspaceIdentityCurrent(
    OAuthScopedWorkspaceSnapshot snapshot,
  ) =>
      snapshot._epoch == _epoch &&
      snapshot._resetRevision == _resetRevision &&
      snapshot._generation == AccountPreferenceWrites.generation &&
      !_guestInitializations.containsKey(snapshot._store) &&
      !isAccountRetiring(snapshot._store);

  static bool isScopedWorkspaceRuntimeCurrent(
    OAuthScopedWorkspaceSnapshot snapshot,
  ) => _isScopedWorkspaceIdentityCurrent(snapshot) && _failure == null;

  /// Only the original verified store can retain a candidate while its own
  /// diagnostic blocks adoption. This does not admit reads or ordinary writes.
  static bool hasMatchingScopedReconciliation(
    OAuthScopedWorkspaceSnapshot snapshot,
  ) {
    final diagnostic = _failure;
    return diagnostic != null &&
        identical(diagnostic._workspace, snapshot) &&
        _isScopedWorkspaceIdentityCurrent(snapshot) &&
        identical(diagnostic._store, snapshot._store) &&
        diagnostic._epoch == snapshot._epoch &&
        diagnostic._generation == snapshot._generation &&
        snapshot._store.get(scopeOwnerKey) == snapshot.rawRecord &&
        AccountPreferenceTransaction.valuesEqual(
          snapshot._store.get('auth_state'),
          snapshot._authState,
        ) &&
        AccountPreferenceTransaction.valuesEqual(
          snapshot._store.get(_accountOwnerKey),
          snapshot._accountOwner,
        );
  }

  static OAuthScopedReconciliationSnapshot captureScopedReconciliation(
    OAuthScopedWorkspaceSnapshot snapshot,
  ) {
    if (!hasMatchingScopedReconciliation(snapshot)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    return OAuthScopedReconciliationSnapshot._(snapshot, _failure!);
  }

  static bool isScopedReconciliationRuntimeCurrent(
    OAuthScopedReconciliationSnapshot recovery,
  ) =>
      identical(_failure, recovery._diagnostic) &&
      hasMatchingScopedReconciliation(recovery.workspace);

  /// The matching diagnostic is the only waived ordinary admission condition.
  /// Call after each reload; malformed/foreign preimages remain fail-closed.
  static void ensureScopedReconciliationCurrentLocked(
    OAuthScopedReconciliationSnapshot recovery,
    SharedPreferences preferences,
  ) {
    if (!identical(recovery.workspace._store, preferences) ||
        !isScopedReconciliationRuntimeCurrent(recovery)) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    ensureAccountAdmissionLocked(preferences);
  }

  static void ensureScopedWorkspaceCurrentLocked(
    OAuthScopedWorkspaceSnapshot snapshot,
    SharedPreferences preferences,
  ) {
    if (!identical(snapshot._store, preferences) ||
        !isScopedWorkspaceRuntimeCurrent(snapshot) ||
        preferences.get(scopeOwnerKey) != snapshot.rawRecord) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    ensureAccountAdmissionLocked(preferences);
    _requireScopePreimages(
      preferences,
      expectedAuthState: snapshot._authState,
      expectedAccountOwner: snapshot._accountOwner,
    );
  }

  /// Explicit empty initialization, separate from read-only restoration.
  /// A rejected ACK never compensates away an identity that may have persisted.
  static Future<OAuthScopedWorkspaceSnapshot> initializeEmptyGuestScopeLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required bool Function() isCurrent,
  }) => _initializeEmptyScopeLocked(
    preferences,
    expectedAuthState: expectedAuthState,
    expectedAccountOwner: null,
    isCurrent: isCurrent,
  );

  static Future<OAuthScopedWorkspaceSnapshot> initializeEmptyAccountScopeLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required String expectedAccountOwner,
    required bool Function() isCurrent,
  }) => _initializeEmptyScopeLocked(
    preferences,
    expectedAuthState: expectedAuthState,
    expectedAccountOwner: expectedAccountOwner,
    isCurrent: isCurrent,
  );

  static Future<OAuthScopedWorkspaceSnapshot> _initializeEmptyScopeLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required String? expectedAccountOwner,
    required bool Function() isCurrent,
  }) async {
    ensureAccountAdmissionLocked(preferences);
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
    _requireScopePreimages(
      preferences,
      expectedAuthState: expectedAuthState,
      expectedAccountOwner: expectedAccountOwner,
    );
    if (!_isEmptyScopeLocked(
      preferences,
      allowExistingOwner: true,
      expectedAccountOwner: expectedAccountOwner,
    )) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    if (preferences.containsKey(scopeOwnerKey)) {
      return readScopedWorkspaceLocked(
        preferences,
        expectedAuthState: expectedAuthState,
        expectedAccountOwner: expectedAccountOwner,
      )!;
    }
    final candidate = _GuestScopeInitialization(
      (expectedAccountOwner == null
              ? OAuthScopedOwnerRecord._newGuest()
              : OAuthScopedOwnerRecord._newAccount(expectedAccountOwner))
          .encode(),
      expectedAuthState,
      _epoch,
      _resetRevision,
      AccountPreferenceWrites.generation,
      _guestEmptyInventory(preferences),
      accountOwner: expectedAccountOwner,
    );
    _guestInitializations[preferences] = candidate;
    _notifyStateChanged();
    return _writeGuestCandidate(preferences, candidate, isCurrent);
  }

  static Map<String, Object?> _guestEmptyInventory(
    SharedPreferences preferences,
  ) => {
    for (final key in preferences.getKeys().where(isOAuthScopeKey))
      if (key != scopeOwnerKey)
        key: AccountPreferenceTransaction.freezeValue(preferences.get(key)),
  };

  /// Only explicit confirmation can settle this store's original candidate.
  /// It cannot substitute a different identity or clear an unrelated failure.
  static Future<OAuthScopedWorkspaceSnapshot>
  confirmGuestScopeInitializationLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required bool Function() isCurrent,
    OAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
  }) => _confirmScopeInitializationLocked(
    preferences,
    expectedAuthState: expectedAuthState,
    expectedAccountOwner: null,
    isCurrent: isCurrent,
    expectedInitialization: expectedInitialization,
    requireExpectedInitialization: requireExpectedInitialization,
  );

  static Future<OAuthScopedWorkspaceSnapshot>
  confirmAccountScopeInitializationLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required String expectedAccountOwner,
    required bool Function() isCurrent,
    OAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
  }) => _confirmScopeInitializationLocked(
    preferences,
    expectedAuthState: expectedAuthState,
    expectedAccountOwner: expectedAccountOwner,
    isCurrent: isCurrent,
    expectedInitialization: expectedInitialization,
    requireExpectedInitialization: requireExpectedInitialization,
  );

  static Future<OAuthScopedWorkspaceSnapshot> _confirmScopeInitializationLocked(
    SharedPreferences preferences, {
    required Object? expectedAuthState,
    required String? expectedAccountOwner,
    required bool Function() isCurrent,
    OAuthScopeInitializationTicket? expectedInitialization,
    bool requireExpectedInitialization = false,
  }) async {
    if (requireExpectedInitialization && expectedInitialization == null) {
      throw ArgumentError('The original initialization ticket is required');
    }
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
    final candidate = _guestInitializations[preferences];
    if (expectedInitialization != null &&
        (candidate == null ||
            !identical(candidate.ticket, expectedInitialization) ||
            !isScopeInitializationRuntimeCurrent(
              expectedInitialization,
              preferences,
            ))) {
      throw const OAuthScopedWorkspaceUnavailable();
    }
    if (candidate == null ||
        candidate.accountOwner != expectedAccountOwner ||
        !AccountPreferenceTransaction.valuesEqual(
          expectedAuthState,
          candidate.authState,
        )) {
      throw const OAuthScopeInitializationPending();
    }
    return _writeGuestCandidate(preferences, candidate, isCurrent);
  }

  static Future<OAuthScopedWorkspaceSnapshot> _writeGuestCandidate(
    SharedPreferences preferences,
    _GuestScopeInitialization candidate,
    bool Function() isCurrent,
  ) async {
    void check({bool requirePersisted = false}) {
      _requireScopePreimages(
        preferences,
        expectedAuthState: candidate.authState,
        expectedAccountOwner: candidate.accountOwner,
      );
      final inventory = _guestEmptyInventory(preferences);
      if (!isCurrent() ||
          !identical(_guestInitializations[preferences], candidate) ||
          candidate.epoch != _epoch ||
          candidate.reset != _resetRevision ||
          candidate.generation != AccountPreferenceWrites.generation ||
          !_isEmptyScopeLocked(
            preferences,
            allowExistingOwner: true,
            expectedAccountOwner: candidate.accountOwner,
          ) ||
          inventory.length != candidate.inventory.length ||
          !candidate.inventory.entries.every(
            (e) =>
                inventory.containsKey(e.key) &&
                AccountPreferenceTransaction.valuesEqual(
                  inventory[e.key],
                  e.value,
                ),
          ) ||
          (preferences.containsKey(scopeOwnerKey)
              ? preferences.get(scopeOwnerKey) != candidate.raw
              : requirePersisted)) {
        throw const OAuthScopeInitializationPending();
      }
    }

    try {
      check();
      await preferences.reload();
      check();
      final saved = await preferences.setString(scopeOwnerKey, candidate.raw);
      await preferences.reload();
      check(requirePersisted: true);
      if (!saved) throw const OAuthScopeInitializationPending();
      // Synchronous final compare and publication; no await after clearing latch.
      _guestInitializations.remove(preferences);
      _notifyStateChanged();
      return readScopedWorkspaceLocked(
        preferences,
        expectedAuthState: candidate.authState,
        expectedAccountOwner: candidate.accountOwner,
      )!;
    } catch (_) {
      // Keep candidate/latch and actual backing bytes. No rollback or retry.
      throw OAuthScopeInitializationPending(
        ticket:
            isScopeInitializationRuntimeCurrent(candidate.ticket, preferences)
            ? candidate.ticket
            : null,
      );
    }
  }

  static void registerAccountClearListener(
    void Function(SharedPreferences) listener,
  ) => _clearListeners.add(listener);

  /// Only a cleanup session can obtain this opaque authority. Arming never
  /// compensates the fence away on a rejected or unknown platform write.
  static Future<OAuthAccountRetirementSession> beginAccountRetirementLocked(
    SharedPreferences preferences, {
    OAuthAccountRetirementAnnouncement? announcement,
  }) async =>
      await _beginRetirementLocked(
            preferences,
            announcement: announcement ?? announceAccountRetirement(),
          )
          as OAuthAccountRetirementSession;

  static Future<OAuthScopeRetirementSession> beginOAuthScopeRetirementLocked(
    SharedPreferences preferences, {
    required OAuthAccountRetirementAnnouncement announcement,
    required OAuthScopeRetirementRequest request,
  }) async =>
      await _beginRetirementLocked(
            preferences,
            announcement: announcement,
            request: request,
          )
          as OAuthScopeRetirementSession;

  static Future<OAuthRetirementSession> _beginRetirementLocked(
    SharedPreferences preferences, {
    required OAuthAccountRetirementAnnouncement announcement,
    OAuthScopeRetirementRequest? request,
  }) async {
    final ticket = announcement;
    if (!_announcements.contains(ticket) ||
        ticket._failed ||
        ticket._oauthOnly != (request != null)) {
      throw const OAuthAccountRetirementPending();
    }
    final singletonStore = await SharedPreferences.getInstance();
    final expectedStore =
        ticket._boundStore ??
        (identical(ticket._domain, _defaultStoreDomain)
            ? singletonStore
            : ticket._domain);
    if (!identical(expectedStore, preferences)) {
      throw const OAuthAccountRetirementPending();
    }
    if (!_announcements.contains(ticket) ||
        ticket._failed ||
        ticket._oauthOnly != (request != null)) {
      throw const OAuthAccountRetirementPending();
    }
    // Once acquisition proves the store, a failed arm remains scoped to that
    // exact identity even if the singleton later changes. Unbound intent still
    // blocks globally until its own acquisition has succeeded.
    ticket._boundStore ??= preferences;
    await preferences.reload();
    final previousSession = _retirements[preferences];
    if (!_announcements.contains(ticket) ||
        ticket._failed ||
        (previousSession != null && !previousSession._failed)) {
      throw const OAuthAccountRetirementPending();
    }
    Object canonicalDomain(OAuthAccountRetirementAnnouncement candidate) {
      final domain = candidate._boundStore ?? candidate._domain;
      return identical(domain, singletonStore) ? _defaultStoreDomain : domain;
    }

    if (request != null) {
      request._ensureCurrent(preferences);
      if (previousSession is OAuthAccountRetirementSession ||
          _announcements.any(
            (other) =>
                !other._oauthOnly &&
                identical(canonicalDomain(other), canonicalDomain(ticket)),
          )) {
        throw const OAuthAccountRetirementPending();
      }
      final inspection = inspectRetirementLocked(preferences);
      if (inspection.fullPending ||
          (inspection.scopedPending && !inspection.scopedRecoverable)) {
        throw const OAuthAccountRetirementPending();
      }
      final marker = _OAuthScopeMarker.parse(
        preferences.get(scopeRetirementFenceKey),
      );
      if (marker != null && !marker.matchesRequest(request)) {
        throw const OAuthAccountRetirementPending();
      }
    }
    ticket._recovery.addAll(
      _announcements.where(
        (previous) =>
            previous._failed &&
            (!ticket._oauthOnly || previous._oauthOnly) &&
            previous._sequence < ticket._sequence &&
            identical(canonicalDomain(previous), canonicalDomain(ticket)),
      ),
    );
    final random = Random.secure();
    final value = jsonEncode({
      'schema': 1,
      'retirementId': base64UrlEncode(
        List<int>.generate(24, (_) => random.nextInt(256)),
      ),
      'state': 'retiring',
      if (request != null) ...{
        'scope': 'oauthOnly',
        'purpose': request.purpose.name,
        'globalOwner': _ownerDigest(request.expectedAccountOwner),
        'scopeOwner': request._scopeOwnerBinding,
      },
    });
    final OAuthRetirementSession session = request == null
        ? OAuthAccountRetirementSession._(
            preferences,
            value,
            ticket,
            AccountPreferenceTransaction.freezeValue(
              preferences.get(scopeRetirementFenceKey),
            ),
          )
        : OAuthScopeRetirementSession._(preferences, value, ticket, request);
    _retirements[preferences] = session;
    _announcements.remove(ticket);
    try {
      final saved = await preferences.setString(session._fenceKey, value);
      await preferences.reload();
      if (!saved || preferences.get(session._fenceKey) != value) {
        throw const OAuthAccountRetirementPending();
      }
      if (request != null) {
        request._ensureCurrent(preferences, checkOriginalFence: false);
      }
      ensureRetirementCurrentLocked(session);
      return session;
    } catch (_) {
      session._failed = true;
      ticket._failed = true;
      _announcements.add(ticket);
      rethrow;
    }
  }

  static void ensureRetirementCurrentLocked(OAuthRetirementSession session) {
    if (session._failed ||
        !identical(_retirements[session.preferences], session) ||
        session.preferences.get(session._fenceKey) != session._value) {
      throw const OAuthAccountRetirementPending();
    }
    if (session is OAuthScopeRetirementSession) {
      if (session.preferences.containsKey(retirementFenceKey) ||
          !_OAuthScopeMarker.parse(
            session._value,
          )!.matches(session.preferences)) {
        throw const OAuthAccountRetirementPending();
      }
    } else if (session is OAuthAccountRetirementSession &&
        !AccountPreferenceTransaction.valuesEqual(
          session.preferences.get(scopeRetirementFenceKey),
          session._scopedFenceRemoved ? null : session._scopedFencePreimage,
        )) {
      throw const OAuthAccountRetirementPending();
    }
  }

  static void failAccountRetirementLocked(OAuthRetirementSession session) {
    session._failed = true;
  }

  /// The outer session owns finalization after all cleanup passes have settled.
  static Future<void> finishAccountRetirementLocked(
    OAuthAccountRetirementSession session, {
    required bool Function(SharedPreferences) hasRemainingOwnedData,
    void Function()? onConfirmed,
  }) async {
    try {
      await _finishAccountRetirementLocked(
        session,
        hasRemainingOwnedData: hasRemainingOwnedData,
        onConfirmed: onConfirmed,
      );
    } catch (_) {
      session._failed = true;
      rethrow;
    }
  }

  static Future<void> _finishAccountRetirementLocked(
    OAuthAccountRetirementSession session, {
    required bool Function(SharedPreferences) hasRemainingOwnedData,
    void Function()? onConfirmed,
  }) async {
    final preferences = session.preferences;
    await preferences.reload();
    ensureRetirementCurrentLocked(session);
    if (hasRemainingOwnedData(preferences)) {
      throw const OAuthAccountRetirementPending();
    }
    // Only a checked full-account session can take over a previous scoped
    // fence. It stays present throughout the ordinary deletion pass.
    if (preferences.containsKey(scopeRetirementFenceKey)) {
      final removed = await preferences.remove(scopeRetirementFenceKey);
      await preferences.reload();
      if (!removed || preferences.containsKey(scopeRetirementFenceKey)) {
        session._failed = true;
        throw const OAuthAccountRetirementPending();
      }
      session._scopedFenceRemoved = true;
      ensureRetirementCurrentLocked(session);
      if (hasRemainingOwnedData(preferences)) {
        throw const OAuthAccountRetirementPending();
      }
    }
    if (preferences.containsKey(scopeRetirementFenceKey)) {
      throw const OAuthAccountRetirementPending();
    }
    final removed = await preferences.remove(retirementFenceKey);
    await preferences.reload();
    if (!removed ||
        preferences.containsKey(retirementFenceKey) ||
        preferences.containsKey(scopeRetirementFenceKey) ||
        hasRemainingOwnedData(preferences) ||
        !identical(_retirements[preferences], session)) {
      throw const OAuthAccountRetirementPending();
    }
    onConfirmed?.call();
    _completeRetirement(session);
  }

  /// The proof is fixed to OAuth private keys; callers cannot supply an empty
  /// predicate and accidentally finalize while old credentials remain.
  static Future<void> finishOAuthScopeRetirementLocked(
    OAuthScopeRetirementSession session,
  ) async {
    final preferences = session.preferences;
    try {
      await preferences.reload();
      ensureRetirementCurrentLocked(session);
      if (preferences.getKeys().any(isOAuthScopeKey)) {
        throw const OAuthAccountRetirementPending();
      }
      final removed = await preferences.remove(scopeRetirementFenceKey);
      await preferences.reload();
      if (!removed ||
          preferences.containsKey(scopeRetirementFenceKey) ||
          preferences.containsKey(retirementFenceKey) ||
          preferences.getKeys().any(isOAuthScopeKey) ||
          _readOwner(preferences, _accountOwnerKey) !=
              session.request.expectedAccountOwner ||
          !identical(_retirements[preferences], session)) {
        throw const OAuthAccountRetirementPending();
      }
      confirmOAuthScopeClearLocked(preferences);
      _completeRetirement(session);
    } catch (_) {
      session._failed = true;
      rethrow;
    }
  }

  static void _completeRetirement(OAuthRetirementSession session) {
    _retirements.remove(session.preferences);
    // Only an explicit later cleanup can settle previously failed unbound
    // intent. Never consume another queued request's active announcement.
    _announcements.removeWhere(
      (ticket) =>
          ticket._failed && session._announcement._recovery.contains(ticket),
    );
    // Successful retirement includes observation of its final public state.
    // A queued event can still run, but observers already own this baseline.
    _deliverStateChanged();
  }

  static String? _readOwner(SharedPreferences preferences, String key) {
    if (!preferences.containsKey(key)) return null;
    final value = preferences.get(key);
    if (value is! String) throw const OAuthAccountRetirementPending();
    return value;
  }

  static String? _ownerDigest(String? value) =>
      value == null ? null : sha256.convert(utf8.encode(value)).toString();

  /// Retire only this store's provider projections and uncertain transaction.
  /// Global source/request histories belonging to other stores are retained.
  static void confirmOAuthScopeClearLocked(SharedPreferences preferences) {
    _resetRevision++;
    _guestInitializations.remove(preferences);
    if (identical(_failure?._store, preferences)) _failure = null;
    _notifyStateChanged();
    for (final listener in _clearListeners) {
      listener(preferences);
    }
  }

  static int get epoch => _epoch;
  static int get resetRevision => _resetRevision;
  static OAuthStorageIndeterminate? get failure => _failure;
  static int sourceRevision(String id) => _sources[id] ?? 0;
  static void sourceChanged(String id) => _sources[id] = sourceRevision(id) + 1;
  static void metadataChanged(String id) => beginRequest(id);
  static int beginRequest(String id) =>
      _requests[id] = (_requests[id] ?? 0) + 1;
  static bool ownsRequest(String id, int request) => _requests[id] == request;

  static void invalidateReset() {
    _resetRevision++;
    _notifyStateChanged();
  }

  /// Account cleanup calls this only after all enrolled writes have drained and
  /// an authoritative reload has confirmed removal of every account key.
  static void confirmAccountClearLocked(SharedPreferences preferences) {
    _epoch++;
    _resetRevision++;
    _guestInitializations.remove(preferences);
    if (identical(_failure?._store, preferences)) _failure = null;
    _sources.clear();
    _requests.clear();
    _notifyStateChanged();
    for (final listener in _clearListeners) {
      listener(preferences);
    }
  }

  static Future<T> run<T>(
    Future<T> Function() operation, {
    required int epoch,
    bool recovering = false,
    bool Function()? isCurrent,
  }) {
    final previous = _tail;
    final result = Future<T>.sync(() async {
      if (previous != null) await previous;
      if (epoch != _epoch) throw const AccountPreferenceWriteCanceled();
      if (isCurrent != null && !isCurrent()) {
        throw const AccountPreferenceWriteCanceled();
      }
      if (!recovering && _failure != null) throw _failure!;
      return operation();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    tail.then<void>((_) {
      if (identical(_tail, tail)) _tail = null;
    });
    return result;
  }

  static Future<void> commitLocked(
    SharedPreferences preferences,
    Map<String, Object?> changes,
    bool Function() isCurrent, {
    void Function()? validateReadback,
    OAuthScopedWorkspaceSnapshot? scopedWorkspace,
  }) async {
    ensureAccountAdmissionLocked(preferences);
    if (_failure != null) throw _failure!;
    if (scopedWorkspace != null) {
      ensureScopedWorkspaceCurrentLocked(scopedWorkspace, preferences);
    }
    final transaction = AccountPreferenceTransaction(preferences, isCurrent);
    final admittedGeneration = AccountPreferenceWrites.generation;
    try {
      for (final entry in changes.entries) {
        switch (entry.value) {
          case String value:
            await transaction.setString(entry.key, value);
          case null:
            if (preferences.containsKey(entry.key)) {
              await transaction.remove(entry.key);
            }
          default:
            throw StateError('Unsupported OAuth preference value');
        }
      }
      await transaction.reload();
      if (!changes.entries.every(
        (entry) => AccountPreferenceTransaction.valuesEqual(
          preferences.get(entry.key),
          entry.value,
        ),
      )) {
        throw StateError('OAuth preference readback failed');
      }
      validateReadback?.call();
      transaction.commit();
    } catch (error) {
      if (transaction.previousValues.isNotEmpty) {
        final diagnostic = OAuthStorageIndeterminate(
          transaction.previousValues,
          transaction.issuedValues,
          _epoch,
          admittedGeneration,
          store: preferences,
          workspace: scopedWorkspace,
        );
        final restorationError = await transaction.rollbackChecked();
        if (restorationError != null) {
          _failure = diagnostic;
          _notifyStateChanged();
          throw diagnostic;
        }
      }
      rethrow;
    }
  }

  static Future<void> reconcileLocked(
    SharedPreferences preferences,
    bool Function() isCurrent, {
    void Function()? validateReadback,
  }) async {
    ensureAccountAdmissionLocked(preferences);
    final diagnostic = _failure;
    if (diagnostic == null) return;
    if (!identical(diagnostic._store, preferences)) throw diagnostic;
    void ensureCurrent() {
      if (!isCurrent() ||
          !identical(_failure, diagnostic) ||
          diagnostic._epoch != _epoch ||
          diagnostic._generation != AccountPreferenceWrites.generation) {
        throw const AccountPreferenceWriteCanceled();
      }
    }

    ensureCurrent();
    await preferences.reload();
    ensureCurrent();
    for (final entry in diagnostic._previous.entries) {
      final actual = preferences.get(entry.key);
      if (!AccountPreferenceTransaction.valuesEqual(actual, entry.value) &&
          !AccountPreferenceTransaction.valuesEqual(
            actual,
            diagnostic._issued[entry.key],
          )) {
        throw diagnostic;
      }
    }
    for (final entry in diagnostic._previous.entries.toList().reversed) {
      ensureCurrent();
      try {
        await AccountPreferenceTransaction.writeValue(
          preferences,
          entry.key,
          entry.value,
        );
      } catch (_) {
        // Confirm backing storage below; a rejected ACK can still persist.
      }
    }
    await preferences.reload();
    ensureCurrent();
    if (!diagnostic._previous.entries.every(
      (entry) => AccountPreferenceTransaction.valuesEqual(
        preferences.get(entry.key),
        entry.value,
      ),
    )) {
      throw diagnostic;
    }
    validateReadback?.call();
    ensureCurrent();
    if (identical(_failure, diagnostic)) {
      _failure = null;
      _notifyStateChanged();
    }
  }
}

/// Credential-free data. Parsing succeeds only for the canonical four-field
/// encoding, so duplicate keys, extra fields and alternate encodings reject.
final class OAuthScopedOwnerRecord {
  final String scopeKind;
  final String scopedOwner;
  final String oauthIncarnation;
  const OAuthScopedOwnerRecord._(
    this.scopeKind,
    this.scopedOwner,
    this.oauthIncarnation,
  );

  static String _newId() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
  }

  static OAuthScopedOwnerRecord _newGuest() =>
      OAuthScopedOwnerRecord._('guest', 'g:${_newId()}', _newId());

  static OAuthScopedOwnerRecord _newAccount(String owner) =>
      OAuthScopedOwnerRecord._(
        'account',
        'a:${sha256.convert(utf8.encode(owner))}',
        _newId(),
      );

  String encode() => jsonEncode({
    'schema': 1,
    'scopeKind': scopeKind,
    'scopedOwner': scopedOwner,
    'oauthIncarnation': oauthIncarnation,
  });

  bool matchesAccountOwner(String? owner) => owner == null
      ? scopeKind == 'guest'
      : owner.trim().isNotEmpty &&
            scopeKind == 'account' &&
            scopedOwner == 'a:${sha256.convert(utf8.encode(owner))}';

  static OAuthScopedOwnerRecord? parse(Object? value) {
    if (value is! String) return null;
    try {
      final raw = jsonDecode(value);
      if (raw is! Map<String, dynamic> ||
          raw.length != 4 ||
          raw['schema'] is! int ||
          raw['schema'] != 1 ||
          raw['scopeKind'] is! String ||
          raw['scopedOwner'] is! String ||
          raw['oauthIncarnation'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(raw['oauthIncarnation'])) {
        return null;
      }
      final guest =
          raw['scopeKind'] == 'guest' &&
          RegExp(r'^g:[A-Za-z0-9_-]{32}$').hasMatch(raw['scopedOwner']);
      final account =
          raw['scopeKind'] == 'account' &&
          RegExp(r'^a:[0-9a-f]{64}$').hasMatch(raw['scopedOwner']);
      if (!guest && !account) return null;
      final result = OAuthScopedOwnerRecord._(
        raw['scopeKind'],
        raw['scopedOwner'],
        raw['oauthIncarnation'],
      );
      return result.encode() == value ? result : null;
    } catch (_) {
      return null;
    }
  }
}

/// Core identity evidence, not an Auth or source dispatch capability.
final class OAuthScopedWorkspaceSnapshot {
  final SharedPreferences _store;
  final OAuthScopedOwnerRecord record;
  final String rawRecord;
  final Object? _authState;
  final String? _accountOwner;
  final int _epoch;
  final int _resetRevision;
  final int _generation;
  const OAuthScopedWorkspaceSnapshot._(
    this._store,
    this.record,
    this.rawRecord,
    this._authState,
    this._accountOwner,
    this._epoch,
    this._resetRevision,
    this._generation,
  );
}

/// A single original diagnostic bound to already verified workspace evidence.
/// Auth must additionally sign the real session; this is not dispatch power.
final class OAuthScopedReconciliationSnapshot {
  final OAuthScopedWorkspaceSnapshot workspace;
  final OAuthStorageIndeterminate _diagnostic;
  const OAuthScopedReconciliationSnapshot._(this.workspace, this._diagnostic);
}

final class _GuestScopeInitialization {
  final OAuthScopeInitializationTicket ticket =
      OAuthScopeInitializationTicket._();
  final String raw;
  final Object? authState;
  final int epoch;
  final int reset;
  final int generation;
  final Map<String, Object?> inventory;
  final String? accountOwner;
  _GuestScopeInitialization(
    this.raw,
    this.authState,
    this.epoch,
    this.reset,
    this.generation,
    Map<String, Object?> inventory, {
    this.accountOwner,
  }) : inventory = Map.unmodifiable(inventory);
}

final class OAuthScopedWorkspaceUnavailable implements Exception {
  const OAuthScopedWorkspaceUnavailable();
  @override
  String toString() => 'OAuth workspace identity is unavailable or stale';
}

final class OAuthScopeInitializationPending implements Exception {
  final OAuthScopeInitializationTicket? ticket;
  const OAuthScopeInitializationPending({this.ticket});
  @override
  String toString() => 'OAuth workspace initialization requires confirmation';
}

/// Empty, identity-only process capability. The active candidate owns it.
final class OAuthScopeInitializationTicket {
  OAuthScopeInitializationTicket._();
  @override
  String toString() => 'OAuthScopeInitializationTicket';
}

/// No account identifier or credentials are stored in the retirement fence.
abstract class OAuthRetirementSession {
  final SharedPreferences preferences;
  final String _value;
  final OAuthAccountRetirementAnnouncement _announcement;
  bool _failed = false;
  OAuthRetirementSession._(this.preferences, this._value, this._announcement);
  String get _fenceKey;
}

final class OAuthAccountRetirementSession extends OAuthRetirementSession {
  final Object? _scopedFencePreimage;
  bool _scopedFenceRemoved = false;
  OAuthAccountRetirementSession._(
    super.preferences,
    super._value,
    super._announcement,
    this._scopedFencePreimage,
  ) : super._();
  @override
  String get _fenceKey => OAuthCalendarStorage.retirementFenceKey;
}

final class OAuthScopeRetirementSession extends OAuthRetirementSession {
  final OAuthScopeRetirementRequest request;
  OAuthScopeRetirementSession._(
    super.preferences,
    super._value,
    super._announcement,
    this.request,
  ) : super._();
  @override
  String get _fenceKey => OAuthCalendarStorage.scopeRetirementFenceKey;
}

class OAuthAccountRetirementAnnouncement {
  final Object _domain;
  SharedPreferences? _boundStore;
  final int _sequence;
  final bool _oauthOnly;
  final Set<OAuthAccountRetirementAnnouncement> _recovery = Set.identity();
  bool _failed = false;
  OAuthAccountRetirementAnnouncement._(
    this._domain,
    this._sequence,
    this._oauthOnly,
  );
}

enum OAuthScopeRetirementPurpose {
  guestAdoption,
  explicitReconnect,
  resumeKnownScope,
}

/// A captured cleanup description, not a permission to dispatch OAuth or write
/// a new account. The issuer supplies its transition/preparation authority.
final class OAuthScopeRetirementRequest {
  final SharedPreferences preferences;
  final String? expectedAccountOwner;
  final String? expectedScopedOwner;
  final OAuthScopeRetirementPurpose purpose;
  final bool Function() _isCurrent;
  final Object? _expectedScopedFence;
  final String? _scopeOwnerBinding;

  OAuthScopeRetirementRequest({
    required this.preferences,
    required this.expectedAccountOwner,
    required this.expectedScopedOwner,
    required this.purpose,
    required bool Function() isCurrent,
  }) : _isCurrent = isCurrent,
       _expectedScopedFence = AccountPreferenceTransaction.freezeValue(
         preferences.get(OAuthCalendarStorage.scopeRetirementFenceKey),
       ),
       _scopeOwnerBinding =
           _OAuthScopeMarker.parse(
             preferences.get(OAuthCalendarStorage.scopeRetirementFenceKey),
           )?.scopeOwner ??
           OAuthCalendarStorage._ownerDigest(expectedScopedOwner);

  bool get isCurrent => _isCurrent();

  void _ensureCurrent(
    SharedPreferences store, {
    bool checkOriginalFence = true,
  }) {
    if (!identical(preferences, store) ||
        !isCurrent ||
        (checkOriginalFence &&
            !AccountPreferenceTransaction.valuesEqual(
              store.get(OAuthCalendarStorage.scopeRetirementFenceKey),
              _expectedScopedFence,
            )) ||
        OAuthCalendarStorage._readOwner(
              store,
              OAuthCalendarStorage._accountOwnerKey,
            ) !=
            expectedAccountOwner ||
        OAuthCalendarStorage._readOwner(
              store,
              OAuthCalendarStorage.scopeOwnerKey,
            ) !=
            expectedScopedOwner) {
      throw const OAuthAccountRetirementPending();
    }
  }
}

final class OAuthRetirementInspection {
  final bool fullPending;
  final bool scopedPending;
  final bool runtimePending;
  final bool scopedRecoverable;
  const OAuthRetirementInspection._({
    required this.fullPending,
    required this.scopedPending,
    required this.runtimePending,
    required this.scopedRecoverable,
  });
  bool get hasPending => fullPending || scopedPending || runtimePending;
}

final class _OAuthScopeMarker {
  final String? globalOwner;
  final String? scopeOwner;
  _OAuthScopeMarker(this.globalOwner, this.scopeOwner);

  static _OAuthScopeMarker? parse(Object? value) {
    if (value is! String) return null;
    try {
      final raw = jsonDecode(value);
      if (raw is! Map<String, dynamic> ||
          raw.length != 7 ||
          raw['schema'] != 1 ||
          raw['scope'] != 'oauthOnly' ||
          raw['state'] != 'retiring' ||
          raw['retirementId'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(raw['retirementId']) ||
          !OAuthScopeRetirementPurpose.values.any(
            (p) => p.name == raw['purpose'],
          )) {
        return null;
      }
      for (final key in ['globalOwner', 'scopeOwner']) {
        if (!raw.containsKey(key) ||
            (raw[key] != null &&
                (raw[key] is! String ||
                    !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw[key])))) {
          return null;
        }
      }
      return _OAuthScopeMarker(raw['globalOwner'], raw['scopeOwner']);
    } catch (_) {
      return null;
    }
  }

  bool matches(SharedPreferences preferences) {
    try {
      final global = OAuthCalendarStorage._readOwner(
        preferences,
        OAuthCalendarStorage._accountOwnerKey,
      );
      final scoped = OAuthCalendarStorage._readOwner(
        preferences,
        OAuthCalendarStorage.scopeOwnerKey,
      );
      return globalOwner == OAuthCalendarStorage._ownerDigest(global) &&
          (scoped == null ||
              scopeOwner == OAuthCalendarStorage._ownerDigest(scoped));
    } catch (_) {
      return false;
    }
  }

  bool matchesRequest(OAuthScopeRetirementRequest request) =>
      globalOwner ==
          OAuthCalendarStorage._ownerDigest(request.expectedAccountOwner) &&
      scopeOwner == request._scopeOwnerBinding;
}

class OAuthAccountRetirementPending implements Exception {
  const OAuthAccountRetirementPending();
  @override
  String toString() => 'OAuth account cleanup is incomplete';
}

/// Credential-bearing journals stay private and never appear in UI/errors.
class OAuthStorageIndeterminate implements Exception {
  final Map<String, Object?> _previous;
  final Map<String, Object?> _issued;
  final int _epoch;
  final int _generation;
  final SharedPreferences _store;
  final OAuthScopedWorkspaceSnapshot? _workspace;

  OAuthStorageIndeterminate(
    Map<String, Object?> previous,
    Map<String, Object?> issued,
    this._epoch,
    this._generation, {
    required SharedPreferences store,
    OAuthScopedWorkspaceSnapshot? workspace,
  }) : _store = store,
       _workspace = workspace,
       _previous = Map.unmodifiable(previous),
       _issued = Map.unmodifiable(issued);

  @override
  String toString() => 'OAuth storage requires reconciliation';
}
