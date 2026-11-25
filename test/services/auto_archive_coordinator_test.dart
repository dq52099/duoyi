import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/auto_archive_coordinator.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(AccountPreferenceWrites.drain);

  test(
    'bind waits for both successful sources and catches up at hydration',
    () async {
      final f = _Fixture(ready: false);
      addTearDown(f.dispose);
      f.coordinator.request();
      await _settle();
      expect(f.todos.calls, isEmpty);
      f.preferences.hydrated = true;
      f.preferences.changed();
      await _settle();
      expect(f.todos.calls, isEmpty);
      f.todos.hydrated = true;
      f.todos.changed();
      await _settle();
      expect(f.todos.calls.single.days, 7);
    },
  );

  test(
    'same-day policy changes coalesce and invalidate held old decisions',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final gate = Completer<void>();
      f.todos.hold = gate;
      await _settle();
      expect(f.todos.calls.single.days, 7);
      final old = f.todos.calls.single;
      f.preferences.days = 14;
      f.preferences.changed();
      f.preferences.days = 0;
      f.preferences.changed();
      expect(old.isCurrent(), isFalse);
      gate.complete();
      await _settle();
      expect(f.todos.calls.map((call) => call.days), [7, 0]);
      expect(f.todos.accepted, [0]);
    },
  );

  test('unrelated preferences do not scan or replay recurring goals', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await _settle();
    expect(f.goals.requests, 1);
    f.preferences.changed();
    await _settle();
    expect(f.todos.calls, hasLength(1));
    expect(f.goals.requests, 1);
    f.preferences.days = 0;
    f.preferences.changed();
    await _settle();
    expect(f.todos.accepted, [7, 0]);
    expect(f.goals.requests, 1);
  });

  for (final failure in ['false', 'throw']) {
    test(
      'archive $failure does not block goals or spin; resume retries',
      () async {
        final f = _Fixture();
        addTearDown(f.dispose);
        f.todos.failure = failure;
        f.todos.releaseDuringFailure = true;
        await _settle();
        expect(f.todos.calls, hasLength(1));
        expect(f.goals.requests, 1);
        f.todos.notifyWithoutRevision();
        await _settle();
        expect(f.todos.calls, hasLength(1));
        f.todos.failure = null;
        f.coordinator.onResume();
        await _settle();
        expect(f.todos.calls, hasLength(2));
        expect(f.todos.accepted, [7]);
        expect(f.goals.requests, 1);
      },
    );
  }

  test(
    'a busy release before the false continuation retains its catch-up',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.todos.failure = 'busy';
      f.todos.releaseDuringFailure = true;
      await _settle();
      expect(f.todos.calls, hasLength(2));
      expect(f.todos.accepted, [7]);
    },
  );

  test(
    'a later busy release wakes a failed scan without changing todo revision',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.todos.failure = 'busy';
      await _settle();
      expect(f.todos.calls, hasLength(1));
      f.todos.failure = null;
      f.todos.releases.value++;
      await _settle();
      expect(f.todos.calls, hasLength(2));
      expect(f.todos.accepted, [7]);
    },
  );

  test(
    'zero archive policy still requests daily recurring goal reminders',
    () async {
      final f = _Fixture(days: 0);
      addTearDown(f.dispose);
      await _settle();
      expect(f.todos.accepted, [0]);
      expect(f.goals.requests, 1);
      f.now = DateTime(2026, 10, 15);
      f.coordinator.onResume();
      await _settle();
      expect(f.todos.accepted, [0, 0]);
      expect(f.goals.requests, 2);
    },
  );

  test('midnight is app-owned and catches up without any page', () {
    fakeAsync((clock) {
      final initial = DateTime(2026, 10, 14, 23, 59, 59);
      final f = _Fixture(now: () => initial.add(clock.elapsed));
      clock.flushMicrotasks();
      expect(f.todos.calls, hasLength(1));
      clock.elapse(const Duration(seconds: 2));
      expect(f.todos.calls, hasLength(2));
      expect(f.todos.calls.last.day.day, 15);
      expect(f.goals.requests, 2);
      f.dispose();
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'same-day authoritative reload cancels and drains before apply',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final gate = Completer<void>();
      f.todos.hold = gate;
      await _settle();
      final old = f.todos.calls.single;
      var applied = false;
      final operation = f.coordinator.withAuthoritativeReload(() async {
        applied = true;
        f.preferences.days = 30;
        return 4;
      });
      await _settle();
      expect(old.isCurrent(), isFalse);
      expect(applied, isFalse);
      gate.complete();
      expect(await operation, 4);
      await _settle();
      expect(applied, isTrue);
      expect(f.preferences.reloads, 1);
      expect(f.todos.reloads, 1);
      expect(f.todos.accepted, [30]);
    },
  );

  test(
    'source replacement during held marker cannot enter the old apply',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await _settle();
      final marker = Completer<bool>();
      f.todos.marker = marker;
      var applied = false;
      final operation = f.coordinator.withAuthoritativeReload(
        () async => applied = true,
      );
      final assertion = expectLater(
        operation,
        throwsA(isA<AccountPreferenceWriteCanceled>()),
      );
      await _settle();
      final nextTodos = _Todos();
      addTearDown(nextTodos.dispose);
      f.coordinator.bind(
        todos: nextTodos,
        preferences: f.preferences,
        auth: f.auth,
        goals: f.goals,
      );
      marker.complete(true);
      await assertion;
      await _settle();
      expect(applied, isFalse);
      expect(nextTodos.calls, hasLength(1));
    },
  );

  test(
    'failed authoritative apply releases barrier and reloads both sources',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await _settle();
      await expectLater(
        f.coordinator.withAuthoritativeReload<void>(() async {
          f.preferences.days = 0;
          throw StateError('synthetic apply failure');
        }),
        throwsStateError,
      );
      await _settle();
      expect(f.preferences.reloads, 1);
      expect(f.todos.reloads, 1);
      expect(f.todos.accepted, [7, 0]);
    },
  );

  test(
    'failed source read is unready until the next successful reload',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await _settle();
      f.preferences.failRead = true;
      await expectLater(
        f.coordinator.withAuthoritativeReload(() async {}),
        throwsStateError,
      );
      await _settle();
      f.coordinator.onResume();
      await _settle();
      expect(f.todos.calls, hasLength(1));
      f.preferences.failRead = false;
      await f.preferences.loadFromStorage();
      await _settle();
      expect(f.todos.calls, hasLength(2));
    },
  );

  test(
    'preflight failure before Auth transition can resume the original owner',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await _settle();
      await f.coordinator.suspendAndDrain();
      f.todos.changed();
      f.coordinator.onResume();
      await _settle();
      expect(f.todos.calls, hasLength(1));
      f.coordinator.resumeAfterAccountPreflightFailure();
      await _settle();
      expect(f.todos.calls, hasLength(2));
    },
  );

  test(
    'blocked/transition owners cannot run or release their account pause',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await _settle();
      f.auth.blocked = true;
      f.auth.changed();
      f.todos.changed();
      f.coordinator.resumeAfterAccountPreflightFailure();
      f.coordinator.onResume();
      await _settle();
      expect(f.todos.calls, hasLength(1));
      f.auth.blocked = false;
      f.auth.changed();
      await _settle();
      expect(f.todos.calls, hasLength(2));
    },
  );

  test(
    'account generation invalidates a held batch even before providers reset',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final gate = Completer<void>();
      f.todos.hold = gate;
      await _settle();
      final old = f.todos.calls.single;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(old.isCurrent(), isFalse);
      f.auth.blocked = true;
      f.auth.changed();
      gate.complete();
      await _settle();
      expect(f.todos.accepted, isEmpty);
    },
  );

  test(
    'dispose and rebind remove old listeners, timers, and late authority',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final gate = Completer<void>();
      f.todos.hold = gate;
      await _settle();
      final old = f.todos.calls.single;
      f.coordinator.dispose();
      expect(old.isCurrent(), isFalse);
      f.todos.changed();
      f.preferences.days = 0;
      f.preferences.changed();
      gate.complete();
      await _settle();
      expect(f.todos.calls, hasLength(1));
      expect(f.todos.accepted, isEmpty);
      expect(f.todos.authoritativeStorageUpdate, isNull);
    },
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Fixture {
  _Fixture({bool ready = true, int days = 7, DateTime Function()? now}) {
    preferences.hydrated = ready;
    preferences.days = days;
    todos.hydrated = ready;
    coordinator = AutoArchiveCoordinator(now: now ?? () => this.now);
    coordinator.bind(
      todos: todos,
      preferences: preferences,
      auth: auth,
      goals: goals,
    );
  }
  DateTime now = DateTime(2026, 10, 14, 12);
  final todos = _Todos();
  final preferences = _Preferences();
  final auth = _Auth();
  final goals = _Goals();
  late final AutoArchiveCoordinator coordinator;
  void dispose() {
    coordinator.dispose();
    todos.dispose();
    preferences.dispose();
    auth.dispose();
    goals.dispose();
  }
}

