import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool _loaded = false;
Future<void>? _fontRegistration;

/// Use packaged fonts for readable optional evidence instead of test glyphs.
Future<void> loadWidgetPolishScreenshotFonts() async {
  final pending = _fontRegistration;
  if (pending != null) {
    await pending;
    return;
  }
  if (_loaded) return;
  final registration = _registerWidgetPolishScreenshotFonts();
  _fontRegistration = registration;
  try {
    await registration;
  } catch (_) {
    _loaded = false;
    rethrow;
  } finally {
    _fontRegistration = null;
  }
}

Future<void> _registerWidgetPolishScreenshotFonts() async {
  // These native fonts remain registered for the lifetime of this test engine.
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
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
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
