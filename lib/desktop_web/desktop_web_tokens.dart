import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/design_tokens.dart';
import '../providers/theme_provider.dart';
import 'desktop_web_nav.dart';

/// Design tokens and surface helpers for the Desktop Web workspace.
///
/// Uses crisp size, letter-spacing, and color-opacity hierarchy with
/// FontWeight.normal only to satisfy the repository typography check.
@immutable
class DesktopWebTokens {
  static const double sidebarWidth = 248.0;
  static const double topbarHeight = 56.0;
  static const double workspaceBreakpoint = 960.0;
  static const double paneListWidth = 216.0;
  static const double paneInspectorWidth = 320.0;
  static const double calendarInspectorWidth = 340.0;
  static const double focusInspectorWidth = 340.0;
  static const double contentMaxWidth = 1520.0;
  static const double embeddedMaxWidth = 1120.0;
  static const double hairlineWidth = 0.6;
  static const double webChromeBlurSigma = 8.0;

  static const double radiusXs = 6.0;
  static const double radiusSm = 8.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusPill = 999.0;

  static const double spaceXs = 4.0;
  static const double spaceSm = 8.0;
  static const double spaceMd = 12.0;
  static const double spaceLg = 16.0;
  static const double spaceXl = 20.0;
  static const double space2xl = 24.0;
  static const double space3xl = 32.0;

  final bool isDark;
  final bool isLiquidGlass;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final Color accentForeground;
  final Color canvasBackground;
  final Color sidebarBackground;
  final Color topbarBackground;
  final Color panelSurface;
  final Color elevatedSurface;
  final Color mutedSurface;
  final Color hoverSurface;
  final Color selectedSurface;
  final Color hairlineBorder;
  final Color strongBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> modalShadow;
  final double glassBlurSigma;

  const DesktopWebTokens({
    required this.isDark,
    required this.isLiquidGlass,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.accentForeground,
    required this.canvasBackground,
    required this.sidebarBackground,
    required this.topbarBackground,
    required this.panelSurface,
    required this.elevatedSurface,
    required this.mutedSurface,
    required this.hoverSurface,
    required this.selectedSurface,
    required this.hairlineBorder,
    required this.strongBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.cardShadow,
    required this.modalShadow,
    required this.glassBlurSigma,
  });

