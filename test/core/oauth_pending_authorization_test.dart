import 'dart:convert';

import 'package:duoyi/core/oauth_calendar_inventory.dart';
import 'package:duoyi/core/oauth_calendar_storage.dart';
import 'package:duoyi/core/oauth_calendar_workspace_codec.dart';
import 'package:duoyi/core/oauth_pending_authorization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// freeze218 plus the main session's exact64 production-ID correction.
// These codec fixtures do not issue an Auth capability.
// Prepared statically for219; this worker did not run or format this file.
const _owner = 'g:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _incarnation = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const _foreignOwner = 'g:CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
const _foreignIncarnation = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD';
final _savedAt = DateTime.utc(2026, 11, 10, 12);
final _attemptId = _repeat('A', 64);
final _accountId = _repeat('B', 64);
final _handle = _repeat('C', 64);
final _fingerprint = _repeat('a', 64);

String _repeat(String value, int count) => List.filled(count, value).join();

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

Map<String, String> _draft() => {
  'provider': 'google',
  'displayName': 'Pending219 calendar',
  'clientId': 'synthetic-client219',
  'clientSecret': 'synthetic-secret219',
  'redirectUri': 'duoyi://oauth/calendar',
  'calendarId': 'primary',
  'codeVerifier': _repeat('V', 64),
  'state': 'synthetic-state219',
};

Map<String, Object?> _account() => {
  'id': _accountId,
  'provider': 'google',
  'displayName': 'Pending219 calendar',
  'clientId': 'synthetic-client219',
  'clientSecret': 'synthetic-secret219',
  'redirectUri': 'duoyi://oauth/calendar',
  'calendarId': 'primary',
  'accessToken': 'synthetic-access219',
  'refreshToken': 'synthetic-refresh219',
  'expiresAt': '2026-11-10T13:00:00.000Z',
  'scope': 'calendar.readonly',
  'colorValue': 0xff336699,
  'enabled': true,
  'lastSyncedAt': null,
};

OAuthOwnedSourceRecord _source({
  OAuthScopedOwnerRecord? scope,
  Map<String, Object?>? changes,
}) => OAuthOwnedSourceRecord.create(
  scope: scope ?? _scope(),
  account: {..._account(), ...?changes},
);

OAuthOwnedPendingAuthorization _prepared({
  Map<String, String>? draft,
  DateTime? savedAt,
}) => OAuthOwnedPendingAuthorization.create(
  scope: _scope(),
  attemptId: _attemptId,
  draft: draft ?? _draft(),
  savedAt: savedAt ?? _savedAt,
);

OAuthOwnedPendingAuthorization _dispatched() =>
    _prepared().dispatched(fingerprint: _fingerprint, accountId: _accountId);

OAuthOwnedPendingAuthorization _received() =>
    _dispatched().received(source: _source(), handle: _handle);

Map<String, dynamic> _envelope(OAuthOwnedPendingAuthorization pending) =>
    jsonDecode(pending.encode()) as Map<String, dynamic>;

OAuthOwnedPendingAuthorization? _parse(String raw) =>
    OAuthOwnedPendingAuthorization.parse(raw, scope: _scope());

