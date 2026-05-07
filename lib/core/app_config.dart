/// 应用硬编码配置。
///
/// 服务器地址采用 **"内置默认 + 构建期覆盖 + 管理员应用内覆盖"** 三层策略：
/// 1. 内置默认值 [defaultServerUrl]；
/// 2. 构建时可通过 `--dart-define=DUOYI_SERVER_URL=https://xxx` 覆盖；
/// 3. 已登录的管理员可在"管理员后台 → 服务器地址"里再次覆盖，写入本地 SharedPreferences。
///
/// 普通用户看不到也无法修改服务器地址。
class AppConfig {
  /// 生产环境默认服务器地址。发布前按需改动。
  static const String defaultServerUrl = 'https://duoyi.example.com';

  /// 构建期注入的服务器地址，例如：
  ///   flutter build apk --dart-define=DUOYI_SERVER_URL=https://duoyi.mycompany.com
  static const String buildTimeServerUrl = String.fromEnvironment(
    'DUOYI_SERVER_URL',
    defaultValue: '',
  );

  /// 优先级：build-time > 硬编码默认
  static String get bakedServerUrl =>
      buildTimeServerUrl.isNotEmpty ? buildTimeServerUrl : defaultServerUrl;
}
