import 'package:flutter/foundation.dart';

class WebTarget {
  static const String raw = String.fromEnvironment(
    'DUOYI_WEB_TARGET',
    defaultValue: 'responsive',
  );

  static bool get isDesktopWebBuild => kIsWeb && raw == 'desktop';
  static bool get isMobileWebBuild => kIsWeb && raw == 'mobile';
}
