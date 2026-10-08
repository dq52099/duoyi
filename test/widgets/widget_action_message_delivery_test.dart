import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
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
