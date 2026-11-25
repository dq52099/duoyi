import 'dart:convert';
import 'dart:math';

import 'oauth_calendar_storage.dart';

/// Durable source data, never an Auth capability. Consumers must separately
/// capture the real issuer's lease and compare its storage preimages.
final class OAuthOwnedSourceRecord {
  final String scopedOwner;
  final String oauthIncarnation;
  final String sourceIncarnation;
  final int metadataRevision;
  final int credentialRevision;
  final Map<String, Object?> account;

  OAuthOwnedSourceRecord._(
    this.scopedOwner,
    this.oauthIncarnation,
    this.sourceIncarnation,
    this.metadataRevision,
    this.credentialRevision,
    Map<String, Object?> account,
  ) : account = Map.unmodifiable(account);

  factory OAuthOwnedSourceRecord.create({
    required OAuthScopedOwnerRecord scope,
    required Map<String, Object?> account,
  }) {
    final checked = _account(account);
    if (checked == null) throw const OAuthWorkspaceCodecException();
    return OAuthOwnedSourceRecord._(
      scope.scopedOwner,
      scope.oauthIncarnation,
      _newIncarnation(),
      1,
      1,
      checked,
    );
  }

  Map<String, Object?> toJson() => {
    'schema': 2,
    'scopedOwner': scopedOwner,
    'oauthIncarnation': oauthIncarnation,
    'sourceIncarnation': sourceIncarnation,
    'metadataRevision': metadataRevision,
    'credentialRevision': credentialRevision,
    'account': account,
  };

  String encode() => jsonEncode(toJson());

  /// Connection configuration changes create a new source incarnation. Token
  /// rotation and user metadata retain the source but advance separate stamps.
  OAuthOwnedSourceRecord withAccount(Map<String, Object?> next) {
    final checked = _account(next);
    if (checked == null) throw const OAuthWorkspaceCodecException();
    final configurationChanged = _configurationKeys.any(
      (key) => account[key] != checked[key],
    );
    if (configurationChanged) {
      return OAuthOwnedSourceRecord._(
        scopedOwner,
        oauthIncarnation,
        _newIncarnation(),
        1,
        1,
        checked,
      );
    }
    final metadataChanged = _metadataKeys.any(
      (key) => account[key] != checked[key],
    );
    final credentialsChanged = _credentialKeys.any(
      (key) => account[key] != checked[key],
    );
    if ((metadataChanged && metadataRevision == _maximumRevision) ||
        (credentialsChanged && credentialRevision == _maximumRevision)) {
      throw const OAuthWorkspaceCodecException();
    }
    return OAuthOwnedSourceRecord._(
      scopedOwner,
      oauthIncarnation,
      sourceIncarnation,
      metadataRevision + (metadataChanged ? 1 : 0),
      credentialRevision + (credentialsChanged ? 1 : 0),
      checked,
    );
  }

  static OAuthOwnedSourceRecord? parse(
    String raw, {
    required OAuthScopedOwnerRecord scope,
  }) {
    try {
      final decoded = jsonDecode(raw);
      final result = _decode(decoded, scope);
      return result != null && result.encode() == raw ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Validate the original whole list so duplicate keys cannot be collapsed
  /// by decoding each row and then treating its re-encoding as original data.
  static List<OAuthOwnedSourceRecord>? parseList(
    String raw, {
    required OAuthScopedOwnerRecord scope,
  }) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      if (decoded.isEmpty) return const [];
      final result = <OAuthOwnedSourceRecord>[];
      final ids = <String>{};
      final incarnations = <String>{};
      for (final value in decoded) {
        final row = _decode(value, scope);
        if (row == null ||
            !ids.add(row.account['id']! as String) ||
            !incarnations.add(row.sourceIncarnation)) {
          return null;
        }
        result.add(row);
      }
      if (jsonEncode(result.map((v) => v.toJson()).toList()) != raw) {
        return null;
      }
      return List.unmodifiable(result);
    } catch (_) {
      return null;
    }
  }

