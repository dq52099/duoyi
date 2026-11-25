import 'dart:convert';

import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _oauthIncarnation = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const _otherIncarnation = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const _maximumRevision = 9007199254740991;

// These parsed scope fixtures are durable codec data only. They neither issue
// nor prove an Auth lease, storage ownership, or permission to sync a calendar.
OAuthScopedOwnerRecord _scope({
  String owner = _owner,
  String incarnation = _oauthIncarnation,
}) => OAuthScopedOwnerRecord.parse(
  jsonEncode({
    'schema': 1,
    'scopeKind': 'guest',
    'scopedOwner': owner,
    'oauthIncarnation': incarnation,
  }),
)!;

Map<String, Object?> _account() => {
  'id': 'oauth_codec_calendar',
  'provider': 'google',
  'displayName': 'Codec calendar',
  'clientId': 'synthetic-client',
  'clientSecret': '',
  'redirectUri': 'duoyi://oauth/callback',
  'calendarId': 'primary',
  'accessToken': 'synthetic-access',
  'refreshToken': '',
  'expiresAt': '2026-11-10T12:00:00.000Z',
  'scope': 'calendar.readonly',
  'colorValue': 0xff336699,
  'enabled': true,
  'lastSyncedAt': null,
};

Map<String, Object?> _event() => {
  'id': 'codec_event',
  'title': 'Codec meeting',
  'date': '2026-11-10T09:00:00.000Z',
  'endDate': '2026-11-10T10:00:00.000Z',
  'subtitle': 'Synthetic room',
  'colorValue': 0xff336699,
  'sourceId': 'oauth_codec_calendar',
  'timeHour': 9,
  'timeMinute': 0,
};

OAuthOwnedSourceRecord _source({OAuthScopedOwnerRecord? scope}) =>
    OAuthOwnedSourceRecord.create(
      scope: scope ?? _scope(),
      account: _account(),
    );

Map<String, Object?> _sourceEnvelope(OAuthOwnedSourceRecord source) => {
  'schema': 2,
  'scopedOwner': source.scopedOwner,
  'oauthIncarnation': source.oauthIncarnation,
  'sourceIncarnation': source.sourceIncarnation,
  'metadataRevision': source.metadataRevision,
  'credentialRevision': source.credentialRevision,
  'account': Map<String, Object?>.of(source.account),
};

Map<String, Object?> _eventsEnvelope(
  OAuthOwnedSourceRecord source,
  List<Map<String, Object?>> events,
) => {
  'schema': 2,
  'scopedOwner': source.scopedOwner,
  'oauthIncarnation': source.oauthIncarnation,
  'sourceAccountId': source.account['id'],
  'sourceIncarnation': source.sourceIncarnation,
  'metadataRevision': source.metadataRevision,
  'credentialRevision': source.credentialRevision,
  'events': events,
};

