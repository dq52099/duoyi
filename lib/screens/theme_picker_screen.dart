import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/account_preference_writes.dart';
import '../core/data_settings_ui_copy.dart';
import '../core/desktop_tokens.dart';
import '../core/i18n.dart';
import '../providers/achievement_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

class ThemePickerScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const ThemePickerScreen({super.key});

  @override
  State<ThemePickerScreen> createState() => _ThemePickerScreenState();
}

class _ThemePickerScreenState extends State<ThemePickerScreen> {
  bool _shopBusy = false;

  Color _accentColor(AppBrand brand) {
    return brand.theme.colorScheme.primary;
  }

  Color _resolveReadableForeground({
    required Iterable<Color> backgrounds,
    required Color preferred,
    double minContrast = 4.5,
  }) {
    if (backgrounds.isEmpty) {
      return preferred;
    }
    final allMeetPreferred = backgrounds.every((bg) {
      final effective = Color.alphaBlend(preferred, bg);
      return appContrastRatio(bg, effective) >= minContrast;
    });
    if (allMeetPreferred) {
      return preferred;
    }

    const dark = Color(0xFF111827);
    const white = Colors.white;

    double minRatio(Color fg) {
      var min = double.infinity;
      for (final bg in backgrounds) {
        final r = appContrastRatio(bg, fg);
        if (r < min) min = r;
      }
      return min;
    }

    final darkMin = minRatio(dark);
    final whiteMin = minRatio(white);

    if (darkMin >= minContrast && whiteMin >= minContrast) {
      return darkMin >= whiteMin ? dark : white;
    }
    if (darkMin >= minContrast) {
      return dark;
    }
    if (whiteMin >= minContrast) {
      return white;
    }
    if (darkMin >= whiteMin) {
      return darkMin >= minContrast ? dark : Colors.black;
    }
    return white;
  }

  Color _balanceForegroundColor({
    required Iterable<Color> surfaces,
    required ColorScheme cs,
  }) {
    return _resolveReadableForeground(
      backgrounds: surfaces,
      preferred: cs.primary,
      minContrast: 4.5,
    );
  }

  Color _priceForegroundColor({
    required Iterable<Color> surfaces,
    required Color accent,
  }) {
    final chipBackgrounds = surfaces.map(
      (s) => Color.alphaBlend(accent.withValues(alpha: 0.12), s),
    );
    return _resolveReadableForeground(
      backgrounds: chipBackgrounds,
      preferred: accent,
      minContrast: 4.5,
    );
  }

  Color _descriptionForegroundColor({
    required Iterable<Color> surfaces,
    required ColorScheme cs,
    required bool isKnownSurface,
    required bool isDark,
  }) {
    if (!isKnownSurface || isDark) {
      return cs.onSurface.withValues(alpha: 0.66);
    }
    return _resolveReadableForeground(
      backgrounds: surfaces,
      preferred: cs.onSurface,
      minContrast: 4.5,
    );
  }

  Color _widgetLabelForegroundColor({
    required Iterable<Color> surfaces,
    required ColorScheme cs,
    required bool isKnownSurface,
    required bool isDark,
  }) {
    if (!isKnownSurface || isDark) {
      return cs.onSurface.withValues(alpha: 0.72);
    }
    return _resolveReadableForeground(
      backgrounds: surfaces,
      preferred: cs.onSurface,
      minContrast: 4.5,
    );
  }

  Color _inactiveOptionIconColor({
    required Iterable<Color> surfaces,
    required ColorScheme cs,
    required bool isKnownSurface,
    required bool isDark,
  }) {
    if (!isKnownSurface || isDark) {
      return cs.onSurface.withValues(alpha: 0.36);
    }
    return _resolveReadableForeground(
      backgrounds: surfaces,
      preferred: cs.onSurface,
      minContrast: 3.0,
    );
  }

  Color _syncNoticeSubtitleForegroundColor({
    required BuildContext context,
    required Color routeBackground,
    required ColorScheme cs,
    required bool isKnownSurface,
    required bool isDark,
  }) {
    if (!isKnownSurface || isDark) {
      return appSecondaryDescriptionColor(context);
    }
    return _resolveReadableForeground(
      backgrounds: [routeBackground],
      preferred: cs.onSurface,
      minContrast: 4.5,
    );
  }

  List<Color> _activeOptionSurfaces({
    required Color routeBackground,
    required Color accent,
    required ColorScheme cs,
    double gradientStartAlpha = 0.12,
  }) {
    final activeStart = Color.alphaBlend(
      accent.withValues(alpha: gradientStartAlpha),
      routeBackground,
    );
    final activeEnd = Color.alphaBlend(cs.surface, routeBackground);
    return [activeStart, Color.lerp(activeStart, activeEnd, 0.5)!, activeEnd];
  }

  Color _activeOptionCheckmarkColor({
    required Color routeBackground,
    required Color accent,
    required ColorScheme cs,
    double gradientStartAlpha = 0.12,
  }) {
    final surfaces = _activeOptionSurfaces(
      routeBackground: routeBackground,
      accent: accent,
      cs: cs,
      gradientStartAlpha: gradientStartAlpha,
    );

    final accentMeets = surfaces.every((bg) {
      final eff = Color.alphaBlend(accent, bg);
      return appContrastRatio(bg, eff) >= 3.0;
    });
    if (accentMeets) return accent;

    final primaryMeets = surfaces.every((bg) {
      final eff = Color.alphaBlend(cs.primary, bg);
      return appContrastRatio(bg, eff) >= 3.0;
    });
    if (primaryMeets) return cs.primary;

    return _resolveReadableForeground(
      backgrounds: surfaces,
      preferred: cs.primary,
      minContrast: 3.0,
    );
  }

