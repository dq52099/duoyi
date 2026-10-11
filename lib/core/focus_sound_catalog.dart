import 'i18n.dart';

class FocusSoundTrack {
  final String id;
  final String _label;
  final String? _englishLabel;
  final String asset;

  const FocusSoundTrack({
    required this.id,
    required String label,
    String? englishLabel,
    required this.asset,
  }) : _label = label,
       _englishLabel = englishLabel;

  String get label => displayLabel();

  String displayLabel({AppLocale? locale}) =>
      (locale ?? I18n.current) == AppLocale.en
      ? _englishLabel ?? _label
      : _label;
}

class FocusSoundOption {
  final String id;
  final String _label;
  final String? _englishLabel;
  final List<String> trackIds;

  const FocusSoundOption({
    required this.id,
    required String label,
    String? englishLabel,
    required this.trackIds,
  }) : _label = label,
       _englishLabel = englishLabel;

  String get label => displayLabel();

  String displayLabel({AppLocale? locale}) =>
      (locale ?? I18n.current) == AppLocale.en
      ? _englishLabel ?? _label
      : _label;

  bool get isNone => id == FocusSoundCatalog.none;
  bool get isMix => trackIds.length > 1;
}

class FocusSoundCatalog {
  FocusSoundCatalog._();

  static const String none = 'none';

