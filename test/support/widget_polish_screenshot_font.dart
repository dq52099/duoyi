import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool _loaded = false;

/// Use packaged fonts for readable optional evidence instead of test glyphs.
Future<void> loadWidgetPolishScreenshotFonts() async {
  if (_loaded) return;
  final textBytes = File(
    'assets/fonts/DroidSansFallbackFull.ttf',
  ).readAsBytesSync();
  await (FontLoader(
    'DuoyiScreenshot',
  )..addFont(Future.value(ByteData.sublistView(textBytes)))).load();
  final iconBytes = File(
    'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  ).readAsBytesSync();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
  final latin = File(
    Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT'] ??
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  );
  if (latin.existsSync()) {
    final bytes = ByteData.sublistView(latin.readAsBytesSync());
    for (final family in ['DuoyiScreenshotLatin', 'Ahem', 'monospace']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  _loaded = true;
}

ThemeData widgetPolishScreenshotTheme() {
  final theme = _loaded
      ? ThemeData(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        )
      : ThemeData();
  return _loaded
      ? theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'DuoyiScreenshotLatin'),
          primaryTextTheme: theme.primaryTextTheme.apply(
            fontFamily: 'DuoyiScreenshotLatin',
          ),
        )
      : theme;
}