  factory DesktopWebTokens.of(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = theme.extension<AppSurfaceStyle>();

    AppBrand? activeBrand;
    try {
      activeBrand = context.select<ThemeProvider?, AppBrand?>(
        (provider) => provider?.brand,
      );
    } catch (_) {
      activeBrand = null;
    }

    final frostedOverride = DesktopWebScope.maybeOf(context)?.frostedOverride;
    final hasTranslucentSurface =
        surfaceStyle?.cardFillColor != null &&
        surfaceStyle!.cardFillColor!.a < 0.99;
    final bool isLiquidGlass;
    if (frostedOverride != null) {
      isLiquidGlass = frostedOverride;
    } else {
      final brandIsGlass =
          activeBrand?.style == BrandStyle.liquidGlass &&
          surfaceStyle != AppSurfaceStyle.ios;
      isLiquidGlass =
          brandIsGlass ||
          surfaceStyle == AppSurfaceStyle.liquidGlass ||
          hasTranslucentSurface;
    }

    final isDefaultLike =
        activeBrand == null ||
        activeBrand.style == BrandStyle.defaultBrand ||
        activeBrand.style == BrandStyle.liquidGlass;

    final Color accent;
    if (isLiquidGlass) {
      accent = isDark ? const Color(0xFF4EA1FF) : const Color(0xFF0A6CDB);
    } else if (activeBrand?.style == BrandStyle.defaultBrand || isDefaultLike) {
      accent = isDark ? const Color(0xFF0A84FF) : DesignTokens.defaultPrimary;
    } else {
      accent = cs.primary;
    }

    final Color accentForeground =
        _contrastRatio(accent, Colors.white) >= 3.5
        ? Colors.white
        : const Color(0xFF121417);

    final Color canvasBackground;
    final Color sidebarBackground;
    final Color topbarBackground;
    final Color panelSurface;
    final Color elevatedSurface;
    final Color mutedSurface;
    final Color hoverSurface;
    final Color selectedSurface;
    final Color hairlineBorder;
    final Color strongBorder;
    final Color textPrimary;
    final Color textSecondary;
    final Color textMuted;

    if (isLiquidGlass) {
      if (isDark) {
        canvasBackground = const Color(0xFF0D1320);
        sidebarBackground = const Color(0xFF141C2C).withValues(alpha: 0.72);
        topbarBackground = const Color(0xFF131A29).withValues(alpha: 0.68);
        panelSurface = const Color(0xFF182234).withValues(alpha: 0.68);
        elevatedSurface = const Color(0xFF1E293D).withValues(alpha: 0.92);
        mutedSurface = Colors.white.withValues(alpha: 0.06);
        hoverSurface = Colors.white.withValues(alpha: 0.08);
        selectedSurface = accent.withValues(alpha: 0.18);
        hairlineBorder = Colors.white.withValues(alpha: 0.16);
        strongBorder = Colors.white.withValues(alpha: 0.24);
        textPrimary = const Color(0xFFF1F5FB);
        textSecondary = const Color(0xFFB5C2D8);
        textMuted = const Color(0xFF8896AE);
      } else {
        canvasBackground = const Color(0xFFE9EEF6);
        sidebarBackground = Colors.white.withValues(alpha: 0.62);
        topbarBackground = Colors.white.withValues(alpha: 0.56);
        panelSurface = Colors.white.withValues(alpha: 0.68);
        elevatedSurface = Colors.white.withValues(alpha: 0.92);
        mutedSurface = const Color(0xFF17233B).withValues(alpha: 0.045);
        hoverSurface = const Color(0xFF17233B).withValues(alpha: 0.06);
        selectedSurface = accent.withValues(alpha: 0.11);
        hairlineBorder = Colors.white.withValues(alpha: 0.72);
        strongBorder = const Color(0xFF17233B).withValues(alpha: 0.14);
        textPrimary = const Color(0xFF131E33);
        textSecondary = const Color(0xFF475770);
        textMuted = const Color(0xFF6B7A92);
      }
    } else if (isDark) {
      final baseBg = isDefaultLike
          ? const Color(0xFF0F1218)
          : theme.scaffoldBackgroundColor;
      final baseSurface = isDefaultLike
          ? const Color(0xFF171B24)
          : cs.surface;
      canvasBackground = baseBg;
      sidebarBackground = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.02),
        baseSurface,
      );
      topbarBackground = Color.alphaBlend(
        baseSurface.withValues(alpha: 0.94),
        baseBg,
      );
      panelSurface = baseSurface;
      elevatedSurface = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.045),
        baseSurface,
      );
      mutedSurface = Colors.white.withValues(alpha: 0.05);
      hoverSurface = Colors.white.withValues(alpha: 0.07);
      selectedSurface = accent.withValues(alpha: 0.17);
      hairlineBorder = Colors.white.withValues(alpha: 0.09);
      strongBorder = Colors.white.withValues(alpha: 0.18);
      textPrimary = const Color(0xFFF2F4F8);
      textSecondary = const Color(0xFFB5BECE);
      textMuted = const Color(0xFF8690A2);
    } else {
      final baseBg = isDefaultLike
          ? const Color(0xFFF6F7F9)
          : theme.scaffoldBackgroundColor;
      final baseSurface = isDefaultLike
          ? const Color(0xFFFFFFFF)
          : cs.surface;
      canvasBackground = baseBg;
      sidebarBackground = isDefaultLike
          ? const Color(0xFFFBFBFC)
          : Color.alphaBlend(
              Colors.white.withValues(alpha: 0.85),
              baseSurface,
            );
      topbarBackground = Color.alphaBlend(
        baseSurface.withValues(alpha: 0.94),
        baseBg,
      );
      panelSurface = baseSurface;
      elevatedSurface = baseSurface;
      mutedSurface = const Color(0xFF181C24).withValues(alpha: 0.055);
      hoverSurface = const Color(0xFF181C24).withValues(alpha: 0.07);
      selectedSurface = accent.withValues(alpha: 0.10);
      hairlineBorder = const Color(0xFF181C24).withValues(alpha: 0.085);
      strongBorder = const Color(0xFF181C24).withValues(alpha: 0.16);
      textPrimary = const Color(0xFF181C24);
      textSecondary = const Color(0xFF4F5969);
      textMuted = const Color(0xFF7B8496);
    }

    return DesktopWebTokens(
      isDark: isDark,
      isLiquidGlass: isLiquidGlass,
      accent: accent,
      accentSoft: accent.withValues(alpha: isDark ? 0.18 : 0.11),
      accentBorder: accent.withValues(alpha: isDark ? 0.42 : 0.30),
      accentForeground: accentForeground,
      canvasBackground: canvasBackground,
      sidebarBackground: sidebarBackground,
      topbarBackground: topbarBackground,
      panelSurface: panelSurface,
      elevatedSurface: elevatedSurface,
      mutedSurface: mutedSurface,
      hoverSurface: hoverSurface,
      selectedSurface: selectedSurface,
      hairlineBorder: hairlineBorder,
      strongBorder: strongBorder,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      success: isDark ? const Color(0xFF4ADE80) : const Color(0xFF23865F),
      warning: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB7791F),
      danger: isDark ? const Color(0xFFF87171) : const Color(0xFFC64747),
      info: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
      cardShadow: isDark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ]
          : [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(
                  alpha: isLiquidGlass ? 0.045 : 0.035,
                ),
                blurRadius: 2.5,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(
                  alpha: isLiquidGlass ? 0.075 : 0.05,
                ),
                blurRadius: isLiquidGlass ? 16 : 12,
                offset: Offset(0, isLiquidGlass ? 6 : 4),
              ),
            ],
      modalShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.16),
          blurRadius: 36,
          offset: const Offset(0, 14),
        ),
      ],
      glassBlurSigma: isLiquidGlass
          ? (kIsWeb ? webChromeBlurSigma : 16.0)
          : 0.0,
    );
  }

  double get chromeBlurSigma =>
      kIsWeb ? math.min(glassBlurSigma, webChromeBlurSigma) : glassBlurSigma;

  TextStyle get pageTitleStyle => TextStyle(
    fontSize: 18,
    height: 1.25,
    letterSpacing: -0.2,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  TextStyle get heroTitleStyle => TextStyle(
    fontSize: 24,
    height: 1.2,
    letterSpacing: -0.4,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  TextStyle get sectionHeaderStyle => TextStyle(
    fontSize: 11.5,
    height: 1.2,
    letterSpacing: 0.6,
    fontWeight: FontWeight.normal,
    color: textMuted,
  );

  TextStyle get cardTitleStyle => TextStyle(
    fontSize: 15,
    height: 1.3,
    letterSpacing: -0.1,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  TextStyle get bodyStyle => TextStyle(
    fontSize: 13.5,
    height: 1.45,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  TextStyle get bodyMutedStyle => TextStyle(
    fontSize: 12.5,
    height: 1.4,
    fontWeight: FontWeight.normal,
    color: textSecondary,
  );

  TextStyle get captionStyle => TextStyle(
    fontSize: 11.5,
    height: 1.3,
    fontWeight: FontWeight.normal,
    color: textMuted,
  );

  TextStyle get metricValueStyle => TextStyle(
    fontSize: 22,
    height: 1.15,
    letterSpacing: -0.5,
    fontWeight: FontWeight.normal,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: textPrimary,
  );

  TextStyle get navItemStyle => TextStyle(
    fontSize: 13.5,
    height: 1.25,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  TextStyle get kbdStyle => TextStyle(
    fontSize: 11,
    height: 1.1,
    letterSpacing: 0.2,
    fontWeight: FontWeight.normal,
    color: textMuted,
  );

  /// Shared panel decoration producing matching pseudo-glass sheen, dark
  /// specular depth, hairline highlight borders, and optional keyboard focus ring.
  BoxDecoration panelDecoration({
    Color? color,
    BorderRadius? borderRadius,
    Border? border,
    bool frosted = false,
    bool hovered = false,
    bool focused = false,
    List<BoxShadow>? boxShadow,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(radiusLg);
    final usePseudoGlass = (frosted || isLiquidGlass) && color == null;
    final bg =
        color ??
        (usePseudoGlass
            ? (isDark
                  ? const Color(0xFF182234).withValues(alpha: 0.76)
                  : Colors.white.withValues(alpha: 0.74))
            : panelSurface);
    final effectiveBg = hovered ? Color.alphaBlend(hoverSurface, bg) : bg;
    final activeBorder =
        border ??
        Border.all(
          color: focused
              ? accentBorder
              : hovered
              ? strongBorder
              : (usePseudoGlass && !isDark
                    ? Colors.white.withValues(alpha: 0.82)
                    : hairlineBorder),
          width: hairlineWidth,
        );
    final Gradient? sheenGradient;
    if (usePseudoGlass) {
      sheenGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.35, 1.0],
        colors: isDark
            ? [
                Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.075),
                  effectiveBg,
                ),
                Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.025),
                  effectiveBg,
                ),
                effectiveBg,
              ]
            : [
                Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.34),
                  effectiveBg,
                ),
                Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.12),
                  effectiveBg,
                ),
                effectiveBg,
              ],
      );
    } else if (isDark && color == null) {
      sheenGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(
            Colors.white.withValues(alpha: 0.04),
            effectiveBg,
          ),
          effectiveBg,
        ],
      );
    } else {
      sheenGradient = null;
    }

    final resolvedShadows = [
      if (focused)
        BoxShadow(
          color: accent.withValues(alpha: 0.45),
          blurRadius: 0,
          spreadRadius: 2.0,
        ),
      ...(boxShadow ?? cardShadow),
    ];

    return BoxDecoration(
      color: sheenGradient == null ? effectiveBg : null,
      gradient: sheenGradient,
      borderRadius: radius,
      border: activeBorder,
      boxShadow: resolvedShadows,
    );
  }

  /// Derives a complete desktop workspace [ThemeData] supporting light/dark
  /// and frosted translucency on top of any active [AppBrand].
  static ThemeData buildWorkspaceTheme({
    required AppBrand brand,
    bool? darkOverride,
    bool? frostedOverride,
  }) {
    final base = brand.theme;
    final wantDark = darkOverride ?? (base.brightness == Brightness.dark);
    final wantFrosted =
        frostedOverride ?? (brand.style == BrandStyle.liquidGlass);

    final AppSurfaceStyle? effectiveSurfaceStyle;
    if (wantFrosted) {
      effectiveSurfaceStyle = AppSurfaceStyle(
        cardRadius: DesignTokens.radiusCardIos,
        smallTileRadius: DesignTokens.radiusControlIos,
        cardFillColor: wantDark
            ? const Color(0xFF182234).withValues(alpha: 0.64)
            : Colors.white.withValues(alpha: DesignTokens.glassFillLightAlpha),
        cardBorder: Border.fromBorderSide(
          BorderSide(
            color: wantDark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(
                    alpha: DesignTokens.glassHighlightAlpha,
                  ),
            width: 0.55,
          ),
        ),
        cardShadow: DesignTokens.shadowXs,
        sheetTopRadius: DesignTokens.sheetIosTopRadius,
        navBarBlurSigma: DesignTokens.navBarWebBlurSigma,
      );
    } else if (brand.style == BrandStyle.liquidGlass && !wantFrosted) {
      effectiveSurfaceStyle = AppSurfaceStyle.ios;
    } else {
      effectiveSurfaceStyle = base.extension<AppSurfaceStyle>();
    }

    if (wantDark == (base.brightness == Brightness.dark) &&
        wantFrosted == (brand.style == BrandStyle.liquidGlass)) {
      return base;
    }

    final primary = wantFrosted
        ? (wantDark ? const Color(0xFF4EA1FF) : const Color(0xFF0A6CDB))
        : (brand.style == BrandStyle.defaultBrand ||
                  brand.style == BrandStyle.liquidGlass
              ? (wantDark
                    ? const Color(0xFF0A84FF)
                    : DesignTokens.defaultPrimary)
              : base.colorScheme.primary);

    final secondary = wantFrosted
        ? const Color(0xFF5AC8FA)
        : base.colorScheme.secondary;

    final Color bg = wantDark
        ? (wantFrosted ? const Color(0xFF0D1320) : const Color(0xFF0F1218))
        : (wantFrosted
              ? const Color(0xFFE9EEF6)
              : DesignTokens.defaultPageBackground);

    final Color surface = wantDark
        ? (wantFrosted ? const Color(0xFF182234) : const Color(0xFF171B24))
        : (wantFrosted
              ? const Color(0xFFF7F9FC)
              : DesignTokens.defaultSurface);

    final ColorScheme scheme = wantDark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            surface: surface,
            error: const Color(0xFFF87171),
            onSurface: const Color(0xFFF2F4F8),
          )
        : ColorScheme.light(
            primary: primary,
            secondary: secondary,
            surface: surface,
            error: DesignTokens.defaultError,
            onSurface: const Color(0xFF181C24),
          );

    final textColor = scheme.onSurface;
    final mutedTextColor = wantDark
        ? const Color(0xFF9AA5BA)
        : const Color(0xFF5B667A);

    final adjustedTextTheme = base.textTheme.apply(
      bodyColor: textColor,
      displayColor: textColor,
    ).copyWith(
      bodySmall: base.textTheme.bodySmall?.copyWith(color: mutedTextColor),
    );

    final outline = wantDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFF181C24).withValues(alpha: 0.10);

    return base.copyWith(
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: adjustedTextTheme,
      dividerColor: outline,
      extensions: effectiveSurfaceStyle == null
          ? const <ThemeExtension<dynamic>>[]
          : <ThemeExtension<dynamic>>[effectiveSurfaceStyle],
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          color: textColor,
          fontWeight: FontWeight.normal,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: wantFrosted
            ? effectiveSurfaceStyle?.cardFillColor
            : surface,
        elevation: 0,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: wantDark
            ? Colors.white.withValues(alpha: 0.05)
            : DesignTokens.defaultSurfaceMuted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: outline, width: hairlineWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(
            color: primary.withValues(alpha: 0.55),
            width: hairlineWidth,
          ),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStatePropertyAll<double>(wantDark ? 6 : 5),
        radius: const Radius.circular(999),
        thumbColor: WidgetStatePropertyAll<Color?>(
          textColor.withValues(alpha: wantDark ? 0.30 : 0.22),
        ),
      ),
    );
  }

  static double _contrastRatio(Color a, Color b) {
    final aLum = a.computeLuminance();
    final bLum = b.computeLuminance();
    final lighter = aLum > bLum ? aLum : bLum;
    final darker = aLum > bLum ? bLum : aLum;
    return (lighter + 0.05) / (darker + 0.05);
  }
}

