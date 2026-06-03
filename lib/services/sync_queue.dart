import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步操作类型
enum SyncOperationType {
  create,  // 创建
  update,  // 更新
  delete,  // 删除
}

/// 离线同步操作
///
/// 记录离线时的数据变更操作，在网络恢复后按优先级批量同步。
class SyncOperation {
  final String id;
  final SyncOperationType type;
  final String collection;
  final String itemId;
  final Map<String, dynamic>? data;
  final int priority; // 0=最高优先级
  final DateTime timestamp;

  const SyncOperation({
    required this.id,
    required this.type,
    required this.collection,
    required this.itemId,
    this.data,
    this.priority = 5,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'collection': collection,
    'itemId': itemId,
    'data': data,
    'priority': priority,
    'timestamp': timestamp.toIso8601String(),
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id']?.toString() ?? '',
      type: SyncOperationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SyncOperationType.update,
      ),
      collection: json['collection']?.toString() ?? '',
      itemId: json['itemId']?.toString() ?? '',
      data: json['data'] as Map<String, dynamic>?,
      priority: json['priority'] as int? ?? 5,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// 离线同步队列
///
/// 管理离线时的操作队列，支持优先级排序、去重、持久化。
class SyncQueue {
  static const String _storageKey = 'sync_operation_queue_v1';
  static const int _maxQueueSize = 1000;

  final List<SyncOperation> _queue = [];
  bool _isLoaded = false;

  /// 队列大小
  int get size => _queue.length;

  /// 是否为空
  bool get isEmpty => _queue.isEmpty;

  /// 是否已满
  bool get isFull => _queue.length >= _maxQueueSize;

  /// 从本地存储加载队列
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        _isLoaded = true;
        return;
      }

      final decoded = json.decode(stored);
      if (decoded is List) {
        _queue.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _queue.add(SyncOperation.fromJson(item));
          }
        }
        // 按优先级和时间排序
        _queue.sort((a, b) {
          final priorityCompare = a.priority.compareTo(b.priority);
          if (priorityCompare != 0) return priorityCompare;
          return a.timestamp.compareTo(b.timestamp);
        });
      }
      _isLoaded = true;
    } catch (e) {
      debugPrint('[SyncQueue] Failed to load queue: $e');
      _queue.clear();
      _isLoaded = true;
    }
  }

  /// 添加操作到队列
  Future<void> enqueue(SyncOperation operation) async {
    await load();

    // 去重：如果已存在相同collection和itemId的操作，更新它
    final existingIndex = _queue.indexWhere(
      (op) => op.collection == operation.collection && op.itemId == operation.itemId,
    );

    if (existingIndex >= 0) {
      // 更新现有操作
      _queue[existingIndex] = operation;
    } else if (!isFull) {
      // 添加新操作
      _queue.add(operation);
    } else {
      // 队列已满，移除最低优先级的操作
      _queue.sort((a, b) => b.priority.compareTo(a.priority));
      _queue.removeLast();
      _queue.add(operation);
    }

    // 重新排序
    _queue.sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.timestamp.compareTo(b.timestamp);
    });

    await persist();
  }

  /// 获取指定数量的高优先级操作
  List<SyncOperation> peek(int count) {
    return _queue.take(count).toList();
  }

  /// 移除指定操作
  Future<void> remove(String operationId) async {
    _queue.removeWhere((op) => op.id == operationId);
    await persist();
  }

  /// 批量移除操作
  Future<void> removeAll(List<String> operationIds) async {
    final idSet = Set<String>.from(operationIds);
    _queue.removeWhere((op) => idSet.contains(op.id));
    await persist();
  }

  /// 清空队列
  Future<void> clear() async {
    _queue.clear();
    await persist();
  }

  /// 持久化到本地存储
  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_queue.map((op) => op.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('[SyncQueue] Failed to persist queue: $e');
    }
  }

  /// 获取按集合分组的操作统计
  Map<String, int> getCollectionStats() {
    final stats = <String, int>{};
    for (final op in _queue) {
      stats[op.collection] = (stats[op.collection] ?? 0) + 1;
    }
    return stats;
  }
}
