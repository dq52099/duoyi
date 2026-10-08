import 'package:test/test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/services/notification_permission_exception.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';
import 'package:duoyi/services/todo_reminder_preflight_copy.dart';

const Object _omittedTitle = Object();
const String _missingDateRawMessage = '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  group('NotificationService issue copy', () {
    test(
      'ensureReady records an expired-time issue before permission or channel calls',
      () async {
        final service = NotificationService();
        addTearDown(service.dispose);
        final past = DateTime.now().subtract(const Duration(minutes: 2));

        final ready = await service.ensureReadyForReminder(
          scheduledTime: past,
          relatedId: '  task-42  ',
          issueTitleCode: NotificationIssueTitle.registrationFailed,
        );

        expect(ready, isFalse);
        final issue = service.lastScheduleIssue!;
        expect(issue.title, '提醒注册失败');
        expect(issue.message, '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。');
        expect(issue.blocking, isTrue);
        expect(issue.scheduledTime, past);
        expect(issue.relatedId, 'task-42');
        expect(issue.copy?.notice, NotificationIssueNotice.timePassed);
        expect(
          issue.copy?.titleCode,
          NotificationIssueTitle.registrationFailed,
        );
        expect(
          issue.renderTitle(locale: AppLocale.en),
          'Reminder not registered',
        );
        expect(
          issue.renderMessage(locale: AppLocale.en),
          'The reminder time has passed and no system notification was registered. Choose a future time.',
        );
        expect(service.historyCount, 0);
        expect(service.pendingCount, 0);
        expect(service.unreadCount, 0);
      },
    );

    test(
      'omitted, null, default, empty, whitespace, custom, and coded titles keep ownership',
      () async {
        final omitted = await _recordPastEnsureReadyIssue();
        final explicitNull = await _recordPastEnsureReadyIssue(
          issueTitle: null,
        );
        final explicitDefault = await _recordPastEnsureReadyIssue(
          issueTitle: '提醒注册失败',
        );

        for (final issue in [omitted, explicitNull]) {
          expect(issue.title, '提醒注册失败');
          expect(
            issue.copy?.titleCode,
            NotificationIssueTitle.registrationFailed,
          );
          expect(
            issue.renderTitle(locale: AppLocale.en),
            'Reminder not registered',
          );
        }

        expect(explicitDefault.title, '提醒注册失败');
        expect(explicitDefault.copy?.titleCode, isNull);
        expect(explicitDefault.renderTitle(locale: AppLocale.en), '提醒注册失败');

        for (final title in ['', '   ', 'Custom reminder label']) {
          final custom = await _recordPastEnsureReadyIssue(issueTitle: title);
          expect(custom.title, title);
          expect(custom.copy?.titleCode, isNull);
          expect(custom.renderTitle(locale: AppLocale.en), title);
        }

        final coded = await _recordPastEnsureReadyIssue(
          issueTitle: 'Caller-owned literal title',
          issueTitleCode: NotificationIssueTitle.snoozeWarning,
        );
        expect(coded.title, 'Caller-owned literal title');
        expect(coded.copy?.titleCode, NotificationIssueTitle.snoozeWarning);
        expect(coded.renderTitle(locale: AppLocale.zh), '稍后提醒注册异常');
        expect(
          coded.renderTitle(locale: AppLocale.en),
          'Check snoozed reminder',
        );
      },
    );

    test(
      'typed records preserve raw fields and duplicate updates replace copy without notifying twice',
      () {
        final service = NotificationService();
        addTearDown(service.dispose);
        var notifications = 0;
        service.addListener(() => notifications++);
        final scheduledTime = DateTime.utc(2026, 10, 8, 12);
        const title = 'raw notification title';
        const message = 'raw service diagnostic';
        final firstCopy = ReminderIssueCopy.notification(
          NotificationIssueNotice.timePassed,
          titleCode: NotificationIssueTitle.taskRegistrationFailed,
          detail: 'raw native detail <first>',
        );
        final latestCopy = ReminderIssueCopy.notification(
          NotificationIssueNotice.sendFailed,
          titleCode: NotificationIssueTitle.sendFailed,
          detail: 'raw native detail <latest>',
        );

        service.recordReminderScheduleIssueWithCopy(
          title: title,
          message: message,
          copy: firstCopy,
          scheduledTime: scheduledTime,
          relatedId: '  task-42  ',
          blocking: false,
        );
        final first = service.lastScheduleIssue!;
        expect(notifications, 1);
        expect(first.title, title);
        expect(first.message, message);
        expect(first.relatedId, 'task-42');
        expect(first.scheduledTime, scheduledTime);
        expect(first.blocking, isFalse);
        expect(first.copy, same(firstCopy));
        expect(
          first.renderMessage(locale: AppLocale.en),
          endsWith('(raw native detail <first>)'),
        );

        I18n.setLocale(AppLocale.en);
        expect(first.renderTitle(locale: AppLocale.zh), '待办提醒注册失败');
        expect(I18n.current, AppLocale.en);
        service.recordReminderScheduleIssueWithCopy(
          title: title,
          message: message,
          copy: latestCopy,
          scheduledTime: scheduledTime,
          relatedId: 'task-42',
          blocking: false,
        );

        final latest = service.lastScheduleIssue!;
        expect(notifications, 1);
        expect(latest.title, title);
        expect(latest.message, message);
        expect(latest.relatedId, 'task-42');
        expect(latest.scheduledTime, scheduledTime);
        expect(latest.blocking, isFalse);
        expect(latest.copy, same(latestCopy));
        expect(latest.happenedAt.isBefore(first.happenedAt), isFalse);
        expect(
          latest.renderTitle(locale: AppLocale.en),
          'Notification not sent',
        );
        expect(
          latest.renderMessage(locale: AppLocale.en),
          endsWith('(raw native detail <latest>)'),
        );
        expect(service.historyCount, 0);
        expect(service.pendingCount, 0);
        expect(service.unreadCount, 0);
      },
    );

    test(
      'legacy issue recording preserves literals and leaves copy absent',
      () {
        final service = NotificationService();
        addTearDown(service.dispose);
        const title = '  upstream title  ';
        const message = 'raw upstream reason: 502 <body>';

        service.recordReminderScheduleIssue(
          title: title,
          message: message,
          relatedId: '  todo:task-legacy  ',
          blocking: false,
        );

        final issue = service.lastScheduleIssue!;
        expect(issue.title, title);
        expect(issue.message, message);
        expect(issue.copy, isNull);
        expect(issue.relatedId, 'task-legacy');
        expect(issue.blocking, isFalse);
        expect(issue.renderTitle(locale: AppLocale.en), title);
        expect(issue.renderMessage(locale: AppLocale.en), message);
        expect(service.historyCount, 0);
        expect(service.pendingCount, 0);
        expect(service.unreadCount, 0);
      },
    );

    test(
      'past scheduleOnce throws with issue copy while retaining legacy exception text',
      () async {
        final service = NotificationService();
        addTearDown(service.dispose);
        final past = DateTime.now().subtract(const Duration(minutes: 1));
        late NotificationScheduleUnavailableException failure;

        try {
          await service.scheduleOnce(
            id: 73,
            title: 'Task',
            body: 'Task reminder',
            when: past,
            payload: 'duoyi://todo/past-task',
          );
          fail(
            'Expected the past schedule time to fail before native scheduling.',
          );
        } on NotificationScheduleUnavailableException catch (error) {
          failure = error;
        }

        final issue = service.lastScheduleIssue!;
        expect(failure.title, issue.title);
        expect(failure.message, issue.message);
        expect(failure.copy, same(issue.copy));
        expect(failure.scheduledTime, past);
        expect(failure.relatedId, 'past-task');
        expect(failure.toString(), '${issue.title}：${issue.message}');
        expect(
          failure.renderTitle(locale: AppLocale.en),
          'Reminder not registered',
        );
        expect(
          failure.renderMessage(locale: AppLocale.en),
          'The reminder time has passed and no system notification was registered. Choose a future time.',
        );
        expect(service.historyCount, 0);
        expect(service.pendingCount, 0);
        expect(service.unreadCount, 0);
      },
    );
  });

  group('ReminderScheduler unresolved preflight issue', () {
    test(
      'typed notification sink records one coded issue and keeps raw failure',
      () async {
        final notification = _TypedNotificationFake();
        final alarm = _OldInterfaceAlarmFake();
        final scheduler = _newScheduler(notification, alarm);
        final todo = _todoWithoutOneShotDate('typed-preflight-todo');

        final failure = await scheduler.syncTodosAndGetTodoFailure([
          todo,
        ], todo.id);

        expect(failure, _missingDateRawMessage);
        expect(notification.copiedIssues, hasLength(1));
        expect(notification.legacyIssues, isEmpty);
        final recorded = notification.copiedIssues.single;
        expect(recorded.title, '待办提醒注册失败');
        expect(recorded.message, _missingDateRawMessage);
        expect(recorded.relatedId, todo.id);
        expect(recorded.scheduledTime, isNull);
        expect(recorded.blocking, isTrue);
        expect(
          recorded.copy?.preflight?.notice,
          TodoReminderPreflightNotice.missingDate,
        );
        expect(
          recorded.copy!.renderTitle(
            fallback: recorded.title,
            locale: AppLocale.en,
          ),
          'Task reminder not registered',
        );
        expect(
          recorded.copy!.renderMessage(
            fallback: recorded.message,
            locale: AppLocale.en,
          ),
          'A one-time reminder needs a due date or reminder date. Set a future date first.',
        );
        expect(notification.scheduleCalls, 0);
        expect(alarm.scheduleCalls, 0);
      },
    );

    test(
      'legacy notification sink records one raw issue and unchanged failure',
      () async {
        final notification = _LegacyNotificationFake();
        final alarm = _OldInterfaceAlarmFake();
        final scheduler = _newScheduler(notification, alarm);
        final todo = _todoWithoutOneShotDate('legacy-preflight-todo');

        final failure = await scheduler.syncTodosAndGetTodoFailure([
          todo,
        ], todo.id);

        expect(failure, _missingDateRawMessage);
        expect(notification, isNot(isA<ReminderScheduleIssueCopySink>()));
        expect(notification.issues, hasLength(1));
        final recorded = notification.issues.single;
        expect(recorded.title, '待办提醒注册失败');
        expect(recorded.message, _missingDateRawMessage);
        expect(recorded.copy, isNull);
        expect(recorded.relatedId, todo.id);
        expect(recorded.scheduledTime, isNull);
        expect(recorded.blocking, isTrue);
        expect(notification.scheduleCalls, 0);
        expect(alarm.scheduleCalls, 0);
      },
    );
  });
}

