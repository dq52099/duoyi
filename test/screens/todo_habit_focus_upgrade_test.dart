import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/todo_filters.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';

class _Item {
  final String id;
  final String title;
  final String notes;
  final List<String> tags;
  final String? list;
  final DateTime? due;
  final int rank;
  final DateTime created;
  final int order;
  final bool done;

  _Item(
    this.id, {
    this.title = '',
    this.notes = '',
    this.tags = const <String>[],
    this.list,
    this.due,
    this.rank = 0,
    DateTime? created,
    this.order = 0,
    this.done = false,
  }) : created = created ?? DateTime(2026, 1, 1);
}

List<_Item> _filter(List<_Item> items, TodoFilterState<int, int> filter) {
  return filterTodos<_Item, int, int>(
    items,
    filter,
    now: DateTime(2026, 6, 1, 9),
    quadrantOf: (_) => 0,
    priorityOf: (t) => t.rank,
    tagsOf: (t) => t.tags,
    listGroupNameOf: (t) => t.list,
    dueDateOf: (t) => t.due,
    isCompletedOf: (t) => t.done,
    isArchivedAfterRolloverOf: (_) => false,
    titleOf: (t) => t.title,
    notesOf: (t) => t.notes,
  );
}

List<String> _sorted(List<_Item> items, TodoSortOrder order) {
  return sortTodos<_Item>(
    items,
    order,
    dueDateOf: (t) => t.due,
    priorityRankOf: (t) => t.rank,
    createdAtOf: (t) => t.created,
    sortOrderOf: (t) => t.order,
    isCompletedOf: (t) => t.done,
  ).map((t) => t.id).toList();
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Todo filters: search + sort', () {
    test('TodoFilterState stays backward compatible', () {
      const state = TodoFilterState<int, int>();
      expect(state.query, '');
      expect(state.sortOrder, TodoSortOrder.manual);
      expect(state.hasActiveFilters, isFalse);
      expect(state.copyWith(query: 'abc').hasActiveFilters, isTrue);
      expect(
        state.copyWith(sortOrder: TodoSortOrder.priority).sortOrder,
        TodoSortOrder.priority,
      );
      expect(state.copyWith(query: 'x').copyWith(tag: 'a').query, 'x');
    });

    test('text search matches title, notes, tags and list name', () {
      final items = [
        _Item('a', title: 'Write Report'),
        _Item('b', notes: 'remember the REPORT draft'),
        _Item('c', tags: const ['report']),
        _Item('d', list: 'Reporting'),
        _Item('e', title: 'Groceries'),
      ];
      final hits = _filter(
        items,
        const TodoFilterState<int, int>(query: '  report '),
      ).map((t) => t.id).toList();
      expect(hits, containsAll(<String>['a', 'b', 'c', 'd']));
      expect(hits, isNot(contains('e')));
      expect(
        _filter(items, const TodoFilterState<int, int>()).length,
        items.length,
      );
    });

    test('sortTodos orders by manual, due date, priority and created', () {
      final items = [
        _Item(
          'late',
          due: DateTime(2026, 6, 9),
          rank: 1,
          created: DateTime(2026, 1, 3),
          order: 2,
        ),
        _Item('none', rank: 3, created: DateTime(2026, 1, 1), order: 0),
        _Item(
          'soon',
          due: DateTime(2026, 6, 2),
          rank: 2,
          created: DateTime(2026, 1, 2),
          order: 1,
        ),
        _Item('done', due: DateTime(2026, 5, 1), rank: 3, done: true),
      ];
      expect(_sorted(items, TodoSortOrder.manual), [
        'late',
        'none',
        'soon',
        'done',
      ]);
      final byDue = _sorted(items, TodoSortOrder.dueDate);
      expect(byDue.take(3).toList(), ['soon', 'late', 'none']);
      expect(byDue.last, 'done');
      final byPriority = _sorted(items, TodoSortOrder.priority);
      expect(byPriority.first, 'none');
      expect(byPriority.last, 'done');
      final byCreated = _sorted(items, TodoSortOrder.created);
      expect(byCreated.last, 'done');
      expect(byCreated.toSet(), items.map((t) => t.id).toSet());
    });
  });

  group('TodoProvider batch reschedule / list / tag assign', () {
    Future<TodoProvider> seeded() async {
      final provider = TodoProvider();
      await provider.addTodo(TodoItem(id: 't1', title: 'one', tags: ['a']));
      await provider.addTodo(TodoItem(id: 't2', title: 'two'));
      await provider.addTodo(TodoItem(id: 't3', title: 'three'));
      return provider;
    }

    TodoItem byId(TodoProvider p, String id) =>
        p.todos.firstWhere((t) => t.id == id);

    test('rescheduleTodosDueDate sets and clears due dates', () async {
      final provider = await seeded();
      final due = DateTime(2030, 3, 4);
      final changed = await provider.rescheduleTodosDueDate(['t1', 't2'], due);
      expect(changed, 2);
      expect(byId(provider, 't1').dueDate, due);
      expect(byId(provider, 't2').dueDate, due);
      expect(byId(provider, 't3').dueDate, isNull);

      expect(await provider.rescheduleTodosDueDate(['t1'], null), 1);
      expect(byId(provider, 't1').dueDate, isNull);
      expect(await provider.rescheduleTodosDueDate(const <String>[], due), 0);
    });

    test('assignTodosListGroup moves and clears list membership', () async {
      final provider = await seeded();
      expect(await provider.assignTodosListGroup(['t1', 't3'], ' Work '), 2);
      expect(byId(provider, 't1').listGroupName, 'Work');
      expect(byId(provider, 't3').listGroupName, 'Work');
      expect(byId(provider, 't2').listGroupName, isNull);

      await provider.assignTodosListGroup(['t1'], '');
      expect(byId(provider, 't1').listGroupName, isNull);
    });

    test('assignTagsToTodos / updateTodosTags merge without duplicates', () async {
      final provider = await seeded();
      expect(await provider.assignTagsToTodos(['t1', 't2'], ['a', 'b']), 2);
      expect(byId(provider, 't1').tags, ['a', 'b']);
      expect(byId(provider, 't2').tags, ['a', 'b']);

      expect(
        await provider.updateTodosTags(['t1', 't2'], removeTags: ['a']),
        2,
      );
      expect(byId(provider, 't1').tags, ['b']);
      expect(await provider.updateTodosTags(['t1']), 0);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString('todos')!) as List<Object?>;
      expect(stored, hasLength(3));
    });
  });

  group('Habit reflection notes, rest passes and archive', () {
    test('new JSON fields round-trip and stay backward compatible', () {
      final legacy = Habit.fromJson(<String, dynamic>{
        'id': 'h',
        'name': 'Read',
      });
      expect(legacy.checkinNotes, isEmpty);
      expect(legacy.frozenDates, isEmpty);
      expect(legacy.freezeTokens, Habit.defaultFreezeTokens);
      final legacyJson = legacy.toJson();
      expect(legacyJson.containsKey('checkinNotes'), isFalse);
      expect(legacyJson.containsKey('freezeTokens'), isFalse);
      expect(legacyJson.containsKey('frozenDates'), isFalse);

      final day = DateTime(2026, 5, 12);
      final habit = Habit(
        id: 'h2',
        name: 'Run',
        tags: const ['health'],
        checkinNotes: {legacy.dateKey(day): 'felt great'},
        freezeTokens: 1,
        frozenDates: [legacy.dateKey(day.subtract(const Duration(days: 1)))],
      );
      final restored = Habit.fromJson(habit.toJson());
      expect(restored.noteForDate(day), 'felt great');
      expect(restored.freezeTokens, 1);
      expect(
        restored.isFrozenForDate(day.subtract(const Duration(days: 1))),
        isTrue,
      );
      expect(restored.tags, ['health']);
      expect(restored.sortedCheckinNotes.single.value, 'felt great');
    });

    test('rest pass keeps streak continuity and spends a token', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      final helper = Habit(id: 'k', name: 'k');
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(
          id: 'streak',
          name: 'Stretch',
          createdAt: today.subtract(const Duration(days: 30)),
          completions: {
            helper.dateKey(today): 1,
            helper.dateKey(twoDaysAgo): 1,
          },
        ),
      );

      final ok = await provider.toggleStreakFreezeForDate('streak', yesterday);
      expect(ok, isTrue);
      var habit = provider.habits.single;
      expect(habit.freezeTokens, Habit.defaultFreezeTokens - 1);
      expect(habit.isFrozenForDate(yesterday), isTrue);
      expect(habit.currentStreak, 2);

      // Completed days cannot be frozen.
      expect(await provider.toggleStreakFreezeForDate('streak', today), isFalse);

      // Toggling again refunds the token.
      expect(await provider.toggleStreakFreezeForDate('streak', yesterday), isTrue);
      habit = provider.habits.single;
      expect(habit.freezeTokens, Habit.defaultFreezeTokens);
      expect(habit.isFrozenForDate(yesterday), isFalse);
      expect(habit.currentStreak, 1);
    });

    test('per-check-in reflection note is stored and cleared', () async {
      final provider = HabitProvider();
      await provider.addHabit(Habit(id: 'note', name: 'Journal'));
      final day = DateTime.now().subtract(const Duration(days: 45));
      await provider.setHabitCheckinNote('note', day, '  deep focus  ');
      expect(provider.habits.single.noteForDate(day), 'deep focus');
      await provider.setHabitCheckinNote('note', day, '   ');
      expect(provider.habits.single.noteForDate(day), isNull);
    });

    test('ended habits move to the archive and can be reopened', () async {
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(id: 'arc', name: 'Archive me', tags: const ['focus', ' work ']),
      );
      await provider.addHabit(Habit(id: 'live', name: 'Keep'));
      expect(provider.allTags, containsAll(<String>['focus', 'work']));

      await provider.endHabit('arc');
      expect(provider.endedHabits.map((h) => h.id), ['arc']);
      expect(provider.activeHabits.map((h) => h.id), ['live']);

      await provider.reopenHabit('arc');
      expect(provider.endedHabits, isEmpty);
      expect(provider.habits.firstWhere((h) => h.id == 'arc').isEnded, isFalse);
    });
  });

  group('Pomodoro daily goal ring + ambient mixer', () {
    test('daily focus goal is clamped and persisted', () async {
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(
        provider.dailyFocusGoalMinutes,
        PomodoroProvider.defaultDailyFocusGoalMinutes,
      );
      expect(provider.dailyFocusGoalProgress, inInclusiveRange(0.0, 1.0));

      await provider.setDailyFocusGoalMinutes(90);
      expect(provider.dailyFocusGoalMinutes, 90);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PomodoroProvider.dailyFocusGoalPrefsKey), 90);

      await provider.setDailyFocusGoalMinutes(1);
      expect(provider.dailyFocusGoalMinutes, 10);

      final reloaded = PomodoroProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(reloaded.dailyFocusGoalMinutes, 10);
    });

    test('multi-track mixer blends tracks with independent volumes', () async {
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.ambientMixerTracks, isEmpty);
      expect(provider.hasMultiTrackMix, isFalse);

      await provider.toggleMixerTrack('rain');
      await provider.toggleMixerTrack('cafe', defaultVolume: 0.4);
      expect(provider.hasMultiTrackMix, isTrue);
      expect(provider.activeMixerTrackIds, containsAll(<String>['rain', 'cafe']));
      expect(provider.ambientMixerTracks['cafe'], closeTo(0.4, 1e-9));

      await provider.setMixerTrackVolume('rain', 0.25);
      expect(provider.ambientMixerTracks['rain'], closeTo(0.25, 1e-9));
      expect(provider.ambientMixerTracks['cafe'], closeTo(0.4, 1e-9));

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString(PomodoroProvider.ambientMixerPrefsKey)!)
              as Map<String, dynamic>;
      expect(stored.keys, containsAll(<String>['rain', 'cafe']));

      final reloaded = PomodoroProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(reloaded.ambientMixerTracks['rain'], closeTo(0.25, 1e-9));
      expect(reloaded.hasMultiTrackMix, isTrue);

      await provider.toggleMixerTrack('cafe');
      expect(provider.hasMultiTrackMix, isFalse);
      await provider.clearMixerTracks();
      expect(provider.ambientMixerTracks, isEmpty);
      expect(prefs.getString(PomodoroProvider.ambientMixerPrefsKey), isNull);
    });
  });

  group('UI wiring contracts (mobile + desktop parity)', () {
    test('Todo search/sort and batch actions on mobile and desktop', () {
      final mobile = _read('lib/screens/todo_screen.dart');
      expect(mobile, contains("ValueKey('todo_mobile_search_field')"));
      expect(mobile, contains("ValueKey('todo_mobile_sort_menu')"));
      expect(mobile, contains('sortTodos('));
      expect(mobile, contains('.rescheduleTodosDueDate('));
      expect(mobile, contains('.assignTodosListGroup('));
      expect(mobile, contains('onRescheduleDueDate'));
      expect(mobile, contains('onAssignList'));
      expect(mobile, contains('onAssignTags'));

      final desktop = _read('lib/desktop_web/views/desktop_todo_view.dart');
      expect(desktop, contains('prefs?.showCompletedTodos'));
      expect(desktop, contains('AppDateFormat.patternOf(context)'));
      expect(desktop, contains("ValueKey('desktop_todo_search_field')"));
      expect(desktop, contains("ValueKey('desktop_todo_batch_toggle')"));
      expect(desktop, contains("ValueKey('desktop_todo_batch_bar')"));
      expect(desktop, contains("ValueKey('desktop_todo_tag_filter_strip')"));
      expect(desktop, contains("ValueKey('desktop_todo_inspector_tag_field')"));
      expect(
        desktop,
        contains("ValueKey('desktop_todo_inspector_recurrence_btn')"),
      );
      expect(
        desktop,
        contains("ValueKey('desktop_todo_inspector_reminder_toggle')"),
      );
      expect(desktop, contains('RecurrencePicker.show('));
      expect(desktop, contains('ReminderPlanEditor('));
      expect(desktop, contains("'desktop_todo_custom_lists_v1'"));
      expect(desktop, contains('.rescheduleTodosDueDate('));
      expect(desktop, contains('.assignTodosListGroup('));
      expect(desktop, contains('.assignTagsToTodos('));
    });

    test('Habit tags, archive filter, week start, backfill and reminders', () {
      final mobile = _read('lib/screens/habit_screen.dart');
      expect(mobile, contains("ValueKey('habit_today_tag_filter_sliver')"));
      expect(mobile, contains("ValueKey('habit_mobile_filter_archived')"));
      expect(mobile, isNot(contains('Icons.shield_outlined')));

      final detail = _read('lib/screens/habit_detail_screen.dart');
      expect(detail, contains("ValueKey('habit_detail_pick_date_backfill')"));
      expect(detail, contains("ValueKey('habit_detail_today_freeze_btn')"));
      expect(detail, contains("ValueKey('habit_detail_reopen_btn')"));
      expect(detail, contains('setHabitCheckinNote('));
      expect(detail, contains('toggleStreakFreezeForDate('));

      final desktop = _read('lib/desktop_web/views/desktop_habit_view.dart');
      expect(desktop, contains('prefs?.firstDayOfWeek'));
      expect(desktop, contains('required this.firstDayOfWeek'));
      expect(desktop, contains('AppTimePicker.show('));
      expect(desktop, contains("ValueKey('desktop_habit_filter_archived')"));
      expect(desktop, contains("'desktop_habit_filter_tag_\$tag'"));
      expect(desktop, contains("'desktop_habit_note_\${habit.id}'"));
      expect(desktop, contains("'desktop_habit_reopen_\${habit.id}'"));
      expect(
        desktop,
        contains("'desktop_habit_dot_\${habit.id}_\${day.weekday}'"),
      );
    });

    test('Focus goal ring, mixer, web-safe import and real task picker', () {
      final mobile = _read('lib/screens/pomodoro_screen.dart');
      final importIndex = mobile.indexOf('customProvider.importAudio()');
      expect(importIndex, greaterThan(0));
      final guardIndex = mobile.lastIndexOf('if (!kIsWeb)', importIndex);
      expect(guardIndex, greaterThan(0));
      expect(importIndex - guardIndex, lessThan(400));
      expect(mobile, contains('context.read<TodoProvider?>()?.activeTodos'));
      expect(mobile, contains("ValueKey('pomodoro_mobile_goal_ring')"));
      expect(mobile, contains("ValueKey('pomodoro_mobile_mixer_panel')"));
      expect(mobile, contains('setMixerTrackVolume('));

      final desktop = _read('lib/desktop_web/views/desktop_focus_view.dart');
      expect(desktop, contains("ValueKey('desktop_focus_daily_goal_ring')"));
      expect(desktop, contains("ValueKey('desktop_focus_goal_edit_btn')"));
      expect(desktop, contains("ValueKey('desktop_focus_mixer_toggle')"));
      expect(desktop, contains("ValueKey('desktop_focus_mixer_tracks')"));
      expect(desktop, contains('setDailyFocusGoalMinutes('));
    });

    test('upgraded files avoid banned bold weights', () {
      final banned = RegExp(
        r'FontWeight\.(bold|w[5-9]00)|DesignTokens\.fontWeightMedium',
      );
      for (final path in const [
        'lib/core/todo_filters.dart',
        'lib/providers/todo_provider.dart',
        'lib/screens/todo_screen.dart',
        'lib/desktop_web/views/desktop_todo_view.dart',
        'lib/models/habit.dart',
        'lib/providers/habit_provider.dart',
        'lib/screens/habit_screen.dart',
        'lib/screens/habit_detail_screen.dart',
        'lib/desktop_web/views/desktop_habit_view.dart',
        'lib/providers/pomodoro_provider.dart',
        'lib/screens/pomodoro_screen.dart',
        'lib/desktop_web/views/desktop_focus_view.dart',
      ]) {
        expect(banned.hasMatch(_read(path)), isFalse, reason: path);
      }
    });
  });
}
