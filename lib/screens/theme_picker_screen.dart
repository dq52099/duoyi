import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/i18n.dart';
import '../providers/achievement_provider.dart';
import '../providers/theme_provider.dart';
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
    }
  }

  String _styleName(AppBrand brand) {
    return switch (brand.style) {
      BrandStyle.defaultBrand => I18n.tr('theme.style.default.name'),
      BrandStyle.re0 => I18n.tr('theme.style.re0.name'),
      BrandStyle.genshin => I18n.tr('theme.style.genshin.name'),
      BrandStyle.starRail => I18n.tr('theme.style.star_rail.name'),
      BrandStyle.wuthering => I18n.tr('theme.style.wuthering.name'),
      BrandStyle.zzz => I18n.tr('theme.style.zzz.name'),
      BrandStyle.yanyun => I18n.tr('theme.style.yanyun.name'),
      BrandStyle.botw => I18n.tr('theme.style.botw.name'),
    };
  }

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

  Future<void> _handleBrandTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    AppBrand brand,
  ) async {
    final isUnlocked = themeProvider.isBrandUnlocked(brand.id);
    if (isUnlocked) {
      await themeProvider.setBrand(brand.id);
      return;
    }
    final cost = themeProvider.brandCost(brand.id);
    final ok = await achievementProvider.spendCoins(
      coins: cost,
      title: '兑换主题：${_styleName(brand)}',
      reason: '奖励商店主题装饰',
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('时光币不足，还差 ${cost - achievementProvider.coinBalance}'),
        ),
      );
      return;
    }
    await themeProvider.unlockBrand(brand.id);
    await themeProvider.setBrand(brand.id);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('已兑换并启用 ${_styleName(brand)}')),
    );
  }

  Future<void> _handleFocusBackdropTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    FocusBackdropReward backdrop,
  ) async {
    final isUnlocked = themeProvider.isFocusBackdropUnlocked(backdrop.id);
    if (isUnlocked) {
      await themeProvider.setFocusBackdrop(backdrop.id);
      return;
    }
    final ok = await achievementProvider.spendCoins(
      coins: backdrop.cost,
      title: '兑换专注背景：${backdrop.name}',
      reason: '奖励商店专注背景',
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '时光币不足，还差 ${backdrop.cost - achievementProvider.coinBalance}',
          ),
        ),
      );
      return;
    }
    await themeProvider.unlockFocusBackdrop(backdrop.id);
    await themeProvider.setFocusBackdrop(backdrop.id);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('已兑换并启用 ${backdrop.name}')));
  }

  Future<void> _handleAvatarFrameTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    AvatarFrameReward frame,
  ) async {
    final isUnlocked = themeProvider.isAvatarFrameUnlocked(frame.id);
    if (isUnlocked) {
      await themeProvider.setAvatarFrame(frame.id);
      return;
    }
    final ok = await achievementProvider.spendCoins(
      coins: frame.cost,
      title: '兑换头像框：${frame.name}',
      reason: '奖励商店头像框',
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '时光币不足，还差 ${frame.cost - achievementProvider.coinBalance}',
          ),
        ),
      );
      return;
    }
    await themeProvider.unlockAvatarFrame(frame.id);
    await themeProvider.setAvatarFrame(frame.id);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('已兑换并启用 ${frame.name}')));
  }

  Future<void> _handleCardSkinTap(
    BuildContext context,
    ThemeProvider themeProvider,
    AchievementProvider achievementProvider,
    CardSkinReward skin,
  ) async {
    final isUnlocked = themeProvider.isCardSkinUnlocked(skin.id);
    if (isUnlocked) {
      await themeProvider.setCardSkin(skin.id);
      return;
    }
    final ok = await achievementProvider.spendCoins(
      coins: skin.cost,
      title: '兑换卡片皮肤：${skin.name}',
      reason: '奖励商店卡片皮肤',
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '时光币不足，还差 ${skin.cost - achievementProvider.coinBalance}',
          ),
        ),
      );
      return;
    }
    await themeProvider.unlockCardSkin(skin.id);
    await themeProvider.setCardSkin(skin.id);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('已兑换并启用 ${skin.name}')));
  }

  Widget _focusBackdropPreview(FocusBackdropReward backdrop) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: backdrop.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
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

  Widget _cardSkinPreview(CardSkinReward skin, ColorScheme cs) {
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Icon(skin.icon, color: cs.onSurface.withValues(alpha: 0.7)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final achievementProvider = context.watch<AchievementProvider>();
    final currentBrand = themeProvider.brand;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(I18n.tr('theme.title'))),
      body: ListView(
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
                              fontWeight: FontWeight.w400,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _styleDescription(currentBrand.style),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.66),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '时光币 ${achievementProvider.coinBalance}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: cs.primary),
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
                    ? accent.withValues(alpha: 0.4)
                    : cs.outlineVariant.withValues(alpha: 0.35),
              ),
              onTap: () => _handleBrandTap(
                context,
                themeProvider,
                achievementProvider,
                brand,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      color: accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _styleName(brand),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _styleDescription(brand.style),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
                  ),
                  const SizedBox(width: 10),
                  Column(
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
                            '$cost 币',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          const AppSectionHeader(
            title: '专注背景',
            subtitle: '用时光币兑换番茄钟卡片装饰',
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
                      colors: [accent.withValues(alpha: 0.12), cs.surface],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              border: Border.all(
                color: isActive
                    ? accent.withValues(alpha: 0.44)
                    : cs.outlineVariant.withValues(alpha: 0.35),
              ),
              onTap: () => _handleFocusBackdropTap(
                context,
                themeProvider,
                achievementProvider,
                backdrop,
              ),
              child: Row(
                children: [
                  _focusBackdropPreview(backdrop),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          backdrop.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          backdrop.description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
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
                            '${backdrop.cost} 币',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          const AppSectionHeader(
            title: '头像框',
            subtitle: '用时光币兑换我的页头像装饰',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          ...themeProvider.avatarFrames.map((frame) {
            final isActive = themeProvider.activeAvatarFrame.id == frame.id;
            final isUnlocked = themeProvider.isAvatarFrameUnlocked(frame.id);
            final accent = frame.colors.first;
            return AppSurfaceCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              gradient: isActive
                  ? LinearGradient(
                      colors: [accent.withValues(alpha: 0.12), cs.surface],
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
              child: Row(
                children: [
                  _avatarFramePreview(frame, cs),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          frame.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          frame.description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
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
                            '${frame.cost} 币',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          const AppSectionHeader(
            title: '卡片皮肤',
            subtitle: '用时光币兑换信息卡片质感',
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
                      colors: [accent.withValues(alpha: 0.18), cs.surface],
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
              child: Row(
                children: [
                  _cardSkinPreview(skin, cs),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          skin.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          skin.description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
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
                            '${skin.cost} 币',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
