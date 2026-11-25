import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/i18n.dart';
import '../core/web_target.dart';
import '../desktop_web/desktop_embedded_scope.dart';
import '../providers/preferences_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import 'calendar_screen.dart';
import 'habit_screen.dart';
import 'today_screen.dart';
import 'todo_screen.dart';
import 'widget_screen.dart';

const double _kMoreAppCardPaddingHorizontal = DesignTokens.spaceMd;
const double _kMoreAppCardPaddingVertical = DesignTokens.spaceSm;
const double _kMoreAppIconBoxSize = 36.0;
const double _kMoreAppIconTrailingSpacing = DesignTokens.spaceSm;
const double _kMoreAppArrowLeadingSpacing = DesignTokens.spaceXs;
const double _kMoreAppArrowIconSize = 13.0;
const double _kMoreAppBorderWidth = 0.55;

const double _kMoreAppCardFixedHorizontalWidth =
    _kMoreAppCardPaddingHorizontal * 2 +
    _kMoreAppIconBoxSize +
    _kMoreAppIconTrailingSpacing +
    _kMoreAppArrowLeadingSpacing +
    _kMoreAppArrowIconSize +
    _kMoreAppBorderWidth * 2;

const double _kMoreAppMeasurementRoundingMargin = 1.0;
const double _kMoreAppGridCrossAxisSpacing = DesignTokens.spaceSm;
const double _kMoreAppGridMainAxisSpacing = DesignTokens.spaceMd;
const double _kMoreAppMinTouchTarget = 44.0;

TextStyle _moreAppButtonTextStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return appSecondaryMenuItemTextStyle(
    context,
  ).copyWith(color: cs.onSurface, fontWeight: FontWeight.normal, height: 1.25);
}

bool _canFitColumns({
  required int columns,
  required double availableWidth,
  required double maxLabelWidth,
}) {
  if (columns <= 0) return false;
  final totalSpacing = (columns - 1) * _kMoreAppGridCrossAxisSpacing;
  final cardWidth = (availableWidth - totalSpacing) / columns;
  final availableLabelWidth = cardWidth - _kMoreAppCardFixedHorizontalWidth;
  return availableLabelWidth >=
      (maxLabelWidth + _kMoreAppMeasurementRoundingMargin);
}

int _determineColumnCount({
  required double availableWidth,
  required double maxLabelWidth,
}) {
  if (availableWidth < 280) {
    return 1;
  }
  if (availableWidth >= 520 &&
      _canFitColumns(
        columns: 3,
        availableWidth: availableWidth,
        maxLabelWidth: maxLabelWidth,
      )) {
    return 3;
  }
  if (_canFitColumns(
    columns: 2,
    availableWidth: availableWidth,
    maxLabelWidth: maxLabelWidth,
  )) {
    return 2;
  }
  return 1;
}

double _calculateCardHeight({
  required List<MoreAppItem> apps,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
  required double availableLabelWidth,
  required bool canFitSingleLine,
}) {
  final labelScale = (textScaler.scale(12) / 12).clamp(0.0, 4.0);
  final baseCardHeight = 56.0 + (labelScale - 1.0).clamp(0.0, 2.0) * 20.0;

  double maxItemHeight = 0.0;
  for (final app in apps) {
    final painter =
        TextPainter(
          text: TextSpan(text: app.label, style: style),
          textDirection: textDirection,
          textScaler: textScaler,
          maxLines: canFitSingleLine ? 1 : null,
        )..layout(
          maxWidth: canFitSingleLine
              ? double.infinity
              : (availableLabelWidth > 0
                    ? availableLabelWidth
                    : double.infinity),
        );

    final contentHeight = math.max(_kMoreAppIconBoxSize, painter.height);
    final itemHeight =
        contentHeight +
        _kMoreAppCardPaddingVertical * 2 +
        _kMoreAppBorderWidth * 2;
    if (itemHeight > maxItemHeight) {
      maxItemHeight = itemHeight;
    }
    painter.dispose();
  }

  return math.max(
    _kMoreAppMinTouchTarget,
    math.max(baseCardHeight, maxItemHeight),
  );
}

class MoreApplicationsScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  final List<int>? visibleBottomNavTabs;

  const MoreApplicationsScreen({super.key, this.visibleBottomNavTabs});

  static List<MoreAppItem> hiddenBottomNavApps(
    PreferencesProvider prefs, {
    List<int>? visibleBottomNavTabs,
  }) {
    final visible = (visibleBottomNavTabs ?? prefs.visibleBottomNavTabs)
        .toSet();
    final apps = <MoreAppItem>[
      MoreAppItem(
        tab: 0,
        icon: Icons.today_outlined,
        label: I18n.tr('nav.today'),
        color: DesignTokens.defaultInfo,
        builder: (_) => const TodayScreen(),
      ),
      MoreAppItem(
        tab: 1,
        icon: Icons.checklist,
        label: I18n.tr('nav.todo'),
        color: DesignTokens.defaultSuccess,
        builder: (_) => const TodoScreen(),
      ),
      MoreAppItem(
        tab: 2,
        icon: Icons.repeat,
        label: I18n.tr('nav.habit'),
        color: DesignTokens.defaultAccent,
        builder: (_) => const HabitScreen(),
      ),
      MoreAppItem(
        tab: 3,
        icon: Icons.calendar_month_outlined,
        label: I18n.tr('nav.calendar'),
        color: DesignTokens.defaultWarning,
        builder: (_) => const CalendarScreen(),
      ),
      MoreAppItem(
        tab: 5,
        icon: Icons.widgets_outlined,
        label: I18n.tr('nav.widget'),
        color: DesignTokens.defaultError,
        builder: (_) => const WidgetScreen(),
      ),
    ];
    return apps
        .where((app) => !visible.contains(app.tab))
        .where((app) => !(WebTarget.isDesktopWebBuild && app.tab == 5))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (context.read<PreferencesProvider?>() == null) {
      return _MoreApplicationsProviderFallback(
        visibleBottomNavTabs: visibleBottomNavTabs,
      );
    }
    return _MoreApplicationsBody(visibleBottomNavTabs: visibleBottomNavTabs);
  }
}

class _MoreApplicationsProviderFallback extends StatefulWidget {
  final List<int>? visibleBottomNavTabs;

  const _MoreApplicationsProviderFallback({this.visibleBottomNavTabs});

  @override
  State<_MoreApplicationsProviderFallback> createState() =>
      _MoreApplicationsProviderFallbackState();
}

class _MoreApplicationsProviderFallbackState
    extends State<_MoreApplicationsProviderFallback> {
  late final PreferencesProvider _preferences = PreferencesProvider();

  @override
  void initState() {
    super.initState();
    unawaited(_preferences.loadFromStorage());
  }

  @override
  void dispose() {
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PreferencesProvider>.value(
      value: _preferences,
      child: _MoreApplicationsBody(
        visibleBottomNavTabs: widget.visibleBottomNavTabs,
      ),
    );
  }
}

class _MoreApplicationsBody extends StatelessWidget {
  final List<int>? visibleBottomNavTabs;

