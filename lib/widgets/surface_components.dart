import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/theme_provider.dart';

/// 当前主题的表面观感档位。
///
/// 默认 iOS 与液态玻璃主题注册了各自的表面档位；re0..botw 未注册，返回 null，
/// 调用点沿用下方 `_standard*` 既有默认值，观感保持不变。
AppSurfaceStyle? appSurfaceStyleOf(BuildContext context) =>
    Theme.of(context).extension<AppSurfaceStyle>();

// 既有通用档（未注册 AppSurfaceStyle 的主题沿用），与改造前逐值一致。
const BorderRadius _standardCardRadius = BorderRadius.all(
  Radius.circular(DesignTokens.radiusCard),
);
const BorderRadius _standardMetricTileRadius = BorderRadius.all(
  Radius.circular(DesignTokens.radiusMd),
);
const double _standardSheetTopRadius = 20;
const BorderRadius _standardSettingsSectionRadius = BorderRadius.all(
  Radius.circular(8),
);

class AppSurfaceCard extends StatelessWidget {
  static const int _maxAllocCacheEntries = 32;
  static final LinkedHashMap<(int, int, bool), LinearGradient>
  _defaultGradientCache = LinkedHashMap<(int, int, bool), LinearGradient>();
  static final LinkedHashMap<(int, bool), WidgetStateProperty<Color?>>
  _overlayColorCache =
      LinkedHashMap<(int, bool), WidgetStateProperty<Color?>>();

  static LinearGradient _cachedDefaultGradient(Color primary, Color surface, bool isDark) {
    final key = (primary.toARGB32(), surface.toARGB32(), isDark);
    final existing = _defaultGradientCache.remove(key);
    if (existing != null) {
      _defaultGradientCache[key] = existing;
      return existing;
    }
    final gradient = LinearGradient(
      colors: [
        Color.alphaBlend(primary.withValues(alpha: isDark ? 0.045 : 0.025), surface),
        surface,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    if (_defaultGradientCache.length >= _maxAllocCacheEntries) {
      _defaultGradientCache.remove(_defaultGradientCache.keys.first);
    }
    _defaultGradientCache[key] = gradient;
    return gradient;
  }

  static WidgetStateProperty<Color?> _cachedOverlayColor(Color primary, bool isDark) {
    final key = (primary.toARGB32(), isDark);
    final existing = _overlayColorCache.remove(key);
    if (existing != null) {
      _overlayColorCache[key] = existing;
      return existing;
    }
    final property = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: isDark ? 0.14 : 0.08);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return primary.withValues(alpha: isDark ? 0.08 : 0.045);
      }
      return Colors.transparent;
    });
    if (_overlayColorCache.length >= _maxAllocCacheEntries) {
      _overlayColorCache.remove(_overlayColorCache.keys.first);
    }
    _overlayColorCache[key] = property;
    return property;
  }

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  /// null 时取主题观感档位（默认主题 iOS 档 16，其余主题 radiusCard 12）。
  final BorderRadius? borderRadius;
  final Border? border;
  final double elevation;
  final List<BoxShadow>? boxShadow;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.gradient,
    this.borderRadius,
    this.border,
    this.elevation = 0,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final effectiveRadius =
        borderRadius ??
        (surfaceStyle == null
            ? _standardCardRadius
            : BorderRadius.circular(surfaceStyle.cardRadius));
    CardSkinReward? cardSkin;
    try {
      cardSkin = context.select<ThemeProvider, CardSkinReward>(
        (provider) => provider.activeCardSkin,
      );
    } catch (_) {
      cardSkin = null;
    }
    final useCardSkin =
        cardSkin != null &&
        cardSkin.id != ThemeProvider.defaultCardSkinId &&
        color == null &&
        gradient == null;
    final surfaceColor = color ?? cs.surface;
    // 液态玻璃主题：默认填充换成半透明白玻璃（调用方传 color 时豁免——
    // 选中态 / 横幅等语义色优先；性能优先走伪玻璃填充，不做逐卡模糊）。
    final effectiveFillColor =
        (color == null ? surfaceStyle?.cardFillColor : null) ?? surfaceColor;
    final defaultGradient =
        color == null && !useCardSkin && surfaceStyle?.cardFillColor == null
        ? _cachedDefaultGradient(cs.primary, surfaceColor, isDark)
        : null;
    final cardBorderColor = isDark
        ? cs.outlineVariant.withValues(alpha: 0.18)
        : (Color.lerp(DesignTokens.defaultBorder, cs.outlineVariant, 0.35) ??
                  DesignTokens.defaultBorder)
              .withValues(alpha: 0.72);
    final skinGradient = useCardSkin
        ? LinearGradient(
            colors: [
              cardSkin.colors.first.withValues(alpha: isDark ? 0.22 : 0.18),
              cardSkin.colors.last.withValues(alpha: isDark ? 0.18 : 0.12),
              cs.surface.withValues(alpha: isDark ? 0.94 : 0.96),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;
    final decoration = BoxDecoration(
      color: gradient == null && skinGradient == null && defaultGradient == null
          ? effectiveFillColor
          : null,
      gradient: gradient ?? skinGradient ?? defaultGradient,
      borderRadius: effectiveRadius,
      // 默认主题 iOS 档：去描边，改由 cardShadow 提供极淡层次；
      // 液态玻璃主题：白色高光描边；其余主题沿用 defaultBorder 淡描边。
      border:
          border ??
          (useCardSkin
              ? Border.all(
                  color: cardSkin.colors.first.withValues(alpha: 0.10),
                  width: 0.55,
                )
              : surfaceStyle?.cardBorder ??
                    Border.all(color: cardBorderColor, width: 0.55)),
      boxShadow:
          boxShadow ??
          (elevation <= 0
              ? (surfaceStyle?.cardShadow ?? const [])
              : [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.12 : 0.035,
                    ),
                    blurRadius: 5.5 + elevation,
                    offset: const Offset(0, 1.5),
                  ),
                ]),
    );

    final content = Ink(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: effectiveRadius,
                overlayColor: _cachedOverlayColor(cs.primary, isDark),
                child: content,
              ),
      ),
    );
  }
}

TextStyle appSecondaryControlTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.2,
  );
}

TextStyle appSecondaryControlLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
    fontSize: 11,
    fontWeight: DesignTokens.fontWeightRegular,
    height: 1.16,
  );
}

TextStyle appSecondaryMenuItemTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.18,
  );
}

TextStyle appSecondaryRouteTitleTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
    fontSize: DesignTokens.fontSizeMd,
    fontWeight: FontWeight.normal,
    color: cs.onSurface,
    height: 1.2,
  );
}

/// Helper for settings and surface description / subtitle foreground colors.
///
/// Ensures descriptions achieve WCAG AA >=4.5:1 contrast on known light
/// default and liquid glass surfaces with plain card skin (alpha 0.72 for
/// regular descriptions, alpha 0.74 for hero subtitles), while preserving
/// legacy alpha (0.62 / 0.66) on dark mode, non-plain skins, or other themes.
Color appSecondaryDescriptionColor(
  BuildContext context, {
  bool isHero = false,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final surfaceStyle = appSurfaceStyleOf(context);
  final cs = theme.colorScheme;
  if (isDark || surfaceStyle == null) {
    return cs.onSurface.withValues(alpha: isHero ? 0.66 : 0.62);
  }

  try {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final brandId = themeProvider.brand.id;
    final isSupportedBrand =
        brandId == 'defaultBrand' || brandId == 'liquidGlass';
    final isPlainSkin =
        themeProvider.activeCardSkin.id == ThemeProvider.defaultCardSkinId;
    if (isSupportedBrand && isPlainSkin) {
      return cs.onSurface.withValues(alpha: isHero ? 0.74 : 0.72);
    }
  } catch (_) {
    // 无 provider 时安全回退现有路径
  }

  return cs.onSurface.withValues(alpha: isHero ? 0.66 : 0.62);
}

Color _appSecondaryActionBackground(ColorScheme cs, {required bool isDark}) {
  final base = cs.primary;
  const darkForeground = Color(0xFF111827);
  if (_appContrastRatio(base, Colors.white) >= 4.5 ||
      _appContrastRatio(base, darkForeground) >= 4.5) {
    return base;
  }
  final target = isDark ? Colors.white : Colors.black;
  for (final amount in const [0.10, 0.16, 0.22, 0.30, 0.38]) {
    final candidate = Color.lerp(base, target, amount) ?? base;
    if (_appContrastRatio(candidate, Colors.white) >= 4.5 ||
        _appContrastRatio(candidate, darkForeground) >= 4.5) {
      return candidate;
    }
  }
  return Color.lerp(base, target, isDark ? 0.38 : 0.30) ?? base;
}

Color _appSecondaryActionForeground(Color background) {
  return _appReadableForeground(background, Colors.white);
}

/// Calculates contrast ratio between two already-composited (opaque) colors
/// according to WCAG 2.1.
///
/// Both [a] and [b] must be fully resolved / composited against their underlying
/// surface before calling this function. For translucent colors, blend them
/// first via [Color.alphaBlend].
double appContrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Chooses a readable foreground color for [background].
///
/// 1. Prioritizes [preferred] when its actual composited appearance
///    ([Color.alphaBlend(preferred, background)]) achieves at least 4.5:1
///    contrast against [background] (WCAG 2.1 AA normal text).
/// 2. If [preferred] does not meet 4.5:1, chooses between the legacy high-contrast
///    dark token (`#111827`) and [Colors.white] if the higher-contrast option
///    achieves at least 4.5:1.
/// 3. If neither dark (`#111827`) nor white reaches 4.5:1 (e.g. on mid-tone
///    backgrounds such as default primary red `#C85656` where white is ~4.267:1
///    and `#111827` is ~4.157:1), falls back to pure [Colors.black] (~4.921:1 on red).
Color appReadableForeground(Color background, Color preferred) {
  final effectivePreferred = Color.alphaBlend(preferred, background);
  if (appContrastRatio(background, effectivePreferred) >= 4.5) return preferred;

  const dark = Color(0xFF111827);
  final darkContrast = appContrastRatio(background, dark);
  final whiteContrast = appContrastRatio(background, Colors.white);
  final bestContrast = darkContrast >= whiteContrast
      ? darkContrast
      : whiteContrast;
  final bestCandidate = darkContrast >= whiteContrast ? dark : Colors.white;

  if (bestContrast >= 4.5) {
    return bestCandidate;
  }
  return Colors.black;
}

Color _appReadableForeground(Color background, Color preferred) =>
    appReadableForeground(background, preferred);

double _appContrastRatio(Color a, Color b) => appContrastRatio(a, b);

ButtonStyle appSecondaryFilledButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final background = _appSecondaryActionBackground(
    cs,
    isDark: theme.brightness == Brightness.dark,
  );
  final disabledBackground =
      Color.lerp(
        cs.surfaceContainerHighest,
        background,
        theme.brightness == Brightness.dark ? 0.22 : 0.18,
      ) ??
      cs.surfaceContainerHighest;
  final surfaceStyle = appSurfaceStyleOf(context);
  final shape = surfaceStyle == null
      ? null
      : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(surfaceStyle.smallTileRadius),
        );
  return FilledButton.styleFrom(
    backgroundColor: background,
    foregroundColor: _appSecondaryActionForeground(background),
    disabledBackgroundColor: disabledBackground,
    disabledForegroundColor: _appReadableForeground(
      disabledBackground,
      cs.onSurfaceVariant,
    ).withValues(alpha: 0.70),
    side: BorderSide(color: background.withValues(alpha: 0.16), width: 0.45),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    minimumSize: const Size(0, 34),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    textStyle: appSecondaryMenuItemTextStyle(context),
    shape: shape,
  );
}

