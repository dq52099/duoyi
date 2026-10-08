import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/widget_action_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('every widget action notice has distinct non-empty bilingual copy', () {
    for (final notice in WidgetActionNotice.values) {
      final message = WidgetActionMessage(notice);
      final zh = message.render(locale: AppLocale.zh);
      final en = message.render(locale: AppLocale.en);

      expect(zh.trim(), isNotEmpty, reason: '${notice.name} Chinese copy');
      expect(en.trim(), isNotEmpty, reason: '${notice.name} English copy');
      expect(zh, isNot(en), reason: notice.name);
      expect(
        en,
        isNot(contains(RegExp(r'[\u3400-\u9fff]'))),
        reason: notice.name,
      );
    }
  });

  test('task and habit names remain literal message parameters', () {
    const subject = '项目 “Aurora” / Q4 🧭';
    final messages = <WidgetActionMessage>[
      WidgetActionMessage(
        WidgetActionNotice.todoAlreadyCompleted,
        subject: subject,
      ),
      WidgetActionMessage(
        WidgetActionNotice.habitNotScheduled,
        subject: subject,
      ),
      WidgetActionMessage(
        WidgetActionNotice.habitAlreadyCompleted,
        subject: subject,
      ),
      WidgetActionMessage(WidgetActionNotice.habitCheckedIn, subject: subject),
      WidgetActionMessage(WidgetActionNotice.todoCompleted, subject: subject),
    ];

    for (final message in messages) {
      for (final locale in AppLocale.values) {
        expect(message.render(locale: locale), contains(subject));
      }
      expect(message.subject, subject);
    }
  });

  test(
    'reminder service title, issue text, and custom issue title are retained',
    () {
      const serviceTitle = 'Reminder service “Night Shift”';
      const issueText = '锁屏闹钟注册状态未确认；permission denied (code 0x17)\n更多详情';
      final issue = WidgetActionMessage(
        WidgetActionNotice.reminderIssue,
        subject: serviceTitle,
        detail: issueText,
      );

      expect(
        issue.render(locale: AppLocale.zh),
        '提醒状态需检查：$serviceTitle：$issueText',
      );
      expect(
        issue.render(locale: AppLocale.en),
        'Reminder status needs attention: $serviceTitle: $issueText',
      );
      expect(issue.subject, serviceTitle);
      expect(issue.detail, issueText);
      final savedWarning = WidgetActionMessage(
        WidgetActionNotice.savedReminderIssue,
        detail: issueText,
      );
      for (final locale in AppLocale.values) {
        expect(savedWarning.render(locale: locale), contains(issueText));
      }
      expect(
        savedWarning.render(locale: AppLocale.en),
        startsWith('Task saved on this device. Check reminder status: '),
      );

      const customIssueTitle = 'Custom reminder title';
      for (final notice in <WidgetActionNotice>[
        WidgetActionNotice.reminderConfigurationInvalid,
        WidgetActionNotice.reminderNotRegistered,
        WidgetActionNotice.alarmPermissionDenied,
      ]) {
        final message = WidgetActionMessage(
          notice,
          issueTitle: customIssueTitle,
        );
        expect(
          message.render(locale: AppLocale.zh),
          contains(customIssueTitle),
        );
        expect(
          message.render(locale: AppLocale.en),
          contains(customIssueTitle),
        );
        expect(message.issueTitle, customIssueTitle);
        final emptyTitle = WidgetActionMessage(notice, issueTitle: '');
        expect(emptyTitle.render(locale: AppLocale.en), startsWith(':'));
        expect(emptyTitle.render(locale: AppLocale.zh), startsWith('：'));
        final defaultTitle = WidgetActionMessage(notice);
        expect(
          defaultTitle.render(locale: AppLocale.en),
          startsWith('Task reminder not registered:'),
        );
      }
    },
  );

  test('sync facts honor precedence and preserve all nine states', () {
    WidgetActionSyncStatus fromFacts({
      bool enabled = true,
      bool accountTransition = false,
      bool authenticated = true,
      bool serverDisabled = false,
      bool autoSync = true,
      bool retryPending = false,
      bool pendingChanges = false,
      String? retryReason,
      String? lastError,
    }) => WidgetActionSyncStatus.fromFacts(
      enabled: enabled,
      accountTransition: accountTransition,
      authenticated: authenticated,
      serverDisabled: serverDisabled,
      autoSync: autoSync,
      retryPending: retryPending,
      pendingChanges: pendingChanges,
      retryReason: retryReason,
      lastError: lastError,
    );

    const retryReason = 'retry token: retained verbatim';
    const failureReason = 'server reason: retained verbatim';
    final statuses = <WidgetActionSyncState, WidgetActionSyncStatus>{
      WidgetActionSyncState.unknown: const WidgetActionSyncStatus(
        WidgetActionSyncState.unknown,
      ),
      WidgetActionSyncState.disabled: fromFacts(
        enabled: false,
        accountTransition: true,
        authenticated: false,
        serverDisabled: true,
        autoSync: false,
        retryPending: true,
        pendingChanges: true,
        lastError: failureReason,
      ),
      WidgetActionSyncState.accountTransition: fromFacts(
        accountTransition: true,
        authenticated: false,
        serverDisabled: true,
        autoSync: false,
        retryPending: true,
        pendingChanges: true,
        lastError: failureReason,
      ),
      WidgetActionSyncState.signedOut: fromFacts(
        authenticated: false,
        serverDisabled: true,
        autoSync: false,
        retryPending: true,
        pendingChanges: true,
        lastError: failureReason,
      ),
      WidgetActionSyncState.serverDisabled: fromFacts(
        serverDisabled: true,
        autoSync: false,
        retryPending: true,
        pendingChanges: true,
        lastError: failureReason,
      ),
      WidgetActionSyncState.autoSyncOff: fromFacts(
        autoSync: false,
        retryPending: true,
        pendingChanges: true,
        lastError: failureReason,
      ),
      WidgetActionSyncState.retryPending: fromFacts(
        retryPending: true,
        pendingChanges: true,
        retryReason: retryReason,
        lastError: failureReason,
      ),
      WidgetActionSyncState.failed: fromFacts(
        pendingChanges: true,
        lastError: failureReason,
      ),
      WidgetActionSyncState.backgroundUpload: fromFacts(
        pendingChanges: false,
        lastError: failureReason,
      ),
    };
    const englishStatus = <WidgetActionSyncState, String>{
      WidgetActionSyncState.unknown: 'Cloud sync status is unconfirmed',
      WidgetActionSyncState.disabled:
          'Not uploaded: cloud sync is disabled in this version.',
      WidgetActionSyncState.accountTransition:
          'Not uploaded: cloud sync is paused while switching accounts.',
      WidgetActionSyncState.signedOut:
          'Not uploaded: no cloud sync account is signed in.',
      WidgetActionSyncState.serverDisabled:
          'Not uploaded: cloud backup is disabled by the administrator.',
      WidgetActionSyncState.autoSyncOff:
          'Not uploaded: automatic sync is off. Enable it to resume syncing.',
      WidgetActionSyncState.retryPending:
          'Cloud sync is incomplete and will retry automatically.',
      WidgetActionSyncState.failed:
          'Cloud sync failed and will retry automatically',
      WidgetActionSyncState.backgroundUpload:
          'Cloud sync will upload in the background',
    };

    expect(statuses.keys.toSet(), WidgetActionSyncState.values.toSet());
    for (final state in WidgetActionSyncState.values) {
      final status = statuses[state]!;
      expect(status.state, state);
      final message = WidgetActionMessage(
        WidgetActionNotice.todoSaved,
        syncState: status.state,
        syncReason: status.reason,
      );
      final zh = message.render(locale: AppLocale.zh);
      final en = message.render(locale: AppLocale.en);
      expect(zh, contains('待办已保存到本机'), reason: state.name);
      expect(en, contains('Task saved on this device'), reason: state.name);
      expect(en, contains(englishStatus[state]!), reason: state.name);
      expect(zh, isNot(en), reason: state.name);
    }

    expect(statuses[WidgetActionSyncState.retryPending]!.reason, retryReason);
    expect(statuses[WidgetActionSyncState.failed]!.reason, failureReason);
    expect(
      WidgetActionMessage(
        WidgetActionNotice.todoSaved,
        syncState: WidgetActionSyncState.retryPending,
        syncReason: statuses[WidgetActionSyncState.retryPending]!.reason,
      ).render(locale: AppLocale.en),
      contains(retryReason),
    );
    expect(
      WidgetActionMessage(
        WidgetActionNotice.todoSaved,
        syncState: WidgetActionSyncState.failed,
        syncReason: statuses[WidgetActionSyncState.failed]!.reason,
      ).render(locale: AppLocale.en),
      contains(failureReason),
    );
    expect(
      fromFacts(pendingChanges: true, lastError: ' \n\t ').state,
      WidgetActionSyncState.backgroundUpload,
      reason: 'blank errors do not produce a failed state',
    );
    expect(
      fromFacts(pendingChanges: false, lastError: failureReason).state,
      WidgetActionSyncState.backgroundUpload,
      reason:
          'an error without pending changes does not produce a failed state',
    );
    for (final emptyReason in <String?>[null, '', ' \n\t ']) {
      expect(
        fromFacts(
          retryPending: true,
          retryReason: emptyReason,
          pendingChanges: true,
          lastError: failureReason,
        ).state,
        WidgetActionSyncState.failed,
        reason: 'an empty retry message must allow pending errors to surface',
      );
      expect(
        fromFacts(retryPending: true, retryReason: emptyReason).state,
        WidgetActionSyncState.backgroundUpload,
        reason: 'an empty retry message falls through like the provider',
      );
    }
  });

  test('saved todo reminder hints cover none, settings, and details', () {
    final hints = <WidgetActionReminderHint, (String, String)>{
      WidgetActionReminderHint.none: ('', ''),
      WidgetActionReminderHint.settings: (
        '；提醒状态可在通知设置/待办详情检查',
        '; check reminder status in Notification Settings or task details',
      ),
      WidgetActionReminderHint.details: (
        '；提醒状态可在待办详情中检查',
        '; check reminder status in task details',
      ),
    };

    for (final entry in hints.entries) {
      final message = WidgetActionMessage(
        WidgetActionNotice.todoSaved,
        reminderHint: entry.key,
      );
      final zh = message.render(locale: AppLocale.zh);
      final en = message.render(locale: AppLocale.en);
      if (entry.key == WidgetActionReminderHint.none) {
        expect(zh, isNot(contains('提醒状态')));
        expect(en, isNot(contains('check reminder status')));
      } else {
        expect(zh, contains(entry.value.$1));
        expect(en, contains(entry.value.$2));
      }
    }
  });

  test('rendering an explicit locale does not change I18n global locale', () {
    I18n.setLocale(AppLocale.en);
    final message = WidgetActionMessage(WidgetActionNotice.quickTodoFailed);

    expect(message.render(locale: AppLocale.zh), '快捷待办创建失败，请稍后重试');
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
    expect(
      message.render(locale: AppLocale.en),
      'Could not create the task. Please try again',
    );
    expect(I18n.current, AppLocale.en);
    expect(I18n.localeListenable.value, AppLocale.en);
  });
}
