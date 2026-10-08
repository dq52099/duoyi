import '../core/i18n.dart';

enum WidgetActionNotice {
  focusRunning,
  focusStarted,
  todoMissing,
  todoAlreadyCompleted,
  habitMissing,
  habitUnsupported,
  habitNotScheduled,
  habitAlreadyCompleted,
  unknownEntry,
  quickTodoUnavailable,
  quickTodoFailed,
  hydrationFailed,
  staleContent,
  validationFailed,
  refreshSucceeded,
  refreshFailed,
  habitCheckedIn,
  habitSaving,
  habitCheckInFailed,
  todoCompleted,
  todoSaving,
  todoCompletionFailed,
  reminderConfigurationInvalid,
  reminderNotRegistered,
  alarmPermissionDenied,
  reminderIssue,
  savedReminderIssue,
  todoSaved,
}

enum WidgetActionSyncState {
  unknown,
  disabled,
  accountTransition,
  signedOut,
  serverDisabled,
  autoSyncOff,
  retryPending,
  failed,
  backgroundUpload,
}

enum WidgetActionReminderHint { none, settings, details }

/// A frozen read of sync facts; locale selection does not reread a provider.
final class WidgetActionSyncStatus {
  const WidgetActionSyncStatus(this.state, {this.reason = ''});

  factory WidgetActionSyncStatus.fromFacts({
    required bool enabled,
    required bool accountTransition,
    required bool authenticated,
    required bool serverDisabled,
    required bool autoSync,
    required bool retryPending,
    required bool pendingChanges,
    String? retryReason,
    String? lastError,
  }) {
    final state = !enabled
        ? WidgetActionSyncState.disabled
        : accountTransition
        ? WidgetActionSyncState.accountTransition
        : !authenticated
        ? WidgetActionSyncState.signedOut
        : serverDisabled
        ? WidgetActionSyncState.serverDisabled
        : !autoSync
        ? WidgetActionSyncState.autoSyncOff
        : retryPending && (retryReason?.trim().isNotEmpty ?? false)
        ? WidgetActionSyncState.retryPending
        : pendingChanges && (lastError?.trim().isNotEmpty ?? false)
        ? WidgetActionSyncState.failed
        : WidgetActionSyncState.backgroundUpload;
    final reason = switch (state) {
      WidgetActionSyncState.retryPending => retryReason ?? '',
      WidgetActionSyncState.failed => lastError ?? '',
      _ => '',
    };
    return WidgetActionSyncStatus(state, reason: reason);
  }

  final WidgetActionSyncState state;
  final String reason;
}

/// Keeps copy separate from identity guards and the locale at dispatch time.
/// User names and untyped service reasons are preserved as literal parameters.
final class WidgetActionMessage {
  const WidgetActionMessage(
    this.notice, {
    this.subject = '',
    this.detail = '',
    this.issueTitle,
    this.syncState = WidgetActionSyncState.unknown,
    this.syncReason = '',
    this.reminderHint = WidgetActionReminderHint.none,
  });

  final WidgetActionNotice notice;
  final String subject;
  final String detail;
  final String? issueTitle;
  final WidgetActionSyncState syncState;
  final String syncReason;
  final WidgetActionReminderHint reminderHint;