  static const List<FocusSoundTrack> tracks = <FocusSoundTrack>[
    FocusSoundTrack(
      id: 'rain',
      label: '窗边雨声',
      englishLabel: 'Rain by the window',
      asset: 'sounds/white_noise/rain.mp3',
    ),
    FocusSoundTrack(
      id: 'forest',
      label: '雨林步行',
      englishLabel: 'Rainforest walk',
      asset: 'sounds/white_noise/forest.mp3',
    ),
    FocusSoundTrack(
      id: 'cafe',
      label: '午后咖啡馆',
      englishLabel: 'Afternoon café',
      asset: 'sounds/white_noise/cafe.mp3',
    ),
    FocusSoundTrack(
      id: 'waves',
      label: '海浪拍岸',
      englishLabel: 'Waves on the shore',
      asset: 'sounds/white_noise/waves.mp3',
    ),
    FocusSoundTrack(
      id: 'night_rain',
      label: '静夜细雨',
      englishLabel: 'Gentle night rain',
      asset: 'sounds/white_noise/night_rain.mp3',
    ),
    FocusSoundTrack(
      id: 'fan',
      label: '桌面风扇',
      englishLabel: 'Desk fan',
      asset: 'sounds/white_noise/fan.mp3',
    ),
    FocusSoundTrack(
      id: 'deep_stream',
      label: '低频溪流',
      englishLabel: 'Deep stream',
      asset: 'sounds/white_noise/deep_stream.mp3',
    ),
    FocusSoundTrack(
      id: 'thunderstorm',
      label: '雷雨天气',
      englishLabel: 'Thunderstorm',
      asset: 'sounds/white_noise/thunderstorm.mp3',
    ),
    FocusSoundTrack(
      id: 'storm_rain',
      label: '狂风暴雨',
      englishLabel: 'Wind and heavy rain',
      asset: 'sounds/white_noise/storm_rain.mp3',
    ),
    FocusSoundTrack(
      id: 'campfire',
      label: '篝火轻响',
      englishLabel: 'Crackling campfire',
      asset: 'sounds/white_noise/campfire.mp3',
    ),
    FocusSoundTrack(
      id: 'dawn_birds',
      label: '清晨鸟鸣',
      englishLabel: 'Birds at dawn',
      asset: 'sounds/white_noise/dawn_birds.mp3',
    ),
    FocusSoundTrack(
      id: 'waterfall',
      label: '瀑布水雾',
      englishLabel: 'Waterfall',
      asset: 'sounds/white_noise/waterfall.mp3',
    ),
    FocusSoundTrack(
      id: 'brook',
      label: '山谷溪涧',
      englishLabel: 'Mountain brook',
      asset: 'sounds/white_noise/brook.mp3',
    ),
    FocusSoundTrack(
      id: 'river',
      label: '河岸水流',
      englishLabel: 'Riverbank water',
      asset: 'sounds/white_noise/river.mp3',
    ),
    FocusSoundTrack(
      id: 'crickets',
      label: '夏夜虫鸣',
      englishLabel: 'Summer night crickets',
      asset: 'sounds/white_noise/crickets.mp3',
    ),
    FocusSoundTrack(
      id: 'clock',
      label: '机械钟摆',
      englishLabel: 'Pendulum clock',
      asset: 'sounds/white_noise/clock.mp3',
    ),
    FocusSoundTrack(
      id: 'keyboard',
      label: '键盘轻敲',
      englishLabel: 'Gentle typing',
      asset: 'sounds/white_noise/keyboard.mp3',
    ),
    FocusSoundTrack(
      id: 'wind',
      label: '穿堂风声',
      englishLabel: 'Breeze through the room',
      asset: 'sounds/white_noise/wind.mp3',
    ),
    FocusSoundTrack(
      id: 'train_station',
      label: '月台列车',
      englishLabel: 'Train platform',
      asset: 'sounds/white_noise/train_station.mp3',
    ),
    FocusSoundTrack(
      id: 'classroom',
      label: '教室环境',
      englishLabel: 'Classroom ambience',
      asset: 'sounds/white_noise/classroom.mp3',
    ),
    FocusSoundTrack(
      id: 'pebble_beach',
      label: '卵石浪声',
      englishLabel: 'Pebble beach waves',
      asset: 'sounds/white_noise/pebble_beach.mp3',
    ),
    FocusSoundTrack(
      id: 'mall',
      label: '商场人声',
      englishLabel: 'Shopping mall ambience',
      asset: 'sounds/white_noise/mall.mp3',
    ),
    FocusSoundTrack(
      id: 'restaurant',
      label: '餐厅低语',
      englishLabel: 'Restaurant chatter',
      asset: 'sounds/white_noise/restaurant.mp3',
    ),
    FocusSoundTrack(
      id: 'garden_birds',
      label: '庭院鸟鸣',
      englishLabel: 'Garden birds',
      asset: 'sounds/white_noise/garden_birds.mp3',
    ),
    FocusSoundTrack(
      id: 'country_night',
      label: '乡野夜声',
      englishLabel: 'Countryside night',
      asset: 'sounds/white_noise/country_night.mp3',
    ),
    FocusSoundTrack(
      id: 'shallow_river',
      label: '石床浅河',
      englishLabel: 'Shallow river',
      asset: 'sounds/white_noise/shallow_river.mp3',
    ),
    FocusSoundTrack(
      id: 'veranda_rain',
      label: '廊下雨雷',
      englishLabel: 'Rain and thunder on the veranda',
      asset: 'sounds/white_noise/veranda_rain.mp3',
    ),
    FocusSoundTrack(
      id: 'breeze_birds',
      label: '微风鸟鸣',
      englishLabel: 'Birds in the breeze',
      asset: 'sounds/white_noise/breeze_birds.mp3',
    ),
  ];

  static const List<FocusSoundOption> options = <FocusSoundOption>[
    FocusSoundOption(
      id: none,
      label: '无白噪音',
      englishLabel: 'No ambient sound',
      trackIds: <String>[],
    ),
    ..._singleOptions,
  ];

