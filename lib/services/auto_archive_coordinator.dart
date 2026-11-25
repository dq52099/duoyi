import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/account_preference_writes.dart';
import '../core/completion_visibility_policy.dart';
import '../core/local_timezone_resolver.dart';
import '../providers/auth_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/todo_provider.dart';
import 'account_local_data_cleaner.dart';

/// App lifetime policy work. Pages never own the timer or a reload barrier.
class AutoArchiveCoordinator {
  AutoArchiveCoordinator({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  TodoProvider? _todos;
  PreferencesProvider? _preferences;
  AuthProvider? _auth;
  GoalProvider? _goals;
  Timer? _midnight;
  Future<void>? _running;
  bool _scheduled = false;
  bool _disposed = false;
  bool _accountSuspended = false;
  int _bindingEpoch = 0;
  int _workEpoch = 0;
  int _reloadDepth = 0;
  bool _archivePending = false;
  bool _goalsPending = false;
  Object? _preferencesState;
  Object? _authState;
  Object? _goalSourceState;
  Object? _calendarState;
  Object? _lastArchive;
  Object? _lastGoals;
  Object? _failedArchive;
  Object? _failedGoals;

  void bind({
    required TodoProvider todos,
    required PreferencesProvider preferences,
    required AuthProvider auth,
    required GoalProvider goals,
  }) {
    if (_disposed ||
        (identical(_todos, todos) &&
            identical(_preferences, preferences) &&
            identical(_auth, auth) &&
            identical(_goals, goals))) {
      return;
    }
    _detach();
    _bindingEpoch++;
    _workEpoch++;
    _todos = todos;
    _preferences = preferences;
    _auth = auth;
    _goals = goals;
    _preferencesState = _preferenceState();
    _authState = _sessionState();
    _goalSourceState = _goalState();
    _calendarState = (_day(), _zone());
    _accountSuspended =
        auth.isAccountTransitionInProgress || auth.isLocalAccountDataBlocked;
    todos.authoritativeStorageUpdate = withAuthoritativeReload;
    todos.addListener(_onTodos);
    todos.todoMutationReleaseListenable.addListener(_onMutationReleased);
    preferences.addListener(_onPreferences);
    auth.addListener(_onAuth);
    goals.addListener(_onGoals);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccount,
    );
    request(recurringGoals: true);
    _scheduleMidnight();
  }

  Object _preferenceState() => (
    _preferences?.storageGeneration,
    _preferences?.isStorageLoaded,
    _preferences?.autoArchiveCompletedDays,
    _preferences?.followSystemTimeZone,
    _preferences?.appTimeZone,
  );
  Object _sessionState() => (
    _auth?.sessionGeneration,
    _auth?.isAccountTransitionInProgress,
    _auth?.isLocalAccountDataBlocked,
  );
  Object _goalState() => (
    _goals?.storageGeneration,
    _goals?.storageReadRevision,
    _goals?.isStorageHydrated,
  );
  Object _day() {
    final now = _now();
    return (now.year, now.month, now.day);
  }

  Object _zone() => (LocalTimezoneResolver.currentIana, _now().timeZoneOffset);
  Object _archiveKey() => (
    _bindingEpoch,
    AccountLocalDataCleaner.accountDataGeneration,
    _todos?.storageGeneration,
    _todos?.revision,
    _preferences?.storageGeneration,
    _preferences?.autoArchiveCompletedDays,
    _day(),
    _zone(),
  );
  Object _goalKey() => (
    _bindingEpoch,
    AccountLocalDataCleaner.accountDataGeneration,
    _goals?.storageGeneration,
    _goals?.storageReadRevision,
    _day(),
    _zone(),
  );

  bool get _canRun =>
      !_disposed &&
      !_accountSuspended &&
      _reloadDepth == 0 &&
      !AccountPreferenceWrites.isBoundaryActive &&
      _auth != null &&
      !_auth!.isAccountTransitionInProgress &&
      !_auth!.isLocalAccountDataBlocked;
  bool get _archiveReady =>
      _canRun &&
      _preferences?.isStorageLoaded == true &&
      _todos?.isStorageHydrated == true;
  bool get _goalsReady => _canRun && _goals?.isStorageHydrated == true;

  void _onTodos() => _request();
  void _onMutationReleased() {
    _failedArchive = null;
    _request();
  }

  void _onPreferences() {
    final next = _preferenceState();
    if (next == _preferencesState) return;
    final calendar = (_day(), _zone());
    final calendarChanged = calendar != _calendarState;
    _calendarState = calendar;
    _preferencesState = next;
    _workEpoch++;
    _request(recurringGoals: calendarChanged);
    _scheduleMidnight();
  }

  void _onGoals() {
    final next = _goalState();
    if (next == _goalSourceState) return;
    _goalSourceState = next;
    _request(recurringGoals: true);
  }

  void _onAuth() {
    final next = _sessionState();
    if (next == _authState) return;
    _authState = next;
    _workEpoch++;
    _accountSuspended =
        _auth!.isAccountTransitionInProgress ||
        _auth!.isLocalAccountDataBlocked;
    _request(recurringGoals: true);
    _scheduleMidnight();
  }

  void _onAccount() {
    _workEpoch++;
    _request(recurringGoals: true);
  }

  /// Explicit events may retry a failed scan. Provider notifications alone
  /// cannot spin on a refused write or a refused dirty marker.
  void request({bool recurringGoals = false}) {
    if (_disposed) return;
    _failedArchive = null;
    if (recurringGoals) _failedGoals = null;
    _request(recurringGoals: recurringGoals);
  }

  void _request({bool recurringGoals = false}) {
    if (_disposed) return;
    _archivePending = true;
    _goalsPending |= recurringGoals;
    _scheduleDrain();
  }

  bool get _hasWork =>
      (_archivePending && _archiveReady && _archiveKey() != _failedArchive) ||
      (_goalsPending && _goalsReady && _goalKey() != _failedGoals);
  void _scheduleDrain() {
    if (_scheduled || _running != null || !_hasWork) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_running != null || !_hasWork) return;
      final running = Future<void>.sync(_drain);
      _running = running;
      running.then(
        (_) {
          if (identical(_running, running)) _running = null;
          _scheduleDrain();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_running, running)) _running = null;
          debugPrint('[AutoArchive] unexpected batch failure: $error\n$stack');
        },
      );
    });
  }

  bool Function() _receipt({required bool archive}) {
    final epoch = _workEpoch;
    final binding = _bindingEpoch;
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final session = _auth?.sessionGeneration;
    final todoGeneration = _todos?.storageGeneration;
    final preferenceGeneration = _preferences?.storageGeneration;
    final days = _preferences?.autoArchiveCompletedDays;
    final goalGeneration = _goals?.storageGeneration;
    final goalRead = _goals?.storageReadRevision;
    final day = _day();
    final zone = _zone();
    return () =>
        _canRun &&
        epoch == _workEpoch &&
        binding == _bindingEpoch &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(account) &&
        session == _auth?.sessionGeneration &&
        day == _day() &&
        zone == _zone() &&
        (archive
            ? _archiveReady &&
                  todoGeneration == _todos?.storageGeneration &&
                  preferenceGeneration == _preferences?.storageGeneration &&
                  days == _preferences?.autoArchiveCompletedDays
            : _goalsReady &&
                  goalGeneration == _goals?.storageGeneration &&
                  goalRead == _goals?.storageReadRevision);
  }

  Future<void> _drain() async {
    // Goal work has its own owner and remains runnable after archive failures.
    if (_archivePending && _archiveReady && _archiveKey() != _failedArchive) {
      _archivePending = false;
      final key = _archiveKey();
      if (key != _lastArchive) {
        final current = _receipt(archive: true);
        final todos = _todos!;
        final days = _preferences!.autoArchiveCompletedDays;
        int? busyReleaseRevision;
        try {
          final success = await todos.archivePastCompletions(
            _now(),
            completedDays: days,
            canWrite: current,
            onBusy: () =>
                busyReleaseRevision = todos.todoMutationReleaseListenable.value,
          );
          if (current()) {
            if (success) {
              _lastArchive = key;
            } else if (busyReleaseRevision != null &&
                busyReleaseRevision !=
                    todos.todoMutationReleaseListenable.value) {
              _archivePending = true;
              _failedArchive = null;
            } else {
              _failedArchive = _archiveKey();
            }
          }
        } catch (error, stack) {
          if (current()) _failedArchive = _archiveKey();
          debugPrint('[AutoArchive] archive not confirmed: $error\n$stack');
        }
      }
    }
    if (_goalsPending && _goalsReady && _goalKey() != _failedGoals) {
      _goalsPending = false;
      final key = _goalKey();
      if (key != _lastGoals) {
        final current = _receipt(archive: false);
        try {
          await CompletionVisibilityPolicy.runRecurringGoalRollover(
            _goals!,
            CompletionVisibilityPolicy.dateOnly(_now()),
            isCurrent: current,
          );
          if (current()) _lastGoals = key;
        } catch (error, stack) {
          if (current()) _failedGoals = _goalKey();
          debugPrint(
            '[AutoArchive] recurring goal request failed: $error\n$stack',
          );
        }
      }
    }
  }

  void onResume() {
    if (_disposed) return;
    request(recurringGoals: true);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    _midnight = null;
    if (!_canRun) return;
    final now = _now();
    final next = DateTime(now.year, now.month, now.day + 1);
    final delay = next.difference(now);
    _midnight = Timer(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
      () {
        request(recurringGoals: true);
        _scheduleMidnight();
      },
    );
  }

  Future<void> suspendAndDrain() async {
    _accountSuspended = true;
    _workEpoch++;
    _midnight?.cancel();
    await _running;
  }

  void resumeAfterAccountPreflightFailure() {
    if (_disposed ||
        _auth?.isAccountTransitionInProgress != false ||
        _auth?.isLocalAccountDataBlocked != false) {
      return;
    }
    _accountSuspended = false;
    _workEpoch++;
    request(recurringGoals: true);
    _scheduleMidnight();
  }

  /// Pauses before storage is applied and reloads both policy sources even if
  /// the originating page has closed. Nesting keeps the pause until all exit.
  Future<T> withAuthoritativeReload<T>(Future<T> Function() operation) async {
    if (_disposed) throw const AccountPreferenceWriteCanceled();
    final todos = _todos;
    final preferences = _preferences;
    final binding = _bindingEpoch;
    final account = AccountLocalDataCleaner.accountDataGeneration;
    final session = _auth?.sessionGeneration;
    bool ownsSources() =>
        !_disposed &&
        binding == _bindingEpoch &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(account) &&
        session == _auth?.sessionGeneration;
    _reloadDepth++;
    _workEpoch++;
    _midnight?.cancel();
    Object? operationError;
    try {
      await _running;
      if (!ownsSources()) throw const AccountPreferenceWriteCanceled();
      if (todos != null && !await todos.retryPendingArchiveMutationMarker()) {
        throw StateError('Archive pending-sync marker is not confirmed');
      }
      if (!ownsSources()) throw const AccountPreferenceWriteCanceled();
      return await operation();
    } catch (error) {
      operationError = error;
      rethrow;
    } finally {
      try {
        if (ownsSources() && todos != null && preferences != null) {
          preferences.resetLocalState();
          await Future.wait([
            preferences.loadFromStorage(),
            todos.loadFromStorage(force: true),
          ]);
        }
      } catch (error, stack) {
        if (operationError == null) rethrow;
        debugPrint('[AutoArchive] reload after failed apply: $error\n$stack');
      } finally {
        _reloadDepth--;
        if (ownsSources()) request(recurringGoals: true);
        _scheduleDrain();
        _scheduleMidnight();
      }
    }
  }

  void _detach() {
    if (_todos?.authoritativeStorageUpdate == withAuthoritativeReload) {
      _todos!.authoritativeStorageUpdate = null;
    }
    _todos?.removeListener(_onTodos);
    _todos?.todoMutationReleaseListenable.removeListener(_onMutationReleased);
    _preferences?.removeListener(_onPreferences);
    _auth?.removeListener(_onAuth);
    _goals?.removeListener(_onGoals);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccount,
    );
    _midnight?.cancel();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _workEpoch++;
    _detach();
  }
}
