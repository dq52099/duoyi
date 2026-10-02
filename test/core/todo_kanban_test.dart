import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/todo_kanban.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  test('默认看板列是待处理、进行中、已完成并按顺序输出', () {
    final config = TodoKanbanBoardConfig.defaults();
    final columns = config.sortedColumns;

    expect(columns.map((column) => column.id), [
      defaultKanbanPendingColumnId,
      defaultKanbanInProgressColumnId,
      defaultKanbanDoneColumnId,
    ]);
    expect(columns.map((column) => column.title), ['待处理', '进行中', '已完成']);
  });

  test('看板列配置可序列化、持久化并补回必需默认列', () {
    const custom = TodoKanbanColumn(
      id: 'review',
      title: '复核',
      colorValue: 0xFF7B1FA2,
      sortOrder: 0,
    );
    final encoded = TodoKanbanBoardConfig(
      columns: [custom],
      groupMode: TodoKanbanGroupMode.priority,
    ).encode();
    final decoded = TodoKanbanBoardConfig.decode(encoded);

    expect(decoded.columnById('review')?.title, '复核');
    expect(decoded.groupMode, TodoKanbanGroupMode.priority);
    expect(decoded.columnById(defaultKanbanPendingColumnId), isNotNull);
    expect(decoded.columnById(defaultKanbanInProgressColumnId), isNotNull);
    expect(decoded.columnById(defaultKanbanDoneColumnId), isNotNull);
    expect(
      json.decode(decoded.encode()) as Map<String, dynamic>,
      contains('columns'),
    );
  });

  test('未知任务列会归一到待处理列', () {
    final config = TodoKanbanBoardConfig.defaults();

    expect(config.normalizeColumnId(null), defaultKanbanPendingColumnId);
    expect(config.normalizeColumnId(''), defaultKanbanPendingColumnId);
    expect(config.normalizeColumnId('missing'), defaultKanbanPendingColumnId);
    expect(
      config.normalizeColumnId(defaultKanbanDoneColumnId),
      defaultKanbanDoneColumnId,
    );
  });

  test('未知看板分组模式会回退到不分组', () {
    final decoded = TodoKanbanBoardConfig.decode(
      json.encode({
        'groupMode': 'missing',
        'columns': TodoKanbanBoardConfig.defaults().columns
            .map((column) => column.toJson())
            .toList(),
      }),
    );

    expect(decoded.groupMode, TodoKanbanGroupMode.none);
    expect(TodoKanbanGroupMode.priority.label, '按优先级');
    expect(TodoKanbanGroupMode.dueDate.storageKey, 'due_date');
  });

  group('自定义看板列删除', () {
    TodoKanbanBoardConfig boardWithCustom() {
      final custom = TodoKanbanColumn(
        id: 'review',
        title: '复核',
        colorValue: 0xFF7B1FA2,
        sortOrder: 3,
      );
      return TodoKanbanBoardConfig(
        columns: [...TodoKanbanBoardConfig.defaults().columns, custom],
      );
    }

    test('删除自定义列成功，剩余列 sortOrder 压实且内置列保留', () {
      final next = boardWithCustom().removeColumn('review');
      expect(next, isNotNull);
      expect(next!.columnById('review'), isNull);
      expect(next.sortedColumns.map((column) => column.id), [
        defaultKanbanPendingColumnId,
        defaultKanbanInProgressColumnId,
        defaultKanbanDoneColumnId,
      ]);
      expect(next.sortedColumns.map((column) => column.sortOrder), [
        0,
        1,
        2,
      ], reason: '删除后排序号应重新压实');
    });

    test('内置列不可删除，不存在的列返回 null', () {
      final board = boardWithCustom();
      expect(
        board.removeColumn(defaultKanbanPendingColumnId),
        isNull,
        reason: '内置「待处理」列不可删',
      );
      expect(board.removeColumn(defaultKanbanInProgressColumnId), isNull);
      expect(board.removeColumn(defaultKanbanDoneColumnId), isNull);
      expect(board.removeColumn('missing'), isNull);
      expect(board.columnById('review'), isNotNull, reason: '失败删除不应改动配置');
    });

    test('删除后指向旧列的任务归并到默认待处理列（无需迁移）', () {
      var board = boardWithCustom();
      // 模拟看板上归在「复核」列的任务。
      final task = TodoItem(
        id: 'task-1',
        title: '归并验证',
        kanbanColumnId: 'review',
      );
      expect(board.normalizeColumnId(task.kanbanColumnId), 'review');

      board = board.removeColumn('review')!;

      // 删除后 normalizeColumnId 把旧列 id 归并到「待处理」。
      expect(
        board.normalizeColumnId(task.kanbanColumnId),
        defaultKanbanPendingColumnId,
      );
    });

    test('删除后的配置可编码持久化，重新解码不复活已删列', () {
      final next = boardWithCustom().removeColumn('review')!;
      final decoded = TodoKanbanBoardConfig.decode(next.encode());

      expect(decoded.columnById('review'), isNull);
      expect(decoded.columnById(defaultKanbanPendingColumnId), isNotNull);
      expect(decoded.sortedColumns, hasLength(3));
    });
  });
}
