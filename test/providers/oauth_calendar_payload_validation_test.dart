// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:duoyi/core/oauth_refresh_journal.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _accountsKey = 'duoyi_oauth_calendar_accounts_v1';
const _pendingKey = 'duoyi_oauth_calendar_pending_authorization_v1';
const _cacheKey = 'duoyi_oauth_calendar_events_existing';
const _wait = Duration(seconds: 4);
const _oldTitle = 'Confirmed OAuth event';
const _codeVerifier =
    'synthetic-code-verifier-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ';

// Uses the real provider and legacy preference codec, with no provider method
// overrides. Public http.runWithClient supplies a fresh MockClient per request.
// Response gates establish order; watchdogs only bound unexpected deadlocks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
  });

  for (final provider in OAuthCalendarProvider.values) {
    test(
      '${provider.name} commits two complete calendar pages once',
      () => f.withHttp(() async {
        final original = await f.seed(provider);
        f.feed.pageCount = 2;
        f.feed.holdPage = 2;
        final published = <List<String>>[];
        f.provider.addListener(() => published.add(_titles(f.provider)));
        final syncing = f.observe(f.provider.syncAll());
        await f.feed.heldPageStarted.future.timeout(_wait);

        expect(f.feed.eventRequests, hasLength(2));
        f.feed.expectContinuation(2);
        expect(_titles(f.provider), [_oldTitle]);
        expect(f.store.writtenKeys, isEmpty, reason: 'pages are unpublished');
        await f.expectRaw(original);

        f.feed.releaseHeldPage();
        expect(await syncing.timeout(_wait), isNull);
        expect(f.provider.isSyncing, isFalse);
        expect(f.provider.lastError, isNull);
        expect(_titles(f.provider), ['Page 1 event', 'Page 2 event']);
        expect(f.feed.tokenRequests, isEmpty);
        expect(
          f.store.writtenKeys.where((key) => key == 'flutter.$_cacheKey'),
          hasLength(1),
          reason: 'commit the complete calendar once',
        );
        for (final titles in published) {
          expect(
            titles,
            anyOf(
              equals([_oldTitle]),
              equals(['Page 1 event', 'Page 2 event']),
            ),
            reason: 'no partial page may become visible',
          );
        }
        await f.expectCommittedTitles(['Page 1 event', 'Page 2 event']);
      }),
    );

    test(
      '${provider.name} valid empty calendar commits absence and advances timestamp',
      () => f.withHttp(() async {
        await f.seed(provider);
        f.feed.pagePayloads[1] = {_collectionKey(provider): <Object?>[]};
        expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
        expect(f.provider.lastError, isNull);
        expect(_titles(f.provider), isEmpty);
        expect(f.feed.eventRequests, hasLength(1));
        await f.expectCommittedTitles(<String>[]);
      }),
    );

    for (final shape in ['missing', 'null', 'object', 'other provider']) {
      test(
        '${provider.name} $shape event collection cannot erase a confirmed cache',
        () => f.withHttp(() async {
          final original = await f.seed(provider);
          f.feed.pagePayloads[1] = _malformedEnvelope(provider, shape);
          expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
          expect(f.provider.isSyncing, isFalse);
          expect(f.provider.lastError, isNotNull);
          expect(_titles(f.provider), [_oldTitle]);
          expect(f.provider.oauthAccounts.single.lastSyncedAt, _oldSync);
          expect(f.feed.eventRequests, hasLength(1));
          expect(f.store.writtenKeys, isEmpty);
          await f.expectRaw(original);
        }),
      );
    }

    test(
      '${provider.name} malformed second page preserves the entire prior calendar',
      () => f.withHttp(() async {
        final original = await f.seed(provider);
        f.feed.pageCount = 2;
        f.feed.pagePayloads[2] = {'unexpected': <Object?>[]};
        expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
        expect(f.feed.eventRequests, hasLength(2));
        f.feed.expectContinuation(2);
        expect(f.provider.lastError, isNotNull);
        expect(_titles(f.provider), [_oldTitle]);
        expect(f.provider.oauthAccounts.single.lastSyncedAt, _oldSync);
        expect(f.store.writtenKeys, isEmpty);
        await f.expectRaw(original);
      }),
    );

    test(
      '${provider.name} omitted refresh token retains confirmed refresh credential',
      () => f.withHttp(() async {
        await f.seed(provider, expired: true);
        f.feed.tokenPayload = {
          'access_token': 'synthetic-renewed-access',
          'expires_in': 3600,
          'token_type': 'Bearer',
        };
        expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
        expect(f.feed.tokenRequests, hasLength(1));
        final renewed = f.provider.oauthAccounts.single;
        expect(renewed.accessToken, 'synthetic-renewed-access');
        expect(renewed.refreshToken, 'synthetic-old-refresh');
        expect(renewed.expiresAt.isAfter(DateTime.now()), isTrue);
        expect(f.feed.eventRequests, hasLength(1));
        expect(f.provider.lastError, isNull);
        final disk = await f.store.getAll();
        final rows = f.accountRows(disk['flutter.$_accountsKey'] as String);
        expect(rows.single['refreshToken'], 'synthetic-old-refresh');
      }),
    );

    test(
      '${provider.name} repeated continuation rejects before another request',
      () => f.withHttp(() async {
        final original = await f.seed(provider);
        f.feed.pageCount = 2;
        f.feed.pagePayloads[2] = {
          _collectionKey(provider): [_event(provider, 2)],
          if (provider == OAuthCalendarProvider.google)
            'nextPageToken': 'page-2'
          else
            '@odata.nextLink': _outlookNext(2).toString(),
        };
        expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
        expect(f.feed.eventRequests, hasLength(2));
        expect(f.provider.lastError, isNotNull);
        expect(f.store.writtenKeys, isEmpty);
        await f.expectRaw(original);
      }),
    );

    for (final canceled in [false, true]) {
      test(
        '${provider.name} malformed ${canceled ? "canceled" : "active"} event handling',
        () => f.withHttp(() async {
          final original = await f.seed(provider);
          f.feed.pagePayloads[1] = {
            _collectionKey(provider): [
              {
                'id': 'no-start',
                if (canceled)
                  if (provider == OAuthCalendarProvider.google)
                    'status': 'cancelled'
                  else
                    'isCancelled': true,
              },
            ],
          };
          expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
          expect(f.feed.eventRequests, hasLength(1));
          if (canceled) {
            expect(f.provider.lastError, isNull);
            await f.expectCommittedTitles(<String>[]);
          } else {
            expect(f.provider.lastError, isNotNull);
            expect(f.store.writtenKeys, isEmpty);
            await f.expectRaw(original);
          }
        }),
      );
    }

    if (provider == OAuthCalendarProvider.outlook) {
      test(
        'outlook foreign continuation never receives bearer token',
        () => f.withHttp(() async {
          final original = await f.seed(provider);
          f.feed.pagePayloads[1] = {
            'value': [_event(provider, 1)],
            '@odata.nextLink':
                'https://untrusted.invalid/v1.0/me/calendar/calendarView',
          };
          expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
          expect(f.feed.eventRequests, hasLength(1));
          expect(f.provider.lastError, isNotNull);
          expect(f.store.writtenKeys, isEmpty);
          await f.expectRaw(original);
        }),
      );
    }

    for (final tokenShape in ['error', 'missing access', 'negative expiry']) {
      test(
        '${provider.name} HTTP 200 $tokenShape cannot report a connected account',
        () => f.withHttp(() async {
          f.feed.selected = provider;
          f.feed.tokenPayload = _invalidToken(tokenShape);
          await f.savePending(provider);
          final result = await f.observe(f.connect(provider)).timeout(_wait);
          expect(result, _validationFailure);
          expect(f.feed.tokenRequests, hasLength(1));
          expect(
            f.feed.tokenRequests.single.bodyFields['grant_type'],
            'authorization_code',
          );
          expect(f.feed.eventRequests, isEmpty);
          expect(f.provider.oauthAccounts, isEmpty);
          expect(f.provider.allEvents(), isEmpty);
          await f.expectDispatchedAuthorizationOnly();
        }),
      );

      test(
        '${provider.name} HTTP 200 $tokenShape refresh keeps credentials and expiry',
        () => f.withHttp(() async {
          final original = await f.seed(provider, expired: true);
          final accountBefore = f.provider.oauthAccounts.single.toJson();
          f.feed.tokenPayload = _invalidToken(tokenShape);
          expect(await f.observe(f.provider.syncAll()).timeout(_wait), isNull);
          expect(f.feed.tokenRequests, hasLength(1));
          expect(
            f.feed.tokenRequests.single.bodyFields['grant_type'],
            'refresh_token',
          );
          expect(f.feed.eventRequests, isEmpty);
          expect(f.provider.lastError, isNotNull);
          expect(f.provider.isSyncing, isFalse);
          expect(f.provider.oauthAccounts.single.toJson(), accountBefore);
          expect(_titles(f.provider), [_oldTitle]);
          await f.expectDispatchedRefreshOnly(original);
          await f.expectRaw(original);
        }),
      );
    }

    test(
      '${provider.name} account revoke between pages stops subsequent HTTP and publication',
      () => f.withHttp(() async {
        final original = await f.seed(provider);
        f.feed.pageCount = 3;
        f.feed.holdPage = 2;
        final syncing = f.observe(f.provider.syncAll());
        await f.feed.heldPageStarted.future.timeout(_wait);
        expect(f.feed.eventRequests, hasLength(2));
        expect(_titles(f.provider), [_oldTitle]);
        expect(f.store.writtenKeys, isEmpty);
        await f.expectRaw(original);

        expect(
          await f
              .observe(AccountLocalDataCleaner.clearSharedPreferences())
              .timeout(_wait),
          isNull,
          reason: 'HTTP pagination must not hold the commit lane',
        );
        f.provider.resetLocalState();
        final writesAfterClear = f.store.writtenKeys.toList();
        var notifications = 0;
        f.provider.addListener(() => notifications++);

        f.feed.releaseHeldPage();
        expect(await syncing.timeout(_wait), isNull);
        expect(
          f.feed.eventRequests,
          hasLength(2),
          reason: 'page 3 is obsolete',
        );
        expect(f.store.writtenKeys, writesAfterClear);
        expect(await f.store.oauthDisk(), isEmpty);
        expect(f.provider.oauthAccounts, isEmpty);
        expect(f.provider.allEvents(), isEmpty);
        expect(f.provider.lastError, isNull);
        expect(f.provider.isSyncing, isFalse);
        expect(notifications, 0);
      }),
    );
  }
}

