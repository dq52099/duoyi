import 'package:flutter/foundation.dart';
import '../services/network_status_service.dart';
import '../services/retry_strategy.dart';
import '../services/sync_queue.dart';

/// 云同步增强扩展
///
/// 为CloudSyncProvider提供网络状态监听、智能重试、离线队列等增强功能。
/// 这个mixin可以被混入CloudSyncProvider以添加新功能。
mixin CloudSyncEnhancements on ChangeNotifier {
  NetworkStatusService? _networkStatus;
  RetryStrategy? _retryStrategy;
  SyncQueue? _syncQueue;
  bool _enhancementsInitialized = false;

  /// 网络状态服务
  NetworkStatusService get networkStatus {
    if (_networkStatus == null) {
      throw StateError('CloudSyncEnhancements not initialized. Call initEnhancements() first.');
    }
    return _networkStatus!;
  }

  /// 重试策略
  RetryStrategy get retryStrategy {
    if (_retryStrategy == null) {
      throw StateError('CloudSyncEnhancements not initialized. Call initEnhancements() first.');
    }
    return _retryStrategy!;
  }

  /// 同步队列
  SyncQueue get syncQueue {
    if (_syncQueue == null) {
      throw StateError('CloudSyncEnhancements not initialized. Call initEnhancements() first.');
    }
    return _syncQueue!;
  }

  /// 是否已初始化增强功能
  bool get enhancementsInitialized => _enhancementsInitialized;

  /// 初始化增强功能
  Future<void> initEnhancements({
    NetworkStatusService? networkStatusService,
  }) async {
    if (_enhancementsInitialized) return;

    _networkStatus = networkStatusService ?? NetworkStatusService();
    _retryStrategy = RetryStrategy();
    _syncQueue = SyncQueue();

    await _syncQueue!.load();

    // 监听网络状态变化
    _networkStatus!.addListener(_onNetworkStatusChanged);

    _enhancementsInitialized = true;
    debugPrint('[CloudSyncEnhancements] Initialized successfully');
  }

  /// 网络状态变化处理
  void _onNetworkStatusChanged() {
    if (_networkStatus!.isOnline) {
      debugPrint('[CloudSyncEnhancements] Network online, triggering immediate sync');
      _retryStrategy!.triggerImmediateRetry();
      // 子类应该实现 onNetworkRestored() 方法来处理网络恢复
      onNetworkRestored();
    } else {
      debugPrint('[CloudSyncEnhancements] Network offline');
      onNetworkLost();
    }
  }

  /// 网络恢复时的回调（子类应重写）
  void onNetworkRestored() {
    // 默认什么都不做，子类可以重写来触发同步
  }

  /// 网络断开时的回调（子类应重写）
  void onNetworkLost() {
    // 默认什么都不做，子类可以重写来暂停同步
  }

  /// 检查是否应该同步
  bool shouldAttemptSync() {
    if (!_enhancementsInitialized) return true; // 未初始化时使用原有逻辑

    // 如果离线，不尝试同步
    if (_networkStatus!.isOffline) {
      debugPrint('[CloudSyncEnhancements] Skipping sync: offline');
      return false;
    }

    // 如果重试策略说不应该重试，等待
    if (_retryStrategy!.shouldRetry && _retryStrategy!.failureCount > 5) {
      debugPrint('[CloudSyncEnhancements] Skipping sync: too many failures');
      return false;
    }

    return true;
  }

  /// 记录同步成功
  void recordSyncSuccess() {
    if (!_enhancementsInitialized) return;
    _retryStrategy!.onSuccess();
  }

  /// 记录同步失败
  void recordSyncFailure(Object error) {
    if (!_enhancementsInitialized) return;

    final errorType = NetworkErrorClassifier.classify(error);
    _retryStrategy!.onFailure();

    debugPrint(
      '[CloudSyncEnhancements] Sync failed (${_retryStrategy!.failureCount}): '
      '${NetworkErrorClassifier.getUserFriendlyMessage(errorType)}, '
      'next retry in ${_retryStrategy!.getNextRetryDescription()}',
    );

    // 如果是可重试的错误，安排重试
    if (NetworkErrorClassifier.isRetryable(errorType)) {
      scheduleRetry();
    }
  }

  /// 安排重试
  void scheduleRetry() {
    if (!_enhancementsInitialized) return;

    _retryStrategy!.scheduleRetry(() {
      debugPrint('[CloudSyncEnhancements] Executing scheduled retry');
      onScheduledRetry();
    });
  }

  /// 定时重试回调（子类应重写）
  void onScheduledRetry() {
    // 默认什么都不做，子类可以重写来触发同步
  }

  /// 添加操作到离线队列
  Future<void> enqueueOfflineOperation(SyncOperation operation) async {
    if (!_enhancementsInitialized) return;

    await _syncQueue!.enqueue(operation);
    debugPrint('[CloudSyncEnhancements] Queued offline operation: ${operation.collection}/${operation.itemId}');
  }

  /// 处理离线队列
  Future<void> processOfflineQueue() async {
    if (!_enhancementsInitialized) return;
    if (_syncQueue!.isEmpty) return;

    debugPrint('[CloudSyncEnhancements] Processing ${_syncQueue!.size} queued operations');

    final operations = _syncQueue!.peek(50); // 每次处理50个操作
    final successIds = <String>[];

    for (final op in operations) {
      try {
        final success = await processSyncOperation(op);
        if (success) {
          successIds.add(op.id);
        }
      } catch (e) {
        debugPrint('[CloudSyncEnhancements] Failed to process operation ${op.id}: $e');
        break; // 遇到错误停止处理，避免浪费
      }
    }

    if (successIds.isNotEmpty) {
      await _syncQueue!.removeAll(successIds);
      debugPrint('[CloudSyncEnhancements] Successfully processed ${successIds.length} operations');
    }
  }

  /// 处理单个同步操作（子类应重写）
  Future<bool> processSyncOperation(SyncOperation operation) async {
    // 默认返回true，子类应该重写来实际处理操作
    return true;
  }

  /// 获取同步状态摘要
  Map<String, dynamic> getSyncStatusSummary() {
    if (!_enhancementsInitialized) {
      return {'initialized': false};
    }

    return {
      'initialized': true,
      'online': _networkStatus!.isOnline,
      'connectionType': _networkStatus!.connectionType,
      'queueSize': _syncQueue!.size,
      'failureCount': _retryStrategy!.failureCount,
      'nextRetry': _retryStrategy!.getNextRetryDescription(),
      'offlineDuration': _networkStatus!.offlineDurationSeconds,
    };
  }

  /// 清理资源
  void disposeEnhancements() {
    _networkStatus?.removeListener(_onNetworkStatusChanged);
    _networkStatus?.dispose();
    _retryStrategy?.dispose();
    _networkStatus = null;
    _retryStrategy = null;
    _syncQueue = null;
    _enhancementsInitialized = false;
  }
}
