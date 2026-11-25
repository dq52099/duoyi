import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/today_ui_copy.dart';
import '../providers/calendar_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/widget_launch_access.dart';
import '../services/widget_schedule_detail.dart';
import '../widgets/calendar_event_sheet.dart';
import '../widgets/surface_components.dart';

/// Opens an already hydrated and authorized widget object in its existing sheet.
Future<void> openWidgetScheduleDetail(
  BuildContext context,
  Uri uri,
  WidgetLaunchAccess access,
) async {
  if (!context.mounted ||
      !access.canProceed ||
      widgetScheduleDetailId(uri) == null) {
    return;
  }
  final calendar = context.read<CalendarProvider>();
  final pomodoro = context.read<PomodoroProvider>();
  final generation = AccountLocalDataCleaner.accountDataGeneration;
  final storageGeneration = pomodoro.storageGeneration;
  access.markInteractionPresented();
  await showAppModalSheet<void>(
    context: context,
    builder: (_) => _ScheduleDetail(
      uri: uri,
      calendar: calendar,
      pomodoro: pomodoro,
      accountGeneration: generation,
      sessionStorageGeneration: storageGeneration,
    ),
  );
}

class _ScheduleDetail extends StatelessWidget {
  const _ScheduleDetail({
    required this.uri,
    required this.calendar,
    required this.pomodoro,
    required this.accountGeneration,
    required this.sessionStorageGeneration,
  });

  final Uri uri;
  final CalendarProvider calendar;
  final PomodoroProvider pomodoro;
  final int accountGeneration;
  final int sessionStorageGeneration;

  @override
  Widget build(BuildContext context) {
    final currentCalendar = uri.host == 'event'
        ? context.watch<CalendarProvider>()
        : calendar;
    final currentPomodoro = uri.host == 'pomodoro'
        ? context.watch<PomodoroProvider>()
        : pomodoro;
    return ListenableBuilder(
      listenable: Listenable.merge([
        I18n.localeListenable,
        AccountLocalDataCleaner.accountDataGenerationListenable,
        uri.host == 'event' ? calendar : pomodoro,
      ]),
      builder: (context, _) {
        final sourceChanged =
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              accountGeneration,
            ) ||
            !identical(currentCalendar, calendar) ||
            !identical(currentPomodoro, pomodoro) ||
            (uri.host == 'pomodoro' &&
                pomodoro.storageGeneration != sessionStorageGeneration);
        final event = sourceChanged
            ? null
            : widgetScheduleDetailEvent(
                uri,
                localEvents: calendar.localEvents,
                sessions: pomodoro.sessions,
                colorScheme: Theme.of(context).colorScheme,
              );
        if (event != null) {
          return CalendarEventSheet(
            event: event,
            accountGeneration: accountGeneration,
          );
        }
        final route = ModalRoute.of(context);
        return AppModalSheet(
          title: TodayUiCopy.detailTitle('events'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                sourceChanged
                    ? TodayUiCopy.detailSourceChanged
                    : TodayUiCopy.detailMissing('events'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (!context.mounted) return;
                  final currentRoute = ModalRoute.of(context);
                  if (route == null ||
                      !route.isActive ||
                      !route.isCurrent ||
                      !identical(currentRoute, route)) {
                    return;
                  }
                  (route.navigator ?? Navigator.of(context)).pop();
                },
                child: Text(I18n.tr('action.close')),
              ),
            ],
          ),
        );
      },
    );
  }
}
