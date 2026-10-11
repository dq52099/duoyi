import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final original = I18n.current;
    addTearDown(() => I18n.setLocale(original));
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  CustomFocusSoundProvider providerForTest() {
    final provider = CustomFocusSoundProvider();
    addTearDown(() {
      provider.resetLocalState();
      provider.dispose();
    });
    return provider;
  }

  test('missing custom selection uses live localized display copy', () async {
    final provider = providerForTest();
    final prefs = await SharedPreferences.getInstance();
    var notifications = 0;
    provider.addListener(() => notifications++);

    expect(provider.labelFor('custom:missing'), '自定义音频');
    I18n.setLocale(AppLocale.en);
    expect(provider.labelFor('custom:missing'), 'Custom audio');
    I18n.setLocale(AppLocale.zh);
    expect(provider.labelFor('custom:missing'), '自定义音频');
    expect(provider.sounds, isEmpty);
    expect(notifications, 0);
    expect(prefs.containsKey(CustomFocusSoundProvider.storageKey), isFalse);
  });

  test(
    'authored sound metadata and storage stay literal across locales',
    () async {
      const labels = ['我的雨声 — café  ', '自定义音频', 'Forest / 夜'];
      final records = [
        for (var i = 0; i < labels.length; i++)
          jsonEncode({
            'id': 'custom:fixture-$i',
            'label': labels[i],
            'path': '/fixture/no-audio-$i.mp3',
            'importedAt': '2024-06-15T12:00:00.000Z',
          }),
      ];
      SharedPreferences.setMockInitialValues({
        CustomFocusSoundProvider.storageKey: records,
      });
      final provider = providerForTest();
      await provider.loadFromStorage();
      final prefs = await SharedPreferences.getInstance();
      final before = provider.sounds.map((sound) => sound.toJson()).toList();
      var notifications = 0;
      provider.addListener(() => notifications++);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        for (var i = 0; i < labels.length; i++) {
          expect(provider.labelFor('custom:fixture-$i'), labels[i]);
          expect(
            provider.labelFor('custom:fixture-$i', locale: AppLocale.en),
            labels[i],
          );
        }
        expect(provider.sounds.map((sound) => sound.toJson()).toList(), before);
        expect(
          prefs.getStringList(CustomFocusSoundProvider.storageKey),
          records,
        );
      }
      expect(notifications, 0);
    },
  );

  test('explicit fallback locale never changes the live locale', () {
    final provider = providerForTest();
    expect(
      provider.labelFor('custom:missing', locale: AppLocale.en),
      'Custom audio',
    );
    expect(I18n.current, AppLocale.zh);
    I18n.setLocale(AppLocale.en);
    expect(provider.labelFor('custom:missing', locale: AppLocale.zh), '自定义音频');
    expect(I18n.current, AppLocale.en);
  });
}
