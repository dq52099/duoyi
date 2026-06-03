import 'dart:collection';
import 'package:flutter/foundation.dart';

/// 缓存条目
class _CacheEntry<V> {
  final V value;
  final DateTime createdAt;
  final Duration? ttl; // Time to live

  _CacheEntry(this.value, {this.ttl})
      : createdAt = DateTime.now();

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(createdAt) > ttl!;
  }
}

/// LRU内存缓存
///
/// 特性：
/// - LRU淘汰策略（最近最少使用）
/// - 可选的过期时间
/// - 大小限制
/// - 线程安全（通过同步方法）
class MemoryCache<K, V> {
  final int maxSize;
  final Duration? defaultTtl;
  final LinkedHashMap<K, _CacheEntry<V>> _cache = LinkedHashMap();

  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  MemoryCache({
    this.maxSize = 100,
    this.defaultTtl,
  });

  /// 获取缓存值
  V? get(K key) {
    final entry = _cache.remove(key);

    if (entry == null) {
      _misses++;
      return null;
    }

    // 检查是否过期
    if (entry.isExpired) {
      _misses++;
      return null;
    }

    // 移到最后（标记为最近使用）
    _cache[key] = entry;
    _hits++;
    return entry.value;
  }

  /// 存入缓存
  void put(K key, V value, {Duration? ttl}) {
    // 如果已存在，先移除
    _cache.remove(key);

    // 如果已满，移除最旧的
    if (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
      _evictions++;
    }

    // 添加新条目
    _cache[key] = _CacheEntry(
      value,
      ttl: ttl ?? defaultTtl,
    );
  }

  /// 移除指定key
  V? remove(K key) {
    final entry = _cache.remove(key);
    return entry?.value;
  }

  /// 清空缓存
  void clear() {
    _cache.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  /// 清理过期条目
  int cleanExpired() {
    var removed = 0;
    final keysToRemove = <K>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      removed++;
    }

    return removed;
  }

  /// 是否包含key
  bool containsKey(K key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// 当前大小
  int get size => _cache.length;

  /// 是否为空
  bool get isEmpty => _cache.isEmpty;

  /// 缓存命中率
  double get hitRate {
    final total = _hits + _misses;
    if (total == 0) return 0.0;
    return _hits / total;
  }

  /// 获取统计信息
  Map<String, dynamic> get stats => {
    'size': size,
    'maxSize': maxSize,
    'hits': _hits,
    'misses': _misses,
    'evictions': _evictions,
    'hitRate': hitRate,
  };

  /// 打印统计信息
  void printStats() {
    debugPrint('[MemoryCache] Stats: $stats');
  }
}

/// 多级缓存（内存 + 可选的第二级）
///
/// 典型用法：MemoryCache作为L1，另一个慢速缓存作为L2
class TieredCache<K, V> {
  final MemoryCache<K, V> l1Cache;
  final MemoryCache<K, V>? l2Cache;

  TieredCache({
    required this.l1Cache,
    this.l2Cache,
  });

  /// 获取值（先L1，再L2）
  V? get(K key) {
    // 尝试L1
    var value = l1Cache.get(key);
    if (value != null) return value;

    // 尝试L2
    final l2 = l2Cache;
    if (l2 != null) {
      value = l2.get(key);
      if (value != null) {
        // 提升到L1
        l1Cache.put(key, value);
        return value;
      }
    }

    return null;
  }

  /// 存入所有级别
  void put(K key, V value, {Duration? ttl}) {
    l1Cache.put(key, value, ttl: ttl);
    l2Cache?.put(key, value, ttl: ttl);
  }

  /// 从所有级别移除
  void remove(K key) {
    l1Cache.remove(key);
    l2Cache?.remove(key);
  }

  /// 清空所有级别
  void clear() {
    l1Cache.clear();
    l2Cache?.clear();
  }

  /// 合并统计
  Map<String, dynamic> get stats {
    final result = <String, dynamic>{'l1': l1Cache.stats};
    final l2 = l2Cache;
    if (l2 != null) {
      result['l2'] = l2.stats;
    }
    return result;
  }
}
