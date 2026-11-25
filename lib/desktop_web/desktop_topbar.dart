import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/pomodoro_provider.dart';
import 'desktop_web_nav.dart';
import 'desktop_web_tokens.dart';

/// Unified 56px flush Desktop Web header bar with breadcrumb/title on the left
/// and page-specific actions on the right.
class DesktopTopBar extends StatelessWidget {
  final DesktopWebNavController controller;

  const DesktopTopBar({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) => ListenableBuilder(
        listenable: Listenable.merge([
          controller,
          controller.topBarListenable,
        ]),
        builder: (context, _) => _buildBar(context, locale),
      ),
    );
  }

  Widget _buildBar(BuildContext context, AppLocale locale) {
    final tokens = DesktopWebTokens.of(context);
    final isEn = locale == AppLocale.en;
    final dest = controller.destination;
    final customSpec = controller.topBarSpecFor(dest);
    final spec = customSpec ?? _defaultSpecFor(context, dest, locale);

    final bool showFocusPill;
    if (dest == DesktopWebDestination.focus) {
      showFocusPill = false;
    } else {
      bool running;
      try {
        running = context.select<PomodoroProvider?, bool>(
          (p) => p != null && p.state.isRunning,
        );
      } on ProviderNotFoundException {
        running = false;
      }
      showFocusPill = running;
    }

    final bar = Container(
      key: const ValueKey('desktop_workspace_topbar'),
      height: DesktopWebTokens.topbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: tokens.topbarBackground,
        border: Border(
          bottom: BorderSide(
            color: tokens.hairlineBorder,
            width: DesktopWebTokens.hairlineWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(dest.selectedIcon, size: 18, color: tokens.accent),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasBreadcrumb =
                    spec.breadcrumb != null && spec.breadcrumb!.isNotEmpty;
                final hasSubtitle =
                    spec.subtitle != null && spec.subtitle!.isNotEmpty;
                final breadcrumbStyle = tokens.captionStyle.copyWith(
                  color: tokens.textMuted,
                  fontSize: 12.5,
                );
                final slashStyle = tokens.captionStyle.copyWith(
                  color: tokens.textMuted.withValues(alpha: 0.6),
                  fontSize: 12.5,
                );
                final titleStyle = tokens.pageTitleStyle.copyWith(
                  fontSize: 15.5,
                );
                final subtitleStyle = tokens.captionStyle.copyWith(
                  color: tokens.textSecondary,
                  fontSize: 11.5,
                );
                final maxW = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 1200.0;
                final slashWidth = hasBreadcrumb
                    ? _measureTextWidth(context, '/', slashStyle) + 12.0
                    : 0.0;
                final breadcrumbNatural = hasBreadcrumb
                    ? _measureTextWidth(
                            context,
                            spec.breadcrumb!,
                            breadcrumbStyle,
                          ) +
                          slashWidth +
                          2.0
                    : 0.0;
                final titleNatural =
                    _measureTextWidth(context, spec.title, titleStyle) + 2.0;
                // 10px gap + 16px horizontal padding + 1.2px border + 2px cushion.
                final subtitleNatural = hasSubtitle
                    ? _measureTextWidth(
                            context,
                            spec.subtitle!,
                            subtitleStyle,
                          ) +
                          29.2
                    : 0.0;

                // Prefer fitting all three; when tight with a subtitle, let the
                // breadcrumb yield before truncating the page title or subtitle.
                final bool allFitWithSubtitle =
                    breadcrumbNatural + titleNatural + subtitleNatural <= maxW;
                final bool prioritizeTitleAndSubtitle =
                    hasSubtitle &&
                    !allFitWithSubtitle &&
                    hasBreadcrumb &&
                    (slashWidth + titleNatural + subtitleNatural + 64.0 <=
                        maxW);

                final bool flexBreadcrumb;
                final bool flexTitle;
                final bool flexSubtitle;
                if (hasSubtitle) {
                  if (allFitWithSubtitle) {
                    flexBreadcrumb = false;
                    flexTitle = false;
                    flexSubtitle = true;
                  } else if (prioritizeTitleAndSubtitle) {
                    flexBreadcrumb = true;
                    flexTitle = false;
                    flexSubtitle = false;
                  } else {
                    flexBreadcrumb = true;
                    flexTitle = true;
                    flexSubtitle = true;
                  }
                } else {
                  final keepBreadcrumb =
                      !hasBreadcrumb ||
                      (breadcrumbNatural + titleNatural <= maxW) ||
                      (breadcrumbNatural <= maxW * 0.55);
                  flexBreadcrumb = !keepBreadcrumb;
                  flexTitle = true;
                  flexSubtitle = false;
                }

                Widget buildText(
                  String text,
                  TextStyle style, {
                  required bool flexible,
                  required int flex,
                }) {
                  final textWidget = Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  );
                  return flexible
                      ? Flexible(flex: flex, child: textWidget)
                      : textWidget;
                }

                final breadcrumbWidgets = hasBreadcrumb
                    ? <Widget>[
                        buildText(
                          spec.breadcrumb!,
                          breadcrumbStyle,
                          flexible: flexBreadcrumb,
                          flex: hasSubtitle ? 1 : 2,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text('/', style: slashStyle),
                        ),
                      ]
                    : const <Widget>[];

                final titleWidget = buildText(
                  spec.title,
                  titleStyle,
                  flexible: flexTitle,
                  flex: hasSubtitle ? 2 : 3,
                );

                final subtitlePill = hasSubtitle
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.mutedSurface,
                          borderRadius: BorderRadius.circular(
                            DesktopWebTokens.radiusPill,
                          ),
                          border: Border.all(
                            color: tokens.hairlineBorder,
                            width: DesktopWebTokens.hairlineWidth,
                          ),
                        ),
                        child: Text(
                          spec.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      )
                    : null;

                return Row(
                  children: [
                    ...breadcrumbWidgets,
                    titleWidget,
                    if (subtitlePill != null) ...[
                      const SizedBox(width: 10),
                      if (flexSubtitle)
                        Flexible(
                          flex: allFitWithSubtitle ? 1 : 3,
                          child: subtitlePill,
                        )
                      else
                        subtitlePill,
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          if (showFocusPill)
            _RunningFocusTopbarPill(
              isEn: isEn,
              onTap: () => controller.navigateTo(DesktopWebDestination.focus),
            ),
          for (final action in spec.actions) ...[
            action,
            const SizedBox(width: 8),
          ],
          if (spec.showQuickSearch)
            _TopbarToolButton(
              key: const ValueKey('desktop_topbar_search_button'),
              icon: Icons.search_rounded,
              label: isEn ? 'Command' : '命令',
              keycap: '⌘K',
              onTap: () => controller.openCommandPalette(
                initialMode: DesktopCommandMode.search,
              ),
            ),
          if (spec.showQuickCreate) ...[
            const SizedBox(width: 8),
            _TopbarPrimaryActionButton(
              key: const ValueKey('desktop_topbar_quick_add'),
              label: _primaryActionLabel(dest, isEn),
              onTap: () => controller.triggerQuickCreate(_quickKindFor(dest)),
            ),
          ],
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
            child: bar,
          ),
        ),
      );
    }
    return RepaintBoundary(child: bar);
  }

  DesktopTopBarSpec _defaultSpecFor(
    BuildContext context,
    DesktopWebDestination dest,
    AppLocale locale,
  ) {
    final now = DateTime.now();
    final subtitle = dest == DesktopWebDestination.today
        ? I18nDateFormat.monthDayWithWeekday(now)
        : null;
    return DesktopTopBarSpec(
      title: dest.localizedLabel(locale),
      breadcrumb: dest.sectionLabel(locale),
      subtitle: subtitle,
      showQuickSearch: true,
      showQuickCreate: dest != DesktopWebDestination.themes &&
          dest != DesktopWebDestination.settings &&
          dest != DesktopWebDestination.moreApps,
    );
  }

  DesktopQuickCreateKind _quickKindFor(DesktopWebDestination dest) =>
      switch (dest) {
        DesktopWebDestination.habit => DesktopQuickCreateKind.habit,
        DesktopWebDestination.calendar => DesktopQuickCreateKind.calendarEvent,
        DesktopWebDestination.focus => DesktopQuickCreateKind.focus,
        DesktopWebDestination.goals => DesktopQuickCreateKind.goal,
        DesktopWebDestination.notes => DesktopQuickCreateKind.note,
        DesktopWebDestination.diary => DesktopQuickCreateKind.diary,
        _ => DesktopQuickCreateKind.todo,
      };

  double _measureTextWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final resolvedStyle = DefaultTextStyle.of(context).style.merge(style);
    final painter = TextPainter(
      text: TextSpan(text: text, style: resolvedStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  String _primaryActionLabel(DesktopWebDestination dest, bool isEn) =>
      switch (dest) {
        DesktopWebDestination.habit => isEn ? 'New Habit' : '新建习惯',
        DesktopWebDestination.calendar => isEn ? 'New Event' : '新建日程',
        DesktopWebDestination.focus => isEn ? 'Start Focus' : '开始专注',
        DesktopWebDestination.goals => isEn ? 'New Goal' : '新建目标',
        DesktopWebDestination.notes => isEn ? 'New Note' : '记一笔',
        DesktopWebDestination.diary => isEn ? 'Write Diary' : '写日记',
        _ => isEn ? 'New Task' : '新建待办',
      };
}

class _RunningFocusTopbarPill extends StatelessWidget {
  final bool isEn;
  final VoidCallback onTap;

  const _RunningFocusTopbarPill({
    required this.isEn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final pomodoroProvider = context.read<PomodoroProvider?>();
    if (pomodoroProvider == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: pomodoroProvider.timerTicks,
      builder: (context, _, _) {
        final state = pomodoroProvider.state;
        if (!state.isRunning) return const SizedBox.shrink();
        final mins = (state.remainingSeconds ~/ 60).toString().padLeft(2, '0');
        final secs = (state.remainingSeconds % 60).toString().padLeft(2, '0');
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(
                    DesktopWebTokens.radiusPill,
                  ),
                  border: Border.all(
                    color: tokens.accentBorder,
                    width: DesktopWebTokens.hairlineWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 14, color: tokens.accent),
                    const SizedBox(width: 5),
                    Text(
                      '${isEn ? 'Focusing' : '专注中'} $mins:$secs',
                      style: tokens.captionStyle.copyWith(
                        color: tokens.accent,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopbarToolButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? keycap;
  final VoidCallback onTap;

  const _TopbarToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.keycap,
    required this.onTap,
  });

  @override
  State<_TopbarToolButton> createState() => _TopbarToolButtonState();
}

class _TopbarToolButtonState extends State<_TopbarToolButton> {
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
          height: 32,
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: tokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: tokens.bodyMutedStyle.copyWith(
                  color: tokens.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              if (widget.keycap != null) ...[
                const SizedBox(width: 6),
                DesktopKeycap(label: widget.keycap!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopbarPrimaryActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _TopbarPrimaryActionButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<_TopbarPrimaryActionButton> createState() =>
      _TopbarPrimaryActionButtonState();
}

class _TopbarPrimaryActionButtonState
    extends State<_TopbarPrimaryActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWebTokens.of(context);
    final bg = _hovered
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.08), tokens.accent)
        : tokens.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DesktopWebTokens.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 15, color: tokens.accentForeground),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: tokens.bodyStyle.copyWith(
                  color: tokens.accentForeground,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
