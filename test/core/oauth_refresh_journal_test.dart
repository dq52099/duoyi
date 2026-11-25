import 'dart:convert';

import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_refresh_journal.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure, synthetic codec data. No Auth issuer, preferences, HTTP, or runtime.
// Prepared for418 against411's API without reading the active new codec.
const _owner = 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _incarnation = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const _sourceIncarnation = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const _maximumRevision = 9007199254740991;
const _stringLimit = 16384;
const _sourceLimit = 131072;
const _rawLimit = 262144;
final _operation = _repeat('O', 64);
final _handle = _repeat('H', 64);
final _dispatchAt = DateTime.utc(2026, 11, 12, 12);
final _receivedAt = DateTime.utc(2026, 11, 12, 12, 1);

String _repeat(String value, int count) => List.filled(count, value).join();
int _bytes(String value) => utf8.encode(value).length;
Matcher get _rejected => throwsA(isA<OAuthWorkspaceCodecException>());

OAuthScopedOwnerRecord _scope({
  String owner = _owner,
  String incarnation = _incarnation,
}) => OAuthScopedOwnerRecord.parse(
  jsonEncode({
    'schema': 1,
    'scopeKind': 'guest',
    'scopedOwner': owner,
    'oauthIncarnation': incarnation,
  }),
)!;

Map<String, Object?> _account() => {
  'id': 'calendar418',
  'provider': 'google',
  'displayName': 'Codec418 calendar',
  'clientId': 'synthetic-client418',
  'clientSecret': 'synthetic-secret418',
  'redirectUri': 'duoyi://oauth/callback',
  'calendarId': 'primary',
  'accessToken': 'synthetic-access418',
  'refreshToken': 'synthetic-refresh418',
  'expiresAt': '2026-11-12T11:00:00.000Z',
  'scope': 'calendar.readonly',
  'colorValue': 0xff336699,
  'enabled': true,
  'lastSyncedAt': null,
};

Map<String, Object?> _sourceJson({
  Map<String, Object?>? accountChanges,
  int credentialRevision = 1,
  int metadataRevision = 1,
}) => {
  'schema': 2,
  'scopedOwner': _owner,
  'oauthIncarnation': _incarnation,
  'sourceIncarnation': _sourceIncarnation,
  'metadataRevision': metadataRevision,
  'credentialRevision': credentialRevision,
  'account': {..._account(), ...?accountChanges},
};

OAuthOwnedSourceRecord _source({
  Map<String, Object?>? accountChanges,
  int credentialRevision = 1,
}) => _parseSource(
  _sourceJson(
    accountChanges: accountChanges,
    credentialRevision: credentialRevision,
  ),
);

OAuthOwnedSourceRecord _parseSource(Map<String, Object?> value) {
  final result = OAuthOwnedSourceRecord.parse(
    jsonEncode(value),
    scope: _scope(),
  );
  expect(
    result,
    isNotNull,
    reason: 'The standalone source fixture must be valid',
  );
  return result!;
}

Map<String, Object?> _sourceCopy(OAuthOwnedSourceRecord source) => {
  'schema': 2,
  'scopedOwner': source.scopedOwner,
  'oauthIncarnation': source.oauthIncarnation,
  'sourceIncarnation': source.sourceIncarnation,
  'metadataRevision': source.metadataRevision,
  'credentialRevision': source.credentialRevision,
  'account': Map<String, Object?>.of(source.account),
};

OAuthOwnedSourceRecord _changedSource(
  OAuthOwnedSourceRecord original, {
  Map<String, Object?>? accountChanges,
  Map<String, Object?>? envelopeChanges,
}) {
  final value = _sourceCopy(original);
  (value['account']! as Map<String, Object?>).addAll(accountChanges ?? {});
  value.addAll(envelopeChanges ?? {});
  return _parseSource(value);
}

