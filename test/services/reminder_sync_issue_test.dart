import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/services/reminder_sync_issue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('mixed entries preserve raw order and render with one explicit locale', () {
    const diagnostic = 'permission probe / 系统返回=0xD3';
    final issue = ReminderSyncIssue([
      const ReminderSyncIssueEntry(
        'unconfirmed producer text',
        copy: ReminderIssueCopy.notification(
          NotificationIssueNotice.oncePermissionUnconfirmed,
          titleCode: NotificationIssueTitle.taskRegistrationFailed,
          detail: diagnostic,
        ),
        includeTitle: true,
        rawTitle: 'raw unconfirmed title',
        rawMessage: 'raw unconfirmed message',
      ),
      const ReminderSyncIssueEntry('literal service detail; keep verbatim'),
      const ReminderSyncIssueEntry(
        'denied producer text',
        copy: ReminderIssueCopy.notification(
          NotificationIssueNotice.sendPermissionDenied,
        ),
        rawTitle: 'unused raw title',
        rawMessage: 'unused raw message',
      ),
    ]);

    expect(
      issue.raw,
      'unconfirmed producer text；literal service detail; keep verbatim；denied producer text',
    );
    expect(issue.entries.map((entry) => entry.raw).toList(), [
      'unconfirmed producer text',
      'literal service detail; keep verbatim',
      'denied producer text',
    ]);

    I18n.setLocale(AppLocale.en);
    expect(
      issue.render(locale: AppLocale.zh),
      '待办提醒状态需检查：系统通知权限未开启，提醒未确认注册成功。请开启通知权限后重新保存提醒。($diagnostic)；literal service detail; keep verbatim；系统通知权限未开启，通知未发送。请开启通知权限后重试。',
    );
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
    expect(
      issue.render(locale: AppLocale.en),
      'Check task reminder: Notifications are disabled, so reminder registration is unconfirmed. Enable notifications and save the reminder again.($diagnostic); literal service detail; keep verbatim; Notifications are disabled and the notification was not sent. Enable notifications and retry.',
    );
    expect(I18n.current, AppLocale.en);

    I18n.setLocale(AppLocale.zh);
    expect(
      issue.render(locale: AppLocale.en),
      contains('Check task reminder:'),
    );
    expect(I18n.current, AppLocale.zh);
  });

  test('typed title fallbacks retain custom and empty labels', () {
    const copy = ReminderIssueCopy.notification(
      NotificationIssueNotice.channelUnknown,
    );
    const customLabel = '自定义提醒标题 / Custom label';
    final custom = ReminderSyncIssueEntry(
      'raw diagnostic',
      copy: copy,
      includeTitle: true,
      rawTitle: customLabel,
      rawMessage: 'raw message fallback',
    );
    final empty = ReminderSyncIssueEntry(
      'raw diagnostic',
      copy: copy,
      includeTitle: true,
      rawTitle: '',
      rawMessage: 'raw message fallback',
    );

    expect(
      custom.render(locale: AppLocale.zh),
      '自定义提醒标题 / Custom label：普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
    );
    expect(
      custom.render(locale: AppLocale.en),
      '自定义提醒标题 / Custom label: The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
    );
    expect(
      empty.render(locale: AppLocale.zh),
      '：普通提醒渠道状态无法确认，提醒会继续注册，但到点显示或声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。',
    );
    expect(
      empty.render(locale: AppLocale.en),
      ': The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.',
    );
  });

  test(
    'entries without copy keep their raw text and literal factory order',
    () {
      const raw = 'opaque reminder service result / code=0xC1';
      const entry = ReminderSyncIssueEntry(raw);
      final issue = ReminderSyncIssue([
        entry,
        const ReminderSyncIssueEntry('next'),
      ]);
      final literal = ReminderSyncIssue.literal(raw);

      expect(entry.render(locale: AppLocale.zh), raw);
      expect(entry.render(locale: AppLocale.en), raw);
      expect(issue.raw, '$raw；next');
      expect(issue.render(locale: AppLocale.en), '$raw; next');
      expect(literal.raw, raw);
      expect(literal.entries, hasLength(1));
      expect(literal.render(locale: AppLocale.zh), raw);
    },
  );

  test('entry list is snapshotted and cannot be mutated through the issue', () {
    final source = <ReminderSyncIssueEntry>[
      const ReminderSyncIssueEntry('first'),
    ];
    final issue = ReminderSyncIssue(source);

    source.add(const ReminderSyncIssueEntry('added after snapshot'));

    expect(issue.entries, hasLength(1));
    expect(issue.entries.single.raw, 'first');
    expect(issue.raw, 'first');
    expect(
      () => issue.entries.add(const ReminderSyncIssueEntry('forbidden')),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('owned scheduler notices and rule details render bilingually', () {
    final expected = <ReminderSyncIssueNotice, (String, String)>{
      ReminderSyncIssueNotice.schedulerMissing: (
        '提醒服务暂不可用，请稍后重新保存提醒。',
        'The reminder service is unavailable. Save the reminder again later.',
      ),
      ReminderSyncIssueNotice.registrationUnconfirmed: (
        '提醒调度器未能确认规则已注册到系统',
        'The reminder scheduler could not confirm system registration.',
      ),
      ReminderSyncIssueNotice.pushNotRegistered: (
        '系统通知服务返回未注册',
        'The system notification service reported no registration.',
      ),
      ReminderSyncIssueNotice.repeatingPushNotRegistered: (
        '系统重复通知服务返回未注册',
        'The system notification service reported no repeating registration.',
      ),
      ReminderSyncIssueNotice.genericFailure: (
        '提醒未注册成功，请检查通知权限、提醒方式和提醒时间。',
        'The reminder was not registered. Check notification permission, reminder type and time.',
      ),
    };
    expect(
      expected.keys.toSet().union({ReminderSyncIssueNotice.ruleNotRegistered}),
      ReminderSyncIssueNotice.values.toSet(),
    );
    for (final entry in expected.entries) {
      final copy = ReminderSyncIssueEntry('raw', notice: entry.key);
      expect(copy.render(locale: AppLocale.zh), entry.value.$1);
      expect(copy.render(locale: AppLocale.en), entry.value.$2);
    }

    const rule = ReminderSyncIssueEntry(
      'raw rule failure',
      notice: ReminderSyncIssueNotice.ruleNotRegistered,
      kind: ReminderKind.push,
      object: ReminderSyncObject.task,
      target: 'Project Aurora / Q4',
    );
    expect(
      rule.render(locale: AppLocale.zh),
      '待办提醒注册失败：“Project Aurora / Q4” 的普通通知未注册成功。请检查系统通知权限和通知渠道。',
    );
    expect(
      rule.render(locale: AppLocale.en),
      'Task reminder not registered: “Project Aurora / Q4”: notification reminder not registered. Check notification permission and channels.',
    );
  });

  test('rule-not-registered copy covers every kind and object', () {
    final objectTitles = <ReminderSyncObject, (String, String)>{
      ReminderSyncObject.task: ('待办提醒注册失败', 'Task reminder not registered'),
      ReminderSyncObject.goal: ('目标提醒注册失败', 'Goal reminder not registered'),
      ReminderSyncObject.reminder: ('提醒注册失败', 'Reminder not registered'),
    };
    final kindCopy = <ReminderKind, (String, String, String, String)>{
      ReminderKind.popup: (
        '弹出提醒',
        'pop-up reminder',
        '请保持应用前台运行，或开启系统通知权限以便后台兜底。',
        'Keep the app in the foreground, or enable notifications for the background fallback.',
      ),
      ReminderKind.alarm: (
        '闹钟提醒',
        'alarm reminder',
        '请检查通知权限、精准闹钟权限、全屏提醒权限和强提醒渠道。',
        'Check notification, exact alarm and full-screen permissions, and the strong alert channel.',
      ),
      ReminderKind.push: (
        '普通通知',
        'notification reminder',
        '请检查系统通知权限和通知渠道。',
        'Check notification permission and channels.',
      ),
      ReminderKind.email: (
        '邮件提醒',
        'email reminder',
        '请检查邮件提醒服务配置。',
        'Check the email reminder service configuration.',
      ),
      ReminderKind.off: (
        '关闭',
        'disabled reminder',
        '请重新启用提醒方式。',
        'Enable a reminder type again.',
      ),
    };
    expect(objectTitles.keys.toSet(), ReminderSyncObject.values.toSet());
    expect(kindCopy.keys.toSet(), ReminderKind.values.toSet());

    const target = '  Aurora / Q4  ';
    for (final object in ReminderSyncObject.values) {
      final (titleZh, titleEn) = objectTitles[object]!;
      for (final kind in ReminderKind.values) {
        final (channelZh, channelEn, hintZh, hintEn) = kindCopy[kind]!;
        final entry = ReminderSyncIssueEntry(
          'raw rule failure',
          notice: ReminderSyncIssueNotice.ruleNotRegistered,
          kind: kind,
          object: object,
          target: target,
        );
        expect(
          entry.render(locale: AppLocale.zh),
          '$titleZh：“  Aurora / Q4  ” 的$channelZh未注册成功。$hintZh',
          reason: '${object.name} / ${kind.name} Chinese rule copy',
        );
        expect(
          entry.render(locale: AppLocale.en),
          '$titleEn: “  Aurora / Q4  ”: $channelEn not registered. $hintEn',
          reason: '${object.name} / ${kind.name} English rule copy',
        );
      }
    }

    const whitespaceTarget = ' \t  \n';
    const fallbackTarget = ReminderSyncIssueEntry(
      'raw rule failure',
      notice: ReminderSyncIssueNotice.ruleNotRegistered,
      kind: ReminderKind.off,
      object: ReminderSyncObject.goal,
      target: whitespaceTarget,
    );
    expect(
      fallbackTarget.render(locale: AppLocale.zh),
      '目标提醒注册失败：该提醒 的关闭未注册成功。请重新启用提醒方式。',
    );
    expect(
      fallbackTarget.render(locale: AppLocale.en),
      'Goal reminder not registered: This reminder: disabled reminder not registered. Enable a reminder type again.',
    );
  });

  test('typed issueResult error is handled without a raw projection', () async {
    final issue = ReminderSyncIssue.literal('raw scheduler result');
    final success = ReminderTodoFailureFuture(Future.value(issue));
    expect(await success.issueResult, same(issue));

    final source = Completer<ReminderSyncIssue?>();
    final failed = ReminderTodoFailureFuture(source.future);
    final handled = expectLater(failed.issueResult, throwsA(isA<StateError>()));
    source.completeError(StateError('typed result failed'), StackTrace.current);
    await handled;
  });

  test(
    'legacy Future forwards catchError predicates and then onError',
    () async {
      final catchSource = Completer<ReminderSyncIssue?>();
      final catchFuture = ReminderTodoFailureFuture(catchSource.future);
      final caught = catchFuture.catchError(
        (Object error) => 'caught: ${error.runtimeType}',
        test: (Object error) => error is StateError,
      );
      catchSource.completeError(StateError('handled by catchError'));
      expect(await caught, 'caught: StateError');

      final rejectedSource = Completer<ReminderSyncIssue?>();
      final rejectedFuture = ReminderTodoFailureFuture(rejectedSource.future);
      final notCaught = rejectedFuture.catchError(
        (Object error) => 'unexpected match',
        test: (Object error) => error is StateError,
      );
      rejectedSource.completeError(ArgumentError('predicate did not match'));
      await expectLater(notCaught, throwsA(isA<ArgumentError>()));

      final thenSource = Completer<ReminderSyncIssue?>();
      final thenFuture = ReminderTodoFailureFuture(thenSource.future);
      final handledByThen = thenFuture.then<String>(
        (_) => 'unexpected success',
        onError: (Object error, StackTrace stack) =>
            'handled by then: ${error.runtimeType}',
      );
      thenSource.completeError(StateError('handled by then'));
      expect(await handledByThen, 'handled by then: StateError');
    },
  );

  test('timeout result is followed by the same operation completion', () async {
    final source = Completer<ReminderSyncIssue?>();
    final future = ReminderTodoFailureFuture(source.future);

    expect(
      await future.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => 'custom timeout result',
      ),
      'custom timeout result',
    );

    source.complete(ReminderSyncIssue.literal('operation completed later'));
    expect(await future.then((raw) => raw), 'operation completed later');
  });

  test('legacy Future forwards whenComplete and asStream', () async {
    final issue = ReminderSyncIssue.literal('projected raw result');
    final future = ReminderTodoFailureFuture(Future.value(issue));
    var completionCount = 0;

    expect(await future.whenComplete(() => completionCount++), issue.raw);
    expect(completionCount, 1);
    expect(await future.asStream().toList(), [issue.raw]);
  });
}
