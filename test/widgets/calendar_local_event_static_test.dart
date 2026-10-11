import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('CalendarEvent supports persisted user-created schedule events', () {
    final model = File('lib/models/calendar_event.dart').readAsStringSync();
    final provider = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(model, contains('event,'));
    expect(model, contains("CalendarEventType.event => I18n.tr"));
    expect(model, contains('final String? note'));
    expect(model, contains('Map<String, dynamic> toJson()'));
    expect(model, contains('factory CalendarEvent.fromJson'));
    expect(model, contains("'type': type.name"));
    expect(model, contains("'note': note"));

    expect(
      provider,
      contains("_localEventsKey = 'duoyi_local_calendar_events_v1'"),
    );
    expect(provider, contains('List<CalendarEvent> get localEvents'));
    expect(provider, contains('Future<void> loadFromStorage()'));
    expect(provider, contains('Future<void> addLocalEvent'));
    expect(provider, contains('Future<void> updateLocalEvent'));
    expect(provider, contains('Future<void> deleteLocalEvent'));
    expect(provider, contains('localEventReminderCanceller'));
    expect(provider, contains('await _cancelLocalEventReminder(event.id);'));
    expect(provider, contains('await _cancelLocalEventReminder(id);'));
    expect(provider, contains('await localEventReminderCanceller?.call(id);'));
    expect(provider, contains('local event reminder cancel failed'));
    expect(main, contains('calendarProvider.localEventReminderCanceller'));
    expect(main, contains('notificationService.cancelCalendarReminder'));
    expect(provider, contains('..addAll(_localEvents)'));
    expect(provider, contains('_hashCalendarEvents(_localEvents)'));
  });

  test('Calendar UI exposes local all-day and multi-day event editing', () {
    final screen = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final sheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();

    expect(
      screen,
      contains('title: Text(CalendarUiCopy.quickAddNewEventTitle)'),
    );
    expect(screen, contains('showLocalCalendarEventEditor('));
    expect(screen, contains('initialDate: _selectedDay'));
    expect(screen, contains('workspaceId: origin.activeWorkspaceId'));

    expect(sheet, contains('Future<void> showLocalCalendarEventEditor'));
    expect(
      sheet,
      contains(
        'CalendarEventSheetUiCopy.editorTitle(isEditing: event != null)',
      ),
    );
    expect(sheet, contains('SwitchListTile('));
    expect(sheet, contains('title: Text(CalendarEventSheetUiCopy.allDay)'));
    expect(sheet, contains("titleKey: 'calendar.picker.start_date'"));
    expect(sheet, contains("titleKey: 'calendar.picker.end_date'"));
    expect(sheet, contains('if (!allDay)'));
    expect(sheet, contains('_normalizeLocalEventTime('));
    expect(
      sheet,
      contains('DateTime(endDate.year, endDate.month, endDate.day + 1)'),
    );
    expect(sheet, contains('DateTime(end.year, end.month, end.day - 1)'));
    expect(sheet, contains('provider.addLocalEvent(next)'));
    expect(sheet, contains('provider.updateLocalEvent(next)'));
    expect(sheet, contains('CalendarEventType.event'));
    expect(sheet, contains('_editLocalEvent(context)'));
    expect(sheet, contains('deleteLocalEvent('));
    expect(sheet, contains('widget.event.id,'));
  });

  test('Calendar separates shell and standalone route backgrounds', () {
    final screen = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(screen, contains('final bool useShellBackground'));
    expect(screen, contains('this.useShellBackground = false'));
    expect(screen, contains('paintBackground: !widget.useShellBackground'));
    expect(screen, contains('backgroundColor: widget.useShellBackground'));
    expect(
      main,
      contains('CalendarScreen(key: calendarKey, useShellBackground: true)'),
    );
  });
}