class AppSecondaryControlTheme extends StatelessWidget {
  final Widget child;

  const AppSecondaryControlTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final controlText = appSecondaryControlTextStyle(context);
    final labelText = appSecondaryControlLabelStyle(context);
    final surfaceStyle = appSurfaceStyleOf(context);
    final controlRadius =
        surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
    final buttonShape = surfaceStyle == null
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(surfaceStyle.smallTileRadius),
          );
    OutlineInputBorder inputBorder(Color color, {double width = 0.35}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final subtleBorder = cs.outlineVariant.withValues(
      alpha: isDark ? 0.12 : 0.16,
    );
    final selectedControlBackground = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.14 : 0.09),
      cs.surface,
    );
    final selectedControlRenderedBackground = Color.alphaBlend(
      selectedControlBackground,
      cs.surface,
    );
    final selectedControlForeground = _appReadableForeground(
      selectedControlRenderedBackground,
      cs.onSurface,
    );
    final selectedControlIcon = _appReadableForeground(
      selectedControlRenderedBackground,
      cs.primary,
    );
    final isPriorityTheme =
        !isDark &&
        (surfaceStyle == AppSurfaceStyle.ios ||
            surfaceStyle == AppSurfaceStyle.liquidGlass);
    final scaffoldBackground = theme.scaffoldBackgroundColor;
    final cardFill = surfaceStyle?.cardFillColor;
    final cardBackground = cardFill != null
        ? Color.alphaBlend(cardFill, scaffoldBackground)
        : cs.surface;
    final candidateBackgrounds = <Color>[scaffoldBackground, cardBackground];
    final fieldFill = theme.inputDecorationTheme.fillColor;
    if (fieldFill != null) {
      candidateBackgrounds.add(Color.alphaBlend(fieldFill, cardBackground));
    }
    Color lowestContrastBg = scaffoldBackground;
    double lowestContrast = double.infinity;
    for (final bg in candidateBackgrounds) {
      final ratio = appContrastRatio(bg, cs.primary);
      if (ratio < lowestContrast) {
        lowestContrast = ratio;
        lowestContrastBg = bg;
      }
    }
    final floatingLabelColor = isPriorityTheme
        ? (lowestContrast >= 4.5
              ? cs.primary
              : _appReadableForeground(lowestContrastBg, cs.primary))
        : cs.primary;
    return Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        textTheme: theme.textTheme.copyWith(
          titleMedium: controlText.copyWith(color: cs.onSurface),
          titleSmall: controlText.copyWith(color: cs.onSurface),
          bodyLarge: controlText.copyWith(color: cs.onSurface),
          bodyMedium: controlText.copyWith(color: cs.onSurface),
          bodySmall: labelText.copyWith(color: cs.onSurfaceVariant),
          labelLarge: labelText.copyWith(color: cs.onSurface),
          labelMedium: labelText.copyWith(color: cs.onSurface),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 34,
            height: 34,
          ),
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: 34,
            height: 34,
          ),
          labelStyle: labelText.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.normal,
          ),
          floatingLabelStyle: labelText.copyWith(
            color: floatingLabelColor,
            fontWeight: FontWeight.normal,
          ),
          hintStyle: controlText.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.68),
            fontWeight: FontWeight.normal,
          ),
          border: inputBorder(subtleBorder),
          enabledBorder: inputBorder(subtleBorder),
          disabledBorder: inputBorder(
            cs.outlineVariant.withValues(alpha: isDark ? 0.045 : 0.06),
          ),
          focusedBorder: inputBorder(
            cs.primary.withValues(alpha: isDark ? 0.16 : 0.12),
            width: 0.4,
          ),
          errorBorder: inputBorder(cs.error.withValues(alpha: 0.24)),
          focusedErrorBorder: inputBorder(
            cs.error.withValues(alpha: 0.30),
            width: 0.4,
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          dense: true,
          titleTextStyle: controlText.copyWith(color: cs.onSurface),
          subtitleTextStyle: labelText.copyWith(color: cs.onSurfaceVariant),
        ),
        dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
          textStyle: controlText.copyWith(color: cs.onSurface),
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
        popupMenuTheme: theme.popupMenuTheme.copyWith(
          textStyle: controlText.copyWith(color: cs.onSurface),
          labelTextStyle: WidgetStatePropertyAll(
            controlText.copyWith(color: cs.onSurface),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: controlText,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: buttonShape,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: controlText,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            shape: buttonShape,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: controlText,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            side: BorderSide(color: subtleBorder, width: 0.4),
            shape: buttonShape,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: appSecondaryFilledButtonStyle(
            context,
          ).copyWith(textStyle: WidgetStatePropertyAll(controlText)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: buttonShape == null
                ? null
                : WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
            textStyle: WidgetStatePropertyAll(controlText),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return cs.onSurface.withValues(alpha: 0.38);
              }
              if (states.contains(WidgetState.selected)) {
                return selectedControlForeground;
              }
              return cs.onSurface;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return selectedControlBackground;
              }
              return Colors.transparent;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              final color = states.contains(WidgetState.selected)
                  ? cs.primary.withValues(alpha: isDark ? 0.34 : 0.30)
                  : subtleBorder;
              return BorderSide(color: color, width: 0.4);
            }),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: labelText.copyWith(color: cs.onSurface),
          secondaryLabelStyle: labelText.copyWith(
            color: selectedControlForeground,
          ),
          selectedColor: selectedControlBackground,
          checkmarkColor: selectedControlIcon,
          iconTheme: IconThemeData(size: 16, color: selectedControlIcon),
          side: BorderSide(color: subtleBorder, width: 0.4),
        ),
      ),
      child: DefaultTextStyle.merge(style: controlText, child: child),
    );
  }
}

class AppSecondaryMenuText extends StatelessWidget {
  final String text;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppSecondaryMenuText(
    this.text, {
    super.key,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: appSecondaryMenuItemTextStyle(
        context,
      ).copyWith(color: color ?? cs.onSurface, fontWeight: FontWeight.normal),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  final TextStyle? titleStyle;
  final TextStyle? actionTextStyle;
  final bool wrapText;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 12, 8),
    this.titleStyle,
    this.actionTextStyle,
    this.wrapText = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: wrapText ? null : 2,
          overflow: wrapText ? TextOverflow.visible : TextOverflow.ellipsis,
          style:
              titleStyle ??
              appSecondaryMenuItemTextStyle(context).copyWith(
                color: cs.onSurface,
                fontSize: DesignTokens.fontSizeSection,
              ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: wrapText ? null : 2,
            overflow: wrapText ? TextOverflow.visible : TextOverflow.ellipsis,
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: appSecondaryDescriptionColor(context)),
          ),
        ],
      ],
    );
    final action = onAction == null || actionLabel == null
        ? null
        : TextButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon ?? Icons.chevron_right, size: 16),
            label: Text(
              actionLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              foregroundColor: cs.primary,
              textStyle:
                  actionTextStyle ??
                  theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          );
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (action == null) return titleColumn;
          if (constraints.maxWidth < 290) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleColumn,
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: action,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: (subtitle == null || subtitle!.isEmpty)
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Expanded(child: titleColumn),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth * 0.42).clamp(96.0, 180.0),
                ),
                child: action,
              ),
            ],
          );
        },
      ),
    );
  }
}

class AppStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.maxWidth = 180,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = Color.alphaBlend(
      filled ? color : color.withValues(alpha: 0.12),
      theme.colorScheme.surface,
    );
    final fg = _appReadableForeground(bg, filled ? Colors.white : color);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.normal,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppInfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final String? title;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const AppInfoBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.title,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppSurfaceCard(
      margin: margin,
      padding: padding,
      onTap: onTap,
      color: color.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08,
      ),
      border: Border.all(color: color.withValues(alpha: 0.10), width: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  /// null 时取主题观感档位（默认主题 iOS 控件档 12，其余主题 radiusMd 10）。
  final BorderRadius? borderRadius;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final TextStyle? titleStyle;
  final int? titleMaxLines;
  final double iconBoxSize;
  final double iconSize;

  const AppMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.borderRadius,
    this.valueStyle,
    this.unitStyle,
    this.titleStyle,
    this.titleMaxLines = 1,
    this.iconBoxSize = 28,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final effectiveRadius =
        borderRadius ??
        (surfaceStyle == null
            ? _standardMetricTileRadius
            : BorderRadius.circular(surfaceStyle.smallTileRadius));
    // 液态玻璃档：小卡与卡面（AppSurfaceCard）、Material Card 共用同一
    // 玻璃填充档（cardFillColor = 白@glassFillLightAlpha），三类卡面质感
    // 一致。其余主题未注册 cardFillColor（null）、暗色无玻璃档，均维持
    // 既有实底档，观感不变。
    final fill =
        (!isDark ? surfaceStyle?.cardFillColor : null) ??
        (isDark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.05),
                cs.surface,
              )
            : cs.surface.withValues(alpha: 0.85));
    // 玻璃体系统一：亮色下小卡描边/阴影与卡面、Material Card 同走
    // AppSurfaceStyle 玻璃档（cardBorder / cardShadow），三类卡面同屏
    // 同质感；未注册主题与暗色维持既有灰描边、无阴影档，观感不变。
    final tileBorder =
        (!isDark ? surfaceStyle?.cardBorder : null) ??
        Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.15 : 0.18),
          width: 0.5,
        );
    final tileShadow = (!isDark ? surfaceStyle?.cardShadow : null) ?? const [];
    final tile = Ink(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: effectiveRadius,
        border: tileBorder,
        boxShadow: tileShadow,
      ),
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: titleMaxLines,
                    overflow: titleMaxLines == null
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style:
                        titleStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: appSecondaryDescriptionColor(context),
                          fontWeight: FontWeight.normal,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style:
                              (valueStyle ??
                                      theme.textTheme.titleMedium?.copyWith(
                                        fontSize: DesignTokens.fontSizeMd,
                                        fontWeight: FontWeight.normal,
                                        color: cs.onSurface,
                                        height: 1.1,
                                      ))
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                        ),
                        if (unit != null && unit!.isNotEmpty)
                          TextSpan(
                            text: unit == '%' ? '%' : ' $unit',
                            style:
                                unitStyle ??
                                theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.normal,
                                  color: appSecondaryDescriptionColor(context),
                                  height: 1.08,
                                ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? tile
            : InkWell(
                onTap: onTap,
                borderRadius: effectiveRadius,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return color.withValues(alpha: isDark ? 0.16 : 0.09);
                  }
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return color.withValues(alpha: isDark ? 0.09 : 0.05);
                  }
                  return Colors.transparent;
                }),
                child: tile,
              ),
      ),
    );
  }
}

class AppActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 14, 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isDark = theme.brightness == Brightness.dark;

    final scaffoldBg = theme.scaffoldBackgroundColor;
    final cardFill = surfaceStyle?.cardFillColor;
    final cardBg = cardFill != null
        ? Color.alphaBlend(cardFill, scaffoldBg)
        : cs.surface;
    final candidateSurfaces = <Color>[scaffoldBg, cardBg];

    Color resolveActionForeground(Color base) {
      bool meetsAll(Color c) {
        for (final surface in candidateSurfaces) {
          if (appContrastRatio(surface, c) < 4.5) return false;
        }
        return true;
      }

      if (meetsAll(base)) return base;

      final target = isDark ? Colors.white : Colors.black;
      for (final amount in const [0.10, 0.16, 0.22, 0.30, 0.38, 0.48]) {
        final candidate = Color.lerp(base, target, amount) ?? base;
        if (meetsAll(candidate)) return candidate;
      }

      Color worstSurface = scaffoldBg;
      double worstRatio = double.infinity;
      for (final surface in candidateSurfaces) {
        final r = appContrastRatio(surface, base);
        if (r < worstRatio) {
          worstRatio = r;
          worstSurface = surface;
        }
      }
      return appReadableForeground(worstSurface, base);
    }

    final actionForeground = resolveActionForeground(cs.primary);

    final resolvedPadding = padding.resolve(Directionality.maybeOf(context));
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: cs.onSurface,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: appSecondaryDescriptionColor(context),
    );

    final titleText = Text(label, style: titleStyle);
    final subtitleText = hasSubtitle
        ? Text(subtitle!, style: subtitleStyle)
        : null;

    final textColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleText,
        if (subtitleText != null) ...[const SizedBox(height: 2), subtitleText],
      ],
    );

    final leading = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );

    final defaultChevron = Icon(
      Icons.chevron_right,
      size: 18,
      color: cs.onSurface.withValues(alpha: 0.38),
    );

    final isActionTrailing = trailing != null && trailing is! Icon;
    final effectiveTrailing = trailing ?? defaultChevron;

    final existingTheme = TextButtonTheme.of(context).style;
    final effectiveButtonStyle =
        (existingTheme ??
                TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ))
            .copyWith(
              foregroundColor: WidgetStatePropertyAll(actionForeground),
              minimumSize: WidgetStateProperty.resolveWith((states) {
                final existing = existingTheme?.minimumSize?.resolve(states);
                if (existing == null) return const Size(44, 44);
                return Size(
                  math.max(existing.width, 44.0),
                  math.max(existing.height, 44.0),
                );
              }),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            );

    final themedTrailing = isActionTrailing
        ? TextButtonTheme(
            data: TextButtonThemeData(style: effectiveButtonStyle),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: effectiveTrailing,
            ),
          )
        : effectiveTrailing;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final textDirection =
                  Directionality.maybeOf(context) ?? TextDirection.ltr;

              final totalWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : 360.0;
              final availableContentWidth = math.max(
                0.0,
                totalWidth - resolvedPadding.horizontal - 52.0,
              );

              bool shouldStack = false;
              if (isActionTrailing) {
                String? buttonText;
                if (trailing is TextButton &&
                    (trailing as TextButton).child is Text) {
                  buttonText = ((trailing as TextButton).child as Text).data;
                }
                double trailingWidth = 80.0;
                final textScale = textScaler.scale(14) / 14;
                if (buttonText != null && buttonText.isNotEmpty) {
                  final actionPainter = TextPainter(
                    text: TextSpan(
                      text: buttonText,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontSize: 12,
                      ),
                    ),
                    textDirection: textDirection,
                    textScaler: textScaler,
                  )..layout();
                  trailingWidth = math.max(44.0, actionPainter.width + 24.0);
                  actionPainter.dispose();
                } else {
                  trailingWidth = math.max(44.0, 72.0 * textScale);
                }

                final availableInlineTextW =
                    availableContentWidth - trailingWidth - 8.0;

                final titlePainter = TextPainter(
                  text: TextSpan(text: label, style: titleStyle),
                  textDirection: textDirection,
                  textScaler: textScaler,
                )..layout();
                final longestTitleWord = titlePainter.minIntrinsicWidth;
                titlePainter.dispose();

                double longestSubtitleWord = 0.0;
                if (hasSubtitle) {
                  final subtitlePainter = TextPainter(
                    text: TextSpan(text: subtitle!, style: subtitleStyle),
                    textDirection: textDirection,
                    textScaler: textScaler,
                  )..layout();
                  longestSubtitleWord = subtitlePainter.minIntrinsicWidth;
                  subtitlePainter.dispose();
                }

                final longestWordWidth = math.max(
                  longestTitleWord,
                  longestSubtitleWord,
                );

                shouldStack =
                    availableInlineTextW < longestWordWidth ||
                    availableInlineTextW < 120.0 ||
                    (availableContentWidth < 240.0 && textScale > 1.3);
              }

              if (shouldStack) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        leading,
                        const SizedBox(width: 12),
                        Expanded(child: textColumn),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: themedTrailing,
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 12),
                  Expanded(child: textColumn),
                  const SizedBox(width: 8),
                  themedTrailing,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class AppSettingsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final double elevation;
  final bool showDividers;

  const AppSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.elevation = 0,
    this.showDividers = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final spacedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spacedChildren.add(children[i]);
      if (showDividers &&
          i < children.length - 1 &&
          children[i] is! Divider &&
          children[i + 1] is! Divider) {
        spacedChildren.add(
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 48,
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.24 : 0.35),
          ),
        );
      }
    }
    return AppSurfaceCard(
      margin: margin,
      padding: padding,
      border: border,
      elevation: elevation,
      // 默认主题 iOS 档取卡片圆角 16，其余主题沿用既有 8。
      borderRadius: surfaceStyle == null
          ? _standardSettingsSectionRadius
          : BorderRadius.circular(surfaceStyle.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: title,
            subtitle: subtitle,
            padding: EdgeInsets.zero,
            wrapText: true,
          ),
          const SizedBox(height: 10),
          ...spacedChildren,
        ],
      ),
    );
  }
}

class AppSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fallback = Icon(
      Icons.chevron_right,
      size: 18,
      color: cs.onSurface.withValues(alpha: 0.38),
    );

    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final rowMinHeight = hasSubtitle ? 54.0 : 42.0;
    final leading = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );
    final titleText = Text(
      title,
      style: appSecondaryMenuItemTextStyle(context).copyWith(
        color: cs.onSurface,
        fontWeight: DesignTokens.fontWeightRegular,
      ),
    );
    final subtitleStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: appSecondaryDescriptionColor(context));
    final subtitleText = Text(subtitle ?? '', style: subtitleStyle);
    final textBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleText,
        if (hasSubtitle) ...[const SizedBox(height: 2), subtitleText],
      ],
    );

    final media = MediaQuery.maybeOf(context);
    final textScale = media != null ? media.textScaler.scale(14) / 14 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: padding,
          child: _AppSettingsTileLayout(
            minRowHeight: rowMinHeight,
            hasTrailing: trailing != null,
            textScale: textScale,
            leading: leading,
            text: textBlock,
            trailing: trailing ?? fallback,
          ),
        ),
      ),
    );
  }
}

enum _SettingsTileSlot { leading, text, trailing }

class _SettingsTileParentData extends ContainerBoxParentData<RenderBox> {
  _SettingsTileSlot? slot;
}

