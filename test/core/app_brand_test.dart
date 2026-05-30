import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('default brand uses Duoyi name', () {
    final source = File('lib/core/app_brand.dart').readAsStringSync();
    final strings = File('lib/core/brand_strings.dart').readAsStringSync();
    expect(source, contains("name: '多仪'"));
    expect(strings, contains("appTitle: '多仪'"));
  });

  test('selected controls use readable foreground tokens', () {
    final source = File('lib/core/app_brand.dart').readAsStringSync();

    expect(source, contains('Color _highContrastForeground'));
    expect(
      source,
      contains('final primaryForeground = _highContrastForeground'),
    );
    expect(source, contains('return primaryForeground;'));
    expect(source, contains('foregroundColor: primaryForeground'));
    expect(
      source,
      contains('final selectedControlBackground = Color.alphaBlend('),
    );
    expect(
      source,
      contains('cs.primary.withValues(alpha: isDark ? 0.14 : 0.09)'),
    );
    expect(source, contains('final selectedControlForeground'));
    expect(source, contains('return selectedControlForeground;'));
    expect(source, contains('final selectedTabBackground = Color.alphaBlend'));
    expect(source, contains('final selectedTabForeground'));
    expect(source, contains('final selectedNavigationBackground'));
    expect(source, contains('final selectedNavigationForeground'));
    expect(source, contains('color: selectedTabBackground'));
    expect(source, contains('indicatorColor: selectedNavigationBackground'));
    expect(source, contains('labelColor: selectedTabForeground'));
    expect(source, contains('color: selected ? selectedNavigationForeground'));
    expect(source, isNot(contains('color: cs.primary.withValues(alpha: 0.12)')));
    expect(
      source,
      isNot(contains('indicatorColor: cs.primary.withValues(alpha: 0.14)')),
    );
    expect(source, isNot(contains('labelColor: cs.primary')));
    expect(source, isNot(contains('color: selected ? cs.primary')));
    expect(source, contains('selectedColor: selectedControlBackground'));
    expect(
      source,
      contains('secondaryLabelStyle: theme.textTheme.labelMedium?.copyWith('),
    );
    expect(source, contains('color: selectedControlForeground'));
    expect(
      source,
      contains('checkColor: WidgetStatePropertyAll<Color>(primaryForeground)'),
    );
  });
}
