import 'dart:async';

/// 智能重试策略
///
/// 使用指数退避算法，在网络错误后逐渐增加重试间隔。
/// 网络恢复或用户操作时可以快速重试。
class RetryStrategy {
  static const List<int> _retryDelaysSeconds = [5, 10, 20, 40, 120, 180];
  static const int _maxRetryDelay = 180; // 3分钟

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _lastSuccessTime;
  Timer? _retryTimer;

  /// 当前失败次数
  int get failureCount => _failureCount;

  /// 上次失败时间
  DateTime? get lastFailureTime => _lastFailureTime;

  /// 上次成功时间
  DateTime? get lastSuccessTime => _lastSuccessTime;

  /// 是否应该重试
  bool get shouldRetry => _failureCount > 0;

  /// 计算下次重试延迟时间
  Duration nextRetryDelay() {
    if (_failureCount == 0) {
      return const Duration(seconds: 5);
    }

    final index = (_failureCount - 1).clamp(0, _retryDelaysSeconds.length - 1);
    final delaySeconds = _retryDelaysSeconds[index].clamp(1, _maxRetryDelay);
    return Duration(seconds: delaySeconds);
  }

  /// 记录成功
  void onSuccess() {
    _failureCount = 0;
    _lastSuccessTime = DateTime.now();
    _lastFailureTime = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 记录失败
  void onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
  }

  /// 重置策略
  void reset() {
    _failureCount = 0;
    _lastFailureTime = null;
    _lastSuccessTime = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 安排定时重试
  void scheduleRetry(void Function() onRetry) {
    _retryTimer?.cancel();

    final delay = nextRetryDelay();
    _retryTimer = Timer(delay, () {
      onRetry();
      _retryTimer = null;
    });
  }

  /// 取消定时重试
  void cancelScheduledRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 立即重试（清除失败计数）
  void triggerImmediateRetry() {
    _failureCount = 0;
    _lastFailureTime = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// 获取人类可读的下次重试时间描述
  String getNextRetryDescription() {
    if (_failureCount == 0) return '立即';

    final delay = nextRetryDelay();
    final seconds = delay.inSeconds;

    if (seconds < 60) {
      return '$seconds秒后';
    } else {
      final minutes = (seconds / 60).round();
      return '$minutes分钟后';
    }
  }

  /// 清理资源
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

/// 网络错误类型
enum NetworkErrorType {
  timeout,          // 超时
  connectionFailed, // 连接失败
  serverError,      // 服务器错误
  unauthorized,     // 未授权
  notFound,         // 资源不存在
  unknown,          // 未知错误
}

/// 网络错误分类器
class NetworkErrorClassifier {
  /// 从错误对象判断错误类型
  static NetworkErrorType classify(Object error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout') ||
        errorString.contains('timed out') ||
        errorString.contains('超时')) {
      return NetworkErrorType.timeout;
    }

    if (errorString.contains('socket') ||
        errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('failed to connect') ||
        errorString.contains('无法连接') ||
        errorString.contains('连接失败')) {
      return NetworkErrorType.connectionFailed;
    }

    if (errorString.contains('401') ||
        errorString.contains('unauthorized') ||
        errorString.contains('未授权')) {
      return NetworkErrorType.unauthorized;
    }

    if (errorString.contains('404') ||
        errorString.contains('not found') ||
        errorString.contains('未找到')) {
      return NetworkErrorType.notFound;
    }

    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504') ||
        errorString.contains('server error') ||
        errorString.contains('服务器错误')) {
      return NetworkErrorType.serverError;
    }

    return NetworkErrorType.unknown;
  }

  /// 判断是否是可重试的错误
  static bool isRetryable(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.timeout:
      case NetworkErrorType.connectionFailed:
      case NetworkErrorType.serverError:
        return true;
      case NetworkErrorType.unauthorized:
      case NetworkErrorType.notFound:
      case NetworkErrorType.unknown:
        return false;
    }
  }

  /// 获取用户友好的错误描述
  static String getUserFriendlyMessage(NetworkErrorType errorType) {
    switch (errorType) {
      case NetworkErrorType.timeout:
        return '网络请求超时，请检查网络连接';
      case NetworkErrorType.connectionFailed:
        return '无法连接到服务器，请检查网络';
      case NetworkErrorType.serverError:
        return '服务器暂时不可用，请稍后重试';
      case NetworkErrorType.unauthorized:
        return '登录已过期，请重新登录';
      case NetworkErrorType.notFound:
        return '请求的资源不存在';
      case NetworkErrorType.unknown:
        return '同步失败，请稍后重试';
    }
  }
}
