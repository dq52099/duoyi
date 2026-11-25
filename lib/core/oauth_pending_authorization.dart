import 'dart:convert';

import 'oauth_calendar_storage.dart';
import 'oauth_calendar_workspace_codec.dart';

enum OAuthPendingPhase { prepared, dispatched, received }

/// Durable attempt data. An Auth-issued scope lease is still required for every
/// read, dispatch and commit; decoding this record never grants authority.
final class OAuthOwnedPendingAuthorization {
  final String scopedOwner;
  final String oauthIncarnation;
  final String attemptId;
  final Map<String, String> draft;
  final DateTime savedAt;
  final OAuthPendingPhase phase;
  final String? codeFingerprint;
  final String? sourceAccountId;
  final String? receiptHandle;
  final OAuthOwnedSourceRecord? receivedSource;

  OAuthOwnedPendingAuthorization._({
    required this.scopedOwner,
    required this.oauthIncarnation,
    required this.attemptId,
    required Map<String, String> draft,
    required this.savedAt,
    required this.phase,
    this.codeFingerprint,
    this.sourceAccountId,
    this.receiptHandle,
    this.receivedSource,
  }) : draft = Map.unmodifiable(draft);

  factory OAuthOwnedPendingAuthorization.create({
    required OAuthScopedOwnerRecord scope,
    required String attemptId,
    required Map<String, String> draft,
    required DateTime savedAt,
  }) {
    if (!_attempt(attemptId) || !_validDraft(draft)) {
      throw const OAuthWorkspaceCodecException();
    }
    return OAuthOwnedPendingAuthorization._(
      scopedOwner: scope.scopedOwner,
      oauthIncarnation: scope.oauthIncarnation,
      attemptId: attemptId,
      draft: {for (final key in _draftKeys) key: draft[key]!},
      savedAt: savedAt.toUtc(),
      phase: OAuthPendingPhase.prepared,
    );
  }

  bool canDispatchAt(DateTime now) {
    final age = now.toUtc().difference(savedAt);
    return phase == OAuthPendingPhase.prepared &&
        age >= Duration.zero &&
        age <= const Duration(minutes: 15);
  }

  OAuthOwnedPendingAuthorization dispatched({
    required String fingerprint,
    required String accountId,
  }) {
    if (phase != OAuthPendingPhase.prepared ||
        !_fingerprint(fingerprint) ||
        !_attempt(accountId)) {
      throw const OAuthWorkspaceCodecException();
    }
    return OAuthOwnedPendingAuthorization._(
      scopedOwner: scopedOwner,
      oauthIncarnation: oauthIncarnation,
      attemptId: attemptId,
      draft: draft,
      savedAt: savedAt,
      phase: OAuthPendingPhase.dispatched,
      codeFingerprint: fingerprint,
      sourceAccountId: accountId,
    );
  }

  OAuthOwnedPendingAuthorization received({
    required OAuthOwnedSourceRecord source,
    required String handle,
  }) {
    if (phase != OAuthPendingPhase.dispatched ||
        !_attempt(handle) ||
        !_matchesSource(source)) {
      throw const OAuthWorkspaceCodecException();
    }
    return OAuthOwnedPendingAuthorization._(
      scopedOwner: scopedOwner,
      oauthIncarnation: oauthIncarnation,
      attemptId: attemptId,
      draft: draft,
      savedAt: savedAt,
      phase: OAuthPendingPhase.received,
      codeFingerprint: codeFingerprint,
      sourceAccountId: sourceAccountId,
      receiptHandle: handle,
      receivedSource: source,
    );
  }

  bool _matchesSource(OAuthOwnedSourceRecord source) =>
      source.scopedOwner == scopedOwner &&
      source.oauthIncarnation == oauthIncarnation &&
      source.account['id'] == sourceAccountId &&
      const [
        'provider',
        'displayName',
        'clientId',
        'clientSecret',
        'redirectUri',
        'calendarId',
      ].every((key) => source.account[key] == draft[key]);

