import 'dart:async';

import 'package:duoyi/services/widget_launch_access.dart';
import 'package:duoyi/services/widget_navigation_request.dart';
import 'package:duoyi/services/widget_quick_todo_action.dart';
import 'package:duoyi/services/widget_action_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an open form is retained without replaying its native receipt', (
    tester,
  ) async {
    final fixture = _Fixture();
    final access = fixture.delivery(fixture.requests.capture());
    final formClosed = Completer<void>();
    final running = access.run(() async {
      access.markInteractionPresented();
      await formClosed.future;
    });
    access.finishDispatch();
    fixture.blocked = true;
    expect(access.canProceed, isFalse);
    expect(fixture.queued, isEmpty);
    expect(fixture.acknowledged, isEmpty);
    fixture.blocked = false;
    expect(access.canProceed, isTrue);
    formClosed.complete();
    await running;
    expect(fixture.acknowledged, [fixture.uri]);
  });

  testWidgets(
    'quick add feedback survives receipt acknowledgment and checks a later lock',
    (tester) async {
      final fixture = _Fixture();
      final access = fixture.delivery(fixture.requests.capture());
      var feedbackCount = 0;
      final running = access.run(
        () => runWidgetQuickTodoAction<String>(
          isCallerAvailable: () => access.canProceed,
          isFeedbackAvailable: () => access.canDeliverFeedback,
          preflight: (_) async => true,
          create: () async {
            access.markActionStarted();
            fixture.actions++;
            return 'Saved';
          },
          feedback: (_, isCurrent) => WidgetActionScope(
            isCallerAvailable: isCurrent,
          ).afterFrame(() => feedbackCount++),
          failureMessage: 'Failed',
        ),
      );
      access.finishDispatch();
      await running;
      expect(fixture.acknowledged, [fixture.uri]);
      expect(access.canProceed, isFalse);
      await tester.pump();
      expect(feedbackCount, 1);
      fixture.blocked = true;
      expect(access.canDeliverFeedback, isFalse);
      expect(fixture.queued, isEmpty);
    },
  );

  testWidgets(
    'lock before the next frame retains the original receipt for replay',
    (tester) async {
      final fixture = _Fixture();
      final request = fixture.requests.capture();
      final access = fixture.delivery(request);
      access.afterFrame(() => fixture.actions++);
      access.finishDispatch();
      expect(fixture.acknowledged, isEmpty);
      fixture.blocked = true;
      await tester.pump();
      expect(fixture.actions, 0);
      expect(fixture.acknowledged, isEmpty);
      expect(fixture.queued.single.$1, same(fixture.uri));
      expect(fixture.queued.single.$2, same(request));
      fixture.blocked = false;
      final replay = fixture.delivery(fixture.queued.single.$2);
      replay.afterFrame(() => fixture.actions++);
      replay.finishDispatch();
      await tester.pump();
      expect(fixture.actions, 1);
      expect(fixture.acknowledged, [fixture.uri]);
    },
  );

  test(
    'locking during a rejected preflight also retains the receipt',
    () async {
      final fixture = _Fixture();
      final access = fixture.delivery(fixture.requests.capture());
      final permission = Completer<bool>();
      final running = access.run(
        () => runWidgetQuickTodoAction<String>(
          isCallerAvailable: () => access.canProceed,
          isFeedbackAvailable: () => access.canDeliverFeedback,
          preflight: (_) => permission.future,
          create: () async {
            fixture.actions++;
            return 'Saved';
          },
          feedback: (_, _) {},
          failureMessage: 'Failed',
        ),
      );
      access.finishDispatch();
      fixture.blocked = true;
      permission.complete(false);
      await running;
      expect(fixture.actions, 0);
      expect(fixture.queued, hasLength(1));
      expect(fixture.acknowledged, isEmpty);
    },
  );

  for (final invalidate in ['account', 'latest date', 'caller']) {
    testWidgets(
      '$invalidate invalidation acknowledges without performing the old action',
      (tester) async {
        final fixture = _Fixture();
        final access = fixture.delivery(
          fixture.requests.capture(),
          latest: true,
        );
        access.afterFrame(() => fixture.actions++);
        access.finishDispatch();
        switch (invalidate) {
          case 'account':
            fixture.generation++;
          case 'latest date':
            fixture.requests.capture();
          case 'caller':
            fixture.available = false;
        }
        await tester.pump();
        expect(fixture.actions, 0);
        expect(fixture.queued, isEmpty);
        expect(fixture.acknowledged, [fixture.uri]);
      },
    );
  }

  test(
    'lock during preflight preserves the receipt without performing a write',
    () async {
      final fixture = _Fixture();
      final access = fixture.delivery(fixture.requests.capture());
      final preflight = Completer<void>();
      final running = access.run(() async {
        await preflight.future;
        if (access.canProceed) fixture.actions++;
      });
      access.finishDispatch();
      fixture.blocked = true;
      preflight.complete();
      await running;
      expect(fixture.actions, 0);
      expect(fixture.queued, hasLength(1));
      expect(fixture.acknowledged, isEmpty);
    },
  );

  test(
    'a write already accepted before locking completes without being replayed',
    () async {
      final fixture = _Fixture();
      final access = fixture.delivery(fixture.requests.capture());
      final completion = Completer<void>();
      final running = access.run(() async {
        access.markActionStarted();
        fixture.actions++;
        await completion.future;
        expect(
          access.canProceed,
          isFalse,
          reason: 'locked feedback is suppressed',
        );
      });
      access.finishDispatch();
      fixture.blocked = true;
      completion.complete();
      await running;
      access.finishDispatch();
      expect(fixture.actions, 1);
      expect(fixture.queued, isEmpty);
      expect(fixture.acknowledged, [fixture.uri]);
      expect(access.canProceed, isFalse);
    },
  );

  testWidgets(
    'separate deliveries of one action remain separate interactions',
    (tester) async {
      final fixture = _Fixture();
      final first = fixture.delivery(fixture.requests.capture());
      final secondUri = fixture.uri.replace(
        queryParameters: {'widget_delivery': 'second'},
      );
      final second = fixture.delivery(
        fixture.requests.capture(),
        uri: secondUri,
      );
      first.afterFrame(() => fixture.actions++);
      second.afterFrame(() => fixture.actions++);
      first.finishDispatch();
      second.finishDispatch();
      await tester.pump();
      expect(fixture.actions, 2);
      expect(fixture.acknowledged, [fixture.uri, secondUri]);
    },
  );
}

class _Fixture {
  int generation = 1;
  bool blocked = false;
  bool available = true;
  int actions = 0;
  final uri = Uri.parse(
    'duoyi://action/checkin_habit?id=habit&widget_delivery=first',
  );
  late final requests = WidgetNavigationRequests(
    accountGeneration: () => generation,
  );
  final queued = <(Uri, WidgetNavigationRequest)>[];
  final acknowledged = <Uri>[];

  WidgetLaunchAccess delivery(
    WidgetNavigationRequest request, {
    bool latest = false,
    Uri? uri,
  }) => WidgetLaunchAccess(
    uri: uri ?? this.uri,
    request: request,
    isBlocked: () => blocked,
    isCallerAvailable: () => available,
    requiresLatest: latest,
    requeue: (uri, request) => queued.add((uri, request)),
    acknowledge: (uri) async => acknowledged.add(uri),
  );
}
