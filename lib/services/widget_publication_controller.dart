import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/i18n.dart';
import 'account_local_data_cleaner.dart';
import 'widget_publication.dart';
import 'widget_publication_client.dart';

/// Supplied only after successful auth hydration and owner persistence.
/// The host predicate must include auth, model and account-generation validity.
class ValidatedWidgetWorkspace {
  ValidatedWidgetWorkspace({
    required this.binding,
    required this.accountGeneration,
    required this.isCurrent,
  });

  final WidgetWorkspaceBinding binding;
  final int accountGeneration;
  final bool Function() isCurrent;
}

/// One synchronous capture of all device locale, brand and theme values.
/// Business fields are discarded; this object cannot carry account content.
class WidgetDevicePresentation {
  WidgetDevicePresentation({
    required this.locale,
    required Map<String, Object> completeValues,
  }) : clearedValues = WidgetPublication.clearedValuesFrom(completeValues) {
    // Validate the complete manifest before installing any device selection.
    document(revision: 0);
  }

  final AppLocale locale;
  final Map<String, Object> clearedValues;

  WidgetPublication document({required int revision}) => WidgetPublication(
    ownerEpoch: 'unassigned-presentation',
    publicationRevision: 0,
    localeRevision: revision,
    state: WidgetPublicationState.cleared,
    locale: locale,
    snapshotDay: '',
    snapshotUtcOffsetMinutes: 0,
    capturedAtMillis: 0,
    values: clearedValues,
  );

  bool sameAs(WidgetDevicePresentation other) =>
      locale == other.locale && _sameValues(clearedValues, other.clearedValues);
}

/// A capture is bound to its original context and CAS expectations forever.
class WidgetPublicationCapture {
  WidgetPublicationCapture._(
    this._controller,
    this._scope,
    this._selection,
    this._expected,
    this._lease,
    this.document,
  );

  final Object _controller;
  final int _scope;
  final int _selection;
  final WidgetStoreSnapshot _expected;
  final String _lease;
  final WidgetPublication document;
}

class WidgetPublicationOutcome {
  const WidgetPublicationOutcome(
    this.status, {
    this.storeCommitted = false,
    this.barrierConfirmed = false,
    this.refreshRequested = false,
  });

  final String status;
  final bool storeCommitted;
  final bool barrierConfirmed;
  final bool refreshRequested;
}

class _PendingPublication {
  const _PendingPublication({
    required this.request,
    required this.scope,
    required this.selection,
    required this.presentation,
    required this.revision,
    this.workspace,
    this.lease,
  });

  final WidgetStoreRequest request;
  final int scope;
  final int selection;
  final WidgetDevicePresentation presentation;
  final int revision;
  final ValidatedWidgetWorkspace? workspace;
  final String? lease;
}

/// Serial authority gate for the approved native publication protocol.
///
/// Native reads must share the application-wide FIFO with mutations. A healthy
/// read after an uncertain call drains that call; it never grants a writer lease.
/// Auth/HomeWidgetService integration and platform readers are separate work.
class WidgetPublicationController {
  WidgetPublicationController({WidgetPublicationClient? client})
    : _client = client ?? WidgetPublicationClient();

  final WidgetPublicationClient _client;
  final Object _identity = Object();
  Future<void> _tail = Future<void>.value();
  ValidatedWidgetWorkspace? _workspace;
  WidgetDevicePresentation? _presentation;
  WidgetStoreSnapshot? _known;
  String? _lease;
  _PendingPublication? _pending;
  int _scope = 0;
  int _selection = 0;
  int _acceptedSelection = -1;
  int _presentationRevision = -1;
  int _floor = 0;
  bool _requiresBarrier = false;
  bool _quarantined = false;
  bool _disposed = false;

  bool get ready =>
      !_disposed &&
      !_quarantined &&
      !_requiresBarrier &&
      _pending == null &&
      _validatedWorkspace(_workspace) &&
      _lease != null &&
      _known?.active == true &&
      _sameBinding(_known!.binding, _workspace!.binding) &&
      _acceptedSelection == _selection &&
      _known!.desiredRevision == _presentationRevision &&
      _known!.desiredLocale == _presentation?.locale;

