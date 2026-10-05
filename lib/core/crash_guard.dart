import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 全局未捕获异常兜底。
///
/// 挂接 [FlutterError.onError]（框架异常）与
/// [PlatformDispatcher.instance.onError]（未捕获的平台/Dart 异常），
/// 将异常摘要追加写入本地日志文件，供用户反馈时随诊断导出。
///
/// 设计约束：
/// - 不使用 runZonedGuarded 包裹 runApp，规避与 async main 的 zone 交互；
/// - handler 内部绝不抛出、绝不弹 UI：记录器任何失败都被静默吞掉，
///   原 handler（若存在）被链式调用；
/// - 日志写入优先同步追加（目录已解析时），目录未就绪时先进内存缓冲，
///   解析完成后补写；单文件超过 512KB 后重建，避免无限增长。
class CrashGuard {
  CrashGuard._();

  static const String _logFileName = 'crash_guard.log';
  static const int _maxLogBytes = 512 * 1024;
  static const int _maxPendingLines = 200;
  static const int _maxMessageLength = 600;

  static FlutterExceptionHandler? _previousFlutterErrorOnError;
  static bool Function(Object error, StackTrace stack)?
  _previousPlatformDispatcherOnError;
  static bool _installed = false;
  static Directory? _resolvedDirectory;
  static bool _resolvingDirectory = false;
  static final List<String> _pendingLines = <String>[];

  /// 测试注入：覆盖日志目录解析（同步返回），生产环境保持 null。
  @visibleForTesting
  static Directory? Function()? logDirectoryOverride;

  /// 挂接全局 handler；重复调用幂等。
  static void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutterErrorOnError = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;
    _previousPlatformDispatcherOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = _handlePlatformError;
    // 预热日志目录（异步，不阻塞启动）。
    unawaited(_ensureDirectory());
  }

  /// 恢复安装前的 handler 并清空状态（测试用）。
  @visibleForTesting
  static void reset() {
    if (FlutterError.onError == _handleFlutterError) {
      FlutterError.onError = _previousFlutterErrorOnError;
    }
    if (PlatformDispatcher.instance.onError == _handlePlatformError) {
      PlatformDispatcher.instance.onError = _previousPlatformDispatcherOnError;
    }
    _previousFlutterErrorOnError = null;
    _previousPlatformDispatcherOnError = null;
    _resolvedDirectory = null;
    _resolvingDirectory = false;
    _pendingLines.clear();
    _installed = false;
  }

  static void _handleFlutterError(FlutterErrorDetails details) {
    record(
      source: 'flutter',
      error: details.exception,
      stack: details.stack,
      context: details.context?.toString(),
      library: details.library,
    );
    final previous = _previousFlutterErrorOnError;
    if (previous == null) {
      FlutterError.dumpErrorToConsole(details);
      return;
    }
    try {
      previous(details);
    } catch (_) {
      // 链式调用失败也不能让兜底本身抛出。
    }
  }

  static bool _handlePlatformError(Object error, StackTrace stack) {
    record(source: 'platform', error: error, stack: stack);
    final previous = _previousPlatformDispatcherOnError;
    if (previous == null) {
      // false = 交回引擎默认处理。
      return false;
    }
    try {
      return previous(error, stack);
    } catch (_) {
      return false;
    }
  }

  /// 记录一条异常摘要；任何失败静默吞掉。
  static void record({
    required String source,
    required Object error,
    StackTrace? stack,
    String? context,
    String? library,
  }) {
    try {
      final line = _formatLine(source, error, stack, context, library);
      final directory = _resolvedDirectory ?? logDirectoryOverride?.call();
      if (directory == null) {
        _enqueue(line);
        unawaited(_ensureDirectory());
        return;
      }
      _appendToLog(directory, line);
    } catch (_) {
      // 兜底记录自身失败必须静默。
    }
  }

  /// 把当前内存缓冲写入日志文件（测试用）。
  @visibleForTesting
  static void flushPendingForTesting() {
    final directory = _resolvedDirectory ?? logDirectoryOverride?.call();
    if (directory == null) return;
    while (_pendingLines.isNotEmpty) {
      _appendToLog(directory, _pendingLines.removeAt(0));
    }
  }

  static String _formatLine(
    String source,
    Object error,
    StackTrace? stack,
    String? context,
    String? library,
  ) {
    final buffer = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write(' [')
      ..write(source)
      ..write('] ')
      ..write(_singleLine(error.toString(), _maxMessageLength));
    if (library != null && library.isNotEmpty) {
      buffer.write(' | library: ');
      buffer.write(_singleLine(library, 120));
    }
    if (context != null && context.isNotEmpty) {
      buffer.write(' | context: ');
      buffer.write(_singleLine(context, 200));
    }
    if (stack != null) {
      String? firstFrame;
      for (final line in stack.toString().split('\n').skip(1)) {
        if (line.trim().isNotEmpty) {
          firstFrame = line;
          break;
        }
      }
      if (firstFrame != null) {
        buffer.write(' | stack: ');
        buffer.write(_singleLine(firstFrame, 300));
      }
    }
    return buffer.toString();
  }

  static String _singleLine(String raw, int maxLength) {
    var line = raw.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    if (line.length > maxLength) {
      line = '${line.substring(0, maxLength)}…';
    }
    return line;
  }

  static void _enqueue(String line) {
    if (_pendingLines.length >= _maxPendingLines) return;
    _pendingLines.add(line);
  }

  static Future<void> _ensureDirectory() async {
    if (_resolvedDirectory != null || _resolvingDirectory) return;
    _resolvingDirectory = true;
    try {
      final override = logDirectoryOverride;
      _resolvedDirectory = override != null
          ? override()
          : await getApplicationSupportDirectory();
    } catch (_) {
      // 目录解析失败：保持 null，后续记录进内存缓冲。
      return;
    } finally {
      _resolvingDirectory = false;
    }
    _flushPending();
  }

  static void _flushPending() {
    final directory = _resolvedDirectory;
    if (directory == null) return;
    while (_pendingLines.isNotEmpty) {
      _appendToLog(directory, _pendingLines.removeAt(0));
    }
  }

  static void _appendToLog(Directory directory, String line) {
    try {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$_logFileName',
      );
      if (file.existsSync() && file.lengthSync() > _maxLogBytes) {
        // 超过上限：重建日志，保留最新记录。
        file.writeAsStringSync('$line\n', mode: FileMode.write);
      } else {
        file.writeAsStringSync('$line\n', mode: FileMode.append);
      }
    } catch (_) {
      // 磁盘写入失败必须静默。
    }
  }
}
