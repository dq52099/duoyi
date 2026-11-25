import 'dart:convert';

import '../core/i18n.dart';

enum WidgetPublicationState { published, cleared, blocked }

enum _WidgetValueType { string, int32, int64, boolean }

/// One complete account/presentation snapshot for the native publication store.
///
/// This descriptor does not authorize a write: the platform must independently
/// compare the expected owner and revisions before accepting its replacement.
/// Instance display modes and launcher options remain outside this document.
class WidgetPublication {
  WidgetPublication({
    required this.ownerEpoch,
    required this.publicationRevision,
    required this.localeRevision,
    required this.state,
    required this.locale,
    required this.snapshotDay,
    required this.snapshotUtcOffsetMinutes,
    required this.capturedAtMillis,
    required Map<String, Object> values,
  }) : values = Map<String, Object>.unmodifiable(values) {
    if (!_valid()) {
      throw const FormatException('Invalid complete widget publication');
    }
  }

  static const storageKey = 'duoyi_widget_publication_v1';
  static const schemaVersion = 1;
  static const maxExactJsonInteger = 9007199254740991;
  static const _documentKeys = {
    'schemaVersion',
    'ownerEpoch',
    'publicationRevision',
    'localeRevision',
    'state',
    'locale',
    'snapshotDay',
    'snapshotUtcOffsetMinutes',
    'capturedAtMillis',
    'values',
  };

  // v1 is a full replacement, never a patch into residual legacy account data.
  static const _valueTypes = <String, _WidgetValueType>{
    'todo_count': _WidgetValueType.int32,
    'habit_percent': _WidgetValueType.int32,
    'habit_active_count': _WidgetValueType.int32,
    'pomodoro_today': _WidgetValueType.int32,
    'focus_minutes_today': _WidgetValueType.int32,
    'brand_app_title': _WidgetValueType.string,
    'nav_todo': _WidgetValueType.string,
    'nav_habit': _WidgetValueType.string,
    'nav_calendar': _WidgetValueType.string,
    'nav_focus': _WidgetValueType.string,
    'widget_first_day_of_week': _WidgetValueType.int32,
    'todo_top3_count': _WidgetValueType.int32,
    'todo_top3_1': _WidgetValueType.string,
    'todo_top3_1_id': _WidgetValueType.string,
    'todo_top3_2': _WidgetValueType.string,
    'todo_top3_2_id': _WidgetValueType.string,
    'todo_top3_3': _WidgetValueType.string,
    'todo_top3_3_id': _WidgetValueType.string,
    'goal_highlight_1': _WidgetValueType.string,
    'goal_highlight_1_id': _WidgetValueType.string,
    'goal_highlight_2': _WidgetValueType.string,
    'goal_highlight_2_id': _WidgetValueType.string,
    'goal_highlight_3': _WidgetValueType.string,
    'goal_highlight_3_id': _WidgetValueType.string,
    'anniversary_highlight_1': _WidgetValueType.string,
    'anniversary_highlight_1_id': _WidgetValueType.string,
    'anniversary_highlight_2': _WidgetValueType.string,
    'anniversary_highlight_2_id': _WidgetValueType.string,
    'course_highlight_1': _WidgetValueType.string,
    'course_highlight_1_id': _WidgetValueType.string,
    'course_highlight_2': _WidgetValueType.string,
    'course_highlight_2_id': _WidgetValueType.string,
    'course_highlight_3': _WidgetValueType.string,
    'course_highlight_3_id': _WidgetValueType.string,
    'note_highlight_1': _WidgetValueType.string,
    'note_highlight_1_id': _WidgetValueType.string,
    'note_highlight_2': _WidgetValueType.string,
    'note_highlight_2_id': _WidgetValueType.string,
    'note_highlight_3': _WidgetValueType.string,
    'note_highlight_3_id': _WidgetValueType.string,
    'memorial_highlight_1': _WidgetValueType.string,
    'memorial_highlight_1_id': _WidgetValueType.string,
    'memorial_highlight_2': _WidgetValueType.string,
    'memorial_highlight_2_id': _WidgetValueType.string,
    'memorial_highlight_3': _WidgetValueType.string,
    'memorial_highlight_3_id': _WidgetValueType.string,
    'diary_highlight_1': _WidgetValueType.string,
    'diary_highlight_1_id': _WidgetValueType.string,
    'diary_highlight_2': _WidgetValueType.string,
    'diary_highlight_2_id': _WidgetValueType.string,
    'diary_highlight_3': _WidgetValueType.string,
    'diary_highlight_3_id': _WidgetValueType.string,
    'today_event_summary': _WidgetValueType.string,
    'schedule_highlight_1': _WidgetValueType.string,
    'schedule_highlight_1_id': _WidgetValueType.string,
    'schedule_highlight_2': _WidgetValueType.string,
    'schedule_highlight_2_id': _WidgetValueType.string,
    'schedule_highlight_3': _WidgetValueType.string,
    'schedule_highlight_3_id': _WidgetValueType.string,
    'calendar_month_summary': _WidgetValueType.string,
    'focus_summary': _WidgetValueType.string,
    'habit_summary': _WidgetValueType.string,
    'streak_summary': _WidgetValueType.string,
    'next_focus_label': _WidgetValueType.string,
    'focus_timer_count_up': _WidgetValueType.boolean,
    'focus_timer_started_at_millis': _WidgetValueType.int64,
    'focus_timer_running': _WidgetValueType.boolean,
    'focus_timer_remaining_seconds': _WidgetValueType.int32,
    'focus_timer_total_seconds': _WidgetValueType.int32,
    'focus_timer_ends_at_millis': _WidgetValueType.int64,
    'focus_timer_label': _WidgetValueType.string,
    'habit_quick_check_id': _WidgetValueType.string,
    'habit_quick_check_label': _WidgetValueType.string,
    'widget_theme_brand_id': _WidgetValueType.string,
    'widget_theme_card_skin_id': _WidgetValueType.string,
    'widget_theme_dark': _WidgetValueType.boolean,
    'widget_theme_primary': _WidgetValueType.string,
    'widget_theme_background': _WidgetValueType.string,
    'widget_theme_surface': _WidgetValueType.string,
    'widget_theme_nav_background': _WidgetValueType.string,
    'widget_theme_border': _WidgetValueType.string,
    'widget_theme_text': _WidgetValueType.string,
    'widget_theme_muted_text': _WidgetValueType.string,
    'widget_theme_on_primary': _WidgetValueType.string,
    'widget_theme_accent_start': _WidgetValueType.string,
    'widget_theme_accent_end': _WidgetValueType.string,
    'widget_theme_background_asset_key': _WidgetValueType.string,
    'widget_theme_corner_radius_dp': _WidgetValueType.int32,
    'widget_theme_control_radius_dp': _WidgetValueType.int32,
    'widget_theme_border_width_dp': _WidgetValueType.int32,
  };

