/// 应用硬编码配置 —— APK/Web 编译后即固定，不再可在运行时修改。
///
/// 两层策略：
/// 1. 源码默认值 [defaultServerUrl] —— 需要发布前改动源码；
/// 2. 构建期注入，通过 `--dart-define=DUOYI_SERVER_URL=https://xxx` 覆盖。
///
/// **普通用户看不到也无法修改；管理员亦不在 APP 内改，如要换址须重新构建分发。**
///
/// 推荐用法：
/// ```bash
/// flutter build apk --release \
///   --dart-define=DUOYI_SERVER_URL=https://duoyi.mycompany.com
///
/// flutter build web --release \
///   --dart-define=DUOYI_SERVER_URL=https://duoyi.mycompany.com
///
/// # 或者与前端同域反代：留空，走相对路径，在 nginx 里把 /api 代到后端
/// flutter build web --release --dart-define=DUOYI_SERVER_URL=
/// ```
class AppConfig {
  /// 源码默认值 —— 发布前按需改动；
  /// 留空字符串表示"走相对路径"(前后端同源部署)。
  static const String defaultServerUrl = '';

  static const String buildTimeServerUrl = String.fromEnvironment(
    'DUOYI_SERVER_URL',
    defaultValue: _kSentinel,
  );

  /// 没有通过 --dart-define 时的哨兵值。
  static const String _kSentinel = '__USE_DEFAULT__';

  /// 最终使用的服务器地址。返回空串代表相对路径。
  static String get bakedServerUrl =>
      buildTimeServerUrl == _kSentinel ? defaultServerUrl : buildTimeServerUrl;
}