class _SettingsTileSlotWidget
    extends ParentDataWidget<_SettingsTileParentData> {
  final _SettingsTileSlot slot;
  const _SettingsTileSlotWidget({required this.slot, required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData as _SettingsTileParentData;
    if (parentData.slot != slot) {
      parentData.slot = slot;
      final targetParent = renderObject.parent;
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _AppSettingsTileLayout;
}

class _TileLayoutCalculation {
  final Size size;
  final Offset leadingOffset;
  final Offset textOffset;
  final Offset trailingOffset;

  const _TileLayoutCalculation({
    required this.size,
    required this.leadingOffset,
    required this.textOffset,
    required this.trailingOffset,
  });
}

class _AppSettingsTileLayout extends MultiChildRenderObjectWidget {
  final double minRowHeight;
  final bool hasTrailing;
  final double textScale;

  _AppSettingsTileLayout({
    required Widget leading,
    required Widget text,
    required Widget trailing,
    required this.minRowHeight,
    required this.hasTrailing,
    required this.textScale,
  }) : super(
         children: [
           _SettingsTileSlotWidget(
             slot: _SettingsTileSlot.leading,
             child: leading,
           ),
           _SettingsTileSlotWidget(slot: _SettingsTileSlot.text, child: text),
           _SettingsTileSlotWidget(
             slot: _SettingsTileSlot.trailing,
             child: trailing,
           ),
         ],
       );

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAppSettingsTile(
      minRowHeight: minRowHeight,
      hasTrailing: hasTrailing,
      textScale: textScale,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAppSettingsTile renderObject,
  ) {
    renderObject
      ..minRowHeight = minRowHeight
      ..hasTrailing = hasTrailing
      ..textScale = textScale;
  }
}

class _RenderAppSettingsTile extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SettingsTileParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SettingsTileParentData> {
  double _minRowHeight;
  bool _hasTrailing;
  double _textScale;

  _RenderAppSettingsTile({
    required double minRowHeight,
    required bool hasTrailing,
    required double textScale,
  }) : _minRowHeight = minRowHeight,
       _hasTrailing = hasTrailing,
       _textScale = textScale;

  double get minRowHeight => _minRowHeight;
  set minRowHeight(double value) {
    if (_minRowHeight == value) return;
    _minRowHeight = value;
    markNeedsLayout();
  }

  bool get hasTrailing => _hasTrailing;
  set hasTrailing(bool value) {
    if (_hasTrailing == value) return;
    _hasTrailing = value;
    markNeedsLayout();
  }

  double get textScale => _textScale;
  set textScale(double value) {
    if (_textScale == value) return;
    _textScale = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SettingsTileParentData) {
      child.parentData = _SettingsTileParentData();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  _TileLayoutCalculation _computeTileLayout(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;

    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as _SettingsTileParentData;
      switch (childParentData.slot) {
        case _SettingsTileSlot.leading:
          leading = child;
        case _SettingsTileSlot.text:
          text = child;
        case _SettingsTileSlot.trailing:
          trailing = child;
        case null:
          break;
      }
      child = childParentData.nextSibling;
    }

    if (leading == null || text == null || trailing == null) {
      return _TileLayoutCalculation(
        size: constraints.smallest,
        leadingOffset: Offset.zero,
        textOffset: Offset.zero,
        trailingOffset: Offset.zero,
      );
    }

    final maxW = constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
    if (!dry) {
      leading.layout(
        const BoxConstraints.tightFor(width: 34, height: 34),
        parentUsesSize: true,
      );
    }

    final Size trailingSize;
    if (dry) {
      trailingSize = trailing.getDryLayout(BoxConstraints(maxWidth: maxW));
    } else {
      trailing.layout(BoxConstraints(maxWidth: maxW), parentUsesSize: true);
      trailingSize = trailing.size;
    }
    final trailingW = trailingSize.width;
    final trailingH = trailingSize.height;

    final spacingBeforeTrailing = trailingW > 0.0 ? 8.0 : 0.0;
    final availableInlineTextW =
        maxW - 34.0 - 10.0 - spacingBeforeTrailing - trailingW;
    final shouldStack =
        hasTrailing &&
        trailingW > 0.0 &&
        ((maxW < 360.0 && textScale > 1.3) ||
            (availableInlineTextW < 160.0 && trailingW > 90.0) ||
            availableInlineTextW < 110.0);

    if (shouldStack) {
      final textW = (maxW - 44.0).clamp(0.0, maxW);
      final Size textSize;
      if (dry) {
        textSize = text.getDryLayout(BoxConstraints(maxWidth: textW));
      } else {
        text.layout(BoxConstraints(maxWidth: textW), parentUsesSize: true);
        textSize = text.size;
      }
      final textH = textSize.height;

      final row1H = textH > 34.0 ? textH : 34.0;
      final leadingTop = (row1H - 34.0) / 2;
      final textTop = (row1H - textH) / 2;

      final trailingTop = row1H + 4.0;
      final trailingLeft = (maxW - trailingW).clamp(0.0, maxW);

      final naturalH = trailingTop + trailingH;
      final totalH = naturalH > minRowHeight ? naturalH : minRowHeight;
      final constrainedSize = constraints.constrain(Size(maxW, totalH));

      return _TileLayoutCalculation(
        size: constrainedSize,
        leadingOffset: Offset(0, leadingTop),
        textOffset: Offset(44.0, textTop),
        trailingOffset: Offset(trailingLeft, trailingTop),
      );
    } else {
      final textW = availableInlineTextW.clamp(0.0, maxW);
      final Size textSize;
      if (dry) {
        textSize = text.getDryLayout(BoxConstraints(maxWidth: textW));
      } else {
        text.layout(BoxConstraints(maxWidth: textW), parentUsesSize: true);
        textSize = text.size;
      }
      final textH = textSize.height;

      final naturalH = [textH, 34.0, trailingH].reduce((a, b) => a > b ? a : b);
      final totalH = naturalH > minRowHeight ? naturalH : minRowHeight;

      final textTop = (totalH - textH) / 2;
      final textCenterDy = textTop + textH / 2;

      final leadingTop = textCenterDy - 17.0;
      final trailingTop = textCenterDy - trailingH / 2;
      final trailingLeft = maxW - trailingW;

      final constrainedSize = constraints.constrain(Size(maxW, totalH));

      return _TileLayoutCalculation(
        size: constrainedSize,
        leadingOffset: Offset(0, leadingTop),
        textOffset: Offset(44.0, textTop),
        trailingOffset: Offset(trailingLeft, trailingTop),
      );
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _computeTileLayout(constraints, dry: true).size;
  }

  @override
  void performLayout() {
    final result = _computeTileLayout(constraints, dry: false);
    size = result.size;

    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;
    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as _SettingsTileParentData;
      switch (childParentData.slot) {
        case _SettingsTileSlot.leading:
          leading = child;
        case _SettingsTileSlot.text:
          text = child;
        case _SettingsTileSlot.trailing:
          trailing = child;
        case null:
          break;
      }
      child = childParentData.nextSibling;
    }

    if (leading != null) {
      (leading.parentData! as _SettingsTileParentData).offset =
          result.leadingOffset;
    }
    if (text != null) {
      (text.parentData! as _SettingsTileParentData).offset = result.textOffset;
    }
    if (trailing != null) {
      (trailing.parentData! as _SettingsTileParentData).offset =
          result.trailingOffset;
    }
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return computeDryLayout(BoxConstraints(maxWidth: width)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return computeDryLayout(BoxConstraints(maxWidth: width)).height;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;
    RenderBox? child = firstChild;
    while (child != null) {
      final pData = child.parentData! as _SettingsTileParentData;
      if (pData.slot == _SettingsTileSlot.leading) leading = child;
      if (pData.slot == _SettingsTileSlot.text) text = child;
      if (pData.slot == _SettingsTileSlot.trailing) trailing = child;
      child = pData.nextSibling;
    }
    final leadW = leading?.getMinIntrinsicWidth(height) ?? 34.0;
    final textW = text?.getMinIntrinsicWidth(height) ?? 0.0;
    final trailW = trailing?.getMinIntrinsicWidth(height) ?? 0.0;
    final spacing = trailW > 0.0 ? 8.0 : 0.0;
    return leadW + 10.0 + textW + spacing + trailW;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;
    RenderBox? child = firstChild;
    while (child != null) {
      final pData = child.parentData! as _SettingsTileParentData;
      if (pData.slot == _SettingsTileSlot.leading) leading = child;
      if (pData.slot == _SettingsTileSlot.text) text = child;
      if (pData.slot == _SettingsTileSlot.trailing) trailing = child;
      child = pData.nextSibling;
    }
    final leadW = leading?.getMaxIntrinsicWidth(height) ?? 34.0;
    final textW = text?.getMaxIntrinsicWidth(height) ?? 0.0;
    final trailW = trailing?.getMaxIntrinsicWidth(height) ?? 0.0;
    final spacing = trailW > 0.0 ? 8.0 : 0.0;
    return leadW + 10.0 + textW + spacing + trailW;
  }
}

class AppListTileCard extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;
  final bool dense;
  final bool isThreeLine;
  final Border? border;
  final double elevation;

  const AppListTileCard({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 4,
    ),
    this.dense = false,
    this.isThreeLine = false,
    this.border,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceStyle = appSurfaceStyleOf(context);
    return AppSurfaceCard(
      margin: margin,
      padding: EdgeInsets.zero,
      onTap: onTap,
      border: border,
      elevation: elevation,
      child: Material(
        color: Colors.transparent,
        borderRadius: surfaceStyle == null
            ? _standardCardRadius
            : BorderRadius.circular(surfaceStyle.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: dense,
          isThreeLine: isThreeLine,
          contentPadding: contentPadding,
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
      ),
    );
  }
}

class AppSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry padding;

  const AppSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleStyle = appSecondaryMenuItemTextStyle(
      context,
    ).copyWith(color: cs.onSurface);
    final subtitleStyle = subtitle != null && subtitle!.isNotEmpty
        ? appSecondaryControlLabelStyle(
            context,
          ).copyWith(color: appSecondaryDescriptionColor(context))
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: padding,
          child: _AppSwitchTileLayout(
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            title: title,
            titleStyle: titleStyle,
            subtitle: subtitle,
            subtitleStyle: subtitleStyle,
            leading: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            text: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: subtitleStyle),
                ],
              ],
            ),
            trailing: Switch(value: value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }
}

enum _SwitchTileSlot { leading, text, trailing }

class _SwitchTileParentData extends ContainerBoxParentData<RenderBox> {
  _SwitchTileSlot? slot;
}

class _SwitchTileSlotWidget extends ParentDataWidget<_SwitchTileParentData> {
  final _SwitchTileSlot slot;
  const _SwitchTileSlotWidget({required this.slot, required super.child});

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData as _SwitchTileParentData;
    if (parentData.slot != slot) {
      parentData.slot = slot;
      final targetParent = renderObject.parent;
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _AppSwitchTileLayout;
}

class _SwitchTileLayoutResult {
  final Size size;
  final Offset leadingOffset;
  final Offset textOffset;
  final Offset trailingOffset;

  const _SwitchTileLayoutResult({
    required this.size,
    required this.leadingOffset,
    required this.textOffset,
    required this.trailingOffset,
  });
}

class _AppSwitchTileLayout extends MultiChildRenderObjectWidget {
  final TextDirection textDirection;
  final TextScaler textScaler;
  final String title;
  final TextStyle titleStyle;
  final String? subtitle;
  final TextStyle? subtitleStyle;

  _AppSwitchTileLayout({
    required this.textDirection,
    required this.textScaler,
    required this.title,
    required this.titleStyle,
    this.subtitle,
    this.subtitleStyle,
    required Widget leading,
    required Widget text,
    required Widget trailing,
  }) : super(
         children: [
           _SwitchTileSlotWidget(slot: _SwitchTileSlot.leading, child: leading),
           _SwitchTileSlotWidget(slot: _SwitchTileSlot.text, child: text),
           _SwitchTileSlotWidget(
             slot: _SwitchTileSlot.trailing,
             child: trailing,
           ),
         ],
       );

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAppSwitchTile(
      textDirection: textDirection,
      textScaler: textScaler,
      title: title,
      titleStyle: titleStyle,
      subtitle: subtitle,
      subtitleStyle: subtitleStyle,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAppSwitchTile renderObject,
  ) {
    renderObject
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..title = title
      ..titleStyle = titleStyle
      ..subtitle = subtitle
      ..subtitleStyle = subtitleStyle;
  }
}

class _RenderAppSwitchTile extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SwitchTileParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SwitchTileParentData> {
  TextDirection _textDirection;
  TextScaler _textScaler;
  String _title;
  TextStyle _titleStyle;
  String? _subtitle;
  TextStyle? _subtitleStyle;

