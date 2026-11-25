// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_inventory.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const _wait = Duration(seconds: 5);
const _redirect = 'https://calendar.example/oauth/calendar';
const _state = 'synthetic-state@102';
const _callback = '$_redirect?code=synthetic-code&state=synthetic-state%40102';
const _encodedCallback =
    '$_redirect?code=opaque%252F%2Fpart%40mail%2Bplus%25tail&state=synthetic-state%40102';
const _decodedCode = 'opaque%2F/part@mail+plus%tail';
const _clientId = 'synthetic-input-client';
const _verifier =
    'synthetic-input-verifier-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _accountsKey = 'duoyi_oauth_calendar_accounts_v1';
const _existingCacheKey = 'duoyi_oauth_calendar_events_existing';
const _pendingKey = 'duoyi_oauth_calendar_pending_authorization_v1';
// All positive backing rows use the public owned codecs.

enum _EntryPoint { client, provider }

const _rejected = <_RejectedInput>[
  _RejectedInput(
    'wrong callback state',
    OAuthAuthorizationInputFailure.stateMismatch,
    input: OAuthAuthorizationInput.callback(
      '$_redirect?code=synthetic-code&state=wrong-state',
    ),
  ),
  _RejectedInput(
    'duplicate callback state',
    OAuthAuthorizationInputFailure.stateMismatch,
    input: OAuthAuthorizationInput.callback(
      '$_callback&state=synthetic-state%40102',
    ),
  ),
  _RejectedInput(
    'callback without expected state',
    OAuthAuthorizationInputFailure.stateMismatch,
    input: OAuthAuthorizationInput.callback(_callback),
    expectedState: null,
  ),
  _RejectedInput(
    'callback redirect mismatch',
    OAuthAuthorizationInputFailure.redirectMismatch,
    input: OAuthAuthorizationInput.callback(
      'https://other.example/oauth/calendar?code=synthetic-code&state=synthetic-state%40102',
    ),
  ),
  _RejectedInput(
    'duplicate callback code',
    OAuthAuthorizationInputFailure.malformedCode,
    input: OAuthAuthorizationInput.callback('$_callback&code=synthetic-code'),
  ),
  _RejectedInput(
    'raw malformed percent in callback code',
    OAuthAuthorizationInputFailure.malformedCallback,
    input: OAuthAuthorizationInput.callback(
      '$_redirect?code=synthetic%2&state=synthetic-state%40102',
    ),
  ),
  _RejectedInput(
    'raw malformed percent in callback state',
    OAuthAuthorizationInputFailure.malformedCallback,
    input: OAuthAuthorizationInput.callback(
      '$_redirect?code=synthetic-code&state=synthetic-state%',
    ),
  ),
  _RejectedInput(
    'raw malformed percent in registered redirect',
    OAuthAuthorizationInputFailure.malformedCallback,
    input: OAuthAuthorizationInput.callback(_callback),
    redirectUri: '$_redirect%2',
  ),
  _RejectedInput(
    'manual callback URI is not auto extracted',
    OAuthAuthorizationInputFailure.malformedCode,
    input: OAuthAuthorizationInput.manualCode(_callback),
  ),
  _RejectedInput(
    'legacy callback URI is not auto extracted',
    OAuthAuthorizationInputFailure.malformedCode,
    raw: _callback,
  ),
  _RejectedInput(
    'raw code plus explicit callback is ambiguous',
    OAuthAuthorizationInputFailure.malformedCode,
    raw: 'synthetic-raw-code',
    input: OAuthAuthorizationInput.callback(_callback),
  ),
  _RejectedInput(
    'whitespace raw code plus explicit manual code is ambiguous',
    OAuthAuthorizationInputFailure.malformedCode,
    raw: ' \t ',
    input: OAuthAuthorizationInput.manualCode('synthetic-code'),
  ),
];

const _accepted = <_AcceptedInput>[
  _AcceptedInput(
    'explicit callback decodes code exactly once',
    _decodedCode,
    input: OAuthAuthorizationInput.callback(_encodedCallback),
  ),
  _AcceptedInput(
    'explicit manual slash at sign and percent code remains opaque',
    _decodedCode,
    input: OAuthAuthorizationInput.manualCode(' \t$_decodedCode\n '),
    expectedState: null,
  ),
  _AcceptedInput(
    'legacy raw slash at sign and percent code remains supported',
    'legacy/%2F@code%tail',
    raw: '  legacy/%2F@code%tail  ',
    expectedState: null,
  ),
];

