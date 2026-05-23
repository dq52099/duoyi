import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

void main() {
  test(
    'PomodoroConfig persists auto DND preference and defaults old data off',
    () {
      final config = PomodoroConfig(
        autoEnableDnd: true,
        strictFocusMode: true,
        monitorDistractingApps: true,
        distractingAppPackages: ['com.tencent.mm', 'com.ss.android.ugc.aweme'],
        focusRoomId: 'deep_work_room',
      );

      final json = config.toJson();
      expect(json['autoEnableDnd'], isTrue);
      expect(json['strictFocusMode'], isTrue);
      expect(json['monitorDistractingApps'], isTrue);
      expect(json['distractingAppPackages'], [
        'com.tencent.mm',
        'com.ss.android.ugc.aweme',
      ]);
      expect(json['focusRoomId'], 'deep_work_room');

      final restored = PomodoroConfig.fromJson(json);
      expect(restored.autoEnableDnd, isTrue);
      expect(restored.strictFocusMode, isTrue);
      expect(restored.monitorDistractingApps, isTrue);
      expect(restored.distractingAppPackages, [
        'com.tencent.mm',
        'com.ss.android.ugc.aweme',
      ]);
      expect(restored.focusRoomId, 'deep_work_room');

      final legacy = PomodoroConfig.fromJson(<String, dynamic>{
        'focusDuration': 1500,
        'shortBreakDuration': 300,
        'longBreakDuration': 900,
        'sessionsPerLongBreak': 4,
        'whiteNoiseSound': 'rain',
      });
      expect(legacy.autoEnableDnd, isFalse);
      expect(legacy.strictFocusMode, isFalse);
      expect(legacy.monitorDistractingApps, isFalse);
      expect(legacy.distractingAppPackages, isEmpty);
      expect(legacy.focusRoomId, isNull);
    },
  );

  test('PomodoroConfig clamps corrupted stored durations on restore', () {
    final restored = PomodoroConfig.fromJson(<String, dynamic>{
      'focusDuration': 0,
      'shortBreakDuration': '1',
      'longBreakDuration': 999999999,
      'sessionsPerLongBreak': 0,
    });

    expect(restored.focusDuration, PomodoroConfig.defaultFocusDuration);
    expect(
      restored.shortBreakDuration,
      PomodoroConfig.defaultShortBreakDuration,
    );
    expect(restored.longBreakDuration, PomodoroConfig.defaultLongBreakDuration);
    expect(restored.sessionsPerLongBreak, 4);
  });

  test('PomodoroSession persists focus room attribution', () {
    final session = PomodoroSession(
      id: 'session-1',
      startTime: DateTime(2026, 5, 18, 9),
      endTime: DateTime(2026, 5, 18, 9, 25),
      durationSeconds: 1500,
      type: PomodoroType.focus,
      focusRoomId: 'deep_work_room',
    );

    final json = session.toJson();
    expect(json['focusRoomId'], 'deep_work_room');

    final restored = PomodoroSession.fromJson(json);
    expect(restored.focusRoomId, 'deep_work_room');
  });

  test('PomodoroSession copyWith supports field updates and clearing', () {
    final session = PomodoroSession(
      id: 'session-1',
      startTime: DateTime(2026, 5, 18, 9),
      endTime: DateTime(2026, 5, 18, 9, 25),
      durationSeconds: 1500,
      type: PomodoroType.focus,
      taskName: '阅读',
      whiteNoiseSound: 'rain',
      tag: '学习',
      focusRoomId: 'deep_work_room',
    );

    final updated = session.copyWith(
      startTime: DateTime(2026, 5, 18, 10),
      durationSeconds: 2700,
      whiteNoiseSound: 'forest',
      clearTaskName: true,
      clearTag: true,
      clearFocusRoomId: true,
    );

    expect(updated.startTime, DateTime(2026, 5, 18, 10));
    expect(updated.durationSeconds, 2700);
    expect(updated.whiteNoiseSound, 'forest');
    expect(updated.taskName, isNull);
    expect(updated.tag, isNull);
    expect(updated.focusRoomId, isNull);
  });

  test('PomodoroFocusPenalty persists reason and affected context', () {
    final penalty = PomodoroFocusPenalty(
      id: 'penalty-1',
      occurredAt: DateTime(2026, 5, 20, 9, 30),
      reason: FocusPenaltyReason.leaveApp,
      affectedSeconds: 900,
      taskName: '阅读',
      tag: '学习',
      focusRoomId: 'deep_work_room',
      appPackage: 'com.tencent.mm',
    );

    final json = penalty.toJson();
    expect(json['reason'], 'leaveApp');
    expect(json['reasonLabel'], '离开应用');
    expect(json['updatedAt'], '2026-05-20T09:30:00.000');
    expect(json['appPackage'], 'com.tencent.mm');

    final restored = PomodoroFocusPenalty.fromJson(json);
    expect(restored.reason, FocusPenaltyReason.leaveApp);
    expect(restored.affectedSeconds, 900);
    expect(restored.taskName, '阅读');
    expect(restored.tag, '学习');
    expect(restored.focusRoomId, 'deep_work_room');
    expect(restored.appPackage, 'com.tencent.mm');
  });

  test('Distracting app penalty reason has stable key and label', () {
    expect(FocusPenaltyReason.distractingApp.key, 'distractingApp');
    expect(FocusPenaltyReason.distractingApp.label, '打开分心应用');
    expect(
      FocusPenaltyReasonX.fromKey('distractingApp'),
      FocusPenaltyReason.distractingApp,
    );
  });
}
