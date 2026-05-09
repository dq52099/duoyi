/// `ReminderScheduler` 依赖的两条调度出口抽象（Task 14.3）。
///
/// 设计目标：把 `ReminderScheduler` 与具体的 `NotificationService` /
/// `AlarmService` 解耦，让通道路由（`ReminderKind.push` 走 push、
/// `ReminderKind.alarm` 走 alarm）可被单元/属性测试以 Fake 实例直接验证，
/// 而无需初始化 flutter_local_notifications 等平台插件。
///
/// 生产代码仍由 `NotificationService implements ReminderNotificationSink`、
/// `AlarmService implements ReminderAlarmSink` 提供真实实现；`ReminderScheduler`
/// 只依赖这两个接口。
library;

/// Push 通道出口（对应 `duoyi_general` / `Importance.high`）。
///
/// 仅罗列 `ReminderScheduler` 真实用到的方法；其他 `NotificationService` 的
/// 语义 API（番茄钟完成、测试通知、历史面板）不属于本接口职责。
abstract class ReminderNotificationSink {
  /// 一次性 push（例如待办到期、目标派发的 push 形态）。
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  });

  /// 每日固定时间 push（主要服务于 `syncHabits`）。
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  });

  /// 通用 cancel（按 id）。
  Future<void> cancel(int id);

  /// 语义化：取消一条待办提醒（内部按稳定 hash 映射到 int id）。
  Future<void> cancelTodoReminder(String todoId);

  /// 语义化：取消一条习惯提醒。
  Future<void> cancelHabitReminder(String habitId);

  /// 语义化：取消一条纪念日提醒。
  Future<void> cancelAnniversary(String annId);

  /// 语义化：每日习惯提醒（push）。
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  });

  /// 语义化：纪念日到达前 N 天提醒（push）。
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  });
}

/// Alarm 通道出口（对应 `duoyi_alarm` / `Importance.max` / 全屏 intent）。
///
/// 仅罗列 `ReminderScheduler` 真实用到的方法；权限申请、pending 查询等
/// 运维性 API 不在路由职责内，保留在 `AlarmService` 自身的公开 API 上。
abstract class ReminderAlarmSink {
  /// 全屏闹钟调度（需要 Android 精准闹钟权限时由实现负责回退/抛错）。
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
  });

  /// 按 id 取消一条闹钟。
  Future<void> cancel(int id);
}
