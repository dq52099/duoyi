/// Locale-aware date and time formatting helpers.
///
/// Keep user-facing dates here instead of scattering manual padLeft patterns
/// through screens. Storage keys and wire formats should continue to use their
/// existing stable serializers.
library;

import 'i18n.dart';

class I18nDateFormat {
  I18nDateFormat._();

  static const defaultPattern = 'yyyy-MM-dd';
  static const supportedPatterns = <String>{
    defaultPattern,
    'MM/dd/yyyy',
    'dd/MM/yyyy',
    'yyyy年M月d日',
  };

  static String normalizePattern(String? pattern) =>
      supportedPatterns.contains(pattern) ? pattern! : defaultPattern;

  static String fullDateTime(
    DateTime value, {
    String? pattern,
    AppLocale? locale,
  }) {
    final effectiveLocale = locale ?? I18n.current;
    return '${date(value, pattern: pattern, locale: effectiveLocale)} '
        '${_weekdayShort(value, effectiveLocale)} ${time(value, locale: effectiveLocale)}';
  }

  static String yearMonth(DateTime value) {
    return switch (I18n.current) {
      AppLocale.en => '${_enMonth(value.month)} ${value.year}',
      AppLocale.zh => '${value.year}年${value.month}月',
    };
  }

  static String date(DateTime value, {String? pattern, AppLocale? locale}) {
    if (pattern != null) {
      final year = value.year.toString().padLeft(4, '0');
      final month = _twoDigits(value.month);
      final day = _twoDigits(value.day);
      return switch (normalizePattern(pattern)) {
        'MM/dd/yyyy' => '$month/$day/$year',
        'dd/MM/yyyy' => '$day/$month/$year',
        'yyyy年M月d日' => '${value.year}年${value.month}月${value.day}日',
        _ => '$year-$month-$day',
      };
    }
    return switch (locale ?? I18n.current) {
      AppLocale.en => '${_enMonth(value.month)} ${value.day}, ${value.year}',
      AppLocale.zh => '${value.year}年${value.month}月${value.day}日',
    };
  }

  static String time(DateTime value, {AppLocale? locale}) {
    return switch (locale ?? I18n.current) {
      AppLocale.en => _enTime(value),
      AppLocale.zh => '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}',
    };
  }

  static String timeOfDay({required int hour, required int minute}) {
    final value = DateTime(2000, 1, 1, hour, minute);
    return time(value);
  }

  static String monthDay(DateTime value) {
    return switch (I18n.current) {
      AppLocale.en => '${_enMonth(value.month)} ${value.day}',
      AppLocale.zh => '${value.month}月${value.day}日',
    };
  }

  static String monthDayWithWeekday(DateTime value) {
    return switch (I18n.current) {
      AppLocale.en => '${monthDay(value)} · ${_weekdayShort(value)}',
      AppLocale.zh => '${monthDay(value)} · ${_weekdayShort(value)}',
    };
  }

  static String shortDateTime(DateTime value) {
    return switch (I18n.current) {
      AppLocale.en => '${monthDay(value)} ${time(value)}',
      AppLocale.zh => '${monthDay(value)} ${time(value)}',
    };
  }

  static String smartDate(
    DateTime value, {
    required bool includeTime,
    String? pattern,
    AppLocale? locale,
  }) {
    if (!includeTime) return date(value, pattern: pattern, locale: locale);
    return fullDateTime(value, pattern: pattern, locale: locale);
  }

  static String compactDateTime(
    DateTime value, {
    bool omitTimeWhenMidnight = false,
  }) {
    final includeTime =
        !omitTimeWhenMidnight || value.hour != 0 || value.minute != 0;
    if (!includeTime) return monthDay(value);
    return shortDateTime(value);
  }

  static String _weekdayShort(DateTime value, [AppLocale? locale]) {
    const zh = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const en = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final index = (value.weekday - DateTime.monday).clamp(0, 6);
    return switch (locale ?? I18n.current) {
      AppLocale.en => en[index],
      AppLocale.zh => zh[index],
    };
  }

  static String _enMonth(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  static String _enTime(DateTime value) {
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return '$hour:${_twoDigits(value.minute)} $suffix';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
