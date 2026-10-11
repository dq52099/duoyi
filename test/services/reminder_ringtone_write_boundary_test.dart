import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_ringtone_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await AccountPreferenceWrites.drain();
    ReminderRingtoneSettings.onChanged = null;
  });

  test('volume rejection restores cache and emits no change', () async {
    final store = _RingtoneStore()
      ..rejectKeyOnce = 'flutter.pref_reminder_ringtone_volume_percent';
    SharedPreferencesStorePlatform.instance = store;
    final changed = <String>[];
    ReminderRingtoneSettings.onChanged = changed.addAll;
    await expectLater(
      ReminderRingtoneSettings.setVolumePercent(80, preview: false),
      throwsStateError,
    );
    expect(await ReminderRingtoneSettings.loadVolumePercent(), 60);
    expect(changed, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        ReminderRingtoneSettings.volumePreferenceKey,
      ),
      isNull,
    );
  });

  test('sound rejection restores both migration marker and sound', () async {
    final store = _RingtoneStore()
      ..rejectKeyOnce = 'flutter.pref_reminder_ringtone_sound';
    SharedPreferencesStorePlatform.instance = store;
    final changed = <String>[];
    ReminderRingtoneSettings.onChanged = changed.addAll;
    await expectLater(
      ReminderRingtoneSettings.setSound('forest', preview: false),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(ReminderRingtoneSettings.legacyAlarmMigrationPreferenceKey),
      isNull,
    );
    expect(
      prefs.getString(ReminderRingtoneSettings.soundPreferenceKey),
      isNull,
    );
    expect(await ReminderRingtoneSettings.loadSound(), 'soft');
    expect(changed, isEmpty);
    // A failed write must not prevent the next choice from being saved.
    await ReminderRingtoneSettings.setSound('forest', preview: false);
    expect(await ReminderRingtoneSettings.loadSound(), 'forest');
    expect(changed, [ReminderRingtoneSettings.soundPreferenceKey]);
  });

  test('rapid ringtone choices persist in submission order', () async {
    final store = _RingtoneStore()
      ..holdKey = 'flutter.pref_reminder_ringtone_sound';
    SharedPreferencesStorePlatform.instance = store;
    final first = ReminderRingtoneSettings.setSound('forest', preview: false);
    await store.started.future.timeout(const Duration(seconds: 5));
    final second = ReminderRingtoneSettings.setSound('silver', preview: false);
    expect(store.heldValues, ['forest']);
    store.release.complete();
    await Future.wait([first, second]);
    expect(store.heldValues, ['forest', 'silver']);
    expect(await ReminderRingtoneSettings.loadSound(), 'silver');
  });

  test('cleanup drains sound writes and discards queued old volume', () async {
    final store = _RingtoneStore()
      ..holdKey = 'flutter.pref_reminder_ringtone_sound';
    SharedPreferencesStorePlatform.instance = store;
    final changed = <String>[];
    ReminderRingtoneSettings.onChanged = changed.addAll;
    final first = ReminderRingtoneSettings.setSound('forest', preview: false);
    await store.started.future.timeout(const Duration(seconds: 5));
    final queued = ReminderRingtoneSettings.setVolumePercent(
      80,
      preview: false,
    );
    var cleaned = false;
    final cleanup = AccountLocalDataCleaner.clearSharedPreferences().then((_) {
      cleaned = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cleaned, isFalse);
    store.release.complete();
    await Future.wait([first, queued, cleanup]);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ReminderRingtoneSettings.soundPreferenceKey),
      isNull,
    );
    expect(
      prefs.getBool(ReminderRingtoneSettings.legacyAlarmMigrationPreferenceKey),
      isNull,
    );
    expect(prefs.getInt(ReminderRingtoneSettings.volumePreferenceKey), isNull);
    expect(changed, isEmpty);
    expect(
      store.events.indexOf('set:flutter.pref_reminder_ringtone_sound'),
      lessThan(
        store.events.indexOf('remove:flutter.pref_reminder_ringtone_sound'),
      ),
    );
  });

  test('aborted transition restores legacy alarm migration', () async {
    SharedPreferences.setMockInitialValues({
      ReminderRingtoneSettings.soundPreferenceKey: 'alarm',
    });
    final store = _RingtoneStore(
      initial: {'flutter.pref_reminder_ringtone_sound': 'alarm'},
    )..holdKey = 'flutter.pref_reminder_ringtone_sound';
    SharedPreferencesStorePlatform.instance = store;
    final changed = <String>[];
    ReminderRingtoneSettings.onChanged = changed.addAll;
    final migration = ReminderRingtoneSettings.loadSound();
    await store.started.future.timeout(const Duration(seconds: 5));
    final boundary = AccountLocalDataCleaner.runPreferenceBoundary<void>(
      () async {
        throw StateError('Preflight failed');
      },
    );
    final failedBoundary = expectLater(boundary, throwsStateError);
    store.release.complete();
    await migration;
    await failedBoundary;
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ReminderRingtoneSettings.soundPreferenceKey),
      'alarm',
    );
    expect(
      prefs.getBool(ReminderRingtoneSettings.legacyAlarmMigrationPreferenceKey),
      isNull,
    );
    expect(changed, isEmpty);
  });

  test('fallback channel sound and schema are restored together', () async {
    final store = _RingtoneStore()
      ..rejectKeyOnce =
          'flutter.pref_reminder_ringtone_fallback_channel_sound_schema_reminders';
    SharedPreferencesStorePlatform.instance = store;
    await expectLater(
      ReminderRingtoneSettings.markAndroidFallbackChannelSoundApplied(
        'reminders',
        'duoyi_forest',
      ),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where(
        (key) =>
            key.startsWith('pref_reminder_ringtone_fallback_channel_sound'),
      ),
      isEmpty,
    );
  });
}

class _RingtoneStore extends InMemorySharedPreferencesStore {
  _RingtoneStore({Map<String, Object> initial = const {}})
    : super.withData(initial);
  String? rejectKeyOnce;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<void>();
  final heldValues = <Object>[];
  final events = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == holdKey) {
      heldValues.add(value);
      if (!started.isCompleted) {
        started.complete();
        await release.future;
      }
    }
    if (key == rejectKeyOnce) {
      rejectKeyOnce = null;
      return false;
    }
    final saved = await super.setValue(valueType, key, value);
    events.add('set:$key');
    return saved;
  }

  @override
  Future<bool> remove(String key) async {
    final removed = await super.remove(key);
    events.add('remove:$key');
    return removed;
  }
}