Future<NotificationScheduleIssue> _recordPastEnsureReadyIssue({
  Object? issueTitle = _omittedTitle,
  NotificationIssueTitle? issueTitleCode,
}) async {
  final service = NotificationService();
  final past = DateTime.now().subtract(const Duration(minutes: 1));
  if (identical(issueTitle, _omittedTitle)) {
    await service.ensureReadyForReminder(
      scheduledTime: past,
      issueTitleCode: issueTitleCode,
    );
  } else {
    await service.ensureReadyForReminder(
      scheduledTime: past,
      issueTitle: issueTitle as String?,
      issueTitleCode: issueTitleCode,
    );
  }
  final issue = service.lastScheduleIssue!;
  service.dispose();
  return issue;
}

TodoItem _todoWithoutOneShotDate(String id) => TodoItem(
  id: id,
  title: 'Reminder without a date',
  reminderPlan: ReminderPlan(
    enabled: true,
    rules: [
      ReminderRule(
        id: 'one-shot',
        type: ReminderRuleType.absolute,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
      ),
    ],
  ),
);

ReminderScheduler _newScheduler(
  _NoopNotificationSink notification,
  _OldInterfaceAlarmFake alarm,
) => ReminderScheduler(
  notification,
  alarm: alarm,
  popup: const NoopReminderPopupSink(),
  registry: InMemoryReminderScheduleRegistry(),
);

