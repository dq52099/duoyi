import 'package:flutter/foundation.dart';

class WebTarget {
  static const String raw = String.fromEnvironment(
    'DUOYI_WEB_TARGET',
    defaultValue: 'responsive',
  );

  /// 仅测试用：非 null 时强制 [isDesktopWebBuild] 返回该值。
  ///
  /// flutter test 跑在 VM 上，kIsWeb 恒为 false，桌面 web 外壳分支
  /// （NavigationRail 壳）无法用真实编译期条件触达，宽屏壳测试靠此注入。
  static bool? debugDesktopWebBuild;

  static bool get isDesktopWebBuild =>
      debugDesktopWebBuild ?? (kIsWeb && raw == 'desktop');
  static bool get isMobileWebBuild => kIsWeb && raw == 'mobile';

  /// Web 渲染器下 BackdropFilter 逐帧回读像素，开销显著高于原生：
  /// 底部导航毛玻璃在 web 端降档（mobile shell 是全应用唯一模糊挂点）。
  static bool get shouldReduceNavBarBlur => kIsWeb;
}