final _oldSync = DateTime.utc(2026, 10, 1);
final _validationFailure = allOf(
  isNotNull,
  isNot(isA<AccountPreferenceWriteCanceled>()),
);

String _collectionKey(OAuthCalendarProvider provider) =>
    provider == OAuthCalendarProvider.google ? 'items' : 'value';

Map<String, Object?> _malformedEnvelope(
  OAuthCalendarProvider provider,
  String shape,
) {
  final key = _collectionKey(provider);
  return switch (shape) {
    'null' => {key: null},
    'object' => {
      key: <String, Object?>{'id': 'not-a-list'},
    },
    'other provider' => {
      (provider == OAuthCalendarProvider.google ? 'value' : 'items'):
          <Object?>[],
    },
    _ => {'unexpected': <Object?>[]},
  };
}

Map<String, Object?> _invalidToken(String shape) => {
  if (shape == 'error') 'error': 'invalid_grant',
  if (shape != 'missing access') 'access_token': 'synthetic-new-access',
  'refresh_token': 'synthetic-new-refresh',
  'token_type': 'Bearer',
  'expires_in': shape == 'negative expiry' ? -1 : 3600,
};

List<String> _titles(CalendarSyncProvider provider) =>
    provider.allEvents().map((event) => event.title).toList();

OAuthCalendarAccount _account(
  OAuthCalendarProvider provider, {
  bool expired = false,
}) => OAuthCalendarAccount(
  id: 'existing',
  provider: provider,
  displayName: 'Confirmed ${provider.name} calendar',
  clientId: 'synthetic-client',
  redirectUri: 'duoyi://oauth/calendar',
  accessToken: 'synthetic-old-access',
  refreshToken: 'synthetic-old-refresh',
  expiresAt: DateTime.utc(expired ? 2000 : 2099),
  lastSyncedAt: _oldSync,
);

