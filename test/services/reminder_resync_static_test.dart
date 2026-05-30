import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'main avoids duplicate reminder resync listeners for self-sync providers',
    () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(main, contains('Future<void> resyncReminders() async'));
      expect(main, contains('var reminderResyncInFlight = false'));
      expect(main, contains('var reminderResyncQueued = false'));
      expect(main, contains('Timer? reminderResyncDebounce'));
      expect(
        main,
        contains('Future<void> queueFullReminderResync({'),
        reason:
            '启动、登录、云同步、时区和权限恢复触发的整轮提醒重放必须先合并，'
            '避免短时间内重复注册同一批系统通知。',
      );
      expect(main, contains('_queueFullReminderResyncCallback'));

      for (final provider in const [
        'todoProvider',
        'habitProvider',
        'anniversaryProvider',
        'countdownProvider',
      ]) {
        final listenerPattern = RegExp(
          r'\b' + provider + r'\.addListener\(([^;\n]+)\);',
          multiLine: true,
        );
        final listeners = listenerPattern
            .allMatches(main)
            .map((match) => match.group(1) ?? '')
            .toList(growable: false);
        for (final listener in listeners) {
          expect(
            listener,
            isNot(
              anyOf(
                contains('resyncReminders'),
                contains('queueFullReminderResync'),
                contains('syncTodos'),
                contains('syncHabits'),
                contains('syncAnniversaries'),
                contains('syncCountdowns'),
              ),
            ),
            reason:
                '$provider already syncs reminders inside its write methods; '
                'a second main.dart listener can replay the same reminder and '
                'show duplicate notifications.',
          );
        }
      }

      expect(
        main,
        isNot(contains('queueGoalReminderSync')),
        reason:
            'Goal reminders must not use a shell ChangeNotifier listener; '
            'it races full resync paths and can register duplicate visible '
            'notifications.',
      );
      expect(
        main,
        isNot(contains('goalProvider.addListener(queueGoalReminderSync)')),
      );
      expect(
        main,
        isNot(contains('_reminderScheduler.resyncAll(')),
        reason:
            'lifecycle resume hooks must reuse queueFullReminderResync instead '
            'of bypassing the shared debounce/serialization path.',
      );
      expect(
        main,
        contains('allowJustMissedOneShotReminders: false'),
        reason:
            '启动、安装更新、权限恢复和时区变化触发的全量重放不能把刚错过的'
            '同分钟一次性提醒顺延到下一分钟，否则更新后会马上弹提醒。',
      );
      final fullResyncTodoCall = main.substring(
        main.indexOf("'syncTodos'"),
        main.indexOf("'syncHabits'", main.indexOf("'syncTodos'")),
      );
      expect(
        fullResyncTodoCall,
        contains('allowJustMissedOneShotReminders: false'),
      );
      for (final reason in const [
        'app timezone changed',
        'ringtone settings changed',
        'cloud sync changed reminders',
        'auth changed',
        'initial logged-in startup',
        'post-frame startup',
        'system timezone changed',
        'notification permission changed',
        'goal timezone changed',
      ]) {
        expect(main, contains("reason: '$reason'"));
      }
      expect(
        main,
        matches(
          RegExp(
            r"queueStartupReminderResync\(\s*"
            r"delay: const Duration\(milliseconds: 1800\),\s*"
            r"reason: 'initial logged-in startup',",
            multiLine: true,
          ),
        ),
        reason:
            '已登录冷启动的全量提醒重放也必须错峰并纳入启动单次队列，'
            '避免首屏期间重复注册本地通知造成卡顿。',
      );
      expect(
        main,
        matches(
          RegExp(
            r"queueStartupReminderResync\(\s*"
            r"delay: const Duration\(milliseconds: 1800\),\s*"
            r"reason: 'post-frame startup',",
            multiLine: true,
          ),
        ),
      );

      final goalProvider = File(
        'lib/providers/goal_provider.dart',
      ).readAsStringSync();
      expect(main, contains('goalProvider.scheduler = reminderScheduler'));
      expect(goalProvider, contains('ReminderScheduler? _scheduler'));
      expect(
        goalProvider,
        contains('set scheduler(ReminderScheduler? scheduler)'),
      );
      expect(goalProvider, contains('Future<void> _syncGoalRemindersNow()'));
      expect(
        goalProvider,
        contains('await scheduler.syncGoals(List.of(_goals))'),
      );
      expect(goalProvider, contains('set reminderResyncRequester'));
      expect(goalProvider, contains('await requester();'));
      final timezoneHookStart = goalProvider.indexOf(
        'Future<void> onTimezoneChanged() async',
      );
      final timeEntriesStart = goalProvider.indexOf(
        'Future<void> _syncTimeEntriesForGoal',
        timezoneHookStart,
      );
      expect(timezoneHookStart, greaterThanOrEqualTo(0));
      expect(timeEntriesStart, greaterThan(timezoneHookStart));
      expect(
        goalProvider.substring(timezoneHookStart, timeEntriesStart),
        isNot(contains('syncGoals(List.of(_goals))')),
        reason:
            'Timezone changes must go through the full resync queue so they '
            'do not overlap startup, permission, or cloud-sync resyncs.',
      );
    },
  );

  test('write-side providers own their reminder sync after data changes', () {
    final sources = {
      'todo': File('lib/providers/todo_provider.dart').readAsStringSync(),
      'habit': File('lib/providers/habit_provider.dart').readAsStringSync(),
      'anniversary': File(
        'lib/providers/anniversary_provider.dart',
      ).readAsStringSync(),
      'countdown': File(
        'lib/providers/countdown_provider.dart',
      ).readAsStringSync(),
      'goal': File('lib/providers/goal_provider.dart').readAsStringSync(),
    };

    expect(sources['todo'], contains('Future<void> _syncTodoRemindersNow()'));
    expect(
      sources['todo'],
      contains('await scheduler.syncTodos(List.of(_todos))'),
    );
    expect(
      sources['habit'],
      contains('Future<void> _syncRemindersNow() async'),
    );
    expect(
      sources['habit'],
      contains('await scheduler.syncHabits(List.of(_habits))'),
    );
    expect(
      sources['anniversary'],
      contains('await scheduler.syncAnniversaries(List.of(_items))'),
    );
    expect(
      sources['countdown'],
      contains('await scheduler.syncCountdowns(List.of(_items))'),
    );
    expect(
      sources['goal'],
      contains('Future<void> _syncGoalRemindersNow() async'),
    );
    expect(
      sources['goal'],
      contains('await scheduler.syncGoals(List.of(_goals))'),
    );
  });
}