  _RenderAppSwitchTile({
    required TextDirection textDirection,
    required TextScaler textScaler,
    required String title,
    required TextStyle titleStyle,
    String? subtitle,
    TextStyle? subtitleStyle,
  }) : _textDirection = textDirection,
       _textScaler = textScaler,
       _title = title,
       _titleStyle = titleStyle,
       _subtitle = subtitle,
       _subtitleStyle = subtitleStyle;

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  TextScaler get textScaler => _textScaler;
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    markNeedsLayout();
  }

  String get title => _title;
  set title(String value) {
    if (_title == value) return;
    _title = value;
    markNeedsLayout();
  }

  TextStyle get titleStyle => _titleStyle;
  set titleStyle(TextStyle value) {
    if (_titleStyle == value) return;
    _titleStyle = value;
    markNeedsLayout();
  }

  String? get subtitle => _subtitle;
  set subtitle(String? value) {
    if (_subtitle == value) return;
    _subtitle = value;
    markNeedsLayout();
  }

  TextStyle? get subtitleStyle => _subtitleStyle;
  set subtitleStyle(TextStyle? value) {
    if (_subtitleStyle == value) return;
    _subtitleStyle = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SwitchTileParentData) {
      child.parentData = _SwitchTileParentData();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  bool _hasUnbrokenWordSplit(double inlineWidth, double stackedWidth) {
    if (inlineWidth <= 0.0) return true;
    if (_textSplits(title, titleStyle, inlineWidth, stackedWidth)) {
      return true;
    }
    final sub = subtitle;
    final subStyle = subtitleStyle;
    if (sub != null &&
        sub.isNotEmpty &&
        subStyle != null &&
        _textSplits(sub, subStyle, inlineWidth, stackedWidth)) {
      return true;
    }
    return false;
  }

  bool _textSplits(
    String text,
    TextStyle style,
    double inlineWidth,
    double stackedWidth,
  ) {
    if (inlineWidth <= 0.0) return true;
    final matches = RegExp(r'[A-Za-z]+').allMatches(text);
    if (matches.isEmpty) return false;

    final inlinePainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: textScaler,
      textDirection: textDirection,
    );
    TextPainter? stackedPainter;
    try {
      inlinePainter.layout(maxWidth: inlineWidth);
      for (final match in matches) {
        final inlineBoxes = inlinePainter.getBoxesForSelection(
          TextSelection(baseOffset: match.start, extentOffset: match.end),
        );
        final inlineLines = inlineBoxes.map((box) => box.top).toSet().length;
        if (inlineLines > 1) {
          stackedPainter ??= TextPainter(
            text: TextSpan(text: text, style: style),
            textScaler: textScaler,
            textDirection: textDirection,
          )..layout(maxWidth: stackedWidth);

          final stackedBoxes = stackedPainter.getBoxesForSelection(
            TextSelection(baseOffset: match.start, extentOffset: match.end),
          );
          final stackedLines = stackedBoxes
              .map((box) => box.top)
              .toSet()
              .length;
          if (stackedLines == 1 || stackedLines < inlineLines) {
            return true;
          }
        }
      }
    } finally {
      inlinePainter.dispose();
      stackedPainter?.dispose();
    }
    return false;
  }

  _SwitchTileLayoutResult _computeTileLayout(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;

    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as _SwitchTileParentData;
      switch (childParentData.slot) {
        case _SwitchTileSlot.leading:
          leading = child;
        case _SwitchTileSlot.text:
          text = child;
        case _SwitchTileSlot.trailing:
          trailing = child;
        case null:
          break;
      }
      child = childParentData.nextSibling;
    }

    if (leading == null || text == null || trailing == null) {
      return _SwitchTileLayoutResult(
        size: constraints.smallest,
        leadingOffset: Offset.zero,
        textOffset: Offset.zero,
        trailingOffset: Offset.zero,
      );
    }

    final bool isRtl = textDirection == TextDirection.rtl;

    if (!constraints.hasBoundedWidth) {
      final Size leadingSize;
      final Size trailingSize;
      final Size textSize;
      if (dry) {
        leadingSize = leading.getDryLayout(
          const BoxConstraints.tightFor(width: 34, height: 34),
        );
        trailingSize = trailing.getDryLayout(const BoxConstraints());
        textSize = text.getDryLayout(const BoxConstraints());
      } else {
        leading.layout(
          const BoxConstraints.tightFor(width: 34, height: 34),
          parentUsesSize: true,
        );
        leadingSize = leading.size;
        trailing.layout(const BoxConstraints(), parentUsesSize: true);
        trailingSize = trailing.size;
        text.layout(const BoxConstraints(), parentUsesSize: true);
        textSize = text.size;
      }
      final double totalW =
          leadingSize.width + 10.0 + textSize.width + trailingSize.width;
      final double rowH = math.max(
        34.0,
        math.max(textSize.height, trailingSize.height),
      );
      final double leadingTop = (rowH - 34.0) / 2;
      final double textTop = (rowH - textSize.height) / 2;
      final double trailingTop = (rowH - trailingSize.height) / 2;
      return _SwitchTileLayoutResult(
        size: constraints.constrain(Size(totalW, rowH)),
        leadingOffset: Offset(isRtl ? totalW - 34.0 : 0.0, leadingTop),
        textOffset: Offset(isRtl ? trailingSize.width : 44.0, textTop),
        trailingOffset: Offset(
          isRtl ? 0.0 : totalW - trailingSize.width,
          trailingTop,
        ),
      );
    }

    final double maxW = constraints.maxWidth;
    if (!dry) {
      leading.layout(
        const BoxConstraints.tightFor(width: 34, height: 34),
        parentUsesSize: true,
      );
    }

    final Size trailingSize;
    if (dry) {
      trailingSize = trailing.getDryLayout(BoxConstraints(maxWidth: maxW));
    } else {
      trailing.layout(BoxConstraints(maxWidth: maxW), parentUsesSize: true);
      trailingSize = trailing.size;
    }
    final double trailingW = trailingSize.width;
    final double trailingH = trailingSize.height;

    final double availableStackedTextW = math.max(0.0, maxW - 44.0);
    final double availableInlineTextW = math.max(
      0.0,
      availableStackedTextW - trailingW,
    );

    final bool shouldStack = _hasUnbrokenWordSplit(
      availableInlineTextW,
      availableStackedTextW,
    );

    final double textMaxW = math.max(
      0.0,
      shouldStack ? availableStackedTextW : availableInlineTextW,
    );
    final textConstraints = BoxConstraints(maxWidth: textMaxW);
    final Size textSize;
    if (dry) {
      textSize = text.getDryLayout(textConstraints);
    } else {
      text.layout(textConstraints, parentUsesSize: true);
      textSize = text.size;
    }
    final double textW = textSize.width;
    final double textH = textSize.height;

    final double leadingLeft = isRtl ? math.max(0.0, maxW - 34.0) : 0.0;
    final double textLeft = isRtl ? math.max(0.0, maxW - 44.0 - textW) : 44.0;
    final double trailingLeft = isRtl ? 0.0 : math.max(0.0, maxW - trailingW);

    if (shouldStack) {
      final double row1H = math.max(34.0, textH);
      final double leadingTop = (row1H - 34.0) / 2;
      final double textTop = (row1H - textH) / 2;
      final double trailingTop = row1H + 4.0;
      final double totalH = trailingTop + trailingH;

      return _SwitchTileLayoutResult(
        size: constraints.constrain(Size(maxW, totalH)),
        leadingOffset: Offset(leadingLeft, leadingTop),
        textOffset: Offset(textLeft, textTop),
        trailingOffset: Offset(trailingLeft, trailingTop),
      );
    } else {
      final double rowH = math.max(34.0, math.max(textH, trailingH));
      final double leadingTop = (rowH - 34.0) / 2;
      final double textTop = (rowH - textH) / 2;
      final double trailingTop = (rowH - trailingH) / 2;

      return _SwitchTileLayoutResult(
        size: constraints.constrain(Size(maxW, rowH)),
        leadingOffset: Offset(leadingLeft, leadingTop),
        textOffset: Offset(textLeft, textTop),
        trailingOffset: Offset(trailingLeft, trailingTop),
      );
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _computeTileLayout(constraints, dry: true).size;
  }

  @override
  void performLayout() {
    final result = _computeTileLayout(constraints, dry: false);
    size = result.size;

    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;
    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as _SwitchTileParentData;
      switch (childParentData.slot) {
        case _SwitchTileSlot.leading:
          leading = child;
        case _SwitchTileSlot.text:
          text = child;
        case _SwitchTileSlot.trailing:
          trailing = child;
        case null:
          break;
      }
      child = childParentData.nextSibling;
    }

    if (leading != null) {
      (leading.parentData! as _SwitchTileParentData).offset =
          result.leadingOffset;
    }
    if (text != null) {
      (text.parentData! as _SwitchTileParentData).offset = result.textOffset;
    }
    if (trailing != null) {
      (trailing.parentData! as _SwitchTileParentData).offset =
          result.trailingOffset;
    }
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final double safeWidth = width.isFinite
        ? math.max(0.0, width)
        : double.infinity;
    return computeDryLayout(BoxConstraints(maxWidth: safeWidth)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final double safeWidth = width.isFinite
        ? math.max(0.0, width)
        : double.infinity;
    return computeDryLayout(BoxConstraints(maxWidth: safeWidth)).height;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;
    RenderBox? child = firstChild;
    while (child != null) {
      final pData = child.parentData! as _SwitchTileParentData;
      if (pData.slot == _SwitchTileSlot.leading) leading = child;
      if (pData.slot == _SwitchTileSlot.text) text = child;
      if (pData.slot == _SwitchTileSlot.trailing) trailing = child;
      child = pData.nextSibling;
    }
    final leadW = leading?.getMinIntrinsicWidth(height) ?? 34.0;
    final textW = text?.getMinIntrinsicWidth(height) ?? 0.0;
    final trailW = trailing?.getMinIntrinsicWidth(height) ?? 0.0;
    return leadW + 10.0 + textW + trailW;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    RenderBox? leading;
    RenderBox? text;
    RenderBox? trailing;
    RenderBox? child = firstChild;
    while (child != null) {
      final pData = child.parentData! as _SwitchTileParentData;
      if (pData.slot == _SwitchTileSlot.leading) leading = child;
      if (pData.slot == _SwitchTileSlot.text) text = child;
      if (pData.slot == _SwitchTileSlot.trailing) trailing = child;
      child = pData.nextSibling;
    }
    final leadW = leading?.getMaxIntrinsicWidth(height) ?? 34.0;
    final textW = text?.getMaxIntrinsicWidth(height) ?? 0.0;
    final trailW = trailing?.getMaxIntrinsicWidth(height) ?? 0.0;
    return leadW + 10.0 + textW + trailW;
  }
}