// Real public client/provider entry points, actual form encoding, and the
// official plugin backing store. Only HTTP responses and platform accounting
// are injected. Provider vectors also use a genuine issuer and saved draft.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final selected in OAuthCalendarProvider.values) {
    group('OID102-${selected.name}', () {
      late _Fixture f;
      _Fixture? created;
      setUp(() async {
        created = null;
        f = await _Fixture.create(selected);
        created = f;
      });
      tearDown(() async {
        await created?.close();
      });

      for (final entryPoint in _EntryPoint.values) {
        for (final vector in _rejected) {
          test(
            '${entryPoint.name} rejects ${vector.name} before dispatch',
            () async {
              final reads = f.store.reads;
              await expectLater(
                f.exchange(entryPoint, vector).timeout(_wait),
                throwsA(
                  isA<OAuthAuthorizationInputException>().having(
                    (error) => error.reason,
                    'reason',
                    vector.reason,
                  ),
                ),
              );
              expect(f.feed.requests, isEmpty);
              expect(f.store.writtenKeys, isEmpty);
              expect(f.store.removedKeys, isEmpty);
              expect(
                f.store.reads,
                reads,
                reason: 'Reject before storage admission',
              );
              expect(f.notifications, 0);
              expect(
                f.provider.oauthAccounts.map((row) => row.toJson()).toList(),
                <Object>[f.existing.toJson()],
              );
              expect(
                f.provider.allEvents().map((event) => event.title).toList(),
                <String>['Existing event'],
              );
              await f.expectUnchangedBackingAndCache();
              f.expectSameBoundary();
            },
          );
        }

        for (final vector in _accepted) {
          test('${entryPoint.name} ${vector.name}', () async {
            final account = await f.exchange(entryPoint, vector).timeout(_wait);
            f.feed.expectOneToken(vector.expectedCode);
            expect(account.provider, selected);
            expect(account.clientId, _clientId);
            expect(account.redirectUri, _redirect);
            expect(account.accessToken, 'synthetic-input-access');
            expect(account.refreshToken, 'synthetic-input-refresh');
            if (entryPoint == _EntryPoint.client) {
              expect(f.feed.requests, hasLength(1));
              expect(f.store.writtenKeys, isEmpty);
              expect(f.store.removedKeys, isEmpty);
              await f.expectUnchangedBackingAndCache();
            } else {
              await f.expectProviderCommit(account);
            }
            f.expectSameBoundary();
          });
        }
      }

      test(
        'provider callback and manual aliases dispatch one resolved code once',
        () async {
          final account = await f
              .exchange(_EntryPoint.provider, _accepted.first)
              .timeout(_wait);
          await f.expectProviderCommit(account);
          f.feed.expectOneToken(_decodedCode);
          // A new public prepared attempt must still reject an alias of the
          // already dispatched code within this same scope incarnation.
          await f.prepareAttempt();
          final backing = await f.store.getAll();
          final writes = List<String>.of(f.store.writtenKeys);
          final removals = List<String>.of(f.store.removedKeys);
          final requests = f.feed.requests.length;
          final notifications = f.notifications;

          await expectLater(
            f.exchange(_EntryPoint.provider, _accepted[1]).timeout(_wait),
            throwsA(isA<StateError>()),
          );
          f.feed.expectOneToken(_decodedCode);
          expect(f.feed.requests, hasLength(requests));
          expect(f.store.writtenKeys, writes);
          expect(f.store.removedKeys, removals);
          expect(f.notifications, notifications);
          expect(await f.store.getAll(), backing);
          await f.preferences.reload();
          expect(_cache(f.preferences), _unprefixed(backing));
          expect(f.provider.oauthAccounts, hasLength(2));
          f.expectSameBoundary();
        },
      );
    });
  }
}

class _Input {
  const _Input({
    this.raw = '',
    this.input,
    this.redirectUri = _redirect,
    this.expectedState = _state,
  });

  final String raw;
  final OAuthAuthorizationInput? input;
  final String redirectUri;
  final String? expectedState;
}

class _RejectedInput extends _Input {
  const _RejectedInput(
    this.name,
    this.reason, {
    super.raw,
    super.input,
    super.redirectUri,
    super.expectedState,
  });

  final String name;
  final OAuthAuthorizationInputFailure reason;
}

class _AcceptedInput extends _Input {
  const _AcceptedInput(
    this.name,
    this.expectedCode, {
    super.raw,
    super.input,
    super.expectedState,
  });

  final String name;
  final String expectedCode;
}

