import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

void main() {
  late AppLocale savedLocale;

  setUp(() {
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(savedLocale));

  test(
    'PomodoroConfig persists auto DND preference and defaults old data off',
    () {
      final config = PomodoroConfig(
        autoEnableDnd: true,
        strictFocusMode: true,
        monitorDistractingApps: true,
        distractingAppPackages: ['com.tencent.mm', 'com.ss.android.ugc.aweme'],
        focusRoomId: 'deep_work_room',
        focusSoundVolume: 0.8,
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
      expect(json['focusSoundVolume'], 0.8);

      final restored = PomodoroConfig.fromJson(json);
      expect(restored.autoEnableDnd, isTrue);
      expect(restored.strictFocusMode, isTrue);
      expect(restored.monitorDistractingApps, isTrue);
      expect(restored.distractingAppPackages, [
        'com.tencent.mm',
        'com.ss.android.ugc.aweme',
      ]);
      expect(restored.focusRoomId, 'deep_work_room');
      expect(restored.focusSoundVolume, 0.8);

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
      expect(legacy.focusSoundVolume, PomodoroConfig.defaultFocusSoundVolume);
    },
  );

  test('PomodoroConfig clamps corrupted focus sound volume on restore', () {
    expect(
      PomodoroConfig.fromJson(<String, dynamic>{
        'focusSoundVolume': 0.2,
      }).focusSoundVolume,
      PomodoroConfig.defaultFocusSoundVolume,
    );
    expect(
      PomodoroConfig.fromJson(<String, dynamic>{
        'focusSoundVolume': 1.2,
      }).focusSoundVolume,
      PomodoroConfig.defaultFocusSoundVolume,
    );
    expect(
      PomodoroConfig.fromJson(<String, dynamic>{
        'focusSoundVolume': '0.6',
      }).focusSoundVolume,
      0.6,
    );
  });

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

  test(
    'PomodoroConfig migrates generated noise without dropping custom audio',
    () {
      final generated = PomodoroConfig.fromJson(<String, dynamic>{
        'whiteNoiseSound': 'brown_noise',
      });
      expect(generated.whiteNoiseSound, 'night_rain');

      final custom = PomodoroConfig.fromJson(<String, dynamic>{
        'whiteNoiseSound': 'custom:focus-loop',
      });
      expect(custom.whiteNoiseSound, 'custom:focus-loop');
    },
  );

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

  test(
    'penalty labels localize while legacy JSON stays Chinese and stable',
    () {
      final expected = <FocusPenaltyReason, List<String>>{
        FocusPenaltyReason.pause: ['暂停专注', 'Paused focus', 'pause'],
        FocusPenaltyReason.skip: ['跳过专注', 'Skipped focus', 'skip'],
        FocusPenaltyReason.reset: ['重置专注', 'Reset focus', 'reset'],
        FocusPenaltyReason.leaveApp: ['离开应用', 'Left the app', 'leaveApp'],
        FocusPenaltyReason.distractingApp: [
          '打开分心应用',
          'Opened a distracting app',
          'distractingApp',
        ],
      };
      final occurredAt = DateTime(2026, 5, 20, 9, 30);
      final penalties = [
        for (final reason in FocusPenaltyReason.values)
          PomodoroFocusPenalty(
            id: 'penalty-${reason.key}',
            occurredAt: occurredAt,
            reason: reason,
            affectedSeconds: 900,
            taskName: '阅读',
            tag: '学习',
            focusRoomId: 'deep_work_room',
            appPackage: 'com.example.synthetic',
          ),
      ];
      final jsonBeforeLocaleChange = [
        for (final penalty in penalties) jsonEncode(penalty.toJson()),
      ];
      const expectedJsonKeys = [
        'id',
        'occurredAt',
        'updatedAt',
        'reason',
        'reasonLabel',
        'affectedSeconds',
        'taskName',
        'tag',
        'focusRoomId',
        'appPackage',
      ];

      I18n.setLocale(AppLocale.zh);
      for (final entry in expected.entries) {
        expect(entry.key.labelFor(AppLocale.zh), entry.value[0]);
        expect(entry.key.label, entry.value[0]);
        expect(entry.key.key, entry.value[2]);
      }

      I18n.setLocale(AppLocale.en);
      for (var index = 0; index < FocusPenaltyReason.values.length; index++) {
        final reason = FocusPenaltyReason.values[index];
        final penalty = penalties[index];
        final json = penalty.toJson();

        expect(reason.labelFor(AppLocale.en), expected[reason]![1]);
        expect(reason.label, expected[reason]![1]);
        expect(reason.labelFor(AppLocale.zh), expected[reason]![0]);
        expect(reason.key, expected[reason]![2]);
        expect(I18n.current, AppLocale.en);
        expect(json.keys.toList(), expectedJsonKeys);
        expect(json['id'], 'penalty-${reason.key}');
        expect(json['occurredAt'], '2026-05-20T09:30:00.000');
        expect(json['updatedAt'], '2026-05-20T09:30:00.000');
        expect(json['reason'], expected[reason]![2]);
        expect(json['reasonLabel'], expected[reason]![0]);
        expect(json['affectedSeconds'], 900);
        expect(json['taskName'], '阅读');
        expect(json['tag'], '学习');
        expect(json['focusRoomId'], 'deep_work_room');
        expect(json['appPackage'], 'com.example.synthetic');
        expect(jsonEncode(json), jsonBeforeLocaleChange[index]);
      }

      expect(FocusPenaltyReason.values.map((reason) => reason.index).toList(), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(FocusPenaltyReason.values.map((reason) => reason.key).toList(), [
        'pause',
        'skip',
        'reset',
        'leaveApp',
        'distractingApp',
      ]);
    },
  );
}
