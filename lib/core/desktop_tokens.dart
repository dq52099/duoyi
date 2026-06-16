/// 桌面端设计系统 - 专属大屏体验的设计参数
///
/// 提供桌面端专用的字体、间距、断点等设计常量。
/// 与 [DesignTokens] 互补，专注于桌面端优化。
class DesktopTokens {
  DesktopTokens._();

  // ========== 断点 ==========

  /// 三栏布局最小宽度（左侧边栏 + 主内容 + 右侧边栏）
  static const double breakpointThreeColumn = 1400;

  /// 两栏布局最小宽度（主内容 + 右侧边栏）
  static const double breakpointTwoColumn = 1100;

  /// 桌面端布局最小宽度
  static const double breakpointDesktop = breakpointTwoColumn;

  // ========== 布局尺寸 ==========

  /// 页面最大内容宽度
  static const double maxContentWidth = 1280;

  /// 左侧边栏宽度（日历 + 快捷入口）
  static const double leftSidebarWidth = 420;

  /// 右侧边栏宽度（目标 + 课程 + 纪念日）
  static const double rightSidebarWidth = 380;

  /// Header 高度
  static const double headerHeight = 120;

  // ========== 间距 ==========

  /// 页面外边距（水平）
  static const double pageHorizontalPadding = 40;

  /// 页面外边距（顶部）
  static const double pageTopPadding = 32;

  /// 页面外边距（底部）
  static const double pageBottomPadding = 40;

  /// 卡片间距（大）
  static const double cardSpacing = 20;

  /// 卡片间距（中）
  static const double cardSpacingMedium = 16;

  /// 卡片间距（小）
  static const double cardSpacingSmall = 12;

  /// 卡片内边距
  static const double cardPadding = 20;

  /// 列间距（主内容与侧边栏）
  static const double columnSpacing = 28;

  /// 列间距（紧凑）
  static const double columnSpacingCompact = 20;

  // ========== 字体大小 ==========

  /// 页面主标题（如"早上好"）
  static const double fontSizePageTitle = 28;

  /// 页面副标题（如日期）
  static const double fontSizePageSubtitle = 15;

  /// 卡片大标题
  static const double fontSizeCardTitle = 20;

  /// 卡片小标题
  static const double fontSizeCardSubtitle = 16;

  /// 正文
  static const double fontSizeBody = 15;

  /// 辅助文字
  static const double fontSizeCaption = 13;

  /// 小号辅助文字
  static const double fontSizeCaptionSmall = 12;

  // ========== 字重 ==========

  /// 页面标题字重
  static const double fontWeightPageTitle = 600; // semibold

  /// 卡片标题字重
  static const double fontWeightCardTitle = 500; // medium

  /// 正文字重
  static const double fontWeightBody = 400; // regular

  // ========== 不透明度 ==========

  /// 主要文字不透明度
  static const double opacityTextPrimary = 0.95;

  /// 次要文字不透明度
  static const double opacityTextSecondary = 0.87;

  /// 辅助文字不透明度
  static const double opacityTextTertiary = 0.70;

  /// 卡片背景不透明度
  static const double opacityCardBackground = 0.92;

  /// 边框不透明度
  static const double opacityBorder = 0.45;

  // ========== 卡片样式 ==========

  /// 卡片圆角
  static const double cardRadius = 12;

  /// 卡片边框宽度
  static const double cardBorderWidth = 0.6;

  /// 卡片阴影高度
  static const double cardElevation = 0.5;

  // ========== 列表项 ==========

  /// 待办列表项高度
  static const double todoItemHeight = 56;

  /// 列表项内边距（垂直）
  static const double listItemPaddingVertical = 12;

  /// 列表项内边距（水平）
  static const double listItemPaddingHorizontal = 16;

  // ========== 图标 ==========

  /// 大图标尺寸
  static const double iconSizeLarge = 28;

  /// 中等图标尺寸
  static const double iconSizeMedium = 24;

  /// 小图标尺寸
  static const double iconSizeSmall = 20;

  // ========== 快捷判断 ==========

  /// 判断当前宽度是否支持三栏布局
  static bool isThreeColumnLayout(double width) => width >= breakpointThreeColumn;

  /// 判断当前宽度是否支持两栏布局
  static bool isTwoColumnLayout(double width) =>
      width >= breakpointTwoColumn && width < breakpointThreeColumn;

  /// 判断当前宽度是否为桌面端
  static bool isDesktopLayout(double width) => width >= breakpointDesktop;
}
