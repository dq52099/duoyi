import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../providers/theme_provider.dart';

class AppSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final BorderRadius borderRadius;
  final Border? border;
  final double elevation;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.gradient,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(DesignTokens.radiusLg),
    ),
    this.border,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    ThemeProvider? themeProvider;
    try {
      themeProvider = context.watch<ThemeProvider>();
    } catch (_) {
      themeProvider = null;
    }
    final cardSkin = themeProvider?.activeCardSkin;
    final useCardSkin =
        cardSkin != null &&
        cardSkin.id != ThemeProvider.defaultCardSkinId &&
        color == null &&
        gradient == null;
    final surfaceColor =
        color ?? (isDark ? cs.surface.withValues(alpha: 0.92) : cs.surface);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final skinGradient = useCardSkin
        ? LinearGradient(
            colors: [
              cardSkin.colors.first.withValues(alpha: isDark ? 0.22 : 0.18),
              cardSkin.colors.last.withValues(alpha: isDark ? 0.18 : 0.12),
              surfaceColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;
    final decoration = BoxDecoration(
      color: gradient == null && skinGradient == null ? surfaceColor : null,
      gradient: gradient ?? skinGradient,
      borderRadius: borderRadius,
      border:
          border ??
          Border.all(
            color: useCardSkin
                ? cardSkin.colors.first.withValues(alpha: 0.28)
                : borderColor,
          ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
          blurRadius: 18 + elevation * 3,
          offset: const Offset(0, 6),
        ),
      ],
    );

    final content = Ink(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
      ),
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      titleStyle ??
                      theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface,
                      ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onAction != null && actionLabel != null)
            TextButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.chevron_right, size: 16),
              label: Text(actionLabel!),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: cs.primary,
                textStyle:
                    actionTextStyle ??
                    theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
        ],
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

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = filled ? color : color.withValues(alpha: 0.12);
    final fg = filled ? Colors.white : color;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w400,
              height: 1.1,
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
      border: Border.all(color: color.withValues(alpha: 0.18)),
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
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w400,
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
  final BorderRadius borderRadius;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final TextStyle? titleStyle;
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
    this.borderRadius = const BorderRadius.all(
      Radius.circular(DesignTokens.radiusMd),
    ),
    this.valueStyle,
    this.unitStyle,
    this.titleStyle,
    this.iconBoxSize = 28,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? cs.surface.withValues(alpha: 0.62)
        : cs.surface.withValues(alpha: 0.78);
    final tile = Ink(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.64),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.018),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        titleStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w400,
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
                              valueStyle ??
                              theme.textTheme.titleMedium?.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                                height: 1.08,
                              ),
                        ),
                        if (unit != null && unit!.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
                            style:
                                unitStyle ??
                                theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: cs.onSurface.withValues(alpha: 0.62),
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
        child: onTap == null
            ? tile
            : InkWell(onTap: onTap, borderRadius: borderRadius, child: tile),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.38),
                  ),
            ],
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

  const AppSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      margin: margin,
      padding: padding,
      border: border,
      elevation: elevation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: title,
            subtitle: subtitle,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          ...children,
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
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.38),
                  ),
            ],
          ),
        ),
      ),
    );
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
    return AppSurfaceCard(
      margin: margin,
      padding: EdgeInsets.zero,
      onTap: onTap,
      border: border,
      elevation: elevation,
      child: ListTile(
        dense: dense,
        isThreeLine: isThreeLine,
        contentPadding: contentPadding,
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    builder: builder,
  );
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
    this.shiftForKeyboard = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dialog = AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: BoxConstraints(minWidth: 320, maxWidth: maxWidth),
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
              style:
                  theme.textTheme.titleLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w400,
                  ) ??
                  TextStyle(
                    color: cs.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                  ),
              child: title,
            ),
          ),
        ],
      ),
      content: content == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: content,
            ),
      actions: actions,
    );
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final scopedDialog = MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: dialog,
    );
    if (!shiftForKeyboard) return scopedDialog;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: scopedDialog,
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
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 20),
    this.maxWidth = 720,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets;
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
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.62 : 0.78),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
      if (title != null || subtitle != null) ...[
        AppSectionHeader(
          title: title ?? '',
          subtitle: subtitle,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 14),
      ],
      child,
      if (leadingActions.isNotEmpty || actions.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            ...leadingActions,
            const Spacer(),
            ...actions
                .expand((action) => [const SizedBox(width: 8), action])
                .skip(1),
          ],
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: media.size.height * 0.88,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: cs.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppModalSheet(
      title: title,
      subtitle: subtitle,
      child: options.isEmpty
          ? (empty ??
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无可选项',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                ))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  ListTile(
                    enabled: option.enabled,
                    contentPadding: EdgeInsets.zero,
                    leading: option.icon == null
                        ? null
                        : Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: (option.color ?? cs.primary).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              option.icon,
                              color: option.color ?? cs.primary,
                              size: 20,
                            ),
                          ),
                    title: Text(
                      option.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: option.enabled
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.38),
                        fontWeight: selectedValue == option.value
                            ? FontWeight.w400
                            : FontWeight.w400,
                      ),
                    ),
                    subtitle: option.subtitle == null
                        ? null
                        : Text(
                            option.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.62),
                            ),
                          ),
                    trailing: selectedValue == option.value
                        ? Icon(Icons.check_rounded, color: cs.primary)
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
              ],
            ),
    );
  }
}

class AppCompactDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double width;

  const AppCompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 112,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.42)
        : cs.surfaceContainerHighest.withValues(alpha: 0.52);
    final borderColor = cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            borderRadius: BorderRadius.circular(16),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            dropdownColor: cs.surface,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w400,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
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
  final double? menuMaxHeight;
  final BorderRadius? borderRadius;
  final Color? dropdownColor;
  final Color? iconEnabledColor;
  final Color? iconDisabledColor;
  final AutovalidateMode? autovalidateMode;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;
  final VoidCallback? onTap;

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
    this.menuMaxHeight = 320,
    this.borderRadius,
    this.dropdownColor,
    this.iconEnabledColor,
    this.iconDisabledColor,
    this.autovalidateMode,
    this.validator,
    this.onSaved,
    this.onTap,
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
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      decoration: inputDecoration,
      items: items,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        onTap?.call();
      },
      onChanged: enabled ? onChanged : null,
      validator: validator,
      onSaved: onSaved,
      autovalidateMode: autovalidateMode,
      isExpanded: isExpanded,
      dropdownColor: dropdownColor ?? cs.surface,
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      menuMaxHeight: menuMaxHeight,
      icon:
          icon ??
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: iconEnabledColor ?? cs.onSurfaceVariant,
          ),
      iconEnabledColor: iconEnabledColor ?? cs.onSurfaceVariant,
      iconDisabledColor:
          iconDisabledColor ?? cs.onSurface.withValues(alpha: 0.38),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}
