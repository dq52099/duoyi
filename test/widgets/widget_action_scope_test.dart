import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/widget_action_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a new guest scope is current by default', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());

    expect(WidgetActionScope().isCurrent, isTrue);
  });

  testWidgets('account switch invalidates the old scope only', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final oldScope = WidgetActionScope();

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    final newScope = WidgetActionScope();

    expect(oldScope.isCurrent, isFalse);
    expect(newScope.isCurrent, isTrue);
  });

  testWidgets('caller availability is checked dynamically', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var callerAvailable = true;
    final scope = WidgetActionScope(isCallerAvailable: () => callerAvailable);

    expect(scope.isCurrent, isTrue);
    callerAvailable = false;
    expect(scope.isCurrent, isFalse);
    callerAvailable = true;
    expect(scope.isCurrent, isTrue);
  });

  testWidgets(
    'a stale generation short-circuits the unavailable caller predicate',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      var predicateCalls = 0;
      final scope = WidgetActionScope(
        isCallerAvailable: () {
          predicateCalls++;
          return false;
        },
      );

      AccountLocalDataCleaner.invalidateInFlightAccountWrites();

      expect(scope.isCurrent, isFalse);
      expect(predicateCalls, 0);
    },
  );

  testWidgets('idle afterFrame requests and delivers on a frame', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.hasScheduledFrame, isFalse);
    final scope = WidgetActionScope();
    var delivered = false;

    scope.afterFrame(() => delivered = true);

    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(delivered, isFalse);
    await tester.pump();
    expect(delivered, isTrue);
  });

  testWidgets(
    'afterFrame registered during post-frame requests the next frame once',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final scope = WidgetActionScope();
      var deliveries = 0;
      var nextFrameRequested = false;

      tester.binding.addPostFrameCallback((_) {
        expect(
          tester.binding.schedulerPhase,
          SchedulerPhase.postFrameCallbacks,
        );
        scope.afterFrame(() => deliveries++);
        nextFrameRequested = tester.binding.hasScheduledFrame;
      });
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(deliveries, 0);
      expect(nextFrameRequested, isTrue);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(deliveries, 1);

      await tester.pump();
      expect(deliveries, 1);
    },
  );

  testWidgets(
    'afterFrame registered during persistent callbacks runs in this frame',
    (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final scope = WidgetActionScope();
      var persistentFrames = 0;
      int? deliveredInFrame;

      tester.binding.addPersistentFrameCallback((_) {
        persistentFrames++;
        expect(
          tester.binding.schedulerPhase,
          SchedulerPhase.persistentCallbacks,
        );
        if (persistentFrames == 1) {
          scope.afterFrame(() => deliveredInFrame = persistentFrames);
        }
      });
      tester.binding.scheduleFrame();
      await tester.pump();

      expect(persistentFrames, 1);
      expect(deliveredInFrame, 1);
    },
  );

  testWidgets(
    'generation switch before the frame suppresses callback and snackbar',
    (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      final scope = WidgetActionScope();
      var delivered = false;

      scope.afterFrame(() {
        delivered = true;
        messengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('Stale account feedback')),
        );
      });
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(delivered, isFalse);
      expect(find.text('Stale account feedback'), findsNothing);
    },
  );

  testWidgets('caller disposal before the frame suppresses callback', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    var callerAvailable = true;
    var delivered = false;
    final scope = WidgetActionScope(isCallerAvailable: () => callerAvailable);

    scope.afterFrame(() => delivered = true);
    callerAvailable = false;
    await tester.pump();

    expect(delivered, isFalse);
  });

  testWidgets('an old queued callback cannot hide the next account snackbar', (
    tester,
  ) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    messengerKey.currentState!.showSnackBar(
      const SnackBar(
        content: Text('Account B snackbar'),
        duration: Duration(minutes: 1),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Account B snackbar'), findsOneWidget);

    final oldAccountScope = WidgetActionScope();
    oldAccountScope.afterFrame(() {
      messengerKey.currentState!
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Account A snackbar')));
    });
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Account B snackbar'), findsOneWidget);
    expect(find.text('Account A snackbar'), findsNothing);
  });

  testWidgets('a current scoped snackbar is displayed', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    final scope = WidgetActionScope();

    scope.afterFrame(() {
      messengerKey.currentState!
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Current scoped feedback')),
        );
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Current scoped feedback'), findsOneWidget);
  });
}