  final String ownerEpoch;
  final int publicationRevision;

  /// Monotonic desired presentation version: locale, theme and calendar layout.
  /// Platform acceptance must compare this with its durable desired floor.
  final int localeRevision;
  final WidgetPublicationState state;
  final AppLocale locale;
  final String snapshotDay;
  final int snapshotUtcOffsetMinutes;
  final int capturedAtMillis;
  final Map<String, Object> values;

  static Set<String> get valueKeys =>
      Set<String>.unmodifiable(_valueTypes.keys);

  static bool _isBusinessValue(String key) =>
      !key.startsWith('widget_theme_') &&
      key != 'widget_first_day_of_week' &&
      key != 'brand_app_title' &&
      !key.startsWith('nav_');

  /// Build a canonical tombstone without preserving user content/placeholders.
  /// The caller supplies the same complete, coherent presentation snapshot.
  static Map<String, Object> clearedValuesFrom(
    Map<String, Object> completeValues,
  ) {
    final cleared = Map<String, Object>.of(completeValues);
    for (final entry in _valueTypes.entries) {
      if (!_isBusinessValue(entry.key)) continue;
      cleared[entry.key] = switch (entry.value) {
        _WidgetValueType.string => '',
        _WidgetValueType.boolean => false,
        _WidgetValueType.int32 || _WidgetValueType.int64 => 0,
      };
    }
    return Map<String, Object>.unmodifiable(cleared);
  }

