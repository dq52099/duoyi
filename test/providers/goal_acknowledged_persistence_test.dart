import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/recurrence.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Cold Goal creation retains previously stored goals', () async {
    final old = GoalItem(id: 'stored', title: 'Stored goal');
    final store = _GoalsStore(
      values: {
        'flutter.duoyi_goals': [jsonEncode(old.toJson())],
      },
    );
    SharedPreferencesStorePlatform.instance = store;
    final provider = GoalProvider();
    addTearDown(provider.dispose);
    await provider.add(GoalItem(id: 'new', title: 'New goal'));
    expect(
      provider.goals.map((goal) => goal.id),
      unorderedEquals(['stored', 'new']),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('duoyi_goals'), hasLength(2));
  });

  test(
    'Rejected Goal creation does not publish a model or success effects',
    () async {
      final store = _GoalsStore()..rejectOnce = true;
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      var persisted = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      final events = <DomainEvent>[];
      final subscription = DomainEventBus.instance.events.listen(events.add);
      addTearDown(subscription.cancel);

      await expectLater(
        provider.add(GoalItem(id: 'rejected', title: 'Rejected goal')),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(provider.goals, isEmpty);
      expect(persisted, 0);
      expect(
        events.where((event) => event.type == DomainEventType.goalCreated),
        isEmpty,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('duoyi_goals'), isNull);
      await provider.add(GoalItem(id: 'retry', title: 'Retry goal'));
      expect(provider.goals.single.id, 'retry');
    },
  );

  test(
    'Held Goal creation stays unpublished until platform acknowledgement',
    () async {
      final store = _GoalsStore()..holdFirst = true;
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      var persisted = 0;
      var notifications = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      provider.addListener(() => notifications++);
      final events = <DomainEvent>[];
      final subscription = DomainEventBus.instance.events.listen(events.add);
      final pending = provider.add(GoalItem(id: 'held', title: 'Held goal'));
      addTearDown(() async {
        if (!store.release.isCompleted) store.release.complete();
        await pending;
        await subscription.cancel();
        provider.dispose();
      });
      await store.started.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(provider.goals, isEmpty);
      expect(persisted, 0);
      expect(notifications, 0);
      expect(events, isEmpty);
      store.release.complete();
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(provider.goals.single.id, 'held');
      expect(persisted, 1);
      expect(events.single.type, DomainEventType.goalCreated);
    },
  );

  test('Overlapping Goal creation serializes complete snapshots', () async {
    final store = _GoalsStore()..holdFirst = true;
    SharedPreferencesStorePlatform.instance = store;
    final provider = GoalProvider();
    final first = provider.add(GoalItem(id: 'first', title: 'First goal'));
    Future<void>? second;
    addTearDown(() async {
      if (!store.release.isCompleted) store.release.complete();
      await first;
      if (second != null) await second;
      provider.dispose();
    });
    await store.started.future.timeout(const Duration(seconds: 5));
    final submittedSecond = provider.add(
      GoalItem(id: 'second', title: 'Second goal'),
    );
    second = submittedSecond;
    await Future<void>.delayed(Duration.zero);
    expect(store.goalWrites, hasLength(1));
    store.release.complete();
    await Future.wait([first, submittedSecond]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('duoyi_goals'), hasLength(2));
    expect(store.goalWrites.map((snapshot) => snapshot.length), [1, 2]);
    expect(
      provider.goals.map((goal) => goal.id),
      unorderedEquals(['first', 'second']),
    );
  });

  test(
    'Account cleanup waits for issued Goal storage before clearing it',
    () async {
      final store = _GoalsStore()..holdFirst = true;
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      var persisted = 0;
      provider.onLocalMutationPersisted = () => persisted++;
      final write = provider.add(
        GoalItem(id: 'old', title: 'Old account goal'),
      );
      final settledWrite = write.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      Future<void>? cleanup;
      addTearDown(() async {
        if (!store.release.isCompleted) store.release.complete();
        await settledWrite;
        if (cleanup != null) await cleanup;
        provider.dispose();
      });
      await store.started.future.timeout(const Duration(seconds: 5));
      provider.resetLocalState();
      var cleaned = false;
      cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((_) {
        cleaned = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, isFalse);
      store.release.complete();
      await settledWrite;
      await cleanup;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.containsKey('duoyi_goals'), isFalse);
      expect(provider.goals, isEmpty);
      expect(persisted, 0);
    },
  );

  test(
    'Caller and getter milestones cannot mutate acknowledged state',
    () async {
      final store = _GoalsStore();
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      final original = GoalItem(
        id: 'isolated',
        title: 'Original',
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          byWeekdays: [0, 2],
        ),
        milestones: [GoalMilestone(id: 'milestone', title: 'Original step')],
      );
      await provider.add(original);
      original.title = 'Caller mutation';
      original.milestones.single.isCompleted = true;
      original.recurrence.byWeekdays!.add(4);
      final exposed = provider.goals.single;
      exposed.title = 'Getter mutation';
      exposed.milestones.single.title = 'Getter step mutation';
      exposed.recurrence.byWeekdays!.clear();
      expect(provider.goals.single.title, 'Original');
      expect(provider.goals.single.milestones.single.title, 'Original step');
      expect(provider.goals.single.milestones.single.isCompleted, isFalse);
      expect(provider.goals.single.recurrence.byWeekdays, [0, 2]);
    },
  );

  test(
    'Rejected milestone update has no achievement or time effects',
    () async {
      final store = _GoalsStore();
      SharedPreferencesStorePlatform.instance = store;
      final audit = _GoalAudit();
      final provider = GoalProvider()..timeAudit = audit;
      addTearDown(provider.dispose);
      addTearDown(audit.dispose);
      await provider.add(
        GoalItem(
          id: 'milestones',
          title: 'Milestone goal',
          milestones: [GoalMilestone(id: 'step', title: 'Step')],
        ),
      );
      final events = <DomainEvent>[];
      final subscription = DomainEventBus.instance.events.listen(events.add);
      addTearDown(subscription.cancel);
      store.rejectOnce = true;
      await expectLater(
        provider.toggleMilestone('milestones', 'step'),
        throwsStateError,
      );
      expect(provider.goals.single.status, GoalStatus.active);
      expect(provider.goals.single.milestones.single.isCompleted, isFalse);
      expect(events, isEmpty);
      expect(audit.operations, isEmpty);
      await provider.toggleMilestone('milestones', 'step');
      expect(provider.goals.single.status, GoalStatus.achieved);
      expect(events.map((event) => event.type), [
        DomainEventType.goalMilestoneCompleted,
        DomainEventType.goalAchieved,
      ]);
      expect(audit.operations, ['record:milestones:step']);
      await provider.setStatus('milestones', GoalStatus.achieved);
      expect(
        events.where((event) => event.type == DomainEventType.goalAchieved),
        hasLength(1),
      );
    },
  );

  test(
    'Goal deletion rolls back when its workspace deletion record fails',
    () async {
      final store = _GoalsStore();
      SharedPreferencesStorePlatform.instance = store;
      final audit = _GoalAudit();
      final provider = GoalProvider()..timeAudit = audit;
      addTearDown(provider.dispose);
      addTearDown(audit.dispose);
      await provider.add(
        GoalItem(
          id: 'shared-goal',
          title: 'Shared',
          workspaceId: 'workspace-a',
        ),
      );
      store.rejectKeyOnce =
          'flutter.${CloudSyncProvider.workspaceDeletedItemsStorageKey}';
      await expectLater(provider.delete('shared-goal'), throwsStateError);
      expect(provider.goals.single.id, 'shared-goal');
      expect(audit.operations, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getStringList('duoyi_goals'), hasLength(1));
      expect(
        prefs.containsKey(CloudSyncProvider.workspaceDeletedItemsStorageKey),
        isFalse,
      );
      await provider.delete('shared-goal');
      expect(provider.goals, isEmpty);
      expect(audit.operations, ['delete:shared-goal']);
      final deleted =
          jsonDecode(
                prefs.getString(
                  CloudSyncProvider.workspaceDeletedItemsStorageKey,
                )!,
              )
              as Map;
      expect((deleted['workspace-a'] as Map)['goals'], contains('shared-goal'));
      expect(
        prefs.containsKey(CloudSyncProvider.deletedItemsStorageKey),
        isFalse,
      );
    },
  );

  test(
    'Goal permission revocation while a write is held rolls it back',
    () async {
      final store = _GoalsStore()..holdFirst = true;
      SharedPreferencesStorePlatform.instance = store;
      var editable = true;
      final provider = GoalProvider()..canEditWorkspace = (_) => editable;
      final pending = provider.add(
        GoalItem(id: 'revoked', title: 'Revoked', workspaceId: 'workspace-a'),
      );
      final verdict = expectLater(pending, throwsA(isA<Exception>()));
      addTearDown(() async {
        if (!store.release.isCompleted) store.release.complete();
        await verdict;
        provider.dispose();
      });
      await store.started.future.timeout(const Duration(seconds: 5));
      editable = false;
      store.release.complete();
      await verdict;
      expect(provider.goals, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.containsKey('duoyi_goals'), isFalse);
    },
  );

  test('Unknown milestone cannot toggle an unrelated step', () async {
    final provider = GoalProvider();
    addTearDown(provider.dispose);
    await provider.add(
      GoalItem(
        id: 'goal',
        title: 'Goal',
        milestones: [GoalMilestone(id: 'actual', title: 'Actual')],
      ),
    );
    await expectLater(
      provider.toggleMilestone('goal', 'missing'),
      throwsStateError,
    );
    expect(provider.goals.single.milestones.single.isCompleted, isFalse);
  });

  test(
    'Committed Goal remains successful after caller authority changes',
    () async {
      final store = _GoalsStore();
      SharedPreferencesStorePlatform.instance = store;
      var writable = true;
      final provider = GoalProvider();
      addTearDown(provider.dispose);
      provider.onLocalMutationPersisted = () => writable = false;
      final events = <DomainEvent>[];
      final subscription = DomainEventBus.instance.events.listen(events.add);
      addTearDown(subscription.cancel);
      await provider.add(
        GoalItem(id: 'acknowledged', title: 'Acknowledged'),
        canWrite: () => writable,
      );
      expect(provider.goals.single.id, 'acknowledged');
      expect(events, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('duoyi_goals'), hasLength(1));
    },
  );

  test('Permission revoked by ACK callback stops creation effects', () async {
    var editable = true;
    final provider = GoalProvider()..canEditWorkspace = (_) => editable;
    addTearDown(provider.dispose);
    provider.onLocalMutationPersisted = () => editable = false;
    final events = <DomainEvent>[];
    final subscription = DomainEventBus.instance.events.listen(events.add);
    addTearDown(subscription.cancel);
    await provider.add(
      GoalItem(id: 'committed', title: 'Committed', workspaceId: 'workspace-a'),
    );
    expect(provider.goals.single.id, 'committed');
    expect(events, isEmpty);
  });

  test('Deletion ACK callback can invalidate tracked writes safely', () async {
    final provider = GoalProvider();
    addTearDown(provider.dispose);
    await provider.add(
      GoalItem(
        id: 'deleted-before-invalidation',
        title: 'Delete me',
        workspaceId: 'workspace-a',
      ),
    );
    var acknowledged = 0;
    provider.onLocalMutationPersisted = () {
      acknowledged++;
      AccountPreferenceWrites.invalidate();
    };
    await provider.delete('deleted-before-invalidation');
    expect(acknowledged, 1);
    expect(provider.goals, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getStringList('duoyi_goals'), isEmpty);
    final tombstones =
        jsonDecode(
              prefs.getString(
                CloudSyncProvider.workspaceDeletedItemsStorageKey,
              )!,
            )
            as Map;
    expect(
      (tombstones['workspace-a'] as Map)['goals'],
      contains('deleted-before-invalidation'),
    );
  });

  for (final deleting in [false, true]) {
    test(
      'Authority loss in the commit continuation preserves ${deleting ? 'deletion' : 'creation'} ACK',
      () async {
        final provider = GoalProvider();
        addTearDown(provider.dispose);
        final goal = GoalItem(
          id: 'commit-window',
          title: 'Committed goal',
          workspaceId: 'workspace-a',
        );
        if (deleting) await provider.add(goal);
        var commitChecked = false;
        var acknowledged = 0;
        provider.onLocalMutationPersisted = () => acknowledged++;
        final events = <DomainEvent>[];
        final subscription = DomainEventBus.instance.events.listen(events.add);
        addTearDown(subscription.cancel);
        bool canWrite() {
          // The authority lease expires after its successful commit check.
          // Later checks must suppress follow-up effects without rejecting
          // the snapshot that was already committed.
          if (commitChecked) return false;
          if (StackTrace.current.toString().contains(
            'AccountPreferenceTransaction.commit',
          )) {
            commitChecked = true;
          }
          return true;
        }

        if (deleting) {
          await provider.delete(goal.id, canWrite: canWrite);
        } else {
          await provider.add(goal, canWrite: canWrite);
        }
        expect(commitChecked, isTrue);
        expect(acknowledged, 1);
        expect(events, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final stored = prefs.getStringList('duoyi_goals')!;
        if (deleting) {
          expect(provider.goals, isEmpty);
          expect(stored, isEmpty);
          final tombstones =
              jsonDecode(
                    prefs.getString(
                      CloudSyncProvider.workspaceDeletedItemsStorageKey,
                    )!,
                  )
                  as Map;
          expect(
            (tombstones['workspace-a'] as Map)['goals'],
            contains(goal.id),
          );
        } else {
          expect(provider.goals.single.id, goal.id);
          expect(jsonDecode(stored.single)['id'], goal.id);
        }
      },
    );
  }

  test(
    'Caller weekday edits during held ACK cannot change the snapshot',
    () async {
      final store = _GoalsStore()..holdFirst = true;
      SharedPreferencesStorePlatform.instance = store;
      final provider = GoalProvider();
      final incoming = GoalItem(
        id: 'held-weekdays',
        title: 'Weekly',
        recurrence: RecurrenceRule(
          frequency: RecurrenceFrequency.weekly,
          byWeekdays: [1, 3],
        ),
      );
      final pending = provider.add(incoming);
      addTearDown(() async {
        if (!store.release.isCompleted) store.release.complete();
        await pending;
        provider.dispose();
      });
      await store.started.future.timeout(const Duration(seconds: 5));
      incoming.recurrence.byWeekdays!.clear();
      store.release.complete();
      await pending;
      expect(provider.goals.single.recurrence.byWeekdays, [1, 3]);
      final prefs = await SharedPreferences.getInstance();
      final stored = GoalItem.fromJson(
        jsonDecode(prefs.getStringList('duoyi_goals')!.single),
      );
      expect(stored.recurrence.byWeekdays, [1, 3]);
    },
  );

  test('Synchronous event reset stops subsequent Goal effects', () async {
    final audit = _GoalAudit();
    final provider = GoalProvider()..timeAudit = audit;
    addTearDown(provider.dispose);
    addTearDown(audit.dispose);
    await provider.add(
      GoalItem(
        id: 'reset',
        title: 'Reset',
        milestones: [GoalMilestone(id: 'step', title: 'Step')],
      ),
    );
    final events = <DomainEvent>[];
    final subscription = DomainEventBus.instance.events.listen((event) {
      events.add(event);
      if (event.type == DomainEventType.goalMilestoneCompleted) {
        provider.resetLocalState();
      }
    });
    addTearDown(subscription.cancel);
    await provider.toggleMilestone('reset', 'step');
    expect(events.map((event) => event.type), [
      DomainEventType.goalMilestoneCompleted,
    ]);
    expect(audit.operations, isEmpty);
    expect(provider.goals, isEmpty);
  });
}