  bool get hasPendingOperation => _pending != null;

  /// Revocation happens before an await and before any model/owner deletion.
  /// It does not claim a durable cleanup barrier; await [invalidate] for that.
  void revoke() {
    _revoke(requireBarrier: true);
  }

  void _revoke({required bool requireBarrier}) {
    _scope++;
    _workspace = null;
    _lease = null;
    _acceptedSelection = -1;
    if (requireBarrier) _requiresBarrier = true;
  }

  /// Every actual change invalidates captures, including zh -> en -> zh.
  /// Only [openWorkspace] or [advancePresentation] installs its native floor.
  void selectPresentation(WidgetDevicePresentation presentation) {
    if (_disposed) throw StateError('Widget controller disposed');
    if (_presentation?.sameAs(presentation) == true) return;
    _presentation = presentation;
    _selection++;
    _acceptedSelection = -1;
  }

  Future<WidgetPublicationOutcome> openWorkspace(
    ValidatedWidgetWorkspace workspace, {
    required bool forceReset,
  }) {
    if (_requiresBarrier) {
      return Future.value(const WidgetPublicationOutcome('barrierRequired'));
    }
    // A same-binding relogin/reset must never fall back to resume if its
    // invalidate attempt is busy, uncertain, or superseded.
    if (forceReset) _requiresBarrier = true;
    _revoke(requireBarrier: false);
    if (_disposed || !_validatedWorkspace(workspace)) {
      return Future.value(const WidgetPublicationOutcome('blocked'));
    }
    _workspace = workspace;
    final scope = _scope;
    final selection = _selection;
    final presentation = _presentation;
    return _enqueue(() async {
      if (presentation == null || !_current(scope, selection, workspace)) {
        return const WidgetPublicationOutcome('blocked');
      }
      var read = await _readFence();
      if (!_current(scope, selection, workspace)) return _superseded;
      if (!_healthy(read)) return WidgetPublicationOutcome(read.status);
      final snapshot = read.snapshot;
      if (forceReset && (read.absent || snapshot?.active == false)) {
        _requiresBarrier = false;
      }
      if (snapshot?.active == true &&
          (forceReset || !_sameBinding(snapshot!.binding, workspace.binding))) {
        // Once a foreign active owner is observed, any failed handoff keeps
        // future opens behind an explicit durable clear barrier.
        _requiresBarrier = true;
        final revision = _versionFor(presentation, snapshot);
        final sealed = await _submit(
          _PendingPublication(
            request: WidgetStoreRequest.invalidate(
              operationId: _operationId(),
              expected: snapshot!,
              presentation: presentation.document(revision: revision),
            ),
            scope: scope,
            selection: selection,
            presentation: presentation,
            revision: revision,
            workspace: workspace,
          ),
        );
        if (!sealed.storeCommitted || !_current(scope, selection, workspace)) {
          return sealed;
        }
        read = await _readFence();
        if (!_current(scope, selection, workspace)) return _superseded;
        if (!_healthy(read) || read.snapshot?.active != false) {
          return WidgetPublicationOutcome(read.status);
        }
      }
      final revision = _versionFor(presentation, read.snapshot);
      return _submit(
        _PendingPublication(
          request: WidgetStoreRequest.open(
            operationId: _operationId(),
            expected: read,
            binding: workspace.binding,
            presentation: presentation.document(revision: revision),
            resume: read.snapshot?.active == true,
          ),
          scope: scope,
          selection: selection,
          presentation: presentation,
          revision: revision,
          workspace: workspace,
        ),
      );
    });
  }