  bool _valid() {
    if (ownerEpoch.trim().isEmpty ||
        !_nonnegativeExact(publicationRevision) ||
        !_nonnegativeExact(localeRevision) ||
        !_nonnegativeExact(capturedAtMillis) ||
        snapshotUtcOffsetMinutes < -1080 ||
        snapshotUtcOffsetMinutes > 1080 ||
        values.length != _valueTypes.length) {
      return false;
    }
    if (state == WidgetPublicationState.published) {
      if (publicationRevision == 0 || !_validDay(snapshotDay)) return false;
    } else if (snapshotDay.isNotEmpty || snapshotUtcOffsetMinutes != 0) {
      return false;
    }
    for (final entry in values.entries) {
      final expected = _valueTypes[entry.key];
      final value = entry.value;
      final valid = switch (expected) {
        _WidgetValueType.string => value is String,
        _WidgetValueType.boolean => value is bool,
        _WidgetValueType.int32 =>
          value is int &&
              value >=
                  (entry.key == 'habit_active_count'
                      ? -1
                      : entry.key == 'widget_first_day_of_week'
                      ? 1
                      : 0) &&
              value <=
                  (entry.key == 'habit_percent'
                      ? 100
                      : entry.key == 'widget_first_day_of_week'
                      ? 7
                      : 2147483647),
        _WidgetValueType.int64 => value is int && _nonnegativeExact(value),
        null => false,
      };
      if (!valid) return false;
      if (state != WidgetPublicationState.published &&
          _isBusinessValue(entry.key)) {
        final empty = switch (expected) {
          _WidgetValueType.string => value == '',
          _WidgetValueType.boolean => value == false,
          _WidgetValueType.int32 || _WidgetValueType.int64 => value == 0,
          null => false,
        };
        if (!empty) return false;
      }
    }
    return values['todo_count'] == values['todo_top3_count'];
  }

  static bool _nonnegativeExact(int value) =>
      value >= 0 && value <= maxExactJsonInteger;

  static bool _validDay(String value) {
    if (value.length != 10 || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final year = int.parse(value.substring(0, 4));
    if (year < 1 || year > 9999) return false;
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'ownerEpoch': ownerEpoch,
    'publicationRevision': publicationRevision,
    'localeRevision': localeRevision,
    'state': state.name,
    'locale': locale.name,
    'snapshotDay': snapshotDay,
    'snapshotUtcOffsetMinutes': snapshotUtcOffsetMinutes,
    'capturedAtMillis': capturedAtMillis,
    'values': Map<String, Object>.of(values),
  };

  String encode() => jsonEncode(toJson());

  /// Flat compatibility projection derives all identity metadata from this doc.
  Map<String, Object> toFlatValues() => {
    ...values,
    'widget_account_nonce': ownerEpoch,
    'widget_locale': locale.name,
    'widget_snapshot_day': state == WidgetPublicationState.published
        ? snapshotDay
        : '',
    'widget_snapshot_utc_offset_minutes': snapshotUtcOffsetMinutes,
  };

  /// Invalid/unknown canonical data must be blocked, never merged with a mirror.
  static WidgetPublication? tryDecode(Object? encoded) {
    if (encoded is! String) return null;
    try {
      return tryFromJson(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  static WidgetPublication? tryFromJson(Object? value) {
    if (value is! Map ||
        value.length != _documentKeys.length ||
        value.keys.any(
          (key) => key is! String || !_documentKeys.contains(key),
        ) ||
        value['schemaVersion'] is! int ||
        value['schemaVersion'] != schemaVersion) {
      return null;
    }
    final owner = value['ownerEpoch'];
    final revision = value['publicationRevision'];
    final localeRevision = value['localeRevision'];
    final day = value['snapshotDay'];
    final offset = value['snapshotUtcOffsetMinutes'];
    final captured = value['capturedAtMillis'];
    final rawValues = value['values'];
    final state = switch (value['state']) {
      'published' => WidgetPublicationState.published,
      'cleared' => WidgetPublicationState.cleared,
      'blocked' => WidgetPublicationState.blocked,
      _ => null,
    };
    final locale = switch (value['locale']) {
      'zh' => AppLocale.zh,
      'en' => AppLocale.en,
      _ => null,
    };
    if (owner is! String ||
        revision is! int ||
        localeRevision is! int ||
        state == null ||
        locale == null ||
        day is! String ||
        offset is! int ||
        captured is! int ||
        rawValues is! Map ||
        rawValues.keys.any((key) => key is! String) ||
        rawValues.values.any((entry) => entry == null)) {
      return null;
    }
    final normalizedValues = Map<String, Object>.from(rawValues);
    // Only the exact original v1 manifest is an upgrade-compatible read.
    // New constructors and captures still require the complete new manifest.
    if (normalizedValues.length == _valueTypes.length - 1 &&
        !normalizedValues.containsKey('widget_first_day_of_week') &&
        normalizedValues.keys.every(_valueTypes.containsKey)) {
      normalizedValues['widget_first_day_of_week'] = DateTime.monday;
    }
    try {
      return WidgetPublication(
        ownerEpoch: owner,
        publicationRevision: revision,
        localeRevision: localeRevision,
        state: state,
        locale: locale,
        snapshotDay: day,
        snapshotUtcOffsetMinutes: offset,
        capturedAtMillis: captured,
        values: normalizedValues,
      );
    } on FormatException {
      return null;
    }
  }
}
