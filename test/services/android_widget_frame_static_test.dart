import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _nativeRoot = 'android/app/src/main/kotlin/com/duoyi/duoyi/';

String _source(String name) => File('$_nativeRoot$name.kt').readAsStringSync();

void main() {
  test('all eleven actual renderers submit through captured frames', () {
    const providers = [
      'DuoyiWidgetProvider',
      'DuoyiTodoWidgetProvider',
      'DuoyiHabitWidgetProvider',
      'DuoyiFocusHabitWidgetProvider',
      'DuoyiCalendarWidgetProvider',
      'DuoyiAnniversaryWidgetProvider',
      'DuoyiGoalWidgetProvider',
      'DuoyiScheduleWidgetProvider',
      'DuoyiCourseWidgetProvider',
      'DuoyiNoteWidgetProvider',
      'DuoyiDiaryWidgetProvider',
    ];
    for (final name in providers) {
      final source = _source(name);
      expect(
        source,
        contains('DuoyiWidgetSnapshot.renderWidget('),
        reason: name,
      );
      expect(source, contains('val prefs = frame.prefs'), reason: name);
      expect(source, contains('DuoyiWidgetBuiltViews(views'), reason: name);
      expect(source, isNot(contains('updateAppWidget(')), reason: name);
      expect(source, isNot(contains('forDisplay(')), reason: name);
      expect(source, isNot(contains('getAppWidgetOptions(')), reason: name);
      expect(source, isNot(contains('actionUri(prefs,')), reason: name);
    }
  });

  test('snapshot initializes styles before reading the native publication', () {
    final source = _source('DuoyiWidgetSnapshot');
    expect(
      source,
      contains('saveForWidgetIfMissing(backing, id, initialStyle)'),
    );
    expect(
      source.indexOf('saveForWidgetIfMissing('),
      lessThan(source.indexOf('val read = store.read(nonBlocking = true)')),
    );
    expect(
      source,
      contains('Looper.myLooper() != android.os.Looper.getMainLooper()'),
    );
    expect(source, contains('read.envelope?.document?.toFlatValues()'));
    expect(source, contains('store.acceptSnapshot(read.envelope)'));
    expect(source, contains('frame.core.rejectionReason(values(latest'));
    expect(source, contains('manager.updateAppWidget(id, built.views)'));
    expect(source, contains('if (!accepted) return@repeat'));
    expect(source, isNot(contains('SharedPreferences by backing')));
    expect(source, isNot(contains('.putString(')));
    expect(source, isNot(contains('requestUpdateForAllWidgets(')));
  });

  test('raw values and dimensions are checked before any accepted effect', () {
    final source = _source('DuoyiWidgetFrameCore');
    expect(source, contains('rawValues != currentValues'));
    expect(source, contains('options != currentOptions'));
    expect(source, contains('clock.zone != currentClock.zone'));
    expect(source, contains('clock.day != currentClock.day'));
    expect(
      source,
      contains('clock.offsetMinutes != currentClock.offsetMinutes'),
    );
    expect(source, contains('systemLocaleTag != currentSystemLocaleTag'));
    expect(source, contains('return "timer_expired"'));
    expect(source, contains('repeat(2)'));
    expect(
      source.indexOf('commit(views)'),
      lessThan(source.indexOf('acceptedEffect(frame, views)')),
    );
  });

  test('frozen preferences cover all reads and deny generic editing', () {
    final source = _source('DuoyiFrozenWidgetPreferences');
    for (final method in [
      'getAll',
      'contains',
      'getString',
      'getStringSet',
      'getInt',
      'getLong',
      'getFloat',
      'getBoolean',
      'edit',
    ]) {
      expect(source, contains('override fun $method('));
    }
    expect(source, contains('DuoyiWidgetFrameCore.immutableValues(values)'));
    expect(source, contains('throw UnsupportedOperationException('));
    expect(source, isNot(contains('backing')));
    final projection = _source('DuoyiWidgetRenderFrame');
    expect(projection, contains('!core.sessionTrusted'));
    expect(projection, contains('it.startsWith("focus_timer_")'));
    expect(projection, isNot(contains('endsWith("_id")')));
  });

  test(
    'focus uses frozen clock values and defers its existing alarm effect',
    () {
      final source = _source('DuoyiFocusHabitWidgetProvider');
      expect(source, contains('val now = frame.wallMillis'));
      expect(source, contains('val base = frame.elapsedMillis'));
      expect(source, contains('-(now - startedAt).coerceAtLeast(0L)'));
      expect(
        source,
        contains('currentTimerRemainingSeconds(prefs, timerRunning, now)'),
      );
      expect(
        source,
        contains('DuoyiWidgetBuiltViews(views, timerAlarmEffect)'),
      );
      expect(
        source,
        contains('val timerAlarmEffect: (() -> Unit)? = if (sessionTrusted)'),
      );
      expect(source, contains('} else null'));
      expect(source, contains('getBroadcast(context, 14101'));
      expect(source, isNot(contains('SystemClock.elapsedRealtime()')));
      expect(source, isNot(contains('Date()')));
    },
  );

  test('all mutation entry points require the captured fresh session', () {
    expect(_source('DuoyiWidgetSnapshot'), contains('require(frame.fresh)'));
    expect(
      _source('DuoyiWidgetProvider'),
      contains('if (frame.fresh) DuoyiWidgetSnapshot.actionUri(frame,'),
    );
    expect(
      _source('DuoyiTodoWidgetProvider'),
      contains('if (!frame.fresh || todoId.isBlank())'),
    );
    expect(
      _source('DuoyiHabitWidgetProvider'),
      contains('if (frame.fresh && habitQuickCheckId.isNotBlank())'),
    );
    expect(
      _source('DuoyiFocusHabitWidgetProvider'),
      contains('if (frame.fresh && !storedRunning)'),
    );
  });
}
