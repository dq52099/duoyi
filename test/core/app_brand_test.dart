import 'dart:io';

import 'package:duoyi/core/app_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _resolveColor(WidgetStateProperty<Color?>? property, String label) {
  final color = property?.resolve(const <WidgetState>{});
  expect(color, isNotNull, reason: '$label should resolve a color.');
  return color!;
}

Color _resolveSelectedColor(
  WidgetStateProperty<Color?>? property,
  String label,
) {
  final color = property?.resolve(const <WidgetState>{WidgetState.selected});
  expect(color, isNotNull, reason: '$label should resolve a selected color.');
  return color!;
}

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
    expect(source, contains('Color _buttonActionBackground'));
    expect(
      source,
      contains('final primaryForeground = _highContrastForeground'),
    );
    expect(
      source,
      contains('final actionBackground = _buttonActionBackground'),
    );
    expect(
      source,
      contains('final actionForeground = _highContrastForeground'),
    );
    expect(source, contains('backgroundColor: actionBackground'));
    expect(source, contains('foregroundColor: actionForeground'));
    expect(source, contains('foregroundColor: actionBackground'));
    expect(
      source,
      contains('final selectedControlBackground = Color.alphaBlend('),
    );
    expect(
      source,
      contains('cs.primary.withValues(alpha: isDark ? 0.20 : 0.14)'),
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
    expect(
      source,
      isNot(contains('color: cs.primary.withValues(alpha: 0.12)')),
    );
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
    expect(
      source,
      isNot(contains('foregroundColor: cs.onSurfaceVariant,\n        padding')),
    );
  });

  test('global button themes resolve compact readable colors', () {
    for (final brand in AppBrands.all) {
      final theme = brand.theme;
      final surface = theme.colorScheme.surface;
      final filled = theme.filledButtonTheme.style;
      final elevated = theme.elevatedButtonTheme.style;
      final outlined = theme.outlinedButtonTheme.style;
      final text = theme.textButtonTheme.style;
      final segmented = theme.segmentedButtonTheme.style;

      expect(filled, isNotNull, reason: '${brand.id} filled button theme');
      expect(elevated, isNotNull, reason: '${brand.id} elevated button theme');
      expect(outlined, isNotNull, reason: '${brand.id} outlined button theme');
      expect(text, isNotNull, reason: '${brand.id} text button theme');
      expect(segmented, isNotNull, reason: '${brand.id} segmented theme');

      final filledBg = _resolveColor(
        filled!.backgroundColor,
        '${brand.id} filled background',
      );
      final filledFg = _resolveColor(
        filled.foregroundColor,
        '${brand.id} filled foreground',
      );
      expect(
        _contrastRatio(filledBg, filledFg),
        greaterThanOrEqualTo(4.5),
        reason: '${brand.id} filled button foreground must stay readable.',
      );
      expect(filled.minimumSize?.resolve(const <WidgetState>{})?.height, 40);

      final elevatedBg = _resolveColor(
        elevated!.backgroundColor,
        '${brand.id} elevated background',
      );
      final elevatedFg = _resolveColor(
        elevated.foregroundColor,
        '${brand.id} elevated foreground',
      );
      expect(
        _contrastRatio(elevatedBg, elevatedFg),
        greaterThanOrEqualTo(4.5),
        reason: '${brand.id} elevated button foreground must stay readable.',
      );
      expect(elevated.minimumSize?.resolve(const <WidgetState>{})?.height, 40);

      final outlinedFg = _resolveColor(
        outlined!.foregroundColor,
        '${brand.id} outlined foreground',
      );
      expect(
        _contrastRatio(outlinedFg, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${brand.id} outlined button text must contrast surface.',
      );
      expect(outlined.minimumSize?.resolve(const <WidgetState>{})?.height, 38);

      final textFg = _resolveColor(
        text!.foregroundColor,
        '${brand.id} text foreground',
      );
      expect(
        _contrastRatio(textFg, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${brand.id} text button color must contrast surface.',
      );
      expect(text.minimumSize?.resolve(const <WidgetState>{})?.height, 36);

      final segmentBg = _resolveSelectedColor(
        segmented!.backgroundColor,
        '${brand.id} segmented selected background',
      );
      final segmentFg = _resolveSelectedColor(
        segmented.foregroundColor,
        '${brand.id} segmented selected foreground',
      );
      expect(
        _contrastRatio(segmentBg, segmentFg),
        greaterThanOrEqualTo(4.5),
        reason: '${brand.id} segmented selected text must stay readable.',
      );
    }
  });
}
