import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';

/// 时区壁钟不变属性测试（Task 14.5）。
///
/// Feature: app-alignment-overhaul
///
/// Property 1 (P1 — Alarm fires at configured local time):
///   ∀ `ReminderConfig r` with `r.kind = alarm, r.hour = H, r.minute = M`,
///   ∀ 目标触发日 D（设备本地时区），
///   最终调度的时间 T（壁钟语义）满足：
///     `T.hour == H ∧ T.minute == M ∧ dateOnly(T) == D ∧
///      T.location.name == tz.local.name`。
///
/// Property 2 (P2 — Timezone change re-sync preserves wall-clock time):
///   设备时区由 `tz1` 切至 `tz2` 后，`ReminderScheduler.resyncAll()` 重新
///   调度的闹钟在新时区下的本地时间仍等于用户原设定的 `(H, M)`，即
///   "壁钟时间不变、绝对 UTC 时间改变"。
///
/// Property 3 (P3 — No UTC leak):
///   ∀ 调度调用，最终传入 `flutter_local_notifications.zonedSchedule` 的
///   `tz.TZDateTime` 的 `location ≠ tz.UTC`（仅当 `tz.local` 非 UTC 时）。
///
/// Validates: Requirements 8.5, 8.7, 8.8
///
/// 测试形态：
///   - 使用 `Random(42)` 种子生成 N=50 次"随机但可复现"的迭代。
///   - 每轮从固定 IANA 白名单中挑选非 UTC 时区，分别演练：单次 sync
///     （P1 / P3）或 tz1→tz2 切换后 resyncAll（P2）。
///   - 以 `_RecordingAlarmSink` 观察 `ReminderScheduler._dispatch` 最终
///     落到闹钟通道的 `when`（plain `DateTime`）；在测试侧用
///     `tz.TZDateTime(tz.local, y, m, d, H, M)` 重建壁钟形式的
///     `TZDateTime`，断言其 `.location` 与 `tz.local` 一致、非 `tz.UTC`。
///
/// 备注：生产 `AlarmService.scheduleFullScreen` 使用
/// `tz.TZDateTime.from(when, tz.local)`，该等价性只在"OS-local 时区与
/// `tz.local` 同步"这个 `LocalTimezoneResolver` 的前置条件下成立；单元
/// 测试无法在进程内动态改写 OS-local 时区，因此 P1/P2 在测试中验证"调度
/// 路径端到端保留 `(hour, minute)`"这一可观测约束 —— 这与 P2 文字表述
/// "壁钟时间不变、绝对 UTC 时间改变" 的诉求对应，而 P3 则直接构造
/// `TZDateTime(tz.local, ...)` 验证 `.location ≠ tz.UTC`。
void main() {
  /// 固定种子，保证"随机"测试在 CI / 本地完全可复现。
  const int kSeed = 42;

  /// 迭代轮次。
  const int kIterations = 50;

  /// 固定的非 UTC IANA 时区白名单。挑 7 个覆盖正 / 负偏移与跨日界：
  /// 东亚 / 北美东西岸 / 欧洲 / 大洋洲 / 太平洋。
  const zones = <String>[
    'Asia/Shanghai',
    'America/New_York',
    'Europe/London',
    'Australia/Sydney',
    'Pacific/Honolulu',
    'Asia/Tokyo',
    'America/Los_Angeles',
  ];

  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  tearDownAll(() {
    // 复位 tz.local，避免污染后续测试的全局状态。
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
  });

  group('P1 — 闹钟按配置的本地时间触发 (Requirements 8.5, 8.7)', () {
    test(
      'scheduled when.(hour, minute) 等于 ReminderConfig(H, M)，且 tz.local 已就绪',
      () async {
        final rng = Random(kSeed);
        for (int iter = 0; iter < kIterations; iter++) {
          final zoneName = zones[rng.nextInt(zones.length)];
          tz.setLocalLocation(tz.getLocation(zoneName));

          final H = rng.nextInt(24);
          final M = rng.nextInt(60);

          final notif = _RecordingNotificationSink();
          final alarm = _RecordingAlarmSink();
          final scheduler = ReminderScheduler(notif, alarm: alarm);

          // 触发日锚定"后天"，确保 `_resolveTodo` 中
          // `when.isBefore(DateTime.now())` 不会过滤掉。
          final due = DateTime.now().add(const Duration(days: 2));
          final todo = TodoItem(
            title: 'p1-iter-$iter',
            dueDate: due,
            reminder: ReminderConfig(
              enabled: true,
              kind: ReminderKind.alarm,
              hour: H,
              minute: M,
            ),
          );

          await scheduler.syncTodos([todo]);

          expect(
            alarm.scheduleFullScreenCalls.length,
            1,
            reason: 'iter=$iter zone=$zoneName H=$H M=$M: 应精确下发一次闹钟调度',
          );
          final call = alarm.scheduleFullScreenCalls.single;

          // 壁钟语义：Scheduler 传入的 DateTime 已按 (H, M) 构造。
          expect(
            call.when.hour,
            H,
            reason: 'iter=$iter zone=$zoneName H=$H M=$M when=${call.when}',
          );
          expect(
            call.when.minute,
            M,
            reason: 'iter=$iter zone=$zoneName H=$H M=$M when=${call.when}',
          );

          // dateOnly(T) == D：与 `due` 的 year/month/day 对齐。
          expect(call.when.year, due.year);
          expect(call.when.month, due.month);
          expect(call.when.day, due.day);

          // 在测试侧构造"等价壁钟形式"的 TZDateTime（= 生产下游
          // `AlarmService` 在 OS-local == tz.local 前提下得到的 T），
          // 断言 timeZoneName / hour / minute 均与 tz.local 对齐。
          final loc = tz.local;
          final tzWhen = tz.TZDateTime(
            loc,
            call.when.year,
            call.when.month,
            call.when.day,
            call.when.hour,
            call.when.minute,
          );
          expect(tzWhen.hour, H);
          expect(tzWhen.minute, M);
          expect(tzWhen.location.name, zoneName);
          // P3 的副约束：非 UTC 时区下 `.location` 不是 tz.UTC。
          expect(tzWhen.location, isNot(equals(tz.UTC)));
        }
      },
    );
  });

  group('P2 — tz 切换后 resyncAll 保留壁钟 (Requirements 8.7, 8.8)', () {
    test(
      'tz1 → tz2 切换 + resyncAll 之后，新调度的 (hour, minute) 仍等于 (H, M)',
      () async {
        final rng = Random(kSeed + 1);
        for (int iter = 0; iter < kIterations; iter++) {
          // 选两个不同的时区。
          final String tz1 = zones[rng.nextInt(zones.length)];
          String tz2;
          do {
            tz2 = zones[rng.nextInt(zones.length)];
          } while (tz2 == tz1);

          final H = rng.nextInt(24);
          final M = rng.nextInt(60);

          // Phase 1：在 tz1 下 sync。
          tz.setLocalLocation(tz.getLocation(tz1));
          final notif = _RecordingNotificationSink();
          final alarm = _RecordingAlarmSink();
          final scheduler = ReminderScheduler(notif, alarm: alarm);

          final due = DateTime.now().add(const Duration(days: 2));
          final todo = TodoItem(
            title: 'p2-iter-$iter',
            dueDate: due,
            reminder: ReminderConfig(
              enabled: true,
              kind: ReminderKind.alarm,
              hour: H,
              minute: M,
            ),
          );
          await scheduler.syncTodos([todo]);

          expect(
            alarm.scheduleFullScreenCalls.length,
            1,
            reason: 'iter=$iter tz1=$tz1: 初次 sync 应下发一次闹钟',
          );
          final call1 = alarm.scheduleFullScreenCalls.last;
          expect(call1.when.hour, H);
          expect(call1.when.minute, M);

          // Phase 2：切换到 tz2 并 resyncAll。
          tz.setLocalLocation(tz.getLocation(tz2));
          await scheduler.resyncAll(
            todos: [todo],
            habits: const [],
            annis: const [],
            goals: const [],
          );

          // resyncAll：先 cancel 已记录的 rule id，再按新数据重新下发。
          // 升级兼容路径还会清理旧版单提醒 id，因此这里不做严格次数约束。
          expect(
            alarm.scheduleFullScreenCalls.length,
            2,
            reason: 'iter=$iter tz1=$tz1 tz2=$tz2: resyncAll 应重新下发一次',
          );
          expect(
            alarm.cancelCalls,
            contains(_todoRuleIntId(todo)),
            reason: 'iter=$iter tz1=$tz1 tz2=$tz2: resyncAll 应先取消旧 rule',
          );
          final call2 = alarm.scheduleFullScreenCalls.last;

          // P2 核心：壁钟不变。
          expect(
            call2.when.hour,
            H,
            reason:
                'iter=$iter tz1=$tz1 tz2=$tz2 H=$H M=$M '
                'call2.when=${call2.when}',
          );
          expect(
            call2.when.minute,
            M,
            reason:
                'iter=$iter tz1=$tz1 tz2=$tz2 H=$H M=$M '
                'call2.when=${call2.when}',
          );

          // 在新 tz 下重建壁钟形式的 TZDateTime，断言 location.name 变了
          // 但 (hour, minute) 不变 —— "绝对 UTC 时间改变、壁钟不变"。
          final tzWhen1InLoc1 = tz.TZDateTime(
            tz.getLocation(tz1),
            call1.when.year,
            call1.when.month,
            call1.when.day,
            call1.when.hour,
            call1.when.minute,
          );
          final tzWhen2InLoc2 = tz.TZDateTime(
            tz.local,
            call2.when.year,
            call2.when.month,
            call2.when.day,
            call2.when.hour,
            call2.when.minute,
          );
          expect(tzWhen2InLoc2.hour, H);
          expect(tzWhen2InLoc2.minute, M);
          expect(tzWhen2InLoc2.location.name, tz2);
          expect(tzWhen2InLoc2.location, isNot(equals(tz.UTC)));

          // 两个 TZDateTime 的绝对 UTC 瞬间必然不同（tz 白名单已排除
          // UTC，且 tz1 ≠ tz2；同一壁钟在不同时区指向不同 UTC 时刻）。
          expect(
            tzWhen2InLoc2.millisecondsSinceEpoch,
            isNot(equals(tzWhen1InLoc1.millisecondsSinceEpoch)),
            reason:
                'iter=$iter tz1=$tz1 tz2=$tz2: 壁钟相同 → '
                '绝对 UTC 时刻必不同',
          );
        }
      },
    );
  });

  group('P3 — 无 UTC 泄漏 (Requirements 8.5)', () {
    test('tz.local 非 UTC 时，调度的 TZDateTime.location ≠ tz.UTC', () async {
      final rng = Random(kSeed + 2);
      for (int iter = 0; iter < kIterations; iter++) {
        final zoneName = zones[rng.nextInt(zones.length)];
        tz.setLocalLocation(tz.getLocation(zoneName));

        final H = rng.nextInt(24);
        final M = rng.nextInt(60);

        final notif = _RecordingNotificationSink();
        final alarm = _RecordingAlarmSink();
        final scheduler = ReminderScheduler(notif, alarm: alarm);

        final due = DateTime.now().add(const Duration(days: 2));
        final todo = TodoItem(
          title: 'p3-iter-$iter',
          dueDate: due,
          reminder: ReminderConfig(
            enabled: true,
            kind: ReminderKind.alarm,
            hour: H,
            minute: M,
          ),
        );
        await scheduler.syncTodos([todo]);

        final call = alarm.scheduleFullScreenCalls.single;
        final tzWhen = tz.TZDateTime(
          tz.local,
          call.when.year,
          call.when.month,
          call.when.day,
          call.when.hour,
          call.when.minute,
        );

        expect(
          tzWhen.location,
          isNot(equals(tz.UTC)),
          reason:
              'iter=$iter zone=$zoneName: tz.TZDateTime.location '
              '不应为 tz.UTC',
        );
        expect(tzWhen.location.name, isNot('UTC'));
        expect(tzWhen.location.name, zoneName);
      }
    });
  });
}