ModalBottomSheetRoute<T> createAppModalSheetRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool shiftForKeyboard = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  ThemeProvider? themeProvider;
  try {
    themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  } catch (_) {
    themeProvider = null;
  }
  final openingTheme = Theme.of(context);
  final hasSecondaryControlTheme =
      context.findAncestorWidgetOfExactType<AppSecondaryControlTheme>() !=
          null ||
      (openingTheme.inputDecorationTheme.prefixIconConstraints ==
          const BoxConstraints.tightFor(width: 34, height: 34));
  final initialBrandId = themeProvider?.brand.id;

  return ModalBottomSheetRoute<T>(
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    requestFocus: false,
    backgroundColor: Colors.transparent,
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    builder: (sheetContext) {
      Widget sheetBuilder(BuildContext innerContext) {
        final child = builder(innerContext);
        if (shiftForKeyboard) return child;
        return MediaQuery.removeViewInsets(
          context: innerContext,
          removeBottom: true,
          child: child,
        );
      }

      if (themeProvider == null || initialBrandId == null) {
        return sheetBuilder(sheetContext);
      }
      return _LiveModalSheetThemeScope(
        themeProvider: themeProvider,
        initialBrandId: initialBrandId,
        openingTheme: openingTheme,
        hasSecondaryControlTheme: hasSecondaryControlTheme,
        builder: sheetBuilder,
      );
    },
  );
}

class _LiveModalSheetThemeScope extends StatefulWidget {
  final ThemeProvider themeProvider;
  final String initialBrandId;
  final ThemeData openingTheme;
  final bool hasSecondaryControlTheme;
  final WidgetBuilder builder;

  const _LiveModalSheetThemeScope({
    required this.themeProvider,
    required this.initialBrandId,
    required this.openingTheme,
    required this.hasSecondaryControlTheme,
    required this.builder,
  });

  @override
  State<_LiveModalSheetThemeScope> createState() =>
      _LiveModalSheetThemeScopeState();
}

class _LiveModalSheetThemeScopeState extends State<_LiveModalSheetThemeScope> {
  late String _lastBrandId;
  late ThemeData _lastTheme;

  @override
  void initState() {
    super.initState();
    _lastBrandId = widget.themeProvider.brand.id;
    _lastTheme = widget.themeProvider.brand.theme;
    widget.themeProvider.addListener(_onThemeChanged);
  }

  @override
  void didUpdateWidget(_LiveModalSheetThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeProvider != widget.themeProvider) {
      oldWidget.themeProvider.removeListener(_onThemeChanged);
      widget.themeProvider.addListener(_onThemeChanged);
      _lastBrandId = widget.themeProvider.brand.id;
      _lastTheme = widget.themeProvider.brand.theme;
    }
  }

  @override
  void dispose() {
    widget.themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    final currentBrand = widget.themeProvider.brand;
    if (currentBrand.id != _lastBrandId || currentBrand.theme != _lastTheme) {
      _lastBrandId = currentBrand.id;
      _lastTheme = currentBrand.theme;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppBrand currentBrand = widget.themeProvider.brand;
    final isInitialBrand = currentBrand.id == widget.initialBrandId;
    final effectiveTheme = isInitialBrand
        ? widget.openingTheme
        : currentBrand.theme;

    Widget content = Builder(builder: widget.builder);
    if (widget.hasSecondaryControlTheme) {
      content = AppSecondaryControlTheme(child: content);
    }
    return Theme(data: effectiveTheme, child: content);
  }
}

Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool shiftForKeyboard = true,
}) {
  final route = createAppModalSheetRoute<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    shiftForKeyboard: shiftForKeyboard,
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push(route);
}

class _AppDialogScrollBehavior extends MaterialScrollBehavior {
  const _AppDialogScrollBehavior();

  @override
  TargetPlatform getPlatform(BuildContext context) => defaultTargetPlatform;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Builder(
      builder: (decorationContext) =>
          super.buildOverscrollIndicator(decorationContext, child, details),
    );
  }
}

class AppDialog extends StatelessWidget {
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final Widget? icon;
  final EdgeInsetsGeometry? contentPadding;
  final double maxWidth;
  final bool shiftForKeyboard;

  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.icon,
    this.contentPadding,
    this.maxWidth = 420,
    this.shiftForKeyboard = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final mediaHeight = media.size.height;
    final rawBottomInset =
        viewInsets.bottom.isFinite && viewInsets.bottom > 0
            ? viewInsets.bottom
            : 0.0;
    final bottomInset = mediaHeight.isFinite
        ? rawBottomInset
              .clamp(0.0, mediaHeight > 0 ? mediaHeight : 0.0)
              .toDouble()
        : rawBottomInset;
    final availableHeight = mediaHeight.isFinite
        ? (mediaHeight > 0
              ? (mediaHeight - bottomInset).clamp(0.0, mediaHeight).toDouble()
              : 0.0)
        : double.infinity;
    final horizontalInset = media.size.width < 360 ? 12.0 : 20.0;
    final availableWidth = media.size.width - horizontalInset * 2;
    final effectiveMaxWidth = availableWidth.isFinite
        ? availableWidth.clamp(0.0, maxWidth).toDouble()
        : maxWidth;
    final effectiveMinWidth = effectiveMaxWidth < 320
        ? effectiveMaxWidth
        : 320.0;
    final dialog = AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      constraints: BoxConstraints(
        minWidth: effectiveMinWidth,
        maxWidth: effectiveMaxWidth,
        maxHeight: availableHeight * 0.86,
      ),
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding:
          contentPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconTheme(
                data: IconThemeData(color: cs.primary, size: 20),
                child: icon!,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: DefaultTextStyle(
              style: (theme.textTheme.titleMedium ?? const TextStyle())
                  .copyWith(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                    height: 1.2,
                  ),
              child: title,
            ),
          ),
        ],
      ),
      content: content == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: AppSecondaryControlTheme(child: content!),
            ),
      actions: actions.isEmpty
          ? null
          : [
              AppSecondaryControlTheme(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
    );
    final keyboardLift = bottomInset;
    final scopedDialog = MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: ScrollConfiguration(
        behavior: const _AppDialogScrollBehavior(),
        child: dialog,
      ),
    );
    if (!shiftForKeyboard) return scopedDialog;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardLift),
      child: Align(
        alignment: bottomInset > 0
            ? const Alignment(0, -0.18)
            : Alignment.center,
        child: scopedDialog,
      ),
    );
  }
}

class AppModalSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final List<Widget> leadingActions;
  final List<Widget> actions;
  final ScrollController? scrollController;
  final bool scrollable;
  final bool showDragHandle;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final bool shiftForKeyboard;

  const AppModalSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.leadingActions = const [],
    this.actions = const [],
    this.scrollController,
    this.scrollable = true,
    this.showDragHandle = true,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 18),
    this.maxWidth = 720,
    this.shiftForKeyboard = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final viewInsets = shiftForKeyboard ? media.viewInsets : EdgeInsets.zero;
    final availableHeight = (media.size.height - viewInsets.bottom).clamp(
      0.0,
      media.size.height,
    );
    final resolvedPadding = padding.resolve(Directionality.of(context));
    final sheetPadding = EdgeInsets.fromLTRB(
      resolvedPadding.left,
      resolvedPadding.top,
      resolvedPadding.right,
      resolvedPadding.bottom,
    );

    final children = <Widget>[
      if (showDragHandle) ...[
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.34),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      if (title != null || subtitle != null) ...[
        AppSectionHeader(
          title: title ?? '',
          subtitle: subtitle,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
      ],
      AppSecondaryControlTheme(child: child),
      if (leadingActions.isNotEmpty || actions.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppSecondaryControlTheme(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [...leadingActions, ...actions],
          ),
        ),
      ],
    ];

    Widget body;
    if (scrollController != null) {
      body = ListView(
        controller: scrollController,
        padding: sheetPadding,
        children: children,
      );
    } else if (scrollable) {
      body = SingleChildScrollView(
        padding: sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    } else {
      body = Padding(
        padding: sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          // Keep the modal hit area on the visible sheet, leaving the scrim
          // available for dismissal above short content.
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: availableHeight * 0.88,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: cs.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(
                      appSurfaceStyleOf(context)?.sheetTopRadius ??
                          _standardSheetTopRadius,
                    ),
                  ),
                  side: Theme.of(context).brightness == Brightness.dark
                      ? BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.28),
                          width: 0.5,
                        )
                      : BorderSide.none,
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppPickerOption<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final bool enabled;

  const AppPickerOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.enabled = true,
  });
}

class AppPickerSheet<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<AppPickerOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T>? onSelected;
  final Widget? empty;
  final bool closeOnSelect;

  const AppPickerSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.options,
    this.selectedValue,
    this.onSelected,
    this.empty,
    this.closeOnSelect = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: title,
      subtitle: subtitle,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return options.isEmpty
              ? (empty ??
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          I18n.tr('picker.empty'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                    ))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options) _optionTile(context, option),
                  ],
                );
        },
      ),
    );
  }

  Widget _optionTile(BuildContext context, AppPickerOption<T> option) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = selectedValue == option.value;
    final accent = option.color ?? cs.primary;
    final borderColor = selected
        ? accent.withValues(alpha: 0.22)
        : cs.outlineVariant.withValues(alpha: 0.12);
    final textColor = option.enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 0.45),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: option.enabled,
          dense: true,
          minLeadingWidth: 30,
          horizontalTitleGap: 10,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: option.icon == null
              ? null
              : Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(option.icon, color: accent, size: 17),
                ),
          title: Text(
            option.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appSecondaryControlTextStyle(
              context,
            ).copyWith(color: textColor, fontWeight: FontWeight.normal),
          ),
          subtitle: option.subtitle == null
              ? null
              : Text(
                  option.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appSecondaryControlLabelStyle(context).copyWith(
                    color: cs.onSurface.withValues(
                      alpha: option.enabled ? 0.62 : 0.38,
                    ),
                  ),
                ),
          trailing: selected
              ? Icon(Icons.check_circle, color: accent, size: 18)
              : null,
          onTap: option.enabled
              ? () {
                  onSelected?.call(option.value);
                  if (closeOnSelect) {
                    Navigator.pop<T>(context, option.value);
                  }
                }
              : null,
        ),
      ),
    );
  }
}

String _dropdownItemLabel<T>(DropdownMenuItem<T> item) {
  final widgetText = _dropdownWidgetText(item.child);
  if (widgetText != null && widgetText.trim().isNotEmpty) {
    return widgetText.trim();
  }
  final value = item.value;
  return value == null ? I18n.tr('picker.not_set') : value.toString();
}