class _RecordedIssue {
  const _RecordedIssue({
    required this.title,
    required this.message,
    required this.copy,
    required this.scheduledTime,
    required this.relatedId,
    required this.blocking,
  });

  final String title;
  final String message;
  final ReminderIssueCopy? copy;
  final DateTime? scheduledTime;
  final String? relatedId;
  final bool blocking;
}

class _NoopNotificationSink implements ReminderNotificationSink {
  int scheduleCalls = 0;

  Future<void> _unexpectedSchedule(String label) async {
    scheduleCalls++;
    throw StateError('Unexpected notification scheduling: $label');
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) => _unexpectedSchedule('once');

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) => _unexpectedSchedule('daily');

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
  }) => _unexpectedSchedule('habit');

  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) => _unexpectedSchedule('anniversary');
}

class _TypedNotificationFake extends _NoopNotificationSink
    implements ReminderScheduleIssueSink, ReminderScheduleIssueCopySink {
  final List<_RecordedIssue> legacyIssues = [];
  final List<_RecordedIssue> copiedIssues = [];

  @override
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    legacyIssues.add(
      _RecordedIssue(
        title: title,
        message: message,
        copy: null,
        scheduledTime: scheduledTime,
        relatedId: relatedId,
        blocking: blocking,
      ),
    );
  }

  @override
  void recordReminderScheduleIssueWithCopy({
    required String title,
    required String message,
    required ReminderIssueCopy copy,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    copiedIssues.add(
      _RecordedIssue(
        title: title,
        message: message,
        copy: copy,
        scheduledTime: scheduledTime,
        relatedId: relatedId,
        blocking: blocking,
      ),
    );
  }
}

class _LegacyNotificationFake extends _NoopNotificationSink
    implements ReminderScheduleIssueSink {
  final List<_RecordedIssue> issues = [];

  @override
  void recordReminderScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    String? relatedId,
    bool blocking = true,
  }) {
    issues.add(
      _RecordedIssue(
        title: title,
        message: message,
        copy: null,
        scheduledTime: scheduledTime,
        relatedId: relatedId,
        blocking: blocking,
      ),
    );
  }
}

class _OldInterfaceAlarmFake implements ReminderAlarmSink {
  int scheduleCalls = 0;

  Future<void> _unexpectedSchedule(String label) async {
    scheduleCalls++;
    throw StateError('Unexpected alarm scheduling: $label');
  }

  @override
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
  }) => _unexpectedSchedule('once');

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
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) => _unexpectedSchedule('daily');

  @override
  Future<void> cancel(int id) async {}
}
