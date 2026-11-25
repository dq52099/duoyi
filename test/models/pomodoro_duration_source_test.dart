import 'dart:convert';

import 'package:duoyi/models/pomodoro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fresh duration inherits; an explicitly supplied 25 minutes does not',
    () {
      expect(PomodoroConfig().focusDurationUsesDefault, isTrue);
      expect(
        PomodoroConfig(focusDuration: 1500).focusDurationUsesDefault,
        isFalse,
      );
    },
  );

  for (final duration in [60, 1500, 2700, 43200, '1500']) {
    test('legacy valid duration $duration remains explicit', () {
      final restored = PomodoroConfig.fromJson({'focusDuration': duration});
      expect(restored.focusDurationUsesDefault, isFalse);
      expect(restored.focusDuration, int.parse('$duration'));
    });
  }

  for (final duration in [null, 0, -1, 43201, 'invalid']) {
    test('missing or invalid legacy duration $duration inherits', () {
      final restored = PomodoroConfig.fromJson({'focusDuration': duration});
      expect(restored.focusDurationUsesDefault, isTrue);
      expect(restored.focusDuration, 1500);
    });
  }

  for (final inherits in [true, false]) {
    test(
      'duration source $inherits survives the complete config round trip',
      () {
        final config = PomodoroConfig(
          focusDuration: 2700,
          focusDurationUsesDefault: inherits,
          shortBreakDuration: 600,
          longBreakDuration: 1200,
          whiteNoiseSound: 'rain',
          autoEnableDnd: true,
          strictFocusMode: true,
          monitorDistractingApps: true,
          distractingAppPackages: ['synthetic.app'],
          focusRoomId: 'synthetic-room',
          playSoundInBreak: true,
          updatedAt: DateTime(2026, 10, 14),
        );
        final payload = jsonDecode(jsonEncode(config.toJson()));
        final restored = PomodoroConfig.fromJson(
          Map<String, dynamic>.from(payload),
        );
        expect(restored.toJson(), config.toJson());
        expect(restored.focusDurationUsesDefault, inherits);
      },
    );
  }
}
