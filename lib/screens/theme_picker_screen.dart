import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/data_settings_ui_copy.dart';
import '../core/i18n.dart';
import '../providers/achievement_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

class ThemePickerScreen extends StatelessWidget {
  const ThemePickerScreen({super.key});

  Color _accentColor(AppBrand brand) {
    return brand.theme.colorScheme.primary;
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
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final token = auth.state.token;
    final userId = auth.state.userId;
    return () =>
        context.mounted &&
        !auth.isAccountTransitionInProgress &&
        !auth.isLocalAccountDataBlocked &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) &&
        auth.state.token == token &&
        auth.state.userId == userId;
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
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              userVisibleApiError(
                e,
                fallbackMessage: DataSettingsUiCopy.themeSaveFailed,
              ),
            ),
          ),
        );
        return false;
      }
    }

    if (!isUnlocked) {
      if (!isCurrent()) return false;
      final ok = await achievementProvider.spendCoins(
        coins: cost,
        title: title,
        reason: DataSettingsUiCopy.rewardShopReason,
      );
      if (!context.mounted || !isCurrent()) return false;
      if (!ok) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              DataSettingsUiCopy.insufficientCoins(
                cost - achievementProvider.coinBalance,
              ),
            ),
          ),
        );
        return false;
      }
    }
    if (!isCurrent()) return false;
    await applyLocal(isCurrent);
    return isCurrent();
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isUnlocked
              ? DataSettingsUiCopy.themeApplied(_styleName(brand))
              : DataSettingsUiCopy.themeRedeemedAndApplied(_styleName(brand)),
        ),
      ),
    );
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
    final backdropDisplayName = DataSettingsUiCopy.focusBackdropName(
      backdrop.id,
      backdrop.name,
    );
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isUnlocked
              ? DataSettingsUiCopy.themeApplied(backdropDisplayName)
              : DataSettingsUiCopy.themeRedeemedAndApplied(backdropDisplayName),
        ),
      ),
    );
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
    final frameDisplayName = DataSettingsUiCopy.avatarFrameName(
      frame.id,
      frame.name,
    );
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isUnlocked
              ? DataSettingsUiCopy.themeApplied(frameDisplayName)
              : DataSettingsUiCopy.themeRedeemedAndApplied(frameDisplayName),
        ),
      ),
    );
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
    final skinDisplayName = DataSettingsUiCopy.cardSkinName(skin.id, skin.name);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isUnlocked
              ? DataSettingsUiCopy.themeApplied(skinDisplayName)
              : DataSettingsUiCopy.themeRedeemedAndApplied(skinDisplayName),
        ),
      ),
    );
  }

  Future<void> _handleWidgetBackgroundTap(
    BuildContext context,
    ThemeProvider themeProvider,
    String id,
    String label,
  ) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    final bool ok;
    try {
      ok = await themeProvider.setWidgetBackgroundBrand(id);
    } catch (_) {
      if (!context.mounted || !isCurrent()) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.themeSaveFailed)),
      );
      return;
    }
    if (!context.mounted || !isCurrent()) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? DataSettingsUiCopy.widgetBackgroundSwitched(label)
              : DataSettingsUiCopy.unlockThemeFirst,
        ),
      ),
    );
  }

  Future<void> _handleWidgetCardSkinTap(
    BuildContext context,
    ThemeProvider themeProvider,
    String id,
    String label,
  ) async {
    final isCurrent = _accountOperationGuard(context);
    if (!isCurrent()) return;
    final bool ok;
    try {
      ok = await themeProvider.setWidgetCardSkin(id);
    } catch (_) {
      if (!context.mounted || !isCurrent()) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(DataSettingsUiCopy.themeSaveFailed)),
      );
      return;
    }
    if (!context.mounted || !isCurrent()) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? DataSettingsUiCopy.widgetCardSkinSwitched(label)
              : DataSettingsUiCopy.unlockCardSkinFirst,
        ),
      ),
    );
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
          appSurfaceStyleOf(context)?.smallTileRadius ?? 14,
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
          appSurfaceStyleOf(context)?.smallTileRadius ?? 14,
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
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: appSecondaryMenuItemTextStyle(context).copyWith(
        fontWeight: FontWeight.normal,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
      selectedColor: Color.alphaBlend(
        cs.primary.withValues(alpha: 0.14),
        cs.surface,
      ),
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.42),
      side: BorderSide(
        color: selected
            ? cs.primary.withValues(alpha: 0.38)
            : cs.outlineVariant.withValues(alpha: 0.16),
        width: 0.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _widgetThemeSection(BuildContext context, ThemeProvider provider) {
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
        label: DataSettingsUiCopy.widgetFollowCurrentTheme,
      ),
      for (final brand in availableBrands)
        (id: brand.id, label: _styleName(brand)),
    ];
    final cardSkinChoices = <({String id, String label})>[
      (
        id: ThemeProvider.widgetFollowCardSkinId,
        label: DataSettingsUiCopy.widgetFollowCardSkin,
      ),
      for (final skin in availableSkins)
        (
          id: skin.id,
          label: DataSettingsUiCopy.cardSkinName(skin.id, skin.name),
        ),
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
                        color: cs.onSurface.withValues(alpha: 0.66),
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
              color: cs.onSurface.withValues(alpha: 0.72),
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
                  onTap: () => _handleWidgetBackgroundTap(
                    context,
                    provider,
                    item.id,
                    item.label,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DataSettingsUiCopy.widgetCardSkinLabel,
            style: appSecondaryControlTextStyle(context).copyWith(
              fontWeight: FontWeight.normal,
              color: cs.onSurface.withValues(alpha: 0.72),
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
                  onTap: () => _handleWidgetCardSkinTap(
                    context,
                    provider,
                    item.id,
                    item.label,
                  ),
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
        final routeBackground = Theme.of(context).brightness == Brightness.dark
            ? cs.surface
            : cs.surfaceContainerLowest;

        return Scaffold(
          backgroundColor: routeBackground,
          appBar: AppBar(
            title: Text(I18n.tr('theme.title')),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            backgroundColor: routeBackground.withValues(alpha: 0.96),
            surfaceTintColor: Colors.transparent,
          ),
          body: AppSecondaryControlTheme(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
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
                                    color: cs.onSurface.withValues(alpha: 0.66),
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
                                    color: cs.primary,
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
                ),
                const SizedBox(height: 8),
                ...themeProvider.brands.map((brand) {
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
                    onTap: () => _handleBrandTap(
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
                                  color: cs.onSurface.withValues(alpha: 0.66),
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
                                : cs.onSurface.withValues(alpha: 0.36),
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
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.focusBackdropSectionTitle,
                  subtitle: DataSettingsUiCopy.focusBackdropSectionSubtitle,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                ...themeProvider.focusBackdrops.map((backdrop) {
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
                    onTap: () => _handleFocusBackdropTap(
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
                                  color: cs.onSurface.withValues(alpha: 0.66),
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
                                ? accent
                                : cs.onSurface.withValues(alpha: 0.36),
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
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.avatarFrameSectionTitle,
                  subtitle: DataSettingsUiCopy.avatarFrameSectionSubtitle,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                ...themeProvider.avatarFrames.map((frame) {
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
                    onTap: () => _handleAvatarFrameTap(
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
                                  color: cs.onSurface.withValues(alpha: 0.66),
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
                                ? accent
                                : cs.onSurface.withValues(alpha: 0.36),
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
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.cardSkinSectionTitle,
                  subtitle: DataSettingsUiCopy.cardSkinSectionSubtitle,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                ...themeProvider.cardSkins.map((skin) {
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
                    onTap: () => _handleCardSkinTap(
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
                                  color: cs.onSurface.withValues(alpha: 0.66),
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
                                ? accent
                                : cs.onSurface.withValues(alpha: 0.36),
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
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                AppSectionHeader(
                  title: DataSettingsUiCopy.widgetSyncNoticeTitle,
                  subtitle: DataSettingsUiCopy.widgetSyncNoticeSubtitle,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                _widgetThemeSection(context, themeProvider),
              ],
            ),
          ),
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
