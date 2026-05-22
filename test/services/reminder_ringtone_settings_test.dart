import 'package:duoyi/services/reminder_ringtone_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads defaults when ringtone settings are absent', () async {
    expect(
      await ReminderRingtoneSettings.loadVolumePercent(),
      ReminderRingtoneSettings.defaultVolumePercent,
    );
    expect(
      await ReminderRingtoneSettings.loadSound(),
      ReminderRingtoneSettings.defaultSound,
    );
  });

  test('persists preset volume and selected ringtone', () async {
    await ReminderRingtoneSettings.setVolumePercent(100);
    await ReminderRingtoneSettings.setSound('classic');

    expect(await ReminderRingtoneSettings.loadVolumePercent(), 100);
    expect(await ReminderRingtoneSettings.loadSound(), 'classic');
  });

  test('normalizes unsupported volume and ringtone values', () async {
    await ReminderRingtoneSettings.setVolumePercent(73);
    await ReminderRingtoneSettings.setSound('missing');

    expect(await ReminderRingtoneSettings.loadVolumePercent(), 80);
    expect(
      await ReminderRingtoneSettings.loadSound(),
      ReminderRingtoneSettings.defaultSound,
    );
  });

  test('exposes multiple named ringtone options beyond volume presets', () {
    expect(
      ReminderRingtoneSettings.sounds.map((sound) => sound.id),
      containsAll(<String>['alarm', 'chime', 'bell', 'beep', 'classic']),
    );
    expect(ReminderRingtoneSettings.sounds.length, greaterThanOrEqualTo(5));
  });

  test('uses native built-in ringtone controls on Android only', () {
    final policy = ReminderRingtoneSettings.platformPolicyFor(
      isAndroid: true,
      isIOS: false,
      isMacOS: false,
      isLinux: false,
      isWindows: false,
    );

    expect(policy.mode, ReminderRingtonePlatformMode.androidNative);
    expect(policy.supportsBuiltInSoundPicker, isTrue);
    expect(policy.supportsVolumePresets, isTrue);
    expect(policy.usesSystemNotificationSound, isFalse);
    expect(
      policy.sectionSubtitleKey,
      'preferences.ringtone.section.subtitle.android',
    );
  });

  test('uses system time-sensitive notification sounds on Apple platforms', () {
    for (final flags in const [
      (isIOS: true, isMacOS: false),
      (isIOS: false, isMacOS: true),
    ]) {
      final policy = ReminderRingtoneSettings.platformPolicyFor(
        isAndroid: false,
        isIOS: flags.isIOS,
        isMacOS: flags.isMacOS,
        isLinux: false,
        isWindows: false,
      );

      expect(
        policy.mode,
        ReminderRingtonePlatformMode.appleSystemTimeSensitive,
      );
      expect(policy.supportsBuiltInSoundPicker, isFalse);
      expect(policy.supportsVolumePresets, isFalse);
      expect(policy.usesSystemNotificationSound, isTrue);
      expect(policy.tileTitleKey, 'preferences.ringtone.system_sound');
      expect(
        policy.tileSubtitleKey,
        'preferences.ringtone.system_sound.subtitle.apple',
      );
    }
  });

  test('uses desktop system notification sounds on Linux and Windows', () {
    for (final flags in const [
      (isLinux: true, isWindows: false),
      (isLinux: false, isWindows: true),
    ]) {
      final policy = ReminderRingtoneSettings.platformPolicyFor(
        isAndroid: false,
        isIOS: false,
        isMacOS: false,
        isLinux: flags.isLinux,
        isWindows: flags.isWindows,
      );

      expect(
        policy.mode,
        ReminderRingtonePlatformMode.desktopSystemNotification,
      );
      expect(policy.supportsBuiltInSoundPicker, isFalse);
      expect(policy.supportsVolumePresets, isFalse);
      expect(policy.usesSystemNotificationSound, isTrue);
      expect(
        policy.tileSubtitleKey,
        'preferences.ringtone.system_sound.subtitle.desktop',
      );
    }
  });

  test('marks platforms without local notifications as unsupported', () {
    final policy = ReminderRingtoneSettings.platformPolicyFor(
      isAndroid: false,
      isIOS: false,
      isMacOS: false,
      isLinux: false,
      isWindows: false,
    );

    expect(policy.mode, ReminderRingtonePlatformMode.unsupported);
    expect(policy.supportsBuiltInSoundPicker, isFalse);
    expect(policy.supportsVolumePresets, isFalse);
    expect(policy.usesSystemNotificationSound, isFalse);
    expect(policy.tileTitleKey, 'preferences.ringtone.unsupported');
  });
}
