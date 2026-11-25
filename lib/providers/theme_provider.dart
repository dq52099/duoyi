import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/domain_event_bus.dart';
import '../core/app_brand.dart';
import '../core/account_preference_writes.dart';
import '../services/account_local_data_cleaner.dart';
import 'achievement_provider.dart';

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
  Future<void> _shopWriteTail = Future<void>.value();

  Future<T> _enqueueShopChange<T>(
    Future<T> Function(
      SharedPreferences preferences,
      AccountPreferenceTransaction transaction,
    )
    change, {
    required T Function() canceledResult,
    void Function()? afterCommit,
    bool Function()? additionalIsCurrent,
  }) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    return AccountPreferenceWrites.runResult<T>((token) {
      bool isCurrent() =>
          _isCurrentShopOperation(generation, accountGeneration) &&
          token.isCurrent &&
          (additionalIsCurrent?.call() ?? true);
      final write = _shopWriteTail.then<T>((_) async {
        if (!isCurrent()) return canceledResult();
        final preferences = await SharedPreferences.getInstance();
        if (!isCurrent()) return canceledResult();
        final restoreState = _captureShopState();
        final transaction = AccountPreferenceTransaction(
          preferences,
          isCurrent,
        );
        try {
          final result = await change(preferences, transaction);
          final didChange = transaction.changedKeys.isNotEmpty;
          transaction.commit();
          if (didChange) {
            afterCommit?.call();
            if (isCurrent()) notifyListeners();
          }
          return result;
        } on AccountPreferenceWriteCanceled {
          await transaction.rollback(canceledBeforeCleanup: true);
          if (generation == _storageGeneration) restoreState();
          return canceledResult();
        } catch (_) {
          if (transaction.isCommitted) rethrow;
          await transaction.rollback(canceledBeforeCleanup: true);
          if (generation == _storageGeneration) {
            restoreState();
            // Preserve actual disk state if the device cannot restore a key.
            await _loadFromStorageNow();
          }
          rethrow;
        }
      });
      _shopWriteTail = write.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      return write;
    }, canceledResult: canceledResult);
  }

  void Function() _captureShopState() {
    final savedBrand = _brand;
    final savedSwitchCount = _switchCount;
    final savedUnlockedBrandIds = Set<String>.of(_unlockedBrandIds);
    final savedUnlockedFocusBackdropIds = Set<String>.of(
      _unlockedFocusBackdropIds,
    );
    final savedUnlockedAvatarFrameIds = Set<String>.of(_unlockedAvatarFrameIds);
    final savedUnlockedCardSkinIds = Set<String>.of(_unlockedCardSkinIds);
    final savedActiveFocusBackdropId = _activeFocusBackdropId;
    final savedActiveAvatarFrameId = _activeAvatarFrameId;
    final savedActiveCardSkinId = _activeCardSkinId;
    final savedActiveWidgetBackgroundId = _activeWidgetBackgroundId;
    final savedActiveWidgetCardSkinId = _activeWidgetCardSkinId;
    final savedShopStateUpdatedAt = _shopStateUpdatedAt;
    final savedServerConfirmedChangePending = _serverConfirmedChangePending;
    return () {
      _brand = savedBrand;
      _switchCount = savedSwitchCount;
      _unlockedBrandIds
        ..clear()
        ..addAll(savedUnlockedBrandIds);
      _unlockedFocusBackdropIds
        ..clear()
        ..addAll(savedUnlockedFocusBackdropIds);
      _unlockedAvatarFrameIds
        ..clear()
        ..addAll(savedUnlockedAvatarFrameIds);
      _unlockedCardSkinIds
        ..clear()
        ..addAll(savedUnlockedCardSkinIds);
      _activeFocusBackdropId = savedActiveFocusBackdropId;
      _activeAvatarFrameId = savedActiveAvatarFrameId;
      _activeCardSkinId = savedActiveCardSkinId;
      _activeWidgetBackgroundId = savedActiveWidgetBackgroundId;
      _activeWidgetCardSkinId = savedActiveWidgetCardSkinId;
      _shopStateUpdatedAt = savedShopStateUpdatedAt;
      _serverConfirmedChangePending = savedServerConfirmedChangePending;
    };
  }

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

  Future<void> loadFromStorage() => _enqueueShopChange<void>(
    (_, _) => _loadFromStorageNow(),
    canceledResult: () {},
  );

  Future<void> _loadFromStorageNow() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
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

  bool _isCurrentShopOperation(int generation, int accountGeneration) =>
      generation == _storageGeneration &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(accountGeneration);

  /// Saves a guest debit, unlock and selection in one shared transaction.
  Future<bool> redeemGuestItem({
    required AchievementProvider rewards,
    required String itemType,
    required String itemId,
    required String title,
    required String reason,
    required bool Function() isAuthorized,
  }) {
    // Capture before waiting on the reward queue, never borrow a new account.
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    bool authorized() =>
        _isCurrentShopOperation(generation, accountGeneration) &&
        isAuthorized();
    return rewards.runCoinPurchase((purchase) {
      var switchedBrand = false;
      return _enqueueShopChange<bool>(
        (prefs, transaction) async {
          if (!authorized()) throw const AccountPreferenceWriteCanceled();
          purchase.ensureCurrent();
          final (unlockKey, activeKey, cost, unlocked) = switch (itemType) {
            'brand' when brands.any((item) => item.id == itemId) => (
              'unlockedBrandIds',
              'activeBrand',
              brandCost(itemId),
              isBrandUnlocked(itemId),
            ),
            'focus_backdrop'
                when focusBackdrops.any((item) => item.id == itemId) =>
              (
                'unlockedFocusBackdropIds',
                'activeFocusBackdropId',
                focusBackdropCost(itemId),
                isFocusBackdropUnlocked(itemId),
              ),
            'avatar_frame' when avatarFrames.any((item) => item.id == itemId) =>
              (
                'unlockedAvatarFrameIds',
                'activeAvatarFrameId',
                avatarFrameCost(itemId),
                isAvatarFrameUnlocked(itemId),
              ),
            'card_skin' when cardSkins.any((item) => item.id == itemId) => (
              'unlockedCardSkinIds',
              'activeCardSkinId',
              cardSkinCost(itemId),
              isCardSkinUnlocked(itemId),
            ),
            _ => throw ArgumentError('Unknown theme shop item'),
          };
          // This check runs inside both queues, so repeated requests charge once.
          if (!unlocked &&
              !await purchase.debit(
                transaction,
                coins: cost,
                title: title,
                reason: reason,
              )) {
            return false;
          }
          purchase.ensureCurrent();
          if (unlocked && _shopStateJson()[activeKey] == itemId) return true;
          final next = _shopStateJson();
          next[unlockKey] = {
            ...List<String>.from(next[unlockKey] as List),
            itemId,
          }.toList();
          next[activeKey] = itemId;
          next['updatedAt'] = DateTime.now().toUtc().toIso8601String();
          if (itemType == 'brand') {
            switchedBrand = _brand.id != itemId;
            if (switchedBrand) next['switchCount'] = _switchCount + 1;
            await transaction.setString(_storageKey, itemId);
            purchase.ensureCurrent();
            await transaction.setStringList(
              _unlockedBrandsKey,
              List<String>.from(next[unlockKey] as List),
            );
            purchase.ensureCurrent();
            await transaction.setInt(
              _switchCountKey,
              next['switchCount'] as int,
            );
            purchase.ensureCurrent();
          }
          await transaction.setString(_shopStateKey, jsonEncode(next));
          purchase.ensureCurrent();
          // Publish the new selection only once all platform writes succeeded.
          _applyShopStateMap(next, prefs: prefs, includeLegacyFallback: false);
          return true;
        },
        canceledResult: () => false,
        additionalIsCurrent: purchase.isCurrent,
        afterCommit: () {
          if (!switchedBrand) return;
          DomainEventBus.instance.publish(
            DomainEvent(
              type: DomainEventType.themeSwitched,
              objectId: _brand.id,
              metadata: {'count': _switchCount},
            ),
          );
        },
      );
    }, isAuthorized: authorized);
  }

  Future<void> applyShopStateFromServer(
    Map<dynamic, dynamic> state, {
    bool trusted = false,
  }) {
    return _enqueueShopChange<void>((preferences, transaction) async {
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
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
      final restoreCommittedState = _captureShopState();
      final changed = _applyShopStateMap(
        incoming,
        prefs: preferences,
        includeLegacyFallback: false,
      );
      if (!changed) {
        restoreCommittedState();
        return;
      }
      final candidateState = _shopStateJson();
      final candidateBrandId = _brand.id;
      final candidateUnlockedBrandIds = _unlockedBrandIds.toList(
        growable: false,
      );
      restoreCommittedState();

      await transaction.setString(_storageKey, candidateBrandId);
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      await transaction.setStringList(
        _unlockedBrandsKey,
        candidateUnlockedBrandIds,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
        touch: false,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      _applyShopStateMap(
        candidateState,
        prefs: preferences,
        includeLegacyFallback: false,
      );
      _shopStateUpdatedAt = nextUpdatedAt;
      _serverConfirmedChangePending = true;
    }, canceledResult: () {});
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
    _activeWidgetBackgroundId = _normalizeWidgetBackgroundId(
      activeWidgetBackgroundId ??
          (includeLegacyFallback
              ? widgetFollowThemeId
              : _activeWidgetBackgroundId),
    );
    final activeWidgetCardSkinId = _stringFromAny(shopState, const [
      'activeWidgetCardSkinId',
      'active_widget_card_skin_id',
      'widgetCardSkinId',
      'widget_card_skin_id',
    ]);
    _activeWidgetCardSkinId = _normalizeWidgetCardSkinId(
      activeWidgetCardSkinId ??
          (includeLegacyFallback
              ? widgetFollowCardSkinId
              : _activeWidgetCardSkinId),
    );
    return before != jsonEncode(_shopStateJson());
  }

  Future<void> unlockBrand(String id) {
    return _enqueueShopChange<void>((preferences, transaction) async {
      if (isBrandUnlocked(id)) return;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return;
      }
      final nextUnlockedBrandIds = [..._unlockedBrandIds, id];
      await transaction.setStringList(_unlockedBrandsKey, nextUnlockedBrandIds);
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      final candidateState = _shopStateJson()
        ..['unlockedBrandIds'] = nextUnlockedBrandIds;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      _unlockedBrandIds.add(id);
      _shopStateUpdatedAt = nextUpdatedAt;
    }, canceledResult: () {});
  }

  Future<void> unlockFocusBackdrop(String id) {
    return _enqueueShopChange<void>((preferences, transaction) async {
      if (isFocusBackdropUnlocked(id)) return;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return;
      }
      final nextUnlocked = [..._unlockedFocusBackdropIds, id];
      final candidateState = _shopStateJson()
        ..['unlockedFocusBackdropIds'] = nextUnlocked;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      _unlockedFocusBackdropIds.add(id);
      _shopStateUpdatedAt = nextUpdatedAt;
    }, canceledResult: () {});
  }

  Future<bool> setFocusBackdrop(String id) {
    return _enqueueShopChange<bool>((preferences, transaction) async {
      if (!isFocusBackdropUnlocked(id)) return false;
      final nextId = focusBackdropById(id).id;
      if (_activeFocusBackdropId == nextId) return true;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return false;
      }
      final candidateState = _shopStateJson()
        ..['activeFocusBackdropId'] = nextId;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return false;
      _activeFocusBackdropId = nextId;
      _shopStateUpdatedAt = nextUpdatedAt;
      return true;
    }, canceledResult: () => false);
  }

  Future<void> unlockAvatarFrame(String id) {
    return _enqueueShopChange<void>((preferences, transaction) async {
      if (isAvatarFrameUnlocked(id)) return;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return;
      }
      final nextUnlocked = [..._unlockedAvatarFrameIds, id];
      final candidateState = _shopStateJson()
        ..['unlockedAvatarFrameIds'] = nextUnlocked;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      _unlockedAvatarFrameIds.add(id);
      _shopStateUpdatedAt = nextUpdatedAt;
    }, canceledResult: () {});
  }

  Future<bool> setAvatarFrame(String id) {
    return _enqueueShopChange<bool>((preferences, transaction) async {
      if (!isAvatarFrameUnlocked(id)) return false;
      final nextId = avatarFrameById(id).id;
      if (_activeAvatarFrameId == nextId) return true;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return false;
      }
      final candidateState = _shopStateJson()..['activeAvatarFrameId'] = nextId;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return false;
      _activeAvatarFrameId = nextId;
      _shopStateUpdatedAt = nextUpdatedAt;
      return true;
    }, canceledResult: () => false);
  }

  Future<void> unlockCardSkin(String id) {
    return _enqueueShopChange<void>((preferences, transaction) async {
      if (isCardSkinUnlocked(id)) return;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return;
      }
      final nextUnlocked = [..._unlockedCardSkinIds, id];
      final candidateState = _shopStateJson()
        ..['unlockedCardSkinIds'] = nextUnlocked;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return;
      _unlockedCardSkinIds.add(id);
      _shopStateUpdatedAt = nextUpdatedAt;
    }, canceledResult: () {});
  }

  Future<bool> setCardSkin(String id) {
    return _enqueueShopChange<bool>((preferences, transaction) async {
      if (!isCardSkinUnlocked(id)) return false;
      final nextId = cardSkinById(id).id;
      if (_activeCardSkinId == nextId) return true;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return false;
      }
      final candidateState = _shopStateJson()..['activeCardSkinId'] = nextId;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return false;
      _activeCardSkinId = nextId;
      _shopStateUpdatedAt = nextUpdatedAt;
      return true;
    }, canceledResult: () => false);
  }

  Future<bool> setWidgetBackgroundBrand(String id) {
    return _enqueueShopChange<bool>((preferences, transaction) async {
      if (id != widgetFollowThemeId && !isBrandUnlocked(id)) {
        return false;
      }
      final nextId = _normalizeWidgetBackgroundId(id);
      if (_activeWidgetBackgroundId == nextId) return true;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return false;
      }
      final candidateState = _shopStateJson()
        ..['activeWidgetBackgroundId'] = nextId;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return false;
      _activeWidgetBackgroundId = nextId;
      _shopStateUpdatedAt = nextUpdatedAt;
      return true;
    }, canceledResult: () => false);
  }

  Future<bool> setWidgetCardSkin(String id) {
    return _enqueueShopChange<bool>((preferences, transaction) async {
      if (id != widgetFollowCardSkinId && !isCardSkinUnlocked(id)) {
        return false;
      }
      final nextId = _normalizeWidgetCardSkinId(id);
      if (_activeWidgetCardSkinId == nextId) return true;
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      if (generation != _storageGeneration ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            accountGeneration,
          )) {
        return false;
      }
      final candidateState = _shopStateJson()
        ..['activeWidgetCardSkinId'] = nextId;
      final nextUpdatedAt = await _saveShopState(
        transaction,
        candidateState: candidateState,
      );
      if (!_isCurrentShopOperation(generation, accountGeneration)) return false;
      _activeWidgetCardSkinId = nextId;
      _shopStateUpdatedAt = nextUpdatedAt;
      return true;
    }, canceledResult: () => false);
  }

  Future<bool> setBrand(String id) {
    return _enqueueShopChange<bool>(
      (preferences, transaction) async {
        if (!isBrandUnlocked(id)) return false;
        final nextBrand = AppBrands.byId(id);
        if (_brand.id == nextBrand.id) return true;
        final generation = _storageGeneration;
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        if (generation != _storageGeneration ||
            !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              accountGeneration,
            )) {
          return false;
        }
        final nextSwitchCount = _switchCount + 1;
        await transaction.setString(_storageKey, nextBrand.id);
        if (!_isCurrentShopOperation(generation, accountGeneration)) {
          return false;
        }
        await transaction.setInt(_switchCountKey, nextSwitchCount);
        if (!_isCurrentShopOperation(generation, accountGeneration)) {
          return false;
        }
        final candidateState = _shopStateJson()
          ..['activeBrand'] = nextBrand.id
          ..['switchCount'] = nextSwitchCount;
        final nextUpdatedAt = await _saveShopState(
          transaction,
          candidateState: candidateState,
        );
        if (!_isCurrentShopOperation(generation, accountGeneration)) {
          return false;
        }
        _brand = nextBrand;
        _switchCount = nextSwitchCount;
        _shopStateUpdatedAt = nextUpdatedAt;
        return true;
      },
      canceledResult: () => false,
      afterCommit: () {
        DomainEventBus.instance.publish(
          DomainEvent(
            type: DomainEventType.themeSwitched,
            objectId: _brand.id,
            metadata: {'count': _switchCount},
          ),
        );
      },
    );
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
    if (!brands.any((brand) => brand.id == id)) return widgetFollowThemeId;
    final brand = AppBrands.byId(id);
    return isBrandUnlocked(brand.id) ? brand.id : widgetFollowThemeId;
  }

  String _normalizeWidgetCardSkinId(String id) {
    if (id == widgetFollowCardSkinId) return widgetFollowCardSkinId;
    if (!cardSkins.any((skin) => skin.id == id)) return widgetFollowCardSkinId;
    final skin = cardSkinById(id);
    return isCardSkinUnlocked(skin.id) ? skin.id : widgetFollowCardSkinId;
  }

  Future<String> _saveShopState(
    AccountPreferenceTransaction preferences, {
    Map<String, dynamic>? candidateState,
    bool touch = true,
  }) async {
    final state = candidateState ?? _shopStateJson();
    final candidateUpdatedAt = _shopStateUpdatedAtOf(candidateState);
    var updatedAt = candidateUpdatedAt.isNotEmpty
        ? candidateUpdatedAt
        : _shopStateUpdatedAt;
    if (touch || updatedAt.isEmpty) {
      updatedAt = DateTime.now().toUtc().toIso8601String();
      state['updatedAt'] = updatedAt;
    } else {
      state['updatedAt'] = updatedAt;
    }
    await preferences.setString(_shopStateKey, jsonEncode(state));
    return updatedAt;
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
