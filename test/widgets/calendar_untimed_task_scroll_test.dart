import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/calendar_day_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';

final _day = DateTime(2030, 6, 29);

class _UntimedTodos extends TodoProvider {
  final item = TodoItem(id: 'untimed-task', title: 'Untimed task', date: _day);
  final updates = <TodoItem>[];

  @override
  List<TodoItem> get todos => [item];

  @override
  Future<TodoMutationResult> updateTodoWithResult(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    updates.add(updated);
    return const TodoMutationResult(saved: true);
  }
}

class _UntimedCalendar extends CalendarProvider {
  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) => [
    CalendarEvent(
      id: 'untimed-calendar-event',
      sourceId: 'untimed-task',
      title: 'Untimed task',
      date: _day,
      type: CalendarEventType.todo,
      color: Colors.blue,
    ),
  ];
}

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets(
        'scrolling untimed task preserves its date $brand ${locale.name}',
        (tester) async {
          final todos = _UntimedTodos();
          final auth = AuthProvider(
            client: ApiClient(
              baseUrl: 'https://duoyi.test',
              httpClient: MockClient(
                (_) async => fail('No fixture HTTP allowed'),
              ),
            ),
          );
          await mountPriorityFixture(
            tester,
            auth: auth,
            brand: brand,
            locale: locale,
            size: const Size(390, 844),
            scale: 1,
            home: MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
                ChangeNotifierProvider(create: (_) => CourseProvider()),
                ChangeNotifierProvider(create: (_) => DiaryProvider()),
                ChangeNotifierProvider<TodoProvider>(create: (_) => todos),
                ChangeNotifierProvider<CalendarProvider>(
                  create: (_) => _UntimedCalendar(),
                ),
              ],
              child: BrandRouteSurface(
                remountOnLocaleChange: false,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => CalendarDayAgenda(
                      date: _day,
                      calendarProvider: context.read<CalendarProvider>(),
                    ),
                  ),
                ),
              ),
            ),
          );
          final task = find.text('Untimed task');
          await tester.ensureVisible(task);
          await tester.pumpAndSettle();
          expect(todos.item.dueDate, isNull);
          await tester.drag(task, const Offset(0, -72));
          await tester.pumpAndSettle();
          final directory =
              Platform.environment['DUOYI_SECONDARY_MEASUREMENTS'];
          if (directory != null) {
            final file = File('$directory/untimed-$brand-${locale.name}.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({
                'originalDueDate': todos.item.dueDate?.toIso8601String(),
                'updates': [
                  for (final item in todos.updates)
                    {'dueDate': item.dueDate?.toIso8601String()},
                ],
              }),
            );
          }
          expect(
            todos.updates,
            isEmpty,
            reason:
                'Scrolling an all-day task must not create a timed deadline',
          );
          expect(todos.item.dueDate, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
