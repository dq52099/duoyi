import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'memory_cache.dart';

/// 缓存统计信息
class CacheStats {
  final int memorySize;
  final int memoryHits;
  final int memoryMisses;
  final double memoryHitRate;
  final int diskReads;
  final int diskWrites;
  final int totalSize;

  const CacheStats({
    required this.memorySize,
    required this.memoryHits,
    required this.memoryMisses,
    required this.memoryHitRate,
    required this.diskReads,
    required this.diskWrites,
    required this.totalSize,
  });

  Map<String, dynamic> toJson() => {
    'memorySize': memorySize,
    'memoryHits': memoryHits,
    'memoryMisses': memoryMisses,
    'memoryHitRate': memoryHitRate,
    'diskReads': diskReads,
    'diskWrites': diskWrites,
    'totalSize': totalSize,
  };
}

/// 统一缓存管理器
///
/// 特性：
/// - 内存缓存（快速访问）
/// - SharedPreferences持久化
/// - 自动压缩大数据
/// - 预加载关键数据
/// - 统计和监控
class CacheManager {
  static CacheManager? _instance;
  static CacheManager get instance {
    _instance ??= CacheManager._();
    return _instance!;
  }

  late final MemoryCache<String, dynamic> _memoryCache;
  SharedPreferences? _prefs;
  bool _initialized = false;

  int _diskReads = 0;
  int _diskWrites = 0;

  // 压缩阈值（字节）
  static const int _compressionThreshold = 1024;

  // 关键数据的缓存键（用于预加载）
  static const List<String> _criticalKeys = [
    'todos',
    'habits',
    'pomodoro_sessions',
    'theme_data',
    'user_profile',
  ];

  CacheManager._() {
    _memoryCache = MemoryCache<String, dynamic>(
      maxSize: 200, // 可以缓存200个条目
      defaultTtl: const Duration(minutes: 30), // 默认30分钟过期
    );
  }

  /// 初始化缓存管理器
  Future<void> init() async {
    if (_initialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
      debugPrint('[CacheManager] Initialized successfully');
    } catch (e) {
      debugPrint('[CacheManager] Initialization failed: $e');
      _initialized = false;
    }
  }

  /// 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  /// 读取缓存
  ///
  /// 先尝试内存缓存，未命中则从SharedPreferences读取
  Future<T?> get<T>(String key, {T Function(dynamic)? decoder}) async {
    // 尝试内存缓存
    final memValue = _memoryCache.get(key);
    if (memValue != null) {
      return decoder != null ? decoder(memValue) : memValue as T?;
    }

    // 未命中，从磁盘读取
    await _ensureInitialized();
    if (_prefs == null) return null;

    _diskReads++;

    try {
      final stored = _prefs!.getString(key);
      if (stored == null) return null;

      // 检查是否压缩
      dynamic decoded;
      if (_isCompressed(stored)) {
        decoded = await _decompress(stored);
      } else {
        decoded = json.decode(stored);
      }

      // 写入内存缓存
      _memoryCache.put(key, decoded);

      return decoder != null ? decoder(decoded) : decoded as T?;
    } catch (e) {
      debugPrint('[CacheManager] Failed to get $key: $e');
      return null;
    }
  }

  /// 写入缓存
  ///
  /// 同时写入内存和SharedPreferences
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    await _ensureInitialized();

    // 写入内存缓存
    _memoryCache.put(key, value, ttl: ttl);

    // 写入磁盘
    if (_prefs == null) return;

    _diskWrites++;

