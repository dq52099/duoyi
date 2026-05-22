import 'dart:io';

import 'package:test/test.dart';

void main() {
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
}
