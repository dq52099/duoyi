import 'package:duoyi/core/focus_sound_catalog.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    final originalLocale = I18n.current;
    addTearDown(() => I18n.setLocale(originalLocale));
    I18n.setLocale(AppLocale.zh);
  });

  group('FocusSoundCatalog', () {
    const bannedGeneratedNoiseIds = <String>{
      'brown_noise',
      'pink_noise',
      'white_stream',
    };

    test('single tracks map to one asset', () {
      expect(FocusSoundCatalog.trackIdsFor('rain'), <String>['rain']);
      expect(FocusSoundCatalog.assetsFor('rain'), <String>[
        'sounds/white_noise/rain.mp3',
      ]);
      expect(FocusSoundCatalog.labelFor('rain'), '窗边雨声');
      expect(FocusSoundCatalog.trackIdsFor('clock'), <String>['clock']);
      expect(FocusSoundCatalog.trackIdsFor('keyboard'), <String>['keyboard']);
      expect(FocusSoundCatalog.trackIdsFor('wind'), <String>['wind']);
      expect(FocusSoundCatalog.trackIdsFor('train_station'), <String>[
        'train_station',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('classroom'), <String>['classroom']);
      expect(FocusSoundCatalog.trackIdsFor('pebble_beach'), <String>[
        'pebble_beach',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('mall'), <String>['mall']);
      expect(FocusSoundCatalog.trackIdsFor('restaurant'), <String>[
        'restaurant',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('garden_birds'), <String>[
        'garden_birds',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('country_night'), <String>[
        'country_night',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('shallow_river'), <String>[
        'shallow_river',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('veranda_rain'), <String>[
        'veranda_rain',
      ]);
      expect(FocusSoundCatalog.trackIdsFor('breeze_birds'), <String>[
        'breeze_birds',
      ]);
    });

    test('mix ids are rejected', () {
      expect(FocusSoundCatalog.trackIdsFor('rain+thunderstorm'), isEmpty);
      expect(FocusSoundCatalog.assetsFor('waves+storm_rain'), isEmpty);
      expect(FocusSoundCatalog.labelFor('forest+deep_stream'), '无白噪音');
    });

    test('unknown ids are ignored as invalid sound configs', () {
      expect(FocusSoundCatalog.trackIdsFor('rain+missing'), isEmpty);
      expect(FocusSoundCatalog.assetsFor('missing'), isEmpty);
      expect(FocusSoundCatalog.labelFor('missing'), '无白噪音');
    });

    test('generated noise ids are unpublished', () {
      final trackIds = FocusSoundCatalog.tracks.map((track) => track.id);
      final optionIds = FocusSoundCatalog.options.map((option) => option.id);

      for (final id in bannedGeneratedNoiseIds) {
        expect(trackIds, isNot(contains(id)));
        expect(optionIds, isNot(contains(id)));
        expect(FocusSoundCatalog.assetMap, isNot(contains(id)));
        expect(FocusSoundCatalog.trackIdsFor(id), isEmpty);
        expect(FocusSoundCatalog.assetsFor(id), isEmpty);
        expect(FocusSoundCatalog.labelFor(id), '无白噪音');
        expect(FocusSoundCatalog.normalizeForPlayback(id), 'night_rain');
      }
    });

    test(
      'legacy generated-noise configs fall back to a smooth real recording',
      () {
        expect(
          FocusSoundCatalog.normalizeForPlayback('white_stream'),
          'night_rain',
        );
        expect(
          FocusSoundCatalog.assetsFor(
            FocusSoundCatalog.normalizeForPlayback('white_stream'),
          ),
          <String>['sounds/white_noise/night_rain.mp3'],
        );
        expect(FocusSoundCatalog.normalizeForPlayback('missing'), 'none');
      },
    );

    test('published options are single track only', () {
      final ids = FocusSoundCatalog.options.map((option) => option.id).toSet();
      expect(ids, isNot(contains('rain+thunderstorm')));
      expect(ids, isNot(contains('waves+storm_rain')));
      expect(ids, isNot(contains('forest+deep_stream')));
      expect(ids, isNot(contains('cafe+rain')));
      expect(
        FocusSoundCatalog.options
            .where((option) => !option.isNone)
            .every((option) => !option.isMix),
        isTrue,
      );
    });

    test('visible track labels avoid generated-noise wording', () {
      for (final track in FocusSoundCatalog.tracks) {
        expect(track.label, isNot(contains('噪')), reason: track.id);
        expect(track.label, isNot(contains('合成')), reason: track.id);
        expect(track.label, isNot(contains('生成')), reason: track.id);
      }
    });

    test(
      'retained built-in metadata follows zh-en-zh without replacing IDs',
      () {
        final tracks = FocusSoundCatalog.tracks;
        final options = FocusSoundCatalog.options;
        final chineseLabels = tracks.map((track) => track.label).toList();
        final trackIds = tracks.map((track) => track.id).toList();
        final optionIds = options.map((option) => option.id).toList();
        final assets = tracks.map((track) => track.asset).toList();
        final selectedTrack = FocusSoundCatalog.trackFor('rain')!;
        final selectedOption = FocusSoundCatalog.optionFor('rain')!;

        expect(selectedTrack.label, '窗边雨声');
        expect(selectedOption.label, '窗边雨声');
        I18n.setLocale(AppLocale.en);
        expect(selectedTrack.label, 'Rain by the window');
        expect(selectedOption.label, 'Rain by the window');
        expect(FocusSoundCatalog.labelFor('none'), 'No ambient sound');

        for (final track in tracks) {
          expect(track.label, isNotEmpty, reason: track.id);
          expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(track.label), isFalse);
          expect(FocusSoundCatalog.optionFor(track.id)!.label, track.label);
          expect(FocusSoundCatalog.labelFor(track.id), track.label);
        }
        expect(FocusSoundCatalog.tracks, same(tracks));
        expect(FocusSoundCatalog.options, same(options));
        expect(tracks.map((track) => track.id).toList(), trackIds);
        expect(options.map((option) => option.id).toList(), optionIds);
        expect(tracks.map((track) => track.asset).toList(), assets);

        I18n.setLocale(AppLocale.zh);
        expect(tracks.map((track) => track.label).toList(), chineseLabels);
        expect(selectedTrack.label, '窗边雨声');
        expect(selectedOption.label, '窗边雨声');
        expect(FocusSoundCatalog.labelFor('none'), '无白噪音');
      },
    );

    test('an explicit display locale leaves the live locale unchanged', () {
      final track = FocusSoundCatalog.trackFor('cafe')!;
      final option = FocusSoundCatalog.optionFor('cafe')!;
      expect(track.displayLabel(locale: AppLocale.en), 'Afternoon café');
      expect(option.displayLabel(locale: AppLocale.en), 'Afternoon café');
      expect(
        FocusSoundCatalog.labelFor('cafe', locale: AppLocale.en),
        'Afternoon café',
      );
      expect(I18n.current, AppLocale.zh);
      expect(track.label, '午后咖啡馆');
      I18n.setLocale(AppLocale.en);
      expect(track.displayLabel(locale: AppLocale.zh), '午后咖啡馆');
      expect(option.displayLabel(locale: AppLocale.zh), '午后咖啡馆');
      expect(I18n.current, AppLocale.en);
    });

    test(
      'fallback track options retain bilingual metadata across switches',
      () {
        final option = FocusSoundCatalog.optionFor(' rain ')!;
        expect(option.id, 'rain');
        expect(option.trackIds, ['rain']);
        expect(option.label, '窗边雨声');
        I18n.setLocale(AppLocale.en);
        expect(option.label, 'Rain by the window');
        I18n.setLocale(AppLocale.zh);
        expect(option.label, '窗边雨声');
      },
    );

    test('invalid playback choices have localized absence labels', () {
      for (final id in ['missing', 'rain+forest', ...bannedGeneratedNoiseIds]) {
        expect(FocusSoundCatalog.labelFor(id, locale: AppLocale.zh), '无白噪音');
        expect(
          FocusSoundCatalog.labelFor(id, locale: AppLocale.en),
          'No ambient sound',
        );
        expect(FocusSoundCatalog.trackIdsFor(id), isEmpty);
        expect(FocusSoundCatalog.assetsFor(id), isEmpty);
      }
    });

    test(
      'literal metadata without a translation stays authored in any locale',
      () {
        const literal = '我的 rain — custom café  ';
        const track = FocusSoundTrack(
          id: 'rain',
          label: literal,
          asset: 'custom',
        );
        const option = FocusSoundOption(
          id: 'rain',
          label: literal,
          trackIds: ['rain'],
        );
        for (final locale in AppLocale.values) {
          I18n.setLocale(locale);
          expect(track.label, literal);
          expect(option.label, literal);
          expect(track.asset, 'custom');
        }
      },
    );

    test(
      'locale changes preserve playback normalization and asset selection',
      () {
        final values = [
          'rain',
          ' rain ',
          'none',
          'missing',
          'rain+forest',
          ...bannedGeneratedNoiseIds,
        ];
        final normalized = values
            .map(FocusSoundCatalog.normalizeForPlayback)
            .toList();
        final assets = values.map(FocusSoundCatalog.assetsFor).toList();
        final assetMap = Map<String, String>.of(FocusSoundCatalog.assetMap);
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          expect(
            values.map(FocusSoundCatalog.normalizeForPlayback).toList(),
            normalized,
          );
          expect(values.map(FocusSoundCatalog.assetsFor).toList(), assets);
          expect(FocusSoundCatalog.assetMap, assetMap);
        }
      },
    );
  });
}