class _GoalsStore extends InMemorySharedPreferencesStore {
  _GoalsStore({Map<String, Object> values = const {}}) : super.withData(values);
  bool rejectOnce = false;
  String? rejectKeyOnce;
  bool holdFirst = false;
  final started = Completer<void>();
  final release = Completer<void>();
  final goalWrites = <List<String>>[];

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (rejectKeyOnce == key) {
      rejectKeyOnce = null;
      await super.setValue(type, key, value);
      return false;
    }
    if (key == 'flutter.duoyi_goals') {
      goalWrites.add(List<String>.from(value as List));
      if (holdFirst && !started.isCompleted) {
        started.complete();
        await release.future;
      }
      await super.setValue(type, key, value);
      if (rejectOnce) {
        rejectOnce = false;
        return false;
      }
      return true;
    }
    return super.setValue(type, key, value);
  }
}

class _GoalAudit extends TimeAuditProvider {
  final operations = <String>[];

  @override
  Future<void> recordGoalMilestone(
    GoalItem goal,
    GoalMilestone milestone, {
    DateTime? completedAt,
  }) async {
    operations.add('record:${goal.id}:${milestone.id}');
  }

  @override
  Future<void> removeGoalMilestone(
    GoalItem goal,
    GoalMilestone milestone,
  ) async {
    operations.add('remove:${goal.id}:${milestone.id}');
  }

  @override
  Future<void> deleteGoalEntries(String goalId) async {
    operations.add('delete:$goalId');
  }
}
