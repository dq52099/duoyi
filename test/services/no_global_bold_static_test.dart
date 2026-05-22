import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('应用 UI 不再引入全局粗体字重', () {
    final bannedWeight = RegExp(r'FontWeight\.(bold|w[5-9]00)');
    final offenders = <String>[];

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (bannedWeight.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '用户要求去掉全局粗体；新增 UI 请使用主题默认字重或 FontWeight.w400。',
    );
  });
}