  const _MoreApplicationsBody({this.visibleBottomNavTabs});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) => _buildLocalized(context),
    );
  }

  Widget _buildLocalized(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final apps = MoreApplicationsScreen.hiddenBottomNavApps(
      context.watch<PreferencesProvider>(),
      visibleBottomNavTabs: visibleBottomNavTabs,
    );
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final countFill = cs.primaryContainer.withValues(alpha: 0.72);
    final countEffectiveBackground = Color.alphaBlend(
      countFill,
      routeBackground,
    );
    final countForeground = appReadableForeground(
      countEffectiveBackground,
      cs.onPrimaryContainer,
    );
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('mine.tile.more_apps')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: ColoredBox(
        color: isLiquidGlass
            ? Colors.transparent
            : routeBackground.withValues(alpha: 0.92),
        child: SafeArea(
          top: false,
          child: AppSecondaryControlTheme(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopTokens.reportMaxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceMd,
                    DesignTokens.spaceLg,
                    DesignTokens.spaceMd,
                    DesignTokens.space3xl,
                  ),
                  children: [
                _MoreAppsIntroCard(appCount: apps.length),
                const SizedBox(height: DesignTokens.spaceXl),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth =
                        constraints.maxWidth.isFinite &&
                            constraints.maxWidth > 0
                        ? constraints.maxWidth
                        : math.max(
                            0.0,
                            MediaQuery.sizeOf(context).width -
                                DesignTokens.spaceMd * 2,
                          );
                    final textScaler = MediaQuery.textScalerOf(context);
                    final textDirection =
                        Directionality.maybeOf(context) ?? TextDirection.ltr;

                    final headingText = _moreAppsText('功能入口', 'Features');
                    final headingStyle = appSecondaryMenuItemTextStyle(context)
                        .copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                          letterSpacing: 0.1,
                        );

                    final headingPainter = TextPainter(
                      text: TextSpan(text: headingText, style: headingStyle),
                      textDirection: textDirection,
                      textScaler: textScaler,
                      maxLines: 1,
                    )..layout();
                    final headingWidth = headingPainter.width;
                    headingPainter.dispose();

                    double countPillWidth = 0.0;
                    if (apps.isNotEmpty) {
                      final countText = I18n.current == AppLocale.en
                          ? '${apps.length} ${apps.length == 1 ? 'feature' : 'features'}'
                          : '${apps.length} 个';
                      final countStyle =
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: countForeground,
                            fontWeight: FontWeight.normal,
                          ) ??
                          const TextStyle();
                      final countPainter = TextPainter(
                        text: TextSpan(text: countText, style: countStyle),
                        textDirection: textDirection,
                        textScaler: textScaler,
                        maxLines: 1,
                      )..layout();
                      countPillWidth =
                          countPainter.width + DesignTokens.spaceSm * 2;
                      countPainter.dispose();
                    }

                    final canFitHeaderRow =
                        apps.isEmpty ||
                        (availableWidth -
                                countPillWidth -
                                DesignTokens.spaceSm) >=
                            (headingWidth + 8.0);

                    final headingBlock = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headingText, style: headingStyle),
                        const SizedBox(height: DesignTokens.spaceXxs),
                        Text(
                          _moreAppsText(
                            '点击卡片即可打开对应功能',
                            'Tap a card to open a feature',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant.withValues(
                                  alpha: 0.78,
                                ),
                              ),
                        ),
                      ],
                    );

                    final countWidget = apps.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spaceSm,
                              vertical: DesignTokens.spaceXs,
                            ),
                            decoration: BoxDecoration(
                              color: countFill,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(DesignTokens.radiusPill),
                              ),
                            ),
                            child: Text(
                              I18n.current == AppLocale.en
                                  ? '${apps.length} ${apps.length == 1 ? 'feature' : 'features'}'
                                  : '${apps.length} 个',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: countForeground,
                                    fontWeight: FontWeight.normal,
                                  ),
                            ),
                          )
                        : null;

                    if (canFitHeaderRow) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: headingBlock),
                          ?countWidget,
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        headingBlock,
                        if (countWidget != null) ...[
                          const SizedBox(height: DesignTokens.spaceSm),
                          countWidget,
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                if (apps.isEmpty)
                  AppSurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceLg,
                      vertical: DesignTokens.spaceXl,
                    ),
                    borderRadius: DesignTokens.borderRadiusLg,
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: cs.primary,
                          size: 22,
                        ),
                        const SizedBox(width: DesignTokens.spaceMd),
                        Expanded(
                          child: Text(
                            _moreAppsText(
                              '当前没有被隐藏的底部导航功能',
                              'No hidden navigation features',
                            ),
                            style: appSecondaryMenuItemTextStyle(context)
                                .copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.68),
                                ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth =
                          constraints.maxWidth.isFinite &&
                              constraints.maxWidth > 0
                          ? constraints.maxWidth
                          : math.max(
                              0.0,
                              MediaQuery.sizeOf(context).width -
                                  DesignTokens.spaceMd * 2,
                            );
                      final textScaler = MediaQuery.textScalerOf(context);
                      final textDirection =
                          Directionality.maybeOf(context) ?? TextDirection.ltr;
                      final labelStyle = _moreAppButtonTextStyle(context);

                      double maxLabelWidth = 0.0;
                      for (final app in apps) {
                        final painter = TextPainter(
                          text: TextSpan(text: app.label, style: labelStyle),
                          textDirection: textDirection,
                          textScaler: textScaler,
                          maxLines: 1,
                        )..layout();
                        if (painter.width > maxLabelWidth) {
                          maxLabelWidth = painter.width;
                        }
                        painter.dispose();
                      }

                      final crossAxisCount = _determineColumnCount(
                        availableWidth: availableWidth,
                        maxLabelWidth: maxLabelWidth,
                      );

                      final cardWidth =
                          (availableWidth -
                              (crossAxisCount - 1) *
                                  _kMoreAppGridCrossAxisSpacing) /
                          crossAxisCount;
                      final availableLabelWidth = math.max(
                        0.0,
                        cardWidth - _kMoreAppCardFixedHorizontalWidth,
                      );
                      final canFitSingleLine =
                          availableLabelWidth >=
                          (maxLabelWidth + _kMoreAppMeasurementRoundingMargin);
                      final allowWrap =
                          !canFitSingleLine && crossAxisCount == 1;

                      final cardHeight = _calculateCardHeight(
                        apps: apps,
                        style: labelStyle,
                        textScaler: textScaler,
                        textDirection: textDirection,
                        availableLabelWidth: availableLabelWidth,
                        canFitSingleLine: canFitSingleLine,
                      );

                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        mainAxisExtent: cardHeight,
                        crossAxisSpacing: _kMoreAppGridCrossAxisSpacing,
                        mainAxisSpacing: _kMoreAppGridMainAxisSpacing,
                        children: [
                          for (final app in apps)
                            MoreApplicationButton(
                              app: app,
                              allowWrap: allowWrap,
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
              ),
            ),
          ),
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
  }
}

