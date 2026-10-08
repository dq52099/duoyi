import 'dart:async';

import '../core/i18n.dart';
import '../models/goal.dart';
import 'reminder_issue_copy.dart';

enum ReminderSyncIssueNotice {
  schedulerMissing,
  registrationUnconfirmed,
  pushNotRegistered,
  repeatingPushNotRegistered,
  ruleNotRegistered,
  genericFailure,
}

enum ReminderSyncObject { task, goal, reminder }

/// A diagnostic and its explicit presentation projection, never inferred text.
final class ReminderSyncIssueEntry {
  const ReminderSyncIssueEntry(
    this.raw, {
    this.copy,
    this.includeTitle = false,
    this.rawTitle = '',
    this.rawMessage = '',
    this.notice,
    this.kind = ReminderKind.off,
    this.object = ReminderSyncObject.reminder,
    this.target = '',
  });

  final String raw;
  final ReminderIssueCopy? copy;
  final bool includeTitle;
  final String rawTitle;
  final String rawMessage;
  final ReminderSyncIssueNotice? notice;
  final ReminderKind kind;
  final ReminderSyncObject object;
  final String target;

  String render({AppLocale? locale}) {
    final selected = locale ?? I18n.current;
    final isZh = selected == AppLocale.zh;
    String pick(String zh, String en) => isZh ? zh : en;
    if (copy != null) {
      final message = copy!.renderMessage(
        fallback: rawMessage,
        locale: selected,
      );
      if (!includeTitle) return message;
      final title = copy!.renderTitle(fallback: rawTitle, locale: selected);
      return '$title${isZh ? '：' : ': '}$message';
    }
    return switch (notice) {
      ReminderSyncIssueNotice.schedulerMissing => pick(
        '提醒服务暂不可用，请稍后重新保存提醒。',
        'The reminder service is unavailable. Save the reminder again later.',
      ),
      ReminderSyncIssueNotice.registrationUnconfirmed => pick(
        '提醒调度器未能确认规则已注册到系统',
        'The reminder scheduler could not confirm system registration.',
      ),
      ReminderSyncIssueNotice.pushNotRegistered => pick(
        '系统通知服务返回未注册',
        'The system notification service reported no registration.',
      ),
      ReminderSyncIssueNotice.repeatingPushNotRegistered => pick(
        '系统重复通知服务返回未注册',
        'The system notification service reported no repeating registration.',
      ),
      ReminderSyncIssueNotice.ruleNotRegistered => _renderRule(selected),
      ReminderSyncIssueNotice.genericFailure => pick(
        '提醒未注册成功，请检查通知权限、提醒方式和提醒时间。',
        'The reminder was not registered. Check notification permission, reminder type and time.',
      ),
      null => raw,
    };
  }

  String _renderRule(AppLocale locale) {
    final isZh = locale == AppLocale.zh;
    String pick(String zh, String en) => isZh ? zh : en;
    final title = switch (object) {
      ReminderSyncObject.task => pick(
        '待办提醒注册失败',
        'Task reminder not registered',
      ),
      ReminderSyncObject.goal => pick(
        '目标提醒注册失败',
        'Goal reminder not registered',
      ),
      ReminderSyncObject.reminder => pick('提醒注册失败', 'Reminder not registered'),
    };
    final name = target.trim().isEmpty
        ? pick('该提醒', 'This reminder')
        : '“$target”';
    final channel = switch (kind) {
      ReminderKind.popup => pick('弹出提醒', 'pop-up reminder'),
      ReminderKind.alarm => pick('闹钟提醒', 'alarm reminder'),
      ReminderKind.push => pick('普通通知', 'notification reminder'),
      ReminderKind.email => pick('邮件提醒', 'email reminder'),
      ReminderKind.off => pick('关闭', 'disabled reminder'),
    };
    final hint = switch (kind) {
      ReminderKind.popup => pick(
        '请保持应用前台运行，或开启系统通知权限以便后台兜底。',
        'Keep the app in the foreground, or enable notifications for the background fallback.',
      ),
      ReminderKind.alarm => pick(
        '请检查通知权限、精准闹钟权限、全屏提醒权限和强提醒渠道。',
        'Check notification, exact alarm and full-screen permissions, and the strong alert channel.',
      ),
      ReminderKind.push => pick(
        '请检查系统通知权限和通知渠道。',
        'Check notification permission and channels.',
      ),
      ReminderKind.email => pick(
        '请检查邮件提醒服务配置。',
        'Check the email reminder service configuration.',
      ),
      ReminderKind.off => pick('请重新启用提醒方式。', 'Enable a reminder type again.'),
    };
    return isZh
        ? '$title：$name 的$channel未注册成功。$hint'
        : '$title: $name: $channel not registered. $hint';
  }
}

/// Ordered entries keep the exact legacy aggregate alongside localized copy.
final class ReminderSyncIssue {
  ReminderSyncIssue(Iterable<ReminderSyncIssueEntry> entries)
    : entries = List.unmodifiable(entries);

  factory ReminderSyncIssue.literal(String raw) =>
      ReminderSyncIssue([ReminderSyncIssueEntry(raw)]);

  final List<ReminderSyncIssueEntry> entries;

  String get raw => entries.map((entry) => entry.raw).join('；');

  String render({AppLocale? locale}) {
    final selected = locale ?? I18n.current;
    return entries
        .map((entry) => entry.render(locale: selected))
        .join(selected == AppLocale.zh ? '；' : '; ');
  }
}

/// Metadata belongs to one returned operation, rather than a mutable getter.
abstract interface class ReminderTodoFailureResultFuture {
  Future<ReminderSyncIssue?> get issueResult;
}

/// Legacy callers still await String?, including subclasses overriding that API.
final class ReminderTodoFailureFuture
    implements Future<String?>, ReminderTodoFailureResultFuture {
  ReminderTodoFailureFuture(this.issueResult);

  @override
  final Future<ReminderSyncIssue?> issueResult;

  // Construct this projection only when a legacy consumer observes it.
  late final Future<String?> _legacy = issueResult.then((issue) => issue?.raw);

  @override
  Stream<String?> asStream() => _legacy.asStream();

  @override
  Future<String?> catchError(Function onError, {bool Function(Object)? test}) =>
      _legacy.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(String?) onValue, {
    Function? onError,
  }) => _legacy.then(onValue, onError: onError);

  @override
  Future<String?> timeout(
    Duration timeLimit, {
    FutureOr<String?> Function()? onTimeout,
  }) => _legacy.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<String?> whenComplete(FutureOr<void> Function() action) =>
      _legacy.whenComplete(action);
}
