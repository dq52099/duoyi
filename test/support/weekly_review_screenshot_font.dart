import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widget_polish_screenshot_font.dart';

final Map<String?, Future<void>> _fontRegistrations = {};

/// Register readable fixture fonts under the production theme's family names.
/// Keep its sizes, weights, colors and component styles unchanged.
Future<void> loadWeeklyReviewScreenshotFonts({String? emojiFontPath}) async {
  final pending = _fontRegistrations[emojiFontPath];
  if (pending != null) {
    await pending;
    return;
  }
  // Engine font registrations survive individual widget tests. Re-registering
  // the same data retains another native copy for every layout case.
  final registration = _registerWeeklyReviewScreenshotFonts(
    emojiFontPath: emojiFontPath,
  );
  _fontRegistrations[emojiFontPath] = registration;
  try {
    await registration;
  } catch (_) {
    if (identical(_fontRegistrations[emojiFontPath], registration)) {
      _fontRegistrations.remove(emojiFontPath);
    }
    rethrow;
  }
}

Future<void> _registerWeeklyReviewScreenshotFonts({
  String? emojiFontPath,
}) async {
  await loadWidgetPolishScreenshotFonts();
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    // The final existing fallback can supply emoji in Linux-only evidence.
    // Earlier families still provide CJK; production theme data is unchanged.
    final emojiFile = emojiFontPath != null ? File(emojiFontPath) : null;
    final font =
        family == 'DroidSansFallbackFull' &&
            emojiFile != null &&
            emojiFile.existsSync()
        ? ByteData.sublistView(emojiFile.readAsBytesSync())
        : chinese;
    await (FontLoader(family)..addFont(Future.value(font))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}
