import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 禁止 Toast 冒充提醒 静态扫描测试（Task 14.4）。
///
/// Feature: app-alignment-overhaul
/// Property 15 (P15): 在 `lib/` 范围内不存在这样的代码路径：
///   `ReminderConfig.enabled = true` 的触发最终只弹出
///   `ScaffoldMessenger.showSnackBar` 而不发出系统通知 / 闹钟。
///
/// Validates: Requirements 4.6
///
/// 证明策略（静态扫描 + 结构约束，非运行时）：
///   提醒派发的"服务层 + Provider 层"（`lib/services/**` 与
///   `lib/providers/**`）按设计 §2.1 的分层约束，不得直接访问
///   `BuildContext`，也不得向 UI 弹出 SnackBar —— 因此如果这两个目录
///   出现 `.showSnackBar(`，就说明出现了"把 SnackBar 当作提醒落地"的
///   可疑路径（至少是层级违规）。
///
///   具体而言，`ReminderScheduler` / `NotificationService` /
///   `AlarmService` 三条调度路径都位于 `lib/services/` 或
///   `lib/providers/`，所以只要这两层没有 `.showSnackBar(`，
///   就证明 `ReminderConfig.enabled=true` 的触发路径与 SnackBar
///   路径**集合不相交**。SnackBar 合法用法（保存反馈、非提醒类消息）
///   仅允许出现在 `lib/screens/` / `lib/widgets/` 的 UI 层。
///
/// 注意：本测试只扫描 `.dart` 源文件的**代码**部分：
///   - 先剥离 `//` 行注释与 `/* */` 块注释；
///   - 匹配严格的 `.showSnackBar(` 调用形态（含 `..showSnackBar(`
///     的级联调用），避免文档或变量名里的"snackBar"字样误报；
///   - 字符串字面量中的出现也视作违规（不太可能，但额外严格）。
void main() {
  test('P15 - 提醒派发层（lib/services/** + lib/providers/**）'
      '不得调用 ScaffoldMessenger.showSnackBar', () {
    final violations = <_Violation>[];
    for (final dirName in const ['lib/services', 'lib/providers']) {
      final dir = Directory(dirName);
      if (!dir.existsSync()) {
        fail('测试前置条件不满足：目录 $dirName 不存在。请从仓库根目录运行 flutter test。');
      }
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.dart')) continue;
        final relPath = _relativePosixPath(entity);
        final source = entity.readAsStringSync();
        final stripped = _stripDartComments(source);
        final lines = stripped.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('.showSnackBar(')) {
            violations.add(
              _Violation(
                path: relPath,
                lineNumber: i + 1,
                snippet: line.trim(),
              ),
            );
          }
        }
      }
    }
    expect(violations, isEmpty, reason: _formatViolations(violations));
  });

  test('P15 - 提醒派发层不得通过第三方 Toast 库（Fluttertoast / BotToast）绕过', () {
    // 防御性：除 SnackBar 外，也有人会用 fluttertoast / bot_toast。
    // 虽然当前 pubspec 未引入这些依赖，此处仍做一轮静态护栏，避免
    // 后续有人在 services/providers 层偷偷引入"toast 当提醒"。
    final forbiddenPatterns = <RegExp>[
      RegExp(r'\bFluttertoast\b'),
      RegExp(r'\bBotToast\b'),
      RegExp(r'''['"]package:fluttertoast\/'''),
      RegExp(r'''['"]package:bot_toast\/'''),
    ];
    final violations = <_Violation>[];
    for (final dirName in const ['lib/services', 'lib/providers']) {
      final dir = Directory(dirName);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.dart')) continue;
        final relPath = _relativePosixPath(entity);
        final source = entity.readAsStringSync();
        final stripped = _stripDartComments(source);
        final lines = stripped.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          for (final re in forbiddenPatterns) {
            if (re.hasMatch(line)) {
              violations.add(
                _Violation(
                  path: relPath,
                  lineNumber: i + 1,
                  snippet: line.trim(),
                ),
              );
              break;
            }
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason: _formatViolations(violations, kind: 'Toast 库调用'),
    );
  });

  test('P15 - 三个关键提醒派发类所在文件必须存在且零 SnackBar', () {
    // 这是 P15 的"最小闭包"断言：R4.1 明确 ReminderScheduler /
    // NotificationService / AlarmService 是提醒派发的全部承载点；
    // 只要这三处各自的源文件里不出现 `.showSnackBar(`，就等价于
    // "ReminderConfig.enabled=true 的触发路径与 SnackBar 互不交叉"。
    const dispatchFiles = <String>[
      'lib/services/reminder_scheduler.dart',
      'lib/services/alarm_service.dart',
      'lib/providers/notification_service.dart',
    ];
    final missing = <String>[];
    final violations = <_Violation>[];
    for (final rel in dispatchFiles) {
      final file = File(rel);
      if (!file.existsSync()) {
        missing.add(rel);
        continue;
      }
      final source = file.readAsStringSync();
      final stripped = _stripDartComments(source);
      final lines = stripped.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('.showSnackBar(')) {
          violations.add(
            _Violation(path: rel, lineNumber: i + 1, snippet: lines[i].trim()),
          );
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          '关键提醒派发文件缺失：$missing —— 已被重命名/删除？请同步修正本测试的'
          'dispatchFiles 白名单，否则 P15 的结构证明不成立。',
    );
    expect(
      violations,
      isEmpty,
      reason: _formatViolations(violations, kind: 'SnackBar 直接调用'),
    );
  });
}