    try {
      final encoded = json.encode(value);

      // 大数据自动压缩
      String toStore;
      if (encoded.length > _compressionThreshold) {
        toStore = await _compress(encoded);
      } else {
        toStore = encoded;
      }

      await _prefs!.setString(key, toStore);
    } catch (e) {
      debugPrint('[CacheManager] Failed to set $key: $e');
    }
  }

  /// 移除缓存
  Future<void> remove(String key) async {
    _memoryCache.remove(key);

    await _ensureInitialized();
    if (_prefs != null) {
      await _prefs!.remove(key);
    }
  }

  /// 清空所有缓存
  Future<void> clear() async {
    _memoryCache.clear();

    await _ensureInitialized();
    if (_prefs != null) {
      await _prefs!.clear();
    }

    _diskReads = 0;
    _diskWrites = 0;
  }

  /// 批量预加载
  ///
  /// 异步加载关键数据到内存缓存
  Future<void> preload([List<String>? keys]) async {
    final keysToLoad = keys ?? _criticalKeys;

    await _ensureInitialized();
    if (_prefs == null) return;

    for (final key in keysToLoad) {
      // 如果内存中已有，跳过
      if (_memoryCache.containsKey(key)) continue;

      try {
        final stored = _prefs!.getString(key);
        if (stored == null) continue;

        dynamic decoded;
        if (_isCompressed(stored)) {
          decoded = await _decompress(stored);
        } else {
          decoded = json.decode(stored);
        }

        _memoryCache.put(key, decoded);
      } catch (e) {
        debugPrint('[CacheManager] Failed to preload $key: $e');
      }
    }

    debugPrint('[CacheManager] Preloaded ${keysToLoad.length} keys');
  }

  /// 清理过期缓存
  int cleanExpired() {
    return _memoryCache.cleanExpired();
  }

  /// 获取统计信息
  CacheStats getStats() {
    final memStats = _memoryCache.stats;
    return CacheStats(
      memorySize: memStats['size'] as int,
      memoryHits: memStats['hits'] as int,
      memoryMisses: memStats['misses'] as int,
      memoryHitRate: memStats['hitRate'] as double,
      diskReads: _diskReads,
      diskWrites: _diskWrites,
      totalSize: memStats['size'] as int,
    );
  }

  /// 打印统计信息
  void printStats() {
    final stats = getStats();
    debugPrint('[CacheManager] Stats: ${stats.toJson()}');
  }

  /// 压缩数据
  Future<String> _compress(String data) async {
    try {
      final bytes = utf8.encode(data);
      final compressed = gzip.encode(bytes);
      final base64 = base64Encode(compressed);
      return 'gzip:$base64'; // 添加前缀标识
    } catch (e) {
      debugPrint('[CacheManager] Compression failed: $e');
      return data;
    }
  }

  /// 解压数据
  Future<dynamic> _decompress(String data) async {
    try {
      // 移除前缀
      final base64Data = data.substring(5); // 'gzip:'.length
      final compressed = base64Decode(base64Data);
      final bytes = gzip.decode(compressed);
      final decoded = utf8.decode(bytes);
      return json.decode(decoded);
    } catch (e) {
      debugPrint('[CacheManager] Decompression failed: $e');
      return null;
    }
  }

  /// 检查是否是压缩数据
  bool _isCompressed(String data) {
    return data.startsWith('gzip:');
  }
}

/// CacheManager的简化接口，用于Provider
///
/// 使用示例：
/// ```dart
/// class MyProvider {
///   Future<void> loadFromStorage() async {
///     final data = await CacheHelper.get('my_key');
///     // 使用数据...
///   }
///
///   Future<void> saveToStorage() async {
///     await CacheHelper.set('my_key', data);
///   }
/// }
/// ```
class CacheHelper {
  static Future<T?> get<T>(String key, {T Function(dynamic)? decoder}) {
    return CacheManager.instance.get<T>(key, decoder: decoder);
  }

  static Future<void> set<T>(String key, T value, {Duration? ttl}) {
    return CacheManager.instance.set<T>(key, value, ttl: ttl);
  }

  static Future<void> remove(String key) {
    return CacheManager.instance.remove(key);
  }

  static Future<void> clear() {
    return CacheManager.instance.clear();
  }

  static CacheStats getStats() {
    return CacheManager.instance.getStats();
  }

  static void printStats() {
    CacheManager.instance.printStats();
  }
}
