import 'dart:async';

import 'package:duoyi/services/digest_reminder_coordinator.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test(
    'daily cancellation and report scheduling share a serialized queue with run-start locale snapshots',
    () async {
      var generation = 14;
      var isEnglish = false;
      final events = <String>[];
      final coordinator = DigestReminderCoordinator(
        currentAccountGeneration: () => generation,
        captureEnglish: () => isEnglish,
      );

      final dailyStarted = Completer<void>();
      final releaseDailyCancel = Completer<void>();
      late DigestReminderRun dailyRun;
      final daily = coordinator.run<String>((run) async {
        dailyRun = run;
        events.add('daily cancel started');
        dailyStarted.complete();
        await releaseDailyCancel.future;
        events.add('daily cancel completed');
        return 'daily-cancelled';
      }, skippedResult: () => 'daily-skipped');
      await dailyStarted.future;
      expect(dailyRun.accountGeneration, 14);
      expect(dailyRun.isEnglish, isFalse);
      expect(dailyRun.isCurrent, isTrue);

      final reportStarted = Completer<void>();
      final releaseReportSchedule = Completer<void>();
      late DigestReminderRun reportRun;
      final report = coordinator.run<String>((run) async {
        reportRun = run;
        events.add('report schedule started');
        reportStarted.complete();
        await releaseReportSchedule.future;
        events.add('report schedule completed');
        return 'report-scheduled';
      }, skippedResult: () => 'report-skipped');

      isEnglish = true;
      expect(events, ['daily cancel started']);
      releaseDailyCancel.complete();
      expect(await daily, 'daily-cancelled');
      await reportStarted.future;

      expect(events, [
        'daily cancel started',
        'daily cancel completed',
        'report schedule started',
      ]);
      expect(reportRun.accountGeneration, 14);
      expect(reportRun.isEnglish, isTrue);
      expect(reportRun.isCurrent, isTrue);

      isEnglish = false;
      expect(reportRun.isEnglish, isTrue);
      releaseReportSchedule.complete();
      expect(await report, 'report-scheduled');
      await coordinator.drain();
      expect(events.last, 'report schedule completed');
      expect(reportRun.isCurrent, isTrue);
    },
  );

  test(
    'a failed callback does not poison the next callback or drain',
    () async {
      final coordinator = DigestReminderCoordinator(
        currentAccountGeneration: () => 3,
        captureEnglish: () => false,
      );
      final failingStarted = Completer<void>();
      final releaseFailure = Completer<void>();
      final failure = coordinator.run<void>((_) async {
        failingStarted.complete();
        await releaseFailure.future;
        throw StateError('synthetic cancellation failure');
      }, skippedResult: () {});

      final nextStarted = Completer<void>();
      final releaseNext = Completer<void>();
      final next = coordinator.run<String>((_) async {
        nextStarted.complete();
        await releaseNext.future;
        return 'next-finished';
      }, skippedResult: () => 'next-skipped');

      await failingStarted.future;
      releaseFailure.complete();
      await expectLater(failure, throwsA(isA<StateError>()));
      await nextStarted.future;

      var drained = false;
      final drain = coordinator.drain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);

      releaseNext.complete();
      expect(await next, 'next-finished');
      await drain;
      expect(drained, isTrue);
      await coordinator.drain();
    },
  );

  test(
    'suspension waits for active cancellation before cancelAll and skips queued old-account work after resume',
    () async {
      var generation = 31;
      final coordinator = DigestReminderCoordinator(
        currentAccountGeneration: () => generation,
        captureEnglish: () => true,
      );
      final activeStarted = Completer<void>();
      final releaseActiveCancel = Completer<void>();
      late DigestReminderRun activeRun;
      final active = coordinator.run<String>((run) async {
        activeRun = run;
        activeStarted.complete();
        await releaseActiveCancel.future;
        return 'active-cancelled';
      }, skippedResult: () => 'active-skipped');
      await activeStarted.future;
      expect(activeRun.isCurrent, isTrue);

      var queuedScheduleRan = false;
      final queued = coordinator.run<bool>(
        (_) {
          queuedScheduleRan = true;
          return true;
        },
        submittedAccountGeneration: generation,
        skippedResult: () => false,
      );

      coordinator.suspendForAccountChange();
      expect(coordinator.isSuspended, isTrue);
      expect(activeRun.isCurrent, isFalse);

      var cancelAllCount = 0;
      final drainThenCancelAll = coordinator.drain().then((_) {
        cancelAllCount++;
      });
      await Future<void>.delayed(Duration.zero);
      expect(cancelAllCount, 0);

      releaseActiveCancel.complete();
      expect(await active, 'active-cancelled');
      expect(await queued, isFalse);
      await drainThenCancelAll;
      expect(cancelAllCount, 1);
      expect(queuedScheduleRan, isFalse);

      generation = 32;
      expect(coordinator.resumeForActiveAccount(), isTrue);
      var staleLifecycleRequestRan = false;
      final staleLifecycleRequest = coordinator.run<bool>(
        (_) {
          staleLifecycleRequestRan = true;
          return true;
        },
        submittedAccountGeneration: 31,
        skippedResult: () => false,
      );
      expect(await staleLifecycleRequest, isFalse);
      expect(staleLifecycleRequestRan, isFalse);

      final resumedRequest = coordinator.run<int>((run) {
        expect(run.accountGeneration, 32);
        expect(run.isCurrent, isTrue);
        return 32;
      }, skippedResult: () => -1);
      expect(await resumedRequest, 32);
      await coordinator.drain();
    },
  );

  test(
    'a queued run from before suspension stays stale after same-generation resume',
    () async {
      const generation = 38;
      final coordinator = DigestReminderCoordinator(
        currentAccountGeneration: () => generation,
        captureEnglish: () => true,
      );
      final activeStarted = Completer<void>();
      final releaseActive = Completer<void>();
      final active = coordinator.run<void>((_) async {
        activeStarted.complete();
        await releaseActive.future;
      }, skippedResult: () {});
      await activeStarted.future;

      var oldQueuedRunStarted = false;
      final oldQueuedRun = coordinator.run<bool>(
        (_) {
          oldQueuedRunStarted = true;
          return true;
        },
        submittedAccountGeneration: generation,
        skippedResult: () => false,
      );

      coordinator.suspendForAccountChange();
      expect(coordinator.resumeForActiveAccount(), isTrue);
      expect(coordinator.isSuspended, isFalse);

      releaseActive.complete();
      await active;
      expect(await oldQueuedRun, isFalse);
      expect(oldQueuedRunStarted, isFalse);

      final freshRun = coordinator.run<bool>(
        (_) => true,
        skippedResult: () => false,
      );
      expect(await freshRun, isTrue);
      await coordinator.drain();
    },
  );

  test(
    'drain waits for a held platform schedule to register before cancelAll clears pending work',
    () async {
      final coordinator = DigestReminderCoordinator(
        currentAccountGeneration: () => 52,
        captureEnglish: () => false,
      );
      final pendingSchedules = <String>{};
      final events = <String>[];
      final platformScheduleStarted = Completer<void>();
      final releasePlatformSchedule = Completer<void>();
      final schedule = coordinator.run<String>((_) async {
        events.add('platform schedule started');
        platformScheduleStarted.complete();
        await releasePlatformSchedule.future;
        pendingSchedules.add('daily');
        events.add('platform schedule registered');
        return 'registered';
      }, skippedResult: () => 'skipped');
      await platformScheduleStarted.future;

      coordinator.suspendForAccountChange();
      var cancelAllCount = 0;
      final drainThenCancelAll = coordinator.drain().then((_) {
        events.add('cancelAll');
        cancelAllCount++;
        pendingSchedules.clear();
      });
      await Future<void>.delayed(Duration.zero);
      expect(cancelAllCount, 0);
      expect(pendingSchedules, isEmpty);

      releasePlatformSchedule.complete();
      expect(await schedule, 'registered');
      await drainThenCancelAll;

      expect(events, [
        'platform schedule started',
        'platform schedule registered',
        'cancelAll',
      ]);
      expect(cancelAllCount, 1);
      expect(pendingSchedules, isEmpty);
    },
  );

  test(
    'live snapshots reflect availability and generation while explicit stale submissions skip',
    () async {
      var generation = 45;
      var available = true;
      final coordinator = DigestReminderCoordinator(
        currentAccountGeneration: () => generation,
        captureEnglish: () => false,
        isAccountAvailable: () => available,
      );

      final normalSnapshot = coordinator.run<bool>(
        (run) => run.isCurrent,
        skippedResult: () => false,
      );
      expect(await normalSnapshot, isTrue);

      final activeStarted = Completer<void>();
      final releaseActive = Completer<void>();
      late DigestReminderRun activeRun;
      final active = coordinator.run<bool>((run) async {
        activeRun = run;
        activeStarted.complete();
        await releaseActive.future;
        return run.isCurrent;
      }, skippedResult: () => false);
      await activeStarted.future;
      expect(activeRun.isCurrent, isTrue);

      available = false;
      expect(activeRun.isCurrent, isFalse);
      var unavailableRequestRan = false;
      final unavailableRequest = coordinator.run<bool>((_) {
        unavailableRequestRan = true;
        return true;
      }, skippedResult: () => false);

      releaseActive.complete();
      expect(await active, isFalse);
      expect(await unavailableRequest, isFalse);
      expect(unavailableRequestRan, isFalse);
      expect(coordinator.resumeForActiveAccount(), isFalse);

      available = true;
      expect(coordinator.resumeForActiveAccount(), isTrue);
      generation = 46;
      var staleDebounceRan = false;
      final staleDebounce = coordinator.run<bool>(
        (_) {
          staleDebounceRan = true;
          return true;
        },
        submittedAccountGeneration: 45,
        skippedResult: () => false,
      );
      expect(await staleDebounce, isFalse);
      expect(staleDebounceRan, isFalse);
      await coordinator.drain();
    },
  );

  test('an idle run releases its previous FakeAsync source zone', () async {
    final coordinator = DigestReminderCoordinator(
      currentAccountGeneration: () => 1,
      captureEnglish: () => true,
    );
    int? firstResult;

    fakeAsync((async) {
      coordinator
          .run<int>((_) => 1, skippedResult: () => -1)
          .then((value) => firstResult = value);
      async.flushMicrotasks();
    });
    expect(firstResult, 1);

    int? secondResult;
    coordinator
        .run<int>((_) => 2, skippedResult: () => -1)
        .then((value) => secondResult = value);
    await Future<void>.delayed(Duration.zero);
    expect(secondResult, 2);
  });
}
