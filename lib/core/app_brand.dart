import 'package:flutter/material.dart';
import 'brand_strings.dart';

const String _cnFontFamily = 'sans-serif';
const List<String> _cnFontFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'Microsoft YaHei',
  'WenQuanYi Micro Hei',
];

enum BrandStyle {
  defaultBrand,
  re0,
  genshin,
  starRail,
  wuthering,
  zzz,
  yanyun,
  botw,
}

class AppBrand {
  final BrandStyle style;
  final String name;
  final ThemeData theme;
  final String? backgroundAsset;
  final Color backgroundOverlay;
  final double backgroundOverlayOpacity;

  const AppBrand({
    required this.style,
    required this.name,
    required this.theme,
    this.backgroundAsset,
    this.backgroundOverlay = const Color(0xFFFFFFFF),
    this.backgroundOverlayOpacity = 0.7,
  });

  String get id => style.name;
  BrandStrings get strings => BrandStrings.forStyle(style);
}

TextTheme _textTheme({
  required Brightness brightness,
  required Color bodyColor,
  required Color mutedColor,
  required Color headingColor,
}) {
  TextStyle style(double size, Color color, {double height = 1.3}) {
    return TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: size,
      height: height,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: color,
    );
  }

  return TextTheme(
    displayLarge: style(57, headingColor, height: 1.12),
    displayMedium: style(45, headingColor, height: 1.16),
    displaySmall: style(36, headingColor, height: 1.2),
    headlineLarge: style(32, headingColor, height: 1.22),
    headlineMedium: style(28, headingColor, height: 1.24),
    headlineSmall: style(25, headingColor, height: 1.28),
    titleLarge: style(22, headingColor, height: 1.24),
    titleMedium: style(18, headingColor, height: 1.28),
    titleSmall: style(14, headingColor, height: 1.3),
    bodyLarge: style(16, bodyColor, height: 1.56),
    bodyMedium: style(14, bodyColor, height: 1.58),
    bodySmall: style(12, mutedColor, height: 1.5),
    labelLarge: style(14, bodyColor, height: 1.2),
    labelMedium: style(12, bodyColor, height: 1.2),
    labelSmall: style(11, bodyColor, height: 1.2),
  );
}

