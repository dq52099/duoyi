import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../core/app_brand.dart';
import '../services/account_local_data_cleaner.dart';

class FocusBackdropReward {
  final String id;
  final String name;
  final String description;
  final int cost;
  final IconData icon;
  final List<Color> colors;

  const FocusBackdropReward({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.icon,
    required this.colors,
  });
}

class AvatarFrameReward {
  final String id;
  final String name;
  final String description;
  final int cost;
  final IconData icon;
  final List<Color> colors;

  const AvatarFrameReward({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.icon,
    required this.colors,
  });
}

class CardSkinReward {
  final String id;
  final String name;
  final String description;
  final int cost;
  final IconData icon;
  final List<Color> colors;

  const CardSkinReward({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.icon,
    required this.colors,
  });
}

class ThemeProvider extends ChangeNotifier {
  static const _storageKey = 'active_brand';
  static const _switchCountKey = 'theme_switch_count';
  static const _unlockedBrandsKey = 'theme_unlocked_brands';
  static const _shopStateKey = 'theme_shop_state';
  static const premiumBrandCost = 120;
  static const defaultFocusBackdropId = 'classic_focus';
  static const defaultAvatarFrameId = 'simple_frame';
  static const defaultCardSkinId = 'plain_card';
  static const widgetFollowThemeId = 'follow_theme';
  static const widgetFollowCardSkinId = 'follow_card_skin';
  static const focusBackdropRewards = <FocusBackdropReward>[
    FocusBackdropReward(
      id: defaultFocusBackdropId,
      name: '经典专注',
      description: '简洁的番茄钟渐变背景',
      cost: 0,
      icon: Icons.timer_outlined,
      colors: [Color(0xFFE53935), Color(0xFFFFFFFF)],
    ),
    FocusBackdropReward(
      id: 'morning_focus',
      name: '晨光书桌',
      description: '适合清晨阅读和学习的暖色背景',
      cost: 80,
      icon: Icons.wb_sunny_outlined,
      colors: [Color(0xFFFFB74D), Color(0xFFFFF3E0)],
    ),
    FocusBackdropReward(
      id: 'forest_focus',
      name: '林间深呼吸',
      description: '适合长时间深度工作的自然绿色背景',
      cost: 100,
      icon: Icons.park_outlined,
      colors: [Color(0xFF2E7D32), Color(0xFFE8F5E9)],
    ),
    FocusBackdropReward(
      id: 'ocean_focus',
      name: '海岸静流',
      description: '适合复盘、写作和低压专注的蓝绿色背景',
      cost: 100,
      icon: Icons.waves_outlined,
      colors: [Color(0xFF00838F), Color(0xFFE0F7FA)],
    ),
    FocusBackdropReward(
      id: 'night_focus',
      name: '夜航模式',
      description: '适合夜间学习的低亮度深色背景',
      cost: 120,
      icon: Icons.dark_mode_outlined,
      colors: [Color(0xFF283593), Color(0xFF121826)],
    ),
  ];
  static const avatarFrameRewards = <AvatarFrameReward>[
    AvatarFrameReward(
      id: defaultAvatarFrameId,
      name: '简洁头像',
      description: '默认头像样式',
      cost: 0,
      icon: Icons.account_circle_outlined,
      colors: [Color(0xFF607D8B), Color(0xFFCFD8DC)],
    ),
    AvatarFrameReward(
      id: 'golden_frame',
      name: '金色勋章框',
      description: '适合成就达人展示的金色头像框',
      cost: 90,
      icon: Icons.workspace_premium_outlined,
      colors: [Color(0xFFFFB300), Color(0xFFFFF8E1)],
    ),
    AvatarFrameReward(
      id: 'forest_frame',
      name: '绿叶守护框',
      description: '适合习惯连续打卡的自然头像框',
      cost: 100,
      icon: Icons.eco_outlined,
      colors: [Color(0xFF2E7D32), Color(0xFFE8F5E9)],
    ),
    AvatarFrameReward(
      id: 'aurora_frame',
      name: '极光能量框',
      description: '适合高效专注周的流光头像框',
      cost: 120,
      icon: Icons.auto_awesome_outlined,
      colors: [Color(0xFF7E57C2), Color(0xFF26C6DA)],
    ),
  ];
  static const cardSkinRewards = <CardSkinReward>[
    CardSkinReward(
      id: defaultCardSkinId,
      name: '素净卡片',
      description: '默认信息卡片样式',
      cost: 0,
      icon: Icons.crop_square_outlined,
      colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5)],
    ),
    CardSkinReward(
      id: 'paper_card',
      name: '纸感计划卡',
      description: '适合日程和待办整理的柔和纸感',
      cost: 90,
      icon: Icons.sticky_note_2_outlined,
      colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
    ),
    CardSkinReward(
      id: 'mint_card',
      name: '薄荷清单卡',
      description: '适合习惯和专注记录的清爽卡片',
      cost: 100,
      icon: Icons.spa_outlined,
      colors: [Color(0xFFE0F2F1), Color(0xFFB2DFDB)],
    ),
    CardSkinReward(
      id: 'starlight_card',
      name: '星光玻璃卡',
      description: '适合夜间复盘的低亮度玻璃质感',
      cost: 120,
      icon: Icons.nightlight_round,
      colors: [Color(0xFF283593), Color(0xFF7E57C2)],
    ),
  ];

  AppBrand _brand = AppBrands.defaultBrand;
  int _switchCount = 0;
  final Set<String> _unlockedBrandIds = {AppBrands.defaultBrand.id};
  final Set<String> _unlockedFocusBackdropIds = {defaultFocusBackdropId};
  final Set<String> _unlockedAvatarFrameIds = {defaultAvatarFrameId};
  final Set<String> _unlockedCardSkinIds = {defaultCardSkinId};
  String _activeFocusBackdropId = defaultFocusBackdropId;
  String _activeAvatarFrameId = defaultAvatarFrameId;
  String _activeCardSkinId = defaultCardSkinId;
  String _activeWidgetBackgroundId = widgetFollowThemeId;
  String _activeWidgetCardSkinId = widgetFollowCardSkinId;
  String _shopStateUpdatedAt = '';
  bool _serverConfirmedChangePending = false;
  int _storageGeneration = 0;

  AppBrand get brand => _brand;
  List<AppBrand> get brands => AppBrands.all;
  int get themeSwitchCount => _switchCount;
  Set<String> get unlockedBrandIds => Set.unmodifiable(_unlockedBrandIds);
  Set<String> get unlockedFocusBackdropIds =>
      Set.unmodifiable(_unlockedFocusBackdropIds);
  List<FocusBackdropReward> get focusBackdrops => focusBackdropRewards;
  List<AvatarFrameReward> get avatarFrames => avatarFrameRewards;
  List<CardSkinReward> get cardSkins => cardSkinRewards;
  FocusBackdropReward get activeFocusBackdrop =>
      focusBackdropById(_activeFocusBackdropId);
  AvatarFrameReward get activeAvatarFrame =>
      avatarFrameById(_activeAvatarFrameId);
  CardSkinReward get activeCardSkin => cardSkinById(_activeCardSkinId);
  String get activeWidgetBackgroundId => _activeWidgetBackgroundId;
  String get activeWidgetCardSkinId => _activeWidgetCardSkinId;
  AppBrand get activeWidgetBackgroundBrand =>
      _activeWidgetBackgroundId == widgetFollowThemeId
      ? _brand
      : AppBrands.byId(_activeWidgetBackgroundId);
  CardSkinReward get activeWidgetCardSkin =>
      _activeWidgetCardSkinId == widgetFollowCardSkinId
      ? activeCardSkin
      : cardSkinById(_activeWidgetCardSkinId);
  String get shopStateUpdatedAt => _shopStateUpdatedAt;
  Map<String, dynamic> get shopStateSnapshot => _shopStateJson();

  bool consumeServerConfirmedChange() {
    final value = _serverConfirmedChangePending;
    _serverConfirmedChangePending = false;
    return value;
  }

  void resetLocalState() {
    _storageGeneration++;
    _brand = AppBrands.defaultBrand;
    _switchCount = 0;
    _unlockedBrandIds
      ..clear()
      ..add(AppBrands.defaultBrand.id);
    _unlockedFocusBackdropIds
      ..clear()
      ..add(defaultFocusBackdropId);
    _unlockedAvatarFrameIds
      ..clear()
      ..add(defaultAvatarFrameId);
    _unlockedCardSkinIds
      ..clear()
      ..add(defaultCardSkinId);
    _activeFocusBackdropId = defaultFocusBackdropId;
    _activeAvatarFrameId = defaultAvatarFrameId;
    _activeCardSkinId = defaultCardSkinId;
    _activeWidgetBackgroundId = widgetFollowThemeId;
    _activeWidgetCardSkinId = widgetFollowCardSkinId;
    _shopStateUpdatedAt = '';
    _serverConfirmedChangePending = false;
    notifyListeners();
  }

  bool isBrandUnlocked(String id) =>
      id == AppBrands.defaultBrand.id || _unlockedBrandIds.contains(id);

  int brandCost(String id) {
    if (id == AppBrands.defaultBrand.id) return 0;
    final index = brands.indexWhere((brand) => brand.id == id);
    return premiumBrandCost + (index < 0 ? 0 : index * 20);
  }

  bool isFocusBackdropUnlocked(String id) =>
      id == defaultFocusBackdropId || _unlockedFocusBackdropIds.contains(id);

  int focusBackdropCost(String id) => focusBackdropById(id).cost;

  bool isAvatarFrameUnlocked(String id) =>
      id == defaultAvatarFrameId || _unlockedAvatarFrameIds.contains(id);

  int avatarFrameCost(String id) => avatarFrameById(id).cost;

  bool isCardSkinUnlocked(String id) =>
      id == defaultCardSkinId || _unlockedCardSkinIds.contains(id);

  int cardSkinCost(String id) => cardSkinById(id).cost;

  FocusBackdropReward focusBackdropById(String id) {
    return focusBackdropRewards.firstWhere(
      (item) => item.id == id,
      orElse: () => focusBackdropRewards.first,
    );
  }

  AvatarFrameReward avatarFrameById(String id) {
    return avatarFrameRewards.firstWhere(
      (item) => item.id == id,
      orElse: () => avatarFrameRewards.first,
    );
  }

  CardSkinReward cardSkinById(String id) {
    return cardSkinRewards.firstWhere(
      (item) => item.id == id,
      orElse: () => cardSkinRewards.first,
    );
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    final shopState = _readShopState(prefs);
    if (shopState != null && _isIncomingShopStateOlder(shopState)) {
      debugPrint(
        '[theme-sync] skipped older stored shop state incoming='
        '${_shopStateUpdatedAtOf(shopState)} current=$_shopStateUpdatedAt',
      );
      return;
    }
    final changed = _applyShopStateMap(
      shopState,
      prefs: prefs,
      includeLegacyFallback: true,
    );
    if (changed) notifyListeners();
  }

  Future<void> applyShopStateFromServer(
    Map<dynamic, dynamic> state, {
    bool trusted = false,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    final incoming = Map<String, dynamic>.from(state);
    if (!trusted && _isIncomingShopStateOlder(incoming)) {
      debugPrint(
        '[theme-sync] skipped older shop state incoming='
        '${_shopStateUpdatedAtOf(incoming)} current=$_shopStateUpdatedAt',
      );
      return;
    }
    final changed = _applyShopStateMap(
      incoming,
      prefs: prefs,
      includeLegacyFallback: false,
    );
    if (!changed) return;
    await prefs.setString(_storageKey, _brand.id);
    await prefs.setStringList(
      _unlockedBrandsKey,
      _unlockedBrandIds.toList(growable: false),
    );
    await _saveShopState(prefs, touch: false);
    _serverConfirmedChangePending = true;
    notifyListeners();
  }

  bool _applyShopStateMap(
    Map<String, dynamic>? shopState, {
    required SharedPreferences prefs,
    required bool includeLegacyFallback,
  }) {
    final before = jsonEncode(_shopStateJson());
    final id =
        _stringFromAny(shopState, const ['activeBrand', 'active_brand']) ??
        (includeLegacyFallback ? prefs.getString(_storageKey) : null);
    _brand = AppBrands.byId(id);
    _switchCount =
        _intFromAny(shopState, const ['switchCount', 'switch_count']) ??
        (includeLegacyFallback ? prefs.getInt(_switchCountKey) : null) ??
        0;
    final updatedAt =
        shopState?['updatedAt']?.toString() ??
        shopState?['updated_at']?.toString();
    if (updatedAt != null && updatedAt.isNotEmpty) {
      _shopStateUpdatedAt = updatedAt;
    } else if (!includeLegacyFallback && _shopStateUpdatedAt.isEmpty) {
      _shopStateUpdatedAt = DateTime.now().toUtc().toIso8601String();
    }
    _unlockedBrandIds
      ..clear()
      ..add(AppBrands.defaultBrand.id)
      ..addAll(
        _stringListFromAny(shopState, const [
          'unlockedBrandIds',
          'unlocked_brand_ids',
        ]),
      )
      ..add(_brand.id);
    if (includeLegacyFallback) {
      _unlockedBrandIds.addAll(
        prefs.getStringList(_unlockedBrandsKey) ?? const <String>[],
      );
    }
    _unlockedFocusBackdropIds
      ..clear()
      ..add(defaultFocusBackdropId)
      ..addAll(
        _stringListFromAny(shopState, const [
          'unlockedFocusBackdropIds',
          'unlocked_focus_backdrop_ids',
        ]),
      );
    final activeBackdropId = _stringFromAny(shopState, const [
      'activeFocusBackdropId',
      'active_focus_backdrop_id',
    ]);
    _activeFocusBackdropId = isFocusBackdropUnlocked(activeBackdropId ?? '')
        ? activeBackdropId!
        : defaultFocusBackdropId;
    _unlockedAvatarFrameIds
      ..clear()
      ..add(defaultAvatarFrameId)
      ..addAll(
        _stringListFromAny(shopState, const [
          'unlockedAvatarFrameIds',
          'unlocked_avatar_frame_ids',
        ]),
      );
    final activeAvatarFrameId = _stringFromAny(shopState, const [
      'activeAvatarFrameId',
      'active_avatar_frame_id',
    ]);
    _activeAvatarFrameId = isAvatarFrameUnlocked(activeAvatarFrameId ?? '')
        ? activeAvatarFrameId!
        : defaultAvatarFrameId;
    _unlockedCardSkinIds
      ..clear()
      ..add(defaultCardSkinId)
      ..addAll(
        _stringListFromAny(shopState, const [
          'unlockedCardSkinIds',
          'unlocked_card_skin_ids',
        ]),
      );
    final activeCardSkinId = _stringFromAny(shopState, const [
      'activeCardSkinId',
      'active_card_skin_id',
    ]);
    _activeCardSkinId = isCardSkinUnlocked(activeCardSkinId ?? '')
        ? activeCardSkinId!
        : defaultCardSkinId;
    final activeWidgetBackgroundId = _stringFromAny(shopState, const [
      'activeWidgetBackgroundId',
      'active_widget_background_id',
      'widgetBackgroundBrandId',
      'widget_background_brand_id',
    ]);
    if (activeWidgetBackgroundId != null) {
      _activeWidgetBackgroundId = _normalizeWidgetBackgroundId(
        activeWidgetBackgroundId,
      );
    } else if (includeLegacyFallback) {
      _activeWidgetBackgroundId = widgetFollowThemeId;
    }
    final activeWidgetCardSkinId = _stringFromAny(shopState, const [
      'activeWidgetCardSkinId',
      'active_widget_card_skin_id',
      'widgetCardSkinId',
      'widget_card_skin_id',
    ]);
    if (activeWidgetCardSkinId != null) {
      _activeWidgetCardSkinId = _normalizeWidgetCardSkinId(
        activeWidgetCardSkinId,
      );
    } else if (includeLegacyFallback) {
      _activeWidgetCardSkinId = widgetFollowCardSkinId;
    }
    return before != jsonEncode(_shopStateJson());
  }

  Future<void> unlockBrand(String id) async {
    if (isBrandUnlocked(id)) return;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _unlockedBrandIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await prefs.setStringList(
      _unlockedBrandsKey,
      _unlockedBrandIds.toList(growable: false),
    );
    await _saveShopState(prefs);
    notifyListeners();
  }

  Future<void> unlockFocusBackdrop(String id) async {
    if (isFocusBackdropUnlocked(id)) return;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _unlockedFocusBackdropIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await _saveShopState(prefs);
    notifyListeners();
  }

  Future<bool> setFocusBackdrop(String id) async {
    if (!isFocusBackdropUnlocked(id)) return false;
    final nextId = focusBackdropById(id).id;
    if (_activeFocusBackdropId == nextId) return true;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _activeFocusBackdropId = nextId;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    await _saveShopState(prefs);
    notifyListeners();
    return true;
  }

  Future<void> unlockAvatarFrame(String id) async {
    if (isAvatarFrameUnlocked(id)) return;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _unlockedAvatarFrameIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await _saveShopState(prefs);
    notifyListeners();
  }

  Future<bool> setAvatarFrame(String id) async {
    if (!isAvatarFrameUnlocked(id)) return false;
    final nextId = avatarFrameById(id).id;
    if (_activeAvatarFrameId == nextId) return true;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _activeAvatarFrameId = nextId;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    await _saveShopState(prefs);
    notifyListeners();
    return true;
  }

  Future<void> unlockCardSkin(String id) async {
    if (isCardSkinUnlocked(id)) return;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _unlockedCardSkinIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await _saveShopState(prefs);
    notifyListeners();
  }

  Future<bool> setCardSkin(String id) async {
    if (!isCardSkinUnlocked(id)) return false;
    final nextId = cardSkinById(id).id;
    if (_activeCardSkinId == nextId) return true;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _activeCardSkinId = nextId;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    await _saveShopState(prefs);
    notifyListeners();
    return true;
  }

  Future<bool> setWidgetBackgroundBrand(String id) async {
    if (id != widgetFollowThemeId && !isBrandUnlocked(id)) {
      return false;
    }
    final nextId = _normalizeWidgetBackgroundId(id);
    if (_activeWidgetBackgroundId == nextId) return true;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _activeWidgetBackgroundId = nextId;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    await _saveShopState(prefs);
    notifyListeners();
    return true;
  }

  Future<bool> setWidgetCardSkin(String id) async {
    if (id != widgetFollowCardSkinId && !isCardSkinUnlocked(id)) {
      return false;
    }
    final nextId = _normalizeWidgetCardSkinId(id);
    if (_activeWidgetCardSkinId == nextId) return true;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _activeWidgetCardSkinId = nextId;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    await _saveShopState(prefs);
    notifyListeners();
    return true;
  }

  Future<bool> setBrand(String id) async {
    if (!isBrandUnlocked(id)) return false;
    final prev = _brand.id;
    _brand = AppBrands.byId(id);
    if (prev == _brand.id) return true;
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    await prefs.setString(_storageKey, _brand.id);
    _switchCount++;
    await prefs.setInt(_switchCountKey, _switchCount);
    DomainEventBus.instance.publish(
      DomainEvent(
        type: DomainEventType.themeSwitched,
        objectId: _brand.id,
        metadata: {'count': _switchCount},
      ),
    );
    await _saveShopState(prefs);
    notifyListeners();
    return true;
  }

  bool _isIncomingShopStateOlder(Map<String, dynamic> incoming) {
    final incomingUpdatedAt = _shopStateUpdatedAtOf(incoming);
    if (_shopStateUpdatedAt.isEmpty) return false;
    if (incomingUpdatedAt.isEmpty) return true;
    final incomingTime = DateTime.tryParse(incomingUpdatedAt);
    final currentTime = DateTime.tryParse(_shopStateUpdatedAt);
    if (incomingTime != null && currentTime != null) {
      return incomingTime.toUtc().isBefore(currentTime.toUtc());
    }
    return incomingUpdatedAt.compareTo(_shopStateUpdatedAt) < 0;
  }

  String _shopStateUpdatedAtOf(Map<dynamic, dynamic>? state) {
    return state?['updatedAt']?.toString() ??
        state?['updated_at']?.toString() ??
        '';
  }

  Map<String, dynamic>? _readShopState(SharedPreferences prefs) {
    final raw = prefs.getString(_shopStateKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  String? _stringFromAny(Map<String, dynamic>? state, List<String> keys) {
    if (state == null) return null;
    for (final key in keys) {
      if (!state.containsKey(key)) continue;
      final value = state[key];
      if (value == null) continue;
      final text = value.toString();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  int? _intFromAny(Map<String, dynamic>? state, List<String> keys) {
    if (state == null) return null;
    for (final key in keys) {
      if (!state.containsKey(key)) continue;
      final value = state[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Iterable<String> _stringListFromAny(
    Map<String, dynamic>? state,
    List<String> keys,
  ) {
    if (state == null) return const <String>[];
    Object? raw;
    for (final key in keys) {
      if (!state.containsKey(key)) continue;
      raw = state[key];
      break;
    }
    if (raw is! List) return const <String>[];
    return raw.map((id) => id.toString());
  }

  String _normalizeWidgetBackgroundId(String id) {
    if (id == widgetFollowThemeId) return widgetFollowThemeId;
    final brand = AppBrands.byId(id);
    return isBrandUnlocked(brand.id) ? brand.id : widgetFollowThemeId;
  }

  String _normalizeWidgetCardSkinId(String id) {
    if (id == widgetFollowCardSkinId) return widgetFollowCardSkinId;
    final skin = cardSkinById(id);
    return isCardSkinUnlocked(skin.id) ? skin.id : widgetFollowCardSkinId;
  }

  Future<void> _saveShopState(
    SharedPreferences prefs, {
    bool touch = true,
  }) async {
    if (touch || _shopStateUpdatedAt.isEmpty) {
      _shopStateUpdatedAt = DateTime.now().toUtc().toIso8601String();
    }
    await prefs.setString(_shopStateKey, jsonEncode(_shopStateJson()));
  }

  Map<String, dynamic> _shopStateJson() => {
    'activeBrand': _brand.id,
    'switchCount': _switchCount,
    'unlockedBrandIds': _unlockedBrandIds.toList(growable: false),
    'activeFocusBackdropId': _activeFocusBackdropId,
    'unlockedFocusBackdropIds': _unlockedFocusBackdropIds.toList(
      growable: false,
    ),
    'activeAvatarFrameId': _activeAvatarFrameId,
    'unlockedAvatarFrameIds': _unlockedAvatarFrameIds.toList(growable: false),
    'activeCardSkinId': _activeCardSkinId,
    'unlockedCardSkinIds': _unlockedCardSkinIds.toList(growable: false),
    'activeWidgetBackgroundId': _activeWidgetBackgroundId,
    'activeWidgetCardSkinId': _activeWidgetCardSkinId,
    if (_shopStateUpdatedAt.isNotEmpty) 'updatedAt': _shopStateUpdatedAt,
  };
}
