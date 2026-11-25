import 'package:flutter/material.dart';

import '../core/calendar_aggregator.dart';
import '../models/calendar_event.dart';
import '../models/pomodoro.dart';

/// Decodes one opaque identity after splitting the encoded URL path.
String? widgetScheduleDetailId(Uri uri) {
  if (uri.scheme != 'duoyi' ||
      !{'event', 'pomodoro'}.contains(uri.host) ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment) {
    return null;
  }
  try {
    final segments = uri.pathSegments;
    if (segments.length != 1 || segments.single.trim().isEmpty) return null;
    const keys = {
      'source',
      'widget_delivery',
      'widget_day',
      'widget_offset',
      'widget_account',
    };
    final parameters = uri.queryParametersAll;
    if (parameters.entries.any(
      (entry) => !keys.contains(entry.key) || entry.value.length != 1,
    )) {
      return null;
    }
    return segments.single;
  } on FormatException {
    return null;
  }
}

/// Resolves current owned objects, never a cached widget title or another item.
CalendarEvent? widgetScheduleDetailEvent(
  Uri uri, {
  required Iterable<CalendarEvent> localEvents,
  required List<PomodoroSession> sessions,
  required ColorScheme colorScheme,
}) {
  final id = widgetScheduleDetailId(uri);
  if (id == null) return null;
  if (uri.host == 'event') {
    for (final event in localEvents) {
      if (event.type == CalendarEventType.event && event.id == id) return event;
    }
    return null;
  }
  for (final session in sessions) {
    if (session.id == id && session.type == PomodoroType.focus) {
      return CalendarAggregator.buildEvents(
        todos: const [],
        habits: const [],
        pomodoroSessions: [session],
        colorScheme: colorScheme,
      ).single;
    }
  }
  return null;
}
