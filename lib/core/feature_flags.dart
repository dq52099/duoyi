/// 特性开关（Task 23.1 / Requirements 12.6）。
///
/// 集中管理"分阶段上线"的布尔开关。默认都关闭，给生产环境留回滚余地；
/// CI / QA / dogfood 构建可以在启动前通过 `FeatureFlags.override(...)` 翻开。
///
/// 后续如需按用户/租户/Remote Config 动态控制，可以在此基础上加
/// `SharedPreferences` 持久化或 `RemoteConfig` 拉取，对外 API 保持不变。
library;

class FeatureFlags {
  FeatureFlags._();

  // -----------------------
  // 静态默认值
  // -----------------------

  /// 后端 CloudSync v2 契约：Goal/Todo 字段对齐、排队重试。
  /// 默认 false——客户端完全离线可用；翻开后才启用 API 同步。
  static const bool _kCloudSyncV2Default = false;

  // -----------------------
  // 可覆盖层
  // -----------------------

  static bool? _cloudSyncV2Override;

  /// 当前是否开启 cloud_sync_v2。
  static bool get cloudSyncV2 =>
      _cloudSyncV2Override ?? _kCloudSyncV2Default;

  /// 运行时覆盖（给 QA / 集成测试用）；传 null 恢复到默认值。
  static void overrideCloudSyncV2(bool? value) {
    _cloudSyncV2Override = value;
  }

  /// 清空所有覆盖层（主要给单元测试用）。
  static void resetAllOverrides() {
    _cloudSyncV2Override = null;
  }
}