Map<String, Object?> _cachedEvent(OAuthCalendarProvider provider) => {
  'id': 'oauth_${provider.name}_existing_cached',
  'title': _oldTitle,
  'date': '2026-11-09T11:00:00.000Z',
  'endDate': '2026-11-09T12:00:00.000Z',
  'subtitle': null,
  'colorValue': 0xFF5E97F6,
  'sourceId': null,
  'timeHour': 11,
  'timeMinute': 0,
};

Map<String, Object?> _event(OAuthCalendarProvider provider, int page) => {
  'id': 'page-$page',
  if (provider == OAuthCalendarProvider.google)
    'summary': 'Page $page event'
  else
    'subject': 'Page $page event',
  'start': {
    'dateTime': '2026-11-09T11:00:00.000Z',
    if (provider == OAuthCalendarProvider.outlook) 'timeZone': 'UTC',
  },
  'end': {
    'dateTime': '2026-11-09T12:00:00.000Z',
    if (provider == OAuthCalendarProvider.outlook) 'timeZone': 'UTC',
  },
};

Uri _outlookNext(int page) => Uri.https(
  'graph.microsoft.com',
  '/v1.0/me/calendar/calendarView',
  {r'$skiptoken': 'page-$page'},
);

class _Fixture {
  _Fixture(this.previousStore, this.store, this.prefs) {
    provider = CalendarSyncProvider(authProvider: auth);
  }
  final SharedPreferencesStorePlatform previousStore;
  final _Store store;
  final SharedPreferences prefs;
  // This fixture owns the issuer; every Calendar provider borrows it.
  final AuthProvider auth = AuthProvider();
  late final AuthOAuthScopeLease lease;
  late final OAuthScopedOwnerRecord scope;
  final seedSources = <OAuthOwnedSourceRecord>[];
  late final String seedCacheRaw;
  OAuthOwnedPendingAuthorization? preparedAttempt;
  final createdAt = DateTime.now().toUtc();
  late final CalendarSyncProvider provider;
  final feed = _Feed();
  final pending = <Future<Object?>>[];