class _Fixture {
  _Fixture(this.previousStore, this.store, this.preferences, this.selected) {
    feed = _Feed(selected);
    client = MockClient(feed.respond);
    auth = AuthProvider(
      client: ApiClient(baseUrl: 'https://duoyi.test', httpClient: client),
    );
    provider = CalendarSyncProvider(
      oauthHttpClient: client,
      authProvider: auth,
    );
    existing = OAuthCalendarAccount(
      id: 'existing',
      provider: selected,
      displayName: 'Existing calendar',
      clientId: 'synthetic-existing-client',
      redirectUri: _redirect,
      accessToken: 'synthetic-existing-access',
      refreshToken: 'synthetic-existing-refresh',
      expiresAt: DateTime.utc(2099),
      lastSyncedAt: DateTime.utc(2026, 11, 9),
    );
  }

  final SharedPreferencesStorePlatform previousStore;
  final _Store store;
  final SharedPreferences preferences;
  final OAuthCalendarProvider selected;
  late final _Feed feed;
  late final http.Client client;
  late final CalendarSyncProvider provider;
  late final AuthProvider auth;
  late final AuthOAuthScopeLease lease;
  late final OAuthScopedOwnerRecord scope;
  late final OAuthOwnedSourceRecord existingSource;
  late final OAuthCalendarAccount existing;
  late final Map<String, Object> before;
  late final int accountGeneration;
  late final int writesGeneration;
  late final int oauthEpoch;
  late final int resetRevision;
  int notifications = 0;