OAuthOwnedSourceRecord _rotated(OAuthOwnedSourceRecord original) =>
    _changedSource(
      original,
      accountChanges: {
        'accessToken': 'synthetic-rotated-access418',
        'refreshToken': 'synthetic-rotated-refresh418',
        'expiresAt': '2026-11-12T13:00:00.000Z',
      },
      envelopeChanges: {'credentialRevision': original.credentialRevision + 1},
    );

OAuthOwnedRefreshJournal _claim({
  OAuthOwnedSourceRecord? source,
  String? operation,
  String? handle,
  DateTime? at,
  OAuthScopedOwnerRecord? scope,
}) => OAuthOwnedRefreshJournal.createDispatched(
  scope: scope ?? _scope(),
  operationId: operation ?? _operation,
  receiptHandle: handle ?? _handle,
  originalSource: source ?? _source(),
  dispatchedAt: at ?? _dispatchAt,
);

OAuthOwnedRefreshJournal _receipt({OAuthOwnedSourceRecord? original}) {
  final source = original ?? _source();
  return _claim(
    source: source,
  ).received(returnedSource: _rotated(source), receivedAt: _receivedAt);
}

OAuthOwnedRefreshJournal? _parse(String raw) =>
    OAuthOwnedRefreshJournal.parse(raw, scope: _scope());

// Expected wire shape is independent of the new codec's toJson implementation.
Map<String, Object?> _wire(
  OAuthOwnedSourceRecord original, {
  OAuthOwnedSourceRecord? returned,
}) => {
  'schema': 1,
  'kind': 'refresh',
  'scopedOwner': _owner,
  'oauthIncarnation': _incarnation,
  'operationId': _operation,
  'receiptHandle': _handle,
  'sourceAccountId': original.account['id'],
  'originalSource': _sourceCopy(original),
  'phase': returned == null ? 'dispatched' : 'received',
  'dispatchedAt': _dispatchAt.toIso8601String(),
  'receivedAt': returned == null ? null : _receivedAt.toIso8601String(),
  'returnedSource': returned == null ? null : _sourceCopy(returned),
};

