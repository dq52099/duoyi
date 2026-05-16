import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  final cs = const ColorScheme.light().copyWith(
    primary: Colors.blue,
    tertiary: Colors.green,
  );

  group('CalendarAggregator 冲突检测', () {
    test('同一天多个事件不会全部标记冲突，只有时间真正重叠的才标记', () {
      final today = DateTime(2026, 5, 13);
      final todos = [
        TodoItem(
          id: 't1',
          title: '上午任务',
          date: today,
          dueDate: DateTime(2026, 5, 13, 10, 0),
        ),
        TodoItem(
          id: 't2',
          title: '下午任务',
          date: today,
          dueDate: DateTime(2026, 5, 13, 15, 0),
        ),
      ];
      final events = CalendarAggregator.buildEvents(
        todos: todos,
        habits: const [],
        pomodoroSessions: const [],
        colorScheme: cs,
      );
      expect(events.length, 2);
      // 不同时间段不应触发冲突
      expect(events.every((e) => !e.hasConflict), isTrue);
    });

    test('属性测试: 随机生成同时段事件 → 应该被标记冲突', () {
      final today = DateTime(2026, 5, 13);
      final random = Random(42);
      for (var trial = 0; trial < 50; trial++) {
        final hour = 9 + random.nextInt(8);
        final todos = [
          TodoItem(
            id: 't1_$trial',
            title: '任务一',
            date: today,
            dueDate: DateTime(2026, 5, 13, hour, 0),
          ),
          TodoItem(
            id: 't2_$trial',
            title: '任务二',
            date: today,
            dueDate: DateTime(2026, 5, 13, hour, 0),
          ),
        ];
        final events = CalendarAggregator.buildEvents(
          todos: todos,
          habits: const [],
          pomodoroSessions: const [],
          colorScheme: cs,
        );
        // 至少两个事件中应有冲突标记
        final conflictCount = events.where((e) => e.hasConflict).length;
        expect(
          conflictCount,
          greaterThanOrEqualTo(2),
          reason: '相同小时的两个事件应都标记冲突 (trial=$trial)',
        );
      }
    });

    test('属性测试: 排序后日期递增', () {
      final random = Random(7);
      for (var trial = 0; trial < 20; trial++) {
        final todos = <TodoItem>[
          for (var i = 0; i < 10; i++)
            TodoItem(
              id: 'r${trial}_$i',
              title: '任务$i',
              date: DateTime(2026, 5, 1 + random.nextInt(30)),
            ),
        ];
        final events = CalendarAggregator.buildEvents(
          todos: todos,
          habits: const [],
          pomodoroSessions: const [],
          colorScheme: cs,
        );
        for (var i = 1; i < events.length; i++) {
          expect(
            !events[i].date.isBefore(events[i - 1].date),
            isTrue,
            reason: '事件应按日期升序排列',
          );
        }
      }
    });

    test('habit + pomodoro + todo 混合不影响排序稳定性', () {
      final today = DateTime(2026, 5, 14);
      final events = CalendarAggregator.buildEvents(
        todos: [
          TodoItem(
            id: 't1',
            title: 'todo',
            date: today,
            dueDate: DateTime(2026, 5, 14, 14),
          ),
        ],
        habits: [
          Habit(
            id: 'h1',
            name: '阅读',
            completions: {'2026-05-14': 1},
          ),
        ],
        pomodoroSessions: [
          PomodoroSession(
            id: 'p1',
            startTime: DateTime(2026, 5, 14, 10),
            endTime: DateTime(2026, 5, 14, 10, 25),
            durationSeconds: 1500,
            type: PomodoroType.focus,
          ),
        ],
        colorScheme: cs,
      );
      expect(events.length, 3);
      expect(events.map((e) => e.type).toSet(), {
        CalendarEventType.todo,
        CalendarEventType.habit,
        CalendarEventType.pomodoro,
      });
    });
  });
}
