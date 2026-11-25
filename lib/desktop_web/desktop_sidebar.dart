import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/almanac_ui_copy.dart';
import '../core/app_brand.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../services/holiday_calendar.dart';
import '../widgets/cached_avatar_image.dart';
import 'desktop_web_nav.dart';
import 'desktop_web_tokens.dart';

/// Persistent 248px Desktop Web workspace sidebar.
class DesktopSidebar extends StatelessWidget {
  final DesktopWebNavController controller;

  const DesktopSidebar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) => _buildSidebar(context, locale),
    );
  }

  R _selectOptional<P, R>(
    BuildContext context,
    R Function(P? provider) selector,
    R fallback,
  ) {
    try {
      return context.select<P?, R>(selector);
    } on ProviderNotFoundException {
      return fallback;
    }
  }

  Widget _buildSidebar(BuildContext context, AppLocale locale) {
    final tokens = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;
    final activeDest = controller.destination;

    final now = DateTime.now();
    final todayDay = DateTime(now.year, now.month, now.day);

    final (todayTodoCount, activeTodoCount) = _selectOptional<TodoProvider, (int, int)>(
      context,
      (p) {
        if (p == null) return (0, 0);
        final todayPending = p
            .visibleTodayTodos(now)
            .where((t) => !t.isCompleted)
            .length;
        return (todayPending, p.activeTodos.length);
      },
      (0, 0),
    );
    final pendingHabitCount = _selectOptional<HabitProvider, int>(
      context,
      (p) =>
          p?.habits
              .where((h) => h.isActiveToday() && !h.isCompletedToday())
              .length ??
          0,
      0,
    );
    final todayEventCount = _selectOptional<CalendarProvider, int>(
      context,
      (p) =>
          p?.events
              .where(
                (e) =>
                    e.date.year == todayDay.year &&
                    e.date.month == todayDay.month &&
                    e.date.day == todayDay.day,
              )
              .length ??
          0,
      0,
    );
    final countdownCount = _selectOptional<CountdownProvider, int>(
      context,
      (p) => p?.items.length ?? 0,
      0,
    );
    final activeGoalCount = _selectOptional<GoalProvider, int>(
      context,
      (p) => p?.activeGoals.length ?? 0,
      0,
    );
    final activeNoteCount = _selectOptional<NoteProvider, int>(
      context,
      (p) => p?.activeNotes.length ?? 0,
      0,
    );
    final activeBrand = _selectOptional<ThemeProvider, AppBrand?>(
      context,
      (p) => p?.brand,
      null,
    );

    final workspaceItems = <DesktopWebDestination>[
      DesktopWebDestination.today,
      DesktopWebDestination.todo,
      DesktopWebDestination.habit,
      DesktopWebDestination.calendar,
      DesktopWebDestination.focus,
    ];
    final toolItems = <DesktopWebDestination>[
      DesktopWebDestination.almanac,
      DesktopWebDestination.goals,
      DesktopWebDestination.notes,
      DesktopWebDestination.diary,
      DesktopWebDestination.stats,
      DesktopWebDestination.timeAudit,
      DesktopWebDestination.schedule,
      DesktopWebDestination.anniversary,
      DesktopWebDestination.countdown,
    ];

    final sidebarInner = Container(
      key: const ValueKey('desktop_workspace_sidebar'),
      width: DesktopWebTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: tokens.sidebarBackground,
        border: Border(
          right: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarBrandHeader(
            isEn: isEn,
            brandName: activeBrand?.localizedName,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SidebarSearchButton(
                  isEn: isEn,
                  onTap: () => controller.openCommandPalette(
                    initialMode: DesktopCommandMode.search,
                  ),
                ),
                const SizedBox(height: 8),
                _SidebarQuickCreateButton(
                  isEn: isEn,
                  onSelectKind: controller.triggerQuickCreate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              children: [
                _SectionTitle(
                  label: DesktopWebDestination.today.sectionLabel(locale),
                ),
                const SizedBox(height: 4),
                for (final dest in workspaceItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _SidebarNavItem(
                      destination: dest,
                      label: dest.localizedLabel(locale),
                      selected: activeDest == dest,
                      trailing: _trailingForDestination(
                        dest,
                        tokens: tokens,
                        todayTodoCount: todayTodoCount,
                        activeTodoCount: activeTodoCount,
                        pendingHabitCount: pendingHabitCount,
                        todayEventCount: todayEventCount,
                        activeGoalCount: activeGoalCount,
                        activeNoteCount: activeNoteCount,
                        countdownCount: countdownCount,
                      ),
                      onTap: () => controller.navigateTo(
                        dest,
                        clearSelectedEntity: true,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                _SectionTitle(
                  label: DesktopWebDestination.goals.sectionLabel(locale),
                ),
                const SizedBox(height: 4),
                for (final dest in toolItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _SidebarNavItem(
                      destination: dest,
                      label: dest.localizedLabel(locale),
                      selected: activeDest == dest,
                      trailing: _trailingForDestination(
                        dest,
                        tokens: tokens,
                        todayTodoCount: todayTodoCount,
                        activeTodoCount: activeTodoCount,
                        pendingHabitCount: pendingHabitCount,
                        todayEventCount: todayEventCount,
                        activeGoalCount: activeGoalCount,
                        activeNoteCount: activeNoteCount,
                        countdownCount: countdownCount,
                      ),
                      onTap: () => controller.navigateTo(
                        dest,
                        clearSelectedEntity: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _SidebarBottomDock(
            controller: controller,
            locale: locale,
          ),
        ],
      ),
    );

    final blurSigma = kIsWeb
        ? math.min(tokens.glassBlurSigma, DesktopWebTokens.webChromeBlurSigma)
        : tokens.glassBlurSigma;
    if (blurSigma > 0) {
      return RepaintBoundary(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
            ),
            child: sidebarInner,
          ),
        ),
      );
    }
    return RepaintBoundary(child: sidebarInner);
  }

  Widget? _trailingForDestination(
    DesktopWebDestination dest, {
    required DesktopWebTokens tokens,
    required int todayTodoCount,
    required int activeTodoCount,
    required int pendingHabitCount,
    required int todayEventCount,
    required int activeGoalCount,
    required int activeNoteCount,
    int countdownCount = 0,
  }) {
    if (dest == DesktopWebDestination.focus) {
      return _SidebarFocusBadge(tokens: tokens);
    }

    if (dest == DesktopWebDestination.almanac) {
      final today = DateTime.now();
      final isHoliday = HolidayCalendar.isHoliday(today);
      final isMakeup = !isHoliday && HolidayCalendar.isWorkMakeupDay(today);
      if (!isHoliday && !isMakeup) return null;
      final tagColor = isHoliday ? tokens.success : tokens.warning;
      final label = isHoliday
          ? AlmanacUiCopy.holidayTag
          : AlmanacUiCopy.makeupWorkdayTag;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: tagColor.withValues(alpha: tokens.isDark ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
        ),
        child: Text(
          label,
          style: tokens.captionStyle.copyWith(
            color: tagColor,
            fontSize: 10.5,
          ),
        ),
      );
    }

    final int count = switch (dest) {
      DesktopWebDestination.today => todayTodoCount,
      DesktopWebDestination.todo => activeTodoCount,
      DesktopWebDestination.habit => pendingHabitCount,
      DesktopWebDestination.calendar => todayEventCount,
      DesktopWebDestination.goals => activeGoalCount,
      DesktopWebDestination.notes => activeNoteCount,
      DesktopWebDestination.countdown => countdownCount,
      _ => 0,
    };

    if (count <= 0) return null;
    final selected = controller.destination == dest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: selected ? tokens.accentSoft : tokens.mutedSurface,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: tokens.captionStyle.copyWith(
          color: selected ? tokens.accent : tokens.textMuted,
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SidebarFocusBadge extends StatelessWidget {
  final DesktopWebTokens tokens;

  const _SidebarFocusBadge({required this.tokens});

  @override
  Widget build(BuildContext context) {
    bool isRunning = false;
    try {
      isRunning = context.select<PomodoroProvider?, bool>(
        (p) => p?.state.isRunning ?? false,
      );
    } on ProviderNotFoundException {
      isRunning = false;
    }
    if (!isRunning) return const SizedBox.shrink();
    final pomodoroProvider = context.read<PomodoroProvider?>();
    if (pomodoroProvider == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: pomodoroProvider.timerTicks,
      builder: (context, _, _) {
        final state = pomodoroProvider.state;
        if (!state.isRunning) return const SizedBox.shrink();
        final mins = (state.remainingSeconds ~/ 60).toString().padLeft(2, '0');
        final secs = (state.remainingSeconds % 60).toString().padLeft(2, '0');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
          ),
          child: Text(
            '$mins:$secs',
            style: tokens.captionStyle.copyWith(
              color: tokens.accent,
              fontSize: 10.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

class _SidebarBrandHeader extends StatelessWidget {
  final bool isEn;
  final String? brandName;

  const _SidebarBrandHeader({
    required this.isEn,
    this.brandName,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final title = isEn ? 'Duoyi' : '多仪';
    final rawBrand = brandName?.trim();
    final subtitle =
        (rawBrand == null ||
            rawBrand.isEmpty ||
            rawBrand == '多仪' ||
            rawBrand == 'Duoyi')
        ? (isEn ? 'Productivity Workspace' : '效率工作台')
        : rawBrand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 12),
      child: Row(
        children: [
          const _DuoyiDesktopLogo(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.cardTitleStyle.copyWith(fontSize: 15),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.captionStyle.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tokens.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
              border: Border.all(
                color: tokens.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Text(
              'Web',
              style: tokens.captionStyle.copyWith(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSearchButton extends StatefulWidget {
  final bool isEn;
  final VoidCallback onTap;

  const _SidebarSearchButton({
    required this.isEn,
    required this.onTap,
  });

  @override
  State<_SidebarSearchButton> createState() => _SidebarSearchButtonState();
}

class _SidebarSearchButtonState extends State<_SidebarSearchButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: const ValueKey('desktop_sidebar_search_trigger'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? tokens.hoverSurface : tokens.mutedSurface,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
            border: Border.all(
              color: _hovered ? tokens.strongBorder : tokens.hairlineBorder,
              width: DesktopWebTokens.hairlineWidth,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 15, color: tokens.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isEn ? 'Search...' : '搜索...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyMutedStyle.copyWith(
                    color: tokens.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const DesktopKeycap(label: '⌘K'),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarQuickCreateButton extends StatefulWidget {
  final bool isEn;
  final ValueChanged<DesktopQuickCreateKind> onSelectKind;

  const _SidebarQuickCreateButton({
    required this.isEn,
    required this.onSelectKind,
  });

  @override
  State<_SidebarQuickCreateButton> createState() =>
      _SidebarQuickCreateButtonState();
}

class _SidebarQuickCreateButtonState extends State<_SidebarQuickCreateButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final isEn = widget.isEn;
    final bg = _hovered
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.08), tokens.accent)
        : tokens.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<DesktopQuickCreateKind>(
        key: const ValueKey('desktop_sidebar_quick_create'),
        tooltip: isEn ? 'Quick create' : '快速新建',
        offset: const Offset(0, 40),
        color: tokens.elevatedSurface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
          side: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
        onSelected: widget.onSelectKind,
        itemBuilder: (context) => [
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.todo,
            Icons.check_circle_outline,
            isEn ? 'New Task' : '新建待办',
          ),
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.habit,
            Icons.repeat_rounded,
            isEn ? 'New Habit' : '新建习惯',
          ),
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.goal,
            Icons.flag_outlined,
            isEn ? 'New Goal' : '新建目标',
          ),
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.note,
            Icons.edit_note_rounded,
            isEn ? 'New Note' : '随手记',
          ),
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.diary,
            Icons.menu_book_outlined,
            isEn ? 'Write Diary' : '写日记',
          ),
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.calendarEvent,
            Icons.event_available_outlined,
            isEn ? 'New Event' : '新建日程',
          ),
          _buildMenuItem(
            tokens,
            DesktopQuickCreateKind.focus,
            Icons.timer_outlined,
            isEn ? 'Start 25m Focus' : '开始番茄专注',
          ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                size: 16,
                color: tokens.accentForeground,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isEn ? 'Quick Create' : '快速新建',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(
                    color: tokens.accentForeground,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: tokens.accentForeground.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<DesktopQuickCreateKind> _buildMenuItem(
    DesktopWebTokens tokens,
    DesktopQuickCreateKind kind,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<DesktopQuickCreateKind>(
      value: kind,
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tokens.accent),
          const SizedBox(width: 10),
          Text(label, style: tokens.bodyStyle.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tokens.sectionHeaderStyle,
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final DesktopWebDestination destination;
  final String label;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.destination,
    required this.label,
    required this.selected,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        DesktopHoverTile(
          key: ValueKey('desktop_nav_${destination.name}'),
          selected: selected,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 17,
                color: selected ? tokens.accent : tokens.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.navItemStyle.copyWith(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ],
            ],
          ),
        ),
        if (selected)
          Positioned(
            left: 0,
            top: 7,
            bottom: 7,
            child: IgnorePointer(
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SidebarBottomDock extends StatelessWidget {
  final DesktopWebNavController controller;
  final AppLocale locale;

  const _SidebarBottomDock({
    required this.controller,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;
    final activeDest = controller.destination;
    final isLiquidGlass = tokens.isLiquidGlass;
    final isDark = tokens.isDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: tokens.mutedSurface,
              borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
              border: Border.all(
                color: tokens.hairlineBorder,
                width: DesktopWebTokens.hairlineWidth,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ThemeToggleChip(
                    key: const ValueKey('desktop_theme_toggle_default'),
                    label: isEn ? 'iOS' : 'iOS 默认',
                    selected: !isLiquidGlass,
                    onTap: () => _switchSurface(context, frosted: false),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: _ThemeToggleChip(
                    key: const ValueKey('desktop_theme_toggle_glass'),
                    label: isEn ? 'Glass' : '毛玻璃',
                    selected: isLiquidGlass,
                    onTap: () => _switchSurface(context, frosted: true),
                  ),
                ),
                const SizedBox(width: 2),
                _BrightnessToggleButton(
                  key: const ValueKey('desktop_theme_toggle_brightness'),
                  isDark: isDark,
                  tooltip: isEn ? 'Toggle light/dark' : '深浅切换',
                  onTap: () => controller.toggleDarkMode(
                    isDark ? Brightness.dark : Brightness.light,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DesktopHoverTile(
                  key: const ValueKey('desktop_nav_themes'),
                  selected: activeDest == DesktopWebDestination.themes,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  onTap: () => controller.navigateTo(DesktopWebDestination.themes),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 15,
                        color: activeDest == DesktopWebDestination.themes
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          DesktopWebDestination.themes.localizedLabel(locale),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.captionStyle.copyWith(
                            color: activeDest == DesktopWebDestination.themes
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: DesktopHoverTile(
                  key: const ValueKey('desktop_nav_moreApps'),
                  selected: activeDest == DesktopWebDestination.moreApps,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  onTap: () =>
                      controller.navigateTo(DesktopWebDestination.moreApps),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.grid_view_outlined,
                        size: 15,
                        color: activeDest == DesktopWebDestination.moreApps
                            ? tokens.accent
                            : tokens.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          DesktopWebDestination.moreApps.localizedLabel(locale),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.captionStyle.copyWith(
                            color: activeDest == DesktopWebDestination.moreApps
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _AccountDockCard(
            selected: activeDest == DesktopWebDestination.settings,
            isEn: isEn,
            onTap: () => controller.navigateTo(DesktopWebDestination.settings),
          ),
        ],
      ),
    );
  }

  void _switchSurface(BuildContext context, {required bool frosted}) {
    controller.setFrostedOverride(frosted);
    ThemeProvider? tp;
    try {
      tp = context.read<ThemeProvider?>();
    } on ProviderNotFoundException {
      tp = null;
    }
    if (tp == null) return;
    if (frosted) {
      if (tp.isBrandUnlocked(AppBrands.liquidGlass.id) &&
          tp.brand.id != AppBrands.liquidGlass.id) {
        tp.setBrand(AppBrands.liquidGlass.id);
      }
    } else {
      if (tp.brand.id == AppBrands.liquidGlass.id) {
        tp.setBrand(AppBrands.defaultBrand.id);
      }
    }
  }
}

class _ThemeToggleChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ThemeToggleChip> createState() => _ThemeToggleChipState();
}

class _ThemeToggleChipState extends State<_ThemeToggleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? tokens.panelSurface
                : (_hovered ? tokens.hoverSurface : Colors.transparent),
            borderRadius: BorderRadius.circular(5),
            border: widget.selected
                ? Border.all(
                    color: tokens.hairlineBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  )
                : null,
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.captionStyle.copyWith(
              color: widget.selected ? tokens.textPrimary : tokens.textMuted,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrightnessToggleButton extends StatefulWidget {
  final bool isDark;
  final String tooltip;
  final VoidCallback onTap;

  const _BrightnessToggleButton({
    super.key,
    required this.isDark,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_BrightnessToggleButton> createState() =>
      _BrightnessToggleButtonState();
}

class _BrightnessToggleButtonState extends State<_BrightnessToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? tokens.hoverSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              widget.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 14,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountDockCard extends StatelessWidget {
  final bool selected;
  final bool isEn;
  final VoidCallback onTap;

  const _AccountDockCard({
    required this.selected,
    required this.isEn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    ({bool isLoggedIn, String? displayName, String? username, String? avatar})
    authSlice;
    try {
      authSlice = context.select<
        AuthProvider?,
        ({
          bool isLoggedIn,
          String? displayName,
          String? username,
          String? avatar,
        })
      >(
        (p) => (
          isLoggedIn: p?.state.isLoggedIn ?? false,
          displayName: p?.state.displayName,
          username: p?.state.username,
          avatar: p?.state.avatar,
        ),
      );
    } on ProviderNotFoundException {
      authSlice = (
        isLoggedIn: false,
        displayName: null,
        username: null,
        avatar: null,
      );
    }

    ({
      String displayName,
      String username,
      String avatarUrl,
      String avatarInitials,
    })
    profileSlice;
    try {
      profileSlice = context.select<
        UserProvider?,
        ({
          String displayName,
          String username,
          String avatarUrl,
          String avatarInitials,
        })
      >(
        (p) => (
          displayName: p?.profile.displayName ?? '',
          username: p?.profile.username ?? '',
          avatarUrl: p?.profile.avatarUrl ?? '',
          avatarInitials: p?.profile.avatarInitials ?? '',
        ),
      );
    } on ProviderNotFoundException {
      profileSlice = (
        displayName: '',
        username: '',
        avatarUrl: '',
        avatarInitials: '',
      );
    }

    final isLoggedIn = authSlice.isLoggedIn;

    String? resolveName(String? raw) {
      final trimmed = raw?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      if (!isLoggedIn && trimmed == '用户') return null;
      return trimmed;
    }

    String? resolveInitials(String? raw) {
      final trimmed = raw?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      if (!isLoggedIn && trimmed == '我') return null;
      return trimmed;
    }

    final rawName =
        resolveName(authSlice.displayName) ??
        resolveName(profileSlice.displayName) ??
        resolveName(authSlice.username) ??
        resolveName(profileSlice.username) ??
        (isEn ? 'Local Workspace' : '本地工作区');

    final avatarUrl =
        (authSlice.avatar?.trim().isNotEmpty == true
            ? authSlice.avatar!.trim()
            : null) ??
        (profileSlice.avatarUrl.trim().isNotEmpty
            ? profileSlice.avatarUrl.trim()
            : null) ??
        '';

    final initials =
        resolveInitials(profileSlice.avatarInitials) ??
        (!isLoggedIn && !isEn && profileSlice.avatarInitials.trim() == '我'
            ? '我'
            : (rawName.isNotEmpty ? rawName.substring(0, 1).toUpperCase() : 'L'));

    final subtitle = isLoggedIn
        ? (isEn ? 'Synced · Settings' : '云同步账号 · 设置')
        : (isEn ? 'Guest · Sign in / Settings' : '本地空间 · 登录 / 设置');

    return DesktopHoverTile(
      key: const ValueKey('desktop_sidebar_account_card'),
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      borderRadius: BorderRadius.circular(DesktopWebTokens.radiusMd),
      child: Row(
        children: [
          _DesktopAvatar(
            url: avatarUrl,
            initials: initials,
            size: 30,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rawName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.bodyStyle.copyWith(fontSize: 12.5),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.captionStyle.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          Icon(
            Icons.settings_outlined,
            size: 15,
            color: selected ? tokens.accent : tokens.textMuted,
          ),
        ],
      ),
    );
  }
}

class _DesktopAvatar extends StatelessWidget {
  final String url;
  final String initials;
  final double size;

  const _DesktopAvatar({
    required this.url,
    required this.initials,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    Widget fallback() => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(DesktopWebTokens.radiusPill),
        border: Border.all(
          color: tokens.accentBorder,
          width: DesktopWebTokens.hairlineWidth,
        ),
      ),
      child: Text(
        initials,
        style: tokens.captionStyle.copyWith(
          color: tokens.accent,
          fontSize: size * 0.42,
        ),
      ),
    );

    if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://') && kIsWeb)) {
      return fallback();
    }

    if (kIsWeb) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        ),
      );
    }

    return ClipOval(
      child: CachedAvatarImage(
        url: url,
        width: size,
        height: size,
        fallbackBuilder: (_) => fallback(),
      ),
    );
  }
}

class _DuoyiDesktopLogo extends StatelessWidget {
  final double size;

  const _DuoyiDesktopLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/logo/duoyi_logo_192.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF007AFF), Color(0xFF0051AB)],
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.schedule_rounded,
            size: size * 0.56,
            color: tokens.accentForeground,
          ),
        ),
      ),
    );
  }
}
