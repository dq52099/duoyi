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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/priority_theme_fixture.dart';

final _day = DateTime(2030, 6, 29);

class _RecordingTodos extends TodoProvider {
  final item = TodoItem(
    id: 'lane-todo',
    title: 'Drag task',
    date: _day,
    dueDate: DateTime(2030, 6, 29, 9),
  );
  final updates = <TodoItem>[];
  final reminderWaits = <bool>[];

  @override
  List<TodoItem> get todos => [item];

  @override
  Future<TodoMutationResult> updateTodoWithResult(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    expect(id, item.id);
    updates.add(updated);
    reminderWaits.add(waitForReminderSync);
    return const TodoMutationResult(saved: true);
  }
}

class _Calendar extends CalendarProvider {
  _Calendar({required this.longNeighbor});
  final bool longNeighbor;

  @override
  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) => [
    for (var index = 0; index < 4; index++)
      CalendarEvent(
        id: 'lane-$index',
        sourceId: index == 0 ? 'lane-todo' : null,
        title: index == 0
            ? 'Drag task'
            : index == 1 && longNeighbor
            ? List.filled(200, 'Very long user title').join(' ')
            : 'Other $index',
        date: _day,
        time: const TimeOfDay(hour: 9, minute: 0),
        endDate: DateTime(2030, 6, 29, 9, 45),
        type: index == 0 ? CalendarEventType.todo : CalendarEventType.event,
        color: Colors.blue,
      ),
  ];
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final longTitle in [false, true]) {
        testWidgets(
          'timeline lanes preserve Todo drag $brand ${locale.name} long=$longTitle',
          (tester) async {
            final todos = _RecordingTodos();
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
              size: const Size(320, 844),
              scale: 2,
              home: MultiProvider(
                providers: [
                  ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
                  ChangeNotifierProvider(create: (_) => CourseProvider()),
                  ChangeNotifierProvider(create: (_) => DiaryProvider()),
                  ChangeNotifierProvider<TodoProvider>(create: (_) => todos),
                  ChangeNotifierProvider<CalendarProvider>(
                    create: (_) => _Calendar(longNeighbor: longTitle),
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
            final title = find.byKey(
              const ValueKey('calendar-compact-title-lane-0'),
            );
            Future<Offset> revealTitle() async {
              await Scrollable.ensureVisible(tester.element(title));
              await tester.pumpAndSettle();
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: title, matching: find.byType(RichText)),
              );
              final boxes = paragraph.getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 9),
              );
              expect(boxes, isNotEmpty);
              return paragraph.localToGlobal(boxes.first.toRect().center);
            }

            final start = await revealTitle();
            final horizontal = Scrollable.maybeOf(
              tester.element(title),
              axis: Axis.horizontal,
            );
            expect(horizontal, isNotNull);
            expect(horizontal!.position.maxScrollExtent, greaterThan(0));
            // A long preview in another lane must not create an enormous canvas.
            // The event title itself is synthetic and remains unchanged.
            if (longTitle) {
              expect(horizontal.position.maxScrollExtent, lessThan(4000));
            }
            final before = horizontal.position.pixels;
            await tester.dragFrom(start, const Offset(-100, 0));
            await tester.pumpAndSettle();
            expect(horizontal.position.pixels, greaterThan(before));
            expect(todos.updates, isEmpty);

            final verticalStart = await revealTitle();
            // Resolve the gesture arena first: DragStartBehavior.start consumes
            // the initial slop movement rather than reporting it as an update.
            final gesture = await tester.startGesture(verticalStart);
            await gesture.moveBy(const Offset(0, 24));
            await tester.pump();
            await gesture.moveBy(const Offset(0, 48));
            await gesture.up();
            await tester.pumpAndSettle();
            expect(todos.updates, hasLength(1));
            expect(todos.updates.single.dueDate, DateTime(2030, 6, 29, 9, 30));
            expect(todos.updates.single.id, todos.item.id);
            expect(todos.updates.single.title, todos.item.title);
            expect(todos.reminderWaits, [false]);
            expect(todos.item.dueDate, DateTime(2030, 6, 29, 9));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