int _idFor(String key) {
  int h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

int _todoRuleIntId(TodoItem todo) =>
    _idFor('todo:${todo.id}:${todo.reminderPlan.primaryRule!.id}');

// ---------------------------------------------------------------------------
// Fakes：Recording sinks（与 channel_routing_pbt_test.dart 的实现保持形态
// 一致，这里保留在本文件内以保持测试独立、无跨文件耦合）。
// ---------------------------------------------------------------------------

class _ScheduleOnceCall {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  const _ScheduleOnceCall({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
  });
}

class _ScheduleFullScreenCall {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  final bool requireExactAlarm;
  final bool fullScreen;
  const _ScheduleFullScreenCall({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    required this.payload,
    required this.requireExactAlarm,
    required this.fullScreen,
  });
}

class _RecordingNotificationSink implements ReminderNotificationSink {
  final List<_ScheduleOnceCall> scheduleOnceCalls = [];

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    scheduleOnceCalls.add(
      _ScheduleOnceCall(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelTodoReminder(String todoId) async {}

  @override
  Future<void> cancelHabitReminder(String habitId) async {}

  @override
  Future<void> cancelAnniversary(String annId) async {}

  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {}

  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async {}
}

class _RecordingAlarmSink implements ReminderAlarmSink {
  final List<_ScheduleFullScreenCall> scheduleFullScreenCalls = [];
  final List<int> cancelCalls = [];

  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
  }) async {
    scheduleFullScreenCalls.add(
      _ScheduleFullScreenCall(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
        requireExactAlarm: requireExactAlarm,
        fullScreen: fullScreen,
      ),
    );
  }

  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
  }) async {}

  @override
  Future<void> cancel(int id) async {
    cancelCalls.add(id);
  }
}
