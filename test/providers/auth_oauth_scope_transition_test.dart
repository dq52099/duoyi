// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _wait = Duration(seconds: 5);
const _scope = OAuthCalendarStorage.scopeRetirementFenceKey;
const _full = OAuthCalendarStorage.retirementFenceKey;
const _scopeOwner = OAuthCalendarStorage.scopeOwnerKey;
const _accountOwner = AccountLocalDataCleaner.accountDataOwnerKey;
const _accounts = 'duoyi_oauth_calendar_accounts_v1';
const _guestAuth = '{ "token" : null }';
const _scopeBinding = 'synthetic-guest-scope112';
const _guest = <String, Object>{
  'todos': '[ { "id" : "guest112", "title" : "keep todo112" } ]',
  'duoyi_notes': '[ { "body" : "keep guest note112" } ]',
  'duoyi_ics_subscriptions_v1':
      '[ { "id" : "guest112", "url" : "https://example.invalid/guest112.ics" } ]',
  'duoyi_ics_events_guest112': '[ { "summary" : "keep ICS112" } ]',
  'duoyi_location_reminders_v1': '[]',
  'sync_deleted_items': '{ "todos" : [ "old112" ] }',
  'sync_pending_local_changes': true,
  'pomodoro_config': '{ "minutes" : 25 }',
  'theme_unlocked_brands': <String>['guest-brand112'],
  'auth_state': _guestAuth,
  'device_setting': 7,
};
const _oauth = <String, Object>{
  _scopeOwner: _scopeBinding,
  _accounts: 'synthetic-credential-bearing-accounts112',
  'duoyi_oauth_calendar_pending_authorization_v1': 'synthetic-pending112',
  'duoyi_oauth_calendar_events_guest112': '[ { "summary" : "private112" } ]',
  'duoyi_oauth_calendar_commit_state_v1': 'synthetic-journal112',
  'duoyi_oauth_calendar_future_private112': <String>['synthetic-secret112'],
  'duoyi_oauth_calendar_future_bool112': true,
};
const _account = AuthState(
  userId: 'next-user112',
  username: 'next-user112',
  token: 'synthetic-token112',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;

  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
  });

  test(
    'AOS112-01 guest login retires OAuth and preserves original guest bytes',
    () async {
      await f.seed();
      await f.withAuth((auth) async {
        expect(auth.isGuestWorkspaceReady, isFalse);
        await auth.login(
          username: _account.username!,
          password: 'synthetic-password112',
        );

        await f.expectScopedSuccess();
        final raw = await f.disk();
        expect(auth.state.userId, _account.userId);
        expect(auth.state.token, _account.token);
        expect(auth.successfulAccountTransitionRevision, 1);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(auth.isLocalAccountDataBlocked, isFalse);
        expect(raw[_accountOwner], 'id:next-user112');
        expect(
          AuthState.fromJson(jsonDecode(raw['auth_state']! as String)).token,
          _account.token,
        );
        expect(auth.validatedWidgetAccountIdentity, 'id:next-user112');
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));
        expect(f.store.count('set', 'auth_state'), 1);
        expect(f.store.count('set', _accountOwner), 1);
        expect(
          jsonDecode(f.store.scopeMarkers.single)['purpose'],
          'guestAdoption',
        );
        expect(f.loginRequests, 1);
      });
    },
  );

  test(
    'AOS112-02 held scoped fence ACK prevents auth and owner writes',
    () async {
      await f.seed();
      final before = await f.disk();
      final fence = f.store.plan('set', _scope, accepted: true, persists: true);
      await f.withAuth((auth) async {
        var finished = false;
        final login = f.observe(
          auth
              .login(
                username: _account.username!,
                password: 'synthetic-password112',
              )
              .whenComplete(() {
                finished = true;
              }),
        );
        await fence.started.future.timeout(_wait);

        final held = await f.disk();
        expect(held[_scope], isA<String>());
        expect(f.oauthData(held), f.oauthBefore);
        expect(held['auth_state'], before['auth_state']);
        expect(held.containsKey(_accountOwner), isFalse);
        expect(f.store.authOwnerAttempts, isEmpty);
        expect(f.store.oauthRemovals, isEmpty);
        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.isAccountTransitionInProgress, isTrue);
        expect(auth.successfulAccountTransitionRevision, 0);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.validatedWidgetAccountIdentity, isNull);
        expect(finished, isFalse);
        expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
        await f.expectOrdinary();

        fence.release.complete();
        expect((await login.timeout(_wait)).error, isNull);
        expect(finished, isTrue);
        await f.expectScopedSuccess();
        final ack = f.store.events.indexOf('ack:set:$_scope:true');
        final cleared = f.store.events.indexOf('ack:remove:$_scope:true');
        final authWrite = f.store.events.indexOf('attempt:set:auth_state');
        final ownerWrite = f.store.events.indexOf('attempt:set:$_accountOwner');
        expect(ack, greaterThanOrEqualTo(0));
        expect(cleared, greaterThan(ack));
        expect(authWrite, greaterThan(cleared));
        expect(ownerWrite, greaterThan(authWrite));
        expect(auth.state.token, _account.token);
        expect(auth.successfulAccountTransitionRevision, 1);
        expect(f.loginRequests, 1);
      });
    },
  );

  test(
    'AOS112-03 startup recovers old scoped fence before account owner adoption',
    () async {
      // Generate an interrupted marker with the real cleaner and disk write.
      // A rejected ACK persists the marker but prevents every OAuth deletion.
      final accountBytes = jsonEncode(_account.toJson());
      await f.seed(authBytes: accountBytes);
      final fence = f.store.plan(
        'set',
        _scope,
        accepted: false,
        persists: true,
      );
      final interrupted = f.observe(
        AccountLocalDataCleaner.runOAuthScopeRetirement<void>(
          OAuthScopeRetirementRequest(
            preferences: f.prefs,
            expectedAccountOwner: null,
            expectedScopedOwner: _scopeBinding,
            purpose: OAuthScopeRetirementPurpose.explicitReconnect,
            isCurrent: () => true,
          ),
          () async {},
        ),
      );
      await fence.started.future.timeout(_wait);
      fence.release.complete();
      expect(
        (await interrupted.timeout(_wait)).error,
        isA<OAuthAccountRetirementPending>(),
      );
      final persisted = await f.disk();
      expect(persisted[_scope], isA<String>());
      expect(f.oauthData(persisted), f.oauthBefore);
      expect(f.store.oauthRemovals, isEmpty);

      await f.restoreForFreshHydration(persisted);
      final inspection = OAuthCalendarStorage.inspectRetirementLocked(f.prefs);
      expect(inspection.scopedRecoverable, isTrue);
      expect(inspection.runtimePending, isFalse);
      expect(inspection.fullPending, isFalse);
      await f.withAuth((auth) async {
        await auth.loadFromStorage(refreshServerConfig: false);

        await f.expectScopedSuccess();
        final raw = await f.disk();
        expect(raw['auth_state'], accountBytes);
        expect(raw[_accountOwner], 'id:next-user112');
        expect(auth.state.token, _account.token);
        expect(auth.successfulAccountTransitionRevision, 1);
        expect(auth.isLocalAccountDataBlocked, isFalse);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(auth.validatedWidgetAccountIdentity, 'id:next-user112');
        expect(f.store.count('set', 'auth_state'), 0);
        expect(f.store.count('remove', 'auth_state'), 0);
        expect(f.store.count('set', _accountOwner), 1);
        expect(f.store.count('remove', _accountOwner), 0);
        expect(
          jsonDecode(f.store.scopeMarkers.single)['purpose'],
          'resumeKnownScope',
        );
        final cleared = f.store.events.indexOf('ack:remove:$_scope:true');
        expect(cleared, greaterThanOrEqualTo(0));
        expect(
          f.store.events.indexOf('attempt:set:$_accountOwner'),
          greaterThan(cleared),
        );
        expect(f.loginRequests, 0);
      });
    },
  );

  test(
    'AOS112-04 malformed scoped fence blocks startup and preserves guest bytes',
    () async {
      const malformed = '{"schema":1,"scope":"oauthOnly",BROKEN112';
      await f.seed(extra: {_scope: malformed});
      final before = await f.disk();
      await f.withAuth((auth) async {
        final loading = await f
            .observe(auth.loadFromStorage(refreshServerConfig: false))
            .timeout(_wait);

        expect(loading.error, isA<AccountLocalDataCleanupBlockedException>());
        expect(await f.disk(), before);
        await f.expectOrdinary();
        expect(f.oauthData(await f.disk()), f.oauthBefore);
        expect((await f.disk())[_scope], malformed);
        expect(f.store.authOwnerAttempts, isEmpty);
        expect(f.store.oauthRemovals, isEmpty);
        expect(f.store.count('set', _scope), 0);
        expect(f.store.count('remove', _scope), 0);
        f.expectNoFullRetirement();
        expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.isLocalAccountDataBlocked, isTrue);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(auth.successfulAccountTransitionRevision, 0);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));
        expect(f.loginRequests, 0);
      });
    },
  );

  test(
    'AOS112-05 unhydrated guest lease capture fails until genuine hydration',
    () async {
      await f.seed(includeOAuth: false);
      final before = await f.disk();
      await f.withAuth((auth) async {
        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));
        expect(f.store.attempts, isEmpty);
        expect(await f.disk(), before);

        await auth.loadFromStorage(refreshServerConfig: false);
        expect(auth.isGuestWorkspaceReady, isTrue);
        final lease = auth.captureGuestWorkspaceLease();
        expect(auth.isGuestWorkspaceLeaseCurrent(lease), isTrue);
        final foreign = f.newAuth();
        expect(foreign.isGuestWorkspaceLeaseCurrent(lease), isFalse);
        await f.expectOrdinary();
        expect((await f.disk())['auth_state'], _guestAuth);
        expect((await f.disk()).containsKey(_accountOwner), isFalse);
        expect(f.store.count('remove', _accountOwner), 1);

        await foreign.loadFromStorage(refreshServerConfig: false);
        expect(foreign.isGuestWorkspaceReady, isTrue);
        expect(foreign.isGuestWorkspaceLeaseCurrent(lease), isFalse);
        expect(
          foreign.isGuestWorkspaceLeaseCurrent(
            foreign.captureGuestWorkspaceLease(),
          ),
          isTrue,
        );

        // A new hydration boundary revokes the earlier guest authority.
        final reloading = f.observe(
          auth.loadFromStorage(refreshServerConfig: false),
        );
        expect(auth.isGuestWorkspaceLeaseCurrent(lease), isFalse);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect((await reloading.timeout(_wait)).error, isNull);
        expect(auth.isGuestWorkspaceReady, isTrue);
        expect(auth.isGuestWorkspaceLeaseCurrent(lease), isFalse);
        expect(
          auth.isGuestWorkspaceLeaseCurrent(auth.captureGuestWorkspaceLease()),
          isTrue,
        );
        expect(auth.successfulAccountTransitionRevision, 2);
        expect(f.store.count('set', 'auth_state'), 0);
        expect(f.store.count('set', _accountOwner), 0);
        await f.expectOrdinary();
        expect((await f.disk())['auth_state'], _guestAuth);
        expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
        f.expectNoFullRetirement();
        expect(f.loginRequests, 0);
      });
    },
  );

  test(
    'AOS112-06 explicit guest OAuth preparation clears legacy data before readiness',
    () async {
      await f.seed();
      final before = await f.disk();
      await f.withAuth((auth) async {
        final loading = await f
            .observe(auth.loadFromStorage(refreshServerConfig: false))
            .timeout(_wait);
        expect(loading.error, isA<AccountLocalDataCleanupBlockedException>());
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.isLocalAccountDataBlocked, isTrue);
        expect(await f.disk(), before);
        expect(f.store.authOwnerAttempts, isEmpty);
        f.expectNoFullRetirement();

        final ownerAck = f.store.plan(
          'remove',
          _accountOwner,
          accepted: true,
          persists: true,
        );
        final preparing = f.observe(auth.prepareGuestOAuthWorkspace());
        await ownerAck.started.future.timeout(_wait);
        await f.expectScopedSuccess();
        expect((await f.disk())['auth_state'], _guestAuth);
        expect((await f.disk()).containsKey(_accountOwner), isFalse);
        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.isAccountTransitionInProgress, isTrue);
        expect(auth.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));

        ownerAck.release.complete();
        expect((await preparing.timeout(_wait)).error, isNull);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(auth.isLocalAccountDataBlocked, isFalse);
        expect(auth.isGuestWorkspaceReady, isTrue);
        final lease = auth.captureGuestWorkspaceLease();
        expect(auth.isGuestWorkspaceLeaseCurrent(lease), isTrue);
        expect(f.store.count('remove', _accountOwner), 1);
        expect(f.store.count('set', _accountOwner), 0);
        expect(f.store.count('set', 'auth_state'), 0);
        expect(f.store.count('remove', 'auth_state'), 0);
        expect(
          jsonDecode(f.store.scopeMarkers.single)['purpose'],
          'explicitReconnect',
        );
        await f.expectScopedSuccess();
        expect(f.loginRequests, 0);
      });
    },
  );

  test(
    'AOS112-07 empty OAuth guest login waits for scoped ACK and reset listener',
    () async {
      await f.seed(includeOAuth: false);
      final before = await f.disk();
      final fence = f.store.plan('set', _scope, accepted: true, persists: true);
      final finalAck = f.store.plan(
        'remove',
        _scope,
        accepted: true,
        persists: true,
      );
      final observedPrefs = f.prefs;
      final observedStore = f.store;
      final listenerSnapshots = <List<Object>>[];
      var observing = true;
      // The storage API has no unregister hook. Disable this store-bound probe
      // before fixture teardown so later full cleanup cannot enter its census.
      OAuthCalendarStorage.registerAccountClearListener((preferences) {
        if (!observing || !identical(preferences, observedPrefs)) return;
        listenerSnapshots.add(<Object>[
          OAuthCalendarStorage.resetRevision,
          AccountPreferenceWrites.isBoundaryActive,
          preferences.containsKey(_scope),
          preferences.containsKey(_full),
        ]);
        observedStore.events.add('listener:empty-scope112');
      });
      try {
        await f.withAuth((auth) async {
          final login = f.observe(
            auth.login(
              username: _account.username!,
              password: 'synthetic-password112',
            ),
          );
          await fence.started.future.timeout(_wait);

          final held = await f.disk();
          expect(f.oauthBefore, isEmpty);
          expect(f.oauthData(held), isEmpty);
          expect(held[_scope], isA<String>());
          expect(held['auth_state'], before['auth_state']);
          expect(held.containsKey(_accountOwner), isFalse);
          expect(f.store.authOwnerAttempts, isEmpty);
          expect(f.store.oauthRemovals, isEmpty);
          expect(listenerSnapshots, isEmpty);
          expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
          expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
          expect(auth.state.isLoggedIn, isFalse);
          expect(auth.isAccountTransitionInProgress, isTrue);
          expect(auth.successfulAccountTransitionRevision, 0);
          await f.expectOrdinary();

          fence.release.complete();
          await finalAck.started.future.timeout(_wait);
          // Disk removal alone is insufficient: neither reset nor listener nor
          // account publication can precede the final successful platform ACK.
          expect((await f.disk()).containsKey(_scope), isFalse);
          expect(f.store.authOwnerAttempts, isEmpty);
          expect(listenerSnapshots, isEmpty);
          expect(OAuthCalendarStorage.resetRevision, f.resetBefore);
          expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
          expect(auth.state.isLoggedIn, isFalse);
          expect(auth.successfulAccountTransitionRevision, 0);
          f.expectNoFullRetirement();

          finalAck.release.complete();
          expect((await login.timeout(_wait)).error, isNull);
          await f.expectScopedSuccess();
          expect(listenerSnapshots, [
            <Object>[f.resetBefore + 1, true, false, false],
          ]);
          expect(f.store.oauthRemovals, isEmpty);
          expect(f.store.count('set', _scope), 1);
          expect(f.store.count('remove', _scope), 1);
          expect(f.store.count('set', 'auth_state'), 1);
          expect(f.store.count('set', _accountOwner), 1);
          final marker =
              jsonDecode(f.store.scopeMarkers.single) as Map<String, dynamic>;
          expect(marker['purpose'], 'guestAdoption');
          expect(marker['globalOwner'], isNull);
          expect(marker['scopeOwner'], isNull);
          final cleared = f.store.events.indexOf('ack:remove:$_scope:true');
          final listener = f.store.events.indexOf('listener:empty-scope112');
          final authWrite = f.store.events.indexOf('attempt:set:auth_state');
          final ownerWrite = f.store.events.indexOf(
            'attempt:set:$_accountOwner',
          );
          expect(cleared, greaterThanOrEqualTo(0));
          expect(listener, greaterThan(cleared));
          expect(authWrite, greaterThan(listener));
          expect(ownerWrite, greaterThan(authWrite));
          expect((await f.disk())[_accountOwner], 'id:next-user112');
          expect(auth.state.token, _account.token);
          expect(auth.successfulAccountTransitionRevision, 1);
          expect(auth.isAccountTransitionInProgress, isFalse);
          expect(auth.isLocalAccountDataBlocked, isFalse);
          expect(auth.isGuestWorkspaceReady, isFalse);
          expect(f.loginRequests, 1);
        });
      } finally {
        observing = false;
      }
    },
  );

  test(
    'AOS112-08 guest preparation rejects backing auth change during owner ACK',
    () async {
      await f.seed(includeOAuth: false);
      await f.withAuth((auth) async {
        await auth.loadFromStorage(refreshServerConfig: false);
        expect(auth.isGuestWorkspaceReady, isTrue);
        final originalLease = auth.captureGuestWorkspaceLease();
        expect(auth.isGuestWorkspaceLeaseCurrent(originalLease), isTrue);
        final revisionBefore = auth.successfulAccountTransitionRevision;
        f.store.clearLog();

        final ownerAck = f.store.plan(
          'remove',
          _accountOwner,
          accepted: true,
          persists: true,
        );
        final preparing = f.observe(auth.prepareGuestOAuthWorkspace());
        await ownerAck.started.future.timeout(_wait);
        await f.expectScopedSuccess();
        expect(auth.isAccountTransitionInProgress, isTrue);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.isGuestWorkspaceLeaseCurrent(originalLease), isFalse);
        expect(f.prefs.getString('auth_state'), _guestAuth);
        expect((await f.disk()).containsKey(_accountOwner), isFalse);

        final replacement = jsonEncode(_account.toJson());
        expect(
          await f.store.externalStringWrite('auth_state', replacement),
          isTrue,
        );
        // This is an external backing write, deliberately leaving the real
        // SharedPreferences cache stale until Auth reloads after the owner ACK.
        expect(f.prefs.getString('auth_state'), _guestAuth);
        expect((await f.disk())['auth_state'], replacement);
        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.isGuestWorkspaceReady, isFalse);
        ownerAck.release.complete();
        expect(
          (await preparing.timeout(_wait)).error,
          isA<AccountLocalDataCleanupBlockedException>(),
        );

        expect(f.prefs.getString('auth_state'), replacement);
        expect((await f.disk())['auth_state'], replacement);
        expect((await f.disk()).containsKey(_accountOwner), isFalse);
        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(auth.isLocalAccountDataBlocked, isTrue);
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.isGuestWorkspaceLeaseCurrent(originalLease), isFalse);
        expect(auth.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));
        expect(auth.validatedWidgetAccountIdentity, isNull);
        expect(auth.successfulAccountTransitionRevision, revisionBefore);
        expect(f.store.count('remove', _accountOwner), 1);
        expect(f.store.count('set', _accountOwner), 0);
        expect(f.store.count('set', 'auth_state'), 0);
        expect(f.store.count('remove', 'auth_state'), 0);
        expect(
          f.store.events.where((event) => event == 'external:set:auth_state'),
          hasLength(1),
        );
        expect(f.store.count('set', _scope), 1);
        expect(f.store.count('remove', _scope), 1);
        expect(
          jsonDecode(f.store.scopeMarkers.single)['purpose'],
          'explicitReconnect',
        );
        await f.expectScopedSuccess();
        expect(f.loginRequests, 0);
      });
    },
  );
}

