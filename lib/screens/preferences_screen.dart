import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/settings_ui_copy.dart';
import '../core/web_target.dart';
import '../providers/preferences_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../widgets/settings_picker_tile.dart';
import '../widgets/surface_components.dart';

/// 个性设置入口页。这里只做二级入口，不直接承载具体设置项。
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final cs = Theme.of(context).colorScheme;
        final routeBackground = Theme.of(context).brightness == Brightness.dark
            ? cs.surface
            : cs.surfaceContainerLowest;
        return Scaffold(
          backgroundColor: routeBackground,
          appBar: AppBar(
            title: Text(SettingsUiCopy.preferencesTitle),
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.tune, color: cs.primary, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              I18n.tr('preferences.local.title'),
                              style: appSecondaryMenuItemTextStyle(
                                context,
                              ).copyWith(color: cs.onSurface),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              SettingsUiCopy.preferencesHeroExplanation,
                              softWrap: true,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
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
                AppSettingsSection(
                  title: SettingsUiCopy.preferencesCategoriesSectionTitle,
                  subtitle: SettingsUiCopy.preferencesCategoriesSectionSubtitle,
                  children: [
                    _PreferencesEntryTile(
                      icon: Icons.tune_outlined,
                      color: cs.primary,
                      title: SettingsUiCopy.displayAndBehaviorTitle,
                      subtitle: SettingsUiCopy.displayAndBehaviorSubtitle,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PersonalizationSettingsScreen(),
                        ),
                      ),
                    ),
                    _PreferencesEntryTile(
                      icon: Icons.space_dashboard_outlined,
                      color: Colors.blueGrey,
                      title: SettingsUiCopy.navigationSectionTitle,
                      subtitle: SettingsUiCopy.navigationSectionSubtitle,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BottomNavSettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Adaptive multiline entry tile for preferences screen index.
///
/// Ensures full title and explanatory subtitle wrap without ellipsis
/// on narrow widths (320px) and large text scales (1.6x).
class _PreferencesEntryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PreferencesEntryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final controlRadius =
        surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
    final controlBorderRadius = BorderRadius.circular(controlRadius);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: controlBorderRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: controlBorderRadius,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        softWrap: true,
                        style: appSecondaryMenuItemTextStyle(context).copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        softWrap: true,
                        style: appSecondaryControlLabelStyle(context).copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                          height: 1.35,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 纯本地的用户习惯，与服务器/管理员配置无关。
class PersonalizationSettingsScreen extends StatefulWidget {
  const PersonalizationSettingsScreen({super.key});

  @override
  State<PersonalizationSettingsScreen> createState() =>
      _PersonalizationSettingsScreenState();
}

class _PersonalizationSettingsScreenState
    extends State<PersonalizationSettingsScreen> {
  final GlobalKey _dateSectionKey = GlobalKey();
  final GlobalKey _defaultsSectionKey = GlobalKey();
  final GlobalKey _interactionSectionKey = GlobalKey();
  final GlobalKey _archiveSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToContext(BuildContext target) {
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  void _scrollToMenuTarget(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    _scrollToContext(target);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(SettingsUiCopy.displayAndBehaviorTitle),
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.tune, color: cs.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          I18n.tr('preferences.local.title'),
                          style: appSecondaryMenuItemTextStyle(
                            context,
                          ).copyWith(color: cs.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          SettingsUiCopy.displayAndBehaviorHeroSubtitle,
                          softWrap: true,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
            _PreferenceSectionMenu(
              groups: [
                _PreferenceMenuGroup(
                  title: SettingsUiCopy.jumpToMenuTitle,
                  items: [
                    _PreferenceMenuItem(
                      icon: Icons.calendar_month_outlined,
                      label: SettingsUiCopy.jumpToDate,
                      onTap: () => _scrollToMenuTarget(_dateSectionKey),
                    ),
                    _PreferenceMenuItem(
                      icon: Icons.tune_outlined,
                      label: SettingsUiCopy.jumpToDefaults,
                      onTap: () => _scrollToMenuTarget(_defaultsSectionKey),
                    ),
                    _PreferenceMenuItem(
                      icon: Icons.touch_app_outlined,
                      label: SettingsUiCopy.jumpToInteraction,
                      onTap: () => _scrollToMenuTarget(_interactionSectionKey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _dateSectionKey,
              child: AppSettingsSection(
                title: I18n.tr('preferences.section.date'),
                subtitle: I18n.tr('preferences.section.date.subtitle'),
                children: [
                  SettingsPickerTile<int>(
                    icon: Icons.calendar_view_week_outlined,
                    color: cs.primary,
                    titleBuilder: () => I18n.tr('preferences.first_day.title'),
                    subtitleBuilder: () => p.firstDayOfWeek == 1
                        ? I18n.tr('preferences.first_day.current_monday')
                        : I18n.tr('preferences.first_day.current_sunday'),
                    pickerTitleBuilder: () => SettingsUiCopy.selectFirstDay,
                    currentValue: p.firstDayOfWeek,
                    displayLabelBuilder: () => p.firstDayOfWeek == 1
                        ? I18n.tr('weekday.mon')
                        : I18n.tr('weekday.sun'),
                    optionsBuilder: () => [
                      SettingsPickerOption<int>(
                        value: 1,
                        title: I18n.tr('weekday.mon'),
                        subtitle: I18n.tr(
                          'preferences.first_day.current_monday',
                        ),
                      ),
                      SettingsPickerOption<int>(
                        value: 7,
                        title: I18n.tr('weekday.sun'),
                        subtitle: I18n.tr(
                          'preferences.first_day.current_sunday',
                        ),
                      ),
                    ],
                    onSelected: (v) {
                      context.read<PreferencesProvider>().setFirstDayOfWeek(v);
                    },
                  ),
                  SettingsPickerTile<String>(
                    icon: Icons.date_range_outlined,
                    color: Colors.teal,
                    titleBuilder: () =>
                        I18n.tr('preferences.date_format.title'),
                    subtitleBuilder: () =>
                        SettingsUiCopy.dateFormatSample(p.dateFormat),
                    pickerTitleBuilder: () => SettingsUiCopy.selectDateFormat,
                    currentValue: p.dateFormat,
                    displayLabelBuilder: () =>
                        SettingsUiCopy.dateFormatSample(p.dateFormat),
                    optionsBuilder: () => [
                      for (final pattern
                          in SettingsUiCopy.supportedDateFormatPatterns)
                        SettingsPickerOption<String>(
                          value: pattern,
                          title: SettingsUiCopy.dateFormatLabel(pattern),
                          subtitle: SettingsUiCopy.dateFormatSample(pattern),
                        ),
                    ],
                    onSelected: (v) {
                      context.read<PreferencesProvider>().setDateFormat(v);
                    },
                  ),
                  SettingsPickerTile<String>(
                    icon: Icons.public_outlined,
                    color: Colors.deepOrange,
                    titleBuilder: () => I18n.tr('preferences.timezone.title'),
                    subtitleBuilder: () => p.followSystemTimeZone
                        ? '${I18n.tr('preferences.timezone.follow_system')}：${SettingsUiCopy.timeZoneDisplayName(p.appTimeZone)}'
                        : SettingsUiCopy.timeZoneDisplayName(p.appTimeZone),
                    pickerTitleBuilder: () => SettingsUiCopy.selectTimeZone,
                    currentValue: p.appTimeZoneSelection,
                    displayLabelBuilder: () =>
                        SettingsUiCopy.timeZoneDisplayName(
                          p.appTimeZoneSelection,
                        ),
                    optionsBuilder: () => [
                      for (final id in SettingsUiCopy.supportedTimeZoneIds)
                        SettingsPickerOption<String>(
                          value: id,
                          title: SettingsUiCopy.timeZoneDisplayName(id),
                          subtitle: id == 'system'
                              ? I18n.tr('preferences.timezone.follow_system')
                              : id,
                        ),
                    ],
                    onSelected: (v) {
                      context.read<PreferencesProvider>().setAppTimeZone(v);
                    },
                  ),
                  AppSwitchTile(
                    icon: Icons.brightness_2_outlined,
                    color: Colors.indigo,
                    value: p.showLunar,
                    title: I18n.tr('preferences.lunar.title'),
                    subtitle: I18n.tr('preferences.lunar.subtitle'),
                    onChanged: (v) =>
                        context.read<PreferencesProvider>().setShowLunar(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _defaultsSectionKey,
              child: AppSettingsSection(
                title: I18n.tr('preferences.section.defaults'),
                subtitle: I18n.tr('preferences.section.defaults.subtitle'),
                children: [
                  SettingsPickerTile<int>(
                    icon: Icons.open_in_new,
                    color: Colors.blue,
                    titleBuilder: () =>
                        I18n.tr('preferences.default_tab.title'),
                    subtitleBuilder: () => _tabLabel(p.defaultTab),
                    pickerTitleBuilder: () => SettingsUiCopy.selectDefaultTab,
                    currentValue: p.defaultTab,
                    displayLabelBuilder: () => _tabLabel(p.defaultTab),
                    optionsBuilder: () => [
                      for (var tab = 0; tab <= 6; tab++)
                        if (PreferencesProvider.isBottomNavTabSupported(tab))
                          SettingsPickerOption<int>(
                            value: tab,
                            title: _tabLabel(tab),
                          ),
                    ],
                    onSelected: (v) {
                      context.read<PreferencesProvider>().setDefaultTab(v);
                    },
                  ),
                  AppSwitchTile(
                    icon: Icons.add_circle_outline,
                    color: cs.primary,
                    value: p.quickCaptureFab,
                    title: I18n.tr('preferences.quick_capture.title'),
                    subtitle: I18n.tr('preferences.quick_capture.subtitle'),
                    onChanged: (v) => context
                        .read<PreferencesProvider>()
                        .setQuickCaptureFab(v),
                  ),
                  AppSwitchTile(
                    icon: Icons.done_all,
                    color: Colors.green,
                    value: p.showCompletedTodos,
                    title: I18n.tr('preferences.show_completed.title'),
                    subtitle: I18n.tr('preferences.show_completed.subtitle'),
                    onChanged: (v) => context
                        .read<PreferencesProvider>()
                        .setShowCompletedTodos(v),
                  ),
                  _SliderSetting(
                    icon: Icons.timer_outlined,
                    color: Colors.red,
                    title: I18n.tr('preferences.pomodoro_length.title'),
                    subtitleBuilder: (value) =>
                        '${value.round()} ${I18n.tr('unit.minute')}',
                    value: p.defaultPomodoroMinutes.toDouble(),
                    min: 5,
                    max: 180,
                    divisions: 35,
                    labelBuilder: (value) =>
                        '${value.round()} ${I18n.tr('unit.min')}',
                    onChanged: (v) => p.setDefaultPomodoroMinutes(v.round()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _interactionSectionKey,
              child: Column(
                children: [
                  AppSettingsSection(
                    title: I18n.tr('preferences.section.interaction'),
                    subtitle: I18n.tr(
                      'preferences.section.interaction.subtitle',
                    ),
                    children: [
                      AppSwitchTile(
                        icon: Icons.vibration,
                        color: Colors.purple,
                        value: p.haptic,
                        title: I18n.tr('preferences.haptic.title'),
                        subtitle: I18n.tr('preferences.haptic.subtitle'),
                        onChanged: (v) =>
                            context.read<PreferencesProvider>().setHaptic(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: _archiveSectionKey,
                    child: AppSettingsSection(
                      title: I18n.tr('preferences.section.auto_archive'),
                      subtitle: I18n.tr(
                        'preferences.section.auto_archive.subtitle',
                      ),
                      children: [
                        _SliderSetting(
                          icon: Icons.inventory_2_outlined,
                          color: Colors.brown,
                          title: I18n.tr('preferences.auto_archive.title'),
                          subtitleBuilder: (value) => value.round() == 0
                              ? I18n.tr('preferences.auto_archive.never')
                              : '${value.round()} ${I18n.tr('preferences.auto_archive.after_days')}',
                          value: p.autoArchiveCompletedDays.toDouble(),
                          min: 0,
                          max: 365,
                          divisions: 365,
                          labelBuilder: (value) => value.round() == 0
                              ? I18n.tr('action.off')
                              : '${value.round()} ${I18n.tr('unit.day')}',
                          onChanged: (v) =>
                              p.setAutoArchiveCompletedDays(v.round()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BottomNavSettingsScreen extends StatelessWidget {
  const BottomNavSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final cs = Theme.of(context).colorScheme;
        final routeBackground = Theme.of(context).brightness == Brightness.dark
            ? cs.surface
            : cs.surfaceContainerLowest;
        return Scaffold(
          backgroundColor: routeBackground,
          appBar: AppBar(
            title: Text(I18n.tr('preferences.section.bottom_nav')),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            backgroundColor: routeBackground.withValues(alpha: 0.96),
            surfaceTintColor: Colors.transparent,
          ),
          body: AppSecondaryControlTheme(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                AppInfoBanner(
                  icon: Icons.space_dashboard_outlined,
                  title: I18n.tr('preferences.section.bottom_nav'),
                  message: SettingsUiCopy.navigationBannerMessage,
                  color: cs.primary,
                  margin: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                const _BottomNavSettingsSection(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomNavSettingsSection extends StatelessWidget {
  const _BottomNavSettingsSection();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();
    final tabs = WebTarget.isDesktopWebBuild
        ? p.bottomNavOrder
              .where(PreferencesProvider.isBottomNavTabSupported)
              .toList(growable: false)
        : p.bottomNavOrder;
    return AppSettingsSection(
      title: I18n.tr('preferences.section.bottom_nav'),
      subtitle: I18n.tr('preferences.section.bottom_nav.subtitle'),
      children: [
        for (final tab in tabs)
          _NavConfigTile(
            tab: tab,
            label: _tabLabel(tab),
            visible: p.bottomNavVisible.contains(tab),
            canMoveUp: p.bottomNavOrder.indexOf(tab) > 0,
            canMoveDown:
                p.bottomNavOrder.indexOf(tab) < p.bottomNavOrder.length - 1,
          ),
      ],
    );
  }
}

String _tabLabel(int index) {
  switch (index) {
    case 0:
      return I18n.tr('nav.today');
    case 1:
      return I18n.tr('nav.todo');
    case 2:
      return I18n.tr('nav.habit');
    case 3:
      return I18n.tr('nav.calendar');
    case 4:
      return I18n.tr('nav.focus');
    case 5:
      return I18n.tr('nav.widget');
    case 6:
      return I18n.tr('nav.mine');
    default:
      return I18n.tr('nav.today');
  }
}

class _PreferenceMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PreferenceMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _PreferenceMenuGroup {
  final String title;
  final List<_PreferenceMenuItem> items;

  const _PreferenceMenuGroup({required this.title, required this.items});
}

class _PreferenceSectionMenu extends StatelessWidget {
  final List<_PreferenceMenuGroup> groups;

  const _PreferenceSectionMenu({required this.groups});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups) ...[
            Text(
              group.title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11,
                height: 1.15,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in group.items)
                  ActionChip(
                    avatar: Icon(item.icon, size: 16, color: cs.primary),
                    label: Text(
                      item.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontSize: 11,
                        height: 1.12,
                        color: cs.onSurface,
                      ),
                    ),
                    onPressed: item.onTap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (group != groups.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _NavConfigTile extends StatelessWidget {
  final int tab;
  final String label;
  final bool visible;
  final bool canMoveUp;
  final bool canMoveDown;

  const _NavConfigTile({
    required this.tab,
    required this.label,
    required this.visible,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  IconData get _icon => switch (tab) {
    0 => Icons.today_outlined,
    1 => Icons.checklist,
    2 => Icons.repeat,
    3 => Icons.calendar_month_outlined,
    4 => Icons.timer_outlined,
    5 => Icons.widgets_outlined,
    _ => Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final lockedVisible = PreferencesProvider.fixedBottomNavTabs.contains(tab);
    final p = context.watch<PreferencesProvider>();
    final visibleCount = p.bottomNavVisible.length;
    final reachedLimit =
        !visible && visibleCount >= PreferencesProvider.maxBottomNavTabs;
    final subtitle = lockedVisible
        ? I18n.tr('preferences.nav.fixed')
        : reachedLimit
        ? SettingsUiCopy.maxTabsConstraint(PreferencesProvider.maxBottomNavTabs)
        : visible
        ? I18n.tr('preferences.nav.visible')
        : I18n.tr('preferences.nav.hidden');

    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final controlRadius =
        surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
    final controlBorderRadius = BorderRadius.circular(controlRadius);

    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final textScale = media.textScaler.scale(1.0);
        final shouldStack = constraints.maxWidth < 320 || textScale >= 1.25;

        final iconWidget = Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: controlBorderRadius,
          ),
          child: Icon(_icon, color: cs.primary, size: 18),
        );

        final textColumn = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              softWrap: true,
              style: appSecondaryMenuItemTextStyle(
                context,
              ).copyWith(color: cs.onSurface, fontWeight: FontWeight.normal),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              softWrap: true,
              style: appSecondaryControlLabelStyle(context).copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        );

        final actionsWidget = _NavConfigActions(
          tab: tab,
          visible: visible,
          lockedVisible: lockedVisible,
          reachedLimit: reachedLimit,
          canMoveUp: canMoveUp,
          canMoveDown: canMoveDown,
        );

        return Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: shouldStack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          iconWidget,
                          const SizedBox(width: 10),
                          Expanded(child: textColumn),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.only(
                          left: constraints.maxWidth < 260 ? 0 : 44,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [actionsWidget],
                        ),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      iconWidget,
                      const SizedBox(width: 10),
                      Expanded(child: textColumn),
                      const SizedBox(width: 8),
                      actionsWidget,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _NavConfigActions extends StatelessWidget {
  final int tab;
  final bool visible;
  final bool lockedVisible;
  final bool reachedLimit;
  final bool canMoveUp;
  final bool canMoveDown;

  const _NavConfigActions({
    required this.tab,
    required this.visible,
    required this.lockedVisible,
    required this.reachedLimit,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    Widget compactIconButton({
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      );
    }

    return Row(
      key: ValueKey('bottom_nav_actions_$tab'),
      mainAxisSize: MainAxisSize.min,
      children: [
        compactIconButton(
          tooltip: I18n.tr('action.move_up'),
          onPressed: canMoveUp
              ? () => context.read<PreferencesProvider>().moveBottomNavTab(
                  tab,
                  -1,
                )
              : null,
          icon: Icons.keyboard_arrow_up_rounded,
        ),
        compactIconButton(
          tooltip: I18n.tr('action.move_down'),
          onPressed: canMoveDown
              ? () =>
                    context.read<PreferencesProvider>().moveBottomNavTab(tab, 1)
              : null,
          icon: Icons.keyboard_arrow_down_rounded,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: visible,
              onChanged: lockedVisible || reachedLimit
                  ? null
                  : (v) => context
                        .read<PreferencesProvider>()
                        .setBottomNavVisible(tab, v),
            ),
          ),
        ),
      ],
    );
  }
}

class _SliderSetting extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String Function(double) subtitleBuilder;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelBuilder;
  final Future<void> Function(double) onChanged;

  const _SliderSetting({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitleBuilder,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  State<_SliderSetting> createState() => _SliderSettingState();
}

class _SliderSettingState extends State<_SliderSetting> {
  double? _draftValue;
  bool _dragging = false;
  bool _saving = false;
  int _interactionGeneration = AccountLocalDataCleaner.accountDataGeneration;
  int? _dragGeneration;

  double get _value =>
      (_draftValue ?? widget.value).clamp(widget.min, widget.max);

  @override
  void didUpdateWidget(covariant _SliderSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_interactionGeneration !=
        AccountLocalDataCleaner.accountDataGeneration) {
      _interactionGeneration = AccountLocalDataCleaner.accountDataGeneration;
      _draftValue = null;
      _dragging = false;
      _saving = false;
    } else if (!_dragging &&
        !_saving &&
        (oldWidget.value != widget.value ||
            oldWidget.min != widget.min ||
            oldWidget.max != widget.max)) {
      _draftValue = null;
    }
  }

  Future<void> _finishDrag(double value) async {
    final generation = _dragGeneration ?? _interactionGeneration;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
      setState(() {
        _draftValue = null;
        _dragging = false;
        _dragGeneration = null;
      });
      return;
    }
    setState(() {
      _dragging = false;
      _dragGeneration = null;
      _draftValue = value;
      _saving = true;
    });
    try {
      await widget.onChanged(value);
    } catch (_) {
      if (mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, _, _) => Text(SettingsUiCopy.saveFailed),
            ),
          ),
        );
      }
    } finally {
      if (mounted &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation)) {
        setState(() {
          _saving = false;
          _draftValue = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      softWrap: true,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitleBuilder(_value),
                      softWrap: true,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.labelBuilder(_value),
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            value: _value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: widget.labelBuilder(_value),
            onChangeStart: (_) {
              _dragGeneration = AccountLocalDataCleaner.accountDataGeneration;
            },
            onChanged: _saving
                ? null
                : (value) {
                    if (_dragGeneration != null &&
                        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
                          _dragGeneration!,
                        )) {
                      return;
                    }
                    setState(() {
                      _dragging = true;
                      _draftValue = value;
                    });
                  },
            onChangeEnd: _finishDrag,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: SettingsUiCopy.decreaseValue,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: _saving || _dragging || _value <= widget.min
                    ? null
                    : () => _finishDrag(
                        (_value - (widget.max - widget.min) / widget.divisions)
                            .clamp(widget.min, widget.max),
                      ),
                icon: const Icon(Icons.remove_rounded, size: 20),
              ),
              IconButton(
                tooltip: SettingsUiCopy.increaseValue,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: _saving || _dragging || _value >= widget.max
                    ? null
                    : () => _finishDrag(
                        (_value + (widget.max - widget.min) / widget.divisions)
                            .clamp(widget.min, widget.max),
                      ),
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