/// Crisp hairline-bordered surface panel with hover state and pseudo-glass
/// translucent surface styling (no per-card BackdropFilter inside scrollables).
class DesktopPanelCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius? borderRadius;
  final bool frosted;
  final Border? border;

  const DesktopPanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderRadius,
    this.frosted = false,
    this.border,
  });

  @override
  State<DesktopPanelCard> createState() => _DesktopPanelCardState();
}

class _DesktopPanelCardState extends State<DesktopPanelCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final radius =
        widget.borderRadius ?? BorderRadius.circular(DesktopWebTokens.radiusLg);
    final decoration = tokens.panelDecoration(
      color: widget.color,
      borderRadius: radius,
      border: widget.border,
      frosted: widget.frosted,
      hovered: _hovered && widget.onTap != null,
      focused: _focused && widget.onTap != null,
    );

    if (widget.onTap == null) {
      return Container(
        padding: widget.padding,
        decoration: decoration,
        child: widget.child,
      );
    }

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: decoration,
      child: widget.child,
    );

    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (hovered) {
        if (mounted && _hovered != hovered) {
          setState(() => _hovered = hovered);
        }
      },
      onFocusChange: (focused) {
        if (mounted && _focused != focused) {
          setState(() => _focused = focused);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: content,
      ),
    );
  }
}