  static const List<FocusSoundOption> _singleOptions = <FocusSoundOption>[
    FocusSoundOption(
      id: 'rain',
      label: '窗边雨声',
      englishLabel: 'Rain by the window',
      trackIds: <String>['rain'],
    ),
    FocusSoundOption(
      id: 'forest',
      label: '雨林步行',
      englishLabel: 'Rainforest walk',
      trackIds: <String>['forest'],
    ),
    FocusSoundOption(
      id: 'cafe',
      label: '午后咖啡馆',
      englishLabel: 'Afternoon café',
      trackIds: <String>['cafe'],
    ),
    FocusSoundOption(
      id: 'waves',
      label: '海浪拍岸',
      englishLabel: 'Waves on the shore',
      trackIds: <String>['waves'],
    ),
    FocusSoundOption(
      id: 'night_rain',
      label: '静夜细雨',
      englishLabel: 'Gentle night rain',
      trackIds: <String>['night_rain'],
    ),
    FocusSoundOption(
      id: 'fan',
      label: '桌面风扇',
      englishLabel: 'Desk fan',
      trackIds: <String>['fan'],
    ),
    FocusSoundOption(
      id: 'deep_stream',
      label: '低频溪流',
      englishLabel: 'Deep stream',
      trackIds: <String>['deep_stream'],
    ),
    FocusSoundOption(
      id: 'thunderstorm',
      label: '雷雨天气',
      englishLabel: 'Thunderstorm',
      trackIds: <String>['thunderstorm'],
    ),
    FocusSoundOption(
      id: 'storm_rain',
      label: '狂风暴雨',
      englishLabel: 'Wind and heavy rain',
      trackIds: <String>['storm_rain'],
    ),
    FocusSoundOption(
      id: 'campfire',
      label: '篝火轻响',
      englishLabel: 'Crackling campfire',
      trackIds: <String>['campfire'],
    ),
    FocusSoundOption(
      id: 'dawn_birds',
      label: '清晨鸟鸣',
      englishLabel: 'Birds at dawn',
      trackIds: <String>['dawn_birds'],
    ),
    FocusSoundOption(
      id: 'waterfall',
      label: '瀑布水雾',
      englishLabel: 'Waterfall',
      trackIds: <String>['waterfall'],
    ),
    FocusSoundOption(
      id: 'brook',
      label: '山谷溪涧',
      englishLabel: 'Mountain brook',
      trackIds: <String>['brook'],
    ),
    FocusSoundOption(
      id: 'river',
      label: '河岸水流',
      englishLabel: 'Riverbank water',
      trackIds: <String>['river'],
    ),
    FocusSoundOption(
      id: 'crickets',
      label: '夏夜虫鸣',
      englishLabel: 'Summer night crickets',
      trackIds: <String>['crickets'],
    ),
    FocusSoundOption(
      id: 'clock',
      label: '机械钟摆',
      englishLabel: 'Pendulum clock',
      trackIds: <String>['clock'],
    ),
    FocusSoundOption(
      id: 'keyboard',
      label: '键盘轻敲',
      englishLabel: 'Gentle typing',
      trackIds: <String>['keyboard'],
    ),
    FocusSoundOption(
      id: 'wind',
      label: '穿堂风声',
      englishLabel: 'Breeze through the room',
      trackIds: <String>['wind'],
    ),
    FocusSoundOption(
      id: 'train_station',
      label: '月台列车',
      englishLabel: 'Train platform',
      trackIds: <String>['train_station'],
    ),
    FocusSoundOption(
      id: 'classroom',
      label: '教室环境',
      englishLabel: 'Classroom ambience',
      trackIds: <String>['classroom'],
    ),
    FocusSoundOption(
      id: 'pebble_beach',
      label: '卵石浪声',
      englishLabel: 'Pebble beach waves',
      trackIds: <String>['pebble_beach'],
    ),
    FocusSoundOption(
      id: 'mall',
      label: '商场人声',
      englishLabel: 'Shopping mall ambience',
      trackIds: <String>['mall'],
    ),
    FocusSoundOption(
      id: 'restaurant',
      label: '餐厅低语',
      englishLabel: 'Restaurant chatter',
      trackIds: <String>['restaurant'],
    ),
    FocusSoundOption(
      id: 'garden_birds',
      label: '庭院鸟鸣',
      englishLabel: 'Garden birds',
      trackIds: <String>['garden_birds'],
    ),
    FocusSoundOption(
      id: 'country_night',
      label: '乡野夜声',
      englishLabel: 'Countryside night',
      trackIds: <String>['country_night'],
    ),
    FocusSoundOption(
      id: 'shallow_river',
      label: '石床浅河',
      englishLabel: 'Shallow river',
      trackIds: <String>['shallow_river'],
    ),
    FocusSoundOption(
      id: 'veranda_rain',
      label: '廊下雨雷',
      englishLabel: 'Rain and thunder on the veranda',
      trackIds: <String>['veranda_rain'],
    ),
    FocusSoundOption(
      id: 'breeze_birds',
      label: '微风鸟鸣',
      englishLabel: 'Birds in the breeze',
      trackIds: <String>['breeze_birds'],
    ),
  ];

