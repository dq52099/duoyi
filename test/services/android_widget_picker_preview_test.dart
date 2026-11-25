import 'dart:io';

import 'package:test/test.dart';

const _resourceRoot = 'android/app/src/main/res/';
const _layouts = [
  'duoyi_widget_preview_compact.xml',
  'duoyi_widget_preview_standard.xml',
  'duoyi_widget_preview_detailed.xml',
];
const _drawableRoot = '${_resourceRoot}drawable/';
const _rootBackgroundFile = 'widget_picker_preview_background.xml';
const _navBackgroundFile = 'widget_picker_preview_nav_background.xml';
const _rootBackgroundReference =
    'android:background="@drawable/widget_picker_preview_background"';
const _navBackgroundReference =
    'android:background="@drawable/widget_picker_preview_nav_background"';

String _read(String path) => File(path).readAsStringSync();

Set<String> _stringKeys(String xml) => RegExp(
  r'<string\s+name="([^"]+)"(?:\s+translatable="false")?>',
).allMatches(xml).map((match) => match.group(1)!).toSet();

void main() {
  group('Android widget picker previews', () {
    final chineseStrings = _read(
      '${_resourceRoot}values/widget_preview_strings.xml',
    );
    final englishStrings = _read(
      '${_resourceRoot}values-en/widget_preview_strings.xml',
    );
    final chineseKeys = _stringKeys(chineseStrings);
    final englishKeys = _stringKeys(englishStrings);

    test('all visible copy uses matching localized string resources', () {
      expect(englishKeys, equals(chineseKeys));
      expect(RegExp(r'[\u3400-\u9fff]').hasMatch(englishStrings), isFalse);

      final referencedKeys = <String>{};
      final stringReference = RegExp(r'^@string/([A-Za-z0-9_]+)$');
      final dimensionLiteral = RegExp(r'^\d+[×x]\d+$');
      for (final layoutName in _layouts) {
        final path = '${_resourceRoot}layout/$layoutName';
        final layout = _read(path);
        final textValues = RegExp(
          r'android:text="([^"]*)"',
        ).allMatches(layout).map((match) => match.group(1)!);

        expect(textValues, isNotEmpty, reason: layoutName);
        for (final value in textValues) {
          final resourceMatch = stringReference.firstMatch(value);
          if (resourceMatch != null) {
            referencedKeys.add(resourceMatch.group(1)!);
          } else {
            expect(
              dimensionLiteral.hasMatch(value),
              isTrue,
              reason: '$layoutName has an unlocalized text literal: $value',
            );
          }
        }
        expect(
          RegExp(r'[\u3400-\u9fff]').hasMatch(layout),
          isFalse,
          reason: '$layoutName contains a hard-coded Chinese literal',
        );
      }

      expect(referencedKeys, isNotEmpty);
      expect(chineseKeys, containsAll(referencedKeys));
      expect(englishKeys, containsAll(referencedKeys));
    });

    test('all previews use standalone preview background drawables', () {
      final rootBackground = '$_drawableRoot$_rootBackgroundFile';
      final navBackground = '$_drawableRoot$_navBackgroundFile';
      expect(File(rootBackground).existsSync(), isTrue);
      expect(File(navBackground).existsSync(), isTrue);
      expect(_read(rootBackground), contains('<shape'));
      expect(_read(navBackground), contains('<shape'));

      for (final layoutName in _layouts) {
        final layout = _read('${_resourceRoot}layout/$layoutName');
        expect(layout, contains(_rootBackgroundReference), reason: layoutName);
        expect(layout, contains(_navBackgroundReference), reason: layoutName);
        expect(
          layout,
          isNot(contains('@drawable/widget_bg')),
          reason: layoutName,
        );
        expect(
          layout,
          isNot(contains('@drawable/widget_nav_bg')),
          reason: layoutName,
        );
      }
    });
  });
}
