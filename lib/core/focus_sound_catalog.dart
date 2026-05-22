class FocusSoundTrack {
  final String id;
  final String label;
  final String asset;

  const FocusSoundTrack({
    required this.id,
    required this.label,
    required this.asset,
  });
}

class FocusSoundOption {
  final String id;
  final String label;
  final List<String> trackIds;

  const FocusSoundOption({
    required this.id,
    required this.label,
    required this.trackIds,
  });

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
      asset: 'sounds/white_noise/rain.mp3',
    ),
    FocusSoundTrack(
      id: 'forest',
      label: '雨林步行',
      asset: 'sounds/white_noise/forest.mp3',
    ),
    FocusSoundTrack(
      id: 'cafe',
      label: '午后咖啡馆',
      asset: 'sounds/white_noise/cafe.mp3',
    ),
    FocusSoundTrack(
      id: 'waves',
      label: '海浪拍岸',
      asset: 'sounds/white_noise/waves.mp3',
    ),
    FocusSoundTrack(
      id: 'brown_noise',
      label: '低频暖流',
      asset: 'sounds/white_noise/brown_noise.mp3',
    ),
    FocusSoundTrack(
      id: 'night_rain',
      label: '静夜细雨',
      asset: 'sounds/white_noise/night_rain.mp3',
    ),
    FocusSoundTrack(
      id: 'fan',
      label: '桌面风扇',
      asset: 'sounds/white_noise/fan.mp3',
    ),
    FocusSoundTrack(
      id: 'pink_noise',
      label: '柔和静流',
      asset: 'sounds/white_noise/pink_noise.mp3',
    ),
    FocusSoundTrack(
      id: 'deep_stream',
      label: '低频溪流',
      asset: 'sounds/white_noise/deep_stream.mp3',
    ),
    FocusSoundTrack(
      id: 'thunderstorm',
      label: '雷雨天气',
      asset: 'sounds/white_noise/thunderstorm.mp3',
    ),
    FocusSoundTrack(
      id: 'storm_rain',
      label: '狂风暴雨',
      asset: 'sounds/white_noise/storm_rain.mp3',
    ),
    FocusSoundTrack(
      id: 'campfire',
      label: '篝火轻响',
      asset: 'sounds/white_noise/campfire.mp3',
    ),
    FocusSoundTrack(
      id: 'dawn_birds',
      label: '清晨鸟鸣',
      asset: 'sounds/white_noise/dawn_birds.mp3',
    ),
    FocusSoundTrack(
      id: 'waterfall',
      label: '瀑布水雾',
      asset: 'sounds/white_noise/waterfall.mp3',
    ),
    FocusSoundTrack(
      id: 'brook',
      label: '山谷溪涧',
      asset: 'sounds/white_noise/brook.mp3',
    ),
    FocusSoundTrack(
      id: 'river',
      label: '河岸水流',
      asset: 'sounds/white_noise/river.mp3',
    ),
    FocusSoundTrack(
      id: 'crickets',
      label: '夏夜虫鸣',
      asset: 'sounds/white_noise/crickets.mp3',
    ),
    FocusSoundTrack(
      id: 'white_stream',
      label: '白色静流',
      asset: 'sounds/white_noise/white_stream.mp3',
    ),
    FocusSoundTrack(
      id: 'clock',
      label: '机械钟摆',
      asset: 'sounds/white_noise/clock.mp3',
    ),
    FocusSoundTrack(
      id: 'keyboard',
      label: '键盘轻敲',
      asset: 'sounds/white_noise/keyboard.mp3',
    ),
    FocusSoundTrack(
      id: 'wind',
      label: '穿堂风声',
      asset: 'sounds/white_noise/wind.mp3',
    ),
    FocusSoundTrack(
      id: 'train_station',
      label: '月台列车',
      asset: 'sounds/white_noise/train_station.mp3',
    ),
    FocusSoundTrack(
      id: 'classroom',
      label: '教室环境',
      asset: 'sounds/white_noise/classroom.mp3',
    ),
    FocusSoundTrack(
      id: 'pebble_beach',
      label: '卵石浪声',
      asset: 'sounds/white_noise/pebble_beach.mp3',
    ),
    FocusSoundTrack(
      id: 'mall',
      label: '商场人声',
      asset: 'sounds/white_noise/mall.mp3',
    ),
    FocusSoundTrack(
      id: 'restaurant',
      label: '餐厅低语',
      asset: 'sounds/white_noise/restaurant.mp3',
    ),
    FocusSoundTrack(
      id: 'garden_birds',
      label: '庭院鸟鸣',
      asset: 'sounds/white_noise/garden_birds.mp3',
    ),
    FocusSoundTrack(
      id: 'country_night',
      label: '乡野夜声',
      asset: 'sounds/white_noise/country_night.mp3',
    ),
    FocusSoundTrack(
      id: 'shallow_river',
      label: '石床浅河',
      asset: 'sounds/white_noise/shallow_river.mp3',
    ),
    FocusSoundTrack(
      id: 'veranda_rain',
      label: '廊下雨雷',
      asset: 'sounds/white_noise/veranda_rain.mp3',
    ),
    FocusSoundTrack(
      id: 'breeze_birds',
      label: '微风鸟鸣',
      asset: 'sounds/white_noise/breeze_birds.mp3',
    ),
  ];

  static const List<FocusSoundOption> options = <FocusSoundOption>[
    FocusSoundOption(id: none, label: '无白噪音', trackIds: <String>[]),
    ..._singleOptions,
  ];

  static const List<FocusSoundOption> _singleOptions = <FocusSoundOption>[
    FocusSoundOption(id: 'rain', label: '窗边雨声', trackIds: <String>['rain']),
    FocusSoundOption(id: 'forest', label: '雨林步行', trackIds: <String>['forest']),
    FocusSoundOption(id: 'cafe', label: '午后咖啡馆', trackIds: <String>['cafe']),
    FocusSoundOption(id: 'waves', label: '海浪拍岸', trackIds: <String>['waves']),
    FocusSoundOption(
      id: 'brown_noise',
      label: '低频暖流',
      trackIds: <String>['brown_noise'],
    ),
    FocusSoundOption(
      id: 'night_rain',
      label: '静夜细雨',
      trackIds: <String>['night_rain'],
    ),
    FocusSoundOption(id: 'fan', label: '桌面风扇', trackIds: <String>['fan']),
    FocusSoundOption(
      id: 'pink_noise',
      label: '柔和静流',
      trackIds: <String>['pink_noise'],
    ),
    FocusSoundOption(
      id: 'deep_stream',
      label: '低频溪流',
      trackIds: <String>['deep_stream'],
    ),
    FocusSoundOption(
      id: 'thunderstorm',
      label: '雷雨天气',
      trackIds: <String>['thunderstorm'],
    ),
    FocusSoundOption(
      id: 'storm_rain',
      label: '狂风暴雨',
      trackIds: <String>['storm_rain'],
    ),
    FocusSoundOption(
      id: 'campfire',
      label: '篝火轻响',
      trackIds: <String>['campfire'],
    ),
    FocusSoundOption(
      id: 'dawn_birds',
      label: '清晨鸟鸣',
      trackIds: <String>['dawn_birds'],
    ),
    FocusSoundOption(
      id: 'waterfall',
      label: '瀑布水雾',
      trackIds: <String>['waterfall'],
    ),
    FocusSoundOption(id: 'brook', label: '山谷溪涧', trackIds: <String>['brook']),
    FocusSoundOption(id: 'river', label: '河岸水流', trackIds: <String>['river']),
    FocusSoundOption(
      id: 'crickets',
      label: '夏夜虫鸣',
      trackIds: <String>['crickets'],
    ),
    FocusSoundOption(
      id: 'white_stream',
      label: '白色静流',
      trackIds: <String>['white_stream'],
    ),
    FocusSoundOption(id: 'clock', label: '机械钟摆', trackIds: <String>['clock']),
    FocusSoundOption(
      id: 'keyboard',
      label: '键盘轻敲',
      trackIds: <String>['keyboard'],
    ),
    FocusSoundOption(id: 'wind', label: '穿堂风声', trackIds: <String>['wind']),
    FocusSoundOption(
      id: 'train_station',
      label: '月台列车',
      trackIds: <String>['train_station'],
    ),
    FocusSoundOption(
      id: 'classroom',
      label: '教室环境',
      trackIds: <String>['classroom'],
    ),
    FocusSoundOption(
      id: 'pebble_beach',
      label: '卵石浪声',
      trackIds: <String>['pebble_beach'],
    ),
    FocusSoundOption(id: 'mall', label: '商场人声', trackIds: <String>['mall']),
    FocusSoundOption(
      id: 'restaurant',
      label: '餐厅低语',
      trackIds: <String>['restaurant'],
    ),
    FocusSoundOption(
      id: 'garden_birds',
      label: '庭院鸟鸣',
      trackIds: <String>['garden_birds'],
    ),
    FocusSoundOption(
      id: 'country_night',
      label: '乡野夜声',
      trackIds: <String>['country_night'],
    ),
    FocusSoundOption(
      id: 'shallow_river',
      label: '石床浅河',
      trackIds: <String>['shallow_river'],
    ),
    FocusSoundOption(
      id: 'veranda_rain',
      label: '廊下雨雷',
      trackIds: <String>['veranda_rain'],
    ),
    FocusSoundOption(
      id: 'breeze_birds',
      label: '微风鸟鸣',
      trackIds: <String>['breeze_birds'],
    ),
  ];

  static const Map<String, String> assetMap = <String, String>{
    'rain': 'sounds/white_noise/rain.mp3',
    'forest': 'sounds/white_noise/forest.mp3',
    'cafe': 'sounds/white_noise/cafe.mp3',
    'waves': 'sounds/white_noise/waves.mp3',
    'brown_noise': 'sounds/white_noise/brown_noise.mp3',
    'night_rain': 'sounds/white_noise/night_rain.mp3',
    'fan': 'sounds/white_noise/fan.mp3',
    'pink_noise': 'sounds/white_noise/pink_noise.mp3',
    'deep_stream': 'sounds/white_noise/deep_stream.mp3',
    'thunderstorm': 'sounds/white_noise/thunderstorm.mp3',
    'storm_rain': 'sounds/white_noise/storm_rain.mp3',
    'campfire': 'sounds/white_noise/campfire.mp3',
    'dawn_birds': 'sounds/white_noise/dawn_birds.mp3',
    'waterfall': 'sounds/white_noise/waterfall.mp3',
    'brook': 'sounds/white_noise/brook.mp3',
    'river': 'sounds/white_noise/river.mp3',
    'crickets': 'sounds/white_noise/crickets.mp3',
    'white_stream': 'sounds/white_noise/white_stream.mp3',
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

  static String labelFor(String sound) {
    return optionFor(sound)?.label ?? '无白噪音';
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
      label: track.label,
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
    if (sound.trim().isEmpty || sound == none) return const <String>[];
    if (sound.contains('+')) return const <String>[];
    final ids = sound
        .split('+')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return const <String>[];

    final valid = <String>[];
    for (final id in ids) {
      if (!assetMap.containsKey(id)) return const <String>[];
      if (!valid.contains(id)) valid.add(id);
    }
    return List<String>.unmodifiable(valid);
  }

  static List<String> assetsFor(String sound) {
    return trackIdsFor(
      sound,
    ).map((id) => assetMap[id]!).toList(growable: false);
  }
}
