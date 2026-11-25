// NEW858: original21 I18n output contract for generated consumption.
// Freeze the original21 I18n outputs; never obtain expected values from
// generated localization, ARBs, I18n.tr or AppBrand.localizedName.
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocale originalLocale;
  setUp(() {
    originalLocale = I18n.current;
  });
  tearDown(() => I18n.setLocale(originalLocale));

  test('theme adapter21 keys retain frozen outputs through zh en zh', () {
    final readers = <String, String Function()>{
      for (final key in _themeOutputs.keys) key: () => I18n.tr(key),
    };
    for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      for (final entry in readers.entries) {
        expect(
          entry.value(),
          _expected(_themeOutputs[entry.key]!, locale),
          reason: entry.key,
        );
      }
    }
  });

  test(
    'theme adapter explicit locale preserves output and selected locale without notifications',
    () {
      for (final selected in [AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(selected);
        final notifierBefore = I18n.localeListenable.value;
        var notifications = 0;
        void observe() => notifications++;
        I18n.localeListenable.addListener(observe);
        try {
          final opposite = selected == AppLocale.zh
              ? AppLocale.en
              : AppLocale.zh;
          for (final requested in [opposite, selected, opposite]) {
            for (final entry in _themeOutputs.entries) {
              expect(
                I18n.trForLocale(entry.key, requested),
                _expected(entry.value, requested),
                reason:
                    '${entry.key}, selected $selected, requested $requested',
              );
              expect(I18n.current, selected);
              expect(I18n.localeListenable.value, notifierBefore);
              expect(notifications, 0);
            }
          }
        } finally {
          I18n.localeListenable.removeListener(observe);
        }
      }
    },
  );

  test(
    'theme adapter unknown near keys and real non theme outputs keep compatibility',
    () {
      for (final selected in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(selected);
        for (final key in _passthroughKeys) {
          expect(I18n.tr(key), key, reason: key);
          for (final requested in AppLocale.values) {
            expect(I18n.trForLocale(key, requested), key, reason: key);
            expect(I18n.current, selected);
          }
        }
        for (final entry in _nonThemeOutputs.entries) {
          expect(
            I18n.tr(entry.key),
            _expected(entry.value, selected),
            reason: entry.key,
          );
          for (final requested in AppLocale.values) {
            expect(
              I18n.trForLocale(entry.key, requested),
              _expected(entry.value, requested),
              reason: entry.key,
            );
            expect(I18n.current, selected);
          }
        }
      }
    },
  );

  test(
    'theme adapter nine real AppBrands retain localized names through zh en zh',
    () {
      final brands = AppBrands.all;
      expect(
        brands.map((brand) => brand.id),
        unorderedEquals(_brandNames.keys),
      );
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        for (final brand in brands) {
          final expected = _brandNames[brand.id]!;
          expect(AppBrands.byId(brand.id), same(brand));
          expect(
            brand.localizedName,
            _expected(expected, locale),
            reason: brand.id,
          );
          // The stable domain name stays unchanged when display locale changes.
          expect(brand.name, expected.zh, reason: brand.id);
        }
      }
    },
  );
}

typedef _LocalizedOutput = ({String zh, String en});
String _expected(_LocalizedOutput output, AppLocale locale) =>
    locale == AppLocale.zh ? output.zh : output.en;

const _themeOutputs = <String, _LocalizedOutput>{
  'theme.title': (zh: '主题风格', en: 'Theme style'),
  'theme.section.styles': (zh: '可选风格', en: 'Available styles'),
  'theme.section.styles.subtitle': (
    zh: '切换后会同步全局主题',
    en: 'Changes apply to the whole app',
  ),
  'theme.style.default.name': (zh: '多仪', en: 'Duoyi'),
  'theme.style.default.description': (
    zh: '简洁原版 · 暖橙基调',
    en: 'Clean original · warm orange base',
  ),
  'theme.style.re0.name': (zh: '从零开始', en: 'Re:Zero'),
  'theme.style.re0.description': (
    zh: '银发魔女 · 露格尼卡圣域',
    en: 'Silver-haired witch · Lugunica sanctuary',
  ),
  'theme.style.genshin.name': (zh: '原神', en: 'Genshin Impact'),
  'theme.style.genshin.description': (
    zh: '元素绘卷 · 提瓦特画架',
    en: 'Elemental scroll · Teyvat easel',
  ),
  'theme.style.star_rail.name': (zh: '星穹铁道', en: 'Honkai: Star Rail'),
  'theme.style.star_rail.description': (
    zh: '星穹列车 · 开拓之旅',
    en: 'Astral Express · trailblazing journey',
  ),
  'theme.style.wuthering.name': (zh: '鸣潮', en: 'Wuthering Waves'),
  'theme.style.wuthering.description': (
    zh: '共鸣终端 · 潮声频谱',
    en: 'Resonance terminal · tidal spectrum',
  ),
  'theme.style.zzz.name': (zh: '绝区零', en: 'Zenless Zone Zero'),
  'theme.style.zzz.description': (
    zh: '委托影像 · 新艾利都',
    en: 'Commission footage · New Eridu',
  ),
  'theme.style.yanyun.name': (zh: '燕云十六声', en: 'Where Winds Meet'),
  'theme.style.yanyun.description': (
    zh: '江湖画案 · 墨痕回转',
    en: 'Jianghu sketchbook · ink trails',
  ),
  'theme.style.botw.name': (zh: '希卡之石', en: 'Sheikah Slate'),
  'theme.style.botw.description': (
    zh: '希卡之石 · 具现化',
    en: 'Sheikah Slate · materialized',
  ),
  'theme.style.liquid_glass.name': (zh: '液态玻璃', en: 'Liquid Glass'),
  'theme.style.liquid_glass.description': (
    zh: 'iOS 玻璃拟态 · 半透明白与高光',
    en: 'iOS glassmorphism · translucent white and highlights',
  ),
};

const _nonThemeOutputs = <String, _LocalizedOutput>{
  'action.confirm': (zh: '确定', en: 'OK'),
  'nav.today': (zh: '今日', en: 'Today'),
  'todo.matrix': (zh: '四象限', en: 'Matrix'),
};

const _passthroughKeys = <String>[
  '',
  'theme',
  'theme.',
  'Theme.title',
  'theme.title ',
  'theme.title\u200b',
  'theme.style.default.NAME',
  'theme.style.starRail.name',
  'theme.style.liquidGlass.description',
  'theme.style.not_exist.name',
  'theme.section.styles.subtitle.extra',
  'theme.style.default.name\u0000',
  'unknown858.自定义🧩',
];

const _brandNames = <String, _LocalizedOutput>{
  'defaultBrand': (zh: '多仪', en: 'Duoyi'),
  're0': (zh: '从零开始', en: 'Re:Zero'),
  'genshin': (zh: '原神', en: 'Genshin Impact'),
  'starRail': (zh: '星穹铁道', en: 'Honkai: Star Rail'),
  'wuthering': (zh: '鸣潮', en: 'Wuthering Waves'),
  'zzz': (zh: '绝区零', en: 'Zenless Zone Zero'),
  'yanyun': (zh: '燕云十六声', en: 'Where Winds Meet'),
  'botw': (zh: '希卡之石', en: 'Sheikah Slate'),
  'liquidGlass': (zh: '液态玻璃', en: 'Liquid Glass'),
};
