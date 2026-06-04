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
    final activeTimerBranch = provider.substring(
      provider.indexOf('if (_timer?.isActive ?? false)'),
      provider.indexOf(
        'return;',
        provider.indexOf('if (_timer?.isActive ?? false)'),
      ),
    );
    expect(activeTimerBranch, contains('unawaited(_syncSoundToState());'));
    expect(activeTimerBranch, contains('_syncDndToState();'));
    expect(activeTimerBranch, contains('_syncDistractionMonitorToState();'));
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

  test('white-noise changes preview at full focus volume when idle', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains(
        'Future<bool> setWhiteNoiseSound(String sound, {bool preview = true})',
      ),
    );
    expect(provider, isNot(contains('_soundPreviewGeneration')));
    expect(provider, contains('if (preview &&'));
    expect(provider, contains('normalized != FocusSoundCatalog.none'));
    expect(provider, contains('!_state.isRunning'));
    expect(provider, contains('_previewWhiteNoiseSound(normalized)'));
    expect(provider, contains('Future<bool> _previewWhiteNoiseSound'));
    expect(provider, contains('Future<bool> _syncSoundToState()'));
    expect(provider, contains('return _sound.preview(sound)'));
    expect(provider, contains('Future<bool> _playFocusSound(String sound)'));
    expect(provider, contains('_state.isRunning'));
    final setter = provider.substring(
      provider.indexOf(
        'Future<bool> setWhiteNoiseSound(String sound, {bool preview = true})',
      ),
      provider.indexOf('Future<bool> setFocusSoundVolume('),
    );
    expect(setter, contains('final playbackOk = await _syncSoundToState();'));
    expect(
      setter,
      matches(RegExp(r'if\s*\(\s*!playbackOk\s*&&\s*_state\.isRunning')),
    );
    expect(
      setter,
      contains('_config.whiteNoiseSound = FocusSoundCatalog.none;'),
    );
    expect(setter, isNot(contains('return _playFocusSound(normalized);')));
    expect(
      provider,
      contains('await _sound.setVolume(_config.focusSoundVolume)'),
    );
    expect(provider, contains('return _sound.play(sound)'));

    final service = File(
      'lib/services/focus_sound_service.dart',
    ).readAsStringSync();
    expect(service, contains('static const double defaultVolume = 1.0'));
    expect(service, contains('Future<bool> play(String sound)'));
    expect(service, contains('Future<bool> preview('));
    expect(service, contains('Future<void>.delayed(duration).then'));
    expect(service, contains('return false;'));
    expect(service, contains('if (assets.isEmpty)'));
    expect(
      service,
      contains('assets.map(AssetSource.new).toList(growable: false)'),
    );
  });

  test('focus sound volume setting previews current or fallback sound', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();

    expect(provider, contains('Future<bool> setFocusSoundVolume('));
    expect(provider, contains('FocusSoundService.minimumAudibleVolume'));
    expect(provider, contains('_focusSoundPreviewFallback'));
    expect(provider, contains('FocusSoundCatalog.tracks.first.id'));
    expect(
      provider,
      contains('return _previewWhiteNoiseSound(_focusSoundPreviewFallback);'),
    );
    expect(screen, contains('ChoiceChip('));
    expect(screen, contains('.setFocusSoundVolume(value)'));
    expect(screen, contains('点击声音会自动试听，也可以先点试听确认音量。'));
    expect(screen, contains('final VoidCallback? onPreview;'));
    expect(screen, contains("tooltip: '试听'"));
    expect(screen, contains('onPreview: () async'));
    expect(screen, contains('专注声音试听启动失败，请检查系统音量或音频资源'));
  });

  test('goal focus noise choices preview and report failures', () {
    final goalEdit = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();

    expect(
      goalEdit,
      contains("import '../services/focus_sound_service.dart';"),
    );
    expect(goalEdit, contains('Future<void> _pickFocusNoise(String id)'));
    expect(
      goalEdit,
      contains('context.read<PomodoroProvider?>()?.config.focusSoundVolume'),
    );
    expect(goalEdit, contains('FocusSoundService.defaultVolume'));
    expect(goalEdit, contains('FocusSoundService.instance.preview(id)'));
    expect(goalEdit, contains('专注声音预览启动失败'));
    expect(goalEdit, contains('onPickNoise: _pickFocusNoise'));
  });

  test('editing focus session sound also previews without saving globally', () {
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final editorStart = screen.indexOf(
      'Future<void> showPomodoroSessionEditor',
    );
    final screenStart = screen.indexOf('class PomodoroScreen', editorStart);
    expect(editorStart, greaterThanOrEqualTo(0));
    expect(screenStart, greaterThan(editorStart));
    final editor = screen.substring(editorStart, screenStart);

    expect(screen, contains("import '../services/focus_sound_service.dart';"));
    expect(editor, contains('Future<void> previewSound(String value)'));
    expect(editor, contains('setSt(() => selectedSound = value)'));
    expect(editor, contains('FocusSoundService.instance.stop()'));
    expect(editor, contains('provider.config.focusSoundVolume'));
    expect(editor, contains('FocusSoundService.instance.preview(value)'));
    expect(editor, contains('专注声音预览启动失败'));
    expect(editor, contains('previewSound(value ?? FocusSoundCatalog.none)'));
    expect(editor, isNot(contains('provider.setWhiteNoiseSound(')));
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
