import 'package:flutter/material.dart';

/// 全局设计 Token。
///
/// 所有新写 UI 应从这里取颜色 / 圆角 / 间距 / 字阶 / 阴影。
/// 业务色（主题色 / AppBar 色等）仍然走 `Theme.of(ctx).colorScheme`；
/// 这里只定义"跨主题通用"的语义色与度量。
///
/// 对应 `Requirement 10.1`。
class DesignTokens {
  DesignTokens._();

  // ----- Spacing（4 的倍数，保持节奏一致） -----
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;
  static const double space3xl = 32;
  static const double space4xl = 40;
  static const double space5xl = 48;

  // ----- Default palette -----
  static const Color defaultPageBackground = Color(0xFFF6F7F9);
  static const Color defaultSurface = Color(0xFFFFFFFF);
  static const Color defaultSurfaceMuted = Color(0xFFF1F3F6);
  static const Color defaultText = Color(0xFF1F2933);
  static const Color defaultTextMuted = Color(0xFF667085);
  static const Color defaultBorder = Color(0xFFD9E0E8);
  static const Color defaultPrimary = Color(0xFFC85656);
  static const Color defaultPrimarySoft = Color(0xFFF7E3E3);
  static const Color defaultPrimaryPressed = Color(0xFFA94444);
  static const Color defaultAccent = Color(0xFF2F8F83);
  static const Color defaultInfo = Color(0xFF2F6FAE);
  static const Color defaultSuccess = Color(0xFF2E7D62);
  static const Color defaultWarning = Color(0xFFB7791F);
  static const Color defaultError = Color(0xFFC64747);

  // ----- Radius -----
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusControl = 10;
  static const double radiusMd = 10;
  static const double radiusCard = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 28;
  static const double radiusPill = 999;

  // Convenience shapes
  static const BorderRadius borderRadiusSm = BorderRadius.all(
    Radius.circular(radiusSm),
  );
  static const BorderRadius borderRadiusMd = BorderRadius.all(
    Radius.circular(radiusMd),
  );
  static const BorderRadius borderRadiusLg = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius borderRadiusXl = BorderRadius.all(
    Radius.circular(radiusXl),
  );

  // ----- Typography scale（与 ThemeData TextTheme 协同，提供字号常量） -----
  static const double fontSizeXs = 11;
  static const double fontSizeSm = 12;
  static const double fontSizeBase = 14;
  static const double fontSizeSection = 15;
  static const double fontSizeMd = 16;
  static const double fontSizeLg = 18;
  static const double fontSizeXl = 22;
  static const double fontSizeXxl = 28;

  static const FontWeight fontWeightRegular = FontWeight.normal;
  static const FontWeight fontWeightMedium = FontWeight.normal;

  // ----- Elevation / Shadow -----
  static const List<BoxShadow> shadowXs = [
    BoxShadow(
      color: Color(0x0F000000), // #000 6%
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x14000000), // #000 8%
      blurRadius: 7,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x1A000000), // #000 10%
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x24000000), // #000 14%
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  // ----- Durations -----
  static const Duration durationInstant = Duration(milliseconds: 80);
  static const Duration durationFast = Duration(milliseconds: 160);
  static const Duration durationBase = Duration(milliseconds: 240);
  static const Duration durationSlow = Duration(milliseconds: 320);
  static const Duration durationFade = Duration(milliseconds: 300);

  // ----- 语义色：完成态 / 过期 / 临期 / 归档 / 一般状态 -----
  //
  // 这些是跨主题通用的"语义颜色"。具体视觉状态（已完成、临期、过期、归档、普通）
  // 由 `CompletionVisibilityPolicy.visualState(...)` 决定，颜色映射用这里的 token。
  static const Color todoNormal = Color(0xDE000000); // black87 ~ onSurface
  static const Color todoDueSoon = Color(0xFFFFB74D); // orange.shade400
  static const Color todoOverdue = Color(0xFFEF5350); // red.shade400
  static const Color todoCompleted = Color(0xFF66BB6A); // green.shade400
  static const Color todoArchived = Color(0xFFBDBDBD); // grey.shade400

  /// 完成态文本的"灰度 70%"：与 `todoCompleted` 配套使用。
  static const double completedTextOpacity = 0.7;

  // ----- 结果态 -----
  static const Color resultEmpty = Color(0xFF9E9E9E); // grey.shade500
  static const Color resultError = Color(0xFFEF5350); // red.shade400
  static const Color resultLoadingShimmerBase = Color(0xFFEEEEEE);
  static const Color resultLoadingShimmerHighlight = Color(0xFFFAFAFA);

  // ----- 优先级色标（对齐 TodoItem.priority） -----
  static const Color priorityHigh = Color(0xFFE53935); // red 600
  static const Color priorityMedium = Color(0xFFFB8C00); // orange 600
  static const Color priorityLow = Color(0xFF43A047); // green 600
  static const Color priorityNone = Color(0xFFB0BEC5); // blueGrey 200

  // ----- Dialog / 二次确认 统一样式 token -----
  static const EdgeInsets dialogContentPadding = EdgeInsets.fromLTRB(
    spaceXxl,
    spaceLg,
    spaceXxl,
    spaceSm,
  );
  static const EdgeInsets dialogActionsPadding = EdgeInsets.fromLTRB(
    spaceMd,
    0,
    spaceMd,
    spaceSm,
  );
  static const BorderRadius dialogBorderRadius = borderRadiusLg;
}
