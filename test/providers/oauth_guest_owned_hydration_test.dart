// ignore_for_file: depend_on_referenced_packages
// Eight literal Auth + codec inventory cases. This is not evidence of an actual
// CalendarSyncProvider OAuth connection or provider dispatch authorization.
// Prepared only; no formatter, compiler, or test was run by this worker.

import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
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
const _accounts = OAuthCalendarStorage.accountsKey;
const _sourceId = 'oauth_owned_hydration';
const _cacheKey = '${OAuthCalendarStorage.eventsKeyPrefix}$_sourceId';
const _unknownKey = 'duoyi_oauth_calendar_unknown_owned_hydration';
const _ordinary = <String, Object>{
  'auth_state': '{ "token" : null }',
  'todos': '[ { "id" : "owned_hydration", "title" : "keep this todo" } ]',
  'duoyi_notes': '[ { "body" : "keep this note" } ]',
  'duoyi_ics_subscriptions_v1': '[ { "id" : "ordinary_subscription" } ]',
  'sync_pending_local_changes': true,
  'pomodoro_config': '{ "minutes" : 27 }',
  'theme_unlocked_brands': <String>['owned-hydration-brand', 'other-brand'],
  'owned_hydration_device_setting': 7,
};

Map<String, Object?> _account() => {
  'id': _sourceId,
  'provider': 'google',
  'displayName': 'Owned hydration calendar',
  'clientId': 'synthetic-owned-client',
  'clientSecret': '',
  'redirectUri': 'duoyi://oauth/callback',
  'calendarId': 'primary',
  'accessToken': 'synthetic-owned-access',
  'refreshToken': '',
  'expiresAt': '2026-11-10T12:00:00.000Z',
  'scope': 'calendar.readonly',
  'colorValue': 0xff336699,
  'enabled': true,
  'lastSyncedAt': null,
};

