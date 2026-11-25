import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:flutter_test/flutter_test.dart';

const _authoritativeMetadata = <String>{
  'widget_account_nonce',
  'widget_snapshot_day',
  'widget_snapshot_utc_offset_minutes',
  'widget_locale',
};

const _documentKeys = <String>{
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

const _presentationKeys = <String>{
  'widget_first_day_of_week',
  'brand_app_title',
  'nav_todo',
  'nav_habit',
  'nav_calendar',
  'nav_focus',
  'widget_theme_brand_id',
  'widget_theme_card_skin_id',
  'widget_theme_dark',
  'widget_theme_primary',
  'widget_theme_background',
  'widget_theme_surface',
  'widget_theme_nav_background',
  'widget_theme_border',
  'widget_theme_text',
  'widget_theme_muted_text',
  'widget_theme_on_primary',
  'widget_theme_accent_start',
  'widget_theme_accent_end',
  'widget_theme_background_asset_key',
  'widget_theme_corner_radius_dp',
  'widget_theme_control_radius_dp',
  'widget_theme_border_width_dp',
};

const _int32Keys = <String>{
  'widget_first_day_of_week',
  'todo_count',
  'habit_percent',
  'habit_active_count',
  'pomodoro_today',
  'focus_minutes_today',
  'todo_top3_count',
  'focus_timer_remaining_seconds',
  'focus_timer_total_seconds',
  'widget_theme_corner_radius_dp',
  'widget_theme_control_radius_dp',
  'widget_theme_border_width_dp',
};

const _int64Keys = <String>{
  'focus_timer_started_at_millis',
  'focus_timer_ends_at_millis',
};

Map<String, Object> _producerValues() {
  final values = Map<String, Object>.of(
    HomeWidgetService.accountPayloadDefaults,
  );
  for (final key in _authoritativeMetadata) {
    values.remove(key);
  }
  return values;
}

Map<String, Object> _valuesForState(WidgetPublicationState state) {
  final values = _producerValues();
  return state == WidgetPublicationState.published
      ? values
      : WidgetPublication.clearedValuesFrom(values);
}

Map<String, Object> _publishedValuesWithInt32(String key, int value) {
  final values = _producerValues()..[key] = value;
  if (key == 'todo_count' || key == 'todo_top3_count') {
    values['todo_count'] = value;
    values['todo_top3_count'] = value;
  }
  return values;
}

int _int32Minimum(String key) => key == 'habit_active_count'
    ? -1
    : key == 'widget_first_day_of_week'
    ? 1
    : 0;

int _int32Maximum(String key) => key == 'habit_percent'
    ? 100
    : key == 'widget_first_day_of_week'
    ? 7
    : 2147483647;

WidgetPublication _publication({
  String ownerEpoch = 'owner-epoch-a',
  int publicationRevision = 1,
  int localeRevision = 0,
  WidgetPublicationState state = WidgetPublicationState.published,
  AppLocale locale = AppLocale.zh,
  String? snapshotDay,
  int snapshotUtcOffsetMinutes = 0,
  int capturedAtMillis = 0,
  Map<String, Object>? values,
}) => WidgetPublication(
  ownerEpoch: ownerEpoch,
  publicationRevision: publicationRevision,
  localeRevision: localeRevision,
  state: state,
  locale: locale,
  snapshotDay:
      snapshotDay ??
      (state == WidgetPublicationState.published ? '2024-02-29' : ''),
  snapshotUtcOffsetMinutes: snapshotUtcOffsetMinutes,
  capturedAtMillis: capturedAtMillis,
  values: values ?? _valuesForState(state),
);

Map<String, dynamic> _decodedDocument(WidgetPublication publication) =>
    Map<String, dynamic>.from(jsonDecode(publication.encode()) as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocale originalLocale;

  setUp(() {
    originalLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() {
    I18n.setLocale(originalLocale);
  });

  test(
    'v1 has exactly ten document fields and the complete 90-field producer value catalog',
    () {
      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        final producerDefaults = HomeWidgetService.accountPayloadDefaults;
        final expectedValues = Map<String, Object>.of(producerDefaults);
        for (final key in _authoritativeMetadata) {
          expect(expectedValues.remove(key), isNotNull, reason: key);
        }

        expect(expectedValues, hasLength(90));
        expect(WidgetPublication.valueKeys, expectedValues.keys.toSet());
        final publication = _publication(
          locale: locale,
          values: expectedValues,
        );
        expect(publication.values, expectedValues);
        expect(publication.toJson().keys.toSet(), _documentKeys);
        expect(publication.toJson(), hasLength(10));

        for (final key in _authoritativeMetadata) {
          expect(publication.values.containsKey(key), isFalse, reason: key);
        }
        expect(publication.values.containsKey('widget_theme_brand_id'), isTrue);
        expect(publication.values.containsKey('widget_theme_primary'), isTrue);
        expect(publication.values.containsKey('widget_display_mode'), isFalse);
        expect(
          WidgetPublication.valueKeys.any(
            (key) => key.startsWith('widget_display_mode_'),
          ),
          isFalse,
        );
        expect(
          WidgetPublication.valueKeys.any(
            (key) => key.startsWith('widget_launcher_'),
          ),
          isFalse,
        );
      }
    },
  );

  test('constructor snapshots source values and all output maps are fresh', () {
    final sourceValues = _producerValues();
    final originalTodoCount = sourceValues['todo_count'];
    final publication = _publication(values: sourceValues);

    sourceValues['todo_count'] = 700;
    sourceValues['late_key'] = 'not in the publication';
    expect(publication.values['todo_count'], originalTodoCount);
    expect(publication.values.containsKey('late_key'), isFalse);
    expect(
      () => publication.values['todo_count'] = 701,
      throwsUnsupportedError,
    );
    expect(
      () => WidgetPublication.valueKeys.add('another_key'),
      throwsUnsupportedError,
    );

    final firstDocument = publication.toJson();
    final firstValues = firstDocument['values'] as Map<String, Object>;
    expect(identical(firstValues, publication.values), isFalse);
    firstValues['todo_count'] = 702;
    firstDocument['ownerEpoch'] = 'mutated output';

    final secondDocument = publication.toJson();
    expect(identical(firstDocument, secondDocument), isFalse);
    expect(secondDocument['ownerEpoch'], 'owner-epoch-a');
    expect(
      (secondDocument['values'] as Map<String, Object>)['todo_count'],
      originalTodoCount,
    );

    final firstFlatValues = publication.toFlatValues();
    firstFlatValues['todo_count'] = 703;
    expect(publication.toFlatValues()['todo_count'], originalTodoCount);
  });

  test(
    'clearedValuesFrom zeroes 67 business fields and preserves 23 presentation fields',
    () {
      final source = _producerValues();
      final originalSource = Map<String, Object>.of(source);
      final cleared = WidgetPublication.clearedValuesFrom(source);
      final businessKeys = WidgetPublication.valueKeys.difference(
        _presentationKeys,
      );

      expect(source, originalSource);
      expect(cleared.keys.toSet(), source.keys.toSet());
      expect(cleared, hasLength(90));
      expect(_presentationKeys, hasLength(23));
      expect(businessKeys, hasLength(67));
      for (final key in businessKeys) {
        switch (source[key]) {
          case String _:
            expect(cleared[key], '', reason: key);
            break;
          case int _:
            expect(cleared[key], 0, reason: key);
            break;
          case bool _:
            expect(cleared[key], false, reason: key);
            break;
          default:
            fail('Unexpected producer value type for $key');
        }
      }
      for (final key in _presentationKeys) {
        expect(cleared[key], source[key], reason: key);
      }
      expect(() => cleared['todo_count'] = 1, throwsUnsupportedError);

      for (final state in [
        WidgetPublicationState.cleared,
        WidgetPublicationState.blocked,
      ]) {
        final tombstone = _publication(state: state, values: cleared);
        expect(tombstone.state, state);
        expect(tombstone.values, cleared);
        expect(tombstone.snapshotDay, '');
        expect(tombstone.snapshotUtcOffsetMinutes, 0);
      }
    },
  );

  test(
    'cleared and blocked reject each business field tampered individually',
    () {
      final cleared = WidgetPublication.clearedValuesFrom(_producerValues());
      final businessKeys = WidgetPublication.valueKeys.difference(
        _presentationKeys,
      );
      expect(businessKeys, hasLength(67));

      for (final state in [
        WidgetPublicationState.cleared,
        WidgetPublicationState.blocked,
      ]) {
        for (final key in businessKeys) {
          final tampered = Map<String, Object>.of(cleared);
          switch (tampered[key]) {
            case String _:
              tampered[key] = 'stale account value';
              break;
            case int _:
              tampered[key] = 1;
              break;
            case bool _:
              tampered[key] = true;
              break;
            default:
              fail('Unexpected tombstone value type for $key');
          }
          expect(
            () => _publication(state: state, values: tampered),
            throwsFormatException,
            reason: '${state.name}: $key',
          );
        }
        final sentinelTamper = Map<String, Object>.of(cleared)
          ..['habit_active_count'] = -1;
        expect(
          () => _publication(state: state, values: sentinelTamper),
          throwsFormatException,
          reason: '${state.name}: the published-only -1 activity sentinel',
        );
      }
    },
  );

  test(
    'raw owner, user text, and item IDs survive JSON round trips unchanged',
    () {
      final values = _producerValues();
      const ownerEpoch = ' 账号-A\t ';
      const title = '　待办： café 🧋 👩🏽‍💻  \n';
      const taskId = '  task:id-42\t ';
      values['todo_top3_1'] = title;
      values['todo_top3_1_id'] = taskId;

      final publication = _publication(ownerEpoch: ownerEpoch, values: values);
      final decoded = WidgetPublication.tryDecode(publication.encode());

      expect(decoded, isNotNull);
      expect(decoded!.ownerEpoch, ownerEpoch);
      expect(decoded.values['todo_top3_1'], title);
      expect(decoded.values['todo_top3_1_id'], taskId);
      expect(decoded.toFlatValues()['widget_account_nonce'], ownerEpoch);
    },
  );

  test(
    'descriptor creation and serialization leave the global locale notifier unchanged',
    () {
      final localeBefore = I18n.current;
      final notifierBefore = I18n.localeListenable.value;
      var notificationCount = 0;
      void countLocaleNotifications() => notificationCount++;
      I18n.localeListenable.addListener(countLocaleNotifications);
      try {
        final otherLocale = localeBefore == AppLocale.zh
            ? AppLocale.en
            : AppLocale.zh;
        final publication = _publication(locale: otherLocale);
        publication.toJson();
        publication.encode();
        publication.toFlatValues();
        expect(WidgetPublication.tryDecode(publication.encode()), isNotNull);
      } finally {
        I18n.localeListenable.removeListener(countLocaleNotifications);
      }

      expect(I18n.current, localeBefore);
      expect(I18n.localeListenable.value, notifierBefore);
      expect(notificationCount, 0);
    },
  );

  test(
    'strict decoder rejects missing, null, extra, and wrongly typed fields',
    () {
      final canonical = _decodedDocument(_publication());
      final malformed = <Map<String, dynamic>>[];

      malformed.add(
        Map<String, dynamic>.of(canonical)..remove('capturedAtMillis'),
      );
      malformed.add(<String, dynamic>{...canonical, 'extra': true});
      malformed.add(<String, dynamic>{...canonical, 'ownerEpoch': null});
      malformed.add(<String, dynamic>{
        ...canonical,
        'publicationRevision': '1',
      });
      malformed.add(<String, dynamic>{...canonical, 'localeRevision': 0.0});
      malformed.add(<String, dynamic>{...canonical, 'state': null});
      malformed.add(<String, dynamic>{...canonical, 'locale': 7});
      malformed.add(<String, dynamic>{...canonical, 'snapshotDay': null});
      malformed.add(<String, dynamic>{
        ...canonical,
        'snapshotUtcOffsetMinutes': '0',
      });
      malformed.add(<String, dynamic>{...canonical, 'capturedAtMillis': 0.0});
      malformed.add(<String, dynamic>{...canonical, 'values': null});
      malformed.add(<String, dynamic>{...canonical, 'values': <Object>[]});

      final nullValue = _decodedDocument(_publication());
      (nullValue['values'] as Map<String, dynamic>)['todo_count'] = null;
      malformed.add(nullValue);
      final extraValue = _decodedDocument(_publication());
      (extraValue['values'] as Map<String, dynamic>)['unknown'] = 'extra';
      malformed.add(extraValue);
      final wrongIntegerType = _decodedDocument(_publication());
      (wrongIntegerType['values'] as Map<String, dynamic>)['todo_count'] = '3';
      malformed.add(wrongIntegerType);
      final wrongBooleanType = _decodedDocument(_publication());
      (wrongBooleanType['values']
              as Map<String, dynamic>)['widget_theme_dark'] =
          0;
      malformed.add(wrongBooleanType);

      for (final candidate in malformed) {
        expect(WidgetPublication.tryFromJson(candidate), isNull);
      }
      expect(WidgetPublication.tryDecode('{invalid json'), isNull);
      expect(WidgetPublication.tryDecode(<String, Object>{}), isNull);
    },
  );

  test('unknown schema, state, and locale values are blocked', () {
    final unknownVersion = _decodedDocument(_publication());
    unknownVersion['schemaVersion'] = WidgetPublication.schemaVersion + 1;
    expect(WidgetPublication.tryFromJson(unknownVersion), isNull);

    final unknownState = _decodedDocument(_publication());
    unknownState['state'] = 'pending';
    expect(WidgetPublication.tryFromJson(unknownState), isNull);

    final unknownLocale = _decodedDocument(_publication());
    unknownLocale['locale'] = 'fr';
    expect(WidgetPublication.tryFromJson(unknownLocale), isNull);
  });

  test(
    'published days use strict Gregorian validation, including leap days',
    () {
      expect(_publication(snapshotDay: '0001-01-01').snapshotDay, '0001-01-01');
      expect(_publication(snapshotDay: '9999-12-31').snapshotDay, '9999-12-31');
      expect(_publication(snapshotDay: '2024-02-29').snapshotDay, '2024-02-29');
      expect(_publication(snapshotDay: '2000-02-29').snapshotDay, '2000-02-29');

      for (final day in [
        '0000-01-01',
        '10000-01-01',
        '2023-02-29',
        '2024-04-31',
        '2024-13-01',
        '2024-00-01',
        '2024-2-09',
        '24-02-09',
        '2024-02-09\n',
      ]) {
        expect(
          () => _publication(snapshotDay: day),
          throwsFormatException,
          reason: day,
        );
      }
    },
  );

  test(
    'published, cleared, and blocked states enforce revision and day rules',
    () {
      for (final state in [
        WidgetPublicationState.cleared,
        WidgetPublicationState.blocked,
      ]) {
        final publication = _publication(
          state: state,
          publicationRevision: 0,
          snapshotDay: '',
        );
        expect(publication.state, state);
        expect(publication.toFlatValues()['widget_snapshot_day'], '');
        expect(publication.values['todo_count'], 0);
        expect(publication.values['todo_top3_count'], 0);
      }

      expect(() => _publication(publicationRevision: 0), throwsFormatException);
      expect(() => _publication(snapshotDay: ''), throwsFormatException);
      expect(
        () => _publication(
          state: WidgetPublicationState.cleared,
          snapshotDay: '2024-02-29',
        ),
        throwsFormatException,
      );
      expect(
        () => _publication(
          state: WidgetPublicationState.blocked,
          snapshotDay: '2024-02-29',
        ),
        throwsFormatException,
      );
      for (final state in [
        WidgetPublicationState.cleared,
        WidgetPublicationState.blocked,
      ]) {
        expect(
          () => _publication(state: state, snapshotUtcOffsetMinutes: 1),
          throwsFormatException,
          reason: '${state.name} must use offset zero',
        );
      }
    },
  );

  test(
    'UTC offset accepts inclusive day bounds and rejects values outside them',
    () {
      expect(
        _publication(snapshotUtcOffsetMinutes: -1080).snapshotUtcOffsetMinutes,
        -1080,
      );
      expect(
        _publication(snapshotUtcOffsetMinutes: 1080).snapshotUtcOffsetMinutes,
        1080,
      );
      expect(
        () => _publication(snapshotUtcOffsetMinutes: -1081),
        throwsFormatException,
      );
      expect(
        () => _publication(snapshotUtcOffsetMinutes: 1081),
        throwsFormatException,
      );
    },
  );

  test(
    'every Int32 value accepts its field range and rejects each adjacent overflow',
    () {
      expect(_int32Keys, hasLength(12));
      for (final key in _int32Keys) {
        final minimum = _int32Minimum(key);
        final maximum = _int32Maximum(key);
        expect(
          _publication(
            values: _publishedValuesWithInt32(key, minimum),
          ).values[key],
          minimum,
          reason: '$key lower bound',
        );
        expect(
          _publication(
            values: _publishedValuesWithInt32(key, maximum),
          ).values[key],
          maximum,
          reason: '$key upper bound',
        );
        expect(
          () =>
              _publication(values: _publishedValuesWithInt32(key, minimum - 1)),
          throwsFormatException,
          reason: '$key below lower bound',
        );
        expect(
          () =>
              _publication(values: _publishedValuesWithInt32(key, maximum + 1)),
          throwsFormatException,
          reason: '$key above upper bound',
        );
      }

      final mismatchedCount = _producerValues()..['todo_count'] = 1;
      expect(
        () => _publication(values: mismatchedCount),
        throwsFormatException,
        reason: 'todo_count and todo_top3_count share one source count',
      );
    },
  );

  test(
    'revision, capture, and integer values preserve exact JSON boundary values',
    () {
      const max = WidgetPublication.maxExactJsonInteger;
      final values = _producerValues()
        ..['focus_timer_started_at_millis'] = max
        ..['focus_timer_ends_at_millis'] = max;
      final publication = _publication(
        publicationRevision: max,
        localeRevision: max,
        capturedAtMillis: max,
        values: values,
      );
      final decoded = WidgetPublication.tryDecode(publication.encode());

      expect(decoded, isNotNull);
      expect(decoded!.publicationRevision, max);
      expect(decoded.localeRevision, max);
      expect(decoded.capturedAtMillis, max);
      expect(decoded.values['focus_timer_started_at_millis'], max);
      expect(decoded.values['focus_timer_ends_at_millis'], max);

      for (final create in [
        () => _publication(publicationRevision: -1),
        () => _publication(publicationRevision: max + 1),
        () => _publication(localeRevision: -1),
        () => _publication(localeRevision: max + 1),
        () => _publication(capturedAtMillis: -1),
        () => _publication(capturedAtMillis: max + 1),
      ]) {
        expect(create, throwsFormatException);
      }

      expect(_int64Keys, hasLength(2));
      for (final key in _int64Keys) {
        for (final boundary in [0, max]) {
          final values = _producerValues()..[key] = boundary;
          expect(
            _publication(values: values).values[key],
            boundary,
            reason: '$key boundary $boundary',
          );
        }
        for (final invalid in [-1, max + 1]) {
          final values = _producerValues()..[key] = invalid;
          expect(
            () => _publication(values: values),
            throwsFormatException,
            reason: '$key invalid $invalid',
          );
        }
      }
    },
  );

  test('flat projection replaces all identity metadata from the document', () {
    final values = _producerValues()
      ..['todo_count'] = 42
      ..['todo_top3_count'] = 42
      ..['todo_top3_1'] = 'Task from the complete document';
    final publication = _publication(
      ownerEpoch: ' owner-epoch-raw ',
      publicationRevision: 4,
      localeRevision: 2,
      locale: AppLocale.en,
      snapshotDay: '2025-01-03',
      snapshotUtcOffsetMinutes: -345,
      capturedAtMillis: 123456789,
      values: values,
    );
    final flat = publication.toFlatValues();

    expect(
      flat.keys.toSet(),
      HomeWidgetService.accountPayloadDefaults.keys.toSet(),
    );
    expect(flat['widget_account_nonce'], ' owner-epoch-raw ');
    expect(flat['widget_locale'], 'en');
    expect(flat['widget_snapshot_day'], '2025-01-03');
    expect(flat['widget_snapshot_utc_offset_minutes'], -345);
    expect(flat['todo_count'], 42);
    expect(flat['todo_top3_1'], 'Task from the complete document');
    expect(
      _authoritativeMetadata.intersection(publication.values.keys.toSet()),
      isEmpty,
    );

    final cleared = _publication(
      state: WidgetPublicationState.cleared,
      snapshotDay: '',
    );
    final clearedFlat = cleared.toFlatValues();
    expect(clearedFlat['widget_snapshot_day'], '');
    expect(
      clearedFlat,
      hasLength(HomeWidgetService.accountPayloadDefaults.length),
    );
  });
}
