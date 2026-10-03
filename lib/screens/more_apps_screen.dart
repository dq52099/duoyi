import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/web_target.dart';
import '../providers/preferences_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import 'calendar_screen.dart';
import 'habit_screen.dart';
import 'today_screen.dart';
import 'todo_screen.dart';
import 'widget_screen.dart';

class MoreApplicationsScreen extends StatelessWidget {
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
        label: '今日',
        color: Colors.blue,
        builder: (_) => const TodayScreen(),
      ),
      MoreAppItem(
        tab: 1,
        icon: Icons.checklist,
        label: '待办',
        color: Colors.green,
        builder: (_) => const TodoScreen(),
      ),
      MoreAppItem(
        tab: 2,
        icon: Icons.repeat,
        label: '习惯',
        color: Colors.teal,
        builder: (_) => const HabitScreen(),
      ),
      MoreAppItem(
        tab: 3,
        icon: Icons.calendar_month_outlined,
        label: '日历',
        color: Colors.indigo,
        builder: (_) => const CalendarScreen(),
      ),
      MoreAppItem(
        tab: 5,
        icon: Icons.widgets_outlined,
        label: '小组件',
        color: Colors.deepPurple,
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
    final cs = Theme.of(context).colorScheme;
    final apps = MoreApplicationsScreen.hiddenBottomNavApps(
      context.watch<PreferencesProvider>(),
      visibleBottomNavTabs: visibleBottomNavTabs,
    );
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('更多应用'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: ColoredBox(
        color: routeBackground.withValues(alpha: 0.92),
        child: SafeArea(
          top: false,
          child: AppSecondaryControlTheme(
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '功能入口',
                            style: appSecondaryMenuItemTextStyle(context)
                                .copyWith(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.normal,
                                  letterSpacing: 0.1,
                                ),
                          ),
                          const SizedBox(height: DesignTokens.spaceXxs),
                          Text(
                            '点击卡片即可打开对应功能',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.78,
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (apps.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spaceSm,
                          vertical: DesignTokens.spaceXs,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.72),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(DesignTokens.radiusPill),
                          ),
                        ),
                        child: Text(
                          '${apps.length} 个',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.normal,
                              ),
                        ),
                      ),
                  ],
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
                            '当前没有被隐藏的底部导航功能',
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
                      final width = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width;
                      final veryNarrow = width < 280;
                      final compact = width < 520;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: veryNarrow
                            ? 1
                            : compact
                            ? 2
                            : 3,
                        childAspectRatio: veryNarrow
                            ? 3.0
                            : compact
                            ? 2.55
                            : 3.3,
                        crossAxisSpacing: DesignTokens.spaceSm,
                        mainAxisSpacing: DesignTokens.spaceMd,
                        children: [
                          for (final app in apps)
                            MoreApplicationButton(app: app),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.24 : 0.14),
                  borderRadius: DesignTokens.borderRadiusLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spaceMd),
                  child: Icon(Icons.apps_rounded, color: cs.primary, size: 26),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '隐藏入口',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceXs),
                    Text(
                      '这里集中放置未显示在底部导航中的功能，随时可以继续使用。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (appCount == 0) ...[
                      const SizedBox(height: DesignTokens.spaceSm),
                      Text(
                        '所有功能都已固定在底部导航',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.normal,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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

  const MoreApplicationButton({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = DesignTokens.borderRadiusMd;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: '打开${app.label}',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(
              alpha: isDark ? 0.42 : 0.64,
            ),
            borderRadius: radius,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.34 : 0.42),
              width: 0.55,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.13 : 0.045),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
                horizontal: DesignTokens.spaceMd,
                vertical: DesignTokens.spaceSm,
              ),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: app.color.withValues(
                          alpha: isDark ? 0.22 : 0.14,
                        ),
                        borderRadius: DesignTokens.borderRadiusMd,
                      ),
                      child: Icon(app.icon, color: app.color, size: 19),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(
                    child: Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(context).copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceXs),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
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
