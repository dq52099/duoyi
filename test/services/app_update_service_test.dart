import 'package:duoyi/services/app_update_service.dart';
import 'package:test/test.dart';

void main() {
  test('release notes display hides GitHub generated full changelog link', () {
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.0.0',
    );

    final display = service.debugFormatReleaseNotesForTest('''
## 更新内容
- 修复 AI 配置测试误报
- 更新弹框显示具体摘要

**Full Changelog**: https://github.com/dq52099/duoyi/compare/v1.0.0...v1.0.1
''');

    expect(display, contains('修复 AI 配置测试误报'));
    expect(display, contains('更新弹框显示具体摘要'));
    expect(display, isNot(contains('Full Changelog')));
    expect(display, isNot(contains('compare/v1.0.0')));
  });

  test(
    'minimum supported version only locks app when force update is enabled',
    () {
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.9',
      );

      service.debugSetUpdatePolicyForTest(
        latestVersion: '1.2.0',
        minimumSupportedVersion: '1.2.0',
        forceUpdateRequired: false,
      );
      expect(service.hasUpdate, isTrue);
      expect(service.mustUpdate, isFalse);

      service.debugSetUpdatePolicyForTest(
        latestVersion: '1.2.0',
        minimumSupportedVersion: '1.2.0',
        forceUpdateRequired: true,
      );
      expect(service.mustUpdate, isTrue);
    },
  );
}
