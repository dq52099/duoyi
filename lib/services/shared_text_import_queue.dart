import 'dart:collection';

/// Serializes external share drafts and keeps their original account binding.
/// Unlocking reopens the choice sheet; it never confirms an import.
class SharedTextImportQueue {
  SharedTextImportQueue({
    required this.accountGeneration,
    required this.isBlocked,
    required this.isReady,
    required this.open,
    this.onError,
  });

  final int Function() accountGeneration;
  final bool Function() isBlocked;
  final bool Function() isReady;
  final Future<void> Function(SharedTextImportRequest) open;
  final void Function(Object, StackTrace)? onError;
  final _pending = Queue<SharedTextImportRequest>();
  bool _opening = false;

  void receive(String text, {int? receivedAccountGeneration}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _pending.add(
      SharedTextImportRequest._(
        this,
        trimmed,
        receivedAccountGeneration ?? accountGeneration(),
      ),
    );
  }

  Future<void> drain() async {
    if (_opening) return;
    _opening = true;
    try {
      while (_pending.isNotEmpty && !isBlocked() && isReady()) {
        final request = _pending.removeFirst();
        request._deferred = false;
        if (!request.isCurrentAccount) continue;
        try {
          await open(request);
        } catch (error, stack) {
          onError?.call(error, stack);
        } finally {
          if (!request._deferred) request._finished = true;
        }
      }
    } finally {
      _opening = false;
    }
  }

  void _defer(SharedTextImportRequest request) {
    if (!request.isCurrentAccount ||
        request._finished ||
        request._actionStarted ||
        request._deferred) {
      return;
    }
    request._deferred = true;
    _pending.addFirst(request);
  }
}

class SharedTextImportRequest {
  SharedTextImportRequest._(
    this._queue,
    this.text,
    this.accountGeneration, {
    String? noteId,
  }) : noteId =
           noteId ??
           'share_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}';

  static int _nextId = 0;

  final SharedTextImportQueue _queue;
  final String text;
  final int accountGeneration;
  final String noteId;
  bool _deferred = false;
  bool _finished = false;
  bool _actionStarted = false;
  bool _retryQueued = false;

  bool get isCurrentAccount => accountGeneration == _queue.accountGeneration();
  bool get canProceed =>
      !_finished &&
      !_deferred &&
      isCurrentAccount &&
      !_queue.isBlocked() &&
      _queue.isReady();

  bool get canDeliverFeedback =>
      isCurrentAccount && !_queue.isBlocked() && _queue.isReady();

  void defer() => _queue._defer(this);

  /// A write that has already started must never be replayed after unlocking.
  void markActionStarted() => _actionStarted = true;

  /// Explicit retry keeps the note identity even if storage acceptance was unclear.
  /// Locks never retry an already started write automatically.
  bool retry() {
    if (_retryQueued ||
        !isCurrentAccount ||
        _queue.isBlocked() ||
        !_queue.isReady()) {
      return false;
    }
    _retryQueued = true;
    _queue._pending.add(
      SharedTextImportRequest._(
        _queue,
        text,
        accountGeneration,
        noteId: noteId,
      ),
    );
    return true;
  }
}
