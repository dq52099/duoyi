import 'dart:async';

import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/services/required_storage_startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final family in ['course', 'calendar']) {
    test(
      'real $family storage decode failure keeps the phase closed',
      () async {
        final key = family == 'course'
            ? 'duoyi_courses'
            : 'duoyi_local_calendar_events_v1';
        SharedPreferences.setMockInitialValues({
          key: ['{invalid synthetic JSON'],
        });
        final course = CourseProvider();
        final calendar = CalendarProvider();
        addTearDown(course.dispose);
        addTearDown(calendar.dispose);
        final task = family == 'course'
            ? course.loadFromStorage
            : calendar.loadFromStorage;
        final phase = RequiredStorageStartup();
        Future<void> attempt() =>
            phase.ensure(isCurrent: () => true, run: (load) => load(task));
        await expectLater(attempt(), throwsFormatException);
        expect(phase.ready, isFalse);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(key, []);
        await attempt();
        expect(phase.ready, isTrue);
        expect(course.courses, isEmpty);
        expect(calendar.localEvents, isEmpty);
      },
    );
  }

  test('concurrent callers wait for every required load once', () async {
    final phase = RequiredStorageStartup();
    final first = Completer<void>();
    final second = Completer<void>();
    var calls = 0;
    Future<void> run(
      Future<void> Function(Future<void> Function()) load,
    ) async {
      calls++;
      await load(() => first.future);
      await load(() => second.future);
    }

    final a = phase.ensure(run: run, isCurrent: () => true);
    final b = phase.ensure(run: run, isCurrent: () => true);
    expect(identical(a, b), isTrue);
    expect(phase.ready, isFalse);
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(phase.ready, isFalse);
    second.complete();
    await Future.wait([a, b]);
    expect(calls, 1);
    expect(phase.ready, isTrue);
    await phase.ensure(run: run, isCurrent: () => true);
    expect(calls, 1);
  });

  for (final synchronous in [true, false]) {
    test(
      'failed required load permits fresh retry (sync=$synchronous)',
      () async {
        final phase = RequiredStorageStartup();
        var calls = 0;
        var fail = true;
        Future<void> task() {
          calls++;
          if (fail) {
            if (synchronous) throw const FormatException('synthetic storage');
            return Future<void>.error(
              const FormatException('synthetic storage'),
            );
          }
          return Future<void>.value();
        }

        Future<void> attempt() =>
            phase.ensure(isCurrent: () => true, run: (load) => load(task));
        await expectLater(attempt(), throwsFormatException);
        expect(phase.ready, isFalse);
        fail = false;
        await attempt();
        expect(calls, 2);
        expect(phase.ready, isTrue);
      },
    );
  }

  test(
    'context change rejects late load and never starts the next one',
    () async {
      final phase = RequiredStorageStartup();
      final held = Completer<void>();
      var current = true;
      var secondCalls = 0;
      final pending = phase.ensure(
        isCurrent: () => current,
        run: (load) async {
          await load(() => held.future);
          await load(() async {
            secondCalls++;
          });
        },
      );
      final rejected = expectLater(pending, throwsStateError);
      current = false;
      held.complete();
      await rejected;
      expect(phase.ready, isFalse);
      expect(secondCalls, 0);
    },
  );

  test('old rejection cannot erase a newer completed attempt', () async {
    final phase = RequiredStorageStartup();
    final held = Completer<void>();
    final old = phase.ensure(
      isCurrent: () => true,
      run: (load) => load(() => held.future),
    );
    final rejected = expectLater(old, throwsStateError);
    phase.invalidate();
    await phase.ensure(isCurrent: () => true, run: (load) => load(() async {}));
    expect(phase.ready, isTrue);
    held.complete();
    await rejected;
    expect(phase.ready, isTrue);
  });

  test('new context recaptures after cached old success', () async {
    final phase = RequiredStorageStartup();
    var generation = 1;
    var calls = 0;
    Future<void> attempt() {
      final captured = generation;
      return phase.ensure(
        isCurrent: () => generation == captured,
        run: (load) => load(() async {
          calls++;
        }),
      );
    }

    await attempt();
    generation++;
    expect(phase.ready, isFalse);
    await attempt();
    expect(calls, 2);
    expect(phase.ready, isTrue);
  });

  test('timeout cannot mark ready after a successful fresh retry', () async {
    final phase = RequiredStorageStartup();
    final held = Completer<void>();
    var lateContinuation = 0;
    await expectLater(
      phase.ensure(
        isCurrent: () => true,
        loadTimeout: const Duration(milliseconds: 1),
        run: (load) async {
          await load(() => held.future);
          lateContinuation++;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(phase.ready, isFalse);
    await phase.ensure(isCurrent: () => true, run: (load) => load(() async {}));
    held.complete();
    await Future<void>.delayed(Duration.zero);
    expect(phase.ready, isTrue);
    expect(lateContinuation, 0);
  });

  test('unavailable context does not execute storage', () async {
    final phase = RequiredStorageStartup();
    var calls = 0;
    await expectLater(
      phase.ensure(
        isCurrent: () => false,
        run: (load) async {
          calls++;
        },
      ),
      throwsStateError,
    );
    expect(calls, 0);
    expect(phase.ready, isFalse);
    expect(phase.failed, isTrue);
  });

  test('observers see shared failure and recovery from any caller', () async {
    final phase = RequiredStorageStartup();
    addTearDown(phase.dispose);
    final states = <(bool, bool, bool)>[];
    phase.addListener(
      () => states.add((phase.ready, phase.busy, phase.failed)),
    );
    final failed = Completer<void>();
    Future<void> attempt() => phase.ensure(
      isCurrent: () => true,
      run: (load) => load(() => failed.future),
    );
    final first = attempt();
    final second = attempt();
    expect(identical(first, second), isTrue);
    final rejected = expectLater(first, throwsFormatException);
    failed.completeError(const FormatException('synthetic storage'));
    await rejected;
    expect(states, [(false, true, false), (false, false, true)]);
    await phase.ensure(isCurrent: () => true, run: (load) => load(() async {}));
    expect(states, [
      (false, true, false),
      (false, false, true),
      (false, true, false),
      (true, false, false),
    ]);
  });

  test('obsolete completion does not notify a newer ready phase', () async {
    final phase = RequiredStorageStartup();
    addTearDown(phase.dispose);
    final oldLoad = Completer<void>();
    final old = phase.ensure(
      isCurrent: () => true,
      run: (load) => load(() => oldLoad.future),
    );
    final rejected = expectLater(old, throwsStateError);
    phase.invalidate();
    await phase.ensure(isCurrent: () => true, run: (load) => load(() async {}));
    var changes = 0;
    phase.addListener(() => changes++);
    oldLoad.complete();
    await rejected;
    expect(changes, 0);
    expect(phase.ready, isTrue);
    expect(phase.busy, isFalse);
    expect(phase.failed, isFalse);
  });
}
