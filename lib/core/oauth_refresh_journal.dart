import 'dart:convert';

import 'oauth_calendar_storage.dart';
import 'oauth_calendar_workspace_codec.dart';

enum OAuthRefreshPhase { dispatched, received }

/// Frozen refresh data. Parsing never authorizes a request or a storage write.
final class OAuthOwnedRefreshJournal {
  final OAuthScopedOwnerRecord _scope;
  final String operationId;
  final String receiptHandle;
  final OAuthOwnedSourceRecord originalSource;
  final OAuthRefreshPhase phase;
  final DateTime dispatchedAt;
  final DateTime? receivedAt;
  final OAuthOwnedSourceRecord? returnedSource;

  OAuthOwnedRefreshJournal._({
    required OAuthScopedOwnerRecord scope,
    required this.operationId,
    required this.receiptHandle,
    required this.originalSource,
    required this.phase,
    required this.dispatchedAt,
    this.receivedAt,
    this.returnedSource,
  }) : _scope = scope;

  String get scopedOwner => _scope.scopedOwner;
  String get oauthIncarnation => _scope.oauthIncarnation;
  String get sourceAccountId => originalSource.account['id']! as String;

  factory OAuthOwnedRefreshJournal.createDispatched({
    required OAuthScopedOwnerRecord scope,
    required String operationId,
    required String receiptHandle,
    required OAuthOwnedSourceRecord originalSource,
    required DateTime dispatchedAt,
  }) {
    if (!_validIdentity(operationId) ||
        !_validIdentity(receiptHandle) ||
        !dispatchedAt.isUtc ||
        !_validSource(originalSource, scope)) {
      throw const OAuthWorkspaceCodecException();
    }
    final result = OAuthOwnedRefreshJournal._(
      scope: scope,
      operationId: operationId,
      receiptHandle: receiptHandle,
      originalSource: originalSource,
      phase: OAuthRefreshPhase.dispatched,
      dispatchedAt: dispatchedAt,
    );
    result._requireSize();
    return result;
  }

  OAuthOwnedRefreshJournal received({
    required OAuthOwnedSourceRecord returnedSource,
    required DateTime receivedAt,
  }) {
    if (phase != OAuthRefreshPhase.dispatched ||
        !receivedAt.isUtc ||
        receivedAt.isBefore(dispatchedAt) ||
        !_validSource(returnedSource, _scope) ||
        !_validPair(originalSource, returnedSource)) {
      throw const OAuthWorkspaceCodecException();
    }
    final result = OAuthOwnedRefreshJournal._(
      scope: _scope,
      operationId: operationId,
      receiptHandle: receiptHandle,
      originalSource: originalSource,
      phase: OAuthRefreshPhase.received,
      dispatchedAt: dispatchedAt,
      receivedAt: receivedAt,
      returnedSource: returnedSource,
    );
    result._requireSize();
    return result;
  }

  Map<String, Object?> toJson() => {
    'schema': 1,
    'kind': 'refresh',
    'scopedOwner': scopedOwner,
    'oauthIncarnation': oauthIncarnation,
    'operationId': operationId,
    'receiptHandle': receiptHandle,
    'sourceAccountId': sourceAccountId,
    'originalSource': originalSource.toJson(),
    'phase': phase.name,
    'dispatchedAt': dispatchedAt.toIso8601String(),
    'receivedAt': receivedAt?.toIso8601String(),
    'returnedSource': returnedSource?.toJson(),
  };

  String encode() => jsonEncode(toJson());

