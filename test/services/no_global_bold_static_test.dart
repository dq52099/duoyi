import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('应用 UI 不再引入全局粗体字重', () {
    final bannedWeight = RegExp(r'FontWeight\.(bold|w[5-9]00)');
    final bannedTokenUse = RegExp(r'\bDesignTokens\.fontWeightMedium\b');
    final offenders = <String>[];

    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (bannedWeight.hasMatch(line) || bannedTokenUse.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '用户要求去掉全局粗体；新增 UI 请使用主题默认字重或 FontWeight.normal，不再正向使用 DesignTokens.fontWeightMedium。',
    );
  });

  test('全局设计令牌和管理后台不再提供粗体入口', () {
    final bannedWeight = RegExp(r'FontWeight\.(bold|w[5-9]00)');
    final designTokens = File('lib/core/design_tokens.dart').readAsStringSync();
    final appBrand = File('lib/core/app_brand.dart').readAsStringSync();
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    for (final source in [designTokens, appBrand, admin, surface]) {
      expect(source, isNot(contains('DesignTokens.fontWeightMedium')));
      expect(source, isNot(bannedWeight));
    }

    final adminExplicitWeights = RegExp(
      r'fontWeight:\s+FontWeight\.(\w+)',
    ).allMatches(admin).map((match) => match.group(1)).toSet();

    expect(
      adminExplicitWeights,
      everyElement(equals('normal')),
      reason: '管理员后台用户明确要求不要粗体，显式字重只能是 normal。',
    );

    final adminFontWeightAssignments = RegExp(
      r'fontWeight:\s*([^,\n)]+)',
    ).allMatches(admin).map((match) => match.group(1)!.trim()).toList();

    expect(
      adminFontWeightAssignments,
      everyElement(equals('FontWeight.normal')),
      reason: '管理员后台不应通过局部 TextStyle 或主题样式恢复粗体；如需显式声明，只允许 FontWeight.normal。',
    );
  });
}
