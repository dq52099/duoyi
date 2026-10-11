import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../services/account_local_data_cleaner.dart';
import 'surface_components.dart';

/// Single option entry for [SettingsPickerTile].
class SettingsPickerOption<T> {
  final T value;
  final String title;
  final String? subtitle;

  const SettingsPickerOption({
    required this.value,
    required this.title,
    this.subtitle,
  });
}

/// Shared iOS-style settings picker tile with bottom modal selection.
///
/// Features:
/// - Re-evaluates copy functions in [ValueListenableBuilder] so already-open
///   picker sheets update dynamically when [I18n.localeListenable] changes.
/// - Guarantees `context.mounted` check before invoking [onSelected].
/// - Normal font weights throughout (selection conveyed via tint and checkmark).
/// - Stacks current value below the label on narrow screens (<300px) or enlarged
///   text scales (>=1.25x), allowing full value text to wrap without clipping.
/// - Uses [AppSurfaceStyle.smallTileRadius] with [DesignTokens] fallback for control radii.
/// - Minimum action height of 44pt on all interactive elements.
class SettingsPickerTile<T> extends StatelessWidget {
  final IconData icon;
  final Color color;
  final ValueGetter<String> titleBuilder;
  final ValueGetter<String?>? subtitleBuilder;
  final ValueGetter<String> pickerTitleBuilder;
  final T currentValue;
  final ValueGetter<String> displayLabelBuilder;
  final ValueGetter<List<SettingsPickerOption<T>>> optionsBuilder;
  final FutureOr<void> Function(T) onSelected;
  final EdgeInsetsGeometry padding;

  const SettingsPickerTile({
    super.key,
    required this.icon,
    required this.color,
    required this.titleBuilder,
    this.subtitleBuilder,
    required this.pickerTitleBuilder,
    required this.currentValue,
    required this.displayLabelBuilder,
    required this.optionsBuilder,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
  });

  Future<void> _showPicker(BuildContext context) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final picked = await showAppModalSheet<T>(
      context: context,
      builder: (sheetContext) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) {
          final surfaceStyle = appSurfaceStyleOf(ctx);
          final controlRadius =
              surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
          final controlBorderRadius = BorderRadius.circular(controlRadius);
          final cs = Theme.of(ctx).colorScheme;

          final pickerTitle = pickerTitleBuilder();
          final pickerSubtitle = subtitleBuilder?.call();
          final options = optionsBuilder();

          return AppModalSheet(
            title: pickerTitle,
            subtitle: pickerSubtitle,
            showDragHandle: true,
            scrollable: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final opt in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: opt.value == currentValue
                          ? cs.primary.withValues(alpha: 0.08)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.22),
                      shape: RoundedRectangleBorder(
                        borderRadius: controlBorderRadius,
                        side: BorderSide(
                          color: opt.value == currentValue
                              ? cs.primary.withValues(alpha: 0.22)
                              : cs.outlineVariant.withValues(alpha: 0.12),
                          width: 0.45,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.of(ctx).pop(opt.value),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        opt.title,
                                        softWrap: true,
                                        style: appSecondaryControlTextStyle(ctx)
                                            .copyWith(
                                              color: cs.onSurface,
                                              fontWeight: FontWeight.normal,
                                            ),
                                      ),
                                      if (opt.subtitle != null &&
                                          opt.subtitle!.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          opt.subtitle!,
                                          softWrap: true,
                                          style:
                                              appSecondaryControlLabelStyle(
                                                ctx,
                                              ).copyWith(
                                                color: cs.onSurface.withValues(
                                                  alpha: 0.62,
                                                ),
                                                fontWeight: FontWeight.normal,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (opt.value == currentValue) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.check_rounded,
                                    color: cs.primary,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );

    if (!context.mounted) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    if (picked != null) {
      final result = onSelected(picked);
      if (result is Future) {
        await result;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final surfaceStyle = appSurfaceStyleOf(context);
        final controlRadius =
            surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
        final controlBorderRadius = BorderRadius.circular(controlRadius);

        final title = titleBuilder();
        final subtitle = subtitleBuilder?.call();
        final displayLabel = displayLabelBuilder();

        return LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            final textScale = media.textScaler.scale(1.0);
            final shouldStack = constraints.maxWidth < 300 || textScale >= 1.25;

            final iconWidget = Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: controlBorderRadius,
              ),
              child: Icon(icon, color: color, size: 18),
            );

            final textColumn = Column(
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
                if (subtitle != null && subtitle.isNotEmpty) ...[
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
              ],
            );

            final valueContainer = Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.42)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.52),
                borderRadius: controlBorderRadius,
                border: Border.all(
                  color: cs.outlineVariant.withValues(
                    alpha: isDark ? 0.10 : 0.12,
                  ),
                  width: 0.45,
                ),
              ),
              child: Row(
                mainAxisSize: shouldStack ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: shouldStack
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      displayLabel,
                      softWrap: true,
                      style: appSecondaryControlTextStyle(context).copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            );

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showPicker(context),
                borderRadius: controlBorderRadius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: padding,
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
                                child: valueContainer,
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
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (constraints.maxWidth * 0.48).clamp(
                                    100.0,
                                    180.0,
                                  ),
                                ),
                                child: valueContainer,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