Matcher get _rejected => throwsA(isA<OAuthWorkspaceCodecException>());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OPA219-01 prepared canonical roundtrip preserves the frozen draft', () {
    final pending = _prepared();
    final parsed = _parse(pending.encode())!;
    expect(parsed.phase, OAuthPendingPhase.prepared);
    expect(parsed.scopedOwner, _owner);
    expect(parsed.oauthIncarnation, _incarnation);
    expect(parsed.attemptId, _attemptId);
    expect(parsed.draft, _draft());
    expect(parsed.savedAt, _savedAt);
    expect(parsed.codeFingerprint, isNull);
    expect(parsed.sourceAccountId, isNull);
    expect(parsed.receiptHandle, isNull);
    expect(parsed.receivedSource, isNull);
    expect(parsed.encode(), pending.encode());
  });

  test('OPA219-02 dispatched roundtrip retains the original attempt', () {
    final pending = _dispatched();
    final parsed = _parse(pending.encode())!;
    expect(parsed.phase, OAuthPendingPhase.dispatched);
    expect(parsed.attemptId, _attemptId);
    expect(parsed.draft, _draft());
    expect(parsed.savedAt, _savedAt);
    expect(parsed.codeFingerprint, _fingerprint);
    expect(parsed.sourceAccountId, _accountId);
    expect(parsed.receiptHandle, isNull);
    expect(parsed.receivedSource, isNull);
    expect(parsed.encode(), pending.encode());
  });

  test(
    'OPA219-03 received roundtrip retains credentials and receipt identity',
    () {
      final pending = _received();
      final parsed = _parse(pending.encode())!;
      expect(parsed.phase, OAuthPendingPhase.received);
      expect(parsed.attemptId, _attemptId);
      expect(parsed.draft, _draft());
      expect(parsed.savedAt, _savedAt);
      expect(parsed.codeFingerprint, _fingerprint);
      expect(parsed.sourceAccountId, _accountId);
      expect(parsed.receiptHandle, _handle);
      expect(parsed.receivedSource!.account, _account());
      expect(
        parsed.receivedSource!.sourceIncarnation,
        pending.receivedSource!.sourceIncarnation,
      );
      expect(parsed.encode(), pending.encode());
    },
  );

  test(
    'OPA219-04 envelope rejects missing extra malformed and unknown fields',
    () {
      final pending = _prepared();
      for (final key in _envelope(pending).keys) {
        final value = _envelope(pending)..remove(key);
        expect(_parse(jsonEncode(value)), isNull, reason: 'missing $key');
      }
      final extra = _envelope(pending)..['unknown'] = false;
      expect(_parse(jsonEncode(extra)), isNull);
      for (final schema in <Object?>[null, 1, 3, 2.0, '2', true]) {
        final value = _envelope(pending)..['schema'] = schema;
        expect(_parse(jsonEncode(value)), isNull, reason: 'schema $schema');
      }
      for (final phase in <Object?>[
        null,
        '',
        'Prepared',
        'committed',
        0,
        true,
      ]) {
        final value = _envelope(pending)..['phase'] = phase;
        expect(_parse(jsonEncode(value)), isNull, reason: 'phase $phase');
      }
      for (final raw in ['', '{', 'null', '[]', 'true', '42', '"record"']) {
        expect(_parse(raw), isNull, reason: 'non-envelope $raw');
      }
    },
  );

  test('OPA219-05 prepared rejects every dispatch and receipt payload', () {
    final values = <String, Object?>{
      'codeFingerprint': _fingerprint,
      'sourceAccountId': _accountId,
      'receiptHandle': _handle,
      'receivedSource': _source().toJson(),
    };
    for (final entry in values.entries) {
      final value = _envelope(_prepared())..[entry.key] = entry.value;
      expect(_parse(jsonEncode(value)), isNull, reason: entry.key);
    }
  });

  test(
    'OPA219-06 dispatched requires dispatch identity and forbids receipts',
    () {
      final pending = _dispatched();
      for (final key in ['codeFingerprint', 'sourceAccountId']) {
        final value = _envelope(pending)..[key] = null;
        expect(_parse(jsonEncode(value)), isNull, reason: 'required $key');
      }
      for (final entry in <String, Object?>{
        'receiptHandle': _handle,
        'receivedSource': _source().toJson(),
      }.entries) {
        final value = _envelope(pending)..[entry.key] = entry.value;
        expect(
          _parse(jsonEncode(value)),
          isNull,
          reason: 'forbidden ${entry.key}',
        );
      }
    },
  );

  test('OPA219-07 received requires a complete typed receipt and source', () {
    final pending = _received();
    for (final key in [
      'codeFingerprint',
      'sourceAccountId',
      'receiptHandle',
      'receivedSource',
    ]) {
      final value = _envelope(pending)..[key] = null;
      expect(_parse(jsonEncode(value)), isNull, reason: 'required $key');
    }
    for (final badSource in <Object?>[{}, [], 'source', _account(), true]) {
      final value = _envelope(pending)..['receivedSource'] = badSource;
      expect(_parse(jsonEncode(value)), isNull);
    }
    final value = _envelope(pending);
    (value['receivedSource'] as Map<String, dynamic>)['sourceIncarnation'] =
        'invalid-source';
    expect(_parse(jsonEncode(value)), isNull);
  });

  test(
    'OPA219-08 canonical parsing rejects duplicates and alternate encodings',
    () {
      final pending = _received();
      final raw = pending.encode();
      final reversed = Map<String, Object?>.fromEntries(
        pending.toJson().entries.toList().reversed,
      );
      final reorderedDraft = _envelope(pending);
      reorderedDraft['draft'] = Map<String, dynamic>.fromEntries(
        (reorderedDraft['draft'] as Map<String, dynamic>).entries
            .toList()
            .reversed,
      );
      final alternatives = [
        ' $raw',
        '$raw\n',
        const JsonEncoder.withIndent('  ').convert(pending.toJson()),
        jsonEncode(reversed),
        jsonEncode(reorderedDraft),
        raw.replaceFirst('"schema":2', '"schema":1,"schema":2'),
        raw.replaceFirst('"state":', '"state":null,"state":'),
        raw.replaceFirst(
          '"receivedSource":{"schema":2',
          '"receivedSource":{"schema":1,"schema":2',
        ),
        raw.replaceFirst('"account":{"id":', '"account":{"id":null,"id":'),
        raw.replaceFirst('"attemptId":', '"attemptId":null,"attemptId":'),
        raw.replaceFirst('synthetic-state219', r'\u0073ynthetic-state219'),
      ];
      expect(_parse(raw), isNotNull);
      for (var i = 0; i < alternatives.length; i++) {
        expect(
          alternatives[i],
          isNot(raw),
          reason: 'fixture $i must change bytes',
        );
        expect(
          _parse(alternatives[i]),
          isNull,
          reason: 'alternate encoding $i',
        );
      }
    },
  );

  test('OPA219-09 every phase rejects foreign owner and OAuth incarnation', () {
    for (final pending in [_prepared(), _dispatched(), _received()]) {
      final raw = pending.encode();
      expect(_parse(raw), isNotNull);
      expect(
        OAuthOwnedPendingAuthorization.parse(
          raw,
          scope: _scope(owner: _foreignOwner),
        ),
        isNull,
      );
      expect(
        OAuthOwnedPendingAuthorization.parse(
          raw,
          scope: _scope(incarnation: _foreignIncarnation),
        ),
        isNull,
      );
      for (final key in ['scopedOwner', 'oauthIncarnation']) {
        for (final bad in <Object?>[null, 7, '']) {
          final value = _envelope(pending)..[key] = bad;
          expect(_parse(jsonEncode(value)), isNull, reason: '$key $bad');
        }
      }
    }
  });

  test(
    'OPA219-10 attempt fingerprint account and handle shapes are strict',
    () {
      final badIds = [
        '',
        _repeat('A', 43),
        _repeat('A', 63),
        _repeat('A', 65),
        '${_repeat('A', 63)}=',
      ];
      for (final id in badIds) {
        expect(
          () => OAuthOwnedPendingAuthorization.create(
            scope: _scope(),
            attemptId: id,
            draft: _draft(),
            savedAt: _savedAt,
          ),
          _rejected,
        );
        expect(
          () =>
              _prepared().dispatched(fingerprint: _fingerprint, accountId: id),
          _rejected,
        );
        expect(
          () => _dispatched().received(source: _source(), handle: id),
          _rejected,
        );
      }
      for (final fingerprint in [
        '',
        _repeat('a', 63),
        _repeat('a', 65),
        _repeat('A', 64),
        _repeat('g', 64),
      ]) {
        expect(
          () => _prepared().dispatched(
            fingerprint: fingerprint,
            accountId: _accountId,
          ),
          _rejected,
        );
      }
      for (final key in [
        'attemptId',
        'sourceAccountId',
        'receiptHandle',
        'codeFingerprint',
      ]) {
        for (final bad in <Object?>[null, 7, '', true, 'invalid']) {
          final value = _envelope(_received())..[key] = bad;
          expect(_parse(jsonEncode(value)), isNull, reason: '$key $bad');
        }
      }
      final allowedId = '${_repeat('A', 62)}_-';
      final allowed =
          OAuthOwnedPendingAuthorization.create(
            scope: _scope(),
            attemptId: allowedId,
            draft: _draft(),
            savedAt: _savedAt,
          ).dispatched(
            fingerprint: _repeat('0123456789abcdef', 4),
            accountId: allowedId,
          );
      expect(_parse(allowed.encode()), isNotNull);
    },
  );

  test(
    'OPA219-11 draft rejects missing extra wrong-type and invalid connection fields',
    () {
      for (final key in _draft().keys) {
        final missing = _draft()..remove(key);
        expect(
          () => _prepared(draft: missing),
          _rejected,
          reason: 'missing $key',
        );
        final missingValue = _envelope(_prepared());
        (missingValue['draft'] as Map<String, dynamic>).remove(key);
        expect(
          _parse(jsonEncode(missingValue)),
          isNull,
          reason: 'missing draft $key',
        );
        final value = _envelope(_prepared());
        (value['draft'] as Map<String, dynamic>)[key] = 7;
        expect(_parse(jsonEncode(value)), isNull, reason: 'wrong type $key');
      }
      expect(() => _prepared(draft: _draft()..['unknown'] = ''), _rejected);
      final extraValue = _envelope(_prepared());
      (extraValue['draft'] as Map<String, dynamic>)['unknown'] = '';
      expect(_parse(jsonEncode(extraValue)), isNull);
      for (final badDraft in <Object?>[null, {}, [], 'draft', true]) {
        final value = _envelope(_prepared())..['draft'] = badDraft;
        expect(_parse(jsonEncode(value)), isNull);
      }
      final invalid = <String, List<String>>{
        'provider': ['', 'Google', 'unknown'],
        'clientId': ['', '  '],
        'calendarId': ['', '\t'],
        'redirectUri': [
          '',
          '/relative',
          'https:///calendar',
          'https://user@example.org/callback',
          'duoyi://oauth/calendar#fragment',
          'duoyi://oauth/ca lendar',
          'duoyi://oauth/\\calendar',
          'duoyi://oauth/calendar%ZZ',
          'duoyi://oauth/calendar\u0000',
        ],
      };
      for (final entry in invalid.entries) {
        for (final bad in entry.value) {
          final draft = _draft()..[entry.key] = bad;
          expect(
            () => _prepared(draft: draft),
            _rejected,
            reason: '${entry.key} $bad',
          );
          final value = _envelope(_prepared());
          (value['draft'] as Map<String, dynamic>)[entry.key] = bad;
          expect(_parse(jsonEncode(value)), isNull);
        }
      }
      final allowed = _draft()
        ..['provider'] = 'outlook'
        ..['displayName'] = ''
        ..['clientSecret'] = ''
        ..['redirectUri'] = 'https://example.org/callback?return=%2Fcalendar';
      expect(_parse(_prepared(draft: allowed).encode()), isNotNull);
    },
  );

  test(
    'OPA219-12 PKCE accepts RFC bounds and rejects invalid verifier bytes',
    () {
      for (final verifier in [
        _repeat('A', 43),
        _repeat('V', 64),
        _repeat('z', 128),
        '${_repeat('A', 37)}._~-09',
      ]) {
        final pending = _prepared(draft: _draft()..['codeVerifier'] = verifier);
        expect(_parse(pending.encode())!.draft['codeVerifier'], verifier);
      }
      for (final verifier in [
        '',
        _repeat('A', 42),
        _repeat('A', 129),
        '${_repeat('A', 42)}=',
        '${_repeat('A', 42)}+',
        '${_repeat('A', 42)}/',
        '${_repeat('A', 42)} ',
        '${_repeat('A', 42)}中',
        '${_repeat('A', 42)}\n',
      ]) {
        expect(
          () => _prepared(draft: _draft()..['codeVerifier'] = verifier),
          _rejected,
        );
        final value = _envelope(_prepared());
        (value['draft'] as Map<String, dynamic>)['codeVerifier'] = verifier;
        expect(_parse(jsonEncode(value)), isNull);
      }
    },
  );

  test('OPA219-13 state is nonblank and bounded at 256 characters', () {
    for (final state in ['s', _repeat('S', 256)]) {
      expect(
        _parse(_prepared(draft: _draft()..['state'] = state).encode()),
        isNotNull,
      );
    }
    for (final state in ['', ' \t\n', _repeat('S', 257)]) {
      expect(() => _prepared(draft: _draft()..['state'] = state), _rejected);
      final value = _envelope(_prepared());
      (value['draft'] as Map<String, dynamic>)['state'] = state;
      expect(_parse(jsonEncode(value)), isNull);
    }
  });

  test(
    'OPA219-14 savedAt requires canonical UTC and creation normalizes local time',
    () {
      final local = DateTime(2026, 11, 10, 12);
      final pending = _prepared(savedAt: local);
      expect(pending.savedAt.isUtc, isTrue);
      expect(pending.savedAt, local.toUtc());
      expect(_parse(pending.encode())!.savedAt, local.toUtc());
      for (final date in <Object?>[
        null,
        7,
        '',
        'invalid',
        '2026-11-10T12:00:00',
        '2026-11-10T12:00:00Z',
        '2026-11-10T12:00:00.000+00:00',
        '2026-11-10T13:00:00.000+01:00',
        '2026-11-10T12:00:00.000000Z',
      ]) {
        final value = _envelope(_prepared())..['savedAt'] = date;
        expect(_parse(jsonEncode(value)), isNull, reason: 'date $date');
      }
    },
  );

  test('OPA219-15 dispatch age includes zero and fifteen minutes only', () {
    final pending = _prepared();
    expect(
      pending.canDispatchAt(_savedAt.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
    expect(pending.canDispatchAt(_savedAt), isTrue);
    expect(
      pending.canDispatchAt(_savedAt.add(const Duration(minutes: 15))),
      isTrue,
    );
    expect(
      pending.canDispatchAt(
        _savedAt.add(const Duration(minutes: 15, microseconds: 1)),
      ),
      isFalse,
    );
    expect(
      pending.canDispatchAt(_savedAt.add(const Duration(days: 1))),
      isFalse,
    );
    expect(
      pending.canDispatchAt(DateTime.parse('2026-11-10T13:00:00+01:00')),
      isTrue,
    );
    for (final consumed in [_dispatched(), _received()]) {
      expect(consumed.canDispatchAt(_savedAt), isFalse);
      expect(
        consumed.canDispatchAt(_savedAt.add(const Duration(minutes: 15))),
        isFalse,
      );
    }
  });

  test(
    'OPA219-16 phase transitions cannot skip replay or mutate predecessors',
    () {
      final prepared = _prepared();
      final preparedBytes = prepared.encode();
      expect(
        () => prepared.received(source: _source(), handle: _handle),
        _rejected,
      );
      final dispatched = prepared.dispatched(
        fingerprint: _fingerprint,
        accountId: _accountId,
      );
      final dispatchedBytes = dispatched.encode();
      final received = dispatched.received(source: _source(), handle: _handle);
      expect(
        () => dispatched.dispatched(
          fingerprint: _fingerprint,
          accountId: _accountId,
        ),
        _rejected,
      );
      expect(
        () => received.dispatched(
          fingerprint: _fingerprint,
          accountId: _accountId,
        ),
        _rejected,
      );
      expect(
        () => received.received(source: _source(), handle: _handle),
        _rejected,
      );
      expect(prepared.encode(), preparedBytes);
      expect(dispatched.encode(), dispatchedBytes);
      expect(prepared.phase, OAuthPendingPhase.prepared);
      expect(dispatched.phase, OAuthPendingPhase.dispatched);
      expect(received.phase, OAuthPendingPhase.received);
    },
  );

  test(
    'OPA219-17 received rejects foreign source scope and wrong source account',
    () {
      final wrongSources = [
        _source(scope: _scope(owner: _foreignOwner)),
        _source(scope: _scope(incarnation: _foreignIncarnation)),
        _source(changes: {'id': _repeat('E', 64)}),
      ];
      for (final source in wrongSources) {
        expect(
          () => _dispatched().received(source: source, handle: _handle),
          _rejected,
        );
        final value = _envelope(_received())
          ..['receivedSource'] = source.toJson();
        expect(_parse(jsonEncode(value)), isNull);
      }
      final wrongAccount = _envelope(_received())
        ..['sourceAccountId'] = _repeat('E', 64);
      expect(_parse(jsonEncode(wrongAccount)), isNull);
    },
  );

  test(
    'OPA219-18 received rejects every mismatched frozen connection field',
    () {
      final changes = <String, Object?>{
        'provider': 'outlook',
        'displayName': 'Different calendar',
        'clientId': 'different-client',
        'clientSecret': 'different-secret',
        'redirectUri': 'duoyi://oauth/other',
        'calendarId': 'different-calendar',
      };
      for (final entry in changes.entries) {
        final source = _source(changes: {entry.key: entry.value});
        expect(
          () => _dispatched().received(source: source, handle: _handle),
          _rejected,
          reason: entry.key,
        );
        final value = _envelope(_received())
          ..['receivedSource'] = source.toJson();
        expect(_parse(jsonEncode(value)), isNull, reason: entry.key);
        final changedDraft = _envelope(_received());
        (changedDraft['draft'] as Map<String, dynamic>)[entry.key] =
            entry.value;
        expect(
          _parse(jsonEncode(changedDraft)),
          isNull,
          reason: 'draft ${entry.key}',
        );
      }
      final allowed = _source(
        changes: {
          'accessToken': 'rotated-access219',
          'refreshToken': 'rotated-refresh219',
          'colorValue': 0xff123456,
          'enabled': false,
        },
      );
      expect(
        _parse(
          _dispatched().received(source: allowed, handle: _handle).encode(),
        ),
        isNotNull,
      );
    },
  );

  test(
    'OPA219-19 draft snapshots stay immutable through creation parsing and phases',
    () {
      final draft = _draft();
      final prepared = _prepared(draft: draft);
      final bytes = prepared.encode();
      draft['state'] = 'changed-after-creation';
      draft['clientId'] = 'changed-after-creation';
      draft.clear();
      expect(prepared.draft, _draft());
      expect(prepared.encode(), bytes);
      final dispatched = prepared.dispatched(
        fingerprint: _fingerprint,
        accountId: _accountId,
      );
      final received = dispatched.received(source: _source(), handle: _handle);
      for (final pending in [
        prepared,
        dispatched,
        received,
        _parse(received.encode())!,
      ]) {
        final before = pending.encode();
        expect(
          () => pending.draft['state'] = 'overwrite',
          throwsUnsupportedError,
        );
        expect(() => pending.draft.remove('state'), throwsUnsupportedError);
        expect(() => pending.draft.clear(), throwsUnsupportedError);
        final json = pending.toJson();
        expect(
          () => (json['draft'] as Map<String, String>)['state'] = 'overwrite',
          throwsUnsupportedError,
        );
        json['draft'] = <String, String>{};
        expect(pending.encode(), before);
        expect(pending.draft, _draft());
      }
    },
  );

  test(
    'OPA219-20 expired received restores in inventory without reopening dispatch',
    () async {
      final received = _received();
      final raw = received.encode();
      final muchLater = _savedAt.add(const Duration(days: 30));
      final parsed = _parse(raw)!;
      expect(parsed.phase, OAuthPendingPhase.received);
      expect(parsed.receiptHandle, _handle);
      expect(parsed.receivedSource!.account, _account());
      expect(parsed.canDispatchAt(muchLater), isFalse);
      expect(
        () =>
            parsed.dispatched(fingerprint: _fingerprint, accountId: _accountId),
        _rejected,
      );
      final fixture = <String, Object>{
        OAuthCalendarStorage.scopeOwnerKey: _scope().encode(),
        OAuthCalendarStorage.pendingAuthorizationKey: raw,
        'todos': '[{"id":"ordinary219","title":"keep"}]',
      };
      SharedPreferences.setMockInitialValues(fixture);
      final preferences = await SharedPreferences.getInstance();
      final before = {
        for (final key in preferences.getKeys()) key: preferences.get(key),
      };
      final epoch = OAuthCalendarStorage.epoch;
      final reset = OAuthCalendarStorage.resetRevision;
      // An uncommitted received source lives inside pending; accounts may be absent.
      expect(OAuthCalendarInventory.validate(preferences, _scope()), isEmpty);
      expect({
        for (final key in preferences.getKeys()) key: preferences.get(key),
      }, before);
      expect(
        preferences.getString(OAuthCalendarStorage.pendingAuthorizationKey),
        raw,
      );
      expect(OAuthCalendarStorage.epoch, epoch);
      expect(OAuthCalendarStorage.resetRevision, reset);
      // Age gates dispatch, not durable decoding, for all three phases.
      for (final pending in [_prepared(), _dispatched(), received]) {
        final restored = _parse(pending.encode())!;
        expect(restored.encode(), pending.encode());
        expect(restored.canDispatchAt(muchLater), isFalse);
      }
    },
  );
}
