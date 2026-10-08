import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart'
    show TodoReminderPreflightIssue;
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:duoyi/services/reminder_sync_issue.dart';
import 'package:duoyi/services/todo_reminder_preflight_copy.dart';
import 'package:duoyi/services/widget_action_message.dart';
import 'package:duoyi/services/widget_action_scope.dart';
import 'package:duoyi/services/widget_quick_todo_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'a delayed preflight failure renders the locale selected before feedback',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      final enteredPreflight = Completer<void>();
      final releasePreflight = Completer<bool>();
      final feedbackQueued = Completer<WidgetActionMessage>();
      var createCalls = 0;

      final pending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: feedbackQueued,
        preflight: (showFeedback) {
          enteredPreflight.complete();
          return releasePreflight.future.then((ready) {
            if (!ready) {
              showFeedback(
                const WidgetActionMessage(
                  WidgetActionNotice.reminderNotRegistered,
                ),
              );
            }
            return ready;
          });
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );

      await enteredPreflight.future;
      I18n.setLocale(AppLocale.en);
      releasePreflight.complete(false);
      final delivered = await feedbackQueued.future;
      await pending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(createCalls, 0);
      expect(delivered.notice, WidgetActionNotice.reminderNotRegistered);
      expect(find.text(delivered.render(locale: AppLocale.en)), findsOneWidget);
    },
  );

  testWidgets(
    'a delayed successful create renders locale changed after frame scheduling',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      final enteredCreate = Completer<void>();
      final releaseCreate = Completer<WidgetActionMessage>();
      final feedbackQueued = Completer<WidgetActionMessage>();
      const created = WidgetActionMessage(
        WidgetActionNotice.todoCompleted,
        subject: 'Created after permission check',
      );

      final pending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: feedbackQueued,
        preflight: (_) async => true,
        create: () {
          enteredCreate.complete();
          return releaseCreate.future;
        },
      );

      await enteredCreate.future;
      I18n.setLocale(AppLocale.en);
      releaseCreate.complete(created);
      final delivered = await feedbackQueued.future;
      I18n.setLocale(AppLocale.zh);
      await pending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(delivered, same(created));
      expect(find.text(delivered.render(locale: AppLocale.zh)), findsOneWidget);
      expect(find.text(delivered.render(locale: AppLocale.en)), findsNothing);
    },
  );

  testWidgets('a delayed create failure is localized at delivery time', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await _pumpMessenger(tester, messengerKey);
    final enteredCreate = Completer<void>();
    final releaseCreate = Completer<WidgetActionMessage>();
    final feedbackQueued = Completer<WidgetActionMessage>();

    final pending = _runAction(
      messengerKey: messengerKey,
      feedbackQueued: feedbackQueued,
      preflight: (_) async => true,
      create: () {
        enteredCreate.complete();
        return releaseCreate.future;
      },
    );

    await enteredCreate.future;
    I18n.setLocale(AppLocale.en);
    releaseCreate.completeError(
      StateError('create failed after the account-local save'),
      StackTrace.current,
    );
    final delivered = await feedbackQueued.future;
    I18n.setLocale(AppLocale.zh);
    await pending;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(delivered.notice, WidgetActionNotice.quickTodoFailed);
    expect(find.text(delivered.render(locale: AppLocale.zh)), findsOneWidget);
    expect(find.text(delivered.render(locale: AppLocale.en)), findsNothing);
  });

  testWidgets('an account switch suppresses A feedback and delivers B', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await _pumpMessenger(tester, messengerKey);
    I18n.setLocale(AppLocale.en);
    final accountAQueued = Completer<WidgetActionMessage>();
    const accountAMessage = WidgetActionMessage(
      WidgetActionNotice.todoCompleted,
      subject: 'Account A task',
    );

    final accountAPending = _runAction(
      messengerKey: messengerKey,
      feedbackQueued: accountAQueued,
      preflight: (_) async => true,
      create: () async => accountAMessage,
    );
    await accountAQueued.future;
    await accountAPending;

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    const accountBMessage = WidgetActionMessage(
      WidgetActionNotice.todoCompleted,
      subject: 'Account B task',
    );
    final accountBQueued = Completer<WidgetActionMessage>();
    final accountBPending = _runAction(
      messengerKey: messengerKey,
      feedbackQueued: accountBQueued,
      preflight: (_) async => true,
      create: () async => accountBMessage,
    );
    await accountBQueued.future;
    await accountBPending;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text(accountAMessage.render(locale: AppLocale.en)),
      findsNothing,
    );
    expect(
      find.text(accountBMessage.render(locale: AppLocale.en)),
      findsOneWidget,
    );
  });

  testWidgets('a stable guest action delivers its successful descriptor', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await _pumpMessenger(tester, messengerKey);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final enteredPreflight = Completer<void>();
    final releasePreflight = Completer<bool>();
    final enteredCreate = Completer<void>();
    final releaseCreate = Completer<WidgetActionMessage>();
    final feedbackQueued = Completer<WidgetActionMessage>();
    const guestMessage = WidgetActionMessage(
      WidgetActionNotice.todoSaved,
      syncState: WidgetActionSyncState.signedOut,
    );

    final pending = _runAction(
      messengerKey: messengerKey,
      feedbackQueued: feedbackQueued,
      preflight: (_) {
        enteredPreflight.complete();
        return releasePreflight.future;
      },
      create: () {
        enteredCreate.complete();
        return releaseCreate.future;
      },
    );

    await enteredPreflight.future;
    releasePreflight.complete(true);
    await enteredCreate.future;
    releaseCreate.complete(guestMessage);
    final delivered = await feedbackQueued.future;
    await pending;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      AccountLocalDataCleaner.accountDataGeneration,
      generation,
      reason: 'a guest action does not need an account transition',
    );
    expect(delivered, same(guestMessage));
    expect(
      find.text(guestMessage.render(locale: AppLocale.zh)),
      findsOneWidget,
    );
  });

  testWidgets('typed preflight feedback localizes after a delayed failure', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await _pumpMessenger(tester, messengerKey);
    final enteredPreflight = Completer<void>();
    final releasePreflight = Completer<void>();
    final feedbackQueued = Completer<WidgetActionMessage>();
    var createCalls = 0;
    final issue = TodoReminderPreflightIssue.coded(
      TodoReminderPreflightNotice.invalidWeeklyRule,
    );
    final descriptor = WidgetActionMessage(
      WidgetActionNotice.reminderIssue,
      subject: issue.title,
      detail: issue.message,
      preflightCopy: issue.copy,
    );

    final pending = _runAction(
      messengerKey: messengerKey,
      feedbackQueued: feedbackQueued,
      preflight: (showFeedback) {
        enteredPreflight.complete();
        return releasePreflight.future.then((_) {
          showFeedback(descriptor);
          return false;
        });
      },
      create: () async {
        createCalls++;
        return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
      },
    );

    await enteredPreflight.future;
    I18n.setLocale(AppLocale.en);
    releasePreflight.complete();
    final delivered = await feedbackQueued.future;
    await pending;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(createCalls, 0);
    expect(delivered, same(descriptor));
    expect(delivered.subject, issue.title);
    expect(delivered.detail, issue.message);
    expect(find.text(descriptor.render(locale: AppLocale.en)), findsOneWidget);
  });

  testWidgets(
    'account A typed preflight descriptor is suppressed while B is current',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      I18n.setLocale(AppLocale.en);
      var createCalls = 0;

      WidgetActionMessage descriptorFor(TodoReminderPreflightIssue issue) =>
          WidgetActionMessage(
            WidgetActionNotice.reminderIssue,
            subject: issue.title,
            detail: issue.message,
            preflightCopy: issue.copy,
          );

      final accountAIssue = TodoReminderPreflightIssue.coded(
        TodoReminderPreflightNotice.missingDate,
      );
      final accountAMessage = descriptorFor(accountAIssue);
      final accountAQueued = Completer<WidgetActionMessage>();
      final accountAPending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: accountAQueued,
        preflight: (showFeedback) async {
          showFeedback(accountAMessage);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );
      await accountAQueued.future;
      await accountAPending;

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      final accountBIssue = TodoReminderPreflightIssue.coded(
        TodoReminderPreflightNotice.timeInPast,
      );
      final accountBMessage = descriptorFor(accountBIssue);
      final accountBQueued = Completer<WidgetActionMessage>();
      final accountBPending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: accountBQueued,
        preflight: (showFeedback) async {
          showFeedback(accountBMessage);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );
      await accountBQueued.future;
      await accountBPending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(createCalls, 0);
      expect(
        find.text(accountAMessage.render(locale: AppLocale.en)),
        findsNothing,
      );
      expect(
        find.text(accountBMessage.render(locale: AppLocale.en)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'typed notification issue renders the locale selected after feedback is queued',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      const diagnostic = 'POST_NOTIFICATIONS 未授权 / platform result=0xD3';
      final descriptor = WidgetActionMessage(
        WidgetActionNotice.reminderIssue,
        subject: '待办提醒注册失败',
        detail: diagnostic,
        issueCopy: const ReminderIssueCopy.notification(
          NotificationIssueNotice.oncePermissionUnconfirmed,
          titleCode: NotificationIssueTitle.taskRegistrationFailed,
          detail: diagnostic,
        ),
      );
      final feedbackQueued = Completer<WidgetActionMessage>();
      var createCalls = 0;

      final pending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: feedbackQueued,
        preflight: (showFeedback) async {
          showFeedback(descriptor);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );

      final delivered = await feedbackQueued.future;
      I18n.setLocale(AppLocale.en);
      await pending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(createCalls, 0);
      expect(delivered, same(descriptor));
      expect(
        find.text(
          'Reminder status needs attention: Check task reminder: Notifications are disabled, so reminder registration is unconfirmed. Enable notifications and save the reminder again.($diagnostic)',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'account A typed notification issue is suppressed while B is current',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      I18n.setLocale(AppLocale.en);
      var createCalls = 0;

      WidgetActionMessage notificationIssue(String detail) =>
          WidgetActionMessage(
            WidgetActionNotice.reminderIssue,
            subject: '待办提醒注册失败',
            detail: detail,
            issueCopy: ReminderIssueCopy.notification(
              NotificationIssueNotice.channelProbeFailed,
              titleCode: NotificationIssueTitle.taskRegistrationFailed,
              detail: detail,
            ),
          );

      final accountAMessage = notificationIssue(
        '渠道查询异常 / account A diagnostic',
      );
      final accountAQueued = Completer<WidgetActionMessage>();
      final accountAPending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: accountAQueued,
        preflight: (showFeedback) async {
          showFeedback(accountAMessage);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );
      await accountAQueued.future;
      await accountAPending;

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      final accountBMessage = notificationIssue(
        '渠道查询异常 / account B diagnostic',
      );
      final accountBQueued = Completer<WidgetActionMessage>();
      final accountBPending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: accountBQueued,
        preflight: (showFeedback) async {
          showFeedback(accountBMessage);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );
      await accountBQueued.future;
      await accountBPending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(createCalls, 0);
      expect(
        find.text(accountAMessage.render(locale: AppLocale.en)),
        findsNothing,
      );
      expect(
        find.text(accountBMessage.render(locale: AppLocale.en)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'saved reminder sync issue uses the locale selected before frame delivery',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      const diagnostic = 'channel probe failed / 渠道状态=未知';
      final syncIssue = ReminderSyncIssue([
        const ReminderSyncIssueEntry(
          'legacy channel warning',
          copy: ReminderIssueCopy.notification(
            NotificationIssueNotice.channelProbeFailed,
            titleCode: NotificationIssueTitle.taskRegistrationFailed,
            detail: diagnostic,
          ),
          includeTitle: true,
          rawTitle: '待办提醒注册失败',
          rawMessage: 'legacy warning message',
        ),
        const ReminderSyncIssueEntry('opaque scheduler log: item=17'),
      ]);
      final descriptor = WidgetActionMessage(
        WidgetActionNotice.savedReminderIssue,
        detail: 'legacy detail should not replace the typed issue',
        syncIssueCopy: syncIssue,
      );
      final feedbackQueued = Completer<WidgetActionMessage>();
      final pending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: feedbackQueued,
        preflight: (_) async => true,
        create: () async => descriptor,
      );

      final delivered = await feedbackQueued.future;
      I18n.setLocale(AppLocale.en);
      await pending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(delivered, same(descriptor));
      expect(
        find.text(
          'Task saved on this device. Check reminder status: Check task reminder: The regular reminder channel could not be verified. Registration will continue, but system settings may affect display or sound. Check system notification settings, then save the reminder again.($diagnostic); opaque scheduler log: item=17',
        ),
        findsOneWidget,
      );
      const legacy = WidgetActionMessage(
        WidgetActionNotice.savedReminderIssue,
        detail: '自定义原始诊断 / keep verbatim',
      );
      expect(
        legacy.render(locale: AppLocale.en),
        'Task saved on this device. Check reminder status: 自定义原始诊断 / keep verbatim',
      );
    },
  );

  testWidgets(
    'account A saved reminder sync feedback is suppressed while B is current',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await _pumpMessenger(tester, messengerKey);
      I18n.setLocale(AppLocale.en);
      var createCalls = 0;

      WidgetActionMessage descriptorFor(String account) => WidgetActionMessage(
        WidgetActionNotice.savedReminderIssue,
        detail: 'legacy detail for $account',
        syncIssueCopy: ReminderSyncIssue.literal(
          'scheduler sync diagnostic for $account',
        ),
      );

      final accountAMessage = descriptorFor('account A');
      final accountAQueued = Completer<WidgetActionMessage>();
      final accountAPending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: accountAQueued,
        preflight: (showFeedback) async {
          showFeedback(accountAMessage);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );
      await accountAQueued.future;
      await accountAPending;

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      final accountBMessage = descriptorFor('account B');
      final accountBQueued = Completer<WidgetActionMessage>();
      final accountBPending = _runAction(
        messengerKey: messengerKey,
        feedbackQueued: accountBQueued,
        preflight: (showFeedback) async {
          showFeedback(accountBMessage);
          return false;
        },
        create: () async {
          createCalls++;
          return const WidgetActionMessage(WidgetActionNotice.todoCompleted);
        },
      );
      await accountBQueued.future;
      await accountBPending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(createCalls, 0);
      expect(
        find.text(accountAMessage.render(locale: AppLocale.en)),
        findsNothing,
      );
      expect(
        find.text(accountBMessage.render(locale: AppLocale.en)),
        findsOneWidget,
      );
    },
  );
}

Future<void> _pumpMessenger(
  WidgetTester tester,
  GlobalKey<ScaffoldMessengerState> messengerKey,
) async {
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: messengerKey,
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
}

Future<void> _runAction({
  required GlobalKey<ScaffoldMessengerState> messengerKey,
  required Completer<WidgetActionMessage> feedbackQueued,
  required Future<bool> Function(void Function(WidgetActionMessage)) preflight,
  required Future<WidgetActionMessage> Function() create,
}) => runWidgetQuickTodoAction<WidgetActionMessage>(
  isCallerAvailable: () => true,
  preflight: preflight,
  create: create,
  feedback: (message, isCurrent) {
    WidgetActionScope(isCallerAvailable: isCurrent).afterFrame(() {
      messengerKey.currentState!
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message.render()),
            duration: const Duration(minutes: 1),
          ),
        );
    });
    feedbackQueued.complete(message);
  },
  failureMessage: const WidgetActionMessage(WidgetActionNotice.quickTodoFailed),
);
