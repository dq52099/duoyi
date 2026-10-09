import 'dart:async';

import 'package:flutter/services.dart';

import '../core/i18n.dart';
import 'widget_publication.dart';

/// Account identity has to come from validated local auth, never widget data.
class WidgetWorkspaceBinding {
  WidgetWorkspaceBinding({required this.kind, required this.key}) {
    if ((kind != 'account' && kind != 'guest') || key.trim().isEmpty) {
      throw const FormatException('Invalid widget workspace binding');
    }
  }

  final String kind;
  final String key;

  Map<String, Object> toJson() => {'kind': kind, 'key': key};

  static WidgetWorkspaceBinding? _decode(Object? raw) {
    if (!_keys(raw, {'kind', 'key'})) return null;
    final map = raw as Map;
    if (map['kind'] is! String || map['key'] is! String) return null;
    try {
      return WidgetWorkspaceBinding(kind: map['kind'], key: map['key']);
    } on FormatException {
      return null;
    }
  }
}

/// Facts from one native read; this object carries no writer capability.
class WidgetStoreSnapshot {
  WidgetStoreSnapshot._({
    required this.storeRevision,
    required this.binding,
    required this.ownerEpoch,
    required this.active,
    required this.desiredRevision,
    required this.desiredLocale,
    required this.document,
    required this.lastOperationId,
    required this.lastRequestDigest,
  });

  final int storeRevision;
  final WidgetWorkspaceBinding? binding;
  final String ownerEpoch;
  final bool active;
  final int desiredRevision;
  final AppLocale desiredLocale;
  final WidgetPublication document;
  final String lastOperationId;
  final String lastRequestDigest;

  static WidgetStoreSnapshot? _decode(Map raw) {
    if (!_keys(raw, {
      'status',
      'storeRevision',
      'binding',
      'ownerEpoch',
      'leaseState',
      'desiredPresentation',
      'document',
      'lastOperationId',
      'lastRequestDigest',
    })) {
      return null;
    }
    final revision = raw['storeRevision'];
    final epoch = raw['ownerEpoch'];
    final state = raw['leaseState'];
    final desired = raw['desiredPresentation'];
    final document = WidgetPublication.tryFromJson(raw['document']);
    final operation = raw['lastOperationId'];
    final digest = raw['lastRequestDigest'];
    if (!_integer(revision, positive: true) ||
        !_opaque(epoch) ||
        !_keys(desired, {'revision', 'locale'}) ||
        document == null ||
        !_opaque(operation) ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      return null;
    }
    final presentation = desired as Map;
    final desiredRevision = presentation['revision'];
    final desiredLocale = _locale(presentation['locale']);
    if (!_integer(desiredRevision) ||
        desiredLocale == null ||
        document.ownerEpoch != epoch ||
        document.localeRevision > (desiredRevision as int) ||
        (document.localeRevision == desiredRevision &&
            document.locale != desiredLocale)) {
      return null;
    }
    final active = state == 'active';
    final binding = WidgetWorkspaceBinding._decode(raw['binding']);
    if (state != 'active' && state != 'sealed') return null;
    if (raw['status'] != (active ? 'ready' : 'sealed')) return null;
    if (active ? binding == null : raw['binding'] != null) return null;
    if (!active &&
        (document.state == WidgetPublicationState.published ||
            document.localeRevision != desiredRevision)) {
      return null;
    }
    return WidgetStoreSnapshot._(
      storeRevision: revision as int,
      binding: binding,
      ownerEpoch: epoch as String,
      active: active,
      desiredRevision: desiredRevision,
      desiredLocale: desiredLocale,
      document: document,
      lastOperationId: operation as String,
      lastRequestDigest: digest,
    );
  }
}

class WidgetStoreRead {
  WidgetStoreRead._(this.status, [this.snapshot]);

  final String status;
  final WidgetStoreSnapshot? snapshot;
  bool get absent => status == 'absent';
}

/// Immutable operation retained for an exact retry after an uncertain response.
/// No retry may substitute a newer revision, epoch, binding or document.
class WidgetStoreRequest {
  WidgetStoreRequest._(
    this.method,
    Map<String, Object?> arguments,
    this.expected,
  ) : arguments = _freeze(arguments);

  final String method;
  final Map<String, Object?> arguments;
  final WidgetStoreSnapshot? expected;
  String get operationId => arguments['operationId'] as String;

  static Map<String, Object?> _common(
    String operationId,
    WidgetStoreSnapshot? expected,
  ) {
    if (!_opaque(operationId)) {
      throw const FormatException('Invalid widget operation identity');
    }
    return {
      'protocolVersion': 1,
      'operationId': operationId,
      'expectedStoreRevision': expected?.storeRevision,
      'expectedOwnerEpoch': expected?.ownerEpoch,
    };
  }

  static Map<String, Object> _presentation(WidgetPublication cleared) {
    if (cleared.state != WidgetPublicationState.cleared) {
      throw const FormatException(
        'Presentation must have cleared business data',
      );
    }
    return {
      'revision': cleared.localeRevision,
      'locale': cleared.locale.name,
      'values': cleared.values,
    };
  }