class _Result<T> {
  _Result.value(this.value) : error = null;
  _Result.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

class _Step {
  _Step({required this.accepted, required this.persists});
  final bool accepted;
  final bool persists;
  final started = Completer<void>();
  final release = Completer<void>();
}

// Only the platform backing store controls ACK timing/failure. All Auth,
// preference cache, OAuth retirement and account cleanup logic remains real.
class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData(<String, Object>{});
  final attempts = <String>[];
  final events = <String>[];
  final scopeMarkers = <String>[];
  final steps = <_Step>[];
  final _plans = <String, List<_Step>>{};

  _Step plan(
    String operation,
    String key, {
    required bool accepted,
    required bool persists,
  }) {
    final step = _Step(accepted: accepted, persists: persists);
    _plans.putIfAbsent('$operation:$key', () => []).add(step);
    steps.add(step);
    return step;
  }

  int count(String operation, String key) =>
      attempts.where((entry) => entry == '$operation:$key').length;
  List<String> get authOwnerAttempts => attempts
      .where(
        (entry) =>
            entry == 'set:auth_state' ||
            entry == 'remove:auth_state' ||
            entry == 'set:$_accountOwner' ||
            entry == 'remove:$_accountOwner',
      )
      .toList();
  List<String> get oauthRemovals => attempts
      .where(
        (entry) =>
            entry.startsWith('remove:') &&
            OAuthCalendarStorage.isOAuthScopeKey(
              entry.substring('remove:'.length),
            ),
      )
      .toList();
  Future<Map<String, Object>> backing() => super.getAll();