  static Future<_Fixture> create(OAuthCalendarProvider selected) async {
    await AccountPreferenceWrites.drain().timeout(_wait);
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    _Fixture? created;
    try {
      final preferences = await SharedPreferences.getInstance();
      await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      final f = _Fixture(previous, store, preferences, selected);
      created = f;
      expect(f.auth.isGuestWorkspaceReady, isFalse);
      await http.runWithClient(
        () => f.auth.loadFromStorage(refreshServerConfig: false),
        () => f.client,
      ).timeout(_wait);
      expect(f.auth.isGuestWorkspaceReady, isTrue);
      expect(f.provider.isOAuthReady, isFalse);
      await f.auth.initializeOAuthScope().timeout(_wait);
      f.lease = f.auth.captureOAuthScopeLease();
      expect(f.auth.isOAuthScopeLeaseCurrent(f.lease), isTrue);
      f.scope = OAuthScopedOwnerRecord.parse(f.lease.workspace.rawRecord)!;
      expect(f.scope.scopeKind, 'guest');
      f.existingSource = OAuthOwnedSourceRecord.create(
        scope: f.scope,
        account: f.existing.toJson(),
      );
      final cache = OAuthOwnedEventsRecord.create(
        source: f.existingSource,
        events: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cached',
            'title': 'Existing event',
            'date': DateTime.utc(2026, 11, 10, 12).toIso8601String(),
            'endDate': null,
            'subtitle': null,
            'colorValue': f.existing.colorValue,
            'sourceId': f.existing.id,
            'timeHour': null,
            'timeMinute': null,
          },
        ],
      );
      // Preserve the original unrelated StringList control through the public
      // generic preference writer; the OAuth commit accepts only String/null.
      expect(
        await AccountPreferenceTransaction.writeValue(
          preferences,
          'duoyi_notes',
          <String>['Unrelated saved note'],
        ),
        isTrue,
      );
      await AccountPreferenceWrites.runResult<void>((token) {
        bool current() =>
            token.isCurrent && f.auth.isOAuthScopeLeaseCurrent(f.lease);
        return OAuthCalendarStorage.run<void>(() async {
          await preferences.reload();
          token.ensureCurrent();
          OAuthCalendarStorage.ensureScopedWorkspaceCurrentLocked(
            f.lease.workspace, preferences,
          );
          await OAuthCalendarStorage.commitLocked(
            preferences,
            <String, Object?>{
              _accountsKey: jsonEncode([f.existingSource.toJson()]),
              _existingCacheKey: cache.encode(),
            },
            current,
            scopedWorkspace: f.lease.workspace,
            validateReadback: () =>
                OAuthCalendarInventory.validate(preferences, f.scope),
          );
        }, epoch: OAuthCalendarStorage.epoch, isCurrent: current);
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled())
          .timeout(_wait);
      await f.auth.restoreOAuthScope().timeout(_wait);
      expect(f.provider.isOAuthReady, isTrue);
      await f.provider.prepareOAuthScope().timeout(_wait);
      await f.provider.loadFromStorage().timeout(_wait);
      expect(f.provider.oauthAccounts, hasLength(1));
      expect(f.provider.allEvents().single.title, 'Existing event');
      await f.prepareAttempt();
      f.feed.readPendingClaim = () async =>
          (await store.backing())['flutter.$_pendingKey'] as String?;
      f.feed.scope = f.scope;
      f.before = await store.getAll();
      f.accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      f.writesGeneration = AccountPreferenceWrites.generation;
      f.oauthEpoch = OAuthCalendarStorage.epoch;
      f.resetRevision = OAuthCalendarStorage.resetRevision;
      store.writtenKeys.clear();
      store.removedKeys.clear();
      expect(f.feed.requests, isEmpty);
      f.provider.addListener(() => f.notifications++);
      return f;
    } catch (_) {
      if (created != null) {
        await created.close();
      } else {
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = previous;
      }
      rethrow;
    }
  }

  Future<void> prepareAttempt() async {
    final draft = await provider.savePendingOAuthAuthorization(
      provider: selected,
      displayName: 'Input calendar',
      clientId: _clientId,
      clientSecret: '',
      redirectUri: _redirect,
      calendarId: 'primary',
      codeVerifier: _verifier,
      state: _state,
    ).timeout(_wait);
    final pending = OAuthOwnedPendingAuthorization.parse(
      (await store.backing())['flutter.$_pendingKey'] as String,
      scope: scope,
    );
    expect(pending, isNotNull);
    expect(pending!.attemptId, draft['attemptId']);
    expect(pending.phase, OAuthPendingPhase.prepared);
    expect(pending.canDispatchAt(DateTime.now()), isTrue);
  }

  Future<OAuthCalendarAccount> exchange(_EntryPoint entryPoint, _Input value) {
    feed.requiresOwnedClaim = entryPoint == _EntryPoint.provider;
    if (entryPoint == _EntryPoint.client) {
      return OAuthCalendarClient.exchangeAuthorizationCode(
        provider: selected,
        displayName: 'Input calendar',
        clientId: _clientId,
        redirectUri: value.redirectUri,
        authorizationCode: value.raw,
        authorizationInput: value.input,
        expectedState: value.expectedState,
        codeVerifier: _verifier,
        client: client,
        accountId: 'synthetic-client-result',
      );
    }
    return provider.addOAuthAccountFromCode(
      provider: selected,
      displayName: 'Input calendar',
      clientId: _clientId,
      redirectUri: value.redirectUri,
      authorizationCode: value.raw,
      authorizationInput: value.input,
      expectedState: value.expectedState,
      codeVerifier: _verifier,
    );
  }

  void expectSameBoundary() {
    expect(AccountLocalDataCleaner.accountDataGeneration, accountGeneration);
    expect(AccountPreferenceWrites.generation, writesGeneration);
    expect(OAuthCalendarStorage.epoch, oauthEpoch);
    expect(OAuthCalendarStorage.resetRevision, resetRevision);
  }

  Future<void> expectUnchangedBackingAndCache() async {
    expect(await store.getAll(), before, reason: 'Actual plugin backing bytes');
    expect(_cache(preferences), _unprefixed(before), reason: 'Existing cache');
    await preferences.reload();
    expect(_cache(preferences), _unprefixed(before), reason: 'Reloaded cache');
  }

  Future<void> expectProviderCommit(OAuthCalendarAccount account) async {
    expect(provider.lastError, isNull);
    expect(feed.eventRequests, hasLength(1));
    expect(feed.requests, hasLength(2));
    expect(provider.oauthAccounts, hasLength(2));
    expect(provider.oauthAccounts.last.toJson(), account.toJson());
    expect(account.lastSyncedAt, isNotNull);
    final backing = await store.getAll();
    final rows = OAuthOwnedSourceRecord.parseList(
      backing['flutter.$_accountsKey'] as String, scope: scope,
    );
    expect(rows, hasLength(2));
    expect(rows!.first.encode(), existingSource.encode());
    expect(rows.last.account, account.toJson());
    expect(rows.last.scopedOwner, scope.scopedOwner);
    expect(rows.last.oauthIncarnation, scope.oauthIncarnation);
    expect(rows.last.sourceIncarnation, isNot(existingSource.sourceIncarnation));
    final events = OAuthOwnedEventsRecord.parse(
      backing['flutter.duoyi_oauth_calendar_events_${account.id}'] as String,
      source: rows.last,
    );
    expect(events, isNotNull);
    expect(events!.events, isEmpty);
    expect(backing.containsKey('flutter.$_pendingKey'), isFalse);
    expect(feed.claims, hasLength(1));
    expect(feed.claims.single.sourceAccountId, account.id);
    for (final entry in before.entries) {
      if (entry.key != 'flutter.$_accountsKey' &&
          entry.key != 'flutter.$_pendingKey') {
        expect(backing[entry.key], entry.value);
      }
    }
    expect(store.removedKeys, <String>['flutter.$_pendingKey']);
    expect(
      store.writtenKeys.toSet(),
      <String>{
        'flutter.$_pendingKey',
        'flutter.$_accountsKey',
        'flutter.duoyi_oauth_calendar_events_${account.id}',
      },
    );
    await preferences.reload();
    OAuthCalendarInventory.validate(preferences, scope);
    expect(_cache(preferences), _unprefixed(backing));
  }

  Future<void> close() async {
    try {
      await AccountPreferenceWrites.drain().timeout(_wait);
    } finally {
      provider.dispose();
      auth.dispose();
      client.close();
      try {
        await AccountLocalDataCleaner.clearSharedPreferences().timeout(_wait);
      } finally {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        SharedPreferencesStorePlatform.instance = previousStore;
      }
    }
  }
}