// ---------------------------------------------------------------------------
// 辅助：违规记录
// ---------------------------------------------------------------------------

class _Violation {
  final String path;
  final int lineNumber;
  final String snippet;
  const _Violation({
    required this.path,
    required this.lineNumber,
    required this.snippet,
  });

  @override
  String toString() => '$path:$lineNumber  $snippet';
}

String _formatViolations(List<_Violation> v, {String kind = 'SnackBar'}) {
  if (v.isEmpty) return '';
  final buf = StringBuffer()
    ..writeln('检测到提醒派发层存在 $kind 路径（P15 违规）：')
    ..writeln('')
    ..writeln('任何位于 lib/services/** 或 lib/providers/** 的代码都不得通过')
    ..writeln('ScaffoldMessenger.showSnackBar 或 Toast 库做用户可见反馈——')
    ..writeln('这条约束是 R4.6 的静态证明：service/provider 层物理上无法访问')
    ..writeln('ScaffoldMessenger，就无法用 SnackBar 顶替系统通知 / 闹钟。')
    ..writeln('合法的 SnackBar 使用场合只能在 lib/screens/** 或 lib/widgets/**。')
    ..writeln('')
    ..writeln('违规点：');
  for (final x in v) {
    buf.writeln('  - $x');
  }
  return buf.toString();
}

String _relativePosixPath(File file) {
  final current = _toPosix(Directory.current.absolute.path);
  final path = _toPosix(file.absolute.path);
  final prefix = current.endsWith('/') ? current : '$current/';
  if (path.startsWith(prefix)) {
    return path.substring(prefix.length);
  }
  return _toPosix(file.path);
}

// ---------------------------------------------------------------------------
// 辅助：剥离 Dart 注释（// 行注释 + /* */ 块注释），保留字符串字面量原样。
// ---------------------------------------------------------------------------

String _stripDartComments(String source) {
  final out = StringBuffer();
  final len = source.length;
  int i = 0;
  // 状态机：0=普通, 1=单行注释, 2=块注释, 3=单引号字符串, 4=双引号字符串,
  //         5=三单引号字符串, 6=三双引号字符串, 7=单引号 raw, 8=双引号 raw
  // 简化：为了健壮性只区分 normal / line-comment / block-comment /
  //       single-string / double-string / triple-single / triple-double。
  // 转义字符 `\` 在字符串内保留原样。
  while (i < len) {
    final c = source[i];
    final next = i + 1 < len ? source[i + 1] : '';
    final next2 = i + 2 < len ? source[i + 2] : '';

    // 行注释 `//...\n`
    if (c == '/' && next == '/') {
      while (i < len && source[i] != '\n') {
        i++;
      }
      if (i < len) {
        out.write('\n'); // 保留换行以对齐行号
        i++;
      }
      continue;
    }
    // 块注释 `/* ... */`
    if (c == '/' && next == '*') {
      i += 2;
      while (i < len) {
        if (source[i] == '*' && i + 1 < len && source[i + 1] == '/') {
          i += 2;
          break;
        }
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      continue;
    }
    // 三引号字符串：原样保留
    if ((c == '"' || c == "'") && next == c && next2 == c) {
      final quote = c;
      out.write(source[i]);
      out.write(source[i + 1]);
      out.write(source[i + 2]);
      i += 3;
      while (i < len) {
        if (source[i] == quote &&
            i + 1 < len &&
            source[i + 1] == quote &&
            i + 2 < len &&
            source[i + 2] == quote) {
          out.write(source[i]);
          out.write(source[i + 1]);
          out.write(source[i + 2]);
          i += 3;
          break;
        }
        out.write(source[i]);
        i++;
      }
      continue;
    }
    // 单引号 / 双引号字符串：原样保留，处理 `\x` 转义
    if (c == '"' || c == "'") {
      final quote = c;
      out.write(c);
      i++;
      while (i < len) {
        final ch = source[i];
        if (ch == r'\' && i + 1 < len) {
          out.write(ch);
          out.write(source[i + 1]);
          i += 2;
          continue;
        }
        out.write(ch);
        i++;
        if (ch == quote) break;
        if (ch == '\n') break; // 单行字符串遇到换行即终止
      }
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

String _toPosix(String path) => path.replaceAll(r'\', '/');