class _MoreAppsIntroCard extends StatelessWidget {
  final int appCount;

  const _MoreAppsIntroCard({required this.appCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final textScaler = MediaQuery.textScalerOf(context);

    final titleStyle =
        Theme.of(context).textTheme.titleMedium?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.normal,
        ) ??
        const TextStyle();
    final bodyStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          height: 1.45,
        ) ??
        const TextStyle();
    final emptyStyle =
        Theme.of(context).textTheme.labelMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.normal,
        ) ??
        const TextStyle();

    final titleText = _moreAppsText('隐藏入口', 'Hidden features');
    final bodyText = _moreAppsText(
      '这里集中放置未显示在底部导航中的功能，随时可以继续使用。',
      'Features hidden from the bottom navigation are still available here.',
    );
    final emptyText = appCount == 0
        ? _moreAppsText(
            '所有功能都已固定在底部导航',
            'All features are shown in the bottom navigation',
          )
        : null;

    final iconWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: isDark ? 0.24 : 0.14),
        borderRadius: DesignTokens.borderRadiusLg,
      ),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceMd),
        child: Icon(Icons.apps_rounded, color: cs.primary, size: 26),
      ),
    );

    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleText, style: titleStyle),
        const SizedBox(height: DesignTokens.spaceXs),
        Text(bodyText, style: bodyStyle),
        if (emptyText != null) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(emptyText, style: emptyStyle),
        ],
      ],
    );

    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: DesignTokens.borderRadiusXl,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: DesignTokens.borderRadiusXl,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer.withValues(alpha: isDark ? 0.72 : 0.92),
              cs.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.52 : 0.62,
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const iconAndGapWidth = 50.0 + DesignTokens.spaceMd; // 62.0
              final availableTextWidth =
                  constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth - iconAndGapWidth
                  : math.max(
                      0.0,
                      MediaQuery.sizeOf(context).width -
                          DesignTokens.spaceMd * 2 -
                          DesignTokens.spaceLg * 2 -
                          iconAndGapWidth,
                    );

              double maxWordWidth = 0.0;
              void checkWords(String text, TextStyle style) {
                for (final word in text.split(RegExp(r'\s+'))) {
                  if (word.isEmpty) continue;
                  final painter = TextPainter(
                    text: TextSpan(text: word, style: style),
                    textDirection: textDirection,
                    textScaler: textScaler,
                    maxLines: 1,
                  )..layout();
                  if (painter.width > maxWordWidth) {
                    maxWordWidth = painter.width;
                  }
                  painter.dispose();
                }
              }

              checkWords(titleText, titleStyle);
              checkWords(bodyText, bodyStyle);
              if (emptyText != null) {
                checkWords(emptyText, emptyStyle);
              }

              final canFitHorizontal =
                  availableTextWidth >= (maxWordWidth + 8.0);

              if (canFitHorizontal) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconWidget,
                    const SizedBox(width: DesignTokens.spaceMd),
                    Expanded(child: textContent),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  iconWidget,
                  const SizedBox(height: DesignTokens.spaceMd),
                  textContent,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class MoreAppItem {
  final int tab;
  final IconData icon;
  final String label;
  final Color color;
  final WidgetBuilder builder;

  const MoreAppItem({
    required this.tab,
    required this.icon,
    required this.label,
    required this.color,
    required this.builder,
  });
}

