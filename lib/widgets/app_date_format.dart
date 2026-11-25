import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/i18n_date_format.dart';
import '../providers/preferences_provider.dart';

/// Date presentation for the current preference scope. Listening methods are
/// for builds; callbacks and exports should capture a pattern or use readPattern.
class AppDateFormat {
  AppDateFormat._();

  static String? patternOf(BuildContext context) =>
      context.select<PreferencesProvider?, String?>(
        (preferences) => preferences?.dateFormat,
      );

  static String? readPattern(BuildContext context) =>
      context.read<PreferencesProvider?>()?.dateFormat;

  static String date(BuildContext context, DateTime value) =>
      I18nDateFormat.date(value, pattern: patternOf(context));

  static String fullDateTime(BuildContext context, DateTime value) =>
      I18nDateFormat.fullDateTime(value, pattern: patternOf(context));

  static String smartDate(
    BuildContext context,
    DateTime value, {
    required bool includeTime,
  }) => I18nDateFormat.smartDate(
    value,
    includeTime: includeTime,
    pattern: patternOf(context),
  );
}