  static OAuthOwnedRefreshJournal? parse(
    String raw, {
    required OAuthScopedOwnerRecord scope,
  }) {
    // Bound the complete input before decoding unknown nested content.
    if (raw.length > _maximumRawBytes ||
        utf8.encode(raw).length > _maximumRawBytes) {
      return null;
    }
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.length != _journalKeys.length ||
          !_journalKeys.every(value.containsKey) ||
          value['schema'] is! int ||
          value['schema'] != 1 ||
          value['kind'] != 'refresh' ||
          value['scopedOwner'] != scope.scopedOwner ||
          value['oauthIncarnation'] != scope.oauthIncarnation ||
          !_validIdentity(value['operationId']) ||
          !_validIdentity(value['receiptHandle']) ||
          value['sourceAccountId'] is! String ||
          value['originalSource'] is! Map<String, dynamic>) {
        return null;
      }
      final original = OAuthOwnedSourceRecord.parse(
        jsonEncode(value['originalSource']),
        scope: scope,
      );
      final dispatched = _utcDate(value['dispatchedAt']);
      if (original == null ||
          dispatched == null ||
          value['sourceAccountId'] != original.account['id']) {
        return null;
      }
      var result = OAuthOwnedRefreshJournal.createDispatched(
        scope: scope,
        operationId: value['operationId'] as String,
        receiptHandle: value['receiptHandle'] as String,
        originalSource: original,
        dispatchedAt: dispatched,
      );
      if (value['phase'] == OAuthRefreshPhase.dispatched.name) {
        if (value['receivedAt'] != null || value['returnedSource'] != null) {
          return null;
        }
      } else if (value['phase'] == OAuthRefreshPhase.received.name) {
        final receivedTime = _utcDate(value['receivedAt']);
        if (receivedTime == null ||
            value['returnedSource'] is! Map<String, dynamic>) {
          return null;
        }
        final returned = OAuthOwnedSourceRecord.parse(
          jsonEncode(value['returnedSource']),
          scope: scope,
        );
        if (returned == null) return null;
        result = result.received(
          returnedSource: returned,
          receivedAt: receivedTime,
        );
      } else {
        return null;
      }
      // Compare the whole original raw: nested duplicate keys must not become
      // acceptable merely because jsonDecode collapsed them into a map.
      return result.encode() == raw ? result : null;
    } catch (_) {
      return null;
    }
  }

  bool matchesOriginalSource(OAuthOwnedSourceRecord actual) =>
      actual.encode() == originalSource.encode();

  bool matchesReturnedSource(OAuthOwnedSourceRecord actual) =>
      returnedSource != null && actual.encode() == returnedSource!.encode();

  void _requireSize() {
    if (!_boundedString(scopedOwner) ||
        !_boundedString(oauthIncarnation) ||
        !_boundedString(sourceAccountId) ||
        utf8.encode(encode()).length > _maximumRawBytes) {
      throw const OAuthWorkspaceCodecException();
    }
  }

  @override
  String toString() => 'OAuthOwnedRefreshJournal(${phase.name})';
}

const _maximumRawBytes = 262144;
const _maximumSourceBytes = 131072;
const _maximumStringBytes = 16384;
const _maximumRevision = 9007199254740991;
const _journalKeys = [
  'schema',
  'kind',
  'scopedOwner',
  'oauthIncarnation',
  'operationId',
  'receiptHandle',
  'sourceAccountId',
  'originalSource',
  'phase',
  'dispatchedAt',
  'receivedAt',
  'returnedSource',
];
const _credentialKeys = ['accessToken', 'refreshToken', 'expiresAt', 'scope'];

bool _validIdentity(Object? value) =>
    value is String &&
    value.length == 64 &&
    RegExp(r'^[A-Za-z0-9_-]{64}$').hasMatch(value);

bool _boundedString(String value) =>
    value.length <= _maximumStringBytes &&
    utf8.encode(value).length <= _maximumStringBytes;

DateTime? _utcDate(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.isUtc && parsed.toIso8601String() == value
      ? parsed
      : null;
}

bool _validSource(OAuthOwnedSourceRecord source, OAuthScopedOwnerRecord scope) {
  final encoded = source.encode();
  if (utf8.encode(encoded).length > _maximumSourceBytes ||
      OAuthOwnedSourceRecord.parse(encoded, scope: scope) == null ||
      source.account['refreshToken'] is! String ||
      (source.account['refreshToken']! as String).trim().isEmpty) {
    return false;
  }
  // Only the known, validated shallow source/account fields contain strings.
  return source.toJson().values.whereType<String>().every(_boundedString) &&
      source.account.values.whereType<String>().every(_boundedString);
}

bool _validPair(
  OAuthOwnedSourceRecord original,
  OAuthOwnedSourceRecord returned,
) {
  if (returned.scopedOwner != original.scopedOwner ||
      returned.oauthIncarnation != original.oauthIncarnation ||
      returned.sourceIncarnation != original.sourceIncarnation ||
      returned.metadataRevision != original.metadataRevision ||
      _utcDate(returned.account['expiresAt']) == null ||
      original.account.keys.any(
        (key) =>
            !_credentialKeys.contains(key) &&
            original.account[key] != returned.account[key],
      )) {
    return false;
  }
  final changed = _credentialKeys.any(
    (key) => original.account[key] != returned.account[key],
  );
  if (changed && original.credentialRevision == _maximumRevision) return false;
  return returned.credentialRevision ==
      original.credentialRevision + (changed ? 1 : 0);
}
