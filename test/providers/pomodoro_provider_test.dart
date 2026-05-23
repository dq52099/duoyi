import 'dart:io';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('PomodoroProvider updates and deletes paired time audit records', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final model = File('lib/models/pomodoro.dart').readAsStringSync();
    final audit = File(
      'lib/providers/time_audit_provider.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains('Future<bool> updateSession(PomodoroSession updated) async'),
    );
    expect(provider, contains('final previous = _sessions[idx];'));
    expect(provider, contains('_sessions[idx] = updated;'));
    expect(provider, contains('_affectsTodayFocusCount(previous)'));
    expect(provider, contains('_affectsTodayFocusCount(updated)'));
    expect(provider, contains('await _refreshTodayFocusMeta();'));
    expect(
      provider,
      contains(
        'final dedupeKey = TimeAuditProvider.pomodoroDedupeKey(updated.id);',
      ),
    );
    expect(provider, contains('await _timeAudit?.recordPomodoroSession('));
    expect(
      provider,
      contains('await _timeAudit?.deleteByDedupeKey(dedupeKey);'),
    );
    expect(provider, contains('await _saveSessions();'));
    expect(provider, contains('notifyListeners();'));

    expect(provider, contains('Future<bool> deleteSession(String id) async'));
    expect(provider, contains('await _timeAudit?.deleteByDedupeKey('));
    expect(provider, contains('TimeAuditProvider.pomodoroDedupeKey(id)'));
    expect(provider, contains('_sessionCountToday = _sessions'));

    expect(model, contains('PomodoroSession copyWith('));
    expect(model, contains('bool clearTaskName = false'));
    expect(model, contains('bool clearTag = false'));
    expect(model, contains('bool clearFocusRoomId = false'));

    expect(audit, contains('Future<void> recordPomodoroSession('));
    expect(audit, contains('dedupeKey: pomodoroDedupeKey(sessionId),'));
    expect(
      audit,
      contains('static String pomodoroDedupeKey(String sessionId)'),
    );
  });

  test('PomodoroProvider start/completion code guards timer handoff', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('if (_timer?.isActive ?? false)'));
    expect(provider, contains('final completedState = _state;'));
    expect(provider, contains('final completedType = completedState.type;'));
    expect(
      provider,
      contains(
        'final shouldAutoStartNext = completedType == PomodoroType.focus',
      ),
    );
    expect(provider, contains('? _config.autoStartBreaks'));
    expect(provider, contains(': _config.autoStartFocus'));
    expect(provider, contains('final lastDate = _lastDate ??= _todayKey();'));
    expect(provider, isNot(contains('_lastDate!')));
    expect(
      provider,
      isNot(
        contains(
          'isRunning: _config.autoStartBreaks || _config.autoStartFocus',
        ),
      ),
    );
  });

  test('startIfIdle does not create duplicate active timers', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(PomodoroConfig(focusDuration: 5));
    var listenerNotifications = 0;
    var timerTicks = 0;
    provider.addListener(() => listenerNotifications++);
    provider.timerTicks.addListener(() => timerTicks++);

    fakeAsync((async) {
      provider.startIfIdle();
      provider.startIfIdle();

      expect(provider.state.isRunning, isTrue);
      expect(async.periodicTimerCount, 1);
      expect(listenerNotifications, 1);

      async.elapse(const Duration(seconds: 1));
      expect(provider.state.remainingSeconds, 4);
      expect(async.periodicTimerCount, 1);
      expect(timerTicks, 1);
      expect(
        listenerNotifications,
        1,
        reason: 'second ticks must not rebuild the whole app shell',
      );

      provider.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
    'strict focus switch notifies before async persistence completes',
    () async {
      final provider = PomodoroProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      final future = provider.setStrictFocusMode(true);

      expect(provider.config.strictFocusMode, isTrue);
      expect(notifications, 1);

      await future;
      provider.dispose();
    },
  );

  test(
    'focus room selection is idempotent to avoid room-tab flicker',
    () async {
      final provider = PomodoroProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setFocusRoomId('deep_work_room');
      final firstRevision = provider.persistedRevision;

      await provider.setFocusRoomId('deep_work_room');

      expect(provider.state.focusRoomId, 'deep_work_room');
      expect(provider.config.focusRoomId, 'deep_work_room');
      expect(provider.persistedRevision, firstRevision);
      expect(notifications, 1);

      provider.dispose();
    },
  );

  test('focus completion auto-starts break only when enabled', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(
      PomodoroConfig(
        focusDuration: 1,
        shortBreakDuration: 5,
        autoStartBreaks: true,
        autoStartFocus: false,
      ),
    );

    fakeAsync((async) {
      provider.startIfIdle();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(provider.sessions, hasLength(1));
      expect(provider.sessions.single.type, PomodoroType.focus);
      expect(provider.state.type, PomodoroType.shortBreak);
      expect(provider.state.isRunning, isTrue);
      expect(provider.state.remainingSeconds, 5);
      expect(async.periodicTimerCount, 1);

      provider.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
    'manual focus start does not bounce into break when break auto-start is off',
    () async {
      final provider = PomodoroProvider();
      await provider.setConfig(
        PomodoroConfig(
          focusDuration: 1,
          shortBreakDuration: 5,
          autoStartBreaks: false,
          autoStartFocus: true,
        ),
      );

      fakeAsync((async) {
        provider.startIfIdle();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.sessions, hasLength(1));
        expect(provider.sessions.single.type, PomodoroType.focus);
        expect(provider.state.type, PomodoroType.shortBreak);
        expect(provider.state.isRunning, isFalse);
        expect(async.periodicTimerCount, 0);

        provider.dispose();
      });
    },
  );

  test('break completion auto-starts focus only when enabled', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(
      PomodoroConfig(
        focusDuration: 1,
        shortBreakDuration: 1,
        autoStartBreaks: false,
        autoStartFocus: true,
      ),
    );

    fakeAsync((async) {
      provider.startIfIdle();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(provider.state.type, PomodoroType.shortBreak);
      expect(provider.state.isRunning, isFalse);
      expect(async.periodicTimerCount, 0);

      provider.startIfIdle();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(provider.sessions, hasLength(2));
      expect(provider.sessions.last.type, PomodoroType.shortBreak);
      expect(provider.state.type, PomodoroType.focus);
      expect(provider.state.isRunning, isTrue);
      expect(provider.state.remainingSeconds, 1);
      expect(async.periodicTimerCount, 1);

      provider.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
    'break completion does not auto-start focus from stale autoStartBreaks flag',
    () async {
      final provider = PomodoroProvider();
      await provider.setConfig(
        PomodoroConfig(
          focusDuration: 1,
          shortBreakDuration: 1,
          autoStartBreaks: true,
          autoStartFocus: false,
        ),
      );

      fakeAsync((async) {
        provider.startIfIdle();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.state.type, PomodoroType.shortBreak);
        expect(provider.state.isRunning, isTrue);
        expect(async.periodicTimerCount, 1);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.sessions, hasLength(2));
        expect(provider.sessions.last.type, PomodoroType.shortBreak);
        expect(provider.state.type, PomodoroType.focus);
        expect(provider.state.isRunning, isFalse);
        expect(async.periodicTimerCount, 0);

        provider.dispose();
      });
    },
  );
}
