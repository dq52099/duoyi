import 'package:duoyi/core/focus_sound_catalog.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