  Future<bool> externalStringWrite(String key, String value) {
    events.add('external:set:$key');
    return super.setValue('String', 'flutter.$key', value);
  }

  Future<bool> _perform(
    String operation,
    String platformKey,
    Future<bool> Function() persist,
  ) async {
    final key = platformKey.substring('flutter.'.length);
    final id = '$operation:$key';
    attempts.add(id);
    events.add('attempt:$id');
    final plans = _plans[id];
    final step = plans == null || plans.isEmpty ? null : plans.removeAt(0);
    if (step == null) {
      final accepted = await persist();
      events.add('ack:$id:$accepted');
      return accepted;
    }
    if (step.persists) expect(await persist(), isTrue);
    step.started.complete();
    await step.release.future;
    events.add('ack:$id:${step.accepted}');
    return step.accepted;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.$_scope' && value is String) scopeMarkers.add(value);
    return _perform('set', key, () => super.setValue(type, key, value));
  }

  @override
  Future<bool> remove(String key) =>
      _perform('remove', key, () => super.remove(key));

  void clearLog() {
    attempts.clear();
    events.clear();
    scopeMarkers.clear();
  }

  void releaseAll() {
    for (final step in steps) {
      if (!step.release.isCompleted) step.release.complete();
    }
    _plans.clear();
  }
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _BackingStore store;
  SharedPreferences prefs;
  final pending = <Future<void>>[];
  final auths = <AuthProvider>[];
  final clients = <MockClient>[];
  int loginRequests = 0;
  late Map<String, Object> ordinaryBefore;
  late Map<String, Object> oauthBefore;
  late int resetBefore;
  late int oauthEpochBefore;
  late int icsBefore;

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _BackingStore();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    return _Fixture(previous, store, prefs);
  }

  MockClient newHttpClient() {
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        loginRequests++;
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], _account.username);
        expect(body['password'], 'synthetic-password112');
        return http.Response(
          jsonEncode(_account.toJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/api/config') {
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    clients.add(client);
    return client;
  }

  AuthProvider newAuth() {
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://example.test',
        httpClient: newHttpClient(),
      ),
    );
    auths.add(auth);
    return auth;
  }

  Future<void> withAuth(Future<void> Function(AuthProvider) operation) =>
      http.runWithClient(() async {
        await operation(newAuth());
      }, newHttpClient);

  Future<void> seed({
    bool includeOAuth = true,
    String authBytes = _guestAuth,
    Map<String, Object> extra = const {},
  }) async {
    final values = <String, Object>{
      ..._guest,
      'auth_state': authBytes,
      if (includeOAuth) ..._oauth,
      ...extra,
    };
    await writeValues(values);
    recordBaseline(await disk());
  }

  Future<void> writeValues(Map<String, Object> values) async {
    for (final entry in values.entries) {
      expect(
        await AccountPreferenceTransaction.writeValue(
          prefs,
          entry.key,
          entry.value,
        ),
        isTrue,
      );
    }
    await prefs.reload();
  }

  void recordBaseline(Map<String, Object> raw) {
    ordinaryBefore = ordinaryData(raw);
    oauthBefore = oauthData(raw);
    resetBefore = OAuthCalendarStorage.resetRevision;
    oauthEpochBefore = OAuthCalendarStorage.epoch;
    icsBefore = IcsSubscriptionStorage.epoch;
    store.clearLog();
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      entry.key.substring('flutter.'.length):
          AccountPreferenceTransaction.freezeValue(entry.value)!,
  };
  Map<String, Object> oauthData(Map<String, Object> raw) => {
    for (final entry in raw.entries)
      if (OAuthCalendarStorage.isOAuthScopeKey(entry.key))
        entry.key: entry.value,
  };
  Map<String, Object> ordinaryData(Map<String, Object> raw) => {
    for (final entry in raw.entries)
      if (!entry.key.startsWith('duoyi_oauth_calendar_') &&
          entry.key != 'auth_state' &&
          entry.key != _accountOwner)
        entry.key: entry.value,
  };

  Future<void> restoreForFreshHydration(Map<String, Object> persisted) async {
    // Settle genuine process-local retirement state before replaying the
    // interrupted disk image. No private reset or mocked cleanup is used.
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final key in (await disk()).keys.where(
      (key) => !persisted.containsKey(key),
    )) {
      expect(await prefs.remove(key), isTrue);
    }
    await writeValues(persisted);
    final previousPrefs = prefs;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(identical(previousPrefs, prefs), isFalse);
    expect(await disk(), persisted);
    recordBaseline(persisted);
  }

  Future<_Result<T>> observe<T>(Future<T> task) {
    final result = task.then<_Result<T>>(
      (value) => _Result<T>.value(value),
      onError: (Object error, StackTrace _) => _Result<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> expectOrdinary() async {
    final raw = await disk();
    expect(ordinaryData(raw), ordinaryBefore);
    // Compare serialized values themselves, preserving whitespace and bytes.
    for (final key in [
      'todos',
      'duoyi_notes',
      'duoyi_ics_subscriptions_v1',
      'duoyi_ics_events_guest112',
    ]) {
      expect(raw[key], ordinaryBefore[key]);
    }
    for (final key in ordinaryBefore.keys) {
      expect(store.count('remove', key), 0, reason: key);
      expect(store.count('set', key), 0, reason: key);
    }
    expect(IcsSubscriptionStorage.epoch, icsBefore);
    expect(OAuthCalendarStorage.epoch, oauthEpochBefore);
  }

  void expectNoFullRetirement() {
    expect(store.count('set', _full), 0);
    expect(store.count('remove', _full), 0);
  }

  Future<void> expectScopedSuccess() async {
    await expectOrdinary();
    final raw = await disk();
    expect(oauthData(raw), isEmpty);
    expect(raw.containsKey(_scope), isFalse);
    expect(raw.containsKey(_full), isFalse);
    expectNoFullRetirement();
    expect(OAuthCalendarStorage.resetRevision, resetBefore + 1);
    expect(OAuthCalendarStorage.isAccountRetiring(prefs), isFalse);
    expect(AccountPreferenceWrites.isBoundaryActive, isFalse);
  }

  Future<void> close() async {
    store.releaseAll();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      // Real full retirement is fixture teardown, after all measured assertions.
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      for (final auth in auths) {
        auth.dispose();
      }
      for (final client in clients) {
        client.close();
      }
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}