ThemeData _withSharedControls(ThemeData theme) {
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final surface = cs.surface;
  final surfaceTint = Colors.transparent;
  final outline = cs.outlineVariant.withValues(alpha: isDark ? 0.54 : 0.72);
  final fill = isDark
      ? cs.surfaceContainerHighest.withValues(alpha: 0.38)
      : cs.surfaceContainerHighest.withValues(alpha: 0.55);
  final sheetShape = const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  );
  final dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
  );

  final body = theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface);
  final bodyMuted = theme.textTheme.bodySmall?.copyWith(
    color: cs.onSurface.withValues(alpha: 0.68),
  );
  final label = theme.textTheme.labelLarge?.copyWith(
    fontWeight: FontWeight.w400,
  );
  OutlineInputBorder fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  final inputTheme = InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: fieldBorder(outline),
    enabledBorder: fieldBorder(outline),
    focusedBorder: fieldBorder(cs.primary, width: 1.6),
    errorBorder: fieldBorder(cs.error.withValues(alpha: 0.9)),
    focusedErrorBorder: fieldBorder(cs.error, width: 1.6),
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.46),
    ),
    labelStyle: theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.72),
    ),
    floatingLabelStyle: theme.textTheme.bodySmall?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w400,
    ),
    prefixIconColor: WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    suffixIconColor: WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    errorStyle: theme.textTheme.bodySmall?.copyWith(color: cs.error),
  );

  return theme.copyWith(
    materialTapTargetSize: MaterialTapTargetSize.padded,
    inputDecorationTheme: inputTheme,
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: surfaceTint,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.34 : 0.14),
      shape: dialogShape,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.56 : 0.36),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: theme.textTheme.titleLarge?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
      contentTextStyle: body,
      iconColor: cs.primary,
      clipBehavior: Clip.antiAlias,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: surfaceTint,
      modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.48 : 0.32),
      elevation: 0,
      modalElevation: 10,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
      shape: sheetShape,
      showDragHandle: true,
      dragHandleColor: cs.outlineVariant,
      dragHandleSize: const Size(40, 4),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 720),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.surfaceContainerHighest,
      actionTextColor: cs.primary,
      contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
      surfaceTintColor: surfaceTint,
      textStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      iconColor: cs.onSurfaceVariant,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      inputDecorationTheme: inputTheme,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      disabledColor: cs.onSurface.withValues(alpha: 0.38),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: outline),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: label,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.primary.withValues(alpha: 0.14);
          }
          return fill;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return cs.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.onSurfaceVariant;
        }),
        side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: cs.primary.withValues(alpha: 0.54));
          }
          return BorderSide(color: outline);
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        textStyle: WidgetStatePropertyAll(label),
        iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.onSurfaceVariant;
        }),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        padding: const EdgeInsets.all(10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: fill,
      selectedColor: cs.primary.withValues(alpha: 0.12),
      secondarySelectedColor: cs.secondary.withValues(alpha: 0.12),
      disabledColor: cs.onSurface.withValues(alpha: 0.08),
      deleteIconColor: cs.onSurface.withValues(alpha: 0.72),
      checkmarkColor: cs.primary,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
      secondaryLabelStyle: theme.textTheme.labelMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
      iconTheme: IconThemeData(size: 18, color: cs.onSurfaceVariant),
      surfaceTintColor: surfaceTint,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
      elevation: 0,
      pressElevation: 0,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.38);
        }
        if (states.contains(WidgetState.selected)) {
          return cs.onPrimary;
        }
        return cs.surfaceContainerHighest;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return cs.primary;
        }
        return cs.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return outline;
      }),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(1.0),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.transparent;
        }
        return cs.primary.withValues(alpha: 0.12);
      }),
      splashRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return cs.primary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll<Color>(cs.onPrimary),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.transparent;
        }
        return cs.primary.withValues(alpha: 0.12);
      }),
      splashRadius: 20,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: outline),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        return cs.primary;
      }),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.transparent;
        }
        return cs.primary.withValues(alpha: 0.12);
      }),
      backgroundColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      side: BorderSide(color: outline),
      splashRadius: 20,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.onSurface.withValues(alpha: 0.14),
      thumbColor: cs.primary,
      overlayColor: cs.primary.withValues(alpha: 0.12),
      valueIndicatorColor: cs.primary,
      valueIndicatorTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: cs.onPrimary,
        fontWeight: FontWeight.w400,
      ),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.primary.withValues(alpha: 0.16),
      circularTrackColor: cs.primary.withValues(alpha: 0.16),
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withValues(alpha: isDark ? 0.52 : 0.64),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      iconColor: cs.primary,
      textColor: cs.onSurface,
      tileColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      labelColor: cs.primary,
      unselectedLabelColor: cs.onSurfaceVariant,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w400,
      ),
      unselectedLabelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w400,
      ),
      overlayColor: WidgetStatePropertyAll(cs.primary.withValues(alpha: 0.08)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      elevation: 0,
      backgroundColor: surface.withValues(alpha: isDark ? 0.92 : 0.96),
      indicatorColor: cs.primary.withValues(alpha: 0.14),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return theme.textTheme.labelSmall?.copyWith(
          color: selected ? cs.primary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? cs.primary : cs.onSurfaceVariant,
          size: 24,
        );
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: label,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: surface,
      surfaceTintColor: surfaceTint,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
      shape: dialogShape,
      headerBackgroundColor: cs.primary,
      headerForegroundColor: cs.onPrimary,
      headerHeadlineStyle: theme.textTheme.headlineSmall?.copyWith(
        color: cs.onPrimary,
        fontWeight: FontWeight.w400,
      ),
      headerHelpStyle: bodyMuted?.copyWith(
        color: cs.onPrimary.withValues(alpha: 0.84),
      ),
      weekdayStyle: theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w400,
      ),
      dayStyle: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface),
      dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.24);
        }
        if (states.contains(WidgetState.selected)) {
          return cs.onPrimary;
        }
        return cs.onSurface;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return cs.primary;
        }
        return Colors.transparent;
      }),
      dayOverlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return cs.primary.withValues(alpha: 0.15);
        }
        return cs.primary.withValues(alpha: 0.08);
      }),
      dayShape: const WidgetStatePropertyAll<OutlinedBorder?>(CircleBorder()),
      todayForegroundColor: WidgetStatePropertyAll<Color?>(cs.primary),
      todayBackgroundColor: WidgetStatePropertyAll<Color?>(
        cs.primary.withValues(alpha: 0.12),
      ),
      todayBorder: BorderSide(color: cs.primary, width: 1.4),
      yearStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      yearForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return cs.onPrimary;
        }
        return cs.onSurface;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return cs.primary;
        }
        return Colors.transparent;
      }),
      yearOverlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return cs.primary.withValues(alpha: 0.08);
      }),
      yearShape: const WidgetStatePropertyAll<OutlinedBorder?>(CircleBorder()),
      rangePickerBackgroundColor: surface,
      rangePickerSurfaceTintColor: surfaceTint,
      rangePickerShape: dialogShape,
      dividerColor: cs.outlineVariant.withValues(alpha: 0.52),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        textStyle: label,
      ),
      confirmButtonStyle: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: label,
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: surface,
      shape: dialogShape,
      elevation: 0,
      dayPeriodBorderSide: BorderSide(color: outline),
      dayPeriodColor: cs.primary.withValues(alpha: 0.14),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      dayPeriodTextColor: cs.onSurface,
      dialBackgroundColor: cs.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.36 : 0.56,
      ),
      dialHandColor: cs.primary,
      dialTextColor: cs.onSurface,
      hourMinuteColor: cs.primary.withValues(alpha: 0.12),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      hourMinuteTextColor: cs.onSurface,
      helpTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w400,
      ),
      confirmButtonStyle: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: label,
      ),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        textStyle: label,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll<double>(isDark ? 6 : 5),
      radius: const Radius.circular(999),
      thumbVisibility: const WidgetStatePropertyAll<bool>(false),
      thumbColor: WidgetStatePropertyAll<Color?>(
        cs.onSurface.withValues(alpha: isDark ? 0.36 : 0.24),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: cs.primary,
      selectionColor: cs.primary.withValues(alpha: 0.22),
      selectionHandleColor: cs.primary,
    ),
  );
}

