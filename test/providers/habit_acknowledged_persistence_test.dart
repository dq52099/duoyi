// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late HabitProvider habits;
  late TimeAuditProvider audit;
  late StreamSubscription<DomainEvent> subscription;
  final events = <DomainEvent>[];
  var disposed = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    habits = HabitProvider();
    audit = TimeAuditProvider();
    habits.timeAudit = audit;
    disposed = false;
    events.clear();
    subscription = DomainEventBus.instance.events.listen(events.add);
  });
  tearDown(() async {
    if (!store.release.isCompleted) store.release.complete();
    if (!store.tombstoneRelease.isCompleted) store.tombstoneRelease.complete();
    await AccountPreferenceWrites.drain();
    await subscription.cancel();
    if (!disposed) habits.dispose();
    audit.dispose();
  });

  test(
    'cold creation hydrates existing habits and publishes after acknowledgement',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('habits', jsonEncode([_habit('prior').toJson()]));
      var persisted = 0;
      habits.onLocalMutationPersisted = () => persisted++;
      store.hold = true;
      final create = habits.addHabit(_habit('new'));
      await store.started.future;
      try {
        expect(habits.habits.map((h) => h.id), ['prior']);
        expect(events, isEmpty);
        expect(persisted, 0);
      } finally {
        store.release.complete();
      }
      await create;
      expect(_saved(prefs).map((h) => h.id).toSet(), {'prior', 'new'});
      expect(events.single.type, DomainEventType.habitCreated);
      expect(persisted, 1);
    },
  );

  for (final throwError in [false, true]) {
    test(
      'failed creation $throwError leaves no habit or success event and can retry',
      () async {
        await habits.addHabit(_habit('prior'));
        events.clear();
        var persisted = 0;
        habits.onLocalMutationPersisted = () => persisted++;
        final prefs = await SharedPreferences.getInstance();
        store.reject = true;
        store.throwError = throwError;
        await expectLater(
          habits.addHabit(_habit('rejected')),
          throwsStateError,
        );
        expect(habits.habits.map((h) => h.id), ['prior']);
        expect(_saved(prefs).map((h) => h.id), ['prior']);
        expect(events, isEmpty);
        expect(persisted, 0);
        await habits.addHabit(_habit('rejected'));
        expect(habits.habits.map((h) => h.id), ['prior', 'rejected']);
      },
    );

    test(
      'failed check-in $throwError does not change memory, disk, rewards or time audit',
      () async {
        await habits.addHabit(_habit('check-in'));
        events.clear();
        var persisted = 0;
        habits.onLocalMutationPersisted = () => persisted++;
        final prefs = await SharedPreferences.getInstance();
        final heldReference = habits.habits.single;
        store.reject = true;
        store.throwError = throwError;
        await expectLater(habits.incrementHabit('check-in'), throwsStateError);
        expect(habits.habits.single.todayCount(), 0);
        expect(heldReference.todayCount(), 0);
        expect(_saved(prefs).single.todayCount(), 0);
        expect(events, isEmpty);
        expect(persisted, 0);
        expect(audit.entries, isEmpty);
        await habits.incrementHabit('check-in');
        expect(habits.habits.single.todayCount(), 1);
        expect(_saved(prefs).single.todayCount(), 1);
        expect(events.single.type, DomainEventType.habitCheckedIn);
      },
    );
  }

  test(
    'rapid check-ins serialize and retain all acknowledged counts',
    () async {
      await habits.addHabit(_habit('rapid'));
      final prefs = await SharedPreferences.getInstance();
      final baseline = store.habitWrites;
      store.hold = true;
      final first = habits.incrementHabit('rapid');
      await store.started.future;
      final second = habits.incrementHabit('rapid');
      final third = habits.incrementHabit('rapid');
      try {
        await Future<void>.delayed(Duration.zero);
        expect(store.habitWrites, baseline + 1);
        expect(habits.habits.single.todayCount(), 0);
      } finally {
        store.release.complete();
      }
      await Future.wait([first, second, third]);
      expect(habits.habits.single.todayCount(), 3);
      expect(_saved(prefs).single.todayCount(), 3);
    },
  );

  test(
    'queued configuration edit keeps a concurrently acknowledged check-in',
    () async {
      await habits.addHabit(_habit('editing'));
      final draft = habits.habits.single.copyWith(name: 'Updated label');
      store.hold = true;
      final checkIn = habits.incrementHabit('editing');
      await store.started.future;
      final edit = habits.updateHabit('editing', draft);
      store.release.complete();
      await Future.wait([checkIn, edit]);
      final prefs = await SharedPreferences.getInstance();
      expect(habits.habits.single.name, 'Updated label');
      expect(habits.habits.single.todayCount(), 1);
      expect(_saved(prefs).single.todayCount(), 1);
    },
  );

  for (final mutation in [
    'import',
    'decrement',
    'update',
    'end',
    'reorder',
    'delete',
  ]) {
    test(
      'rejected $mutation retains acknowledged models and storage',
      () async {
        await habits.addHabit(_habit('one'));
        await habits.addHabit(_habit('two'));
        await habits.incrementHabit('one');
        events.clear();
        final prefs = await SharedPreferences.getInstance();
        final memoryBefore = jsonEncode(
          habits.habits.map((h) => h.toJson()).toList(),
        );
        final diskBefore = prefs.getString('habits');
        var persisted = 0;
        habits.onLocalMutationPersisted = () => persisted++;
        store.reject = true;
        final Future<Object?> pending = switch (mutation) {
          'import' => habits.importHabits([_habit('three')]),
          'decrement' => habits.decrementHabit('one'),
          'update' => habits.updateHabit(
            'one',
            habits.habits.first.copyWith(name: 'Unacknowledged label'),
          ),
          'end' => habits.endHabit('one'),
          'reorder' => habits.reorder(['two', 'one']),
          _ => habits.deleteHabit('one'),
        };
        await expectLater(pending, throwsStateError);
        expect(
          jsonEncode(habits.habits.map((h) => h.toJson()).toList()),
          memoryBefore,
        );
        expect(prefs.getString('habits'), diskBefore);
        expect(prefs.getString('sync_deleted_items'), isNull);
        expect(persisted, 0);
        expect(events, isEmpty);
      },
    );
  }

  test(
    'failed deletion tombstone rolls back habit and retains time records',
    () async {
      await habits.addHabit(_habit('timed', unit: '分钟'));
      await habits.incrementHabit('timed');
      expect(audit.entries, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString('habits');
      events.clear();
      store.rejectTombstone = true;
      await expectLater(habits.deleteHabit('timed'), throwsStateError);
      expect(prefs.getString('habits'), before);
      expect(prefs.getString('sync_deleted_items'), isNull);
      expect(habits.habits.single.id, 'timed');
      expect(audit.entries, hasLength(1));
      expect(events, isEmpty);
      await habits.deleteHabit('timed');
      expect(habits.habits, isEmpty);
      expect(audit.entries, isEmpty);
      expect(
        jsonDecode(prefs.getString('sync_deleted_items')!)['habits'],
        contains('timed'),
      );
    },
  );

  test(
    'concurrent same-ID creation publishes one acknowledged habit',
    () async {
      store.hold = true;
      final first = habits.addHabit(_habit('same'));
      await store.started.future;
      final second = habits.addHabit(_habit('same'));
      store.release.complete();
      await Future.wait([first, second]);
      expect(habits.habits, hasLength(1));
      expect(
        events.where((e) => e.type == DomainEventType.habitCreated),
        hasLength(1),
      );
    },
  );

  test(
    'failed habit deletion cannot erase another collection tombstone',
    () async {
      await habits.addHabit(_habit('habit-delete'));
      store.holdTombstone = true;
      store.rejectTombstone = true;
      final deletion = expectLater(
        habits.deleteHabit('habit-delete'),
        throwsStateError,
      );
      await store.tombstoneStarted.future;
      final other = CloudSyncProvider.recordDeletedItem(
        'todos',
        'distinct-todo',
      );
      await Future<void>.delayed(Duration.zero);
      store.tombstoneRelease.complete();
      await Future.wait([deletion, other]);
      final prefs = await SharedPreferences.getInstance();
      final tombstones =
          jsonDecode(prefs.getString('sync_deleted_items')!) as Map;
      expect(tombstones['todos'], contains('distinct-todo'));
      expect(tombstones['habits'], isNull);
      expect(habits.habits.single.id, 'habit-delete');
    },
  );

  for (final interruption in ['reset', 'dispose']) {
    for (final timing in ['synchronous', 'microtask']) {
      for (final mutation in [
        'add',
        'increment',
        'decrement',
        'end',
        'update',
        'reorder',
      ]) {
        test(
          '$interruption $timing after $mutation acknowledgement cannot publish stale effects',
          () async {
            await habits.addHabit(_habit('one', unit: '分钟'));
            await habits.addHabit(_habit('two'));
            await habits.incrementHabitForDate(
              'one',
              DateTime.now(),
              amount: 1,
            );
            events.clear();
            final trace = <String>[];
            final invalidation = Completer<void>();
            var invalidated = false;
            var staleNotices = 0;
            var staleEvents = 0;
            habits.addListener(() {
              trace.add('notify');
              if (invalidated) staleNotices++;
            });
            final effectSubscription = DomainEventBus.instance.events.listen((
              _,
            ) {
              trace.add('event');
              if (invalidated) staleEvents++;
            });
            void invalidate() {
              trace.add('invalidate');
              if (interruption == 'dispose') {
                disposed = true;
                habits.dispose();
              } else {
                habits.resetLocalState();
              }
              audit.resetLocalState();
              // resetLocalState's own notification belongs to invalidation.
              invalidated = true;
              invalidation.complete();
            }

            habits.onLocalMutationPersisted = () {
              trace.add('acknowledged');
              if (timing == 'microtask') {
                scheduleMicrotask(invalidate);
              } else {
                invalidate();
              }
            };
            final Future<void> pending = switch (mutation) {
              'add' => habits.addHabit(_habit('three')),
              'increment' => habits.incrementHabitForDate(
                'one',
                DateTime.now(),
                amount: 1,
              ),
              'decrement' => habits.decrementHabit('one'),
              'end' => habits.endHabit('one'),
              'update' => habits.updateHabit(
                'one',
                habits.habits.first.copyWith(name: 'New name'),
              ),
              _ => habits.reorder(['two', 'one']),
            };
            try {
              var canceled = false;
              await pending.then<void>(
                (_) {
                  trace.add('completed');
                },
                onError: (Object error, StackTrace _) {
                  expect(error, isA<AccountPreferenceWriteCanceled>());
                  canceled = true;
                  trace.add('canceled');
                },
              );
              await invalidation.future;
              await AccountPreferenceWrites.drain();
              // A scheduled reset is not yet an invalidation. Dart may complete
              // an awaited Future inline before the scheduled microtask runs.
              // Synchronous invalidation must cancel; both schedules must stop
              // every effect after the provider actually becomes invalid.
              if (timing == 'synchronous') {
                expect(canceled, isTrue);
                expect(events, isEmpty);
              }
              expect(staleEvents, 0, reason: trace.join(' → '));
              expect(staleNotices, 0, reason: trace.join(' → '));
              expect(audit.entries, isEmpty, reason: trace.join(' → '));
              debugPrint(
                '$interruption/$timing/$mutation: ${trace.join(' → ')}',
              );
            } finally {
              await effectSubscription.cancel();
            }
          },
        );
      }
    }
  }

  test(
    'cleanup drains issued check-in and cancels follower without cross-account time record',
    () async {
      await habits.addHabit(_habit('old', unit: '分钟'));
      events.clear();
      final prefs = await SharedPreferences.getInstance();
      store.hold = true;
      var persisted = 0;
      habits.onLocalMutationPersisted = () => persisted++;
      final first = habits.incrementHabitForDate(
        'old',
        DateTime.now(),
        amount: 1,
      );
      final firstObserved = first.then<void>(
        (_) {},
        onError: (Object e, StackTrace _) {
          expect(e, isA<AccountPreferenceWriteCanceled>());
        },
      );
      await store.started.future;
      final follower = habits.incrementHabit('old');
      final followerObserved = follower.then<void>(
        (_) {},
        onError: (Object e, StackTrace _) {
          expect(e, isA<AccountPreferenceWriteCanceled>());
        },
      );
      var cleaned = false;
      final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then(
        (_) => cleaned = true,
      );
      habits.resetLocalState();
      audit.resetLocalState();
      try {
        await Future<void>.delayed(Duration.zero);
        expect(cleaned, isFalse);
      } finally {
        store.release.complete();
      }
      await Future.wait([firstObserved, followerObserved, cleanup]);
      expect(prefs.getString('habits'), isNull);
      expect(prefs.getStringList('duoyi_time_entries'), isNull);
      expect(habits.habits, isEmpty);
      expect(audit.entries, isEmpty);
      expect(events, isEmpty);
      expect(persisted, 0);
      await habits.addHabit(_habit('new-account'));
      expect(_saved(prefs).single.id, 'new-account');
    },
  );

  for (final channel in ['event', 'notification']) {
    for (final interruption in ['reset', 'dispose']) {
      test(
        '$channel listener $interruption prevents later TimeAudit call',
        () async {
          audit.dispose();
          final spy = _RecordCountingAudit();
          audit = spy;
          habits.timeAudit = spy;
          await habits.addHabit(_habit('reentrant', unit: '分钟'));
          var armed = true;
          void invalidate() {
            if (!armed) return;
            armed = false;
            if (interruption == 'dispose') {
              disposed = true;
              habits.dispose();
            } else {
              habits.resetLocalState();
            }
            spy.resetLocalState();
          }

          StreamSubscription<DomainEvent>? effects;
          if (channel == 'event') {
            effects = DomainEventBus.instance.events.listen((event) {
              if (event.type == DomainEventType.habitCheckedIn) invalidate();
            });
          } else {
            habits.addListener(invalidate);
          }
          try {
            await habits.incrementHabitForDate(
              'reentrant',
              DateTime.now(),
              amount: 1,
            );
            await AccountPreferenceWrites.drain();
            expect(armed, isFalse);
            expect(spy.recordCalls, 0);
            expect(spy.entries, isEmpty);
          } finally {
            await effects?.cancel();
          }
        },
      );
    }
  }

  for (final invalidate in ['reset', 'dispose']) {
    test(
      '$invalidate during acknowledged check-in suppresses later publication',
      () async {
        await habits.addHabit(_habit('stale', unit: '分钟'));
        events.clear();
        var notices = 0;
        var persisted = 0;
        habits.addListener(() => notices++);
        habits.onLocalMutationPersisted = () => persisted++;
        store.hold = true;
        final pending = habits.incrementHabitForDate(
          'stale',
          DateTime.now(),
          amount: 1,
        );
        final observed = pending.then<void>(
          (_) {},
          onError: (Object e, StackTrace _) {
            expect(e, isA<AccountPreferenceWriteCanceled>());
          },
        );
        await store.started.future;
        if (invalidate == 'dispose') {
          disposed = true;
          habits.dispose();
        } else {
          habits.resetLocalState();
        }
        final before = notices;
        store.release.complete();
        await observed;
        expect(notices, before);
        expect(persisted, 0);
        expect(events, isEmpty);
        expect(audit.entries, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(_saved(prefs).single.todayCount(), 0);
      },
    );
  }
}

Habit _habit(String id, {String? unit}) =>
    Habit(id: id, name: id, targetCount: 8, unit: unit);
List<Habit> _saved(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString('habits') ?? '[]') as List)
        .map((raw) => Habit.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool hold = false;
  bool reject = false;
  bool rejectTombstone = false;
  bool holdTombstone = false;
  bool throwError = false;
  int habitWrites = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  final tombstoneStarted = Completer<void>();
  final tombstoneRelease = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.sync_deleted_items') {
      final rejectThis = rejectTombstone;
      rejectTombstone = false;
      if (holdTombstone && !tombstoneStarted.isCompleted) {
        tombstoneStarted.complete();
        await tombstoneRelease.future;
      }
      await super.setValue(type, key, value);
      return !rejectThis;
    }
    if (key != 'flutter.habits') return super.setValue(type, key, value);
    habitWrites++;
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.setValue(type, key, value);
    if (reject) {
      reject = false;
      if (throwError) throw StateError('synthetic habit write rejection');
      return false;
    }
    return true;
  }
}

class _RecordCountingAudit extends TimeAuditProvider {
  int recordCalls = 0;
  @override
  Future<void> recordHabitCheckIn(
    Habit habit, {
    required int cumulativeCount,
    int amount = 1,
    DateTime? at,
  }) {
    recordCalls++;
    return super.recordHabitCheckIn(
      habit,
      cumulativeCount: cumulativeCount,
      amount: amount,
      at: at,
    );
  }
}
