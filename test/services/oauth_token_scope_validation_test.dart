// Prepared461 from frozen458 public client API and the supplied scope contract.
// No Auth/store authority, formatter, compiler, or test execution.

import 'dart:convert';

import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _wrongScopes = <Object?>[
  null,
  461,
  461.5,
  true,
  ['Calendars.Read'],
  {'scope': 'Calendars.Read'},
];
const _blankScopes = ['', '   ', '\t\r\n'];
const _access = 'synthetic-scope461-response-access';
const _refresh = 'synthetic-scope461-response-refresh';

void main() {
  test('OTS461-01 code omitted scope uses each provider default', () async {
    for (final provider in OAuthCalendarProvider.values) {
      final f = _Fixture(provider);
      final result = await f.exchange(_token());
      _expectAccepted(f, result, provider.defaultScope, refreshing: false);
    }
  });

  test(
    'OTS461-02 refresh omitted scope preserves original custom scope',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        final f = _Fixture(provider);
        expect(f.original.scope, isNot(provider.defaultScope));
        final result = await f.refresh(_token());
        _expectAccepted(f, result, f.original.scope, refreshing: true);
      }
    },
  );

  test(
    'OTS461-03 code valid scope string preserves exact response text',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        for (final scope in _validScopes(provider)) {
          final f = _Fixture(provider);
          final result = await f.exchange(_token(hasScope: true, scope: scope));
          _expectAccepted(f, result, scope, refreshing: false);
        }
      }
    },
  );

  test(
    'OTS461-04 refresh valid scope string preserves exact text and original metadata',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        for (final scope in _validScopes(provider)) {
          final f = _Fixture(provider);
          final result = await f.refresh(_token(hasScope: true, scope: scope));
          _expectAccepted(f, result, scope, refreshing: true);
        }
      }
    },
  );

  test(
    'OTS461-05 code rejects present null and nonstring scope values',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        for (final scope in _wrongScopes) {
          final f = _Fixture(provider);
          await expectLater(
            f.exchange(_token(hasScope: true, scope: scope)),
            throwsA(isA<FormatException>()),
            reason: '${provider.name}: present ${scope.runtimeType} scope',
          );
        }
      }
    },
  );

  test(
    'OTS461-06 refresh rejects present null and nonstring scope values without mutating original',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        for (final scope in _wrongScopes) {
          final f = _Fixture(provider);
          await expectLater(
            f.refresh(_token(hasScope: true, scope: scope)),
            throwsA(isA<FormatException>()),
            reason: '${provider.name}: present ${scope.runtimeType} scope',
          );
        }
      }
    },
  );

  test(
    'OTS461-07 code rejects empty and whitespace-only scope strings',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        for (final scope in _blankScopes) {
          final f = _Fixture(provider);
          await expectLater(
            f.exchange(_token(hasScope: true, scope: scope)),
            throwsA(isA<FormatException>()),
            reason: '${provider.name}: blank scope ${jsonEncode(scope)}',
          );
        }
      }
    },
  );

  test(
    'OTS461-08 refresh rejects empty and whitespace-only scope without mutating original',
    () async {
      for (final provider in OAuthCalendarProvider.values) {
        for (final scope in _blankScopes) {
          final f = _Fixture(provider);
          await expectLater(
            f.refresh(_token(hasScope: true, scope: scope)),
            throwsA(isA<FormatException>()),
            reason: '${provider.name}: blank scope ${jsonEncode(scope)}',
          );
        }
      }
    },
  );
}

List<String> _validScopes(OAuthCalendarProvider provider) => [
  provider.defaultScope,
  '  ${provider.defaultScope}\t ',
  '${provider.defaultScope}  extra.scope461',
];

Map<String, Object?> _token({bool hasScope = false, Object? scope}) => {
  'access_token': _access,
  'refresh_token': _refresh,
  'expires_in': 7200,
  'token_type': 'Bearer',
  if (hasScope) 'scope': scope,
};

