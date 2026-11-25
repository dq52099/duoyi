// ignore_for_file: depend_on_referenced_packages
// Source census: 18 cases = 6 initialization faults + 3 confirmation replacements
// + 8 strict parser variants + 1 static empty-account-owner counterexample.
// Prepared only; no formatter/compiler/test was run.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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
const _sidecar = 'duoyi_oauth_calendar_future_private162';
const _accountOwner = AccountLocalDataCleaner.accountDataOwnerKey;
const _emptyAccounts = '[ \n ]';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "guest162", "title" : "preserve todo162" } ]',
  'duoyi_notes': '[ { "body" : "preserve note162" } ]',
  'duoyi_ics_subscriptions_v1': '[ { "id" : "ordinary162" } ]',
  'sync_pending_local_changes': true,
  'pomodoro_config': '{ "minutes" : 27 }',
  'theme_unlocked_brands': <String>['brand162', 'second162'],
  'device_setting162': 162,
};

enum _Fault {
  falseBefore,
  falseAfter,
  throwAfter,
  readFailure,
  heldReadDispose,
  heldAckDispose,
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async => f = await _Fixture.create());
  tearDown(() async => f.close());

  const failures = <(String, _Fault)>[
    (
      'GSI162-01 owner ACK false before persistence requires explicit confirmation',
      _Fault.falseBefore,
    ),
    (
      'GSI162-02 owner ACK false after persistence requires explicit confirmation',
      _Fault.falseAfter,
    ),
    (
      'GSI162-03 owner throw after persistence keeps exact candidate for confirmation',
      _Fault.throwAfter,
    ),
    (
      'GSI162-04 owner ACK true with failing readback requires explicit confirmation',
      _Fault.readFailure,
    ),
    (
      'GSI162-05 held owner readback and disposed issuer cannot publish guest scope',
      _Fault.heldReadDispose,
    ),
    (
      'GSI162-06 held owner ACK and disposed issuer cannot publish guest scope',
      _Fault.heldAckDispose,
    ),
  ];
  for (final (name, fault) in failures) {
    test(name, () async {
      await f.run(() => _exerciseFailure(f, fault));
    });
  }

  test(
    'GSI162-07 confirmation rejects replacement with a different issuer-created owner',
    () async {
      await f.run(() async {
        final auth = await f.hydratedAuth();
        await f.issue(auth);
        final archivedOwner = (await f.disk())[_owner]! as String;
        // The replacement and failed candidate both originate at the actual
        // issuer. This explicit scoped retirement preserves ordinary raw data.
        await f.succeed(auth.prepareGuestOAuthWorkspace());
        f.expectOrdinary(await f.disk());
        f.store.mutations.clear();
        final step = f.store.planOwner(_Fault.falseAfter);
        await f.reject(
          auth.initializeGuestOAuthScope(),
          isA<OAuthScopeInitializationPending>(),
        );
        final candidate = step.raw!;
        expect(candidate, isNot(archivedOwner));
        expect(OAuthScopedOwnerRecord.parse(candidate), isNotNull);
        await f.store.inject(_owner, archivedOwner);
        final replaced = await f.disk();
        final attempts = f.store.mutations.toList();
        await f.reject(
          auth.confirmGuestOAuthScopeInitialization(),
          isA<OAuthScopeInitializationPending>(),
        );
        expect(await f.disk(), replaced);
        expect(f.store.mutations, attempts);
        expect((await f.disk())[_owner], archivedOwner);
        expect(
          auth.captureGuestOAuthScopeLease,
          throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
        );
        await f.expectLatch();
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    },
  );

  test(
    'GSI162-08 confirmation rejects replaced empty-container raw preimage',
    () async {
      await f.run(() async {
        final auth = await f.hydratedAuth();
        final step = f.store.planOwner(_Fault.falseAfter);
        await f.reject(
          auth.initializeGuestOAuthScope(),
          isA<OAuthScopeInitializationPending>(),
        );
        // Both rows decode to an empty list. Candidate inventory must retain
        // the exact original string, not silently rebase on equivalent JSON.
        await f.store.inject(_accounts, '[]');
        final replaced = await f.disk();
        expect(replaced[_owner], step.raw);
        final attempts = f.store.mutations.toList();
        await f.reject(
          auth.confirmGuestOAuthScopeInitialization(),
          isA<OAuthScopeInitializationPending>(),
        );
        expect(await f.disk(), replaced);
        expect(f.store.mutations, attempts);
        await f.expectLatch();
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    },
  );

  test(
    'GSI162-09 confirmation rejects newly inserted private sidecar',
    () async {
      await f.run(() async {
        final auth = await f.hydratedAuth();
        final step = f.store.planOwner(_Fault.falseAfter);
        await f.reject(
          auth.initializeGuestOAuthScope(),
          isA<OAuthScopeInitializationPending>(),
        );
        await f.store.inject(_sidecar, <String>['synthetic-private162']);
        final replaced = await f.disk();
        expect(replaced[_owner], step.raw);
        final attempts = f.store.mutations.toList();
        await f.reject(
          auth.confirmGuestOAuthScopeInitialization(),
          isA<OAuthScopedWorkspaceUnavailable>(),
        );
        expect(await f.disk(), replaced);
        expect(f.store.mutations, attempts);
        await f.expectLatch();
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    },
  );

  final parserCases = <(String, String Function(String))>[
    (
      'GSI162-10 truncated canonical owner is rejected without normalization',
      (raw) => raw.substring(0, raw.length - 1),
    ),
    (
      'GSI162-11 duplicate schema key is rejected without normalization',
      (raw) => '{"schema":1,${raw.substring(1)}',
    ),
    (
      'GSI162-12 duplicate scopedOwner key is rejected without normalization',
      (raw) {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        return '{"scopedOwner":${jsonEncode(record['scopedOwner'])},${raw.substring(1)}';
      },
    ),
    (
      'GSI162-13 surrounding whitespace owner is rejected without normalization',
      (raw) => ' $raw\n',
    ),
    (
      'GSI162-14 reversed owner field order is rejected without normalization',
      (raw) {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        return jsonEncode({
          'oauthIncarnation': record['oauthIncarnation'],
          'scopedOwner': record['scopedOwner'],
          'scopeKind': record['scopeKind'],
          'schema': record['schema'],
        });
      },
    ),
    (
      'GSI162-15 escaped scopeKind spelling is rejected without normalization',
      (raw) => raw.replaceFirst('"guest"', r'"g\u0075est"'),
    ),
    (
      'GSI162-16 floating schema version is rejected without normalization',
      (raw) => raw.replaceFirst('"schema":1', '"schema":1.0'),
    ),
    (
      'GSI162-17 extra owner field is rejected without normalization',
      (raw) => '{"extra":false,${raw.substring(1)}',
    ),
  ];
  for (final (name, corrupt) in parserCases) {
    test(name, () async {
      await f.run(() async {
        final issuer = await f.hydratedAuth();
        final lease = await f.issue(issuer);
        final canonical = (await f.disk())[_owner]! as String;
        final parsed = OAuthScopedOwnerRecord.parse(canonical);
        expect(parsed, isNotNull);
        expect(parsed!.encode(), canonical);
        expect(parsed.matchesAccountOwner(null), isTrue);
        expect(issuer.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
        final malformed = corrupt(canonical);
        expect(malformed, isNot(canonical));
        expect(OAuthScopedOwnerRecord.parse(malformed), isNull);
        await f.store.inject(_owner, malformed);
        final corrupted = await f.disk();
        f.store.mutations.clear();

        final peer = f.newAuth();
        await f.reject(
          peer.loadFromStorage(refreshServerConfig: false),
          isA<AccountLocalDataCleanupBlockedException>(),
        );
        expect(peer.isGuestWorkspaceReady, isFalse);
        expect(peer.isLocalAccountDataBlocked, isTrue);
        expect(peer.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
        await f.reject(peer.restoreGuestOAuthScope(), isA<ApiException>());
        await f.reject(
          issuer.restoreGuestOAuthScope(),
          isA<OAuthScopedWorkspaceUnavailable>(),
        );
        await f.reject(
          f.readDurable(lease),
          isA<OAuthScopedWorkspaceUnavailable>(),
        );
        expect(await f.disk(), corrupted);
        expect(f.store.mutations, isEmpty);
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    });
  }

  test(
    'GSI162-18 empty account-owner digest cannot authorize core scope read',
    () async {
      await f.run(() async {
        // Static negative core data only. This canonical record does not come
        // from, and must never be presented as, a legitimate Auth capability.
        final raw = jsonEncode({
          'schema': 1,
          'scopeKind': 'account',
          'scopedOwner': 'a:${sha256.convert(utf8.encode(''))}',
          'oauthIncarnation': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        });
        expect(OAuthScopedOwnerRecord.parse(raw)?.encode(), raw);
        await f.store.inject(_owner, raw);
        await f.store.inject(_accountOwner, '');
        final before = await f.disk();
        f.store.mutations.clear();
        await f.succeed(
          OAuthCalendarStorage.run<void>(() async {
            await f.prefs.reload();
            expect(
              () => OAuthCalendarStorage.readScopedWorkspaceLocked(
                f.prefs,
                expectedAuthState: _ordinary['auth_state'],
                expectedAccountOwner: '',
              ),
              throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
            );
          }, epoch: OAuthCalendarStorage.epoch),
        );
        expect(await f.disk(), before);
        expect(f.store.mutations, isEmpty);
        for (final entry in _ordinary.entries) {
          expect(before[entry.key], entry.value, reason: entry.key);
        }
        expect(f.requests, isEmpty);
      });
    },
  );
}

Future<void> _exerciseFailure(_Fixture f, _Fault fault) async {
  final auth = await f.hydratedAuth();
  final before = await f.disk();
  final epoch = OAuthCalendarStorage.epoch;
  final reset = OAuthCalendarStorage.resetRevision;
  final generation = AccountPreferenceWrites.generation;
  final step = f.store.planOwner(fault);
  var finished = false;
  final initialization = f.observe(
    auth.initializeGuestOAuthScope().whenComplete(() => finished = true),
  );
  await step.started.future.timeout(_wait);
  final disposed =
      fault == _Fault.heldReadDispose || fault == _Fault.heldAckDispose;
  if (fault == _Fault.heldReadDispose) {
    await step.read.started.future.timeout(_wait);
  }
  if (disposed) {
    expect(finished, isFalse);
    expect((await f.disk())[_owner], step.raw);
    expect(
      auth.captureGuestOAuthScopeLease,
      throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
    );
    f.dispose(auth);
    expect(auth.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
    if (fault == _Fault.heldAckDispose) {
      step.release.complete();
    } else {
      step.read.release.complete();
    }
  }
  final result = await initialization.timeout(_wait);
  // The revised public contract normalizes platform write/read exceptions to
  // the same pending type while retaining the candidate and original backing.
  expect(result.error, isA<OAuthScopeInitializationPending>());
  if (fault == _Fault.throwAfter) {
    expect(f.store.events, contains('throw:owner'));
  } else if (fault == _Fault.readFailure) {
    expect(f.store.events, contains('throw:readback'));
  } else if (fault == _Fault.falseBefore || fault == _Fault.falseAfter) {
    expect(f.store.events, contains('ack:owner:false'));
  }
  expect(finished, isTrue);
  final candidate = step.raw!;
  expect(OAuthScopedOwnerRecord.parse(candidate), isNotNull);
  final failed = await f.disk();
  expect(failed.containsKey(_owner), fault != _Fault.falseBefore);
  if (fault == _Fault.falseBefore) {
    expect(failed, before);
  } else {
    expect(failed[_owner], candidate);
    expect({
      for (final entry in failed.entries)
        if (entry.key != _owner) entry.key: entry.value,
    }, before);
  }
  expect(f.store.ownerValues, [candidate]);
  expect(f.store.mutations, ['set:$_owner']);
  if (fault == _Fault.readFailure || disposed) {
    expect(f.store.events, contains('ack:owner:true'));
  }
  expect(OAuthCalendarStorage.epoch, epoch);
  expect(OAuthCalendarStorage.resetRevision, reset);
  expect(AccountPreferenceWrites.generation, generation);
  await f.expectLatch();
  f.expectOrdinary(failed);

  // No singleton reset or sanitation between failure and these ordinary peers.
  // The exact store latch must reject even a canonical persisted candidate.
  final peer = f.newAuth();
  await f.reject(
    peer.loadFromStorage(refreshServerConfig: false),
    isA<AccountLocalDataCleanupBlockedException>(),
  );
  expect(peer.isGuestWorkspaceReady, isFalse);
  expect(peer.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
  await f.reject(peer.restoreGuestOAuthScope(), isA<ApiException>());
  await f.reject(peer.initializeGuestOAuthScope(), isA<ApiException>());
  await f.reject(
    peer.confirmGuestOAuthScopeInitialization(),
    isA<ApiException>(),
  );
  expect(await f.disk(), failed);
  expect(f.store.mutations, ['set:$_owner']);

  if (disposed) {
    await f.reject(
      auth.confirmGuestOAuthScopeInitialization(),
      isA<ApiException>(),
    );
    await f.expectLatch();
    expect(await f.disk(), failed);
    expect(f.store.ownerValues, [candidate]);
  } else {
    expect(auth.isGuestWorkspaceReady, isTrue);
    expect(
      auth.captureGuestOAuthScopeLease,
      throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
    );
    await f.reject(
      auth.restoreGuestOAuthScope(),
      isA<OAuthScopeInitializationPending>(),
    );
    await f.reject(
      auth.initializeGuestOAuthScope(),
      isA<OAuthScopeInitializationPending>(),
    );
    expect(await f.disk(), failed);
    expect(f.store.ownerValues, [candidate]);
    await f.succeed(auth.confirmGuestOAuthScopeInitialization());
    expect(f.store.ownerValues, [candidate, candidate]);
    final confirmed = await f.disk();
    expect(confirmed[_owner], candidate);
    expect(confirmed[_accounts], _emptyAccounts);
    f.expectOrdinary(confirmed);
    final lease = auth.captureGuestOAuthScopeLease();
    expect(lease.workspace.rawRecord, candidate);
    expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    await f.succeed(f.commitEmptyAccounts(auth, lease));
    await f.succeed(f.readDurable(lease));
    expect((await f.disk())[_accounts], '[]');
    expect(f.store.ownerValues, [candidate, candidate]);
    f.expectOrdinary(await f.disk());
    expect(OAuthCalendarStorage.epoch, epoch);
    expect(OAuthCalendarStorage.resetRevision, reset);
    expect(AccountPreferenceWrites.generation, generation);
  }
  expect(f.requests, isEmpty);
}

final class _InjectedWriteFailure implements Exception {
  const _InjectedWriteFailure();
  @override
  String toString() => 'synthetic owner162 throw after persistence';
}

final class _InjectedReadFailure implements Exception {
  const _InjectedReadFailure();
  @override
  String toString() => 'synthetic owner162 readback failure after true ACK';
}

class _ReadStep {
  _ReadStep({required this.held, required this.fail});
  final bool held;
  final bool fail;
  final failure = const _InjectedReadFailure();
  final started = Completer<void>();
  final release = Completer<void>();
}

class _OwnerStep {
  _OwnerStep(this.fault)
    : read = _ReadStep(
        held: fault == _Fault.heldReadDispose,
        fail: fault == _Fault.readFailure,
      );
  final _Fault fault;
  final _ReadStep read;
  final writeFailure = const _InjectedWriteFailure();
  final started = Completer<void>();
  final release = Completer<void>();
  String? raw;
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];
  final events = <String>[];
  final ownerValues = <String>[];
  final steps = <_OwnerStep>[];
  _OwnerStep? _nextOwner;
  _ReadStep? _nextRead;

  _OwnerStep planOwner(_Fault fault) {
    if (_nextOwner != null || _nextRead != null) {
      throw StateError('An initialization platform fault is already pending');
    }
    final step = _OwnerStep(fault);
    steps.add(step);
    _nextOwner = step;
    return step;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final step = _nextRead;
    _nextRead = null;
    if (step != null) {
      events.add('read:owner');
      step.started.complete();
      if (step.held) await step.release.future;
      if (step.fail) {
        events.add('throw:readback');
        throw step.failure;
      }
    }
    // The read occurs after the gate release, never from an earlier snapshot.
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final logical = _logical(key);
    mutations.add('set:$logical');
    if (logical != _owner) return super.setValue(type, key, value);
    expect(value, isA<String>());
    final raw = value as String;
    ownerValues.add(raw);
    final step = _nextOwner;
    _nextOwner = null;
    if (step == null) return super.setValue(type, key, value);
    step.raw = raw;
    if (step.fault != _Fault.falseBefore) {
      expect(await super.setValue(type, key, value), isTrue);
      events.add('persist:owner');
    }
    if (step.fault == _Fault.readFailure ||
        step.fault == _Fault.heldReadDispose) {
      _nextRead = step.read;
    }
    step.started.complete();
    if (step.fault == _Fault.heldAckDispose) await step.release.future;
    if (step.fault == _Fault.throwAfter) {
      events.add('throw:owner');
      throw step.writeFailure;
    }
    final accepted =
        step.fault != _Fault.falseBefore && step.fault != _Fault.falseAfter;
    events.add('ack:owner:$accepted');
    return accepted;
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
    for (final step in steps) {
      if (!step.release.isCompleted) step.release.complete();
      if (!step.read.release.isCompleted) step.read.release.complete();
    }
    _nextOwner = null;
    _nextRead = null;
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
    await store.inject(_accounts, _emptyAccounts);
    await prefs.reload();
    store.mutations.clear();
    return _Fixture(previous, store, prefs);
  }

  Future<void> run(Future<void> Function() body) async {
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method != 'GET' || request.url.path != '/api/config') {
        throw StateError('Unexpected initialization fixture HTTP request');
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
        .timeout(const Duration(seconds: 45));
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

  Future<AuthProvider> hydratedAuth() async {
    final auth = newAuth();
    await succeed(auth.loadFromStorage(refreshServerConfig: false));
    expect(auth.isGuestWorkspaceReady, isTrue);
    expect(
      auth.captureGuestOAuthScopeLease,
      throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
    );
    expect(store.mutations, isEmpty);
    return auth;
  }

  Future<AuthGuestOAuthScopeLease> issue(AuthProvider auth) async {
    await succeed(auth.initializeGuestOAuthScope());
    final lease = auth.captureGuestOAuthScopeLease();
    expect(auth.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    await succeed(readDurable(lease));
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

  Future<void> readDurable(AuthGuestOAuthScopeLease lease) =>
      OAuthCalendarStorage.run<void>(() async {
        await prefs.reload();
        OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
          lease.workspace,
          prefs,
        );
      }, epoch: OAuthCalendarStorage.epoch);

  Future<void> expectLatch() => OAuthCalendarStorage.run<void>(() async {
    await prefs.reload();
    expect(
      () => OAuthCalendarStorage.ensureAccountAdmissionLocked(prefs),
      throwsA(isA<OAuthScopeInitializationPending>()),
    );
    expect(
      () => OAuthCalendarStorage.readScopedWorkspaceLocked(
        prefs,
        expectedAuthState: _ordinary['auth_state'],
      ),
      throwsA(isA<OAuthScopeInitializationPending>()),
    );
  }, epoch: OAuthCalendarStorage.epoch).timeout(_wait);

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
    for (final key in _ordinary.keys) {
      expect(store.mutations, isNot(contains('set:$key')), reason: key);
      expect(store.mutations, isNot(contains('remove:$key')), reason: key);
    }
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
      // Public full cleanup runs only after measured assertions and owned work
      // settle, including disposed-issuer cases whose latch must remain pending.
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
