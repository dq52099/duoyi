import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show TodoReminderPreflightIssue, preflightTodoReminderPlan;
import 'package:duoyi/services/todo_reminder_preflight_copy.dart';
import 'package:duoyi/services/widget_action_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('all five copy codes have canonical bilingual title and message', () {
    final expected = <TodoReminderPreflightNotice, (String, String, String, String)>{
      TodoReminderPreflightNotice.missingDate: (
        '待办提醒注册失败',
        '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。',
        'Task reminder not registered',
        'A one-time reminder needs a due date or reminder date. Set a future date first.',
      ),
      TodoReminderPreflightNotice.timeInPast: (
        '待办提醒注册失败',
        '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
        'Task reminder not registered',
        'The reminder time has passed and no system notification was registered. Choose a future time.',
      ),
      TodoReminderPreflightNotice.invalidRepeatTime: (
        '重复提醒注册失败',
        '重复提醒缺少有效时间，请重新选择提醒时间。',
        'Repeating reminder not registered',
        'The repeating reminder needs a valid time. Select the reminder time again.',
      ),
      TodoReminderPreflightNotice.invalidWeeklyRule: (
        '每周提醒注册失败',
        '每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
        'Weekly reminder not registered',
        'A weekly reminder needs a valid time and at least one weekday. Select the reminder rule again.',
      ),
      TodoReminderPreflightNotice.noDeliverableRule: (
        '待办提醒注册失败',
        '提醒计划没有可注册的规则，请重新设置提醒。',
        'Task reminder not registered',
        'The reminder plan has no rules that can be registered. Set up the reminder again.',
      ),
    };

    expect(expected.keys.toSet(), TodoReminderPreflightNotice.values.toSet());
    for (final entry in expected.entries) {
      final copy = TodoReminderPreflightCopy(entry.key);
      expect(copy.title(locale: AppLocale.zh), entry.value.$1);
      expect(copy.message(locale: AppLocale.zh), entry.value.$2);
      expect(copy.title(locale: AppLocale.en), entry.value.$3);
      expect(copy.message(locale: AppLocale.en), entry.value.$4);
    }
  });

  test('coded and raw preflight issues preserve their distinct payloads', () {
    final scheduledTime = DateTime(2026, 6, 5, 12, 45);
    final coded = TodoReminderPreflightIssue.coded(
      TodoReminderPreflightNotice.invalidWeeklyRule,
      blocking: false,
      scheduledTime: scheduledTime,
    );
    expect(coded.blocking, isFalse);
    expect(coded.scheduledTime, scheduledTime);
    expect(coded.copy, isNotNull);
    expect(coded.copy!.notice, TodoReminderPreflightNotice.invalidWeeklyRule);
    expect(coded.title, coded.copy!.title(locale: AppLocale.zh));
    expect(coded.message, coded.copy!.message(locale: AppLocale.zh));

    const rawTitle = '待办提醒注册失败';
    const rawMessage = '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。';
    final raw = TodoReminderPreflightIssue(
      title: rawTitle,
      message: rawMessage,
      blocking: false,
      scheduledTime: scheduledTime,
    );
    expect(raw.copy, isNull);
    expect(raw.title, rawTitle);
    expect(raw.message, rawMessage);
    expect(raw.blocking, isFalse);
    expect(raw.scheduledTime, scheduledTime);

    final rawMessageDescriptor = WidgetActionMessage(
      WidgetActionNotice.reminderIssue,
      subject: raw.title,
      detail: raw.message,
      preflightCopy: raw.copy,
    );
    expect(
      rawMessageDescriptor.render(locale: AppLocale.en),
      'Reminder status needs attention: $rawTitle: $rawMessage',
      reason: 'untyped raw text is not heuristically translated',
    );
  });

  test(
    'each reachable preflight producer attaches its code and canonical copy',
    () {
      final now = DateTime(2026, 6, 5, 12);
      TodoItem withRule(
        String id,
        ReminderRule rule, {
        DateTime? dueDate,
        DateTime? reminderAt,
      }) => TodoItem(
        id: id,
        title: id,
        dueDate: dueDate,
        reminderAt: reminderAt,
        reminderPlan: ReminderPlan(enabled: true, rules: [rule]),
      );

      final cases =
          <
            ({
              String name,
              TodoItem todo,
              TodoReminderPreflightNotice notice,
              DateTime? scheduledTime,
            })
          >[
            (
              name: 'absolute one-shot without date',
              todo: withRule(
                'absolute-missing-date',
                ReminderRule(
                  id: 'absolute-missing-date-rule',
                  type: ReminderRuleType.absolute,
                  kind: ReminderKind.push,
                  hour: 13,
                  minute: 0,
                ),
              ),
              notice: TodoReminderPreflightNotice.missingDate,
              scheduledTime: null,
            ),
            (
              name: 'relative one-shot without due date',
              todo: withRule(
                'relative-missing-date',
                ReminderRule(
                  id: 'relative-missing-date-rule',
                  type: ReminderRuleType.relativeToDue,
                  kind: ReminderKind.push,
                  hour: 13,
                  minute: 0,
                  offsetMinutes: -15,
                ),
              ),
              notice: TodoReminderPreflightNotice.missingDate,
              scheduledTime: null,
            ),
            (
              name: 'absolute one-shot in the past',
              todo: withRule(
                'absolute-time-in-past',
                ReminderRule(
                  id: 'absolute-time-in-past-rule',
                  type: ReminderRuleType.absolute,
                  kind: ReminderKind.push,
                  hour: 10,
                  minute: 30,
                ),
                dueDate: DateTime(2026, 6, 5),
              ),
              notice: TodoReminderPreflightNotice.timeInPast,
              scheduledTime: DateTime(2026, 6, 5, 10, 30),
            ),
            (
              name: 'relative one-shot in the past',
              todo: withRule(
                'relative-time-in-past',
                ReminderRule(
                  id: 'relative-time-in-past-rule',
                  type: ReminderRuleType.relativeToDue,
                  kind: ReminderKind.push,
                  hour: 11,
                  minute: 30,
                  offsetMinutes: -60,
                ),
                dueDate: DateTime(2026, 6, 5),
              ),
              notice: TodoReminderPreflightNotice.timeInPast,
              scheduledTime: DateTime(2026, 6, 5, 10, 30),
            ),
            (
              name: 'daily rule with invalid time',
              todo: withRule(
                'invalid-daily-time',
                ReminderRule(
                  id: 'invalid-daily-time-rule',
                  type: ReminderRuleType.dailyTime,
                  kind: ReminderKind.push,
                  hour: 25,
                  minute: 0,
                ),
              ),
              notice: TodoReminderPreflightNotice.invalidRepeatTime,
              scheduledTime: null,
            ),
            (
              name: 'weekly rule without weekdays',
              todo: withRule(
                'invalid-weekly-rule',
                ReminderRule(
                  id: 'invalid-weekly-rule-rule',
                  type: ReminderRuleType.weeklyTime,
                  kind: ReminderKind.push,
                  hour: 9,
                  minute: 0,
                ),
              ),
              notice: TodoReminderPreflightNotice.invalidWeeklyRule,
              scheduledTime: null,
            ),
          ];

      for (final entry in cases) {
        final result = preflightTodoReminderPlan(entry.todo, now: now);
        expect(result.hasEnabledPlan, isTrue, reason: entry.name);
        final issue = result.blockingIssue;
        expect(issue, isNotNull, reason: entry.name);
        expect(issue!.blocking, isTrue, reason: entry.name);
        expect(issue.scheduledTime, entry.scheduledTime, reason: entry.name);
        expect(issue.copy, isNotNull, reason: entry.name);
        expect(issue.copy!.notice, entry.notice, reason: entry.name);
        expect(
          issue.title,
          issue.copy!.title(locale: AppLocale.zh),
          reason: entry.name,
        );
        expect(
          issue.message,
          issue.copy!.message(locale: AppLocale.zh),
          reason: entry.name,
        );
      }
      // noDeliverableRule is only a defensive fallback: every enabled rule
      // above is either deliverable or adds its own issue before that check.
    },
  );

  test('preflight prefers valid enabled plans and filters disabled rules', () {
    final now = DateTime(2026, 6, 5, 12);
    final validMixed = TodoItem(
      id: 'valid-mixed-plan',
      title: 'valid mixed plan',
      dueDate: DateTime(2026, 6, 5),
      reminder: const ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 8,
        minute: 0,
      ),
      reminderPlan: ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'future-absolute',
            type: ReminderRuleType.absolute,
            kind: ReminderKind.alarm,
            hour: 14,
            minute: 0,
          ),
          ReminderRule(
            id: 'disabled-invalid-weekly',
            enabled: false,
            type: ReminderRuleType.weeklyTime,
            kind: ReminderKind.email,
            hour: 26,
          ),
          ReminderRule(
            id: 'off-invalid-weekly',
            type: ReminderRuleType.weeklyTime,
            kind: ReminderKind.off,
            hour: 26,
          ),
        ],
      ),
    );
    final mixedResult = preflightTodoReminderPlan(validMixed, now: now);
    expect(mixedResult.hasEnabledPlan, isTrue);
    expect(mixedResult.ok, isTrue);
    expect(mixedResult.issues, isEmpty);
    expect(mixedResult.kinds, {ReminderKind.alarm});
    expect(mixedResult.firstScheduledTime, DateTime(2026, 6, 5, 14));

    final partlyInvalidPlan = TodoItem(
      id: 'partly-invalid-plan',
      title: 'partly invalid plan',
      dueDate: DateTime(2026, 6, 5),
      reminderPlan: ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'deliverable-absolute',
            type: ReminderRuleType.absolute,
            kind: ReminderKind.push,
            hour: 14,
            minute: 0,
          ),
          ReminderRule(
            id: 'blocking-weekly',
            type: ReminderRuleType.weeklyTime,
            kind: ReminderKind.alarm,
            hour: 9,
            minute: 0,
          ),
        ],
      ),
    );
    final partlyInvalidResult = preflightTodoReminderPlan(
      partlyInvalidPlan,
      now: now,
    );
    expect(partlyInvalidResult.hasEnabledPlan, isTrue);
    expect(partlyInvalidResult.ok, isFalse);
    expect(
      partlyInvalidResult.blockingIssue?.copy?.notice,
      TodoReminderPreflightNotice.invalidWeeklyRule,
    );
    expect(partlyInvalidResult.firstScheduledTime, DateTime(2026, 6, 5, 14));
    expect(partlyInvalidResult.kinds, {ReminderKind.push, ReminderKind.alarm});

    final disabledPlan = TodoItem(
      id: 'disabled-plan',
      title: 'disabled plan',
      reminderPlan: ReminderPlan(
        enabled: false,
        rules: [
          ReminderRule(
            id: 'retained-invalid-rule',
            type: ReminderRuleType.dailyTime,
            kind: ReminderKind.push,
            hour: 28,
            minute: 0,
          ),
        ],
      ),
    );
    final disabledResult = preflightTodoReminderPlan(disabledPlan, now: now);
    expect(disabledResult.hasEnabledPlan, isFalse);
    expect(disabledResult.issues, isEmpty);

    final legacyFallback = TodoItem(
      id: 'empty-new-plan-falls-back-to-legacy',
      title: 'legacy fallback',
      reminder: const ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
      ),
      reminderPlan: ReminderPlan(enabled: true),
    );
    final fallbackResult = preflightTodoReminderPlan(legacyFallback, now: now);
    expect(fallbackResult.hasEnabledPlan, isTrue);
    expect(
      fallbackResult.blockingIssue?.copy?.notice,
      TodoReminderPreflightNotice.missingDate,
    );

    final conflictingLegacy = TodoItem(
      id: 'nonempty-new-plan-wins',
      title: 'new plan wins',
      reminder: const ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
      ),
      reminderPlan: ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'valid-daily',
            type: ReminderRuleType.dailyTime,
            kind: ReminderKind.popup,
            hour: 9,
            minute: 0,
          ),
        ],
      ),
    );
    final preferredResult = preflightTodoReminderPlan(
      conflictingLegacy,
      now: now,
    );
    expect(preferredResult.ok, isTrue);
    expect(preferredResult.kinds, {ReminderKind.popup});
  });

  test('explicit locale renders typed preflight copy without changing I18n', () {
    I18n.setLocale(AppLocale.en);
    final issue = TodoReminderPreflightIssue.coded(
      TodoReminderPreflightNotice.invalidWeeklyRule,
    );
    final descriptor = WidgetActionMessage(
      WidgetActionNotice.reminderIssue,
      subject: issue.title,
      detail: issue.message,
      preflightCopy: issue.copy,
    );

    expect(issue.copy!.title(locale: AppLocale.zh), '每周提醒注册失败');
    expect(
      descriptor.render(locale: AppLocale.zh),
      '提醒状态需检查：每周提醒注册失败：每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
    );
    expect(
      descriptor.render(locale: AppLocale.en),
      'Reminder status needs attention: Weekly reminder not registered: A weekly reminder needs a valid time and at least one weekday. Select the reminder rule again.',
    );
    expect(descriptor.subject, issue.title);
    expect(descriptor.detail, issue.message);
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });
}
