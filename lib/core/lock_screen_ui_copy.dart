/// Lock Screen UI localization and dynamic copy getters (Task: iOS style & i18n).
library;

import 'i18n.dart';

enum LockScreenError {
  wrongPin,
  verificationFailed,
}

class LockScreenUiCopy {
  LockScreenUiCopy._();

  static bool get isZh => I18n.current == AppLocale.zh;

  static String get unlock => isZh ? '解锁' : 'Unlock';
  static String get submitTooltip => isZh ? '提交 PIN 码' : 'Submit PIN';
  static String get deleteTooltip => isZh ? '删除' : 'Delete';
  static String get busyMessage => isZh ? '正在验证…' : 'Verifying…';
  static String get failedRetry =>
      isZh ? '解锁失败，请重试' : 'Unlock failed. Please try again.';

  static String errorMessage(LockScreenError error) {
    return switch (error) {
      LockScreenError.wrongPin => I18n.tr('app_lock.pin_wrong'),
      LockScreenError.verificationFailed => failedRetry,
    };
  }

  static String digitSemantics(String digit) {
    return isZh ? '数字 $digit' : 'Digit $digit';
  }

  static String enteredDigitsSemantics(int count) {
    return isZh ? '已输入 $count 位' : '$count digits entered';
  }
}