  static OAuthOwnedSourceRecord? _decode(
    Object? decoded,
    OAuthScopedOwnerRecord scope,
  ) {
    if (decoded is! Map<String, dynamic> ||
        !_keys(decoded, _sourceKeys) ||
        decoded['schema'] is! int ||
        decoded['schema'] != 2 ||
        decoded['scopedOwner'] != scope.scopedOwner ||
        decoded['oauthIncarnation'] != scope.oauthIncarnation ||
        !_incarnation(decoded['sourceIncarnation']) ||
        !_revision(decoded['metadataRevision']) ||
        !_revision(decoded['credentialRevision'])) {
      return null;
    }
    final account = _account(decoded['account']);
    if (account == null) return null;
    return OAuthOwnedSourceRecord._(
      scope.scopedOwner,
      scope.oauthIncarnation,
      decoded['sourceIncarnation'] as String,
      decoded['metadataRevision'] as int,
      decoded['credentialRevision'] as int,
      account,
    );
  }
}

/// Confirmed events retain their source's identity and provenance revisions.
/// Older confirmed cache is allowed after metadata edits or token rotation;
/// a new source incarnation or a future revision can never adopt that cache.
final class OAuthOwnedEventsRecord {
  final String scopedOwner;
  final String oauthIncarnation;
  final String sourceAccountId;
  final String sourceIncarnation;
  final int metadataRevision;
  final int credentialRevision;
  final List<Map<String, Object?>> events;

  OAuthOwnedEventsRecord._(
    this.scopedOwner,
    this.oauthIncarnation,
    this.sourceAccountId,
    this.sourceIncarnation,
    this.metadataRevision,
    this.credentialRevision,
    List<Map<String, Object?>> events,
  ) : events = List.unmodifiable(events.map(Map<String, Object?>.unmodifiable));

  factory OAuthOwnedEventsRecord.create({
    required OAuthOwnedSourceRecord source,
    required List<Map<String, Object?>> events,
  }) {
    final checked = _events(events);
    if (checked == null) throw const OAuthWorkspaceCodecException();
    return OAuthOwnedEventsRecord._(
      source.scopedOwner,
      source.oauthIncarnation,
      source.account['id']! as String,
      source.sourceIncarnation,
      source.metadataRevision,
      source.credentialRevision,
      checked,
    );
  }

  Map<String, Object?> toJson() => {
    'schema': 2,
    'scopedOwner': scopedOwner,
    'oauthIncarnation': oauthIncarnation,
    'sourceAccountId': sourceAccountId,
    'sourceIncarnation': sourceIncarnation,
    'metadataRevision': metadataRevision,
    'credentialRevision': credentialRevision,
    'events': events,
  };

  String encode() => jsonEncode(toJson());

  static OAuthOwnedEventsRecord? parse(
    String raw, {
    required OAuthOwnedSourceRecord source,
  }) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          !_keys(decoded, _eventsKeys) ||
          decoded['schema'] is! int ||
          decoded['schema'] != 2 ||
          decoded['scopedOwner'] != source.scopedOwner ||
          decoded['oauthIncarnation'] != source.oauthIncarnation ||
          decoded['sourceAccountId'] != source.account['id'] ||
          decoded['sourceIncarnation'] != source.sourceIncarnation ||
          !_revision(decoded['metadataRevision']) ||
          !_revision(decoded['credentialRevision']) ||
          (decoded['metadataRevision'] as int) > source.metadataRevision ||
          (decoded['credentialRevision'] as int) > source.credentialRevision) {
        return null;
      }
      final events = _events(decoded['events']);
      if (events == null) return null;
      final result = OAuthOwnedEventsRecord._(
        source.scopedOwner,
        source.oauthIncarnation,
        source.account['id']! as String,
        source.sourceIncarnation,
        decoded['metadataRevision'] as int,
        decoded['credentialRevision'] as int,
        events,
      );
      return result.encode() == raw ? result : null;
    } catch (_) {
      return null;
    }
  }
}

/// Sanitized failure: never include credentials or the rejected raw record.
final class OAuthWorkspaceCodecException implements Exception {
  const OAuthWorkspaceCodecException();
  @override
  String toString() => 'OAuth workspace record rejected';
}