class MoreApplicationButton extends StatelessWidget {
  final MoreAppItem app;
  final bool allowWrap;

  const MoreApplicationButton({
    super.key,
    required this.app,
    this.allowWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final radius = surfaceStyle != null
        ? BorderRadius.circular(surfaceStyle.smallTileRadius)
        : DesignTokens.borderRadiusMd;
    final cardFill = !isDark && surfaceStyle?.cardFillColor != null
        ? surfaceStyle!.cardFillColor!
        : cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.42 : 0.64);
    final cardBorder = !isDark && surfaceStyle?.cardBorder != null
        ? surfaceStyle!.cardBorder!
        : Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.34 : 0.42),
            width: _kMoreAppBorderWidth,
          );
    final cardShadows = !isDark && surfaceStyle != null
        ? surfaceStyle.cardShadow
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.13 : 0.045),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ];
    final iconBg = app.color.withValues(alpha: isDark ? 0.22 : 0.14);
    final iconColor = appReadableForeground(
      Color.alphaBlend(
        iconBg,
        Color.alphaBlend(cardFill, cs.surface),
      ),
      app.color,
    );
    return Semantics(
      button: true,
      label: I18n.current == AppLocale.en
          ? 'Open ${app.label}'
          : '打开${app.label}',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: cardFill,
            borderRadius: radius,
            border: cardBorder,
            boxShadow: cardShadows,
          ),
          child: InkWell(
            key: const ValueKey('more_application_button_tap_region'),
            borderRadius: radius,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return cs.primary.withValues(alpha: 0.16);
              }
              if (states.contains(WidgetState.selected)) {
                return cs.primary.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return cs.primary.withValues(alpha: 0.08);
              }
              return null;
            }),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (routeContext) =>
                      BrandRouteSurface(child: app.builder(routeContext)),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kMoreAppCardPaddingHorizontal,
                vertical: _kMoreAppCardPaddingVertical,
              ),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: _kMoreAppIconBoxSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: radius,
                      ),
                      child: Icon(app.icon, color: iconColor, size: 19),
                    ),
                  ),
                  const SizedBox(width: _kMoreAppIconTrailingSpacing),
                  Expanded(
                    child: Text(
                      app.label,
                      maxLines: allowWrap ? null : 1,
                      overflow: allowWrap ? null : TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(context).copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: _kMoreAppArrowLeadingSpacing),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: _kMoreAppArrowIconSize,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _moreAppsText(String zh, String en) =>
    I18n.current == AppLocale.en ? en : zh;