/// Hoverable list/navigation tile built with MouseRegion for desktop ergonomics.
class DesktopHoverTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  const DesktopHoverTile({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.borderRadius,
  });

  @override
  State<DesktopHoverTile> createState() => _DesktopHoverTileState();
}

class _DesktopHoverTileState extends State<DesktopHoverTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final radius =
        widget.borderRadius ?? BorderRadius.circular(DesktopWebTokens.radiusSm);
    final Color fill = widget.selected
        ? tokens.selectedSurface
        : (_hovered ? tokens.hoverSurface : Colors.transparent);
    final isInteractive = widget.onTap != null;

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: _focused && isInteractive
            ? Border.all(
                color: tokens.accentBorder,
                width: DesktopWebTokens.hairlineWidth,
              )
            : (widget.selected
                  ? Border.all(
                      color: tokens.accentBorder.withValues(alpha: 0.45),
                      width: DesktopWebTokens.hairlineWidth,
                    )
                  : null),
        boxShadow: _focused && isInteractive
            ? [
                BoxShadow(
                  color: tokens.accent.withValues(alpha: 0.45),
                  blurRadius: 0,
                  spreadRadius: 2.0,
                ),
              ]
            : null,
      ),
      child: widget.child,
    );

    if (!isInteractive) {
      return MouseRegion(
        cursor: MouseCursor.defer,
        onEnter: (_) {
          if (mounted && !_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted && _hovered) setState(() => _hovered = false);
        },
        child: tile,
      );
    }

    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (hovered) {
        if (mounted && _hovered != hovered) {
          setState(() => _hovered = hovered);
        }
      },
      onFocusChange: (focused) {
        if (mounted && _focused != focused) {
          setState(() => _focused = focused);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: tile,
      ),
    );
  }
}

/// Crisp keyboard shortcut keycap badge (for example ⌘K, Enter, Esc).
class DesktopKeycap extends StatelessWidget {
  final String label;

  const DesktopKeycap({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.elevatedSurface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: tokens.hairlineBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: tokens.isDark ? 0.34 : 0.08,
            ),
            blurRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(label, style: tokens.kbdStyle),
    );
  }
}
