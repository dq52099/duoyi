import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/crash_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File logFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crash_guard_test');
    logFile = File('${tempDir.path}${Platform.pathSeparator}crash_guard.log');
    CrashGuard.logDirectoryOverride = () => tempDir;
  });

  tearDown(() {
    CrashGuard.reset();
    CrashGuard.logDirectoryOverride = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  List<String> logLines() => logFile.existsSync()
      ? logFile.readAsLinesSync().where((l) => l.isNotEmpty).toList()
      : <String>[];

  test('a) FlutterError handler 挂接后异常摘要落盘本地日志', () {
    CrashGuard.install();

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: Exception('boom-xyz'),
        stack: StackTrace.current,
        library: 'crash_guard_test',
      ),
    );

    final lines = logLines();
    expect(lines, isNotEmpty, reason: 'handler 应把异常摘要写入日志文件');
    expect(lines.last, contains('boom-xyz'));
    expect(lines.last, contains('[flutter]'));
    expect(lines.last, contains('crash_guard_test'), reason: '应包含来源上下文');
  });

  test('a2) platform handler 记录摘要并交回引擎默认处理', () {
    CrashGuard.install();

    final handled = PlatformDispatcher.instance.onError!(
      StateError('platform-boom'),
      StackTrace.current,
    );

    expect(handled, isFalse, reason: '无前置 handler 时返回 false 交回引擎');
    final lines = logLines();
    expect(lines, isNotEmpty);
    expect(lines.last, contains('platform-boom'));
    expect(lines.last, contains('[platform]'));
  });

  test('b) 日志目录解析失败时 handler 不向外抛且原 handler 仍被调用', () {
    // 目录 override 自身抛错 → 记录失败必须静默。
    CrashGuard.logDirectoryOverride = () => throw StateError('no disk');
    var previousCalled = 0;
    FlutterError.onError = (details) => previousCalled++;

    CrashGuard.install();

    expect(
      () => FlutterError.reportError(
        FlutterErrorDetails(exception: Exception('swallowed')),
      ),
      returnsNormally,
    );
    expect(previousCalled, 1, reason: '链式调用不应受记录失败影响');
  });

  test('b2) 前置 FlutterError handler 抛错时兜底不向外传播', () {
    FlutterError.onError = (details) => throw StateError('broken previous');

    CrashGuard.install();

    expect(
      () => FlutterError.reportError(
        FlutterErrorDetails(exception: Exception('still fine')),
      ),
      returnsNormally,
    );
    expect(logLines(), isNotEmpty, reason: '原 handler 失败不影响本地落盘');
  });

  test('c) 挂接保存并链式调用原有 FlutterError handler', () {
    var previousCalls = 0;
    FlutterError.onError = (details) => previousCalls++;
    final previousHandler = FlutterError.onError;

    CrashGuard.install();
    expect(
      FlutterError.onError,
      isNot(same(previousHandler)),
      reason: '挂接后应替换为新 handler',
    );

    FlutterError.reportError(
      FlutterErrorDetails(exception: Exception('chained')),
    );

    expect(previousCalls, 1, reason: '原 handler 应被保存并链式调用');
    expect(logLines().last, contains('chained'));

    // reset 恢复挂接前的 handler。
    CrashGuard.reset();
    expect(FlutterError.onError, same(previousHandler));
  });

  test('install 重复调用幂等，不产生多层包裹', () {
    var previousCalls = 0;
    FlutterError.onError = (details) => previousCalls++;

    CrashGuard.install();
    final firstHandler = FlutterError.onError;
    CrashGuard.install();
    CrashGuard.install();

    expect(FlutterError.onError, same(firstHandler), reason: '重复 install 应幂等');

    FlutterError.reportError(FlutterErrorDetails(exception: Exception('once')));
    expect(previousCalls, 1, reason: '不应被多层包裹导致重复回调');
  });

  test('日志单文件超过上限后重建，避免无限增长', () {
    CrashGuard.install();

    // 每条摘要截断至 ~600 字符，写 900 条越过 512KB 上限后再写一条，
    // 文件应被重建（长度回落），而不是无限增长。
    const filler = 'x';
    for (var i = 0; i < 900; i++) {
      CrashGuard.record(
        source: 'flutter',
        error: Exception('overflow-$i-$filler' * 100),
      );
    }
    CrashGuard.record(source: 'flutter', error: Exception('after-rotate'));

    expect(logFile.existsSync(), isTrue);
    expect(
      logFile.lengthSync(),
      lessThan(600 * 1024),
      reason: '超限后应重建日志文件，不无限增长',
    );
    final lines = logLines();
    expect(lines.last, contains('after-rotate'), reason: '重建后保留最新记录');
  });
}