const _maximumRevision = 9007199254740991;
const _sourceKeys = {
  'schema',
  'scopedOwner',
  'oauthIncarnation',
  'sourceIncarnation',
  'metadataRevision',
  'credentialRevision',
  'account',
};
const _eventsKeys = {
  'schema',
  'scopedOwner',
  'oauthIncarnation',
  'sourceAccountId',
  'sourceIncarnation',
  'metadataRevision',
  'credentialRevision',
  'events',
};
const _accountKeys = [
  'id',
  'provider',
  'displayName',
  'clientId',
  'clientSecret',
  'redirectUri',
  'calendarId',
  'accessToken',
  'refreshToken',
  'expiresAt',
  'scope',
  'colorValue',
  'enabled',
  'lastSyncedAt',
];
const _configurationKeys = {
  'id',
  'provider',
  'clientId',
  'clientSecret',
  'redirectUri',
  'calendarId',
};
const _credentialKeys = {'accessToken', 'refreshToken', 'expiresAt', 'scope'};
const _metadataKeys = {'displayName', 'colorValue', 'enabled'};
const _eventKeys = [
  'id',
  'title',
  'date',
  'endDate',
  'subtitle',
  'colorValue',
  'sourceId',
  'timeHour',
  'timeMinute',
];

bool _keys(Map<String, dynamic> value, Iterable<String> expected) =>
    value.length == expected.length && expected.every(value.containsKey);
bool _revision(Object? value) =>
    value is int && value > 0 && value <= _maximumRevision;
bool _incarnation(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9_-]{32}$').hasMatch(value);
String _newIncarnation() {
  final random = Random.secure();
  return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
}

bool _nonempty(Object? value) => value is String && value.trim().isNotEmpty;
bool _color(Object? value) => value is int && value >= 0 && value <= 0xffffffff;
bool _date(Object? value) =>
    value is String && DateTime.tryParse(value)?.toIso8601String() == value;
bool _redirect(Object? value) {
  if (value is! String ||
      RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value) ||
      RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(value)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasScheme &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty &&
      !uri.authority.contains('@') &&
      (!const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
          uri.host.isNotEmpty);
}

Map<String, Object?>? _account(Object? raw) {
  if (raw is! Map<String, dynamic> || !_keys(raw, _accountKeys)) return null;
  if (!_nonempty(raw['id']) ||
      !const {'google', 'outlook'}.contains(raw['provider']) ||
      raw['displayName'] is! String ||
      !_nonempty(raw['clientId']) ||
      raw['clientSecret'] is! String ||
      !_redirect(raw['redirectUri']) ||
      !_nonempty(raw['calendarId']) ||
      !_nonempty(raw['accessToken']) ||
      raw['refreshToken'] is! String ||
      !_date(raw['expiresAt']) ||
      !_nonempty(raw['scope']) ||
      !_color(raw['colorValue']) ||
      raw['enabled'] is! bool ||
      (raw['lastSyncedAt'] != null && !_date(raw['lastSyncedAt']))) {
    return null;
  }
  return {for (final key in _accountKeys) key: raw[key]};
}

List<Map<String, Object?>>? _events(Object? raw) {
  if (raw is! List) return null;
  final result = <Map<String, Object?>>[];
  final ids = <String>{};
  for (final value in raw) {
    if (value is! Map<String, dynamic> ||
        !_keys(value, _eventKeys) ||
        !_nonempty(value['id']) ||
        !ids.add(value['id'] as String) ||
        value['title'] is! String ||
        !_date(value['date']) ||
        (value['endDate'] != null && !_date(value['endDate'])) ||
        (value['subtitle'] != null && value['subtitle'] is! String) ||
        !_color(value['colorValue']) ||
        (value['sourceId'] != null && value['sourceId'] is! String)) {
      return null;
    }
    final hour = value['timeHour'];
    final minute = value['timeMinute'];
    if (hour == null
        ? minute != null
        : hour is! int ||
              hour < 0 ||
              hour > 23 ||
              minute is! int ||
              minute < 0 ||
              minute > 59) {
      return null;
    }
    result.add({for (final key in _eventKeys) key: value[key]});
  }
  return result;
}