class _Fixture {
  _Fixture(OAuthCalendarProvider provider)
    : original = OAuthCalendarAccount(
        id: 'scope461-${provider.name}-source',
        provider: provider,
        displayName: 'Scope461 ${provider.name} original name',
        clientId: 'synthetic-scope461-${provider.name}-client',
        clientSecret: '  synthetic-scope461-secret  ',
        redirectUri: 'duoyi://oauth/calendar',
        calendarId: 'scope461-${provider.name}-calendar',
        accessToken: 'synthetic-scope461-original-access',
        refreshToken: 'synthetic-scope461-original-refresh',
        expiresAt: DateTime.utc(2020, 1, 2, 3, 4, 5),
        scope: '${provider.defaultScope} original.scope461',
        colorValue: 0xFF13579B,
        enabled: false,
        lastSyncedAt: DateTime.utc(2026, 11, 10, 11, 12, 13),
      ) {
    originalJson = Map<String, dynamic>.unmodifiable(original.toJson());
  }

  final OAuthCalendarAccount original;
  late final Map<String, dynamic> originalJson;
  final verifier = OAuthCalendarClient.generateCodeVerifier();

  Future<OAuthCalendarAccount> exchange(Map<String, Object?> response) =>
      _invoke(response, refreshing: false);

  Future<OAuthCalendarAccount> refresh(Map<String, Object?> response) =>
      _invoke(response, refreshing: true);

  Future<OAuthCalendarAccount> _invoke(
    Map<String, Object?> response, {
    required bool refreshing,
  }) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.url, Uri.parse(original.provider.tokenEndpoint));
      expect(Uri.splitQueryString(request.body), {
        'client_id': original.clientId,
        'client_secret': original.clientSecret.trim(),
        if (refreshing) ...{
          'grant_type': 'refresh_token',
          'refresh_token': original.refreshToken,
        } else ...{
          'redirect_uri': original.redirectUri,
          'grant_type': 'authorization_code',
          'code': 'synthetic-scope461-code',
          'code_verifier': verifier,
        },
      });
      return http.Response(
        jsonEncode(response),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    try {
      if (refreshing) {
        return await OAuthCalendarClient.refreshAccessToken(
          original,
          client: client,
        );
      }
      return await OAuthCalendarClient.exchangeAuthorizationCode(
        provider: original.provider,
        displayName: original.displayName,
        clientId: original.clientId,
        clientSecret: original.clientSecret,
        redirectUri: original.redirectUri,
        calendarId: original.calendarId,
        colorValue: original.colorValue,
        accountId: original.id,
        authorizationInput: OAuthAuthorizationInput.manualCode(
          'synthetic-scope461-code',
        ),
        codeVerifier: verifier,
        client: client,
      );
    } finally {
      client.close();
      expect(calls, 1, reason: 'Exactly one actual token POST; no retry');
      expect(
        original.toJson(),
        originalJson,
        reason: 'Success and rejection preserve every original account field',
      );
    }
  }
}

void _expectAccepted(
  _Fixture f,
  OAuthCalendarAccount result,
  String scope, {
  required bool refreshing,
}) {
  expect(result, isNot(same(f.original)));
  expect(result.scope, scope);
  expect(result.accessToken, _access);
  expect(result.refreshToken, _refresh);
  final actual = result.toJson();
  final keys = refreshing
      ? f.originalJson.keys.where(
          (key) => !{
            'accessToken',
            'refreshToken',
            'expiresAt',
            'scope',
          }.contains(key),
        )
      : const [
          'id',
          'provider',
          'displayName',
          'clientId',
          'clientSecret',
          'redirectUri',
          'calendarId',
          'colorValue',
        ];
  for (final key in keys) {
    expect(
      actual[key],
      f.originalJson[key],
      reason: '${f.original.provider.name}: unchanged metadata $key',
    );
  }
}