  Map<String, Object?> toJson() => {
    'schema': 2,
    'scopedOwner': scopedOwner,
    'oauthIncarnation': oauthIncarnation,
    'attemptId': attemptId,
    'draft': draft,
    'savedAt': savedAt.toIso8601String(),
    'phase': phase.name,
    'codeFingerprint': codeFingerprint,
    'sourceAccountId': sourceAccountId,
    'receiptHandle': receiptHandle,
    'receivedSource': receivedSource?.toJson(),
  };
  String encode() => jsonEncode(toJson());

  static OAuthOwnedPendingAuthorization? parse(
    String raw, {
    required OAuthScopedOwnerRecord scope,
  }) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.length != _keys.length ||
          !_keys.every(value.containsKey) ||
          value['schema'] != 2 ||
          value['schema'] is! int ||
          value['scopedOwner'] != scope.scopedOwner ||
          value['oauthIncarnation'] != scope.oauthIncarnation ||
          !_attempt(value['attemptId']) ||
          !_validDraft(value['draft'])) {
        return null;
      }
      final date = DateTime.tryParse(
        value['savedAt'] is String ? value['savedAt'] : '',
      );
      if (date == null ||
          !date.isUtc ||
          date.toIso8601String() != value['savedAt']) {
        return null;
      }
      final phase = OAuthPendingPhase.values
          .where((p) => p.name == value['phase'])
          .firstOrNull;
      if (phase == null) return null;
      final received = value['receivedSource'] == null
          ? null
          : OAuthOwnedSourceRecord.parse(
              jsonEncode(value['receivedSource']),
              scope: scope,
            );
      if (phase == OAuthPendingPhase.prepared) {
        if (value['codeFingerprint'] != null ||
            value['sourceAccountId'] != null ||
            value['receiptHandle'] != null ||
            value['receivedSource'] != null) {
          return null;
        }
      } else {
        if (!_fingerprint(value['codeFingerprint']) ||
            !_attempt(value['sourceAccountId'])) {
          return null;
        }
        if (phase == OAuthPendingPhase.dispatched
            ? value['receiptHandle'] != null || value['receivedSource'] != null
            : !_attempt(value['receiptHandle']) || received == null) {
          return null;
        }
      }
      final result = OAuthOwnedPendingAuthorization._(
        scopedOwner: scope.scopedOwner,
        oauthIncarnation: scope.oauthIncarnation,
        attemptId: value['attemptId'],
        draft: {
          for (final key in _draftKeys) key: value['draft'][key] as String,
        },
        savedAt: date,
        phase: phase,
        codeFingerprint: value['codeFingerprint'],
        sourceAccountId: value['sourceAccountId'],
        receiptHandle: value['receiptHandle'],
        receivedSource: received,
      );
      if (received != null && !result._matchesSource(received)) return null;
      return result.encode() == raw ? result : null;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'OAuthOwnedPendingAuthorization(${phase.name})';
}

const _keys = {
  'schema',
  'scopedOwner',
  'oauthIncarnation',
  'attemptId',
  'draft',
  'savedAt',
  'phase',
  'codeFingerprint',
  'sourceAccountId',
  'receiptHandle',
  'receivedSource',
};
const _draftKeys = [
  'provider',
  'displayName',
  'clientId',
  'clientSecret',
  'redirectUri',
  'calendarId',
  'codeVerifier',
  'state',
];
bool _attempt(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9_-]{64}$').hasMatch(value);
bool _fingerprint(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
bool _validDraft(Object? raw) {
  if (raw is! Map ||
      raw.length != _draftKeys.length ||
      !_draftKeys.every((key) => raw[key] is String) ||
      !const {'google', 'outlook'}.contains(raw['provider']) ||
      (raw['clientId'] as String).trim().isEmpty ||
      (raw['calendarId'] as String).trim().isEmpty ||
      (raw['state'] as String).trim().isEmpty ||
      (raw['state'] as String).length > 256 ||
      !RegExp(r'^[A-Za-z0-9._~-]{43,128}$').hasMatch(raw['codeVerifier'])) {
    return false;
  }
  final redirect = raw['redirectUri'] as String;
  if (RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(redirect) ||
      RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(redirect)) {
    return false;
  }
  final uri = Uri.tryParse(redirect);
  return uri != null &&
      uri.hasScheme &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty &&
      !uri.authority.contains('@') &&
      (!const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
          uri.host.isNotEmpty);
}
