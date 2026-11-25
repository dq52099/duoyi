import 'dart:async';
import 'dart:io';

import 'package:duoyi/services/home_widget_push_queue.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root lifecycle forwards both hints and retains resumed refresh', () {
    final main = File('lib/main.dart').readAsStringSync();
    final start = main.indexOf('  void didChangeAppLifecycleState(');
    final end = main.indexOf('\n  ///', start);
    final lifecycle = main.substring(start, end);
    expect(
      main,
      contains(
        'HomeWidgetService.widgetLifecycleChanged = homeWidgetPushQueue.setBackground;',
      ),
    );
    expect(lifecycle, contains('HomeWidgetService.setAppInBackground(true);'));
    expect(lifecycle, contains('HomeWidgetService.setAppInBackground(false);'));
    expect(
      lifecycle,
      contains('_refreshWidgetsFromAction(context, showFeedback: false)'),
    );
    expect(
      main,
      matches(
        RegExp(
          r'deferredLocalStorageHydrated\s*&&\s*!_widgetAccountUnavailable\(authProvider\)',
        ),
      ),
    );
    expect(main, contains('ValidatedWidgetWorkspace('));
  });

  test('foreground changes coalesce and retain the eight-second interval', () {
    fakeAsync((time) {
      var signature = 'one';
      final pushed = <String>[];
      final queue = HomeWidgetPushQueue(
        canPublish: () => true,
        readSignature: () => signature,
        publish: () async {
          pushed.add(signature);
          return true;
        },
        now: time.getClock(DateTime.utc(2026)).now,
      );
      queue.queue();
      time.elapse(const Duration(seconds: 1));
      signature = 'two';
      queue.queue();
      time.elapse(const Duration(milliseconds: 2199));
      expect(pushed, isEmpty);
      time.elapse(const Duration(milliseconds: 1));
      expect(pushed, ['two']);
      signature = 'three';
      queue.queue();
      time.elapse(const Duration(milliseconds: 7999));
      expect(pushed, ['two']);
      time.elapse(const Duration(milliseconds: 1));
      expect(pushed, ['two', 'three']);
      queue.dispose();
    });
  });

  test('background drains pending work and cancels duplicate timer', () {
    fakeAsync((time) {
      var writes = 0;
      final queue = HomeWidgetPushQueue(
        canPublish: () => true,
        readSignature: () => 'one',
        publish: () async {
          writes++;
          return true;
        },
      );
      queue.queue();
      queue.setBackground(true);
      time.flushMicrotasks();
      expect(writes, 1);
      queue.setBackground(true);
      time.elapse(const Duration(minutes: 1));
      expect(writes, 1);
      expect(time.pendingTimers, isEmpty);
      queue.dispose();
    });
  });

  test(
    'in-flight publication drains latest change without timer or overlap',
    () {
      fakeAsync((time) {
        var signature = 'old';
        final first = Completer<bool>();
        final writes = <String>[];
        final queue = HomeWidgetPushQueue(
          canPublish: () => true,
          readSignature: () => signature,
          publish: () {
            writes.add(signature);
            return writes.length == 1 ? first.future : Future.value(true);
          },
          now: time.getClock(DateTime.utc(2026)).now,
        );
        queue.queue();
        time.elapse(HomeWidgetPushQueue.debounceDelay);
        expect(writes, ['old']);
        signature = 'latest';
        queue.queue();
        queue.setBackground(true);
        time.flushMicrotasks();
        expect(writes, ['old']);
        first.complete(true);
        time.flushMicrotasks();
        expect(writes, ['old', 'latest']);
        expect(time.pendingTimers, isEmpty);
        queue.dispose();
      });
    },
  );

  test('new work between inactive and paused is not lost to deduplication', () {
    fakeAsync((time) {
      var signature = 'inactive';
      final writes = <String>[];
      final queue = HomeWidgetPushQueue(
        canPublish: () => true,
        readSignature: () => signature,
        publish: () async {
          writes.add(signature);
          return true;
        },
      );
      queue.queue();
      queue.setBackground(true);
      time.flushMicrotasks();
      signature = 'paused';
      queue.queue();
      queue.setBackground(true);
      time.flushMicrotasks();
      expect(writes, ['inactive', 'paused']);
      expect(time.pendingTimers, isEmpty);
      queue.dispose();
    });
  });

  test(
    'failed background publication remains dirty for resume without retry',
    () {
      fakeAsync((time) {
        var writes = 0;
        final queue = HomeWidgetPushQueue(
          canPublish: () => true,
          readSignature: () => 'same',
          publish: () async {
            writes++;
            return writes > 1;
          },
          now: time.getClock(DateTime.utc(2026)).now,
        );
        queue.queue();
        queue.setBackground(true);
        time.flushMicrotasks();
        expect(writes, 1);
        time.elapse(const Duration(minutes: 1));
        expect(writes, 1);
        expect(time.pendingTimers, isEmpty);
        queue.setBackground(false);
        time.elapse(HomeWidgetPushQueue.debounceDelay);
        expect(writes, 2);
        queue.dispose();
      });
    },
  );

  test('unhydrated background transition never reads or publishes', () {
    fakeAsync((time) {
      var ready = false;
      var reads = 0;
      var writes = 0;
      final queue = HomeWidgetPushQueue(
        canPublish: () => ready,
        readSignature: () {
          reads++;
          return 'ready';
        },
        publish: () async {
          writes++;
          return true;
        },
      );
      queue.queue();
      queue.setBackground(true);
      time.flushMicrotasks();
      expect([reads, writes], [0, 0]);
      expect(time.pendingTimers, isEmpty);
      ready = true;
      queue.queue();
      time.flushMicrotasks();
      expect([reads, writes], [1, 1]);
      queue.dispose();
    });
  });

  test(
    'revoked account prevents followup and fresh account can replace it',
    () {
      fakeAsync((time) {
        var admitted = true;
        var account = 'old';
        final first = Completer<bool>();
        final writes = <String>[];
        final queue = HomeWidgetPushQueue(
          canPublish: () => admitted,
          readSignature: () => account,
          publish: () {
            writes.add(account);
            return writes.length == 1 ? first.future : Future.value(true);
          },
        );
        queue.queue();
        queue.setBackground(true);
        queue.queue();
        admitted = false;
        queue.invalidateSignature();
        first.complete(false);
        time.flushMicrotasks();
        expect(writes, ['old']);
        admitted = true;
        account = 'new';
        queue.queue();
        time.flushMicrotasks();
        expect(writes, ['old', 'new']);
        queue.dispose();
      });
    },
  );

  test('foreground exceptions retry only three times after first attempt', () {
    fakeAsync((time) {
      var attempts = 0;
      final queue = HomeWidgetPushQueue(
        canPublish: () => true,
        readSignature: () => 'same',
        publish: () async {
          attempts++;
          throw StateError('synthetic');
        },
        now: time.getClock(DateTime.utc(2026)).now,
      );
      queue.queue();
      time.elapse(const Duration(minutes: 1));
      expect(attempts, 4);
      expect(time.pendingTimers, isEmpty);
      queue.dispose();
    });
  });

  test('successful unchanged signatures do not publish again', () {
    fakeAsync((time) {
      var writes = 0;
      final queue = HomeWidgetPushQueue(
        canPublish: () => true,
        readSignature: () => 'same',
        publish: () async {
          writes++;
          return true;
        },
      );
      queue.queue();
      queue.setBackground(true);
      time.flushMicrotasks();
      queue.queue();
      time.flushMicrotasks();
      expect(writes, 1);
      queue.invalidateSignature();
      queue.queue();
      time.flushMicrotasks();
      expect(writes, 2);
      queue.dispose();
    });
  });

  test(
    'background drain is bounded and retains newest pending work for resume',
    () {
      fakeAsync((time) {
        var revision = 0;
        final publications = <Completer<bool>>[];
        final writes = <int>[];
        final queue = HomeWidgetPushQueue(
          canPublish: () => true,
          readSignature: () => '$revision',
          publish: () {
            writes.add(revision);
            final completion = Completer<bool>();
            publications.add(completion);
            return completion.future;
          },
          now: time.getClock(DateTime.utc(2026)).now,
        );
        queue.queue();
        queue.setBackground(true);
        revision = 1;
        queue.queue();
        publications[0].complete(true);
        time.flushMicrotasks();
        expect(writes, [0, 1]);
        revision = 2;
        queue.queue();
        publications[1].complete(true);
        time.flushMicrotasks();
        expect(writes, [0, 1]);
        expect(time.pendingTimers, isEmpty);
        queue.setBackground(false);
        time.elapse(HomeWidgetPushQueue.minimumInterval);
        expect(writes, [0, 1, 2]);
        publications[2].complete(true);
        time.flushMicrotasks();
        queue.dispose();
      });
    },
  );
}
