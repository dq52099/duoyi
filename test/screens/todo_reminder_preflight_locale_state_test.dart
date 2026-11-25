import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_detail_ui_copy.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/notification_permission_exception.dart';
import 'package:duoyi/services/reminder_issue_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'failure fallback follows zh to en to zh while readiness is awaited once',
    (tester) async {
      final service = _ControlledNotificationService();
      addTearDown(service.dispose);
      final todo = _todoWithDailyPushReminder();
      late BuildContext context;
      late Future<bool> operation;
      var saveRequests = 0;
      var saveCalls = 0;

      await tester.pumpWidget(
        _contextApp(
          onBuild: (value) => context = value,
          childBuilder: (value) => ElevatedButton(
            key: const ValueKey<String>('run-preflight'),
            onPressed: () {
              saveRequests++;
              operation =
                  preflightTodoReminderSave(
                    value,
                    todo: todo,
                    notificationService: service,
                    issueTitle: 'Literal reminder title',
                  ).then((ready) {
                    if (ready) saveCalls++;
                    return ready;
                  });
            },
            child: const Text('Save'),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('run-preflight')));
      await tester.pump();
      expect(context.mounted, isTrue);
      expect(service.clearCalls, 1);
      expect(service.readinessCalls, 1);
      expect(service.requestedIssueTitle, 'Literal reminder title');
      expect(service.requestedRelatedId, todo.id);
      expect(saveRequests, 1);
      expect(saveCalls, 0);

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(service.clearCalls, 1);
      expect(service.readinessCalls, 1);

      service.readiness.complete(false);
      expect(await operation, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final chinese = TodoDetailUiCopy.reminderPreflightUnregistered(
        'Literal reminder title',
      );
      expect(find.text(chinese), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final english = TodoDetailUiCopy.reminderPreflightUnregistered(
        'Literal reminder title',
      );
      expect(english, isNot(chinese));
      expect(find.text(english), findsOneWidget);
      expect(find.text(chinese), findsNothing);

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(chinese), findsOneWidget);
      expect(saveRequests, 1);
      expect(saveCalls, 0);
      expect(service.clearCalls, 1);
      expect(service.readinessCalls, 1);
    },
  );

  testWidgets(
    'a no-copy issue keeps app-owned-looking Chinese text literal across locales',
    (tester) async {
      const rawTitle = '提醒注册初始化失败';
      const rawMessage = '系统通知初始化失败，提醒暂时无法注册。原始平台诊断 0xA7';
      final issue = NotificationScheduleIssue(
        title: rawTitle,
        message: rawMessage,
        happenedAt: DateTime.utc(2026, 10, 11),
        relatedId: 'preflight-todo',
      );
      final service = _ControlledNotificationService(issueOnFailure: issue);
      addTearDown(service.dispose);
      final todo = _todoWithDailyPushReminder();
      late BuildContext context;

      await tester.pumpWidget(
        _contextApp(
          onBuild: (value) => context = value,
          childBuilder: (_) => const SizedBox.shrink(),
        ),
      );

      final operation = preflightTodoReminderSave(
        context,
        todo: todo,
        notificationService: service,
        issueTitle: 'Fallback title not shown for a recorded issue',
      );
      await tester.pump();
      service.readiness.complete(false);
      expect(await operation, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(issue.copy, isNull);
      expect(issue.title, rawTitle);
      expect(issue.message, rawMessage);
      expect(find.textContaining(rawTitle), findsOneWidget);
      expect(find.textContaining(rawMessage), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.textContaining(rawTitle), findsOneWidget);
      expect(find.textContaining(rawMessage), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.textContaining(rawTitle), findsOneWidget);
      expect(find.textContaining(rawMessage), findsOneWidget);
      expect(service.clearCalls, 1);
      expect(service.readinessCalls, 1);
    },
  );

  testWidgets(
    'typed issue copy updates visible title and message while raw fields stay intact',
    (tester) async {
      const rawTitle = '提醒注册初始化失败';
      const rawMessage = '系统通知初始化失败。原始平台诊断 0xA7';
      const detail = 'native scheduler diagnostic 0xA7';
      final issue = NotificationScheduleIssue(
        title: rawTitle,
        message: rawMessage,
        happenedAt: DateTime.utc(2026, 10, 11),
        relatedId: 'preflight-todo',
        copy: const ReminderIssueCopy.notification(
          NotificationIssueNotice.initializationFailed,
          titleCode: NotificationIssueTitle.initializationFailed,
          detail: detail,
        ),
      );
      final service = _ControlledNotificationService(issueOnFailure: issue);
      addTearDown(service.dispose);
      late BuildContext context;

      await tester.pumpWidget(
        _contextApp(
          onBuild: (value) => context = value,
          childBuilder: (_) => const SizedBox.shrink(),
        ),
      );

      final operation = preflightTodoReminderSave(
        context,
        todo: _todoWithDailyPushReminder(),
        notificationService: service,
        issueTitle: 'Fallback title not shown for a typed issue',
      );
      await tester.pump();
      service.readiness.complete(false);
      expect(await operation, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Regression expectation for the production consumer: use the typed
      // projection while retaining raw diagnostics on the issue object.
      final chineseTitle = issue.renderTitle(locale: AppLocale.zh);
      final chineseMessage = issue.renderMessage(locale: AppLocale.zh);
      expect(find.textContaining(chineseTitle), findsOneWidget);
      expect(find.textContaining(chineseMessage), findsOneWidget);
      expect(chineseMessage, contains(detail));

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      final englishTitle = issue.renderTitle(locale: AppLocale.en);
      final englishMessage = issue.renderMessage(locale: AppLocale.en);
      expect(englishTitle, isNot(chineseTitle));
      expect(englishMessage, isNot(chineseMessage));
      expect(find.textContaining(englishTitle), findsOneWidget);
      expect(find.textContaining(englishMessage), findsOneWidget);
      expect(englishMessage, contains(detail));

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.textContaining(chineseTitle), findsOneWidget);
      expect(find.textContaining(chineseMessage), findsOneWidget);
      expect(issue.title, rawTitle);
      expect(issue.message, rawMessage);
      expect(issue.copy!.detail, detail);
      expect(service.clearCalls, 1);
      expect(service.readinessCalls, 1);
    },
  );

  testWidgets(
    'default app-owned title follows locale while readiness keeps its captured title',
    (tester) async {
      final service = _ControlledNotificationService();
      addTearDown(service.dispose);
      final capturedChineseTitle =
          TodoDetailUiCopy.reminderRegisterFailedIssueTitle;
      late BuildContext context;

      await tester.pumpWidget(
        _contextApp(
          onBuild: (value) => context = value,
          childBuilder: (_) => const SizedBox.shrink(),
        ),
      );

      final operation = preflightTodoReminderSave(
        context,
        todo: _todoWithDailyPushReminder(),
        notificationService: service,
      );
      await tester.pump();
      expect(service.requestedIssueTitle, capturedChineseTitle);

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      service.readiness.complete(false);
      expect(await operation, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final englishWithCapturedTitle =
          TodoDetailUiCopy.reminderPreflightUnregistered(capturedChineseTitle);
      final englishWithCurrentTitle =
          TodoDetailUiCopy.reminderPreflightUnregistered(
            TodoDetailUiCopy.reminderRegisterFailedIssueTitle,
          );
      expect(englishWithCurrentTitle, isNot(englishWithCapturedTitle));
      expect(find.text(englishWithCurrentTitle), findsOneWidget);
      expect(find.text(englishWithCapturedTitle), findsNothing);

      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.text(
          TodoDetailUiCopy.reminderPreflightUnregistered(capturedChineseTitle),
        ),
        findsOneWidget,
      );
      expect(service.clearCalls, 1);
      expect(service.readinessCalls, 1);
    },
  );

  testWidgets('readiness exceptions keep their original details', (
    tester,
  ) async {
    const exception = NotificationScheduleUnavailableException(
      title: 'Exact exception title',
      message: 'The native scheduler returned diagnostic 0xB4',
      relatedId: 'preflight-todo',
    );
    final service = _ControlledNotificationService(readinessError: exception);
    addTearDown(service.dispose);
    late BuildContext context;

    await tester.pumpWidget(
      _contextApp(
        onBuild: (value) => context = value,
        childBuilder: (_) => const SizedBox.shrink(),
      ),
    );

    final operation = preflightTodoReminderSave(
      context,
      todo: _todoWithDailyPushReminder(),
      notificationService: service,
    );
    final assertion = expectLater(operation, throwsA(same(exception)));
    await tester.pump();
    await assertion;

    expect(exception.title, 'Exact exception title');
    expect(exception.message, 'The native scheduler returned diagnostic 0xB4');
    expect(exception.relatedId, 'preflight-todo');
    expect(service.clearCalls, 1);
    expect(service.readinessCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('route disposal suppresses feedback from pending readiness', (
    tester,
  ) async {
    final service = _ControlledNotificationService();
    addTearDown(service.dispose);
    late BuildContext routeContext;

    await tester.pumpWidget(_routeApp((context) => routeContext = context));
    await tester.tap(find.text('Open route'));
    await tester.pumpAndSettle();

    final operation = preflightTodoReminderSave(
      routeContext,
      todo: _todoWithDailyPushReminder(),
      notificationService: service,
      issueTitle: 'Stale route feedback',
    );
    await tester.pump();
    await tester.tap(find.text('Close route'));
    await tester.pumpAndSettle();
    expect(routeContext.mounted, isFalse);

    service.readiness.complete(false);
    expect(await operation, isFalse);
    await tester.pump();
    expect(find.text('Close route'), findsNothing);
    expect(find.textContaining('Stale route feedback'), findsNothing);
    expect(service.clearCalls, 1);
    expect(service.readinessCalls, 1);
  });

  testWidgets('an account generation change suppresses stale feedback', (
    tester,
  ) async {
    final service = _ControlledNotificationService();
    addTearDown(service.dispose);
    final originGeneration = AccountLocalDataCleaner.accountDataGeneration;
    late BuildContext context;

    await tester.pumpWidget(
      _contextApp(
        onBuild: (value) => context = value,
        childBuilder: (_) => const SizedBox.shrink(),
      ),
    );

    final operation = preflightTodoReminderSave(
      context,
      todo: _todoWithDailyPushReminder(),
      notificationService: service,
      issueTitle: 'Stale account feedback',
      accountGeneration: originGeneration,
    );
    await tester.pump();

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    expect(
      AccountLocalDataCleaner.accountDataGeneration,
      isNot(originGeneration),
    );
    service.readiness.complete(false);
    expect(await operation, isFalse);
    await tester.pump();

    expect(find.textContaining('Stale account feedback'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(service.clearCalls, 1);
    expect(service.readinessCalls, 1);
  });
}

TodoItem _todoWithDailyPushReminder() => TodoItem(
  id: 'preflight-todo',
  title: 'Reminder preflight task',
  reminderPlan: ReminderPlan(
    enabled: true,
    rules: [
      ReminderRule(
        id: 'daily-push-rule',
        type: ReminderRuleType.dailyTime,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
      ),
    ],
  ),
);

Widget _contextApp({
  required ValueChanged<BuildContext> onBuild,
  required Widget Function(BuildContext context) childBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) {
        onBuild(context);
        return childBuilder(context);
      },
    ),
  ),
);

Widget _routeApp(ValueChanged<BuildContext> onRouteBuild) => MaterialApp(
  home: Builder(
    builder: (rootContext) => Scaffold(
      body: TextButton(
        onPressed: () => Navigator.of(rootContext).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Builder(
                builder: (routeContext) {
                  onRouteBuild(routeContext);
                  return Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(routeContext).pop(),
                      child: const Text('Close route'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        child: const Text('Open route'),
      ),
    ),
  ),
);

class _ControlledNotificationService extends NotificationService {
  _ControlledNotificationService({this.issueOnFailure, this.readinessError});

  final Completer<bool> readiness = Completer<bool>();
  final NotificationScheduleIssue? issueOnFailure;
  final Object? readinessError;

  NotificationScheduleIssue? _issue;
  int clearCalls = 0;
  int readinessCalls = 0;
  DateTime? requestedScheduledTime;
  String? requestedIssueTitle;
  NotificationIssueTitle? requestedIssueTitleCode;
  String? requestedRelatedId;

  @override
  NotificationScheduleIssue? get lastScheduleIssue => _issue;

  @override
  void clearScheduleIssue() {
    clearCalls++;
    _issue = null;
  }

  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String? issueTitle,
    NotificationIssueTitle? issueTitleCode,
    String? relatedId,
    bool Function()? canContinue,
  }) {
    readinessCalls++;
    requestedScheduledTime = scheduledTime;
    requestedIssueTitle = issueTitle;
    requestedIssueTitleCode = issueTitleCode;
    requestedRelatedId = relatedId;

    final error = readinessError;
    if (error != null) return Future<bool>.error(error);

    return readiness.future.then((ready) {
      if (!ready) _issue = issueOnFailure;
      return ready;
    });
  }
}
