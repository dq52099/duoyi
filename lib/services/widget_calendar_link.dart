import '../core/heatmap_calendar.dart';

/// A civil calendar date, independent of the device's UTC offset.
class WidgetCalendarLink {
  static const _singletonKeys = {
    'date',
    'source',
    'widget_delivery',
    'widget_day',
    'widget_offset',
    'widget_account',
  };

  static bool isCalendarUri(Uri uri) =>
      uri.scheme == 'duoyi' && uri.host == 'calendar';

  static bool hasDateRequest(Uri uri) {
    if (!isCalendarUri(uri)) return false;
    try {
      return uri.queryParametersAll.containsKey('date');
    } on FormatException {
      // Undecodable calendar input can only open the section, never a date.
      return true;
    }
  }

  static DateTime? dateFromUri(Uri uri) {
    if (!isCalendarUri(uri) ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    try {
      final parameters = uri.queryParametersAll;
      if (parameters.keys.any((key) => !_singletonKeys.contains(key))) {
        return null;
      }
      for (final key in _singletonKeys) {
        if ((parameters[key]?.length ?? 0) > 1) return null;
      }
      final values = parameters['date'];
      if (values == null || values.length != 1) return null;
      return HeatmapCalendarWindow.tryParseDateKey(values.single);
    } on FormatException {
      return null;
    }
  }
}