  factory WidgetStoreRequest.open({
    required String operationId,
    required WidgetStoreRead expected,
    required WidgetWorkspaceBinding binding,
    required WidgetPublication presentation,
    required bool resume,
  }) {
    final snapshot = expected.snapshot;
    if (snapshot == null && (!expected.absent || resume)) {
      throw const FormatException('Open requires a verified store context');
    }
    return WidgetStoreRequest._('openWidgetWorkspace', {
      ..._common(operationId, snapshot),
      'mode': resume ? 'resume' : 'initialize',
      'binding': binding.toJson(),
      'presentation': _presentation(presentation),
    }, snapshot);
  }

  factory WidgetStoreRequest.invalidate({
    required String operationId,
    required WidgetStoreSnapshot expected,
    required WidgetPublication presentation,
  }) => WidgetStoreRequest._('invalidateWidgetWorkspace', {
    ..._common(operationId, expected),
    'presentation': _presentation(presentation),
  }, expected);

  factory WidgetStoreRequest.advance({
    required String operationId,
    required WidgetStoreSnapshot expected,
    required String writerLeaseId,
    required int revision,
    required AppLocale locale,
  }) {
    if (!_opaque(writerLeaseId) || !_integer(revision)) {
      throw const FormatException('Invalid widget presentation request');
    }
    return WidgetStoreRequest._('advanceDesiredWidgetPresentation', {
      ..._common(operationId, expected),
      'writerLeaseId': writerLeaseId,
      'desiredPresentation': {'revision': revision, 'locale': locale.name},
    }, expected);
  }

  factory WidgetStoreRequest.publish({
    required String operationId,
    required WidgetStoreSnapshot expected,
    required String writerLeaseId,
    required WidgetPublication document,
  }) {
    if (!_opaque(writerLeaseId)) {
      throw const FormatException('Invalid widget writer capability');
    }
    return WidgetStoreRequest._('publishWidgetPublication', {
      ..._common(operationId, expected),
      'writerLeaseId': writerLeaseId,
      'expectedPublicationRevision': expected.document.publicationRevision,
      'document': document.toJson(),
    }, expected);
  }
}

/// Storage acknowledgement only; callers must still check their auth and
/// presentation generations. A commit does not establish launcher display.
class WidgetStoreAcknowledgement {
  WidgetStoreAcknowledgement._(this.status, [this.metadata]);

  final String status;
  final Map<String, Object?>? metadata;
  bool get committed => status == 'applied' || status == 'alreadyApplied';
  String? get writerLeaseId => metadata?['writerLeaseId'] as String?;
  bool get refreshRequested => metadata?['refreshRequested'] == true;

  static WidgetStoreAcknowledgement _decode(
    Object? raw,
    WidgetStoreRequest request,
  ) {
    if (raw is! Map || raw['status'] is! String) {
      return WidgetStoreAcknowledgement._('invalidResponse');
    }
    final status = raw['status'] as String;
    if (status != 'applied' && status != 'alreadyApplied') {
      if (!_failureStatuses.contains(status) ||
          !(_keys(raw, {'status'}) ||
              _keys(raw, {'status', 'operationId'}) ||
              _keys(raw, {'status', 'refreshRequested'}) ||
              _keys(raw, {'status', 'operationId', 'refreshRequested'})) ||
          (raw.containsKey('refreshRequested') &&
              raw['refreshRequested'] != false) ||
          (raw.containsKey('operationId') &&
              raw['operationId'] != request.operationId)) {
        return WidgetStoreAcknowledgement._('invalidResponse');
      }
      return WidgetStoreAcknowledgement._(status);
    }
    final open = request.method == 'openWidgetWorkspace';
    final keys = {
      'status',
      'operationId',
      'committedStoreRevision',
      'ownerEpoch',
      'publicationRevision',
      'desiredPresentationRevision',
      'appliedPresentationRevision',
      'documentState',
      'refreshRequested',
      if (open) 'writerLeaseId',
    };
    final revision = raw['committedStoreRevision'];
    final epoch = raw['ownerEpoch'];
    final publication = raw['publicationRevision'];
    final desired = raw['desiredPresentationRevision'];
    final applied = raw['appliedPresentationRevision'];
    final state = raw['documentState'];
    final expectedRevision = request.arguments['expectedStoreRevision'] as int?;
    if (!_keys(raw, keys) ||
        raw['operationId'] != request.operationId ||
        !_integer(revision, positive: true) ||
        revision != (expectedRevision ?? 0) + 1 ||
        !_opaque(epoch) ||
        !_integer(publication) ||
        !_integer(desired) ||
        !_integer(applied) ||
        (applied as int) > (desired as int) ||
        !{'published', 'cleared', 'blocked'}.contains(state) ||
        raw['refreshRequested'] is! bool ||
        (open && !_opaque(raw['writerLeaseId']))) {
      return WidgetStoreAcknowledgement._('invalidResponse');
    }
    if (!_matchesRequest(raw, request)) {
      return WidgetStoreAcknowledgement._('invalidResponse');
    }
    return WidgetStoreAcknowledgement._(status, _freeze(raw));
  }