String? _dropdownWidgetText(Widget widget) {
  if (widget is Text) {
    final data = widget.data;
    if (data != null && data.trim().isNotEmpty) return data.trim();
    final spanText = widget.textSpan?.toPlainText();
    if (spanText != null && spanText.trim().isNotEmpty) {
      return spanText.trim();
    }
    return null;
  }
  if (widget is RichText) {
    final text = widget.text.toPlainText();
    return text.trim().isEmpty ? null : text.trim();
  }
  if (widget is Row || widget is Column || widget is Wrap) {
    final children = switch (widget) {
      Row(:final children) => children,
      Column(:final children) => children,
      Wrap(:final children) => children,
      _ => const <Widget>[],
    };
    final parts = <String>[];
    for (final child in children) {
      final text = _dropdownWidgetText(child);
      if (text != null && text.trim().isNotEmpty) parts.add(text.trim());
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
  if (widget is Flexible) return _dropdownWidgetText(widget.child);
  if (widget is Padding && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is Align && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is SizedBox && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is ConstrainedBox && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is DecoratedBox && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  return null;
}

Future<void> _hideKeyboardBeforePicker(BuildContext context) async {
  final hadKeyboard = _effectiveDropdownBottomInset(context) > 1.0;
  _beginDropdownKeyboardDismiss(context);
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  if (!context.mounted) return;
  await _waitForDropdownInsetsToSettle(context);

  if (!context.mounted) return;
  if (hadKeyboard) {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!context.mounted) return;
    await _waitForDropdownAnchorLayoutToSettle(context);
  }
  if (!context.mounted) return;
  if (!_dropdownAnchorIsVisible(context)) {
    await Scrollable.ensureVisible(
      context,
      duration: Duration.zero,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }
  if (!context.mounted) return;
  await _waitForDropdownAnchorLayoutToSettle(context);
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _waitForDropdownInsetsToSettle(BuildContext context) async {
  double? previousInset;
  var closedStableFrames = 0;
  var unchangedFrames = 0;
  for (var i = 0; i < 18; i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 32));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    final inset = _effectiveDropdownBottomInset(context);
    if (inset <= 1.0) {
      closedStableFrames += 1;
      if (closedStableFrames >= 3) {
        await WidgetsBinding.instance.endOfFrame;
        return;
      }
    } else {
      closedStableFrames = 0;
    }

    if (previousInset != null && (inset - previousInset).abs() <= 0.5) {
      unchangedFrames += 1;
      if (unchangedFrames >= 4) return;
    } else {
      unchangedFrames = 0;
    }
    previousInset = inset;
  }
}

void _beginDropdownKeyboardDismiss(BuildContext context) {
  FocusScope.of(context, createDependency: false).unfocus();
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

double _effectiveDropdownBottomInset(BuildContext context) {
  final mediaInset = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0.0;
  final view = View.maybeOf(context);
  final viewInset = view == null
      ? 0.0
      : view.viewInsets.bottom / view.devicePixelRatio;
  return viewInset > mediaInset ? viewInset : mediaInset;
}

RenderBox? _dropdownOverlayBox(BuildContext context) {
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.attached || !overlay.hasSize) {
    return null;
  }
  return overlay;
}

Rect? _dropdownAnchorRectInOverlay(BuildContext context) {
  final box = context.findRenderObject();
  final overlay = _dropdownOverlayBox(context);
  if (box is! RenderBox || overlay == null || !box.attached || !box.hasSize) {
    return null;
  }
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  return Rect.fromPoints(topLeft, bottomRight);
}

Future<void> _waitForDropdownAnchorLayoutToSettle(BuildContext context) async {
  Rect? previous;
  var stableFrames = 0;
  for (var i = 0; i < 14; i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    final rect = _dropdownAnchorRectInOverlay(context);
    if (rect == null) return;
    final stable =
        previous != null &&
        (rect.topLeft - previous.topLeft).distance <= 0.5 &&
        (rect.bottomRight - previous.bottomRight).distance <= 0.5;
    if (stable) {
      stableFrames += 1;
      if (stableFrames >= 2) return;
    } else {
      stableFrames = 0;
    }
    previous = rect;
  }
}

bool _dropdownAnchorIsVisible(BuildContext context) {
  final rect = _dropdownAnchorRectInOverlay(context);
  final overlay = _dropdownOverlayBox(context);
  if (rect == null || overlay == null) {
    return true;
  }
  final media = MediaQuery.maybeOf(context);
  if (media == null) return true;
  final visibleTop = media.padding.top + 8;
  final visibleBottom = overlay.size.height - media.viewInsets.bottom - 8;
  return rect.top >= visibleTop && rect.bottom <= visibleBottom;
}

String _dropdownItemText<T>(DropdownMenuItem<T> item) {
  final child = item.child;
  if (child is AppSecondaryMenuText) {
    return child.text.trim();
  }
  return _dropdownItemLabel(item);
}

/// Route settings arguments attached to anchored popup menus.
class AppAnchoredDropdownMenuMetadata {
  final Object? ownerToken;
  final void Function(Route<dynamic>)? onRouteCreated;

  const AppAnchoredDropdownMenuMetadata({this.ownerToken, this.onRouteCreated});
}

Future<T?> _showAnchoredDropdownMenu<T>({
  required BuildContext context,
  required List<DropdownMenuItem<T>> items,
  required T? selectedValue,
  required double? menuMaxHeight,
  required bool shiftForKeyboard,
  bool Function()? isSelectionAllowed,
  void Function(Route<dynamic>)? onRouteCreated,
  Object? menuOwnerToken,
}) async {
  if (!context.mounted) return null;
  final fieldBox = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (fieldBox == null ||
      overlay == null ||
      !fieldBox.attached ||
      !overlay.attached ||
      !fieldBox.hasSize ||
      !overlay.hasSize) {
    return null;
  }

  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final selectedColor = cs.primary.withValues(alpha: 0.10);

  // Compute required popup width to fit complete numeric choices and selection check,
  // while preserving normal-width alignment for regular 220 dropdowns and constraining
  // to the overlay safe viewport.
  final textScaler = MediaQuery.textScalerOf(context);
  final textDirection = Directionality.of(context);
  final baseItemTextStyle = DefaultTextStyle.of(context).style.merge(
    appSecondaryControlTextStyle(
      context,
    ).copyWith(fontWeight: FontWeight.normal),
  );

  var requiredContentWidth = 0.0;
  for (final item in items) {
    final label = _dropdownItemText(item);
    final isNumeric = RegExp(r'^\s*-?\d+(?:\.\d+)?\s*$').hasMatch(label);
    final painter = TextPainter(
      text: TextSpan(text: label, style: baseItemTextStyle),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    final textWidth = painter.width;
    painter.dispose();

    if (isNumeric) {
      final needed = textWidth + 60.0;
      if (needed > requiredContentWidth) {
        requiredContentWidth = needed;
      }
    } else {
      final minSafe = math.min(textWidth, 24.0) + 60.0;
      if (minSafe > requiredContentWidth) {
        requiredContentWidth = minSafe;
      }
    }
  }

  final maxAllowedWidth = math.max(
    fieldBox.size.width,
    overlay.size.width - 16.0,
  );
  final menuWidth = math
      .max(
        fieldBox.size.width,
        math.max(112.0, (requiredContentWidth + 4.0).ceilToDouble()),
      )
      .clamp(fieldBox.size.width, maxAllowedWidth)
      .toDouble();

  _DropdownMenuPosition? lastPosition;
  _DropdownMenuPosition positionForCurrentLayout() {
    // A caller may replace the field while its menu is still open. Resizing
    // that menu must not read the render object of the removed anchor.
    if (!context.mounted || !fieldBox.attached) return lastPosition!;
    final currentFieldBox = context.findRenderObject() as RenderBox?;
    final currentOverlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final activeFieldBox = currentFieldBox?.attached == true
        ? currentFieldBox!
        : fieldBox;
    final activeOverlay = currentOverlay?.attached == true
        ? currentOverlay!
        : overlay;
    final fieldTopLeft = activeFieldBox.localToGlobal(
      Offset.zero,
      ancestor: activeOverlay,
    );
    final fieldBottomRight = activeFieldBox.localToGlobal(
      activeFieldBox.size.bottomRight(Offset.zero),
      ancestor: activeOverlay,
    );
    final bottomInset = shiftForKeyboard
        ? _effectiveDropdownBottomInset(context)
        : 0.0;
    final safeTop = MediaQuery.paddingOf(context).top + 8;
    final safeBottom = (activeOverlay.size.height - bottomInset - 8).clamp(
      safeTop + 48,
      activeOverlay.size.height,
    );
    final preferredMaxHeight = menuMaxHeight ?? 320;
    final belowSpace = safeBottom - fieldBottomRight.dy - 6;
    final aboveSpace = fieldTopLeft.dy - safeTop - 6;
    final openAbove = belowSpace < 160 && aboveSpace > belowSpace;

    final menuPaddingVertical =
        (theme.popupMenuTheme.menuPadding?.vertical ?? 16.0);
    var totalItemsHeight = 0.0;
    for (final item in items) {
      final label = _dropdownItemText(item);
      final isSelected = item.value == selectedValue;
      final availableTextWidth = math.max(
        0.0,
        menuWidth - (isSelected ? 60.0 : 36.0),
      );
      final painter = TextPainter(
        text: TextSpan(text: label, style: baseItemTextStyle),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: availableTextWidth);
      final textHeight = painter.height;
      painter.dispose();

      final rowHeight = math.max(textHeight, isSelected ? 16.0 : 0.0);
      final itemHeight = math.max(36.0, rowHeight + 14.0);
      totalItemsHeight += itemHeight;
    }
    final renderedContentHeight = totalItemsHeight + menuPaddingVertical;

    final availableHeight =
        (openAbove ? math.min(aboveSpace, renderedContentHeight) : belowSpace)
            .clamp(0.0, preferredMaxHeight)
            .toDouble();
    final unclampedTop = openAbove
        ? fieldTopLeft.dy - availableHeight - 6
        : fieldBottomRight.dy + 6;
    final maxTop = (safeBottom - availableHeight).clamp(safeTop, safeBottom);
    final menuTop = unclampedTop.clamp(safeTop, maxTop).toDouble();
    final menuBottom = (activeOverlay.size.height - menuTop - availableHeight)
        .clamp(0.0, activeOverlay.size.height)
        .toDouble();
    final menuLeft = fieldTopLeft.dx.clamp(0.0, activeOverlay.size.width);
    final menuRight = (activeOverlay.size.width - fieldBottomRight.dx).clamp(
      0.0,
      activeOverlay.size.width,
    );
    final position = _DropdownMenuPosition(
      rect: RelativeRect.fromLTRB(menuLeft, menuTop, menuRight, menuBottom),
      height: availableHeight,
    );
    lastPosition = position;
    return position;
  }

  final initialPosition = positionForCurrentLayout();

  ModalRoute<dynamic>? selectedMenuRoute;
  final picked = await showMenu<T>(
    context: context,
    requestFocus: false,
    positionBuilder: (_, constraints) => positionForCurrentLayout().rect,
    constraints: BoxConstraints(
      minWidth: menuWidth,
      maxWidth: menuWidth,
      maxHeight: initialPosition.height,
    ),
    color: cs.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.14),
        width: 0.45,
      ),
    ),
    routeSettings: RouteSettings(
      name: 'AppAnchoredDropdownMenu',
      arguments: AppAnchoredDropdownMenuMetadata(
        ownerToken: menuOwnerToken,
        onRouteCreated: onRouteCreated,
      ),
    ),
    items: [
      for (final item in items)
        _AnchoredDropdownMenuItem<T>(
          isSelectionAllowed: isSelectionAllowed,
          onSelectedRoute: (route) => selectedMenuRoute = route,
          onRouteCreated: onRouteCreated,
          value: item.value,
          enabled: item.enabled,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          // Open choices need their natural height at the requested text scale.
          child: DefaultTextStyle(
            overflow: TextOverflow.clip,
            style: DefaultTextStyle.of(context).style.merge(
              appSecondaryControlTextStyle(context).copyWith(
                color: item.enabled
                    ? cs.onSurface
                    : cs.onSurface.withValues(alpha: 0.38),
                fontWeight: FontWeight.normal,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: item.value == selectedValue
                    ? selectedColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(
                  children: [
                    Expanded(child: item.child),
                    if (item.value == selectedValue) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, size: 16, color: cs.primary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
  // The result arrives before the exit animation has restored the caller route.
  // Keep its origin checks strict by waiting for the selected menu to disappear.
  await selectedMenuRoute?.completed;
  return picked;
}

class _AnchoredDropdownMenuItem<T> extends PopupMenuItem<T> {
  const _AnchoredDropdownMenuItem({
    required super.value,
    required super.enabled,
    required super.height,
    required super.padding,
    required super.child,
    required this.isSelectionAllowed,
    required this.onSelectedRoute,
    this.onRouteCreated,
  });

  final bool Function()? isSelectionAllowed;
  final ValueChanged<ModalRoute<dynamic>> onSelectedRoute;
  final void Function(Route<dynamic>)? onRouteCreated;

  @override
  PopupMenuItemState<T, _AnchoredDropdownMenuItem<T>> createState() =>
      _AnchoredDropdownMenuItemState<T>();
}

class _AnchoredDropdownMenuItemState<T>
    extends PopupMenuItemState<T, _AnchoredDropdownMenuItem<T>> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      widget.onRouteCreated?.call(route);
    }
  }

  @override
  void handleTap() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || !route.isCurrent) return;
    if (widget.isSelectionAllowed?.call() == false) return;
    widget.onSelectedRoute(route);
    super.handleTap();
  }
}

class _DropdownMenuPosition {
  final RelativeRect rect;
  final double height;

  const _DropdownMenuPosition({required this.rect, required this.height});
}

class AppCompactDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double width;
  final String? selectedLabel;

  /// Rechecked before opening and after each await, before selecting a value.
  final bool Function()? isInteractionAllowed;

  /// Checks the caller while the menu itself covers its route.
  final bool Function()? isSelectionAllowed;

  final void Function(Route<dynamic>)? onMenuRouteCreated;
  final Object? menuOwnerToken;

  const AppCompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 112,
    this.selectedLabel,
    this.isInteractionAllowed,
    this.isSelectionAllowed,
    this.onMenuRouteCreated,
    this.menuOwnerToken,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.42)
        : cs.surfaceContainerHighest.withValues(alpha: 0.52);
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.10 : 0.12,
    );
    final selectedItem = _selectedItem();
    final enabled = onChanged != null && items.any((item) => item.enabled);
    final textColor = enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);
    final controlRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    final effectiveRadius = BorderRadius.circular(controlRadius);
    return SizedBox(
      width: width,
      child: Builder(
        builder: (anchorContext) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: effectiveRadius,
              onTapDown: enabled
                  ? (_) {
                      if (isInteractionAllowed?.call() == false) return;
                      _beginDropdownKeyboardDismiss(anchorContext);
                    }
                  : null,
              onTap: enabled ? () => _openPicker(anchorContext) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: effectiveRadius,
                  border: Border.all(color: borderColor, width: 0.45),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        selectedLabel ??
                            (selectedItem == null
                                ? value.toString()
                                : _dropdownItemLabel(selectedItem)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryControlTextStyle(context).copyWith(
                          color: textColor,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurface.withValues(alpha: 0.38),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  DropdownMenuItem<T>? _selectedItem() {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext anchorContext) async {
    if (onChanged == null || isInteractionAllowed?.call() == false) return;
    await _hideKeyboardBeforePicker(anchorContext);
    if (!anchorContext.mounted) return;
    if (isInteractionAllowed?.call() == false) return;

    final picked = await _showAnchoredDropdownMenu<T>(
      context: anchorContext,
      items: items,
      selectedValue: value,
      menuMaxHeight: 320,
      shiftForKeyboard: false,
      isSelectionAllowed: isSelectionAllowed,
      onRouteCreated: onMenuRouteCreated,
      menuOwnerToken: menuOwnerToken,
    );
    if (picked == null) return;
    // A locale/layout change may recycle a sliver anchor while its menu stays
    // open. An explicit caller-origin guard can still authorize completion.
    if (!anchorContext.mounted && isInteractionAllowed == null) return;
    if (isInteractionAllowed?.call() == false) return;
    onChanged?.call(picked);
  }
}

class AppDropdownField<T> extends StatelessWidget {
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration? decoration;
  final String? labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? icon;
  final bool enabled;
  final bool isExpanded;

  /// Allow the selected label to use as many lines as its width requires.
  final bool wrapSelectedText;
  final double? menuMaxHeight;
  final BorderRadius? borderRadius;
  final Color? dropdownColor;
  final Color? iconEnabledColor;
  final Color? iconDisabledColor;
  final AutovalidateMode? autovalidateMode;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;
  final VoidCallback? onTap;

  /// Rechecked at entry and after each await, before changing form state.
  final bool Function()? isInteractionAllowed;

  /// Checks the caller while the menu itself covers its route.
  final bool Function()? isSelectionAllowed;
  final void Function(Route<dynamic>)? onMenuRouteCreated;

  /// Specific owner identity attached to the menu's route metadata.
  final Object? menuOwnerToken;

  const AppDropdownField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.icon,
    this.enabled = true,
    this.isExpanded = true,
    this.wrapSelectedText = false,
    this.menuMaxHeight = 320,
    this.borderRadius,
    this.dropdownColor,
    this.iconEnabledColor,
    this.iconDisabledColor,
    this.autovalidateMode,
    this.validator,
    this.onSaved,
    this.onTap,
    this.isInteractionAllowed,
    this.isSelectionAllowed,
    this.onMenuRouteCreated,
    this.menuOwnerToken,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inputDecoration =
        decoration ??
        InputDecoration(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: prefixIcon,
          isDense: true,
        );
    final controlRadius =
        appSurfaceStyleOf(context)?.smallTileRadius ?? DesignTokens.radiusControl;
    final effectiveBorderRadius =
        borderRadius ?? BorderRadius.circular(controlRadius);
    return FormField<T>(
      initialValue: initialValue,
      validator: validator,
      onSaved: onSaved,
      autovalidateMode: autovalidateMode,
      builder: (field) {
        final selectedItem = _selectedItem(field.value);
        final iconColor = enabled
            ? iconEnabledColor ?? cs.onSurfaceVariant
            : iconDisabledColor ?? cs.onSurface.withValues(alpha: 0.38);
        final effectiveDecoration = inputDecoration
            .applyDefaults(theme.inputDecorationTheme)
            .copyWith(
              enabled: enabled,
              errorText: field.errorText,
              suffixIcon:
                  inputDecoration.suffixIcon ??
                  icon ??
                  Icon(Icons.keyboard_arrow_down_rounded, color: iconColor),
            );
        final canOpen = enabled && items.any((item) => item.enabled);
        return Builder(
          builder: (anchorContext) {
            final content = selectedItem == null
                ? const SizedBox.shrink()
                : Builder(
                    builder: (textContext) {
                      final inheritedText = DefaultTextStyle.of(textContext);
                      return DefaultTextStyle(
                        maxLines: wrapSelectedText ? null : 1,
                        overflow: wrapSelectedText
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                        softWrap: wrapSelectedText || inheritedText.softWrap,
                        textAlign: inheritedText.textAlign,
                        textWidthBasis: inheritedText.textWidthBasis,
                        textHeightBehavior: inheritedText.textHeightBehavior,
                        style: inheritedText.style.merge(
                          appSecondaryControlTextStyle(context).copyWith(
                            color: enabled
                                ? cs.onSurface
                                : cs.onSurface.withValues(alpha: 0.38),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        child: IconTheme.merge(
                          data: IconThemeData(color: cs.onSurfaceVariant),
                          child: selectedItem.child,
                        ),
                      );
                    },
                  );
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: effectiveBorderRadius,
                onTapDown: canOpen
                    ? (_) {
                        if (isInteractionAllowed?.call() == false) return;
                        _beginDropdownKeyboardDismiss(anchorContext);
                      }
                    : null,
                onTap: canOpen
                    ? () => _openPicker(anchorContext, field, inputDecoration)
                    : null,
                child: InputDecorator(
                  decoration: effectiveDecoration,
                  isEmpty: selectedItem == null,
                  child: content,
                ),
              ),
            );
          },
        );
      },
    );
  }

  DropdownMenuItem<T>? _selectedItem(T? value) {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Future<void> _openPicker(
    BuildContext anchorContext,
    FormFieldState<T> field,
    InputDecoration decoration,
  ) async {
    if (isInteractionAllowed?.call() == false) return;
    onTap?.call();
    if (isInteractionAllowed?.call() == false) return;
    await _hideKeyboardBeforePicker(anchorContext);
    if (!anchorContext.mounted || !field.mounted) return;
    if (isInteractionAllowed?.call() == false) return;

    final picked = await _showAnchoredDropdownMenu<T>(
      context: anchorContext,
      items: items,
      selectedValue: field.value,
      menuMaxHeight: menuMaxHeight,
      shiftForKeyboard: false,
      isSelectionAllowed: isSelectionAllowed ?? isInteractionAllowed,
      onRouteCreated: onMenuRouteCreated,
      menuOwnerToken: menuOwnerToken,
    );
    if (!field.mounted || picked == null) return;
    if (isInteractionAllowed?.call() == false) return;
    field.didChange(picked);
    onChanged(picked);
  }
}
