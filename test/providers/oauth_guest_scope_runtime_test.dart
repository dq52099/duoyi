// ignore_for_file: depend_on_referenced_packages
// Exactly two independent runtime-stamp cases. Prepared only; no formatter,
// compiler or test execution. The released initialization18 fixture is untouched.

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
const _accounts = 'duoyi_oauth_calendar_accounts_v1';
const _accountOwner = AccountLocalDataCleaner.accountDataOwnerKey;
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "runtime168", "title" : "keep todo168" } ]',
  'duoyi_notes': '[ { "body" : "keep note168" } ]',
  'duoyi_ics_subscriptions_v1': '[ { "id" : "ordinary168" } ]',
  'sync_pending_local_changes': true,
  'theme_unlocked_brands': <String>['runtime-brand168'],
  'device_setting168': 168,
};

Matcher get _noScopedLease =>
    anyOf(isA<ApiException>(), isA<OAuthScopedWorkspaceUnavailable>());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  test(
    'GSR168-01 cold guest hydration rejects reset changed during its lane read',
    () async {
      await f.run(() async {
        final issuer = f.newAuth();
        final originalLease = await f.issueGuest(issuer);
        expect(issuer.isGuestOAuthScopeLeaseCurrent(originalLease), isTrue);
        final durable = await f.disk();
        expect(durable[_owner], originalLease.workspace.rawRecord);
        expect(durable[_accounts], '[]');
        f.expectOrdinary(durable);
        f.dispose(issuer);

        // A genuinely unhydrated Auth instance reads the original durable scope.
        // Keep the same real singleton/backing; no cleanup or private reset is
        // inserted between the legitimate issue and this cold private ticket.
        final cold = f.newAuth();
        expect(cold.isGuestWorkspaceReady, isFalse);
        expect(cold.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
        final epoch = OAuthCalendarStorage.epoch;
        final reset = OAuthCalendarStorage.resetRevision;
        final writeGeneration = AccountPreferenceWrites.generation;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final transition = cold.successfulAccountTransitionRevision;
        f.store.mutations.clear();
        f.store.reads = 0;
        // getInstance is already the real cached singleton: read1 is hydration's
        // initial reload, read2 is its authoritative OAuth lane reload.
        final laneRead = f.store.holdRead(2);
        var finished = false;
        final loading = f.observe(
          cold.loadFromStorage(refreshServerConfig: false).whenComplete(() {
            finished = true;
          }),
        );
        await laneRead.started.future.timeout(_wait);
        expect(f.store.reads, 2);
        expect(finished, isFalse);
        expect(cold.isGuestWorkspaceReady, isFalse);
        expect(cold.isAccountTransitionInProgress, isTrue);
        expect(cold.successfulAccountTransitionRevision, transition);
        expect(f.store.mutations, isEmpty);
        expect(await f.disk(), durable);

        OAuthCalendarStorage.invalidateReset();
        expect(OAuthCalendarStorage.resetRevision, reset + 1);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(AccountPreferenceWrites.generation, writeGeneration);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGeneration,
        );
        laneRead.release.complete();
        final result = await loading.timeout(_wait);
        expect(result.error, isA<AccountLocalDataCleanupBlockedException>());
        expect(finished, isTrue);
        expect(cold.isGuestWorkspaceReady, isFalse);
        expect(cold.isLocalAccountDataBlocked, isTrue);
        expect(cold.isAccountTransitionInProgress, isFalse);
        expect(cold.successfulAccountTransitionRevision, transition);
        expect(cold.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
        expect(issuer.isGuestOAuthScopeLeaseCurrent(originalLease), isFalse);
        await f.reject(cold.restoreGuestOAuthScope(), isA<ApiException>());
        expect(await f.disk(), durable);
        expect(f.store.mutations, isEmpty);
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    },
  );

  test(
    'GSR168-02 queued guest restore rejects write generation changed before enrollment',
    () async {
      await f.run(() async {
        final auth = f.newAuth();
        final originalLease = await f.issueGuest(auth);
        expect(auth.isGuestOAuthScopeLeaseCurrent(originalLease), isTrue);
        final durable = await f.disk();
        expect(durable[_owner], originalLease.workspace.rawRecord);
        expect(durable[_accounts], '[]');
        f.expectOrdinary(durable);
        final epoch = OAuthCalendarStorage.epoch;
        final reset = OAuthCalendarStorage.resetRevision;
        final writeGeneration = AccountPreferenceWrites.generation;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        final session = auth.sessionGeneration;
        final transition = auth.successfulAccountTransitionRevision;
        f.store.mutations.clear();
        f.store.reads = 0;

        // No await/event turn between starting restore and invalidation. Its
        // Auth-tail callback cannot manufacture a fresh token for this old call.
        final restoring = f.observe(auth.restoreGuestOAuthScope());
        AccountPreferenceWrites.invalidate();
        expect(f.store.reads, 0);
        expect(f.store.mutations, isEmpty);
        expect(AccountPreferenceWrites.generation, writeGeneration + 1);
        expect(OAuthCalendarStorage.epoch, epoch);
        expect(OAuthCalendarStorage.resetRevision, reset);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          accountGeneration,
        );
        expect(auth.sessionGeneration, session);

        final result = await restoring.timeout(_wait);
        expect(result.error, isA<AccountPreferenceWriteCanceled>());
        expect(auth.isGuestOAuthScopeLeaseCurrent(originalLease), isFalse);
        expect(auth.captureGuestOAuthScopeLease, throwsA(_noScopedLease));
        expect(auth.successfulAccountTransitionRevision, transition);
        expect(auth.isAccountTransitionInProgress, isFalse);
        expect(await f.disk(), durable);
        expect(f.store.mutations, isEmpty);
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    },
  );
}

class _ReadGate {
  _ReadGate(this.number);
  final int number;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  final gates = <_ReadGate>[];
  int reads = 0;

  _ReadGate holdRead(int number) {
    if (number <= reads || gates.any((gate) => gate.number == number)) {
      throw StateError('Read gate must name a new future platform read');
    }
    final gate = _ReadGate(number);
    gates.add(gate);
    return gate;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    for (final gate in gates) {
      if (gate.number == reads && !gate.started.isCompleted) {
        gate.started.complete();
        await gate.release.future;
      }
    }
    // Read backing only after release, so the real reload sees the late event.
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

  Future<void> inject(String key, Object value) async {
    final type = switch (value) {
      String() => 'String',
      bool() => 'Bool',
      int() => 'Int',
      double() => 'Double',
      List<String>() => 'StringList',
      _ => throw ArgumentError('Unsupported synthetic backing value'),
    };
    expect(await super.setValue(type, 'flutter.$key', value), isTrue);
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
  final SharedPreferences prefs;
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
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final entry in _ordinary.entries) {
      await store.inject(entry.key, entry.value);
    }
    // A genuinely empty legacy container gives Auth its read-only guest path;
    // only the public initializer below creates the durable canonical identity.
    await store.inject(_accounts, '[ \n ]');
    await prefs.reload();
    store.mutations.clear();
    return _Fixture(previous, store, prefs);
  }

  Future<void> run(Future<void> Function() body) async {
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method != 'GET' || request.url.path != '/api/config') {
        throw StateError('Unexpected runtime-scope fixture HTTP request');
      }
      return http.Response(
        jsonEncode({
          'api_contract_version': ApiClient.requiredApiContractVersion,
          'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
          'config': <String, Object?>{},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    clients.add(client);
    await http
        .runWithClient(body, () => client)
        .timeout(const Duration(seconds: 30));
  }

  AuthProvider newAuth() {
    final auth = AuthProvider();
    auths.add(auth);
    return auth;
  }

  void dispose(AuthProvider auth) {
    auth.dispose();
    auths.remove(auth);
  }

  Future<AuthGuestOAuthScopeLease> issueGuest(AuthProvider auth) async {
    await succeed(auth.loadFromStorage(refreshServerConfig: false));
    expect(auth.isGuestWorkspaceReady, isTrue);
    await succeed(auth.initializeGuestOAuthScope());
    final lease = auth.captureGuestOAuthScopeLease();
    expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    expect(
      OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)?.encode(),
      lease.workspace.rawRecord,
    );
    await succeed(commitEmptyAccounts(auth, lease));
    return lease;
  }

  Future<void> commitEmptyAccounts(
    AuthProvider auth,
    AuthGuestOAuthScopeLease lease,
  ) {
    final epoch = OAuthCalendarStorage.epoch;
    return AccountPreferenceWrites.runResult<void>((token) {
      bool current() =>
          token.isCurrent && auth.isGuestOAuthScopeLeaseCurrent(lease);
      return OAuthCalendarStorage.run<void>(
        () async {
          await prefs.reload();
          token.ensureCurrent();
          OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
            lease.workspace,
            prefs,
          );
          if (!current()) throw const AccountPreferenceWriteCanceled();
          await OAuthCalendarStorage.commitLocked(prefs, {
            _accounts: '[]',
          }, current);
        },
        epoch: epoch,
        isCurrent: current,
      );
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      _BackingStore._logical(entry.key): entry.value,
  };

  void expectOrdinary(Map<String, Object> raw) {
    for (final entry in _ordinary.entries) {
      expect(raw[entry.key], entry.value, reason: entry.key);
    }
    expect(raw.containsKey(_accountOwner), isFalse);
    expect(raw.containsKey(OAuthCalendarStorage.retirementFenceKey), isFalse);
    expect(
      raw.containsKey(OAuthCalendarStorage.scopeRetirementFenceKey),
      isFalse,
    );
  }

  Future<_Outcome<T>> observe<T>(Future<T> work) {
    final observed = work.then<_Outcome<T>>(
      (value) => _Outcome<T>.value(value),
      onError: (Object error, StackTrace _) => _Outcome<T>.error(error),
    );
    pending.add(observed.then<void>((_) {}));
    return observed;
  }

  Future<void> succeed(Future<void> work) async {
    final result = await observe(work).timeout(_wait);
    expect(result.error, isNull);
  }

  Future<void> reject(Future<void> work, Matcher expected) async {
    final result = await observe(work).timeout(_wait);
    expect(result.error, expected);
  }

  Future<void> close() async {
    store.releaseAll();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      for (final auth in auths) {
        auth.dispose();
      }
      // Explicit public cleanup only after assertions and all observed work;
      // the durable issue-to-invalidation measurements never run sanitation.
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