  static bool _matchesRequest(Map raw, WidgetStoreRequest request) {
    final args = request.arguments;
    final previous = request.expected?.document;
    bool keepsDocument() =>
        previous != null &&
        raw['publicationRevision'] == previous.publicationRevision &&
        raw['appliedPresentationRevision'] == previous.localeRevision &&
        raw['documentState'] == previous.state.name;
    switch (request.method) {
      case 'publishWidgetPublication':
        final doc = args['document'] as Map;
        return raw['ownerEpoch'] == doc['ownerEpoch'] &&
            raw['publicationRevision'] == doc['publicationRevision'] &&
            raw['desiredPresentationRevision'] == doc['localeRevision'] &&
            raw['appliedPresentationRevision'] == doc['localeRevision'] &&
            raw['documentState'] == doc['state'];
      case 'advanceDesiredWidgetPresentation':
        return raw['ownerEpoch'] == args['expectedOwnerEpoch'] &&
            keepsDocument() &&
            raw['desiredPresentationRevision'] ==
                (args['desiredPresentation'] as Map)['revision'];
      case 'invalidateWidgetWorkspace':
      case 'openWidgetWorkspace':
        final presentation = args['presentation'] as Map;
        if (raw['desiredPresentationRevision'] != presentation['revision']) {
          return false;
        }
        if (args['mode'] == 'resume') {
          return raw['ownerEpoch'] == args['expectedOwnerEpoch'] &&
              keepsDocument();
        }
        return raw['ownerEpoch'] != args['expectedOwnerEpoch'] &&
            raw['publicationRevision'] == 0 &&
            raw['appliedPresentationRevision'] == presentation['revision'] &&
            raw['documentState'] == 'cleared';
      default:
        return false;
    }
  }
}

/// Wire adapter only. It neither bootstraps ownership nor automatically retries.
class WidgetPublicationClient {
  WidgetPublicationClient({
    MethodChannel? channel,
    this.responseTimeout = const Duration(seconds: 15),
  }) : _channel = channel ?? const MethodChannel('duoyi/widget-publication') {
    if (responseTimeout <= Duration.zero) {
      throw ArgumentError.value(responseTimeout, 'responseTimeout');
    }
  }

  final MethodChannel _channel;
  final Duration responseTimeout;

  Future<WidgetStoreRead> read() async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('readWidgetStore')
          .timeout(responseTimeout);
      if (raw is! Map || raw['status'] is! String) {
        return WidgetStoreRead._('invalidResponse');
      }
      final status = raw['status'] as String;
      if (status == 'ready' || status == 'sealed') {
        final snapshot = WidgetStoreSnapshot._decode(raw);
        return snapshot == null
            ? WidgetStoreRead._('invalidResponse')
            : WidgetStoreRead._(status, snapshot);
      }
      if (!_keys(raw, {'status'}) ||
          !(status == 'absent' || _failureStatuses.contains(status))) {
        return WidgetStoreRead._('invalidResponse');
      }
      return WidgetStoreRead._(status);
    } on MissingPluginException {
      return WidgetStoreRead._('unavailable');
    } on PlatformException {
      return WidgetStoreRead._('unavailable');
    } on TimeoutException {
      return WidgetStoreRead._('unavailable');
    }
  }

  Future<WidgetStoreAcknowledgement> submit(WidgetStoreRequest request) async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>(request.method, request.arguments)
          .timeout(responseTimeout);
      return WidgetStoreAcknowledgement._decode(raw, request);
    } on MissingPluginException {
      return WidgetStoreAcknowledgement._('unavailable');
    } on PlatformException {
      // The transaction may have committed before its messenger failed.
      // Preserve the exact request; do not manufacture new CAS expectations.
      return WidgetStoreAcknowledgement._('responseUnknown');
    } on TimeoutException {
      // A deadline bounds the Dart wait, not the native transaction lifetime.
      return WidgetStoreAcknowledgement._('responseUnknown');
    }
  }
}

const _failureStatuses = {
  'invalid',
  'revisionConflict',
  'ownerMismatch',
  'supersededPresentation',
  'sealed',
  'corrupt',
  'unsupported',
  'busy',
  'unavailable',
  'durabilityUnknown',
};

bool _integer(Object? value, {bool positive = false}) =>
    value is int &&
    value >= (positive ? 1 : 0) &&
    value <= WidgetPublication.maxExactJsonInteger;
bool _opaque(Object? value) => value is String && value.trim().isNotEmpty;
AppLocale? _locale(Object? value) => switch (value) {
  'zh' => AppLocale.zh,
  'en' => AppLocale.en,
  _ => null,
};
bool _keys(Object? value, Set<String> keys) =>
    value is Map &&
    value.length == keys.length &&
    value.keys.every(keys.contains);

Map<String, Object?> _freeze(Map raw) => Map<String, Object?>.unmodifiable({
  for (final entry in raw.entries)
    entry.key as String: entry.value is Map
        ? _freeze(entry.value)
        : entry.value,
});