class _ArchiveCall {
  _ArchiveCall(this.day, this.days, this.isCurrent);
  final DateTime day;
  final int days;
  final bool Function() isCurrent;
}

class _Todos extends TodoProvider {
  final releases = ValueNotifier<int>(0);
  bool releaseDuringFailure = false;
  @override
  ValueListenable<int> get todoMutationReleaseListenable => releases;
  bool hydrated = true;
  int version = 0;
  int reloads = 0;
  String? failure;
  Completer<void>? hold;
  Completer<bool>? marker;
  final calls = <_ArchiveCall>[];
  final accepted = <int>[];
  @override
  bool get isStorageHydrated => hydrated;
  @override
  int get revision => version;
  void changed() {
    version++;
    notifyListeners();
  }

  void notifyWithoutRevision() => notifyListeners();
  @override
  Future<bool> archivePastCompletions(
    DateTime todayDay, {
    int completedDays = 1,
    bool Function()? canWrite,
    VoidCallback? onBusy,
  }) async {
    final current = canWrite ?? () => true;
    calls.add(_ArchiveCall(todayDay, completedDays, current));
    final gate = hold;
    hold = null;
    if (gate != null) await gate.future;
    if (!current()) return false;
    if (failure == 'busy') {
      onBusy?.call();
      if (releaseDuringFailure) {
        failure = null;
        releases.value++;
      }
      return false;
    }
    if (failure != null && releaseDuringFailure) releases.value++;
    if (failure == 'throw') throw StateError('synthetic archive refusal');
    if (failure == 'false') return false;
    accepted.add(completedDays);
    return true;
  }