  static const Map<String, String> assetMap = <String, String>{
    'rain': 'sounds/white_noise/rain.mp3',
    'forest': 'sounds/white_noise/forest.mp3',
    'cafe': 'sounds/white_noise/cafe.mp3',
    'waves': 'sounds/white_noise/waves.mp3',
    'night_rain': 'sounds/white_noise/night_rain.mp3',
    'fan': 'sounds/white_noise/fan.mp3',
    'deep_stream': 'sounds/white_noise/deep_stream.mp3',
    'thunderstorm': 'sounds/white_noise/thunderstorm.mp3',
    'storm_rain': 'sounds/white_noise/storm_rain.mp3',
    'campfire': 'sounds/white_noise/campfire.mp3',
    'dawn_birds': 'sounds/white_noise/dawn_birds.mp3',
    'waterfall': 'sounds/white_noise/waterfall.mp3',
    'brook': 'sounds/white_noise/brook.mp3',
    'river': 'sounds/white_noise/river.mp3',
    'crickets': 'sounds/white_noise/crickets.mp3',
    'clock': 'sounds/white_noise/clock.mp3',
    'keyboard': 'sounds/white_noise/keyboard.mp3',
    'wind': 'sounds/white_noise/wind.mp3',
    'train_station': 'sounds/white_noise/train_station.mp3',
    'classroom': 'sounds/white_noise/classroom.mp3',
    'pebble_beach': 'sounds/white_noise/pebble_beach.mp3',
    'mall': 'sounds/white_noise/mall.mp3',
    'restaurant': 'sounds/white_noise/restaurant.mp3',
    'garden_birds': 'sounds/white_noise/garden_birds.mp3',
    'country_night': 'sounds/white_noise/country_night.mp3',
    'shallow_river': 'sounds/white_noise/shallow_river.mp3',
    'veranda_rain': 'sounds/white_noise/veranda_rain.mp3',
    'breeze_birds': 'sounds/white_noise/breeze_birds.mp3',
  };

  static String labelFor(String sound, {AppLocale? locale}) {
    return (optionFor(sound) ?? options.first).displayLabel(locale: locale);
  }

  static String normalizeForPlayback(String sound) {
    final clean = sound.trim();
    if (clean.isEmpty || clean == none) return none;
    if (trackIdsFor(clean).isNotEmpty) return clean;
    if (clean.endsWith('_noise') || clean == ['white', 'stream'].join('_')) {
      return 'night_rain';
    }
    return none;
  }

  static FocusSoundOption? optionFor(String sound) {
    for (final option in options) {
      if (option.id == sound) return option;
    }
    final trackIds = trackIdsFor(sound);
    if (trackIds.isEmpty) return null;
    final track = trackFor(trackIds.first);
    if (track == null) return null;
    return FocusSoundOption(
      id: track.id,
      label: track._label,
      englishLabel: track._englishLabel,
      trackIds: <String>[track.id],
    );
  }

  static FocusSoundTrack? trackFor(String id) {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  static List<String> trackIdsFor(String sound) {
    final id = sound.trim();
    if (id.isEmpty || id == none || id.contains('+')) return const <String>[];
    if (!assetMap.containsKey(id)) return const <String>[];
    return <String>[id];
  }

  static List<String> assetsFor(String sound) {
    return trackIdsFor(
      sound,
    ).map((id) => assetMap[id]!).toList(growable: false);
  }
}
