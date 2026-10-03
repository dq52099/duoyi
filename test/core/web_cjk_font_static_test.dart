import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('web CJK fallback font is registered and used by app themes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final brand = File('lib/core/app_brand.dart').readAsStringSync();

    expect(
      pubspec,
      contains(
        'family: DroidSansFallbackFull\n'
        '      fonts:\n'
        '        - asset: assets/fonts/DroidSansFallbackFull.ttf',
      ),
    );
    expect(brand, contains("const String _cnFontFamily = 'sans-serif';"));
    expect(brand, contains('fontFamilyFallback: _cnFontFallback'));
    expect(brand, contains("'DroidSansFallbackFull'"));
    expect(File('assets/fonts/DroidSansFallbackFull.ttf').existsSync(), isTrue);
  });
}
