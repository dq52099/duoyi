import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('unwanted public group injection is not present in project sources', () {
    const roots = ['lib', 'android', 'backend', 'docs', 'test'];
    final blocked = [
      ['1104', '138863'].join(),
      ['Public', 'Token', 'Notice'].join(),
      ['public', 'token', 'notice'].join('_'),
      ['公益 ', 'token2'].join(),
    ];

    final offenders = <String>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (path.contains('/build/') ||
            path.contains('/artifacts/') ||
            path.contains('/backend/uploads/')) {
          continue;
        }
        if (!_isTextSource(path)) continue;
        final content = entity.readAsStringSync();
        for (final token in blocked) {
          if (content.contains(token)) {
            offenders.add('$path contains $token');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

bool _isTextSource(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.dart') ||
      lower.endsWith('.kt') ||
      lower.endsWith('.kts') ||
      lower.endsWith('.java') ||
      lower.endsWith('.swift') ||
      lower.endsWith('.xml') ||
      lower.endsWith('.gradle') ||
      lower.endsWith('.properties') ||
      lower.endsWith('.yaml') ||
      lower.endsWith('.yml') ||
      lower.endsWith('.json') ||
      lower.endsWith('.arb') ||
      lower.endsWith('.md') ||
      lower.endsWith('.py') ||
      lower.endsWith('.txt') ||
      lower.endsWith('.sh') ||
      lower.endsWith('.html') ||
      lower.endsWith('.css') ||
      lower.endsWith('.js') ||
      lower.endsWith('.ts') ||
      lower.endsWith('.plist') ||
      lower.endsWith('.pbxproj') ||
      lower.endsWith('.xcconfig');
}