  Color _cardSkinActiveCheckmarkColor({
    required Color routeBackground,
    required Color accent,
    required ColorScheme cs,
  }) {
    return _activeOptionCheckmarkColor(
      routeBackground: routeBackground,
      accent: accent,
      cs: cs,
      gradientStartAlpha: 0.18,
    );
  }

  String _styleDescription(BrandStyle style) {
    switch (style) {
      case BrandStyle.defaultBrand:
        return I18n.tr('theme.style.default.description');
      case BrandStyle.re0:
        return I18n.tr('theme.style.re0.description');
      case BrandStyle.genshin:
        return I18n.tr('theme.style.genshin.description');
      case BrandStyle.starRail:
        return I18n.tr('theme.style.star_rail.description');
      case BrandStyle.wuthering:
        return I18n.tr('theme.style.wuthering.description');
      case BrandStyle.zzz:
        return I18n.tr('theme.style.zzz.description');
      case BrandStyle.yanyun:
        return I18n.tr('theme.style.yanyun.description');
      case BrandStyle.botw:
        return I18n.tr('theme.style.botw.description');
      case BrandStyle.liquidGlass:
        return I18n.tr('theme.style.liquid_glass.description');
    }
  }

  String _styleName(AppBrand brand) => brand.localizedName;

  Widget _swatch(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  int _visibleCoinBalance(
    AuthProvider authProvider,
    AchievementProvider achievementProvider,
  ) {
    return authProvider.state.isLoggedIn
        ? authProvider.state.coinBalance
        : achievementProvider.coinBalance;
  }

  bool Function() _accountOperationGuard(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final theme = context.read<ThemeProvider>();
    final rewards = context.read<AchievementProvider>();
    final rewardGeneration = rewards.storageGeneration;
    final sessionGeneration = auth.sessionGeneration;
    final route = ModalRoute.of(context);
    final writeGeneration = AccountPreferenceWrites.generation;
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final token = auth.state.token;
    final userId = auth.state.userId;
    return () =>
        context.mounted &&
        (route == null || (route.isActive && route.isCurrent)) &&
        !AccountPreferenceWrites.isBoundaryActive &&
        AccountPreferenceWrites.generation == writeGeneration &&
        identical(context.read<AuthProvider>(), auth) &&
        identical(context.read<ThemeProvider>(), theme) &&
        identical(context.read<AchievementProvider>(), rewards) &&
        rewards.storageGeneration == rewardGeneration &&
        auth.sessionGeneration == sessionGeneration &&
        !auth.isAccountTransitionInProgress &&
        !auth.isLocalAccountDataBlocked &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
        auth.state.token == token &&
        auth.state.userId == userId;
  }

  List<Widget> _buildOptionGridRows(List<Widget> cards, bool useTwoColumns) {
    if (!useTwoColumns) return cards;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final first = cards[i];
      final second = i + 1 < cards.length ? cards[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second ?? const SizedBox.shrink()),
          ],
        ),
      );
    }
    return rows;
  }

  List<Widget> _wrapDesktopWidth(List<Widget> children) {
    return children
        .map(
          (child) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesktopTokens.reportMaxContentWidth,
              ),
              child: child,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> _applyThemeShopItem(
    BuildContext context, {
    required ThemeProvider themeProvider,
    required AchievementProvider achievementProvider,
    required String itemType,
    required String itemId,
    required String title,
    required int cost,
    required bool isUnlocked,
    required Future<void> Function(bool Function() isCurrent) applyLocal,
  }) async {
    if (_shopBusy || !mounted || !_accountOperationGuard(context)()) {
      return false;
    }
    setState(() => _shopBusy = true);
    try {
      return await _applyThemeShopItemNow(
        context,
        themeProvider: themeProvider,
        achievementProvider: achievementProvider,
        itemType: itemType,
        itemId: itemId,
        title: title,
        cost: cost,
        isUnlocked: isUnlocked,
        applyLocal: applyLocal,
      );
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
  }

  Future<bool> _applyThemeShopItemNow(
    BuildContext context, {
    required ThemeProvider themeProvider,
    required AchievementProvider achievementProvider,
    required String itemType,
    required String itemId,
    required String title,
    required int cost,
    required bool isUnlocked,
    required Future<void> Function(bool Function() isCurrent) applyLocal,
  }) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return false;
    final authProvider = context.read<AuthProvider>();
    if (authProvider.state.isLoggedIn) {
      try {
        final res = await authProvider.applyThemeShopItem(
          itemType: itemType,
          itemId: itemId,
          title: title,
        );
        if (!isCurrent()) return false;
        final themeState = _nestedMapValue(res, const [
          'theme_shop_state',
          'themeShopState',
          'theme',
        ]);
        final rewards = _nestedMapValue(res, const [
          'virtual_rewards',
          'virtualRewards',
          'rewards',
        ]);
        if (themeState is Map) {
          if (!isCurrent()) return false;
          await themeProvider.applyShopStateFromServer(
            themeState,
            trusted: true,
          );
          if (!isCurrent()) return false;
        }
        if (rewards is Map) {
          if (!isCurrent()) return false;
          await achievementProvider.applyRewardsSnapshot(rewards);
          if (!isCurrent()) return false;
        }
        if (themeState is! Map) {
          if (!isCurrent()) return false;
          await applyLocal(isCurrent);
        }
        return isCurrent();
      } catch (e) {
        if (!context.mounted || !isCurrent()) return false;
        _showDynamicFeedback(
          context,
          () => userVisibleApiError(
            e,
            fallbackMessage: DataSettingsUiCopy.themeSaveFailed,
          ),
        );
        return false;
      }
    }

    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final sessionGeneration = authProvider.sessionGeneration;
    final token = authProvider.state.token;
    final userId = authProvider.state.userId;
    // Saving belongs to the captured account, even if this view is dismissed.
    bool purchaseAuthorized() =>
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        ) &&
        authProvider.sessionGeneration == sessionGeneration &&
        !authProvider.state.isLoggedIn &&
        !authProvider.isAccountTransitionInProgress &&
        !authProvider.isLocalAccountDataBlocked &&
        authProvider.state.token == token &&
        authProvider.state.userId == userId;
    try {
      final ok = await themeProvider.redeemGuestItem(
        rewards: achievementProvider,
        itemType: itemType,
        itemId: itemId,
        title: title,
        reason: DataSettingsUiCopy.rewardShopReason,
        isAuthorized: purchaseAuthorized,
      );
      if (!context.mounted || !isCurrent()) return false;
      if (!ok) {
        final isInsufficient = achievementProvider.coinBalance < cost;
        final missingCoins = cost - achievementProvider.coinBalance;
        _showDynamicFeedback(
          context,
          () => isInsufficient
              ? DataSettingsUiCopy.insufficientCoins(missingCoins)
              : DataSettingsUiCopy.themeSaveFailed,
        );
        return false;
      }
      return ok;
    } catch (_) {
      if (!context.mounted || !isCurrent()) return false;
      _showDynamicFeedback(context, () => DataSettingsUiCopy.themeSaveFailed);
      return false;
    }
  }

  Object? _nestedMapValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data[key] != null) return data[key];
    }
    for (final wrapperKey in const ['data', 'result', 'payload']) {
      final wrapper = data[wrapperKey];
      if (wrapper is Map) {
        final nested = _nestedMapValue(
          Map<String, dynamic>.from(wrapper),
          keys,
        );
        if (nested != null) return nested;
      }
    }
    final user = data['user'];
    if (user is Map) {
      return _nestedMapValue(Map<String, dynamic>.from(user), keys);
    }
    return null;
  }

  Future<void> _handleBrandTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    AppBrand brand,
  ) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    final isUnlocked = themeProvider.isBrandUnlocked(brand.id);
    final cost = themeProvider.brandCost(brand.id);
    final ok = await _applyThemeShopItem(
      context,
      themeProvider: themeProvider,
      achievementProvider: achievementProvider,
      itemType: 'brand',
      itemId: brand.id,
      title: DataSettingsUiCopy.redeemThemeTitle(_styleName(brand)),
      cost: cost,
      isUnlocked: isUnlocked,
      applyLocal: (isCurrent) async {
        if (!isCurrent()) return;
        if (!isUnlocked) {
          await themeProvider.unlockBrand(brand.id);
          if (!isCurrent()) return;
        }
        if (!isCurrent()) return;
        await themeProvider.setBrand(brand.id);
      },
    );
    if (!context.mounted || !isCurrent()) return;
    if (!ok) {
      return;
    }
    final brandId = brand.id;
    _showDynamicFeedback(context, () {
      final name = AppBrands.byId(brandId).localizedName;
      return isUnlocked
          ? DataSettingsUiCopy.themeApplied(name)
          : DataSettingsUiCopy.themeRedeemedAndApplied(name);
    });
  }

  Future<void> _handleFocusBackdropTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    FocusBackdropReward backdrop,
  ) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    final isUnlocked = themeProvider.isFocusBackdropUnlocked(backdrop.id);
    final ok = await _applyThemeShopItem(
      context,
      themeProvider: themeProvider,
      achievementProvider: achievementProvider,
      itemType: 'focus_backdrop',
      itemId: backdrop.id,
      title: DataSettingsUiCopy.redeemFocusBackdropTitle(
        DataSettingsUiCopy.focusBackdropName(backdrop.id, backdrop.name),
      ),
      cost: backdrop.cost,
      isUnlocked: isUnlocked,
      applyLocal: (isCurrent) async {
        if (!isCurrent()) return;
        if (!isUnlocked) {
          await themeProvider.unlockFocusBackdrop(backdrop.id);
          if (!isCurrent()) return;
        }
        if (!isCurrent()) return;
        await themeProvider.setFocusBackdrop(backdrop.id);
      },
    );
    if (!context.mounted || !isCurrent()) return;
    if (!ok) {
      return;
    }
    final backdropId = backdrop.id;
    final fallbackName = backdrop.name;
    _showDynamicFeedback(context, () {
      final name = DataSettingsUiCopy.focusBackdropName(
        backdropId,
        fallbackName,
      );
      return isUnlocked
          ? DataSettingsUiCopy.themeApplied(name)
          : DataSettingsUiCopy.themeRedeemedAndApplied(name);
    });
  }

  Future<void> _handleAvatarFrameTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    AvatarFrameReward frame,
  ) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    final isUnlocked = themeProvider.isAvatarFrameUnlocked(frame.id);
    final ok = await _applyThemeShopItem(
      context,
      themeProvider: themeProvider,
      achievementProvider: achievementProvider,
      itemType: 'avatar_frame',
      itemId: frame.id,
      title: DataSettingsUiCopy.redeemAvatarFrameTitle(
        DataSettingsUiCopy.avatarFrameName(frame.id, frame.name),
      ),
      cost: frame.cost,
      isUnlocked: isUnlocked,
      applyLocal: (isCurrent) async {
        if (!isCurrent()) return;
        if (!isUnlocked) {
          await themeProvider.unlockAvatarFrame(frame.id);
          if (!isCurrent()) return;
        }
        if (!isCurrent()) return;
        await themeProvider.setAvatarFrame(frame.id);
      },
    );
    if (!context.mounted || !isCurrent()) return;
    if (!ok) {
      return;
    }
    final frameId = frame.id;
    final fallbackName = frame.name;
    _showDynamicFeedback(context, () {
      final name = DataSettingsUiCopy.avatarFrameName(frameId, fallbackName);
      return isUnlocked
          ? DataSettingsUiCopy.themeApplied(name)
          : DataSettingsUiCopy.themeRedeemedAndApplied(name);
    });
  }

  Future<void> _handleCardSkinTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    CardSkinReward skin,
  ) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    final isUnlocked = themeProvider.isCardSkinUnlocked(skin.id);
    final ok = await _applyThemeShopItem(
      context,
      themeProvider: themeProvider,
      achievementProvider: achievementProvider,
      itemType: 'card_skin',
      itemId: skin.id,
      title: DataSettingsUiCopy.redeemCardSkinTitle(
        DataSettingsUiCopy.cardSkinName(skin.id, skin.name),
      ),
      cost: skin.cost,
      isUnlocked: isUnlocked,
      applyLocal: (isCurrent) async {
        if (!isCurrent()) return;
        if (!isUnlocked) {
          await themeProvider.unlockCardSkin(skin.id);
          if (!isCurrent()) return;
        }
        if (!isCurrent()) return;
        await themeProvider.setCardSkin(skin.id);
      },
    );
    if (!context.mounted || !isCurrent()) return;
    if (!ok) {
      return;
    }
    final skinId = skin.id;
    final fallbackName = skin.name;
    _showDynamicFeedback(context, () {
      final name = DataSettingsUiCopy.cardSkinName(skinId, fallbackName);
      return isUnlocked
          ? DataSettingsUiCopy.themeApplied(name)
          : DataSettingsUiCopy.themeRedeemedAndApplied(name);
    });
  }

  String _widgetBackgroundLabel(String id) {
    if (id == ThemeProvider.widgetFollowThemeId) {
      return DataSettingsUiCopy.widgetFollowCurrentTheme;
    }
    return AppBrands.byId(id).localizedName;
  }

  String _widgetCardSkinLabel(ThemeProvider themeProvider, String id) {
    if (id == ThemeProvider.widgetFollowCardSkinId) {
      return DataSettingsUiCopy.widgetFollowCardSkin;
    }
    final skin = themeProvider.cardSkinById(id);
    return DataSettingsUiCopy.cardSkinName(skin.id, skin.name);
  }

  void _showDynamicFeedback(
    BuildContext context,
    String Function() messageResolver,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, child) => Text(messageResolver()),
        ),
      ),
    );
  }

  Future<void> _handleWidgetBackgroundTap(
    BuildContext context,
    ThemeProvider themeProvider,
    String id,
  ) async {
    if (_shopBusy || !mounted) return;
    final targetId = id;
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    setState(() => _shopBusy = true);
    try {
      final ok = await themeProvider.setWidgetBackgroundBrand(targetId);
      if (!context.mounted || !isCurrent()) return;
      _showDynamicFeedback(
        context,
        () => ok
            ? DataSettingsUiCopy.widgetBackgroundSwitched(
                _widgetBackgroundLabel(targetId),
              )
            : DataSettingsUiCopy.unlockThemeFirst,
      );
    } catch (_) {
      if (context.mounted && isCurrent()) {
        _showDynamicFeedback(context, () => DataSettingsUiCopy.themeSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
  }

  Future<void> _handleWidgetCardSkinTap(
    BuildContext context,
    ThemeProvider themeProvider,
    String id,
  ) async {
    if (_shopBusy || !mounted) return;
    final targetId = id;
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    setState(() => _shopBusy = true);
    try {
      final ok = await themeProvider.setWidgetCardSkin(targetId);
      if (!context.mounted || !isCurrent()) return;
      _showDynamicFeedback(
        context,
        () => ok
            ? DataSettingsUiCopy.widgetCardSkinSwitched(
                _widgetCardSkinLabel(themeProvider, targetId),
              )
            : DataSettingsUiCopy.unlockCardSkinFirst,
      );
    } catch (_) {
      if (context.mounted && isCurrent()) {
        _showDynamicFeedback(context, () => DataSettingsUiCopy.themeSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
  }

  Widget _focusBackdropPreview(
    BuildContext context,
    FocusBackdropReward backdrop,
  ) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: backdrop.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          appSurfaceStyleOf(context)?.smallTileRadius ?? 16,
        ),
      ),
      child: Icon(backdrop.icon, color: Colors.white, size: 26),
    );
  }

  Widget _avatarFramePreview(AvatarFrameReward frame, ColorScheme cs) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: frame.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CircleAvatar(
        backgroundColor: cs.surface,
        child: Icon(frame.icon, color: frame.colors.first, size: 24),
      ),
    );
  }

  Widget _cardSkinPreview(
    BuildContext context,
    CardSkinReward skin,
    ColorScheme cs,
  ) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: skin.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(
          appSurfaceStyleOf(context)?.smallTileRadius ?? 16,
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Icon(skin.icon, color: cs.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _widgetThemeChoice({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final selectedBg = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.14),
      cs.surface,
    );
    final selectedForeground = appReadableForeground(selectedBg, cs.primary);
    final labelStyle = appSecondaryMenuItemTextStyle(context).copyWith(
      fontWeight: FontWeight.normal,
      color: selected ? selectedForeground : cs.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final textWidth = painter.width;
        painter.dispose();

        final maxAvailable = constraints.maxWidth;
        const chipHorizontalPadding = 32.0;
        final bool needsWrap =
            maxAvailable.isFinite &&
            (textWidth + chipHorizontalPadding > maxAvailable);

        // RawChip measures the label height at the full chip width, then lays
        // the label out again after removing the chip and label padding. Resolve
        // both paddings here (the same way RawChip's Material 3 defaults do, but
        // from the merged label font size) and hand them to the chip, so the
        // wrapping label can be given its real width up front and both passes
        // agree on the number of lines.
        final chipTheme = ChipTheme.of(context);
        final chipPadding = (chipTheme.padding ?? const EdgeInsets.all(8.0))
            .resolve(Directionality.maybeOf(context) ?? TextDirection.ltr);
        final labelFontSize =
            labelStyle.fontSize ??
            chipTheme.labelStyle?.fontSize ??
            Theme.of(context).textTheme.labelLarge?.fontSize ??
            14.0;
        final labelFontSizeRatio =
            MediaQuery.textScalerOf(context).scale(labelFontSize) / 14.0;
        final chipLabelPadding =
            (chipTheme.labelPadding ??
                    EdgeInsets.lerp(
                      const EdgeInsets.symmetric(horizontal: 8.0),
                      const EdgeInsets.symmetric(horizontal: 4.0),
                      (labelFontSizeRatio - 1.0).clamp(0.0, 1.0).toDouble(),
                    )!)
                .resolve(Directionality.maybeOf(context) ?? TextDirection.ltr);
        final labelMaxWidth =
            (maxAvailable -
                    chipPadding.horizontal -
                    chipLabelPadding.horizontal)
                .clamp(0.0, double.infinity)
                .toDouble();
        final labelText = Text(
          label,
          softWrap: true,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        );

        final chip = ChoiceChip(
          label: maxAvailable.isFinite
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMaxWidth),
                  child: labelText,
                )
              : labelText,
          padding: chipPadding,
          labelPadding: chipLabelPadding,
          selected: selected,
          onSelected: _shopBusy ? null : (_) => onTap(),
          labelStyle: labelStyle,
          selectedColor: selectedBg,
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
          side: BorderSide(
            color: selected
                ? cs.primary.withValues(alpha: 0.38)
                : cs.outlineVariant.withValues(alpha: 0.16),
            width: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          showCheckmark: false,
          // RawChip's padded tap target is kMinInteractiveDimension (48) plus
          // the density adjustment (4 logical pixels per density step). The
          // comfortable density (-1) makes the chip's own hit-tested box a
          // 44x44 minimum while staying tighter than the standard density.
          visualDensity: VisualDensity.comfortable,
          materialTapTargetSize: MaterialTapTargetSize.padded,
        );

        if (needsWrap) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxAvailable),
            child: chip,
          );
        }
        return chip;
      },
    );
  }

  Widget _widgetThemeSection(
    BuildContext context,
    ThemeProvider provider, {
    required Iterable<Color> surfaces,
    required bool isKnownSurface,
    required bool isDark,
  }) {
    final cs = Theme.of(context).colorScheme;
    final availableBrands = provider.brands
        .where((brand) => provider.isBrandUnlocked(brand.id))
        .toList(growable: false);
    final availableSkins = provider.cardSkins
        .where((skin) => provider.isCardSkinUnlocked(skin.id))
        .toList(growable: false);
    final backgroundChoices = <({String id, String label})>[
      (
        id: ThemeProvider.widgetFollowThemeId,
        label: _widgetBackgroundLabel(ThemeProvider.widgetFollowThemeId),
      ),
      for (final brand in availableBrands)
        (id: brand.id, label: _widgetBackgroundLabel(brand.id)),
    ];
    final cardSkinChoices = <({String id, String label})>[
      (
        id: ThemeProvider.widgetFollowCardSkinId,
        label: _widgetCardSkinLabel(
          provider,
          ThemeProvider.widgetFollowCardSkinId,
        ),
      ),
      for (final skin in availableSkins)
        (id: skin.id, label: _widgetCardSkinLabel(provider, skin.id)),
    ];

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.widgets_outlined,
                  color: cs.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DataSettingsUiCopy.widgetThemeTitle,
                      style: appSecondaryRouteTitleTextStyle(
                        context,
                      ).copyWith(fontSize: 14, fontWeight: FontWeight.normal),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DataSettingsUiCopy.widgetThemeSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.normal,
                        color: _descriptionForegroundColor(
                          surfaces: surfaces,
                          cs: cs,
                          isKnownSurface: isKnownSurface,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DataSettingsUiCopy.widgetBackgroundLabel,
            style: appSecondaryControlTextStyle(context).copyWith(
              fontWeight: FontWeight.normal,
              color: _widgetLabelForegroundColor(
                surfaces: surfaces,
                cs: cs,
                isKnownSurface: isKnownSurface,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in backgroundChoices)
                _widgetThemeChoice(
                  context: context,
                  label: item.label,
                  selected: provider.activeWidgetBackgroundId == item.id,
                  onTap: () =>
                      _handleWidgetBackgroundTap(context, provider, item.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DataSettingsUiCopy.widgetCardSkinLabel,
            style: appSecondaryControlTextStyle(context).copyWith(
              fontWeight: FontWeight.normal,
              color: _widgetLabelForegroundColor(
                surfaces: surfaces,
                cs: cs,
                isKnownSurface: isKnownSurface,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in cardSkinChoices)
                _widgetThemeChoice(
                  context: context,
                  label: item.label,
                  selected: provider.activeWidgetCardSkinId == item.id,
                  onTap: () =>
                      _handleWidgetCardSkinTap(context, provider, item.id),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final themeProvider = context.watch<ThemeProvider>();
        final achievementProvider = context.watch<AchievementProvider>();
        final authProvider = context.watch<AuthProvider>();
        final currentBrand = themeProvider.brand;
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceStyle = appSurfaceStyleOf(context);
        final isLiquidGlass = currentBrand.style == BrandStyle.liquidGlass;
        final isKnownSurface =
            currentBrand.id == AppBrands.defaultBrand.id ||
            currentBrand.id == AppBrands.liquidGlass.id;
        final routeBackground = isKnownSurface
            ? Theme.of(context).scaffoldBackgroundColor
            : (isDark ? cs.surface : cs.surfaceContainerLowest);
        final standardCardBase = Color.alphaBlend(
          surfaceStyle?.cardFillColor ?? cs.surface,
          routeBackground,
        );
        final activeCardSkin = themeProvider.activeCardSkin;
        final useCardSkin =
            activeCardSkin.id != ThemeProvider.defaultCardSkinId;
        final skinStart = useCardSkin
            ? Color.alphaBlend(
                activeCardSkin.colors.first.withValues(
                  alpha: isDark ? 0.22 : 0.18,
                ),
                routeBackground,
              )
            : standardCardBase;
        final skinMid = useCardSkin
            ? Color.alphaBlend(
                activeCardSkin.colors.last.withValues(
                  alpha: isDark ? 0.18 : 0.12,
                ),
                routeBackground,
              )
            : standardCardBase;
        final skinEnd = useCardSkin
            ? Color.alphaBlend(
                cs.surface.withValues(alpha: isDark ? 0.94 : 0.96),
                routeBackground,
              )
            : standardCardBase;
        final defaultGradStart = Color.alphaBlend(
          Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.045 : 0.025),
            cs.surface,
          ),
          routeBackground,
        );
        final unselectedCardSurfaces = useCardSkin
            ? [
                skinStart,
                Color.lerp(skinStart, skinMid, 0.5)!,
                skinMid,
                Color.lerp(skinMid, skinEnd, 0.5)!,
                skinEnd,
              ]
            : [
                if (surfaceStyle?.cardFillColor == null) defaultGradStart,
                standardCardBase,
              ];
        final topStart = Color.alphaBlend(
          cs.primary.withValues(alpha: 0.12),
          routeBackground,
        );
        final topEnd = Color.alphaBlend(cs.surface, routeBackground);
        final topCardSurfaces = [
          topStart,
          Color.lerp(topStart, topEnd, 0.5)!,
          topEnd,
        ];

        final scaffold = Scaffold(
          backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
          appBar: AppBar(
            title: Text(I18n.tr('theme.title')),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            backgroundColor: routeBackground.withValues(alpha: 0.96),
            surfaceTintColor: Colors.transparent,
            bottom: _shopBusy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(4),
                    child: LinearProgressIndicator(),
                  )
                : null,
          ),
          body: AppSecondaryControlTheme(
            child: Builder(
              builder: (context) {
                final useTwoColumns = MediaQuery.sizeOf(context).width >= 760;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  children: _wrapDesktopWidth([
                AppSurfaceCard(
                  padding: const EdgeInsets.all(16),
                  gradient: LinearGradient(
                    colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.palette_outlined,
                          color: cs.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _styleName(currentBrand),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.normal,
                                    color: cs.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _styleDescription(currentBrand.style),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.normal,
                                    color: _descriptionForegroundColor(
                                      surfaces: topCardSurfaces,
                                      cs: cs,
                                      isKnownSurface: isKnownSurface,
                                      isDark: isDark,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DataSettingsUiCopy.coinCount(
                                _visibleCoinBalance(
                                  authProvider,
                                  achievementProvider,
                                ),
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.normal,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    color: isKnownSurface
                                        ? _balanceForegroundColor(
                                            surfaces: topCardSurfaces,
                                            cs: cs,
                                          )
                                        : cs.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppSectionHeader(
                  title: I18n.tr('theme.section.styles'),
                  subtitle: I18n.tr('theme.section.styles.subtitle'),
                  padding: EdgeInsets.zero,
                  wrapText: true,
                ),
                const SizedBox(height: 8),
                ..._buildOptionGridRows(
                  themeProvider.brands.map((brand) {
                  final isActive = brand.style == currentBrand.style;
                  final isUnlocked = themeProvider.isBrandUnlocked(brand.id);
                  final cost = themeProvider.brandCost(brand.id);
                  final accent = _accentColor(brand);
                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    color: isActive ? accent.withValues(alpha: 0.08) : null,
                    border: Border.all(
                      color: isActive
                          ? accent.withValues(alpha: 0.28)
                          : cs.outlineVariant.withValues(alpha: 0.14),
                      width: 0.45,
                    ),
                    onTap: _shopBusy
                        ? null
                        : () => _handleBrandTap(
                            context,
                            themeProvider,
                            achievementProvider,
                            brand,
                          ),
                    child: _ThemeOptionRow(
                      preview: BrandBackgroundThumbnail(
                        key: ValueKey('theme_card_bg_${brand.id}'),
                        brand: brand,
                        fallback: Icon(
                          Icons.palette_outlined,
                          color: accent,
                          size: 28,
                        ),
                      ),
                      details: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _styleName(brand),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _styleDescription(brand.style),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: _descriptionForegroundColor(
                                    surfaces: isActive
                                        ? [
                                            Color.alphaBlend(
                                              accent.withValues(alpha: 0.08),
                                              routeBackground,
                                            ),
                                            Color.alphaBlend(
                                              accent.withValues(alpha: 0.08),
                                              standardCardBase,
                                            ),
                                          ]
                                        : unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                                ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _swatch(brand.theme.colorScheme.primary),
                              _swatch(brand.theme.colorScheme.secondary),
                              _swatch(brand.theme.colorScheme.tertiary),
                            ],
                          ),
                        ],
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Icon(
                            isActive
                                ? Icons.check_circle
                                : isUnlocked
                                ? Icons.radio_button_unchecked
                                : Icons.lock_outline,
                            color: isActive
                                ? accent
                                : _inactiveOptionIconColor(
                                    surfaces: unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                          ),
                          if (!isUnlocked) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                DataSettingsUiCopy.coinCost(cost),
                                style: TextStyle(
                                  color: isKnownSurface
                                      ? _priceForegroundColor(
                                          surfaces: unselectedCardSurfaces,
                                          accent: accent,
                                        )
                                      : accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
                  useTwoColumns,
                ),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.focusBackdropSectionTitle,
                  subtitle: DataSettingsUiCopy.focusBackdropSectionSubtitle,
                  padding: EdgeInsets.zero,
                  wrapText: true,
                ),
                const SizedBox(height: 8),
                ..._buildOptionGridRows(
                  themeProvider.focusBackdrops.map((backdrop) {
                  final isActive =
                      themeProvider.activeFocusBackdrop.id == backdrop.id;
                  final isUnlocked = themeProvider.isFocusBackdropUnlocked(
                    backdrop.id,
                  );
                  final accent = backdrop.colors.first;
                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.12),
                              cs.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    border: Border.all(
                      color: isActive
                          ? accent.withValues(alpha: 0.28)
                          : cs.outlineVariant.withValues(alpha: 0.14),
                      width: 0.45,
                    ),
                    onTap: _shopBusy
                        ? null
                        : () => _handleFocusBackdropTap(
                            context,
                            themeProvider,
                            achievementProvider,
                            backdrop,
                          ),
                    child: _ThemeOptionRow(
                      preview: _focusBackdropPreview(context, backdrop),
                      details: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DataSettingsUiCopy.focusBackdropName(
                              backdrop.id,
                              backdrop.name,
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DataSettingsUiCopy.focusBackdropDescription(
                              backdrop.id,
                              backdrop.description,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: _descriptionForegroundColor(
                                    surfaces: isActive
                                        ? _activeOptionSurfaces(
                                            routeBackground: routeBackground,
                                            accent: accent,
                                            cs: cs,
                                            gradientStartAlpha: 0.12,
                                          )
                                        : unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                                ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Icon(
                            isActive
                                ? Icons.check_circle
                                : isUnlocked
                                ? Icons.radio_button_unchecked
                                : Icons.lock_outline,
                            color: isActive
                                ? (isKnownSurface
                                      ? _activeOptionCheckmarkColor(
                                          routeBackground: routeBackground,
                                          accent: accent,
                                          cs: cs,
                                          gradientStartAlpha: 0.12,
                                        )
                                      : accent)
                                : _inactiveOptionIconColor(
                                    surfaces: unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                          ),
                          if (!isUnlocked) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                DataSettingsUiCopy.coinCost(backdrop.cost),
                                style: TextStyle(
                                  color: isKnownSurface
                                      ? _priceForegroundColor(
                                          surfaces: unselectedCardSurfaces,
                                          accent: accent,
                                        )
                                      : accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
                  useTwoColumns,
                ),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.avatarFrameSectionTitle,
                  subtitle: DataSettingsUiCopy.avatarFrameSectionSubtitle,
                  padding: EdgeInsets.zero,
                  wrapText: true,
                ),
                const SizedBox(height: 8),
                ..._buildOptionGridRows(
                  themeProvider.avatarFrames.map((frame) {
                  final isActive =
                      themeProvider.activeAvatarFrame.id == frame.id;
                  final isUnlocked = themeProvider.isAvatarFrameUnlocked(
                    frame.id,
                  );
                  final accent = frame.colors.first;
                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.12),
                              cs.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    border: Border.all(
                      color: isActive
                          ? accent.withValues(alpha: 0.44)
                          : cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                    onTap: _shopBusy
                        ? null
                        : () => _handleAvatarFrameTap(
                            context,
                            themeProvider,
                            achievementProvider,
                            frame,
                          ),
                    child: _ThemeOptionRow(
                      preview: _avatarFramePreview(frame, cs),
                      details: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DataSettingsUiCopy.avatarFrameName(
                              frame.id,
                              frame.name,
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DataSettingsUiCopy.avatarFrameDescription(
                              frame.id,
                              frame.description,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: _descriptionForegroundColor(
                                    surfaces: isActive
                                        ? _activeOptionSurfaces(
                                            routeBackground: routeBackground,
                                            accent: accent,
                                            cs: cs,
                                            gradientStartAlpha: 0.12,
                                          )
                                        : unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                                ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Icon(
                            isActive
                                ? Icons.check_circle
                                : isUnlocked
                                ? Icons.radio_button_unchecked
                                : Icons.lock_outline,
                            color: isActive
                                ? (isKnownSurface
                                      ? _activeOptionCheckmarkColor(
                                          routeBackground: routeBackground,
                                          accent: accent,
                                          cs: cs,
                                          gradientStartAlpha: 0.12,
                                        )
                                      : accent)
                                : _inactiveOptionIconColor(
                                    surfaces: unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                          ),
                          if (!isUnlocked) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                DataSettingsUiCopy.coinCost(frame.cost),
                                style: TextStyle(
                                  color: isKnownSurface
                                      ? _priceForegroundColor(
                                          surfaces: unselectedCardSurfaces,
                                          accent: accent,
                                        )
                                      : accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
                  useTwoColumns,
                ),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.cardSkinSectionTitle,
                  subtitle: DataSettingsUiCopy.cardSkinSectionSubtitle,
                  padding: EdgeInsets.zero,
                  wrapText: true,
                ),
                const SizedBox(height: 8),
                ..._buildOptionGridRows(
                  themeProvider.cardSkins.map((skin) {
                  final isActive = themeProvider.activeCardSkin.id == skin.id;
                  final isUnlocked = themeProvider.isCardSkinUnlocked(skin.id);
                  final accent = skin.colors.first;
                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    gradient: isActive
                        ? LinearGradient(
                            colors: [
                              accent.withValues(alpha: 0.18),
                              cs.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    border: Border.all(
                      color: isActive
                          ? accent.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                    onTap: _shopBusy
                        ? null
                        : () => _handleCardSkinTap(
                            context,
                            themeProvider,
                            achievementProvider,
                            skin,
                          ),
                    child: _ThemeOptionRow(
                      preview: _cardSkinPreview(context, skin, cs),
                      details: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DataSettingsUiCopy.cardSkinName(skin.id, skin.name),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DataSettingsUiCopy.cardSkinDescription(
                              skin.id,
                              skin.description,
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: _descriptionForegroundColor(
                                    surfaces: isActive
                                        ? _activeOptionSurfaces(
                                            routeBackground: routeBackground,
                                            accent: accent,
                                            cs: cs,
                                            gradientStartAlpha: 0.18,
                                          )
                                        : unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                                ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Icon(
                            isActive
                                ? Icons.check_circle
                                : isUnlocked
                                ? Icons.radio_button_unchecked
                                : Icons.lock_outline,
                            color: isActive
                                ? (isKnownSurface
                                      ? _cardSkinActiveCheckmarkColor(
                                          routeBackground: routeBackground,
                                          accent: accent,
                                          cs: cs,
                                        )
                                      : accent)
                                : _inactiveOptionIconColor(
                                    surfaces: unselectedCardSurfaces,
                                    cs: cs,
                                    isKnownSurface: isKnownSurface,
                                    isDark: isDark,
                                  ),
                          ),
                          if (!isUnlocked) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                DataSettingsUiCopy.coinCost(skin.cost),
                                style: TextStyle(
                                  color: isKnownSurface
                                      ? _priceForegroundColor(
                                          surfaces: unselectedCardSurfaces,
                                          accent: accent,
                                        )
                                      : accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
                  useTwoColumns,
                ),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeader(
                      title: DataSettingsUiCopy.widgetSyncNoticeTitle,
                      padding: EdgeInsets.zero,
                      wrapText: true,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DataSettingsUiCopy.widgetSyncNoticeSubtitle,
                      style: appSecondaryControlLabelStyle(context).copyWith(
                        fontWeight: FontWeight.normal,
                        color: _syncNoticeSubtitleForegroundColor(
                          context: context,
                          routeBackground: routeBackground,
                          cs: cs,
                          isKnownSurface: isKnownSurface,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _widgetThemeSection(
                  context,
                  themeProvider,
                  surfaces: unselectedCardSurfaces,
                  isKnownSurface: isKnownSurface,
                  isDark: isDark,
                ),
                  ]),
                );
              },
            ),
          ),
        );

        if (!isLiquidGlass) {
          return scaffold;
        }

        final hasBrandSurface =
            DesktopEmbeddedHostScope.isHosted(context) ||
            context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
            context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
        if (hasBrandSurface) {
          return scaffold;
        }
        return Material(
          color: routeBackground,
          child: BrandBackground(child: scaffold),
        );
      },
    );
  }
}

/// Gives enlarged text room without competing with price and status.
class _ThemeOptionRow extends StatelessWidget {
  final Widget preview;
  final Widget details;
  final Widget trailing;

  const _ThemeOptionRow({
    required this.preview,
    required this.details,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 340 || scale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  preview,
                  const SizedBox(width: 12),
                  Expanded(child: details),
                ],
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: trailing),
            ],
          );
        }
        return Row(
          children: [
            preview,
            const SizedBox(width: 12),
            Expanded(child: details),
            const SizedBox(width: 10),
            trailing,
          ],
        );
      },
    );
  }
}
