import 'package:flutter/foundation.dart';

import 'cloud_sync_provider.dart';

/// 云同步状态的只读展示层（UI 消费专用）。
///
/// 包装 [CloudSyncProvider] 的公开只读状态并转发其通知，供我的页
/// "云同步状态卡" watch。存在意义：UI 层（lib/screens、lib/widgets）
/// 按架构守卫（test/services/cloud_sync_provider_test.dart
/// 「屏幕和组件层不暴露手动云同步入口」）不允许直接引用
/// CloudSyncProvider，也不允许出现任何手动触发同步的入口——
/// 云同步仅由 main.dart / provider 后台排队触发（含失败后自动重试）。
/// 因此本控制器**只暴露状态，不暴露任何同步触发方法**。
class SyncStatusController extends ChangeNotifier {
  CloudSyncProvider? _source;
  bool _forwarding = false;

  SyncStatusController({CloudSyncProvider? source}) {
    if (source != null) {
      attach(source);
    }
  }

  /// 绑定底层 provider 并转发其状态通知。
  void attach(CloudSyncProvider provider) {
    if (identical(_source, provider)) return;
    _source?.removeListener(_forward);
    _source = provider;
    provider.addListener(_forward);
    notifyListeners();
  }

  void detach() {
    _source?.removeListener(_forward);
    _source = null;
    notifyListeners();
  }

  void _forward() {
    if (_forwarding) return;
    _forwarding = true;
    try {
      notifyListeners();
    } finally {
      _forwarding = false;
    }
  }

  /// 上次成功同步时间；从未同步时为 epoch 0（[hasEverSynced] 为 false）。
  DateTime get lastSync =>
      _source?.config.lastSync ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get isSyncing => _source?.isSyncing ?? false;

  String? get lastError => _source?.lastError;

  bool get hasEverSynced => _source?.hasEverSynced ?? false;

  bool get hasPendingChanges => _source?.hasPendingChanges ?? false;

  @override
  void dispose() {
    _source?.removeListener(_forward);
    _source = null;
    super.dispose();
  }
}
