import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform_info.dart';

enum ReminderRingtonePlatformMode {
  androidNative,
  appleSystemTimeSensitive,
  desktopSystemNotification,
  unsupported,
}

class ReminderRingtonePlatformPolicy {
  final ReminderRingtonePlatformMode mode;
  final bool supportsBuiltInSoundPicker;
  final bool supportsVolumePresets;
  final bool usesSystemNotificationSound;
  final String sectionSubtitleKey;
  final String tileTitleKey;
  final String tileSubtitleKey;

  const ReminderRingtonePlatformPolicy({
    required this.mode,
    required this.supportsBuiltInSoundPicker,
    required this.supportsVolumePresets,
    required this.usesSystemNotificationSound,
    required this.sectionSubtitleKey,
    required this.tileTitleKey,
    required this.tileSubtitleKey,
  });
}

class ReminderRingtoneSettings {
  ReminderRingtoneSettings._();

  static const String volumePreferenceKey =
      'pref_reminder_ringtone_volume_percent';
  static const String soundPreferenceKey = 'pref_reminder_ringtone_sound';
  static const int defaultVolumePercent = 80;
  static const String defaultSound = 'alarm';

  static const List<int> presets = <int>[40, 60, 80, 100];
  static const List<ReminderRingtoneOption> sounds = <ReminderRingtoneOption>[
    ReminderRingtoneOption(id: 'alarm', label: '强提醒'),
    ReminderRingtoneOption(id: 'chime', label: '清脆提示'),
    ReminderRingtoneOption(id: 'bell', label: '铃铛'),
    ReminderRingtoneOption(id: 'beep', label: '电子提示'),
    ReminderRingtoneOption(id: 'classic', label: '经典闹铃'),
  ];

  static const MethodChannel _channel = MethodChannel(
    'duoyi/reminder_ringtone',
  );

  static ReminderRingtonePlatformPolicy get platformPolicy => platformPolicyFor(
    isAndroid: PlatformInfo.isAndroid,
    isIOS: PlatformInfo.isIOS,
    isMacOS: PlatformInfo.isMacOS,
    isLinux: PlatformInfo.isLinux,
    isWindows: PlatformInfo.isWindows,
  );

  @visibleForTesting
  static ReminderRingtonePlatformPolicy platformPolicyFor({
    required bool isAndroid,
    required bool isIOS,
    required bool isMacOS,
    required bool isLinux,
    required bool isWindows,
  }) {
    if (isAndroid) {
      return const ReminderRingtonePlatformPolicy(
        mode: ReminderRingtonePlatformMode.androidNative,
        supportsBuiltInSoundPicker: true,
        supportsVolumePresets: true,
        usesSystemNotificationSound: false,
        sectionSubtitleKey: 'preferences.ringtone.section.subtitle.android',
        tileTitleKey: 'preferences.ringtone.sound',
        tileSubtitleKey: 'preferences.ringtone.section.subtitle.android',
      );
    }
    if (isIOS || isMacOS) {
      return const ReminderRingtonePlatformPolicy(
        mode: ReminderRingtonePlatformMode.appleSystemTimeSensitive,
        supportsBuiltInSoundPicker: false,
        supportsVolumePresets: false,
        usesSystemNotificationSound: true,
        sectionSubtitleKey: 'preferences.ringtone.section.subtitle.apple',
        tileTitleKey: 'preferences.ringtone.system_sound',
        tileSubtitleKey: 'preferences.ringtone.system_sound.subtitle.apple',
      );
    }
    if (isLinux || isWindows) {
      return const ReminderRingtonePlatformPolicy(
        mode: ReminderRingtonePlatformMode.desktopSystemNotification,
        supportsBuiltInSoundPicker: false,
        supportsVolumePresets: false,
        usesSystemNotificationSound: true,
        sectionSubtitleKey: 'preferences.ringtone.section.subtitle.desktop',
        tileTitleKey: 'preferences.ringtone.system_sound',
        tileSubtitleKey: 'preferences.ringtone.system_sound.subtitle.desktop',
      );
    }
    return const ReminderRingtonePlatformPolicy(
      mode: ReminderRingtonePlatformMode.unsupported,
      supportsBuiltInSoundPicker: false,
      supportsVolumePresets: false,
      usesSystemNotificationSound: false,
      sectionSubtitleKey: 'preferences.ringtone.section.subtitle.unsupported',
      tileTitleKey: 'preferences.ringtone.unsupported',
      tileSubtitleKey: 'preferences.ringtone.unsupported.subtitle',
    );
  }

  static Future<int> loadVolumePercent() async {
    final p = await SharedPreferences.getInstance();
    return _normalizeVolume(
      p.getInt(volumePreferenceKey) ?? defaultVolumePercent,
    );
  }

  static Future<String> loadSound() async {
    final p = await SharedPreferences.getInstance();
    return _normalizeSound(p.getString(soundPreferenceKey) ?? defaultSound);
  }

  static Future<void> setVolumePercent(int value) async {
    final next = _normalizeVolume(value);
    final p = await SharedPreferences.getInstance();
    await p.setInt(volumePreferenceKey, next);
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setVolumePercent', <String, Object?>{
        'volumePercent': next,
      });
    } catch (e, st) {
      debugPrint('[ReminderRingtoneSettings] setVolumePercent failed: $e\n$st');
    }
  }

  static Future<void> setSound(String value) async {
    final next = _normalizeSound(value);
    final p = await SharedPreferences.getInstance();
    await p.setString(soundPreferenceKey, next);
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setSoundName', <String, Object?>{
        'soundName': next,
      });
    } catch (e, st) {
      debugPrint('[ReminderRingtoneSettings] setSound failed: $e\n$st');
    }
  }

  static int _normalizeVolume(int value) {
    if (value <= 40) return 40;
    if (value <= 60) return 60;
    if (value <= 80) return 80;
    return 100;
  }

  static String _normalizeSound(String value) {
    return sounds.any((s) => s.id == value) ? value : defaultSound;
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    return PlatformInfo.isAndroid;
  }
}

class ReminderRingtoneOption {
  final String id;
  final String label;

  const ReminderRingtoneOption({required this.id, required this.label});
}