Map<String, dynamic> _decoded(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

// Eight long, legal account String fields make a 128KiB source reachable while
// each decoded String stays <=16KiB. accessToken is last, leaving spare capacity
// for a one-byte returned-only change in the odd-sized whole-journal fixture.
OAuthOwnedSourceRecord _sizedSource(int targetBytes) {
  final value = _sourceJson();
  final account = value['account']! as Map<String, Object?>;
  var remaining = targetBytes - _bytes(jsonEncode(value));
  expect(remaining, greaterThanOrEqualTo(0));
  for (final key in [
    'displayName',
    'clientId',
    'clientSecret',
    'redirectUri',
    'calendarId',
    'refreshToken',
    'scope',
    'accessToken',
  ]) {
    final before = account[key]! as String;
    final available = _stringLimit - _bytes(before);
    final added = remaining < available ? remaining : available;
    account[key] = '$before${_repeat('a', added)}';
    remaining -= added;
  }
  expect(remaining, 0, reason: 'Padding must fit valid per-String limits');
  final source = _parseSource(value);
  expect(_bytes(source.encode()), targetBytes);
  for (final field in source.account.values.whereType<String>()) {
    expect(_bytes(field), lessThanOrEqualTo(_stringLimit));
  }
  return source;
}

Map<String, Object?> _sizedPair(int targetBytes) {
  final small = _source();
  final overhead =
      _bytes(jsonEncode(_wire(small, returned: small))) -
      2 * _bytes(small.encode());
  final sourceBytes = (targetBytes - overhead) ~/ 2;
  final original = _sizedSource(sourceBytes);
  var returned = original;
  if ((targetBytes - overhead).isOdd) {
    returned = _changedSource(
      original,
      accountChanges: {'accessToken': '${original.account['accessToken']}a'},
      envelopeChanges: {'credentialRevision': 2},
    );
  }
  expect(_bytes(original.encode()), lessThanOrEqualTo(_sourceLimit));
  expect(_bytes(returned.encode()), lessThanOrEqualTo(_sourceLimit));
  for (final field in returned.account.values.whereType<String>()) {
    expect(_bytes(field), lessThanOrEqualTo(_stringLimit));
  }
  final wire = _wire(original, returned: returned);
  expect(_bytes(jsonEncode(wire)), targetBytes);
  return wire;
}

void main() {
  test('RJC418-01 canonical wire rejects duplicate keys at every nested level', () {
    final original = _source();
    final returned = _rotated(original);
    for (final journal in [
      _claim(source: original),
      _receipt(original: original),
    ]) {
      final expected = _wire(
        original,
        returned: journal.phase == OAuthRefreshPhase.received ? returned : null,
      );
      expect(journal.encode(), jsonEncode(expected));
      expect(_parse(journal.encode())!.encode(), journal.encode());
    }
    final raw = jsonEncode(_wire(original, returned: returned));
    final originalRaw = original.encode();
    final returnedRaw = returned.encode();
    final bad = <String>[
      raw.replaceFirst('"schema":1', '"schema":1,"schema":1'),
      raw.replaceFirst(
        '"originalSource":$originalRaw',
        '"originalSource":${originalRaw.replaceFirst('"schema":2', '"schema":2,"schema":2')}',
      ),
      raw.replaceFirst(
        '"returnedSource":$returnedRaw',
        '"returnedSource":${returnedRaw.replaceFirst('"schema":2', '"schema":2,"schema":2')}',
      ),
      raw.replaceFirst(
        '"originalSource":$originalRaw',
        '"originalSource":${originalRaw.replaceFirst('"id":"calendar418"', '"id":"calendar418","id":"calendar418"')}',
      ),
      raw.replaceFirst(
        '"returnedSource":$returnedRaw',
        '"returnedSource":${returnedRaw.replaceFirst('"id":"calendar418"', '"id":"calendar418","id":"calendar418"')}',
      ),
      ' $raw',
      '$raw\n',
      const JsonEncoder.withIndent(
        ' ',
      ).convert(_wire(original, returned: returned)),
      raw.replaceFirst('Codec418', r'\u0043odec418'),
      raw.replaceFirst('"schema":1', '"schema":1.0'),
      raw.replaceFirst('"credentialRevision":1', '"credentialRevision":1.0'),
      jsonEncode(
        Map<String, Object?>.fromEntries(
          _wire(original, returned: returned).entries.toList().reversed,
        ),
      ),
    ];
    final reordered = _decoded(raw);
    final nested = reordered['originalSource'] as Map<String, dynamic>;
    nested['account'] = Map<String, dynamic>.fromEntries(
      (nested['account'] as Map<String, dynamic>).entries.toList().reversed,
    );
    bad.add(jsonEncode(reordered));
    for (final candidate in bad) {
      expect(candidate, isNot(raw), reason: 'Malformed fixture must differ');
      expect(_parse(candidate), isNull);
    }
    for (final key in _wire(original).keys) {
      final missing = _wire(original)..remove(key);
      expect(_parse(jsonEncode(missing)), isNull, reason: 'Missing $key');
    }
    expect(_parse(jsonEncode(_wire(original)..['unknown'] = false)), isNull);
    for (final candidate in ['', '{', 'null', '[]', 'true', '1', '"record"']) {
      expect(_parse(candidate), isNull);
    }
    expect(raw, jsonEncode(_wire(original, returned: returned)));
  });

  test(
    'RJC418-02 phase transition freezes the claim and forbids receipt replacement',
    () {
      final original = _source();
      final returned = _rotated(original);
      final claim = _claim(source: original);
      expect(claim.phase, OAuthRefreshPhase.dispatched);
      expect(claim.receivedAt, isNull);
      expect(claim.returnedSource, isNull);
      for (final entry in <String, Object?>{
        'receivedAt': _receivedAt.toIso8601String(),
        'returnedSource': _sourceCopy(returned),
      }.entries) {
        expect(
          _parse(jsonEncode(_wire(original)..[entry.key] = entry.value)),
          isNull,
        );
      }
      for (final key in ['receivedAt', 'returnedSource']) {
        final bad = _wire(original, returned: returned)..[key] = null;
        expect(_parse(jsonEncode(bad)), isNull);
      }
      for (final phase in <Object?>[
        'prepared',
        'Received',
        'committed',
        null,
        1,
      ]) {
        expect(_parse(jsonEncode(_wire(original)..['phase'] = phase)), isNull);
      }
      for (final kind in <Object?>['authorization', 'Refresh', null, 1]) {
        expect(_parse(jsonEncode(_wire(original)..['kind'] = kind)), isNull);
      }
      final before = claim.encode();
      final received = claim.received(
        returnedSource: returned,
        receivedAt: _receivedAt,
      );
      expect(received.phase, OAuthRefreshPhase.received);
      expect(received.operationId, claim.operationId);
      expect(received.receiptHandle, claim.receiptHandle);
      expect(received.dispatchedAt, claim.dispatchedAt);
      expect(received.originalSource.encode(), original.encode());
      expect(claim.encode(), before);
      for (final next in [returned, original]) {
        expect(
          () =>
              received.received(returnedSource: next, receivedAt: _receivedAt),
          _rejected,
        );
      }
      expect(_parse(received.encode())!.encode(), received.encode());
    },
  );

  test(
    'RJC418-03 operation handle and scope bind separately from a short source ID',
    () {
      final source = _source(accountChanges: {'id': 'x'});
      final claim = _claim(source: source, operation: _handle, handle: _handle);
      expect(claim.sourceAccountId, 'x');
      expect(_parse(claim.encode()), isNotNull);
      for (final key in ['operationId', 'receiptHandle']) {
        for (final invalid in <Object?>[
          _repeat('A', 63),
          _repeat('A', 65),
          '${_repeat('A', 63)}=',
          '${_repeat('A', 63)} ',
          null,
          64,
        ]) {
          final bad = _wire(source)..[key] = invalid;
          expect(_parse(jsonEncode(bad)), isNull, reason: key);
          if (invalid is String) {
            expect(
              () => _claim(
                source: source,
                operation: key == 'operationId' ? invalid : _operation,
                handle: key == 'receiptHandle' ? invalid : _handle,
              ),
              _rejected,
            );
          }
        }
      }
      expect(
        _parse(jsonEncode(_wire(source)..['sourceAccountId'] = 'other')),
        isNull,
      );
      final foreignScopes = [
        _scope(owner: 'g:DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'),
        _scope(incarnation: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'),
      ];
      for (final scope in foreignScopes) {
        expect(
          OAuthOwnedRefreshJournal.parse(claim.encode(), scope: scope),
          isNull,
        );
        expect(() => _claim(source: source, scope: scope), _rejected);
      }
      for (final key in ['scopedOwner', 'oauthIncarnation']) {
        final bad = _wire(source)..[key] = 'foreign';
        expect(_parse(jsonEncode(bad)), isNull);
        final nestedBad = _decoded(_receipt(original: source).encode());
        (nestedBad['returnedSource'] as Map<String, dynamic>)[key] = 'foreign';
        expect(_parse(jsonEncode(nestedBad)), isNull);
      }
    },
  );

  test(
    'RJC418-04 UTC ordering preserves original local dates and expired fixed targets',
    () {
      final source = _source(
        accountChanges: {
          'expiresAt': '2026-11-12T11:00:00.000',
          'lastSyncedAt': '2026-11-11T10:00:00.000',
        },
      );
      final returned = _changedSource(
        source,
        accountChanges: {'expiresAt': '2026-11-12T11:00:00.000Z'},
        envelopeChanges: {'credentialRevision': 2},
      );
      final received = _claim(
        source: source,
      ).received(returnedSource: returned, receivedAt: _dispatchAt);
      final parsed = _parse(received.encode())!;
      expect(parsed.receivedAt, _dispatchAt);
      expect(parsed.originalSource.encode(), source.encode());
      expect(
        parsed.returnedSource!.account['lastSyncedAt'],
        source.account['lastSyncedAt'],
      );
      expect(
        parsed.returnedSource!.account['expiresAt'],
        '2026-11-12T11:00:00.000Z',
      );
      expect(
        DateTime.parse(
          returned.account['expiresAt']! as String,
        ).isBefore(_dispatchAt),
        isTrue,
      );
      for (final date in [
        '2026-11-12T12:00:00.000',
        '2026-11-12T12:00:00.000+00:00',
        '2026-11-12T12:00:00Z',
        '2026-11-12T12:00:00.000000Z',
        '2026-11-32T12:00:00.000Z',
      ]) {
        for (final key in ['dispatchedAt', 'receivedAt']) {
          final bad = _wire(source, returned: returned)..[key] = date;
          expect(_parse(jsonEncode(bad)), isNull, reason: key);
        }
      }
      final early = _dispatchAt.subtract(const Duration(microseconds: 1));
      expect(
        () => _claim(
          source: source,
        ).received(returnedSource: returned, receivedAt: early),
        _rejected,
      );
      expect(
        _parse(
          jsonEncode(
            _wire(source, returned: returned)
              ..['receivedAt'] = early.toIso8601String(),
          ),
        ),
        isNull,
      );
      final localDate = DateTime(2026, 11, 12, 12);
      expect(localDate.isUtc, isFalse);
      expect(() => _claim(at: localDate), _rejected);
      expect(
        () => _claim(
          source: source,
        ).received(returnedSource: returned, receivedAt: localDate),
        _rejected,
      );
      expect(
        () => _claim(
          source: source,
        ).received(returnedSource: source, receivedAt: _receivedAt),
        _rejected,
        reason:
            'Returned expiry must be UTC even when original expiry is canonical local',
      );
    },
  );

  test(
    'RJC418-05 exact pairing rejects each configuration metadata and provenance mutation',
    () {
      final source = _source();
      final before = source.encode();
      final invalidFields = <String, Object?>{
        'id': 'other418',
        'provider': 'outlook',
        'clientId': 'another-client',
        'clientSecret': 'another-secret',
        'redirectUri': 'duoyi://other/callback',
        'calendarId': 'secondary',
        'displayName': 'Renamed',
        'colorValue': 0xff112233,
        'enabled': false,
        'lastSyncedAt': '2026-11-12T10:00:00.000Z',
      };
      for (final entry in invalidFields.entries) {
        final other = _changedSource(
          source,
          accountChanges: {entry.key: entry.value},
        );
        expect(
          () => _claim(
            source: source,
          ).received(returnedSource: other, receivedAt: _receivedAt),
          _rejected,
          reason: entry.key,
        );
        expect(
          _parse(jsonEncode(_wire(source, returned: other))),
          isNull,
          reason: entry.key,
        );
      }
      for (final entry in <String, Object?>{
        'sourceIncarnation': 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        'metadataRevision': 2,
      }.entries) {
        final other = _changedSource(
          source,
          envelopeChanges: {entry.key: entry.value},
        );
        expect(
          _parse(jsonEncode(_wire(source, returned: other))),
          isNull,
          reason: entry.key,
        );
        expect(
          () => _claim(
            source: source,
          ).received(returnedSource: other, receivedAt: _receivedAt),
          _rejected,
        );
      }
      final receipt = _receipt(original: source);
      final third = _changedSource(
        source,
        accountChanges: {'displayName': 'Third row'},
        envelopeChanges: {'metadataRevision': 2},
      );
      expect(receipt.matchesOriginalSource(source), isTrue);
      expect(receipt.matchesReturnedSource(_rotated(source)), isTrue);
      expect(receipt.matchesOriginalSource(third), isFalse);
      expect(receipt.matchesReturnedSource(third), isFalse);
      expect(_claim(source: source).matchesReturnedSource(source), isFalse);
      expect(source.encode(), before);
    },
  );

  test(
    'RJC418-06 credential revisions allow nochange and exact max transitions without reissuing',
    () {
      final source = _source(credentialRevision: 7);
      final changes = <String, Object?>{
        'accessToken': 'changed-access418',
        'refreshToken': 'changed-refresh418',
        'expiresAt': '2026-11-12T14:00:00.000Z',
        'scope': 'calendar.full',
      };
      for (final entry in changes.entries) {
        final returned = _changedSource(
          source,
          accountChanges: {entry.key: entry.value},
          envelopeChanges: {'credentialRevision': 8},
        );
        final receipt = _claim(
          source: source,
        ).received(returnedSource: returned, receivedAt: _receivedAt);
        final raw = receipt.encode();
        expect(
          _parse(raw)!.returnedSource!.credentialRevision,
          8,
          reason: entry.key,
        );
        expect(_parse(raw)!.encode(), raw);
        for (final invalid in [6, 7, 9]) {
          final wrong = _changedSource(
            returned,
            envelopeChanges: {'credentialRevision': invalid},
          );
          expect(
            _parse(jsonEncode(_wire(source, returned: wrong))),
            isNull,
            reason: '${entry.key} revision',
          );
          expect(
            () => _claim(
              source: source,
            ).received(returnedSource: wrong, receivedAt: _receivedAt),
            _rejected,
          );
        }
      }
      final same = _claim(
        source: source,
      ).received(returnedSource: source, receivedAt: _receivedAt);
      expect(same.matchesOriginalSource(source), isTrue);
      expect(same.matchesReturnedSource(source), isTrue);
      expect(_parse(same.encode())!.returnedSource!.credentialRevision, 7);
      final falseIncrement = _changedSource(
        source,
        envelopeChanges: {'credentialRevision': 8},
      );
      expect(
        _parse(jsonEncode(_wire(source, returned: falseIncrement))),
        isNull,
      );
      expect(
        () => _claim(
          source: source,
        ).received(returnedSource: falseIncrement, receivedAt: _receivedAt),
        _rejected,
      );
      final maximum = _source(credentialRevision: _maximumRevision);
      expect(
        _parse(
          _claim(
            source: maximum,
          ).received(returnedSource: maximum, receivedAt: _receivedAt).encode(),
        ),
        isNotNull,
      );
      final overflow = _changedSource(
        maximum,
        accountChanges: {'scope': 'calendar.full'},
      );
      expect(_parse(jsonEncode(_wire(maximum, returned: overflow))), isNull);
      expect(
        () => _claim(
          source: maximum,
        ).received(returnedSource: overflow, receivedAt: _receivedAt),
        _rejected,
      );
      final penultimate = _source(credentialRevision: _maximumRevision - 1);
      final last = _changedSource(
        penultimate,
        accountChanges: {'scope': 'calendar.full'},
        envelopeChanges: {'credentialRevision': _maximumRevision},
      );
      expect(
        _parse(
          _claim(
            source: penultimate,
          ).received(returnedSource: last, receivedAt: _receivedAt).encode(),
        ),
        isNotNull,
      );
      for (final invalid in <Object?>[0, -1, 7.0, _maximumRevision + 1]) {
        final raw = _decoded(same.encode());
        (raw['returnedSource'] as Map<String, dynamic>)['credentialRevision'] =
            invalid;
        expect(_parse(jsonEncode(raw)), isNull);
      }
    },
  );

  test(
    'RJC418-07 complete target types reject partial maps empty refresh and scope coercion',
    () {
      final source = _source();
      final returned = _rotated(source);
      final invalid = <String, List<Object?>>{
        'refreshToken': ['', ' \t ', null, 42],
        'accessToken': ['', ' ', null, 42],
        'scope': [
          '',
          ' ',
          null,
          42,
          ['calendar.readonly'],
        ],
        'expiresAt': [null, 42, 'yesterday'],
      };
      for (final role in ['originalSource', 'returnedSource']) {
        for (final entry in invalid.entries) {
          for (final value in entry.value) {
            final wire = _decoded(
              jsonEncode(_wire(source, returned: returned)),
            );
            ((wire[role] as Map<String, dynamic>)['account']
                    as Map<String, dynamic>)[entry.key] =
                value;
            expect(
              _parse(jsonEncode(wire)),
              isNull,
              reason: '$role ${entry.key}',
            );
          }
          final missing = _decoded(
            jsonEncode(_wire(source, returned: returned)),
          );
          ((missing[role] as Map<String, dynamic>)['account']
                  as Map<String, dynamic>)
              .remove(entry.key);
          expect(
            _parse(jsonEncode(missing)),
            isNull,
            reason: '$role missing ${entry.key}',
          );
        }
      }
      for (final empty in ['', ' \t ']) {
        final oldSource = _source(accountChanges: {'refreshToken': empty});
        expect(() => _claim(source: oldSource), _rejected);
      }
      final retained = _changedSource(
        source,
        accountChanges: {'accessToken': 'renewed-only418'},
        envelopeChanges: {'credentialRevision': 2},
      );
      final receipt = _claim(
        source: source,
      ).received(returnedSource: retained, receivedAt: _receivedAt);
      expect(
        _parse(receipt.encode())!.returnedSource!.account['refreshToken'],
        source.account['refreshToken'],
      );
      final partial = _wire(source, returned: returned)
        ..['returnedSource'] = {
          'access_token': 'partial418',
          'expires_in': 3600,
        };
      expect(_parse(jsonEncode(partial)), isNull);
    },
  );

  test(
    'RJC418-08 UTF8 byte limits isolate exact string source and raw edges and preserve immutable data',
    () {
      // 5461 three-byte characters plus ASCII =16384 UTF8 bytes, not code units.
      final unicodeAtLimit = '${_repeat('汉', 5461)}a';
      expect(_bytes(unicodeAtLimit), _stringLimit);
      expect(unicodeAtLimit.length, lessThan(_stringLimit));
      final atString = _source(
        accountChanges: {'clientSecret': unicodeAtLimit},
      );
      expect(_parse(_claim(source: atString).encode()), isNotNull);
      final overString = _source(
        accountChanges: {'clientSecret': '${unicodeAtLimit}a'},
      );
      final stringWire = jsonEncode(_wire(overString));
      expect(_bytes(overString.encode()), lessThan(_sourceLimit));
      expect(_bytes(stringWire), lessThan(_rawLimit));
      expect(_parse(stringWire), isNull);
      expect(() => _claim(source: overString), _rejected);
      final badTarget = _changedSource(
        _source(),
        accountChanges: {'accessToken': '${unicodeAtLimit}a'},
        envelopeChanges: {'credentialRevision': 2},
      );
      expect(
        () => _claim().received(
          returnedSource: badTarget,
          receivedAt: _receivedAt,
        ),
        _rejected,
      );

      final atSource = _sizedSource(_sourceLimit);
      final atSourceWire = jsonEncode(_wire(atSource));
      expect(_bytes(atSourceWire), lessThan(_rawLimit));
      expect(_parse(atSourceWire), isNotNull);
      expect(_claim(source: atSource).encode(), atSourceWire);
      final overSource = _sizedSource(_sourceLimit + 1);
      final overSourceWire = jsonEncode(_wire(overSource));
      expect(_bytes(overSourceWire), lessThan(_rawLimit));
      expect(_parse(overSourceWire), isNull);
      expect(() => _claim(source: overSource), _rejected);

      // Independently exercise the returned source edge while the whole raw
      // record and original source remain below their respective limits.
      final smallerOriginal = _sizedSource(_sourceLimit - 2048);
      for (final extra in [2048, 2049]) {
        final sizedReturned = _changedSource(
          smallerOriginal,
          accountChanges: {
            'accessToken':
                '${smallerOriginal.account['accessToken']}${_repeat('a', extra)}',
          },
          envelopeChanges: {'credentialRevision': 2},
        );
        expect(_bytes(sizedReturned.encode()), _sourceLimit + extra - 2048);
        expect(
          _bytes(sizedReturned.account['accessToken']! as String),
          lessThan(_stringLimit),
        );
        final wire = jsonEncode(
          _wire(smallerOriginal, returned: sizedReturned),
        );
        expect(_bytes(wire), lessThan(_rawLimit));
        if (extra == 2048) {
          expect(_parse(wire), isNotNull);
          expect(
            _claim(source: smallerOriginal)
                .received(
                  returnedSource: sizedReturned,
                  receivedAt: _receivedAt,
                )
                .encode(),
            wire,
          );
        } else {
          expect(_parse(wire), isNull);
          expect(
            () => _claim(
              source: smallerOriginal,
            ).received(returnedSource: sizedReturned, receivedAt: _receivedAt),
            _rejected,
          );
        }
      }

      final exactRawWire = _sizedPair(_rawLimit);
      final exactRaw = jsonEncode(exactRawWire);
      expect(_parse(exactRaw), isNotNull);
      final exactOriginal = _parseSource(
        exactRawWire['originalSource']! as Map<String, Object?>,
      );
      final exactReturned = _parseSource(
        exactRawWire['returnedSource']! as Map<String, Object?>,
      );
      expect(
        _claim(source: exactOriginal)
            .received(returnedSource: exactReturned, receivedAt: _receivedAt)
            .encode(),
        exactRaw,
      );
      final overRawWire = _sizedPair(_rawLimit + 1);
      expect(_parse(jsonEncode(overRawWire)), isNull);
      final overOriginal = _parseSource(
        overRawWire['originalSource']! as Map<String, Object?>,
      );
      final overReturned = _parseSource(
        overRawWire['returnedSource']! as Map<String, Object?>,
      );
      expect(
        () => _claim(
          source: overOriginal,
        ).received(returnedSource: overReturned, receivedAt: _receivedAt),
        _rejected,
      );

      // Replacing one ASCII token character with 汉 changes UTF8 bytes but not
      // UTF16 length. Both source and String limits remain legal: only raw fails.
      final unicodeRaw = _decoded(exactRaw);
      for (final role in ['originalSource', 'returnedSource']) {
        final source = unicodeRaw[role] as Map<String, dynamic>;
        final account = source['account'] as Map<String, dynamic>;
        final token = account['accessToken'] as String;
        account['accessToken'] = '汉${token.substring(1)}';
        expect(
          _bytes(account['accessToken'] as String),
          lessThan(_stringLimit),
        );
        expect(_bytes(jsonEncode(source)), lessThan(_sourceLimit));
      }
      final byteOnlyOver = jsonEncode(unicodeRaw);
      expect(byteOnlyOver.length, exactRaw.length);
      expect(byteOnlyOver.length, lessThanOrEqualTo(_rawLimit));
      expect(_bytes(byteOnlyOver), _rawLimit + 4);
      expect(_parse(byteOnlyOver), isNull);

      final journal = _receipt();
      final before = journal.encode();
      final exposed = journal.toJson();
      exposed['operationId'] = 'changed';
      try {
        final source = exposed['originalSource'] as Map;
        (source['account'] as Map)['clientSecret'] = 'mutated418';
      } on UnsupportedError {
        // Returning an immutable nested map also meets the immutability contract.
      }
      expect(journal.encode(), before);
      expect(
        () => journal.originalSource.account['clientSecret'] = 'mutated418',
        throwsUnsupportedError,
      );
      expect(journal.toString(), 'OAuthOwnedRefreshJournal(received)');
      expect(_claim().toString(), 'OAuthOwnedRefreshJournal(dispatched)');
      Object? captured;
      try {
        journal.received(returnedSource: _source(), receivedAt: _receivedAt);
      } catch (error) {
        captured = error;
      }
      expect(captured, isA<OAuthWorkspaceCodecException>());
      for (final secret in [
        'synthetic-secret418',
        'synthetic-access418',
        'synthetic-refresh418',
        _operation,
        _handle,
      ]) {
        expect(journal.toString(), isNot(contains(secret)));
        expect(captured.toString(), isNot(contains(secret)));
      }
      expect(_parse(before)!.encode(), before);
    },
  );
}
