import 'dart:async';

/// The language is selected once when a serialized registration starts.
class DigestReminderRun {
  const DigestReminderRun({
    required this.accountGeneration,
    required this.isEnglish,
    required bool Function() isCurrent,
  }) : _isCurrent = isCurrent;

  final int accountGeneration;
  final bool isEnglish;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
}

/// One queue for daily and report reminders, drained before account cleanup.
class DigestReminderCoordinator {
  DigestReminderCoordinator({
    required this.currentAccountGeneration,
    required this.captureEnglish,
    bool Function()? isAccountAvailable,
  }) : isAccountAvailable = isAccountAvailable ?? (() => true);

  final int Function() currentAccountGeneration;
  final bool Function() captureEnglish;
  final bool Function() isAccountAvailable;
  Future<void>? _tail;
  bool _suspended = false;
  int _suspensionRevision = 0;

  bool get isSuspended => _suspended;

  void suspendForAccountChange() {
    _suspended = true;
    _suspensionRevision++;
  }

  /// Call only after a successful auth transition or storage recovery.
  bool resumeForActiveAccount() {
    if (!isAccountAvailable()) return false;
    _suspended = false;
    return true;
  }

  Future<T> run<T>(
    FutureOr<T> Function(DigestReminderRun run) action, {
    int? submittedAccountGeneration,
    required T Function() skippedResult,
  }) {
    final generation = submittedAccountGeneration ?? currentAccountGeneration();
    final suspensionRevision = _suspensionRevision;
    bool isCurrent() =>
        !_suspended &&
        isAccountAvailable() &&
        suspensionRevision == _suspensionRevision &&
        generation == currentAccountGeneration();
    FutureOr<T> invoke() {
      if (!isCurrent()) return skippedResult();
      return action(
        DigestReminderRun(
          accountGeneration: generation,
          isEnglish: captureEnglish(),
          isCurrent: isCurrent,
        ),
      );
    }

    final previous = _tail;
    final result = previous == null
        ? Future<T>.sync(invoke)
        : previous.then<T>((_) => invoke());
    late final Future<void> tail;
    void release() {
      // Release completed futures, including their source zones, while idle.
      if (identical(_tail, tail)) _tail = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _tail = tail;
    return result;
  }

  Future<void> drain() async {
    while (_tail != null) {
      await _tail;
    }
  }
}
