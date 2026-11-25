/// UI copy for lock settings screens and feedback.
library;

import 'i18n.dart';

class LockSettingsUiCopy {
  LockSettingsUiCopy._();

  static bool get isZh => I18n.current == AppLocale.zh;

  /// Concise bilingual failure feedback when saving settings fails.
  static String get saveFailed =>
      isZh ? '无法保存设置，请重试' : 'Could not save settings. Please try again.';
}
