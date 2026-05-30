import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('source tree does not contain forbidden injected identifiers', () {
    const forbidden = [
      '1104'
          '138863',
    ];
    final roots = [
      Directory('lib'),
      Directory('backend'),
      Directory('android/app/src/main'),
      Directory('test'),
      Directory('docs'),
    ];
    final hits = <String>[];

    for (final root in roots.where((root) => root.existsSync())) {
      final files =
          root
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => !_isGeneratedOrBinary(file.path))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final text = file.readAsStringSync();
        for (final token in forbidden) {
          if (!text.contains(token)) continue;
          hits.add('${file.path}: $token');
        }
      }
    }

    expect(
      hits,
      isEmpty,
      reason: 'Forbidden injected identifiers must not appear in source.',
    );
  });
}

bool _isGeneratedOrBinary(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.apk') ||
      lower.endsWith('.db') ||
      lower.endsWith('.zip') ||
      lower.endsWith('.pyc') ||
      lower.endsWith('.g.dart') ||
      lower.contains('/__pycache__/') ||
      lower.contains('/backups/') ||
      lower.contains('/build/');
}
