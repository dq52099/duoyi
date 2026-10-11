import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'today focus sessions use the start civil day and preserve state',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);

      final midnightFocus = _session(
        id: 'focus-at-midnight',
        start: DateTime(2026, 6, 14),
        end: DateTime(2026, 6, 14, 0, 25),
        type: PomodoroType.focus,
      );
      final daytimeFocus = _session(
        id: 'focus-during-day',
        start: DateTime(2026, 6, 14, 10),
        end: DateTime(2026, 6, 14, 10, 25),
        type: PomodoroType.focus,
      );
      final overnightFocus = _session(
        id: 'focus-started-yesterday',
        start: DateTime(2026, 6, 13, 23, 40),
        end: DateTime(2026, 6, 14, 0, 5),
        type: PomodoroType.focus,
      );
      final todayBreak = _session(
        id: 'break-during-day',
        start: DateTime(2026, 6, 14, 12),
        end: DateTime(2026, 6, 14, 12, 5),
        type: PomodoroType.shortBreak,
      );
      final tomorrowFocus = _session(
        id: 'focus-started-tomorrow',
        start: DateTime(2026, 6, 15),
        end: DateTime(2026, 6, 15, 0, 25),
        type: PomodoroType.focus,
      );
      final seededSessions = [
        midnightFocus,
        daytimeFocus,
        overnightFocus,
        todayBreak,
        tomorrowFocus,
      ];
      await provider.debugAddSessionsForTest(seededSessions);

      final sessionsList = provider.sessions;
      final sessionsBefore = List<PomodoroSession>.of(sessionsList);
      final stateBefore = provider.state;
      final persistedRevisionBefore = provider.persistedRevision;
      final countTodayBefore = provider.sessionCountToday;
      var notifications = 0;
      provider.addListener(() => notifications++);

      final focusSessions = withClock(
        Clock.fixed(DateTime(2026, 6, 14, 12, 30)),
        () => provider.todayFocusSessions,
      );

      expect(focusSessions, hasLength(2));
      expect(identical(focusSessions[0], midnightFocus), isTrue);
      expect(identical(focusSessions[1], daytimeFocus), isTrue);
      expect(focusSessions, isNot(contains(overnightFocus)));
      expect(focusSessions, isNot(contains(todayBreak)));
      expect(focusSessions, isNot(contains(tomorrowFocus)));

      expect(identical(provider.sessions, sessionsList), isTrue);
      expect(provider.sessions, hasLength(sessionsBefore.length));
      for (var index = 0; index < sessionsBefore.length; index++) {
        expect(
          identical(provider.sessions[index], sessionsBefore[index]),
          isTrue,
        );
      }
      expect(identical(provider.state, stateBefore), isTrue);
      expect(provider.persistedRevision, persistedRevisionBefore);
      expect(provider.sessionCountToday, countTodayBefore);
      expect(notifications, 0);
    },
  );
}

PomodoroSession _session({
  required String id,
  required DateTime start,
  required DateTime end,
  required PomodoroType type,
}) => PomodoroSession(
  id: id,
  startTime: start,
  endTime: end,
  durationSeconds: 25 * 60,
  type: type,
);