  /// A healthy FIFO read drains earlier calls before a new exact-CAS tombstone.
  /// No old account capture is replayed to obtain this barrier.
  Future<WidgetPublicationOutcome> invalidate() {
    _revoke(requireBarrier: true);
    final scope = _scope;
    final selection = _selection;
    final presentation = _presentation;
    return _enqueue(() async {
      if (presentation == null || !_current(scope, selection, null)) {
        return const WidgetPublicationOutcome('blocked');
      }
      final read = await _readFence();
      if (!_current(scope, selection, null)) return _superseded;
      if (!_healthy(read)) return WidgetPublicationOutcome(read.status);
      if (read.absent) {
        _requiresBarrier = false;
        return const WidgetPublicationOutcome('absent', barrierConfirmed: true);
      }
      if (read.snapshot?.active == false) {
        _requiresBarrier = false;
        return const WidgetPublicationOutcome('sealed', barrierConfirmed: true);
      }
      final revision = _versionFor(presentation, read.snapshot);
      return _submit(
        _PendingPublication(
          request: WidgetStoreRequest.invalidate(
            operationId: _operationId(),
            expected: read.snapshot!,
            presentation: presentation.document(revision: revision),
          ),
          scope: scope,
          selection: selection,
          presentation: presentation,
          revision: revision,
        ),
      );
    });
  }

  Future<WidgetPublicationOutcome> advancePresentation() {
    final scope = _scope;
    final selection = _selection;
    final presentation = _presentation;
    final workspace = _workspace;
    return _enqueue(() async {
      if (presentation == null ||
          workspace == null ||
          !_current(scope, selection, workspace) ||
          _quarantined ||
          _pending != null ||
          _lease == null ||
          _known?.active != true) {
        return const WidgetPublicationOutcome('blocked');
      }
      if (_acceptedSelection == selection) {
        return const WidgetPublicationOutcome('unchanged');
      }
      final revision = _nextRevision();
      return _submit(
        _PendingPublication(
          request: WidgetStoreRequest.advance(
            operationId: _operationId(),
            expected: _known!,
            writerLeaseId: _lease!,
            revision: revision,
            locale: presentation.locale,
          ),
          scope: scope,
          selection: selection,
          presentation: presentation,
          revision: revision,
          workspace: workspace,
          lease: _lease,
        ),
      );
    });
  }

