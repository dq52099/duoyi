import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background sync and sharing hide stale-backend route diagnostics', () {
    final cloud = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final share = File('lib/providers/share_provider.dart').readAsStringSync();
    final apiClient = File('lib/services/api_client.dart').readAsStringSync();

    expect(cloud, contains('云同步暂不可用，请稍后重试或联系管理员'));
    expect(cloud, contains('_userVisibleSyncError'));
    expect(cloud, contains('userVisibleApiError('));
    expect(cloud, isNot(contains('_lastError = e.toString();')));
    expect(cloud, isNot(contains('_lastError = error.toString();')));

    expect(share, contains('共享空间服务暂不可用，请稍后重试或联系管理员'));
    expect(share, contains('_userVisibleWorkspaceError'));
    expect(share, contains('userVisibleApiError('));
    expect(share, isNot(contains('_lastError = e.toString();')));

    expect(apiClient, contains('isBackendCompatibilityDiagnosticMessage'));
    expect(apiClient, contains('userVisibleApiError('));
    expect(apiClient, contains('服务暂不可用，请稍后重试或联系管理员'));
  });

  test('screens do not show backend deployment diagnostics directly', () {
    for (final path in const [
      'lib/screens/login_screen.dart',
      'lib/screens/profile_screen.dart',
      'lib/screens/feedback_screen.dart',
      'lib/screens/announcements_screen.dart',
      'lib/screens/admin_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('userVisibleApiError('), reason: path);
      expect(source, isNot(contains('e.message')), reason: path);
      expect(
        source,
        isNot(contains('error is ApiException ? error.message')),
        reason: path,
      );
    }

    final shareScreen = File(
      'lib/screens/share_screen.dart',
    ).readAsStringSync();
    expect(shareScreen, contains('userVisibleApiError('));
    expect(shareScreen, isNot(contains(r'打开提及失败: $e')));
    expect(shareScreen, isNot(contains(r'创建失败: $e')));
    expect(shareScreen, isNot(contains(r'加入失败: $e')));
    expect(shareScreen, isNot(contains(r'生成失败: $e')));
    expect(shareScreen, isNot(contains(r'发送失败: $e')));
    expect(shareScreen, contains("打开提及失败: \${_shareError(e)}"));

    final todoDetail = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();
    expect(todoDetail, contains('userVisibleApiError('));
    expect(todoDetail, isNot(contains(r'评论发送失败: $e')));
    expect(todoDetail, contains("评论发送失败: \${_shareError(e)}"));
  });
}
