import 'dart:convert';

const String defaultKanbanPendingColumnId = 'pending';
const String defaultKanbanInProgressColumnId = 'in_progress';
const String defaultKanbanDoneColumnId = 'done';

const String todoKanbanColumnsPrefsKey = 'todo_kanban_columns_v1';

enum TodoKanbanGroupMode { none, priority, dueDate, tag, list }

extension TodoKanbanGroupModeX on TodoKanbanGroupMode {
  String get storageKey => switch (this) {
    TodoKanbanGroupMode.none => 'none',
    TodoKanbanGroupMode.priority => 'priority',
    TodoKanbanGroupMode.dueDate => 'due_date',
    TodoKanbanGroupMode.tag => 'tag',
    TodoKanbanGroupMode.list => 'list',
  };

  String get label => switch (this) {
    TodoKanbanGroupMode.none => '不分组',
    TodoKanbanGroupMode.priority => '按优先级',
    TodoKanbanGroupMode.dueDate => '按截止日',
    TodoKanbanGroupMode.tag => '按标签',
    TodoKanbanGroupMode.list => '按清单',
  };

  static TodoKanbanGroupMode fromStorageKey(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    for (final mode in TodoKanbanGroupMode.values) {
      if (mode.storageKey == value) return mode;
    }
    return TodoKanbanGroupMode.none;
  }
}

class TodoKanbanColumn {
  final String id;
  final String title;
  final int colorValue;
  final int sortOrder;
  final bool builtIn;

  const TodoKanbanColumn({
    required this.id,
    required this.title,
    required this.colorValue,
    required this.sortOrder,
    this.builtIn = false,
  });

  TodoKanbanColumn copyWith({String? title, int? colorValue, int? sortOrder}) {
    return TodoKanbanColumn(
      id: id,
      title: title ?? this.title,
      colorValue: colorValue ?? this.colorValue,
      sortOrder: sortOrder ?? this.sortOrder,
      builtIn: builtIn,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'colorValue': colorValue,
    'sortOrder': sortOrder,
    'builtIn': builtIn,
  };

  factory TodoKanbanColumn.fromJson(Map<String, dynamic> json) {
    return TodoKanbanColumn(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      colorValue: ((json['colorValue'] as num?) ?? 0xFF607D8B).toInt(),
      sortOrder: ((json['sortOrder'] as num?) ?? 0).toInt(),
      builtIn: json['builtIn'] == true,
    );
  }
}

class TodoKanbanBoardConfig {
  final List<TodoKanbanColumn> columns;
  final TodoKanbanGroupMode groupMode;

  const TodoKanbanBoardConfig({
    required this.columns,
    this.groupMode = TodoKanbanGroupMode.none,
  });

  factory TodoKanbanBoardConfig.defaults() {
    return const TodoKanbanBoardConfig(
      groupMode: TodoKanbanGroupMode.none,
      columns: [
        TodoKanbanColumn(
          id: defaultKanbanPendingColumnId,
          title: '待处理',
          colorValue: 0xFF607D8B,
          sortOrder: 0,
          builtIn: true,
        ),
        TodoKanbanColumn(
          id: defaultKanbanInProgressColumnId,
          title: '进行中',
          colorValue: 0xFF1976D2,
          sortOrder: 1,
          builtIn: true,
        ),
        TodoKanbanColumn(
          id: defaultKanbanDoneColumnId,
          title: '已完成',
          colorValue: 0xFF2E7D32,
          sortOrder: 2,
          builtIn: true,
        ),
      ],
    );
  }

  List<TodoKanbanColumn> get sortedColumns {
    final result = [...columns];
    result.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.title.compareTo(b.title);
    });
    return result;
  }

  String normalizeColumnId(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return defaultKanbanPendingColumnId;
    return columns.any((column) => column.id == value)
        ? value
        : defaultKanbanPendingColumnId;
  }

  TodoKanbanColumn? columnById(String id) {
    for (final column in columns) {
      if (column.id == id) return column;
    }
    return null;
  }

  TodoKanbanBoardConfig copyWith({
    List<TodoKanbanColumn>? columns,
    TodoKanbanGroupMode? groupMode,
  }) {
    return TodoKanbanBoardConfig(
      columns: columns ?? this.columns,
      groupMode: groupMode ?? this.groupMode,
    );
  }

  String encode() => json.encode({
    'columns': columns.map((column) => column.toJson()).toList(),
    'groupMode': groupMode.storageKey,
  });

  factory TodoKanbanBoardConfig.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return TodoKanbanBoardConfig.defaults();
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return TodoKanbanBoardConfig.defaults();
      final rawColumns = decoded['columns'];
      if (rawColumns is! List) return TodoKanbanBoardConfig.defaults();
      final columns = rawColumns
          .whereType<Map>()
          .map((item) => TodoKanbanColumn.fromJson(Map.from(item)))
          .where((column) => column.id.trim().isNotEmpty)
          .toList();
      return TodoKanbanBoardConfig(
        columns: _mergeWithRequiredDefaults(columns),
        groupMode: TodoKanbanGroupModeX.fromStorageKey(decoded['groupMode']),
      );
    } catch (_) {
      return TodoKanbanBoardConfig.defaults();
    }
  }

  static List<TodoKanbanColumn> _mergeWithRequiredDefaults(
    List<TodoKanbanColumn> custom,
  ) {
    final byId = <String, TodoKanbanColumn>{
      for (final column in custom) column.id: column,
    };
    final defaults = TodoKanbanBoardConfig.defaults().columns;
    for (final column in defaults) {
      byId.putIfAbsent(column.id, () => column);
    }
    final merged = byId.values.toList();
    merged.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.title.compareTo(b.title);
    });
    for (var i = 0; i < merged.length; i++) {
      merged[i] = merged[i].copyWith(sortOrder: i);
    }
    return merged;
  }
}