Map<String, Object?> _event() => {
  'id': 'owned_hydration_event',
  'title': 'Confirmed guest event',
  'date': '2026-11-10T09:00:00.000Z',
  'endDate': null,
  'subtitle': null,
  'colorValue': 0xff336699,
  'sourceId': _sourceId,
  'timeHour': 9,
  'timeMinute': 0,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'GOH-01 real guest issue and cold owned hydration restore bytes without writes or HTTP',
    () async {
      await _withFixture((f) async {
        final fresh = f.newAuth();
        expect(fresh.isGuestWorkspaceReady, isFalse);
        expect(fresh.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));
        expect(fresh.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
        await f.reject(fresh.initializeGuestOAuthScope(), isA<ApiException>());
        await f.reject(fresh.restoreGuestOAuthScope(), isA<ApiException>());
        expect(f.store.mutations, isEmpty);
        f.dispose(fresh);

        final installed = await f.installOwnedInventory();
        final before = await f.disk();
        expect(before[_owner], installed.lease.workspace.rawRecord);
        expect(before[_accounts], installed.accountsRaw);
        expect(before[_cacheKey], installed.cache.encode());
        expect(installed.source.metadataRevision, 2);
        expect(installed.source.credentialRevision, 2);
        expect(installed.cache.metadataRevision, 1);
        expect(installed.cache.credentialRevision, 1);
        expect(
          f.store.mutations,
          containsAll(['set:$_owner', 'set:$_accounts', 'set:$_cacheKey']),
        );
        f.expectOrdinary(before);
        f.dispose(installed.issuer);

        final cold = f.newAuth();
        expect(cold.isGuestWorkspaceReady, isFalse);
        expect(cold.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
        final runtime = _RuntimeStamps();
        final transition = cold.successfulAccountTransitionRevision;
        f.store.mutations.clear();
        await f.succeed(cold.loadFromStorage(refreshServerConfig: false));
        expect(cold.isGuestWorkspaceReady, isTrue);
        expect(cold.isLocalAccountDataBlocked, isFalse);
        expect(cold.state.isLoggedIn, isFalse);
        expect(cold.successfulAccountTransitionRevision, transition + 1);
        final lease = cold.captureGuestOAuthScopeLease();
        expect(cold.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
        expect(lease.workspace.rawRecord, installed.lease.workspace.rawRecord);
        await f.succeed(f.readOwnedInventory(cold, lease, installed));
        await f.succeed(cold.restoreGuestOAuthScope());
        final restored = cold.captureGuestOAuthScopeLease();
        expect(cold.isGuestOAuthScopeLeaseCurrent(restored), isTrue);
        expect(restored.workspace.rawRecord, lease.workspace.rawRecord);
        await f.succeed(f.readOwnedInventory(cold, restored, installed));
        await f.settle();
        runtime.expectUnchanged();
        expect(await f.disk(), before);
        expect(f.store.mutations, isEmpty);
        f.expectOrdinary(await f.disk());
        expect(f.requests, isEmpty);
      });
    },
  );

  test(
    'GOH-02 typed guest owner cannot adopt legacy unbound account rows',
    () async {
      await _withFixture((f) async {
        final installed = await f.installOwnedInventory();
        // Deliberate backing corruption after a legitimate issuer installation.
        // The typed owner remains real; legacy rows gain no authority from it.
        await f.store.inject(_accounts, jsonEncode([_account()]));
        await f.expectColdBlocked(installed);
      });
    },
  );

  test(
    'GOH-03 cold hydration rejects event cache from a different source incarnation',
    () async {
      await _withFixture((f) async {
        final installed = await f.installOwnedInventory();
        final otherSource = OAuthOwnedSourceRecord.create(
          scope: installed.scope,
          account: _account(),
        );
        expect(
          otherSource.sourceIncarnation,
          isNot(installed.source.sourceIncarnation),
        );
        final wrongCache = OAuthOwnedEventsRecord.create(
          source: otherSource,
          events: [_event()],
        );
        expect(wrongCache.scopedOwner, installed.source.scopedOwner);
        expect(wrongCache.oauthIncarnation, installed.source.oauthIncarnation);
        expect(
          OAuthOwnedEventsRecord.parse(
            wrongCache.encode(),
            source: installed.source,
          ),
          isNull,
        );
        await f.store.inject(_cacheKey, wrongCache.encode());
        await f.expectColdBlocked(installed);
      });
    },
  );

  test(
    'GOH-04 cold hydration rejects orphan cache without removing it',
    () async {
      await _withFixture((f) async {
        final installed = await f.installOwnedInventory();
        final orphan = OAuthOwnedSourceRecord.create(
          scope: installed.scope,
          account: _account()..['id'] = 'oauth_owned_orphan',
        );
        final cache = OAuthOwnedEventsRecord.create(
          source: orphan,
          events: [_event()..['sourceId'] = 'oauth_owned_orphan'],
        );
        await f.store.inject(
          '${OAuthCalendarStorage.eventsKeyPrefix}oauth_owned_orphan',
          cache.encode(),
        );
        await f.expectColdBlocked(installed);
      });
    },
  );

  test(
    'GOH-05 cold hydration rejects duplicate and noncanonical whole source lists',
    () async {
      for (final variant in [
        'duplicate-row',
        'duplicate-key',
        'noncanonical-whitespace',
      ]) {
        await _withFixture((f) async {
          final installed = await f.installOwnedInventory();
          final raw = switch (variant) {
            'duplicate-row' =>
              '[${installed.source.encode()},${installed.source.encode()}]',
            'duplicate-key' => installed.accountsRaw.replaceFirst(
              '"schema":2',
              '"schema":2,"schema":2',
            ),
            _ => ' ${installed.accountsRaw}\n',
          };
          expect(raw, isNot(installed.accountsRaw), reason: variant);
          expect(
            OAuthOwnedSourceRecord.parseList(raw, scope: installed.scope),
            isNull,
            reason: variant,
          );
          await f.store.inject(_accounts, raw);
          await f.expectColdBlocked(installed);
        });
      }
    },
  );

  test(
    'GOH-06 unknown OAuth sidecars block cold hydration and retain typed values',
    () async {
      for (final value in <Object>[
        'synthetic-private-sidecar',
        <String>['private-entry'],
        7,
      ]) {
        await _withFixture((f) async {
          final installed = await f.installOwnedInventory();
          await f.store.inject(_unknownKey, value);
          await f.expectColdBlocked(installed);
          expect((await f.disk())[_unknownKey], value);
        });
      }
    },
  );

  test(
    'GOH-07 pending authorization sidecar blocks cold hydration without sanitation',
    () async {
      await _withFixture((f) async {
        final installed = await f.installOwnedInventory();
        const pending = '{ "state" : "synthetic_pending_inventory" }';
        await f.store.inject(
          OAuthCalendarStorage.pendingAuthorizationKey,
          pending,
        );
        await f.expectColdBlocked(installed);
        expect(
          (await f.disk())[OAuthCalendarStorage.pendingAuthorizationKey],
          pending,
        );
      });
    },
  );

  test(
    'GOH-08 copied source incarnation and cross-source cache cannot authorize cold hydration',
    () async {
      await _withFixture((f) async {
        final installed = await f.installOwnedInventory();
        const otherId = 'oauth_owned_copied_incarnation';
        final copiedAccount = Map<String, Object?>.of(installed.source.account)
          ..['id'] = otherId
          ..['displayName'] = 'Different copied calendar'
          ..['clientId'] = 'different-synthetic-client'
          ..['calendarId'] = 'different-calendar';
        // Deliberate malformed backing copy, never an issuer-created B mutation.
        // A real configuration transition must create a fresh incarnation.
        final copiedRow = installed.source.toJson()
          ..['account'] = copiedAccount;
        expect(
          copiedRow['sourceIncarnation'],
          installed.source.sourceIncarnation,
        );
        final raw = jsonEncode([installed.source.toJson(), copiedRow]);
        expect(
          OAuthOwnedSourceRecord.parseList(raw, scope: installed.scope),
          isNull,
        );
        await f.store.inject(_accounts, raw);
        // A's original bound cache bytes are also copied under B's key suffix.
        // They must never become B's cache through the shared incarnation stamp.
        final otherCacheKey = '${OAuthCalendarStorage.eventsKeyPrefix}$otherId';
        await f.store.inject(otherCacheKey, installed.cache.encode());
        await f.expectColdBlocked(installed);
        expect((await f.disk())[otherCacheKey], installed.cache.encode());
      });
    },
  );
}

Future<void> _withFixture(Future<void> Function(_Fixture) body) async {
  final fixture = await _Fixture.create();
  try {
    await fixture.run(() => body(fixture));
  } finally {
    await fixture.close();
  }
}

class _RuntimeStamps {
  final epoch = OAuthCalendarStorage.epoch;
  final reset = OAuthCalendarStorage.resetRevision;
  final writes = AccountPreferenceWrites.generation;
  final account = AccountLocalDataCleaner.accountDataGeneration;

  void expectUnchanged() {
    expect(OAuthCalendarStorage.epoch, epoch);
    expect(OAuthCalendarStorage.resetRevision, reset);
    expect(AccountPreferenceWrites.generation, writes);
    expect(AccountLocalDataCleaner.accountDataGeneration, account);
  }
}

class _InstalledInventory {
  _InstalledInventory(
    this.issuer,
    this.lease,
    this.scope,
    this.source,
    this.cache,
  );
  final AuthProvider issuer;
  final AuthGuestOAuthScopeLease lease;
  final OAuthScopedOwnerRecord scope;
  final OAuthOwnedSourceRecord source;
  final OAuthOwnedEventsRecord cache;
  String get accountsRaw => jsonEncode([source.toJson()]);
}

class _BackingStore extends InMemorySharedPreferencesStore {
  _BackingStore() : super.withData({});
  final mutations = <String>[];

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

  // Setup or deliberate corruption only. Bypassing the recorder here keeps
  // measured mutations attributable to the real Auth/storage operations.
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
    // Public cleanup only before issuance; never between issue and cold load.
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    for (final entry in _ordinary.entries) {
      await store.inject(entry.key, entry.value);
    }
    await store.inject(_accounts, '[ \n ]');
    await prefs.reload();
    store.mutations.clear();
    return _Fixture(previous, store, prefs);
  }

  Future<void> run(Future<void> Function() body) async {
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      throw StateError('Owned hydration must not send an HTTP request');
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

  Future<_InstalledInventory> installOwnedInventory() async {
    final issuer = newAuth();
    expect(issuer.isGuestWorkspaceReady, isFalse);
    expect(issuer.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
    await succeed(issuer.loadFromStorage(refreshServerConfig: false));
    expect(issuer.isGuestWorkspaceReady, isTrue);
    expect(
      issuer.captureGuestOAuthScopeLease,
      throwsA(isA<OAuthScopedWorkspaceUnavailable>()),
    );
    expect(store.mutations, isEmpty);
    await succeed(issuer.initializeGuestOAuthScope());
    final lease = issuer.captureGuestOAuthScopeLease();
    expect(issuer.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    // The only owner identity used for records is parsed from this real Auth
    // lease. Parsing it supplies data; the issuer + token supply authority.
    final scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    expect(scope.scopeKind, 'guest');
    expect(scope.encode(), lease.workspace.rawRecord);
    final original = OAuthOwnedSourceRecord.create(
      scope: scope,
      account: _account(),
    );
    final cache = OAuthOwnedEventsRecord.create(
      source: original,
      events: [_event()],
    );
    final source = original.withAccount(
      _account()
        ..['displayName'] = 'Edited owned calendar'
        ..['accessToken'] = 'synthetic-rotated-access',
    );
    final installed = _InstalledInventory(issuer, lease, scope, source, cache);
    final epoch = OAuthCalendarStorage.epoch;
    await succeed(
      AccountPreferenceWrites.runResult<void>((token) {
        bool current() =>
            token.isCurrent && issuer.isGuestOAuthScopeLeaseCurrent(lease);
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
              _accounts: installed.accountsRaw,
              _cacheKey: cache.encode(),
            }, current);
          },
          epoch: epoch,
          isCurrent: current,
        );
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
    );
    expect(issuer.isGuestOAuthScopeLeaseCurrent(lease), isTrue);
    expect((await disk())[_owner], lease.workspace.rawRecord);
    expect((await disk())[_accounts], installed.accountsRaw);
    expect((await disk())[_cacheKey], cache.encode());
    await succeed(readOwnedInventory(issuer, lease, installed));
    expectOrdinary(await disk());
    expect(requests, isEmpty);
    return installed;
  }

  Future<void> readOwnedInventory(
    AuthProvider auth,
    AuthGuestOAuthScopeLease lease,
    _InstalledInventory expected,
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
          final scope = OAuthScopedOwnerRecord.parse(
            lease.workspace.rawRecord,
          )!;
          final rawAccounts = prefs.getString(_accounts)!;
          final rows = OAuthOwnedSourceRecord.parseList(
            rawAccounts,
            scope: scope,
          )!;
          expect(rows, hasLength(1));
          expect(rows.single.encode(), expected.source.encode());
          expect(
            rows.single.sourceIncarnation,
            expected.source.sourceIncarnation,
          );
          expect(rawAccounts, expected.accountsRaw);
          final rawCache = prefs.getString(_cacheKey)!;
          final cache = OAuthOwnedEventsRecord.parse(
            rawCache,
            source: rows.single,
          )!;
          expect(rawCache, expected.cache.encode());
          expect(cache.encode(), expected.cache.encode());
          expect(cache.events, [_event()]);
          expect(cache.metadataRevision, 1);
          expect(cache.credentialRevision, 1);
          if (!current()) throw const AccountPreferenceWriteCanceled();
        },
        epoch: epoch,
        isCurrent: current,
      );
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled());
  }

  Future<void> expectColdBlocked(_InstalledInventory installed) async {
    dispose(installed.issuer);
    final before = await disk();
    expect(before[_owner], installed.lease.workspace.rawRecord);
    expectOrdinary(before);
    final cold = newAuth();
    expect(cold.isGuestWorkspaceReady, isFalse);
    final transition = cold.successfulAccountTransitionRevision;
    final runtime = _RuntimeStamps();
    store.mutations.clear();
    await reject(
      cold.loadFromStorage(refreshServerConfig: false),
      isA<AccountLocalDataCleanupBlockedException>(),
    );
    expect(cold.isGuestWorkspaceReady, isFalse);
    expect(cold.isLocalAccountDataBlocked, isTrue);
    expect(cold.isAccountTransitionInProgress, isFalse);
    expect(cold.successfulAccountTransitionRevision, transition);
    expect(cold.captureGuestWorkspaceLease, throwsA(isA<ApiException>()));
    expect(cold.captureGuestOAuthScopeLease, throwsA(isA<ApiException>()));
    await reject(cold.restoreGuestOAuthScope(), isA<ApiException>());
    await reject(cold.initializeGuestOAuthScope(), isA<ApiException>());
    await reject(
      cold.confirmGuestOAuthScopeInitialization(),
      isA<ApiException>(),
    );
    await settle();
    runtime.expectUnchanged();
    expect(await disk(), before);
    expect(store.mutations, isEmpty);
    expectOrdinary(await disk());
    expect(requests, isEmpty);
  }

  Future<Map<String, Object>> disk() async => {
    for (final entry in (await store.backing()).entries)
      _BackingStore._logical(entry.key): entry.value,
  };

  void expectOrdinary(Map<String, Object> raw) {
    for (final entry in _ordinary.entries) {
      expect(raw[entry.key], entry.value, reason: entry.key);
    }
    expect(
      raw.containsKey(AccountLocalDataCleaner.accountDataOwnerKey),
      isFalse,
    );
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

  Future<void> settle() async {
    await succeed(AccountPreferenceWrites.drain());
    await succeed(
      OAuthCalendarStorage.run<void>(
        () async {},
        epoch: OAuthCalendarStorage.epoch,
      ),
    );
  }

  Future<void> close() async {
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
      await OAuthCalendarStorage.run<void>(
        () async {},
        epoch: OAuthCalendarStorage.epoch,
      ).timeout(_wait);
      for (final auth in auths) {
        auth.dispose();
      }
      // Assertions and every observed future settle before public cleanup.
      // No reset or cleanup occurs within any issue-to-hydration measurement.
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
