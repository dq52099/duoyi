import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background sync and sharing hide stale-backend route diagnostics', () {
    final cloud = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final share = File('lib/providers/share_provider.dart').readAsStringSync();

    expect(cloud, contains('云同步暂不可用，请稍后重试或联系管理员'));
    expect(cloud, contains('_userVisibleSyncError'));
    expect(cloud, isNot(contains('_lastError = e.toString();')));
    expect(cloud, isNot(contains('_lastError = error.toString();')));

    expect(share, contains('共享空间服务暂不可用，请稍后重试或联系管理员'));
    expect(share, contains('_userVisibleWorkspaceError'));
    expect(share, isNot(contains('_lastError = e.toString();')));
  });
}