void main() {
  test('OWC-01 source schema2 roundtrip preserves all account fields', () {
    final source = _source();
    expect(source.scopedOwner, _owner);
    expect(source.oauthIncarnation, _oauthIncarnation);
    expect(source.sourceIncarnation, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
    expect(source.metadataRevision, 1);
    expect(source.credentialRevision, 1);
    expect(source.encode(), jsonEncode(_sourceEnvelope(source)));
    final parsed = OAuthOwnedSourceRecord.parse(
      source.encode(),
      scope: _scope(),
    )!;
    expect(parsed.account, _account());
    expect(parsed.sourceIncarnation, source.sourceIncarnation);
    expect(parsed.encode(), source.encode());
  });

  test(
    'OWC-02 source parsing binds owner and OAuth incarnation separately',
    () {
      final raw = _source().encode();
      expect(OAuthOwnedSourceRecord.parse(raw, scope: _scope()), isNotNull);
      expect(
        OAuthOwnedSourceRecord.parse(
          raw,
          scope: _scope(owner: 'g:DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'),
        ),
        isNull,
      );
      expect(
        OAuthOwnedSourceRecord.parse(
          raw,
          scope: _scope(incarnation: _otherIncarnation),
        ),
        isNull,
      );
    },
  );

  test(
    'OWC-03 source envelope rejects wrong schema shape and revision stamps',
    () {
      final source = _source();
      final invalidFields = <String, List<Object?>>{
        'schema': [null, 1, 3, 2.0, '2', true],
        'scopedOwner': [null, 7],
        'oauthIncarnation': [null, 7],
        'sourceIncarnation': [null, 7, '', 'short', '$_otherIncarnation='],
        'metadataRevision': [null, 0, -1, 1.0, '1', _maximumRevision + 1],
        'credentialRevision': [null, 0, -1, 1.0, '1', _maximumRevision + 1],
        'account': [null, [], 'account'],
      };
      for (final entry in invalidFields.entries) {
        for (final value in entry.value) {
          final json = _sourceEnvelope(source)..[entry.key] = value;
          expect(
            OAuthOwnedSourceRecord.parse(jsonEncode(json), scope: _scope()),
            isNull,
            reason: '${entry.key}: $value',
          );
        }
      }
      for (final key in _sourceEnvelope(source).keys) {
        final json = _sourceEnvelope(source)..remove(key);
        expect(
          OAuthOwnedSourceRecord.parse(jsonEncode(json), scope: _scope()),
          isNull,
          reason: 'missing $key',
        );
      }
      final extra = _sourceEnvelope(source)..['unknown'] = false;
      expect(
        OAuthOwnedSourceRecord.parse(jsonEncode(extra), scope: _scope()),
        isNull,
      );
      for (final raw in ['null', '[]', 'true', '{', '']) {
        expect(OAuthOwnedSourceRecord.parse(raw, scope: _scope()), isNull);
      }
      final maximum = _sourceEnvelope(source)
        ..['metadataRevision'] = _maximumRevision
        ..['credentialRevision'] = _maximumRevision;
      expect(
        OAuthOwnedSourceRecord.parse(jsonEncode(maximum), scope: _scope()),
        isNotNull,
      );
    },
  );

  test(
    'OWC-04 source rejects duplicate keys reordered fields and noncanonical JSON',
    () {
      final source = _source();
      final raw = source.encode();
      final reversed = Map<String, Object?>.fromEntries(
        _sourceEnvelope(source).entries.toList().reversed,
      );
      final reorderedAccount = _sourceEnvelope(source)
        ..['account'] = Map<String, Object?>.fromEntries(
          _account().entries.toList().reversed,
        );
      for (final malformed in [
        ' $raw',
        '$raw\n',
        const JsonEncoder.withIndent(' ').convert(_sourceEnvelope(source)),
        raw.replaceFirst('"schema":2', '"schema":2,"schema":2'),
        raw.replaceFirst(
          '"id":"oauth_codec_calendar"',
          '"id":"oauth_codec_calendar","id":"oauth_codec_calendar"',
        ),
        jsonEncode(reversed),
        jsonEncode(reorderedAccount),
        raw.replaceFirst('Codec calendar', r'\u0043odec calendar'),
      ]) {
        expect(
          OAuthOwnedSourceRecord.parse(malformed, scope: _scope()),
          isNull,
        );
      }
    },
  );

  test('OWC-05 account requires exact typed fields and canonical dates', () {
    final source = _source();
    final invalidFields = <String, List<Object?>>{
      'id': [null, '', ' ', 1],
      'provider': [null, 'caldav', 'Google', 1],
      'displayName': [null, 1],
      'clientId': [null, '', ' ', 1],
      'clientSecret': [null, 1],
      'redirectUri': [
        null,
        '',
        'relative/path',
        'https://',
        'duoyi://oauth/#fragment',
        'https://user@example.test/callback',
        'duoyi://oauth/%zz',
        'duoyi://oauth/ bad',
      ],
      'calendarId': [null, '', ' ', 1],
      'accessToken': [null, '', ' ', 1],
      'refreshToken': [null, 1],
      'expiresAt': [null, 1, 'invalid', '2026-11-10', '2026-11-10T12:00:00Z'],
      'scope': [null, '', ' ', 1],
      'colorValue': [null, -1, 0x100000000, 1.0, '1'],
      'enabled': [null, 1, 'true'],
      'lastSyncedAt': [1, 'invalid', '2026-11-10'],
    };
    for (final entry in invalidFields.entries) {
      for (final value in entry.value) {
        final account = _account()..[entry.key] = value;
        final json = _sourceEnvelope(source)..['account'] = account;
        expect(
          OAuthOwnedSourceRecord.parse(jsonEncode(json), scope: _scope()),
          isNull,
          reason: '${entry.key}: $value',
        );
      }
    }
    for (final key in _account().keys) {
      final json = _sourceEnvelope(source)
        ..['account'] = (_account()..remove(key));
      expect(
        OAuthOwnedSourceRecord.parse(jsonEncode(json), scope: _scope()),
        isNull,
        reason: 'missing account $key',
      );
    }
    final extra = _sourceEnvelope(source)
      ..['account'] = (_account()..['extra'] = 1);
    expect(
      OAuthOwnedSourceRecord.parse(jsonEncode(extra), scope: _scope()),
      isNull,
    );
    for (final color in [0, 0xffffffff]) {
      final valid = _account()
        ..['displayName'] = ''
        ..['colorValue'] = color
        ..['lastSyncedAt'] = '2026-11-10T11:00:00.000Z';
      final json = _sourceEnvelope(source)..['account'] = valid;
      expect(
        OAuthOwnedSourceRecord.parse(
          jsonEncode(json),
          scope: _scope(),
        )!.account,
        valid,
      );
    }
  });

  test('OWC-06 invalid source creation and updates throw sanitized errors', () {
    final source = _source();
    final invalid = _account()
      ..['clientSecret'] = 'DO_NOT_INCLUDE_SYNTHETIC_SECRET'
      ..['enabled'] = 'invalid';
    final rejected = isA<OAuthWorkspaceCodecException>().having(
      (error) => error.toString(),
      'sanitized message',
      'OAuth workspace record rejected',
    );
    expect(
      () => OAuthOwnedSourceRecord.create(scope: _scope(), account: invalid),
      throwsA(rejected),
    );
    expect(() => source.withAccount(invalid), throwsA(rejected));
    expect(source.account, _account());
    final maximum = _sourceEnvelope(source)
      ..['metadataRevision'] = _maximumRevision
      ..['credentialRevision'] = _maximumRevision;
    final exhausted = OAuthOwnedSourceRecord.parse(
      jsonEncode(maximum),
      scope: _scope(),
    )!;
    expect(
      () => exhausted.withAccount(_account()..['enabled'] = false),
      throwsA(rejected),
    );
    expect(
      () => exhausted.withAccount(_account()..['accessToken'] = 'rotated'),
      throwsA(rejected),
    );
    expect(
      exhausted.withAccount(_account()).metadataRevision,
      _maximumRevision,
    );
  });

  test(
    'OWC-07 source account copies inputs and remains unmodifiable after parsing',
    () {
      final input = _account();
      final source = OAuthOwnedSourceRecord.create(
        scope: _scope(),
        account: input,
      );
      input['displayName'] = 'Input mutation';
      expect(source.account['displayName'], 'Codec calendar');
      final nextInput = _account()..['displayName'] = 'Edited';
      final next = source.withAccount(nextInput);
      nextInput.clear();
      final parsed = OAuthOwnedSourceRecord.parse(
        next.encode(),
        scope: _scope(),
      )!;
      for (final account in [source.account, next.account, parsed.account]) {
        expect(() => account['enabled'] = false, throwsUnsupportedError);
        expect(() => account.remove('id'), throwsUnsupportedError);
        expect(() => account.clear(), throwsUnsupportedError);
      }
      expect(next.account['displayName'], 'Edited');
      expect(parsed.account, next.account);
    },
  );

  test('OWC-08 source toJson returns a fresh canonical outer map', () {
    final source = _source();
    final before = source.encode();
    final first = source.toJson();
    final second = source.toJson();
    expect(first, _sourceEnvelope(source));
    expect(first, isNot(same(second)));
    first['schema'] = 99;
    first['account'] = <String, Object?>{};
    second.remove('metadataRevision');
    expect(source.encode(), before);
    expect(
      source.toJson().keys.toList(),
      _sourceEnvelope(source).keys.toList(),
    );
    expect(source.toJson(), _sourceEnvelope(source));
  });

  test(
    'OWC-09 each user metadata change increments only metadata revision',
    () {
      final source = _source();
      final changes = <String, Object?>{
        'displayName': 'Renamed',
        'colorValue': 0xff112233,
        'enabled': false,
      };
      for (final entry in changes.entries) {
        final next = source.withAccount(_account()..[entry.key] = entry.value);
        expect(
          next.sourceIncarnation,
          source.sourceIncarnation,
          reason: entry.key,
        );
        expect(next.metadataRevision, 2, reason: entry.key);
        expect(next.credentialRevision, 1, reason: entry.key);
        expect(next.account[entry.key], entry.value);
      }
      final next = source.withAccount({..._account(), ...changes});
      expect(next.metadataRevision, 2);
      expect(
        next
            .withAccount(Map<String, Object?>.of(next.account))
            .metadataRevision,
        2,
      );
      expect(source.account, _account());
    },
  );

  test('OWC-10 each credential change increments only credential revision', () {
    final source = _source();
    final changes = <String, Object?>{
      'accessToken': 'rotated-access',
      'refreshToken': 'rotated-refresh',
      'expiresAt': '2026-11-11T12:00:00.000Z',
      'scope': 'calendar.readonly profile',
    };
    for (final entry in changes.entries) {
      final next = source.withAccount(_account()..[entry.key] = entry.value);
      expect(
        next.sourceIncarnation,
        source.sourceIncarnation,
        reason: entry.key,
      );
      expect(next.metadataRevision, 1, reason: entry.key);
      expect(next.credentialRevision, 2, reason: entry.key);
    }
    final next = source.withAccount({..._account(), ...changes});
    expect(next.credentialRevision, 2);
    expect(
      next
          .withAccount(Map<String, Object?>.of(next.account))
          .credentialRevision,
      2,
    );
    expect(source.account, _account());
  });

  test(
    'OWC-11 each connection configuration change replaces incarnation and resets stamps',
    () {
      final original = _source();
      final source = original.withAccount(
        _account()
          ..['displayName'] = 'Renamed'
          ..['accessToken'] = 'rotated',
      );
      final changes = <String, Object?>{
        'id': 'oauth_codec_other',
        'provider': 'outlook',
        'clientId': 'other-client',
        'clientSecret': 'synthetic-secret',
        'redirectUri': 'duoyi://oauth/other',
        'calendarId': 'other-calendar',
      };
      for (final entry in changes.entries) {
        final input = Map<String, Object?>.of(source.account)
          ..[entry.key] = entry.value;
        final next = source.withAccount(input);
        expect(
          next.sourceIncarnation,
          isNot(source.sourceIncarnation),
          reason: entry.key,
        );
        expect(next.metadataRevision, 1, reason: entry.key);
        expect(next.credentialRevision, 1, reason: entry.key);
        expect(next.scopedOwner, source.scopedOwner);
        expect(next.oauthIncarnation, source.oauthIncarnation);
        expect(next.account, input);
      }
      expect(source.metadataRevision, 2);
      expect(source.credentialRevision, 2);
      final combined = source.withAccount(
        Map<String, Object?>.of(source.account)
          ..['calendarId'] = 'new-calendar'
          ..['displayName'] = 'Another name'
          ..['accessToken'] = 'another-token',
      );
      expect(combined.metadataRevision, 1);
      expect(combined.credentialRevision, 1);
      expect(combined.sourceIncarnation, isNot(source.sourceIncarnation));
    },
  );

  test(
    'OWC-12 unchanged account and lastSyncedAt retain both revision stamps',
    () {
      final source = _source().withAccount(
        _account()
          ..['displayName'] = 'Renamed'
          ..['accessToken'] = 'rotated',
      );
      final unchanged = source.withAccount(
        Map<String, Object?>.of(source.account),
      );
      final synced = source.withAccount(
        Map<String, Object?>.of(source.account)
          ..['lastSyncedAt'] = '2026-11-10T11:00:00.000Z',
      );
      for (final next in [unchanged, synced]) {
        expect(next.sourceIncarnation, source.sourceIncarnation);
        expect(next.metadataRevision, 2);
        expect(next.credentialRevision, 2);
      }
      expect(unchanged.encode(), source.encode());
      expect(synced.account['lastSyncedAt'], '2026-11-10T11:00:00.000Z');
      expect(source.account['lastSyncedAt'], isNull);
      expect(
        synced
            .withAccount(
              Map<String, Object?>.of(synced.account)..['lastSyncedAt'] = null,
            )
            .metadataRevision,
        2,
      );
    },
  );

  test(
    'OWC-13 combined metadata and credential edits increment each stamp once',
    () {
      final source = _source();
      final next = source.withAccount(
        _account()
          ..['displayName'] = 'Renamed'
          ..['colorValue'] = 0
          ..['enabled'] = false
          ..['accessToken'] = 'rotated'
          ..['refreshToken'] = 'refresh'
          ..['lastSyncedAt'] = '2026-11-10T11:00:00.000Z',
      );
      expect(next.sourceIncarnation, source.sourceIncarnation);
      expect(next.metadataRevision, 2);
      expect(next.credentialRevision, 2);
      final again = next.withAccount(
        Map<String, Object?>.of(next.account)
          ..['displayName'] = 'Renamed again'
          ..['accessToken'] = 'rotated again',
      );
      expect(again.metadataRevision, 3);
      expect(again.credentialRevision, 3);
    },
  );

  test(
    'OWC-14 parseList preserves canonical order and accepts whitespace around empty list',
    () {
      final first = _source();
      final second = first.withAccount(
        _account()..['id'] = 'oauth_codec_second',
      );
      final raw = jsonEncode([_sourceEnvelope(second), _sourceEnvelope(first)]);
      final parsed = OAuthOwnedSourceRecord.parseList(raw, scope: _scope())!;
      expect(parsed.map((row) => row.account['id']).toList(), [
        'oauth_codec_second',
        'oauth_codec_calendar',
      ]);
      expect(jsonEncode(parsed.map((row) => row.toJson()).toList()), raw);
      expect(() => parsed.clear(), throwsUnsupportedError);
      expect(() => parsed.add(first), throwsUnsupportedError);
      for (final raw in ['[]', ' \n [ ] \t ']) {
        expect(OAuthOwnedSourceRecord.parseList(raw, scope: _scope()), isEmpty);
      }
      for (final raw in ['', '{', '{}', 'null', '"[]"', '[] trailing']) {
        expect(OAuthOwnedSourceRecord.parseList(raw, scope: _scope()), isNull);
      }
    },
  );

  test(
    'OWC-15 parseList rejects duplicate source IDs and invalid rows atomically',
    () {
      final first = _source();
      final duplicateId = _source();
      final otherOwner = _source(
        scope: _scope(owner: 'g:DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'),
      );
      final otherOAuth = _source(scope: _scope(incarnation: _otherIncarnation));
      final badRevision = _sourceEnvelope(first)..['credentialRevision'] = 0;
      final badAccount = _sourceEnvelope(first)
        ..['account'] = (_account()..remove('enabled'));
      for (final rows in <List<Object?>>[
        [_sourceEnvelope(first), _sourceEnvelope(first)],
        [_sourceEnvelope(first), _sourceEnvelope(duplicateId)],
        [_sourceEnvelope(first), _sourceEnvelope(otherOwner)],
        [_sourceEnvelope(first), _sourceEnvelope(otherOAuth)],
        [_sourceEnvelope(first), badRevision],
        [_sourceEnvelope(first), badAccount],
        [_sourceEnvelope(first), null],
        [false, _sourceEnvelope(first)],
      ]) {
        expect(
          OAuthOwnedSourceRecord.parseList(jsonEncode(rows), scope: _scope()),
          isNull,
        );
      }
    },
  );

  test(
    'OWC-16 parseList validates original nonempty JSON before key collapse',
    () {
      final source = _source();
      final raw = '[${source.encode()}]';
      final reversed = Map<String, Object?>.fromEntries(
        _sourceEnvelope(source).entries.toList().reversed,
      );
      for (final malformed in [
        ' $raw',
        '$raw\n',
        '[ ${source.encode()} ]',
        const JsonEncoder.withIndent(' ').convert([_sourceEnvelope(source)]),
        raw.replaceFirst('"schema":2', '"schema":2,"schema":2'),
        raw.replaceFirst('"enabled":true', '"enabled":false,"enabled":true'),
        jsonEncode([reversed]),
      ]) {
        expect(
          OAuthOwnedSourceRecord.parseList(malformed, scope: _scope()),
          isNull,
        );
      }
      expect(
        OAuthOwnedSourceRecord.parseList(raw, scope: _scope()),
        hasLength(1),
      );
    },
  );

  test(
    'OWC-17 event schema2 roundtrip preserves exact cache fields and nullable options',
    () {
      final source = _source();
      final allDay = _event()
        ..['id'] = 'codec_all_day'
        ..['title'] = ''
        ..['endDate'] = null
        ..['subtitle'] = null
        ..['colorValue'] = 0
        ..['sourceId'] = null
        ..['timeHour'] = null
        ..['timeMinute'] = null;
      final boundary = _event()
        ..['id'] = 'codec_boundary'
        ..['colorValue'] = 0xffffffff
        ..['timeHour'] = 23
        ..['timeMinute'] = 59;
      for (final events in <List<Map<String, Object?>>>[
        [],
        [_event()],
        [_event(), allDay, boundary],
      ]) {
        final cache = OAuthOwnedEventsRecord.create(
          source: source,
          events: events,
        );
        expect(cache.encode(), jsonEncode(_eventsEnvelope(source, events)));
        final parsed = OAuthOwnedEventsRecord.parse(
          cache.encode(),
          source: source,
        )!;
        expect(parsed.events, events);
        expect(parsed.sourceIncarnation, source.sourceIncarnation);
        expect(parsed.metadataRevision, 1);
        expect(parsed.credentialRevision, 1);
        expect(parsed.encode(), cache.encode());
      }
    },
  );

  test(
    'OWC-18 event cache rejects changed owner OAuth scope and stale source incarnation',
    () {
      final source = _source();
      final cache = OAuthOwnedEventsRecord.create(
        source: source,
        events: [_event()],
      );
      final incompatible = [
        _source(scope: _scope(owner: 'g:DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD')),
        _source(scope: _scope(incarnation: _otherIncarnation)),
        _source(),
        source.withAccount(_account()..['calendarId'] = 'replacement-calendar'),
      ];
      for (final next in incompatible) {
        expect(
          OAuthOwnedEventsRecord.parse(cache.encode(), source: next),
          isNull,
        );
      }
      for (final key in [
        'scopedOwner',
        'oauthIncarnation',
        'sourceIncarnation',
      ]) {
        final json = _eventsEnvelope(source, [_event()])
          ..[key] = _otherIncarnation;
        expect(
          OAuthOwnedEventsRecord.parse(jsonEncode(json), source: source),
          isNull,
          reason: key,
        );
      }
      expect(
        OAuthOwnedEventsRecord.parse(cache.encode(), source: source),
        isNotNull,
      );
    },
  );

  test(
    'OWC-19 older event cache revisions remain valid without rewriting provenance',
    () {
      final source = _source();
      final cache = OAuthOwnedEventsRecord.create(
        source: source,
        events: [_event()],
      );
      final edited = source.withAccount(_account()..['displayName'] = 'Edited');
      final rotated = source.withAccount(
        _account()..['accessToken'] = 'rotated',
      );
      final both = edited.withAccount(
        Map<String, Object?>.of(edited.account)..['accessToken'] = 'rotated',
      );
      for (final current in [edited, rotated, both]) {
        final parsed = OAuthOwnedEventsRecord.parse(
          cache.encode(),
          source: current,
        )!;
        expect(parsed.sourceIncarnation, source.sourceIncarnation);
        expect(parsed.metadataRevision, 1);
        expect(parsed.credentialRevision, 1);
        expect(parsed.encode(), cache.encode());
      }
      final currentCache = OAuthOwnedEventsRecord.create(
        source: both,
        events: [_event()],
      );
      expect(currentCache.metadataRevision, 2);
      expect(currentCache.credentialRevision, 2);
      expect(
        OAuthOwnedEventsRecord.parse(currentCache.encode(), source: both),
        isNotNull,
      );
    },
  );

  test(
    'OWC-20 event envelope rejects future revisions and invalid schema or stamps',
    () {
      final source = _source().withAccount(
        _account()
          ..['displayName'] = 'Edited'
          ..['accessToken'] = 'rotated',
      );
      final invalidFields = <String, List<Object?>>{
        'schema': [null, 1, 3, 2.0, '2'],
        'scopedOwner': [null, 1],
        'oauthIncarnation': [null, 1],
        'sourceAccountId': [null, 1, 'different-account'],
        'sourceIncarnation': [null, 1, 'short'],
        'metadataRevision': [null, 0, -1, 1.0, '1', 3, _maximumRevision + 1],
        'credentialRevision': [null, 0, -1, 1.0, '1', 3, _maximumRevision + 1],
        'events': [null, {}, 'events'],
      };
      for (final entry in invalidFields.entries) {
        for (final value in entry.value) {
          final json = _eventsEnvelope(source, [_event()])..[entry.key] = value;
          expect(
            OAuthOwnedEventsRecord.parse(jsonEncode(json), source: source),
            isNull,
            reason: '${entry.key}: $value',
          );
        }
      }
      for (final key in _eventsEnvelope(source, []).keys) {
        final json = _eventsEnvelope(source, [])..remove(key);
        expect(
          OAuthOwnedEventsRecord.parse(jsonEncode(json), source: source),
          isNull,
          reason: 'missing $key',
        );
      }
      final extra = _eventsEnvelope(source, [])..['unknown'] = 1;
      expect(
        OAuthOwnedEventsRecord.parse(jsonEncode(extra), source: source),
        isNull,
      );
      for (final raw in ['null', '[]', 'false', '{', '']) {
        expect(OAuthOwnedEventsRecord.parse(raw, source: source), isNull);
      }
      final futureCache = OAuthOwnedEventsRecord.create(
        source: source,
        events: [_event()],
      );
      final previousEnvelope = _sourceEnvelope(source)
        ..['metadataRevision'] = 1
        ..['credentialRevision'] = 1;
      final previous = OAuthOwnedSourceRecord.parse(
        jsonEncode(previousEnvelope),
        scope: _scope(),
      )!;
      expect(
        OAuthOwnedEventsRecord.parse(futureCache.encode(), source: previous),
        isNull,
      );
    },
  );

  test(
    'OWC-21 event rows reject invalid types duplicate IDs and noncanonical JSON',
    () {
      final source = _source();
      final invalidFields = <String, List<Object?>>{
        'id': [null, '', ' ', 1],
        'title': [null, 1],
        'date': [null, 1, 'invalid', '2026-11-10', '2026-11-10T09:00:00Z'],
        'endDate': [1, 'invalid', '2026-11-10'],
        'subtitle': [1, false],
        'colorValue': [null, -1, 0x100000000, 1.0, '1'],
        'sourceId': [1, false],
        'timeHour': [null, -1, 24, 1.0, '9'],
        'timeMinute': [null, -1, 60, 1.0, '0'],
      };
      for (final entry in invalidFields.entries) {
        for (final value in entry.value) {
          final event = _event()..[entry.key] = value;
          expect(
            OAuthOwnedEventsRecord.parse(
              jsonEncode(_eventsEnvelope(source, [event])),
              source: source,
            ),
            isNull,
            reason: '${entry.key}: $value',
          );
        }
      }
      for (final key in _event().keys) {
        final event = _event()..remove(key);
        expect(
          OAuthOwnedEventsRecord.parse(
            jsonEncode(_eventsEnvelope(source, [event])),
            source: source,
          ),
          isNull,
          reason: 'missing event $key',
        );
      }
      final extra = _event()..['type'] = 'remote';
      final mismatchedTime = _event()..['timeHour'] = null;
      for (final events in [
        [extra],
        [mismatchedTime],
        [_event(), _event()],
      ]) {
        expect(
          OAuthOwnedEventsRecord.parse(
            jsonEncode(_eventsEnvelope(source, events)),
            source: source,
          ),
          isNull,
        );
        expect(
          () => OAuthOwnedEventsRecord.create(source: source, events: events),
          throwsA(isA<OAuthWorkspaceCodecException>()),
        );
      }
      for (final badRow in [null, false, [], 'event']) {
        final json = _eventsEnvelope(source, [])
          ..['events'] = [_event(), badRow];
        expect(
          OAuthOwnedEventsRecord.parse(jsonEncode(json), source: source),
          isNull,
        );
      }
      final raw = jsonEncode(_eventsEnvelope(source, [_event()]));
      final reversed = Map<String, Object?>.fromEntries(
        _eventsEnvelope(source, [_event()]).entries.toList().reversed,
      );
      final reorderedRow = Map<String, Object?>.fromEntries(
        _event().entries.toList().reversed,
      );
      for (final malformed in [
        ' $raw',
        '$raw\n',
        raw.replaceFirst('"schema":2', '"schema":2,"schema":2'),
        raw.replaceFirst(
          '"title":"Codec meeting"',
          '"title":"ignored","title":"Codec meeting"',
        ),
        jsonEncode(reversed),
        jsonEncode(_eventsEnvelope(source, [reorderedRow])),
      ]) {
        expect(OAuthOwnedEventsRecord.parse(malformed, source: source), isNull);
      }
    },
  );

  test(
    'OWC-22 events copy inputs freeze nested maps and return fresh toJson maps',
    () {
      final source = _source();
      final event = _event();
      final input = [event];
      final cache = OAuthOwnedEventsRecord.create(
        source: source,
        events: input,
      );
      final before = cache.encode();
      event['title'] = 'Input mutation';
      input.clear();
      expect(cache.events, [_event()]);
      final parsed = OAuthOwnedEventsRecord.parse(before, source: source)!;
      for (final record in [cache, parsed]) {
        expect(() => record.events.add(_event()), throwsUnsupportedError);
        expect(() => record.events.clear(), throwsUnsupportedError);
        expect(() => record.events[0] = _event(), throwsUnsupportedError);
        expect(
          () => record.events.single['title'] = 'Mutation',
          throwsUnsupportedError,
        );
        expect(() => record.events.single.remove('id'), throwsUnsupportedError);
        final first = record.toJson();
        final second = record.toJson();
        expect(first, _eventsEnvelope(source, [_event()]));
        expect(first, isNot(same(second)));
        first['events'] = [];
        second['schema'] = 99;
        expect(record.encode(), before);
        expect(
          record.toJson().keys.toList(),
          _eventsEnvelope(source, []).keys.toList(),
        );
        expect(record.toJson(), _eventsEnvelope(source, [_event()]));
      }
    },
  );

  test(
    'OWC-23 copied source incarnation cannot adopt another account cache',
    () {
      final first = _source();
      final cache = OAuthOwnedEventsRecord.create(
        source: first,
        events: [_event()],
      );
      // Deliberately malformed ownership data, not a legitimate source mutation.
      final copied = _sourceEnvelope(first)
        ..['account'] = (_account()
          ..['id'] = 'different-account'
          ..['calendarId'] = 'different-calendar');
      final second = OAuthOwnedSourceRecord.parse(
        jsonEncode(copied),
        scope: _scope(),
      )!;
      expect(second.sourceIncarnation, first.sourceIncarnation);
      expect(
        OAuthOwnedSourceRecord.parseList(
          jsonEncode([first.toJson(), copied]),
          scope: _scope(),
        ),
        isNull,
      );
      expect(
        OAuthOwnedEventsRecord.parse(cache.encode(), source: second),
        isNull,
      );
      expect(cache.sourceAccountId, first.account['id']);
      expect(
        OAuthOwnedEventsRecord.parse(cache.encode(), source: first),
        isNotNull,
      );
      final properSecond = first.withAccount(
        _account()..['id'] = 'different-account',
      );
      expect(properSecond.sourceIncarnation, isNot(first.sourceIncarnation));
      expect(
        OAuthOwnedSourceRecord.parseList(
          jsonEncode([first.toJson(), properSecond.toJson()]),
          scope: _scope(),
        ),
        hasLength(2),
      );
    },
  );
}
