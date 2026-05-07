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
  final isDark = brightness == Brightness.dark;
  return TextTheme(
    headlineSmall: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: isDark ? 26 : 25,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: headingColor,
    ),
    titleLarge: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: 22,
      height: 1.24,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: headingColor,
    ),
    titleMedium: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: 18,
      height: 1.28,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: headingColor,
    ),
    bodyLarge: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: 16,
      height: 1.56,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: bodyColor,
    ),
    bodyMedium: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: 14,
      height: 1.58,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: bodyColor,
    ),
    bodySmall: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: mutedColor,
    ),
    labelLarge: TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: 14,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
      color: bodyColor,
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
  return ThemeData(
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
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E2532),
      ),
    ),
  );
}

ThemeData _darkTheme({
  required Color primary,
  required Color secondary,
  required Color surface,
  required Color background,
  Color error = const Color(0xFFFF6B6B),
}) {
  return ThemeData(
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
}

final _re0Theme = ThemeData(
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

final _botwTheme = ThemeData(
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
    name: '指尖时光',
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