ThemeData _lightTheme({
  required Color primary,
  required Color secondary,
  required Color surface,
  required Color background,
  Color error = const Color(0xFFA23535),
}) {
  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.light,
      bodyColor: const Color(0xFF2C323D),
      mutedColor: const Color(0xFF8B95A6),
      headingColor: const Color(0xFF1E2532),
    ),
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: error,
    ),
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface.withValues(alpha: 0.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: const Color(0xFF1E2532),
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: Color(0xFF1E2532),
      ),
    ),
  );
  return _withSharedControls(theme);
}

ThemeData _darkTheme({
  required Color primary,
  required Color secondary,
  required Color surface,
  required Color background,
  Color error = const Color(0xFFFF6B6B),
}) {
  final theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.dark,
      bodyColor: const Color(0xFFF3F6FA),
      mutedColor: const Color(0xFF9CA8BC),
      headingColor: const Color(0xFFFFFFFF),
    ),
    colorScheme: ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: error,
    ),
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: surface.withValues(alpha: 0.9),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: primary.withValues(alpha: 0.24)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.64),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primary.withValues(alpha: 0.42)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primary, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: primary,
    ),
  );
  return _withSharedControls(theme);
}

final _re0Theme = _withSharedControls(
  ThemeData(
    useMaterial3: true,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.light,
      bodyColor: const Color(0xFF243244),
      mutedColor: const Color(0xFF6F7C8F),
      headingColor: const Color(0xFF1C2D46),
    ),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4682B4),
      secondary: Color(0xFFE6E6FA),
      surface: Color(0xFFFDFDFD),
      error: Color(0xFFA23535),
    ),
    scaffoldBackgroundColor: const Color(0xFFFDFDFD),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: 8,
      shadowColor: const Color(0xFF4682B4).withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: const Color(0xFFE6E6FA).withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.96),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: const Color(0xFF4682B4).withValues(alpha: 0.34),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF4682B4), width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4682B4),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        elevation: 4,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  ),
);

final _genshinTheme = _lightTheme(
  primary: const Color(0xFF2E8B57),
  secondary: const Color(0xFFC5892F),
  surface: const Color(0xFFFFFFFF),
  background: const Color(0xFFF8F9F0),
);

final _starRailTheme = _darkTheme(
  primary: const Color(0xFF7EA2FF),
  secondary: const Color(0xFFD0A43A),
  surface: const Color(0xFF161C30),
  background: const Color(0xFF080B16),
);