  /// Call after the origin/lifetime checks, immediately before displaying text.
  String render({AppLocale? locale}) {
    final isZh = (locale ?? I18n.current) == AppLocale.zh;
    String pick(String zh, String en) => isZh ? zh : en;
    final issueLabel =
        issueTitle ?? pick('待办提醒注册失败', 'Task reminder not registered');
    return switch (notice) {
      WidgetActionNotice.focusRunning => pick(
        '专注计时正在进行',
        'A focus timer is already running',
      ),
      WidgetActionNotice.focusStarted => pick('已开始专注', 'Focus started'),
      WidgetActionNotice.todoMissing => pick(
        '这个任务不存在或已被删除',
        'This task is unavailable or has been deleted',
      ),
      WidgetActionNotice.todoAlreadyCompleted => pick(
        '“$subject”已经完成',
        '“$subject” is already complete',
      ),
      WidgetActionNotice.habitMissing => pick(
        '这个习惯不存在或已被删除',
        'This habit is unavailable or has been deleted',
      ),
      WidgetActionNotice.habitUnsupported => pick(
        '这个习惯不支持快捷打卡',
        'This habit does not support quick check-in',
      ),
      WidgetActionNotice.habitNotScheduled => pick(
        '“$subject”今天不需要打卡',
        '“$subject” is not scheduled for today',
      ),
      WidgetActionNotice.habitAlreadyCompleted => pick(
        '“$subject”今天已经完成',
        '“$subject” is already complete today',
      ),
      WidgetActionNotice.unknownEntry => pick(
        '无法识别的入口，已返回我的',
        'Unknown link. Opened Me instead',
      ),
      WidgetActionNotice.quickTodoUnavailable => pick(
        '快捷待办暂不可用，请打开待办页后重试',
        'Quick add is unavailable. Open Tasks and try again',
      ),
      WidgetActionNotice.quickTodoFailed => pick(
        '快捷待办创建失败，请稍后重试',
        'Could not create the task. Please try again',
      ),
      WidgetActionNotice.hydrationFailed => pick(
        '内容加载失败，请重新打开多仪',
        'Could not load content. Please reopen Duoyi',
      ),
      WidgetActionNotice.staleContent => pick(
        '小组件内容已过期，请刷新后再操作',
        'Widget content is out of date. Refresh and try again',
      ),
      WidgetActionNotice.validationFailed => pick(
        '内容加载失败，请刷新小组件',
        'Could not load content. Please refresh the widget',
      ),
      WidgetActionNotice.refreshSucceeded => pick(
        '小组件已刷新',
        'Widgets refreshed',
      ),
      WidgetActionNotice.refreshFailed => pick(
        '刷新失败，请稍后重试',
        'Could not refresh widgets. Please try again',
      ),
      WidgetActionNotice.habitCheckedIn => pick(
        '已打卡：$subject',
        'Checked in: $subject',
      ),
      WidgetActionNotice.habitSaving => pick(
        '习惯正在保存中，请稍后重试',
        'The habit is still saving. Please try again shortly',
      ),
      WidgetActionNotice.habitCheckInFailed => pick(
        '打卡失败，请稍后重试',
        'Could not check in. Please try again',
      ),
      WidgetActionNotice.todoCompleted => pick(
        '已完成：$subject',
        'Completed: $subject',
      ),
      WidgetActionNotice.todoSaving => pick(
        '待办正在保存中，请稍后重试',
        'The task is still saving. Please try again shortly',
      ),
      WidgetActionNotice.todoCompletionFailed => pick(
        '待办完成失败，请稍后重试',
        'Could not complete the task. Please try again',
      ),
      WidgetActionNotice.reminderConfigurationInvalid => pick(
        '$issueLabel：提醒配置异常，请在待办详情中重新设置提醒。',
        '$issueLabel: invalid reminder settings. Reset them in task details.',
      ),
      WidgetActionNotice.reminderNotRegistered => pick(
        '$issueLabel：提醒未注册，请检查通知权限、渠道声音和提醒时间。',
        '$issueLabel: check notification permissions, channel sound and reminder time.',
      ),
      WidgetActionNotice.alarmPermissionDenied => pick(
        '$issueLabel：系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。',
        '$issueLabel: notifications are disabled. Enable them and save the alarm reminder again.',
      ),
      WidgetActionNotice.reminderIssue => pick(
        '提醒状态需检查：$subject：$detail',
        'Reminder status needs attention: $subject: $detail',
      ),
      WidgetActionNotice.savedReminderIssue => pick(
        '快捷待办已保存到本机，提醒状态需检查：$detail',
        'Task saved on this device. Check reminder status: $detail',
      ),
      WidgetActionNotice.todoSaved => _savedMessage(isZh),
    };
  }

  String _savedMessage(bool isZh) {
    String pick(String zh, String en) => isZh ? zh : en;
    final saved = pick('待办已保存到本机', 'Task saved on this device');
    final status = switch (syncState) {
      WidgetActionSyncState.unknown => pick(
        '云同步状态待确认',
        'Cloud sync status is unconfirmed',
      ),
      WidgetActionSyncState.disabled => pick(
        '尚未上传服务器：当前版本未启用云同步。',
        'Not uploaded: cloud sync is disabled in this version.',
      ),
      WidgetActionSyncState.accountTransition => pick(
        '尚未上传服务器：账号切换处理中，云同步已暂停。',
        'Not uploaded: cloud sync is paused while switching accounts.',
      ),
      WidgetActionSyncState.signedOut => pick(
        '尚未上传服务器：未登录云同步账号。',
        'Not uploaded: no cloud sync account is signed in.',
      ),
      WidgetActionSyncState.serverDisabled => pick(
        '尚未上传服务器：管理员已关闭云端备份。',
        'Not uploaded: cloud backup is disabled by the administrator.',
      ),
      WidgetActionSyncState.autoSyncOff => pick(
        '尚未上传服务器：自动同步已关闭，重新开启后会继续同步。',
        'Not uploaded: automatic sync is off. Enable it to resume syncing.',
      ),
      WidgetActionSyncState.retryPending => pick(
        '云同步上次未完成，稍后会自动重试。',
        'Cloud sync is incomplete and will retry automatically.',
      ),
      WidgetActionSyncState.failed => pick(
        '云同步上次失败，稍后会自动重试',
        'Cloud sync failed and will retry automatically',
      ),
      WidgetActionSyncState.backgroundUpload => pick(
        '云同步会后台上传',
        'Cloud sync will upload in the background',
      ),
    };
    final reason = syncReason.isEmpty
        ? ''
        : pick('：$syncReason', ': $syncReason');
    final hint = switch (reminderHint) {
      WidgetActionReminderHint.none => '',
      WidgetActionReminderHint.settings => pick(
        '；提醒状态可在通知设置/待办详情检查',
        '; check reminder status in Notification Settings or task details',
      ),
      WidgetActionReminderHint.details => pick(
        '；提醒状态可在待办详情中检查',
        '; check reminder status in task details',
      ),
    };
    return '$saved${pick('，', '. ')}$status$reason$hint';
  }
}
