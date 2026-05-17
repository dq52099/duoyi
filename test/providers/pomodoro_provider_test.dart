import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'deleteSession removes focus history and paired time audit entry',
    () async {
      final now = DateTime.now();
      final session = PomodoroSession(
        id: 'focus-session-1',
        startTime: DateTime(now.year, now.month, now.day, 9),
        endTime: DateTime(now.year, now.month, now.day, 9, 25),
        durationSeconds: 1500,
        type: PomodoroType.focus,
        taskName: '阅读',
      );
      final todayKey = '${now.year}-${now.month}-${now.day}';
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pomodoro_sessions': jsonEncode(<Map<String, dynamic>>[
          session.toJson(),
        ]),
        'pomodoro_count_today': 1,
        'pomodoro_last_date': todayKey,
      });

      final audit = TimeAuditProvider();
      await audit.loadFromStorage();
      await audit.recordPomodoroSession(
        sessionId: session.id,
        title: session.taskName!,
        startAt: session.startTime,
        endAt: session.endTime,
      );

      final provider = PomodoroProvider()..attachTimeAudit(audit);
      await provider.loadFromStorage();

      expect(provider.sessions.single.id, session.id);
      expect(provider.sessionCountToday, 1);
      expect(audit.entries.single.sourceId, session.id);

      final deleted = await provider.deleteSession(session.id);

      expect(deleted, isTrue);
      expect(provider.sessions, isEmpty);
      expect(provider.sessionCountToday, 0);
      expect(audit.entries, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('pomodoro_sessions')!) as List;
      expect(stored, isEmpty);
    },
  );
}