final _wutheringTheme = _lightTheme(
  primary: const Color(0xFF1B8C8F),
  secondary: const Color(0xFFE6A73A),
  surface: const Color(0xFFFFFFFF),
  background: const Color(0xFFF0F7F6),
);

final _zzzTheme = _darkTheme(
  primary: const Color(0xFFE6C229),
  secondary: const Color(0xFFFF6B35),
  surface: const Color(0xFF181818),
  background: const Color(0xFF0D0D0D),
);

final _yanyunTheme = _lightTheme(
  primary: const Color(0xFF7D4E2D),
  secondary: const Color(0xFFB86F32),
  surface: const Color(0xFFFFFCF6),
  background: const Color(0xFFF5F0E8),
);

final _botwTheme = _withSharedControls(
  ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00D2FF),
      secondary: Color(0xFFFF9600),
      surface: Color(0xFF2A2A2A),
    ),
    textTheme: _textTheme(
      brightness: Brightness.dark,
      bodyColor: Colors.white70,
      mutedColor: Colors.white54,
      headingColor: const Color(0xFF7DEBFF),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF2A2A2A).withValues(alpha: 0.8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF00D2FF), width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.58),
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF00D2FF)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF00D2FF), width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF00D2FF),
        side: const BorderSide(color: Color(0xFF00D2FF), width: 1.5),
        shape: const BeveledRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  ),
);

final _defaultTheme = _lightTheme(
  primary: const Color(0xFFFF7474),
  secondary: const Color(0xFFFFB088),
  surface: const Color(0xFFFFFFFF),
  background: const Color(0xFFF7F8FA),
);

class AppBrands {
  static final defaultBrand = AppBrand(
    style: BrandStyle.defaultBrand,
    name: '多仪',
    theme: _defaultTheme,
    backgroundOverlay: const Color(0xFFFFF8F0),
    backgroundOverlayOpacity: 1.0,
  );
  static final re0 = AppBrand(
    style: BrandStyle.re0,
    name: '从零开始',
    theme: _re0Theme,
    backgroundAsset: 'assets/backgrounds/re0.png',
    backgroundOverlay: const Color(0xFFF8FBFF),
    backgroundOverlayOpacity: 0.72,
  );
  static final genshin = AppBrand(
    style: BrandStyle.genshin,
    name: '原神',
    theme: _genshinTheme,
    backgroundAsset: 'assets/backgrounds/genshin.png',
    backgroundOverlay: const Color(0xFFFFFEF6),
    backgroundOverlayOpacity: 0.70,
  );
  static final starRail = AppBrand(
    style: BrandStyle.starRail,
    name: '星穹铁道',
    theme: _starRailTheme,
    backgroundAsset: 'assets/backgrounds/star_rail.png',
    backgroundOverlay: const Color(0xFF060A18),
    backgroundOverlayOpacity: 0.70,
  );
  static final wuthering = AppBrand(
    style: BrandStyle.wuthering,
    name: '鸣潮',
    theme: _wutheringTheme,
    backgroundAsset: 'assets/backgrounds/wuthering.png',
    backgroundOverlay: const Color(0xFFF7FCFB),
    backgroundOverlayOpacity: 0.68,
  );
  static final zzz = AppBrand(
    style: BrandStyle.zzz,
    name: '绝区零',
    theme: _zzzTheme,
    backgroundAsset: 'assets/backgrounds/zzz.png',
    backgroundOverlay: const Color(0xFF090909),
    backgroundOverlayOpacity: 0.70,
  );
  static final yanyun = AppBrand(
    style: BrandStyle.yanyun,
    name: '燕云十六声',
    theme: _yanyunTheme,
    backgroundAsset: 'assets/backgrounds/yanyun.png',
    backgroundOverlay: const Color(0xFFFFFBF4),
    backgroundOverlayOpacity: 0.72,
  );
  static final botw = AppBrand(
    style: BrandStyle.botw,
    name: '希卡之石',
    theme: _botwTheme,
    backgroundAsset: 'assets/backgrounds/botw.png',
    backgroundOverlay: const Color(0xFF061417),
    backgroundOverlayOpacity: 0.68,
  );

  static List<AppBrand> get all => [
    defaultBrand,
    re0,
    genshin,
    starRail,
    wuthering,
    zzz,
    yanyun,
    botw,
  ];

  static AppBrand byId(String? id) {
    return all.firstWhere((b) => b.id == id, orElse: () => defaultBrand);
  }
}