Map<String, Object?> _cache(SharedPreferences preferences) => <String, Object?>{
  for (final key in preferences.getKeys()) key: preferences.get(key),
};

Map<String, Object> _unprefixed(Map<String, Object> backing) =>
    <String, Object>{
      for (final entry in backing.entries)
        entry.key.substring('flutter.'.length): entry.value,
    };

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.empty();

  final writtenKeys = <String>[];
  final removedKeys = <String>[];
  int reads = 0;
  Future<Map<String, Object>> backing() => super.getAll();

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) {
    reads++;
    return super.getAllWithParameters(parameters);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writtenKeys.add(key);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    removedKeys.add(key);
    return super.remove(key);
  }
}

class _Feed {
  _Feed(this.selected);

  final OAuthCalendarProvider selected;
  final requests = <http.Request>[];
  final tokenRequests = <http.Request>[];
  final eventRequests = <http.Request>[];
  final claims = <OAuthOwnedPendingAuthorization>[];
  bool requiresOwnedClaim = false;
  Future<String?> Function()? readPendingClaim;
  OAuthScopedOwnerRecord? scope;

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    if (request.method == 'POST') {
      expect(request.url, Uri.parse(selected.tokenEndpoint));
      tokenRequests.add(request);
      if (requiresOwnedClaim) {
        final raw = await readPendingClaim!();
        expect(raw, isNotNull, reason: 'Durable claim exists before HTTP');
        final claim = OAuthOwnedPendingAuthorization.parse(raw!, scope: scope!);
        expect(claim, isNotNull);
        expect(claim!.phase, OAuthPendingPhase.dispatched);
        expect(claim.codeFingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
        claims.add(claim);
      }
      return _jsonResponse(<String, Object>{
        'access_token': 'synthetic-input-access',
        'refresh_token': 'synthetic-input-refresh',
        'expires_in': 3600,
        'token_type': 'Bearer',
      });
    }
    expect(request.method, 'GET');
    expect(
      request.url.host,
      selected == OAuthCalendarProvider.google
          ? 'www.googleapis.com'
          : 'graph.microsoft.com',
    );
    expect(request.headers['Authorization'], 'Bearer synthetic-input-access');
    eventRequests.add(request);
    return _jsonResponse(<String, Object>{
      selected == OAuthCalendarProvider.google ? 'items' : 'value': <Object>[],
    });
  }

  void expectOneToken(String expectedCode) {
    expect(tokenRequests, hasLength(1));
    final request = tokenRequests.single;
    expect(request.method, 'POST');
    expect(request.url, Uri.parse(selected.tokenEndpoint));
    expect(
      request.headers['content-type'],
      startsWith('application/x-www-form-urlencoded'),
    );
    final form = Uri.splitQueryString(request.body);
    expect(form, <String, String>{
      'client_id': _clientId,
      'redirect_uri': _redirect,
      'grant_type': 'authorization_code',
      'code': expectedCode,
      'code_verifier': _verifier,
    });
    expect(
      Uri(query: request.body).queryParametersAll['code'],
      <String>[expectedCode],
      reason: 'Exactly one decoded form code field',
    );
    expect(request.body, isNot(contains('state=')));
  }
}

http.Response _jsonResponse(Map<String, Object> payload) => http.Response(
  jsonEncode(payload),
  200,
  headers: const <String, String>{'Content-Type': 'application/json'},
);