  static Future<_Fixture> create() async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    final prefs = await SharedPreferences.getInstance();
    await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
    expect(
      await prefs.setString(
        AccountLocalDataCleaner.accountDataOwnerKey,
        'id:fixture-oauth',
      ),
      isTrue,
    );
    expect(
      await prefs.setString(
        'auth_state',
        jsonEncode(const AuthState(
          userId: 'fixture-oauth',
          token: 'synthetic-fixture-auth-token',
        ).toJson()),
      ),
      isTrue,
    );
    final fixture = _Fixture(previous, store, prefs);
    await fixture.prepareScope();

    store.writtenKeys.clear();
    store.mutations.clear();
    return fixture;
  }

  Future<Object?> observe(Future<dynamic> future) {
    final result = future.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    pending.add(result);
    return result;
  }

  Future<void> withHttp(Future<void> Function() body) =>
      http.runWithClient(body, () => MockClient(feed.respond));

  Future<void> savePending(OAuthCalendarProvider selected) async {
    final snapshot = await provider.savePendingOAuthAuthorization(
      provider: selected,
      displayName: 'Synthetic new calendar',
      clientId: 'synthetic-client',
      clientSecret: '',
      redirectUri: 'duoyi://oauth/calendar',
      calendarId: 'primary',
      codeVerifier: _codeVerifier,
      state: 'synthetic-attempt-state',
    );
    final prepared = OAuthOwnedPendingAuthorization.create(
      scope: scope,
      attemptId: snapshot['attemptId']!,
      draft: {
        'provider': selected.name,
        'displayName': 'Synthetic new calendar',
        'clientId': 'synthetic-client',
        'clientSecret': '',
        'redirectUri': 'duoyi://oauth/calendar',
        'calendarId': 'primary',
        'codeVerifier': _codeVerifier,
        'state': 'synthetic-attempt-state',
      },
      savedAt: DateTime.parse(snapshot['savedAt']!),
    );
    expect(snapshot, {
      ...prepared.draft,
      'attemptId': prepared.attemptId,
      'savedAt': prepared.savedAt.toIso8601String(),
      'phase': 'prepared',
    });
    expect(prepared.canDispatchAt(DateTime.now()), isTrue);
    await expectRaw({_pendingKey: prepared.encode()});
    final parsed = OAuthOwnedPendingAuthorization.parse(
      prefs.getString(_pendingKey)!,
      scope: scope,
    );
    expect(parsed, isNotNull);
    expect(parsed!.encode(), prepared.encode());
    preparedAttempt = prepared;
  }

  Future<OAuthCalendarAccount> connect(OAuthCalendarProvider selected) =>
      provider.addOAuthAccountFromCode(
        provider: selected,
        displayName: 'Synthetic new calendar',
        clientId: 'synthetic-client',
        redirectUri: 'duoyi://oauth/calendar',
        authorizationCode: 'synthetic-single-use-code',
        codeVerifier: _codeVerifier,
        expectedAttemptId: preparedAttempt?.attemptId,
      );

  Future<Map<String, String>> seed(
    OAuthCalendarProvider selected, {
    bool expired = false,
  }) async {
    feed.selected = selected;
    expect(seedSources, isEmpty, reason: 'mint each seed source once');
    seedSources.add(OAuthOwnedSourceRecord.create(
      scope: scope,
      account: _account(selected, expired: expired).toJson(),
    ));
    seedCacheRaw = OAuthOwnedEventsRecord.create(
      source: seedSources.first,
      events: [_cachedEvent(selected)],
    ).encode();
    final raw = <String, String>{
      _accountsKey: jsonEncode(seedSources.map((row) => row.toJson()).toList()),
      _cacheKey: seedCacheRaw,
    };
    await installSeed(raw);
    await provider.loadFromStorage().timeout(_wait);
    expect(_titles(provider), [_oldTitle]);
    store.writtenKeys.clear();
    store.mutations.clear();
    return raw;
  }

  Future<void> prepareScope() async {
    expect(await store.oauthDisk(), isEmpty, reason: 'prepare an empty scope');
    expect(provider.isOAuthReady, isFalse);
    await auth.loadFromStorage(refreshServerConfig: false).timeout(_wait);
    expect(auth.state.userId, 'fixture-oauth');
    expect(auth.state.isLoggedIn, isTrue);
    expect(provider.isOAuthReady, isFalse);
    await provider.prepareOAuthScope(initialize: true).timeout(_wait);
    expect(provider.isOAuthReady, isTrue);
    lease = auth.captureOAuthScopeLease();
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
    // Parsed owner data is never substituted for the real issuer capability.
    scope = OAuthScopedOwnerRecord.parse(lease.workspace.rawRecord)!;
    expect(scope.scopeKind, 'account');
    expect(scope.matchesAccountOwner('id:fixture-oauth'), isTrue);
    expect(scope.encode(), lease.workspace.rawRecord);
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
    });
  }

  Future<void> installSeed(Map<String, String> raw) async {
    final epoch = OAuthCalendarStorage.epoch;
    await AccountPreferenceWrites.runResult<void>((token) {
      bool current() => token.isCurrent && auth.isOAuthScopeLeaseCurrent(lease);
      return OAuthCalendarStorage.run<void>(() async {
        await prefs.reload();
        token.ensureCurrent();
        OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
          lease.workspace,
          prefs,
        );
        if (!current()) throw const AccountPreferenceWriteCanceled();
        await OAuthCalendarStorage.commitLocked(
          prefs,
          raw,
          current,
          scopedWorkspace: lease.workspace,
          validateReadback: () {
            OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
              lease.workspace,
              prefs,
            );
            expect(sourceRecords(prefs.getString(_accountsKey)!)
                .map((row) => row.encode()), seedSources.map((row) => row.encode()));
            final cache = OAuthOwnedEventsRecord.parse(
              prefs.getString(_cacheKey)!,
              source: seedSources.first,
            );
            expect(cache, isNotNull);
            expect(cache!.encode(), seedCacheRaw);
          },
        );
      }, epoch: epoch, isCurrent: current);
    }, canceledResult: () => throw const AccountPreferenceWriteCanceled())
        .timeout(_wait);
    await expectRaw(raw);
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      for (final entry in raw.entries) 'flutter.${entry.key}': entry.value,
    });
    expect(auth.isOAuthScopeLeaseCurrent(lease), isTrue);
  }

  List<OAuthOwnedSourceRecord> sourceRecords(String raw) {
    final records = OAuthOwnedSourceRecord.parseList(raw, scope: scope);
    expect(records, isNotNull, reason: 'validate the original complete source list');
    return records!;
  }

  List<Map<String, dynamic>> accountRows(String raw) =>
      sourceRecords(raw).map((row) => Map<String, dynamic>.from(row.account)).toList();

  OAuthOwnedEventsRecord eventRecord(String raw, String accountsRaw) {
    final source = sourceRecords(accountsRaw)
        .singleWhere((row) => row.account['id'] == 'existing');
    final record = OAuthOwnedEventsRecord.parse(raw, source: source);
    expect(record, isNotNull, reason: 'cache is bound to the current owned source');
    return record!;
  }

  Future<void> expectOAuthDisk(Map<String, Object> expected) async {
    expect(await store.oauthDisk(), expected, reason: 'complete backing OAuth inventory');
    await prefs.reload();
    expect({
      for (final key in prefs.getKeys().where(OAuthCalendarStorage.isOAuthScopeKey))
        'flutter.$key': prefs.get(key)!,
    }, expected, reason: 'complete reloaded OAuth inventory');
  }

  OAuthOwnedPendingAuthorization expectedDispatchedAuthorization(String raw) {
    final actual = OAuthOwnedPendingAuthorization.parse(raw, scope: scope);
    expect(actual, isNotNull, reason: 'canonical owned dispatch claim');
    expect(actual!.phase, OAuthPendingPhase.dispatched);
    expect(preparedAttempt, isNotNull);
    final expected = preparedAttempt!.dispatched(
      fingerprint: sha256.convert(utf8.encode(jsonEncode([
        preparedAttempt!.draft['provider'],
        'synthetic-client',
        'duoyi://oauth/calendar',
        'synthetic-single-use-code',
      ]))).toString(),
      accountId: actual.sourceAccountId!,
    );
    // Only the product-generated source ID is observed; every other field is
    // fixed by the independently read prepared attempt and known request code.
    expect(actual.encode(), expected.encode());
    return expected;
  }

  Future<void> expectDispatchedAuthorizationOnly() async {
    final raw = (await store.getAll())['flutter.$_pendingKey'] as String;
    final expected = expectedDispatchedAuthorization(raw);
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      'flutter.$_pendingKey': expected.encode(),
    });
    expect(store.mutations, [
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': preparedAttempt!.encode()},
      {'kind': 'set', 'key': 'flutter.$_pendingKey', 'value': expected.encode()},
    ], reason: 'exact prepared then dispatched writes; no credential/cache writes');
    expect(store.writtenKeys, [
      'flutter.$_pendingKey', 'flutter.$_pendingKey',
    ]);
  }

  Future<void> expectDispatchedRefreshOnly(Map<String, String> original) async {
    final key = OAuthCalendarStorage.refreshJournalKey;
    final raw = (await store.getAll())['flutter.$key'] as String;
    final actual = OAuthOwnedRefreshJournal.parse(raw, scope: scope);
    expect(actual, isNotNull, reason: 'canonical owned refresh claim');
    expect(actual!.phase, OAuthRefreshPhase.dispatched);
    expect(actual.dispatchedAt.isBefore(createdAt), isFalse);
    expect(actual.dispatchedAt.isAfter(DateTime.now().toUtc()), isFalse);
    final expected = OAuthOwnedRefreshJournal.createDispatched(
      scope: scope,
      operationId: actual.operationId,
      receiptHandle: actual.receiptHandle,
      originalSource: seedSources.single,
      dispatchedAt: actual.dispatchedAt,
    );
    // Generated operation/receipt IDs and time are validated by the codec;
    // the entire original source and all remaining claim fields are pinned.
    expect(actual.encode(), expected.encode());
    await expectOAuthDisk({
      'flutter.${OAuthCalendarStorage.scopeOwnerKey}': lease.workspace.rawRecord,
      for (final entry in original.entries) 'flutter.${entry.key}': entry.value,
      'flutter.$key': expected.encode(),
    });
    expect(store.mutations, [
      {'kind': 'set', 'key': 'flutter.$key', 'value': expected.encode()},
    ], reason: 'one exact dispatched refresh; credentials/cache untouched');
    expect(store.writtenKeys, ['flutter.$key']);
  }

  Future<void> expectRaw(Map<String, String> raw) async {
    final disk = await store.getAll();
    for (final entry in raw.entries) {
      expect(
        disk['flutter.${entry.key}'],
        entry.value,
        reason: 'backing bytes',
      );
    }
    await prefs.reload();
    for (final entry in raw.entries) {
      expect(prefs.getString(entry.key), entry.value, reason: 'reloaded bytes');
    }
  }

  Future<void> expectCommittedTitles(List<String> titles) async {
    final disk = await store.getAll();
    final cached = eventRecord(
      disk['flutter.$_cacheKey'] as String, disk['flutter.$_accountsKey'] as String);
    expect(cached.events.map((row) => row['title']), titles);
    final accounts = accountRows(disk['flutter.$_accountsKey'] as String);
    final stamp = accounts.single['lastSyncedAt'] as String?;
    expect(stamp, isNotNull);
    expect(stamp, isNot(_oldSync.toIso8601String()));
    expect(
      provider.oauthAccounts.single.lastSyncedAt!.toIso8601String(),
      stamp,
    );
    await prefs.reload();
    expect(prefs.getString(_cacheKey), disk['flutter.$_cacheKey']);
    expect(prefs.getString(_accountsKey), disk['flutter.$_accountsKey']);
    expect(provider.lastError, isNull);
  }

  Future<void> close() async {
    feed.releaseHeldPage();
    try {
      await Future.wait(pending).timeout(_wait);
      await AccountPreferenceWrites.drain().timeout(_wait);
    } finally {
      provider.dispose();
      auth.dispose();
      try {
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      } finally {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        SharedPreferencesStorePlatform.instance = previousStore;
      }
    }
  }
}

