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
      expect(main, contains('var reminderProvidersHydrated = false'));
      expect(main, contains('Future<void> ensureReminderProvidersStartup()'));
      final startupQueueStart = main.indexOf(
        'Future<void> queueStartupReminderResync',
      );
      final startupQueueEnd = main.indexOf(
        '_queueFullReminderResyncCallback',
        startupQueueStart,
      );
      final startupQueue = main.substring(startupQueueStart, startupQueueEnd);
      expect(
        startupQueue,
        contains('await ensureReminderProvidersStartup();'),
        reason: '首次提醒重放必须等待提醒 Provider hydration，避免空状态清理持久化队列。',
      );
      expect(
        startupQueue.indexOf('await ensureReminderProvidersStartup();'),
        lessThan(startupQueue.indexOf('startupReminderResyncQueued = true;')),
        reason: '启动 latch 只能在 reminder Provider hydration 后置位。',
      );
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
            r"delay: const Duration\(seconds: 3\),\s*"
            r"reason: 'initial logged-in startup',",
            multiLine: true,
          ),
        ),
        reason:
            '已登录冷启动的全量提醒重放必须尽早纳入启动单次队列，'
            '避免 1 分钟内的 popup/闹钟提醒在冷启动窗口漏注册。',
      );
      expect(
        main,
        matches(
          RegExp(
            r"queueFullReminderResync\(\s*"
            r"delay: const Duration\(seconds: 8\),\s*"
            r"reason: 'auth changed',",
            multiLine: true,
          ),
        ),
        reason: '登录/切号后的提醒重放要错开首屏滚动，同时仍早于 1 分钟测试窗口。',
      );
      expect(
        main,
        matches(
          RegExp(
            r"startCloudSyncAfterAuth\(\s*"
            r"reason: 'auth changed',\s*"
            r"delay: cloudSyncDelayAfterAuth\(initialStartup: false\),",
            multiLine: true,
          ),
        ),
        reason: '登录后的云同步要按 pending 状态决定延迟，避免无改动时抢主线程。',
      );
      expect(
        main,
        contains('return const Duration(milliseconds: 900);'),
        reason: '已有本地待上传改动时，登录后要尽快提交服务器。',
      );
      expect(
        main,
        isNot(contains('delay: const Duration(seconds: 6)')),
        reason: '登录后 6 秒启动云同步会和页面恢复、滚动抢资源。',
      );
      expect(
        main,
        matches(
          RegExp(
            r"queueStartupReminderResync\(\s*"
            r"delay: const Duration\(seconds: 5\),\s*"
            r"reason: 'post-frame startup',",
            multiLine: true,
          ),
        ),
      );
      expect(main, contains('Future<void> _runStartupIdleQueue('));
      expect(main, contains('initialDelay: const Duration(seconds: 75)'));
      expect(main, contains('gap: const Duration(seconds: 12)'));
      expect(
        main,
        contains("'deferred local storage'"),
        reason: '首帧后的本地延迟加载必须进入统一 idle 队列，避免和通知/同步并发抢首屏。',
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
      expect(
        goalProvider,
        matches(
          RegExp(
            r'Future<void> _syncGoalRemindersNow\(\s*'
            r'bool Function\(\) isCurrent,?\s*\) async',
          ),
        ),
      );
      expect(
        goalProvider,
        contains('if (scheduler == null || !isCurrent()) return;'),
        reason: '失效来源不能启动写入后的提醒同步。',
      );
      expect(
        goalProvider,
        contains('await scheduler.syncGoals(_snapshot())'),
        reason: '提醒同步必须使用独立快照，避免共享已确认模型的可变字段。',
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
      final timezoneHook = goalProvider.substring(
        timezoneHookStart,
        timeEntriesStart,
      );
      expect(timezoneHook, contains('await requester();'));
      expect(
        timezoneHook,
        isNot(contains(RegExp(r'\bsyncGoals\s*\('))),
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

    expect(
      sources['todo'],
      matches(
        RegExp(
          r'Future<TodoReminderSyncResult> _syncTodoRemindersNow\(\{\s*'
          r'String\? reportTodoId,\s*'
          r'bool Function\(\)\? canWrite,?\s*\}\)',
        ),
      ),
    );
    final todoProvider = sources['todo']!;
    final todoSyncStart = todoProvider.indexOf(
      'Future<TodoReminderSyncResult> _syncTodoRemindersNow(',
    );
    final todoSyncEnd = todoProvider.indexOf(
      'void _applyReminderSyncResult(',
      todoSyncStart,
    );
    expect(todoSyncStart, greaterThanOrEqualTo(0));
    expect(todoSyncEnd, greaterThan(todoSyncStart));
    final todoSync = todoProvider.substring(todoSyncStart, todoSyncEnd);
    expect(todoSync, contains('if (_disposed || canWrite?.call() == false)'));
    expect(
      todoSync,
      contains('canWrite?.call() != false'),
      reason: '调用方撤销授权后，迟到的提醒结果不能发布为当前来源的成功。',
    );
    expect(todoSync, contains('if (!isCurrent()) return;'));
    expect(sources['todo'], contains('.syncTodos(List.of(_todos))'));
    expect(
      sources['todo'],
      contains('syncTodosAndGetTodoFailure'),
      reason: '创建路径要能读取按待办 ID 记录的注册失败，避免把“已保存”误报成“提醒已注册”。',
    );
    expect(sources['todo'], contains('lastReminderScheduleIssue'));
    expect(
      sources['habit'],
      matches(
        RegExp(
          r'Future<void> _syncRemindersNow\(\s*'
          r'bool Function\(\) isCurrent,?\s*\) async',
        ),
      ),
    );
    expect(sources['habit'], contains('syncHabits(List.of(_habits))'));
    expect(sources['habit'], contains('await _syncRemindersNow(isCurrent);'));
    for (final entry in const {
      'anniversary': 'syncAnniversaries',
      'countdown': 'syncCountdowns',
    }.entries) {
      final provider = sources[entry.key]!;
      final afterCommitStart = provider.indexOf(
        'Future<String?> _afterCommit(',
      );
      final afterCommitEnd = provider.indexOf(
        'Future<String?> add',
        afterCommitStart,
      );
      expect(afterCommitStart, greaterThanOrEqualTo(0));
      expect(afterCommitEnd, greaterThan(afterCommitStart));
      final afterCommit = provider.substring(afterCommitStart, afterCommitEnd);
      const ownershipGuard =
          'if (!syncReminders || !ownsStorage()) return null;';
      final syncCall = 'await scheduler.${entry.value}(snapshot)';
      expect(afterCommit, contains(ownershipGuard));
      expect(afterCommit, contains(syncCall));
      expect(
        afterCommit.indexOf(ownershipGuard),
        lessThan(afterCommit.indexOf(syncCall)),
        reason: '${entry.key} must retain storage ownership before syncing.',
      );
      expect(
        afterCommit,
        contains('return ownsStorage() ? lastReminderSyncIssue : null;'),
      );
    }
    expect(
      sources['goal'],
      matches(
        RegExp(
          r'Future<void> _syncGoalRemindersNow\(\s*'
          r'bool Function\(\) isCurrent,?\s*\) async',
        ),
      ),
    );
    expect(sources['goal'], contains('syncGoals(_snapshot())'));
    expect(
      sources['goal'],
      contains('await _syncGoalRemindersNow(canFinish);'),
    );
  });
}
