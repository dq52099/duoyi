// Static Auth/core guest identity contract from review119.
// Empty-account controls do not prove typed nonempty consumer connections.
// There is no dynamic fallback, fake issuer, private reset, or skipped case.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
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
const _owner = OAuthCalendarStorage.scopeOwnerKey;
const _accountOwner = AccountLocalDataCleaner.accountDataOwnerKey;
const _accounts = 'duoyi_oauth_calendar_accounts_v1';
const _pending = 'duoyi_oauth_calendar_pending_authorization_v1';
const _legacyCache = 'duoyi_oauth_calendar_events_legacy134';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "guest134", "title" : "keep todo134" } ]',
  'duoyi_notes': '[ { "body" : "keep guest note134" } ]',
  'device_setting': 'keep-device134',
};
const _nextAccount = AuthState(
  userId: 'next-account134',
  username: 'next-account134',
  token: 'synthetic-auth-token134',
);

// Bind a new dedicated typed not-ready/stale exception here when its API is
// released. Do not replace this with throwsA(anything): unexpected errors fail.
Matcher get _rejected => anyOf(
  isA<ApiException>(),
  isA<AccountLocalDataCleanupBlockedException>(),
  isA<AccountPreferenceWriteCanceled>(),
  isA<OAuthAccountRetirementPending>(),
  isA<OAuthScopedWorkspaceUnavailable>(),
  isA<OAuthScopeInitializationPending>(),
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

  test('GSO134-01 default Auth cannot issue scoped guest authority', () async {
    await f.run(() async {
      final auth = f.newAuth();
      final before = await f.disk();
      expect(auth.isGuestWorkspaceReady, isFalse);
      expect(auth.captureGuestOAuthScopeLease, throwsA(_rejected));
      await expectLater(
        auth.initializeGuestOAuthScope().timeout(_wait),
        throwsA(_rejected),
      );
      expect(await f.disk(), before);
      expect(f.store.mutations, isEmpty);
      expect(f.requests, isEmpty);
    });
  });

  test(
    'GSO134-02 real issuer creates durable guest and admits fresh core write',
    () async {
      await f.run(() async {
        final auth = f.newAuth();
        final lease = await f.issueGuest(auth);
        final raw = await f.disk();
        expect(raw[_owner], isA<String>());
        expect(raw[_owner] as String, isNotEmpty);
        expect(raw[_accounts], '[]');
        expect(raw.containsKey(_accountOwner), isFalse);
        expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
        f.expectOrdinary(raw);
        // This positive control prevents an always-rejecting core guard from
        // satisfying the stale-write cases below.
        expect(f.store.mutations, contains('set:$_accounts'));
        expect(f.requests, isEmpty);
      });
    },
  );

  test(
    'GSO134-03 legitimate scoped guest fresh hydration is strictly readonly',
    () async {
      await f.run(() async {
        final first = f.newAuth();
        final oldLease = await f.issueGuest(first);
        final persisted = await f.disk();
        final epoch = OAuthCalendarStorage.epoch;
        final reset = OAuthCalendarStorage.resetRevision;
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        first.dispose();
        f.auths.remove(first);

        // Keep durable backing bytes. Do not run cleanup, replay raw credentials,
        // clear private runtime state, or call explicitReconnect between reads.
        SharedPreferences.resetStatic();
        f.prefs = await SharedPreferences.getInstance();
        f.store.mutations.clear();
        final restarted = f.newAuth();
        await restarted
            .loadFromStorage(refreshServerConfig: false)
            .timeout(_wait);
        await restarted.restoreGuestOAuthScope().timeout(_wait);
        final restoredLease = restarted.captureGuestOAuthScopeLease();

        expect(restarted.isGuestWorkspaceReady, isTrue);
        expect(restarted.isGuestOAuthScopeLeaseCurrent(restoredLease), isTrue);
        expect(first.isGuestOAuthScopeLeaseCurrent(oldLease), isFalse);
        await f.checkDurableSnapshot(restoredLease).timeout(_wait);
        expect(await f.disk(), persisted);
        expect(f.store.mutations, isEmpty);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(OAuthCalendarStorage.resetRevision, reset);
        expect(AccountLocalDataCleaner.accountDataGeneration, generation);
        expect(f.requests, isEmpty);
      });
    },
  );

  final legacyCases = <(String, Map<String, Object>)>[
    (
      'GSO134-04 legacy string owner cannot adopt old credentials',
      {
        _owner: 'legacy-untyped-owner134',
        _accounts: '[{"id":"legacy134","access_token":"synthetic-unowned134"}]',
        _legacyCache: '[ { "summary" : "private legacy134" } ]',
      },
    ),
    (
      'GSO134-05 missing owner with old pending remains quarantined',
      {
        _accounts: '[{"id":"legacy134","access_token":"synthetic-unowned134"}]',
        _pending:
            '{"state":"synthetic-old-state134","code":"synthetic-old-code134"}',
        _legacyCache: '[ { "summary" : "private legacy134" } ]',
      },
    ),
    (
      'GSO134-06 malformed owner JSON is preserved and never normalized',
      {_owner: '{broken-owner134', _accounts: '[]'},
    ),
    (
      'GSO134-07 wrong-type owner is preserved and never treated as absent',
      {_owner: true, _accounts: '[]'},
    ),
  ];
  for (final (name, legacy) in legacyCases) {
    test(name, () async {
      await f.run(() async {
        for (final entry in legacy.entries) {
          await f.store.inject(entry.key, entry.value);
        }
        await f.prefs.reload();
        final before = await f.disk();
        f.store.mutations.clear();
        final auth = f.newAuth();
        await expectLater(
          auth.loadFromStorage(refreshServerConfig: false).timeout(_wait),
          throwsA(isA<AccountLocalDataCleanupBlockedException>()),
        );
        expect(auth.isGuestWorkspaceReady, isFalse);
        expect(auth.isLocalAccountDataBlocked, isTrue);
        expect(auth.captureGuestOAuthScopeLease, throwsA(_rejected));
        await expectLater(
          auth.restoreGuestOAuthScope().timeout(_wait),
          throwsA(_rejected),
        );
        await expectLater(
          auth.initializeGuestOAuthScope().timeout(_wait),
          throwsA(_rejected),
        );
        expect(await f.disk(), before);
        expect(before.containsKey(_accountOwner), isFalse);
        expect((await f.disk()).containsKey(_accountOwner), isFalse);
        expect(
          f.store.mutations.where(
            (item) => item.contains('duoyi_oauth_calendar_'),
          ),
          isEmpty,
        );
        expect(f.store.mutations, isNot(contains('set:$_accountOwner')));
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    });
  }

  for (final field in ['scopedOwner', 'oauthIncarnation']) {
    test(
      'GSO134-08 durable $field replacement rejects held old core write',
      () async {
        await f.run(() async {
          final auth = f.newAuth();
          await f.issueGuest(auth);
          final archived =
              jsonDecode((await f.disk())[_owner]! as String)
                  as Map<String, dynamic>;
          // Generate both identities through the actual issuer. Retire the first
          // explicitly, then capture the second only after that reset settles.
          await auth.prepareGuestOAuthWorkspace().timeout(_wait);
          await auth.initializeGuestOAuthScope().timeout(_wait);
          final lease = auth.captureGuestOAuthScopeLease();
          final current = await f.disk();
          final replacement =
              jsonDecode(current[_owner]! as String) as Map<String, dynamic>;
          expect(replacement[field], isNot(archived[field]));
          // Negative external rollback: change just one durable identity field.
          // This never serves as the positive fixture's issuer or parser.
          replacement[field] = archived[field];
          final replacementRaw = jsonEncode(replacement);
          final session = auth.sessionGeneration;
          final generation = AccountLocalDataCleaner.accountDataGeneration;
          final epoch = OAuthCalendarStorage.epoch;
          final reset = OAuthCalendarStorage.resetRevision;
          f.store.mutations.clear();
          final read = f.store.holdNextRead();
          final pending = f.observe(f.commitEmptyAccounts(auth, lease));
          await read.started.future.timeout(_wait);
          await f.store.inject(_owner, replacementRaw);
          // A disk-only change must not need a login/reset to invalidate the
          // captured durable preimage. These runtime stamps remain untouched.
          expect(auth.sessionGeneration, session);
          expect(AccountLocalDataCleaner.accountDataGeneration, generation);
          expect(OAuthCalendarStorage.epoch, epoch);
          expect(OAuthCalendarStorage.resetRevision, reset);
          read.release.complete();
          final result = await pending.timeout(_wait);
          expect(result.error, _rejected);
          expect(f.store.mutations, isEmpty);
          final after = await f.disk();
          expect(after[_owner], replacementRaw);
          expect(after.containsKey(_accounts), isFalse);
          f.expectOrdinary(after);
          expect(f.requests, isEmpty);
        });
      },
    );
  }

  test(
    'GSO134-09 real login retires guest and rejects its old durable snapshot',
    () async {
      await f.run(() async {
        final auth = f.newAuth();
        final lease = await f.issueGuest(auth);
        final oldOwner = (await f.disk())[_owner];
        await auth
            .login(
              username: _nextAccount.username!,
              password: 'synthetic-password134',
            )
            .timeout(_wait);
        await f.prefs.reload();
        final accountDisk = await f.disk();
        expect(auth.state.userId, _nextAccount.userId);
        expect(auth.validatedWidgetAccountIdentity, 'id:next-account134');
        expect(accountDisk[_accountOwner], 'id:next-account134');
        expect(accountDisk.containsKey(_owner), isFalse);
        expect(accountDisk.containsKey(_accounts), isFalse);
        expect(accountDisk.values, isNot(contains(oldOwner)));
        expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isFalse);
        expect(auth.captureGuestOAuthScopeLease, throwsA(_rejected));
        await expectLater(
          f.checkDurableSnapshot(lease).timeout(_wait),
          throwsA(_rejected),
        );
        f.store.mutations.clear();
        await expectLater(
          f.commitEmptyAccounts(auth, lease).timeout(_wait),
          throwsA(_rejected),
        );
        expect(await f.disk(), accountDisk);
        expect(f.store.mutations, isEmpty);
        for (final key in ['todos', 'duoyi_notes', 'device_setting']) {
          expect(accountDisk[key], _ordinary[key]);
        }
        expect(f.requests, contains('POST /api/auth/login'));
        expect(
          f.requests.where(
            (request) =>
                request != 'POST /api/auth/login' &&
                request != 'GET /api/config',
          ),
          isEmpty,
        );
      });
    },
  );
}

class _ReadGate {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  final gates = <_ReadGate>[];
  _ReadGate? _nextRead;

  _ReadGate holdNextRead() {
    if (_nextRead != null) throw StateError('A read is already held');
    final gate = _ReadGate();
    gates.add(gate);
    _nextRead = gate;
    return gate;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final gate = _nextRead;
    _nextRead = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    // Read after release: the production reload sees the actual late backing
    // replacement, rather than a test snapshot taken before the awaited gate.
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutations.add('set:${_logical(key)}');
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations.add('remove:${_logical(key)}');
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations.add('clear');
    return super.clear();
  }

  Future<Map<String, Object>> backing() => super.getAll();

  // Fault injection acts below SharedPreferences' cache; it is not counted as
  // a production mutation. No core/Auth state or private field is changed.
  Future<void> inject(String key, Object value) async {
    final type = switch (value) {
      String() => 'String',
      bool() => 'Bool',
      int() => 'Int',
      double() => 'Double',
      List<String>() => 'StringList',
      _ => throw ArgumentError('Unsupported backing value'),
    };
    if (!await super.setValue(type, 'flutter.$key', value)) {
      throw StateError('Backing injection was rejected');
    }
  }

  void releaseAll() {
    for (final gate in gates) {
      if (!gate.release.isCompleted) gate.release.complete();
    }
  }

  static String _logical(String key) =>
      key.startsWith('flutter.') ? key.substring(8) : key;
}

class _Outcome<T> {
  _Outcome.value(this.value) : error = null;
  _Outcome.error(this.error) : value = null;
  final T? value;
  final Object? error;
}

class _Fixture {
  _Fixture(this.previous, this.store, this.prefs);
  final SharedPreferencesStorePlatform previous;
  final _BackingStore store;
  SharedPreferences prefs;
  final auths = <AuthProvider>[];
  final clients = <http.Client>[];
  final requests = <String>[];
  final pending = <Future<void>>[];

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _BackingStore();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    // Real public cleanup only at fixture admission/teardown, never between
    // the positive persistence and its readonly restarted hydration.
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final entry in _ordinary.entries) {
      await store.inject(entry.key, entry.value);
    }
    await prefs.reload();
    store.mutations.clear();
    return _Fixture(previous, store, prefs);
  }

  Future<void> run(Future<void> Function() body) async {
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      final Object payload;
      if (request.method == 'POST' && request.url.path == '/api/auth/login') {
        payload = _nextAccount.toJson();
      } else if (request.method == 'GET' && request.url.path == '/api/config') {
        payload = {
          'api_contract_version': ApiClient.requiredApiContractVersion,
          'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
          'config': <String, Object?>{},
        };
      } else {
        throw StateError('Unexpected fixture HTTP request');
      }
      return http.Response(
        jsonEncode(payload),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    clients.add(client);
    await http
        .runWithClient(body, () => client)
        .timeout(const Duration(seconds: 20));
  }

  AuthProvider newAuth() {
    final auth = AuthProvider();
    auths.add(auth);
    return auth;
  }

  Future<AuthGuestOAuthScopeLease> issueGuest(AuthProvider auth) async {
    await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
    await auth.initializeGuestOAuthScope().timeout(_wait);
    final lease = auth.captureGuestOAuthScopeLease();
    await commitEmptyAccounts(auth, lease).timeout(_wait);
    return lease;
  }

  Future<void> commitEmptyAccounts(
    AuthProvider auth,
    AuthGuestOAuthScopeLease lease,
  ) {
    final epoch = OAuthCalendarStorage.epoch;
    final storeAtEntry = prefs;
    return AccountPreferenceWrites.runResult<void>((token) {
      bool current() =>
          token.isCurrent && auth.isGuestOAuthScopeLeaseCurrent(lease);
      return OAuthCalendarStorage.run<void>(
        () async {
          await storeAtEntry.reload();
          token.ensureCurrent();
          OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
            lease.workspace,
            storeAtEntry,
          );
          if (!current()) throw const AccountPreferenceWriteCanceled();
          // An empty account container exercises the real core guard and checked
          // commit without inventing a credential/row codec or dispatching HTTP.
          await OAuthCalendarStorage.commitLocked(storeAtEntry, {
            _accounts: '[]',
          }, current);
        },
        epoch: epoch,
        isCurrent: current,
      );
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
  }

  Future<void> checkDurableSnapshot(AuthGuestOAuthScopeLease lease) {
    final storeAtEntry = prefs;
    final epoch = OAuthCalendarStorage.epoch;
    return OAuthCalendarStorage.run<void>(() async {
      await storeAtEntry.reload();
      OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
        lease.workspace,
        storeAtEntry,
      );
    }, epoch: epoch);
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      _BackingStore._logical(entry.key): entry.value,
  };

  void expectOrdinary(Map<String, Object> raw) {
    for (final entry in _ordinary.entries) {
      expect(raw[entry.key], entry.value, reason: entry.key);
    }
  }

  Future<_Outcome<T>> observe<T>(Future<T> task) {
    final result = task.then<_Outcome<T>>(
      (value) => _Outcome<T>.value(value),
      onError: (Object error, StackTrace _) => _Outcome<T>.error(error),
    );
    pending.add(result.then<void>((_) {}));
    return result;
  }

  Future<void> close() async {
    store.releaseAll();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      for (final auth in auths) {
        auth.dispose();
      }
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    } finally {
      for (final client in clients) {
        client.close();
      }
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
    }
  }
}