class _Feed {
  OAuthCalendarProvider selected = OAuthCalendarProvider.google;
  int pageCount = 1;
  int? holdPage;
  Map<String, Object?>? tokenPayload;
  final pagePayloads = <int, Map<String, Object?>>{};
  final tokenRequests = <http.Request>[];
  final eventRequests = <http.Request>[];
  final heldPageStarted = Completer<void>();
  final _heldPageRelease = Completer<void>();

  void releaseHeldPage() {
    if (!_heldPageRelease.isCompleted) _heldPageRelease.complete();
  }

  void expectContinuation(int page) {
    final first = eventRequests.first;
    final next = eventRequests[page - 1];
    if (selected == OAuthCalendarProvider.google) {
      expect(next.url.queryParameters['pageToken'], 'page-$page');
      expect(next.url.path, first.url.path);
      for (final key in ['timeMin', 'timeMax', 'singleEvents', 'orderBy']) {
        expect(next.url.queryParameters[key], first.url.queryParameters[key]);
      }
    } else {
      expect(next.url, _outlookNext(page));
    }
    expect(next.headers['Authorization'], 'Bearer synthetic-old-access');
  }

  Future<http.Response> respond(http.Request request) async {
    if (request.method == 'POST') {
      expect(request.url, Uri.parse(selected.tokenEndpoint));
      tokenRequests.add(request);
      return _jsonResponse(
        tokenPayload ??
            {
              'access_token': 'synthetic-new-access',
              'refresh_token': 'synthetic-new-refresh',
              'expires_in': 3600,
              'token_type': 'Bearer',
            },
      );
    }
    expect(request.method, 'GET');
    expect(
      request.url.host,
      selected == OAuthCalendarProvider.google
          ? 'www.googleapis.com'
          : 'graph.microsoft.com',
    );
    eventRequests.add(request);
    final pageValue = selected == OAuthCalendarProvider.google
        ? request.url.queryParameters['pageToken']
        : request.url.queryParameters[r'$skiptoken'];
    final page = pageValue == null
        ? 1
        : int.parse(pageValue.replaceFirst('page-', ''));
    if (page == holdPage) {
      if (!heldPageStarted.isCompleted) heldPageStarted.complete();
      await _heldPageRelease.future;
    }
    final payload =
        pagePayloads[page] ??
        <String, Object?>{
          _collectionKey(selected): [_event(selected, page)],
          if (page < pageCount)
            if (selected == OAuthCalendarProvider.google)
              'nextPageToken': 'page-${page + 1}'
            else
              '@odata.nextLink': _outlookNext(page + 1).toString(),
        };
    return _jsonResponse(payload);
  }
}

http.Response _jsonResponse(Map<String, Object?> payload) => http.Response(
  jsonEncode(payload),
  200,
  headers: const {'content-type': 'application/json'},
);

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});
  final writtenKeys = <String>[];
  final mutations = <Map<String, Object?>>[];

  @override
  Future<bool> setValue(String type, String key, Object value) {
    writtenKeys.add(key);
    mutations.add({'kind': 'set', 'key': key, 'value': value});
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations.add({'kind': 'remove', 'key': key, 'value': null});
    return super.remove(key);
  }

  Future<Map<String, Object>> oauthDisk() async => {
    for (final entry in (await getAll()).entries)
      if (entry.key.startsWith('flutter.duoyi_oauth_calendar_'))
        entry.key: entry.value,
  };
}
