import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/todo_kanban.dart';

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
}