  @override
  Future<void> loadFromStorage({bool force = false}) async {
    reloads++;
    hydrated = true;
    changed();
  }

  @override
  Future<bool> retryPendingArchiveMutationMarker() async =>
      marker == null ? true : await marker!.future;
  @override
  void dispose() {
    releases.dispose();
    super.dispose();
  }
}

class _Preferences extends PreferencesProvider {
  bool hydrated = true;
  bool failRead = false;
  int days = 7;
  int generation = 0;
  int reloads = 0;
  @override
  bool get isStorageLoaded => hydrated;
  @override
  int get storageGeneration => generation;
  @override
  int get autoArchiveCompletedDays => days;
  void changed() => notifyListeners();
  @override
  void resetLocalState() {
    generation++;
    hydrated = false;
    changed();
  }

  @override
  Future<void> loadFromStorage() async {
    reloads++;
    hydrated = false;
    if (failRead) throw StateError('synthetic preference read refusal');
    hydrated = true;
    changed();
  }
}

class _Auth extends AuthProvider {
  bool blocked = false;
  @override
  bool get isLocalAccountDataBlocked => blocked;
  void changed() => notifyListeners();
}

class _Goals extends GoalProvider {
  int requests = 0;
  @override
  bool get isStorageHydrated => true;
  @override
  List<GoalItem> get goals => [
    GoalItem(
      id: 'synthetic-recurring-goal',
      title: 'Synthetic daily goal',
      startDate: DateTime(2026, 1, 1),
      recurrence: const RecurrenceRule(frequency: RecurrenceFrequency.daily),
    ),
  ];
  @override
  Future<void> onTimezoneChanged() async => requests++;
}