  /// Call only after the required business providers have hydrated. Values and
  /// civil day/offset are captured synchronously; queued work never retags them.
  WidgetPublicationCapture? capture(
    Map<String, Object> completeValues, {
    DateTime? capturedAt,
  }) {
    if (!ready) return null;
    final values = Map<String, Object>.of(completeValues);
    if (!_sameValues(
      WidgetPublication.clearedValuesFrom(values),
      _presentation!.clearedValues,
    )) {
      throw const FormatException('Widget capture presentation mismatch');
    }
    final now = (capturedAt ?? DateTime.now()).toLocal();
    final expected = _known!;
    final document = WidgetPublication(
      ownerEpoch: expected.ownerEpoch,
      publicationRevision: _increment(expected.document.publicationRevision),
      localeRevision: _presentationRevision,
      state: WidgetPublicationState.published,
      locale: _presentation!.locale,
      snapshotDay:
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}',
      snapshotUtcOffsetMinutes: now.timeZoneOffset.inMinutes,
      capturedAtMillis: now.millisecondsSinceEpoch,
      values: values,
    );
    return WidgetPublicationCapture._(
      _identity,
      _scope,
      _selection,
      expected,
      _lease!,
      document,
    );
  }

  Future<WidgetPublicationOutcome> publish(WidgetPublicationCapture capture) =>
      _enqueue(() async {
        if (!identical(capture._controller, _identity) ||
            !ready ||
            capture._scope != _scope ||
            capture._selection != _selection ||
            capture._lease != _lease ||
            capture._expected.storeRevision != _known!.storeRevision) {
          return _superseded;
        }
        final now = DateTime.now().toLocal();
        final captured = capture.document;
        final currentDay =
            '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
        if (captured.snapshotDay != currentDay ||
            captured.snapshotUtcOffsetMinutes != now.timeZoneOffset.inMinutes ||
            captured.capturedAtMillis > now.millisecondsSinceEpoch) {
          return const WidgetPublicationOutcome('staleCapture');
        }
        return _submit(
          _PendingPublication(
            request: WidgetStoreRequest.publish(
              operationId: _operationId(),
              expected: capture._expected,
              writerLeaseId: capture._lease,
              document: capture.document,
            ),
            scope: capture._scope,
            selection: capture._selection,
            presentation: _presentation!,
            revision: _presentationRevision,
            workspace: _workspace,
            lease: capture._lease,
          ),
        );
      });

  /// Optional exact retry. A revoked business/open request is never resent.
  /// Recovery under a new context instead begins with an ordered healthy read.
  Future<WidgetPublicationOutcome> retryPending() => _enqueue(() async {
    final pending = _pending;
    if (pending == null ||
        _quarantined ||
        !_current(pending.scope, pending.selection, pending.workspace)) {
      return const WidgetPublicationOutcome('blocked');
    }
    return _submit(pending);
  });

  void dispose() {
    _revoke(requireBarrier: true);
    _disposed = true;
  }

  bool _current(
    int scope,
    int selection,
    ValidatedWidgetWorkspace? workspace,
  ) =>
      !_disposed &&
      _scope == scope &&
      _selection == selection &&
      identical(_workspace, workspace) &&
      (workspace == null || _validatedWorkspace(workspace));

  Future<WidgetStoreRead> _readFence() async {
    final read = await _client.read();
    if (_healthy(read) && !_quarantined) {
      _known = read.snapshot;
      _observeFloor(read.snapshot);
      // All previously sent calls completed before this read on the native FIFO.
      // Discard capability; only a new open ack can regain it after uncertainty.
      if (_pending != null) {
        _pending = null;
        _lease = null;
        _acceptedSelection = -1;
      }
    }
    if (read.status == 'durabilityUnknown') _quarantined = true;
    return read;
  }

  Future<WidgetPublicationOutcome> _submit(_PendingPublication pending) async {
    if (_quarantined ||
        !_current(pending.scope, pending.selection, pending.workspace)) {
      return const WidgetPublicationOutcome('blocked');
    }
    _pending = pending;
    final ack = await _client.submit(pending.request);
    if (!ack.committed) {
      _lease = null;
      _acceptedSelection = -1;
      if (ack.status == 'durabilityUnknown') _quarantined = true;
      if (!{
        'responseUnknown',
        'invalidResponse',
        'durabilityUnknown',
      }.contains(ack.status)) {
        _pending = null;
      }
      return WidgetPublicationOutcome(ack.status);
    }
    // A valid receipt is storage evidence; a fresh ordered read detects another
    // engine's intervening mutation before installing any local capability.
    final read = await _client.read();
    _observeFloor(read.snapshot);
    if (read.status == 'durabilityUnknown') _quarantined = true;
    if (!_matchesAcknowledgement(read.snapshot, pending, ack)) {
      _lease = null;
      _acceptedSelection = -1;
      return const WidgetPublicationOutcome('confirmationUnavailable');
    }
    _pending = null;
    _known = read.snapshot;
    if (!_current(pending.scope, pending.selection, pending.workspace) ||
        _quarantined) {
      _lease = null;
      _acceptedSelection = -1;
      return _superseded;
    }
    final invalidation = pending.request.method == 'invalidateWidgetWorkspace';
    if (invalidation) {
      _lease = null;
      _acceptedSelection = -1;
      _requiresBarrier = false;
    } else {
      _lease = ack.writerLeaseId ?? pending.lease;
      _acceptedSelection = pending.selection;
      _presentationRevision = pending.revision;
    }
    return WidgetPublicationOutcome(
      ack.status,
      storeCommitted: true,
      barrierConfirmed: invalidation,
      refreshRequested: ack.refreshRequested,
    );
  }

  bool _matchesAcknowledgement(
    WidgetStoreSnapshot? snapshot,
    _PendingPublication pending,
    WidgetStoreAcknowledgement ack,
  ) {
    if (snapshot == null) return false;
    final metadata = ack.metadata!;
    if (snapshot.storeRevision != metadata['committedStoreRevision'] ||
        snapshot.ownerEpoch != metadata['ownerEpoch'] ||
        snapshot.lastOperationId != pending.request.operationId ||
        snapshot.document.publicationRevision !=
            metadata['publicationRevision'] ||
        snapshot.desiredRevision != metadata['desiredPresentationRevision'] ||
        snapshot.document.localeRevision !=
            metadata['appliedPresentationRevision'] ||
        snapshot.document.state.name != metadata['documentState'] ||
        snapshot.desiredLocale != pending.presentation.locale) {
      return false;
    }
    final method = pending.request.method;
    if (method == 'invalidateWidgetWorkspace') {
      return !snapshot.active &&
          _sameValues(
            snapshot.document.values,
            pending.presentation.clearedValues,
          );
    }
    if (!snapshot.active ||
        !_sameBinding(snapshot.binding, pending.workspace?.binding)) {
      return false;
    }
    if (method == 'publishWidgetPublication') {
      final document = WidgetPublication.tryFromJson(
        pending.request.arguments['document'],
      );
      return document != null && _sameDocument(snapshot.document, document);
    }
    if (method == 'advanceDesiredWidgetPresentation' ||
        pending.request.arguments['mode'] == 'resume') {
      return _sameDocument(
        snapshot.document,
        pending.request.expected!.document,
      );
    }
    return _sameValues(
      snapshot.document.values,
      pending.presentation.clearedValues,
    );
  }

  bool _healthy(WidgetStoreRead read) =>
      !_quarantined && (read.absent || read.snapshot != null);

  void _observeFloor(WidgetStoreSnapshot? snapshot) {
    if (snapshot != null && snapshot.desiredRevision > _floor) {
      _floor = snapshot.desiredRevision;
    }
  }

  int _versionFor(
    WidgetDevicePresentation presentation,
    WidgetStoreSnapshot? snapshot,
  ) {
    _observeFloor(snapshot);
    if (snapshot == null) return _floor;
    if (snapshot.desiredRevision == _floor &&
        snapshot.desiredRevision == snapshot.document.localeRevision &&
        snapshot.desiredLocale == presentation.locale &&
        _sameValues(
          WidgetPublication.clearedValuesFrom(snapshot.document.values),
          presentation.clearedValues,
        )) {
      return snapshot.desiredRevision;
    }
    return _nextRevision();
  }

  int _nextRevision() => _increment(_floor);
  String _operationId() => const Uuid().v4();

  Future<WidgetPublicationOutcome> _enqueue(
    Future<WidgetPublicationOutcome> Function() body,
  ) {
    final result = _tail.then((_) async {
      try {
        return await body();
      } catch (_) {
        // A transition caller must never mistake a thrown codec/transport error
        // for a completed clear barrier and continue deleting account data.
        _lease = null;
        _acceptedSelection = -1;
        return const WidgetPublicationOutcome('controllerError');
      }
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _lease = null;
        _acceptedSelection = -1;
      },
    );
    return result;
  }

  static const _superseded = WidgetPublicationOutcome('supersededContext');
}

int _increment(int value) {
  if (value >= WidgetPublication.maxExactJsonInteger) {
    throw StateError('Widget revision exhausted');
  }
  return value + 1;
}

bool _sameBinding(WidgetWorkspaceBinding? a, WidgetWorkspaceBinding? b) =>
    a != null && b != null && a.kind == b.kind && a.key == b.key;

bool _validatedWorkspace(ValidatedWidgetWorkspace? workspace) {
  if (workspace == null ||
      !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        workspace.accountGeneration,
      )) {
    return false;
  }
  try {
    return workspace.isCurrent();
  } catch (_) {
    return false;
  }
}

bool _sameValues(Map<String, Object> a, Map<String, Object> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

bool _sameDocument(WidgetPublication a, WidgetPublication b) =>
    a.ownerEpoch == b.ownerEpoch &&
    a.publicationRevision == b.publicationRevision &&
    a.localeRevision == b.localeRevision &&
    a.state == b.state &&
    a.locale == b.locale &&
    a.snapshotDay == b.snapshotDay &&
    a.snapshotUtcOffsetMinutes == b.snapshotUtcOffsetMinutes &&
    a.capturedAtMillis == b.capturedAtMillis &&
    _sameValues(a.values, b.values);
