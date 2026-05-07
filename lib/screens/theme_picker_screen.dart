import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_brand.dart';
import '../providers/theme_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentBrand = themeProvider.brand;

    return Scaffold(
      appBar: AppBar(title: const Text('主题风格')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: themeProvider.brands.length,
        separatorBuilder: (context, index) => const Divider(indent: 72),
        itemBuilder: (_, i) {
          final brand = themeProvider.brands[i];
          final isActive = brand.style == currentBrand.style;
          final accent = _accentColor(brand);

          return ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: isActive ? Border.all(color: accent, width: 2) : null,
              ),
              child: Icon(Icons.palette, color: accent),
            ),
            title: Text(
              brand.name,
              style: TextStyle(fontWeight: FontWeight.w600, color: accent),
            ),
            subtitle: Text(
              _styleDescription(brand.style),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: isActive
                ? Icon(Icons.check_circle, color: accent)
                : const Icon(Icons.circle_outlined, color: Colors.grey),
            onTap: () => themeProvider.setBrand(brand.id),
          );
        },
      ),
    );
  }
}
