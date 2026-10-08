import 'dart:async';
import 'dart:io';

import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/widget_quick_todo_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runWidgetQuickTodoAction', () {
    test(
      'same-account success forwards the reminder warning unchanged',
      () async {
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        const warning = '快捷待办已保存到本机，但提醒未注册：锁屏闹钟注册状态未确认。';
        var preflightCalls = 0;
        var createCalls = 0;
        final messages = <String>[];
        final currentAtFeedback = <bool>[];

        await runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (_) async {
            preflightCalls++;
            return true;
          },
          create: () async {
            createCalls++;
            return warning;
          },
          feedback: (message, isCurrent) {
            messages.add(message);
            currentAtFeedback.add(isCurrent());
          },
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        expect(preflightCalls, 1);
        expect(createCalls, 1);
        expect(messages, [warning]);
        expect(currentAtFeedback.single, isTrue);
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isTrue,
        );
      },
    );

    test(
      'a failed reminder preflight forwards its current warning and skips create',
      () async {
        const warning = '待办提醒注册失败：提醒未注册，请稍后重试。';
        var createCalls = 0;
        final messages = <String>[];

        await runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (showFeedback) async {
            showFeedback(warning);
            return false;
          },
          create: () async {
            createCalls++;
            return 'unexpected success';
          },
          feedback: (message, isCurrent) {
            expect(isCurrent(), isTrue);
            messages.add(message);
          },
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        expect(createCalls, 0);
        expect(messages, [warning]);
      },
    );

    test(
      'an unavailable guest caller returns before preflight or create',
      () async {
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        var preflightCalls = 0;
        var createCalls = 0;
        final messages = <String>[];

        await runWidgetQuickTodoAction(
          isCallerAvailable: () => false,
          preflight: (_) async {
            preflightCalls++;
            return true;
          },
          create: () async {
            createCalls++;
            return 'unexpected success';
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        expect(preflightCalls, 0);
        expect(createCalls, 0);
        expect(messages, isEmpty);
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isTrue,
          reason: 'guest unavailability is independent of account generation',
        );
      },
    );

    test(
      'an account-generation switch during preflight prevents create',
      () async {
        final enteredPreflight = Completer<void>();
        final releasePreflight = Completer<bool>();
        var createCalls = 0;
        final messages = <String>[];
        final generation = AccountLocalDataCleaner.accountDataGeneration;

        final pending = runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (_) {
            enteredPreflight.complete();
            return releasePreflight.future;
          },
          create: () async {
            createCalls++;
            return 'unexpected success';
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        await enteredPreflight.future;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isFalse,
        );
        releasePreflight.complete(true);
        await pending;

        expect(createCalls, 0);
        expect(messages, isEmpty);
      },
    );

    test(
      'a transition or disposal predicate change alone prevents create',
      () async {
        final enteredPreflight = Completer<void>();
        final releasePreflight = Completer<bool>();
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        var callerAvailable = true;
        var createCalls = 0;
        final messages = <String>[];

        final pending = runWidgetQuickTodoAction(
          isCallerAvailable: () => callerAvailable,
          preflight: (_) {
            enteredPreflight.complete();
            return releasePreflight.future;
          },
          create: () async {
            createCalls++;
            return 'unexpected success';
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        await enteredPreflight.future;
        callerAvailable = false;
        releasePreflight.complete(true);
        await pending;

        expect(createCalls, 0);
        expect(messages, isEmpty);
        expect(
          AccountLocalDataCleaner.accountDataGeneration,
          generation,
          reason:
              'the caller predicate changed without invalidating account generation',
        );
      },
    );

    test(
      'stale preflight feedback is suppressed after an account switch',
      () async {
        final enteredPreflight = Completer<void>();
        final releasePreflight = Completer<void>();
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        var createCalls = 0;
        final messages = <String>[];

        final pending = runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (showFeedback) async {
            enteredPreflight.complete();
            await releasePreflight.future;
            showFeedback('旧账户的提醒未注册');
            return false;
          },
          create: () async {
            createCalls++;
            return 'unexpected success';
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        await enteredPreflight.future;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isFalse,
        );
        releasePreflight.complete();
        await pending;

        expect(createCalls, 0);
        expect(messages, isEmpty);
      },
    );

    test(
      'a stale preflight error is logged but its failure feedback is suppressed',
      () async {
        final enteredPreflight = Completer<void>();
        final releasePreflight = Completer<void>();
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final messages = <String>[];
        Object? loggedError;
        StackTrace? loggedStack;
        var createCalls = 0;

        final pending = runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (_) async {
            enteredPreflight.complete();
            await releasePreflight.future;
            throw StateError('old-account preflight failed');
          },
          create: () async {
            createCalls++;
            return 'unexpected success';
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
          logError: (error, stack) {
            loggedError = error;
            loggedStack = stack;
          },
        );

        await enteredPreflight.future;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isFalse,
        );
        releasePreflight.complete();
        await pending;

        expect(createCalls, 0);
        expect(messages, isEmpty);
        expect(loggedError, isA<StateError>());
        expect(loggedStack, isNotNull);
      },
    );

    test(
      'an account switch during create suppresses its success message',
      () async {
        final enteredCreate = Completer<void>();
        final releaseCreate = Completer<String>();
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final messages = <String>[];
        var createCalls = 0;

        final pending = runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (_) async => true,
          create: () {
            createCalls++;
            enteredCreate.complete();
            return releaseCreate.future;
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
        );

        await enteredCreate.future;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isFalse,
        );
        releaseCreate.complete('快捷待办已保存到本机');
        await pending;

        expect(createCalls, 1);
        expect(messages, isEmpty);
      },
    );

    test(
      'an account switch during create suppresses its failure feedback',
      () async {
        final enteredCreate = Completer<void>();
        final releaseCreate = Completer<String>();
        final generation = AccountLocalDataCleaner.accountDataGeneration;
        final messages = <String>[];
        Object? loggedError;
        StackTrace? loggedStack;
        var createCalls = 0;

        final pending = runWidgetQuickTodoAction(
          isCallerAvailable: () => true,
          preflight: (_) async => true,
          create: () {
            createCalls++;
            enteredCreate.complete();
            return releaseCreate.future;
          },
          feedback: (message, _) => messages.add(message),
          failureMessage: '快捷待办创建失败，请稍后重试',
          logError: (error, stack) {
            loggedError = error;
            loggedStack = stack;
          },
        );

        await enteredCreate.future;
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        expect(
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
          isFalse,
        );
        releaseCreate.completeError(
          StateError('old-account create failed'),
          StackTrace.current,
        );
        await pending;

        expect(createCalls, 1);
        expect(messages, isEmpty);
        expect(loggedError, isA<StateError>());
        expect(loggedStack, isNotNull);
      },
    );

    test(
      'current preflight and create errors forward the failure message',
      () async {
        Future<void> expectCurrentError({required bool failPreflight}) async {
          const failure = '快捷待办创建失败，请稍后重试';
          final messages = <String>[];
          final currentAtFeedback = <bool>[];
          Object? loggedError;
          StackTrace? loggedStack;
          var createCalls = 0;

          await runWidgetQuickTodoAction(
            isCallerAvailable: () => true,
            preflight: (_) async {
              if (failPreflight) throw StateError('current preflight failure');
              return true;
            },
            create: () async {
              createCalls++;
              throw StateError('current create failure');
            },
            feedback: (message, isCurrent) {
              messages.add(message);
              currentAtFeedback.add(isCurrent());
            },
            failureMessage: failure,
            logError: (error, stack) {
              loggedError = error;
              loggedStack = stack;
            },
          );

          expect(messages, [failure]);
          expect(currentAtFeedback.single, isTrue);
          expect(loggedError, isA<StateError>());
          expect(loggedStack, isNotNull);
          expect(createCalls, failPreflight ? 0 : 1);
        }

        await expectCurrentError(failPreflight: true);
        await expectCurrentError(failPreflight: false);
      },
    );

    test('delayed feedback checks isCurrent again before delivery', () async {
      final allowDelivery = Completer<void>();
      final deliveryFinished = Completer<void>();
      final generation = AccountLocalDataCleaner.accountDataGeneration;
      final deliveredMessages = <String>[];
      String? queuedMessage;
      bool Function()? queuedIsCurrent;

      await runWidgetQuickTodoAction(
        isCallerAvailable: () => true,
        preflight: (_) async => true,
        create: () async => '快捷待办已保存到本机',
        feedback: (message, isCurrent) {
          queuedMessage = message;
          queuedIsCurrent = isCurrent;
          unawaited(() async {
            await allowDelivery.future;
            if (isCurrent()) deliveredMessages.add(message);
            deliveryFinished.complete();
          }());
        },
        failureMessage: '快捷待办创建失败，请稍后重试',
      );

      expect(queuedMessage, '快捷待办已保存到本机');
      expect(queuedIsCurrent, isNotNull);
      expect(queuedIsCurrent!(), isTrue);

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      expect(
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation),
        isFalse,
      );
      allowDelivery.complete();
      await deliveryFinished.future;

      expect(deliveredMessages, isEmpty);
    });
  });

  test(
    'source wiring: quick widget draft binds providers and guarded feedback',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final actionStart = source.indexOf(
        'Future<void> _createQuickTodoFromAction(',
      );
      final actionEnd = source.indexOf(
        '\nbool _widgetAccountUnavailable',
        actionStart,
      );
      expect(actionStart, greaterThanOrEqualTo(0));
      expect(actionEnd, greaterThan(actionStart));
      final actionSource = source.substring(actionStart, actionEnd);
      final authBinding = actionSource.indexOf(
        'final auth = context.read<AuthProvider>();',
      );
      final todoBinding = actionSource.indexOf(
        'final todos = Provider.of<TodoProvider?>(context, listen: false);',
      );
      final coordinatorCall = actionSource.indexOf(
        'await runWidgetQuickTodoAction(',
      );

      expect(authBinding, greaterThanOrEqualTo(0));
      expect(todoBinding, greaterThanOrEqualTo(0));
      expect(authBinding, lessThan(coordinatorCall));
      expect(todoBinding, lessThan(coordinatorCall));
      expect(
        actionSource,
        contains('context.mounted && !_widgetAccountUnavailable(auth)'),
      );
      expect(
        actionSource,
        contains(
          '_showWidgetActionFeedbackFromShell(message, isCurrentAction: isCurrent)',
        ),
      );

      final feedbackStart = source.indexOf(
        'void _showWidgetActionFeedbackFromShell(',
      );
      final feedbackEnd = source.indexOf(
        '\nFuture<void> _createQuickTodoFromAction',
        feedbackStart,
      );
      expect(feedbackStart, greaterThanOrEqualTo(0));
      expect(feedbackEnd, greaterThan(feedbackStart));
      final feedbackSource = source.substring(feedbackStart, feedbackEnd);
      final generationCapture = feedbackSource.indexOf(
        'final generation = AccountLocalDataCleaner.accountDataGeneration;',
      );
      final postFrame = feedbackSource.indexOf(
        'WidgetsBinding.instance.addPostFrameCallback',
      );
      final generationGuard = feedbackSource.indexOf(
        'if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation))',
      );
      final predicate = feedbackSource.indexOf(
        'if (isCurrentAction != null && !isCurrentAction()) return;',
      );
      final messenger = feedbackSource.indexOf(
        'ScaffoldMessenger.of(latestContext)',
      );

      expect(generationCapture, greaterThanOrEqualTo(0));
      expect(postFrame, greaterThanOrEqualTo(0));
      expect(generationCapture, lessThan(postFrame));
      expect(generationGuard, greaterThan(postFrame));
      expect(generationGuard, lessThan(predicate));
      expect(predicate, greaterThan(postFrame));
      expect(messenger, greaterThan(predicate));
      expect(messenger, greaterThan(generationGuard));
    },
  );
}
