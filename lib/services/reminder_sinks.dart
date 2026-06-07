/// `ReminderScheduler` 依赖的调度出口抽象（Task 14.3）。
///
/// 设计目标：把 `ReminderScheduler` 与具体的 `NotificationService` /
/// `AlarmService` 解耦，让通道路由（`ReminderKind.push` 走 push、
/// `ReminderKind.alarm` 走 alarm、`ReminderKind.email` 走 email outbox）
/// 可被单元/属性测试以 Fake 实例直接验证，
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
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  });

  /// 全屏闹钟的重复调度（每日 / 每周）。
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
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  });

  /// 按 id 取消一条闹钟。
  Future<void> cancel(int id);
}

/// 可选的系统待触发队列查询接口。
///
/// `ReminderScheduler` 会在规则内容未变化时使用它确认系统队列仍然存在。
/// 这样可以覆盖系统通知队列被清空、旧版本曾错误缓存成功等场景；不支持该
/// 接口的通道仍按原有内存幂等逻辑处理。
abstract class ReminderPendingSink {
  Future<List<int>> pendingIds();
}

/// 可选的提醒注册诊断出口。
///
/// 当提醒规则已经启用，但最终无法解析成任何可注册的系统任务时，
/// `ReminderScheduler` 会通过该接口把失败原因暴露给页面和健康提示，
/// 避免用户保存后只看到“已创建”，实际系统队列为空。
abstract class ReminderScheduleIssueSink {
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  });
}

abstract class ReminderScheduleIssueClearSink {
  void clearReminderScheduleIssue();
}

/// 邮件提醒出口。
///
/// 当前客户端只负责把邮件提醒解析成可投递请求；真正投递可以由后端、
/// OpenList/WebDAV 备份任务或后续 SMTP 配置接管。默认 no-op 实现保证
/// 未配置邮件服务时不会误发本地通知或闹钟。
abstract class ReminderEmailSink {
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  });

  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  });

  Future<void> cancel(int id);
}

/// 前台弹出框提醒出口。
///
/// 这条通道只负责应用进程存活时的应用内弹窗；系统级后台/锁屏提醒仍应使用
/// push 或 alarm 通道。
abstract class ReminderPopupSink {
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  });

  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  });

  Future<void> cancel(int id);
}

class NoopReminderPopupSink implements ReminderPopupSink {
  const NoopReminderPopupSink();

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    throw const ReminderPopupFallbackUnavailableException(
      '未配置弹出框提醒出口，popup 提醒未注册',
    );
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    throw const ReminderPopupFallbackUnavailableException(
      '未配置弹出框提醒出口，popup 重复提醒未注册',
    );
  }

  @override
  Future<void> cancel(int id) async {}
}

class ReminderPopupFallbackUnavailableException implements Exception {
  final String message;

  const ReminderPopupFallbackUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Popup 通道缺省实现的系统通知兜底。
///
/// 生产入口通常会注入 `ForegroundReminderPopupSink`，用户选择“弹出框”时只
/// 展示应用内弹窗，避免和系统通知重复。测试或后台对象图若没有显式注入
/// popup sink，则使用本实现直接落到 push 通道，避免 popup 规则被空实现
/// 缓存为“已调度”。
class NotificationFallbackReminderPopupSink implements ReminderPopupSink {
  final ReminderNotificationSink notificationFallback;

  const NotificationFallbackReminderPopupSink(this.notificationFallback);

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) {
    return notificationFallback.scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: _fallbackPayload(payload),
    );
  }

  @override
  Future<void> scheduleRepeating({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) {
    return notificationFallback.scheduleDaily(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: _fallbackPayload(payload),
    );
  }

  @override
  Future<void> cancel(int id) => notificationFallback.cancel(id);

  String? _fallbackPayload(String? payload) {
    if (payload == null || payload.isEmpty) return payload;
    final uri = Uri.tryParse(payload);
    if (uri == null) return payload;
    final query = Map<String, String>.from(uri.queryParameters)
      ..putIfAbsent('fallback', () => 'popup_notification');
    return uri.replace(queryParameters: query).toString();
  }
}

class NoopReminderEmailSink implements ReminderEmailSink {
  const NoopReminderEmailSink();

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {}

  @override
  Future<void> scheduleRepeating({
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
}
