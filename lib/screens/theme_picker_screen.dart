import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
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
        return '简洁原版 · 暖橙基调';
      case BrandStyle.re0:
        return '银发魔女 · 露格尼卡圣域';
      case BrandStyle.genshin:
        return '元素绘卷 · 提瓦特画架';
      case BrandStyle.starRail:
        return '星穹列车 · 开拓之旅';
      case BrandStyle.wuthering:
        return '共鸣终端 · 潮声频谱';
      case BrandStyle.zzz:
        return '委托影像 · 新艾利都';
      case BrandStyle.yanyun:
        return '江湖画案 · 墨痕回转';
      case BrandStyle.botw:
        return '希卡之石 · 具现化';
    }
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentBrand = themeProvider.brand;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('主题风格')),
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
                        currentBrand.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
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
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSectionHeader(
            title: '可选风格',
            subtitle: '切换后会同步全局主题',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          ...themeProvider.brands.map((brand) {
            final isActive = brand.style == currentBrand.style;
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
              onTap: () => themeProvider.setBrand(brand.id),
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
                          brand.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
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
                  Icon(
                    isActive
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isActive
                        ? accent
                        : cs.onSurface.withValues(alpha: 0.36),
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
