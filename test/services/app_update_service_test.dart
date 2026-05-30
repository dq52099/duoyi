import 'dart:convert';
import 'package:duoyi/core/app_update_policy.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'dart:io';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('release notes display hides GitHub generated full changelog link', () {
    final display = formatUpdateNotesForDisplay('''
## 更新内容
- 修复 AI 配置测试误报
- 更新弹框显示具体摘要

**Full Changelog**: https://github.com/dq52099/duoyi/compare/v1.0.0...v1.0.1
''');

    expect(display, startsWith('本次更新摘要：'));
    expect(display, contains('- 修复 AI 配置测试误报'));
    expect(display, contains('- 更新弹框显示具体摘要'));
    expect(display, isNot(contains('Full Changelog')));
    expect(display, isNot(contains('compare/v1.0.0')));
  });

  test(
    'minimum supported version only locks app when force update is enabled',
    () {
      expect(compareAppVersions('1.2.0', '1.1.9'), greaterThan(0));
      expect(
        shouldForceAppUpdate(
          currentVersion: '1.1.9',
          latestVersion: '1.2.0',
          minimumSupportedVersion: '1.2.0',
          forceUpdateRequired: false,
        ),
        isFalse,
      );
      expect(
        shouldForceAppUpdate(
          currentVersion: '1.1.9',
          latestVersion: '1.2.0',
          minimumSupportedVersion: '1.2.0',
          forceUpdateRequired: true,
        ),
        isTrue,
      );
    },
  );

  test(
    'server force update policy blocks current app when version is raised',
    () {
      expect(
        shouldForceAppUpdate(
          currentVersion: '1.1.9',
          latestVersion: '1.2.0',
          minimumSupportedVersion: '1.1.9',
          forceUpdateRequired: true,
        ),
        isTrue,
      );
      expect(
        shouldForceAppUpdate(
          currentVersion: '1.1.9',
          latestVersion: '1.1.9',
          minimumSupportedVersion: '1.1.9',
          forceUpdateRequired: true,
        ),
        isFalse,
      );
    },
  );

  test('client uses backend mobile update before GitHub fallback', () {
    final source = File(
      'lib/services/app_update_service.dart',
    ).readAsStringSync();
    final checkStart = source.indexOf('Future<void> checkNow()');
    final checkEnd = source.indexOf(
      'Future<void> checkServerPolicyNow()',
      checkStart,
    );
    expect(checkStart, greaterThanOrEqualTo(0));
    expect(checkEnd, greaterThan(checkStart));
    final checkNow = source.substring(checkStart, checkEnd);

    expect(source, contains('_checkBackendMobileUpdate'));
    expect(source, contains("_backendUri("));
    expect(source, contains("'/api/mobile/apps/duoyi/update'"));
    expect(source, contains('current_version_code'));
    expect(source, contains('major * 100000 + minor * 10000 + patch'));
    expect(checkNow, contains('bool? mobileUpdateLoaded;'));
    expect(
      checkNow,
      contains('mobileUpdateLoaded = await _checkBackendMobileUpdate()'),
    );
    expect(checkNow, contains('if (!e.allowGitHubFallback) rethrow;'));
    expect(checkNow, contains('if (configLoaded != true)'));
    expect(checkNow, contains('_mergeGitHubLatestRelease('));
  });

  test('backend update errors do not silently fall back to GitHub', () {
    final source = File(
      'lib/services/app_update_service.dart',
    ).readAsStringSync();

    expect(source, contains('class _BackendUpdateCheckException'));
    expect(source, contains('ApiClient.requiredApiContractVersion'));
    expect(source, contains('ApiClient.requiredApiContractRoutesHash'));
    expect(source, contains('移动端更新接口返回'));
    expect(source, contains('/api/config 返回'));
    expect(
      source,
      isNot(contains('if (resp.statusCode != 200) return null;')),
      reason:
          'Only 404 should use compatibility fallback; 5xx/invalid JSON must surface instead of losing force-update policy.',
    );
  });

  test(
    'mobile update 404 with stale backend contract still falls back to GitHub',
    () async {
      final seen = <String>[];
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.9',
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add(request.url.path);
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.url.path == '/api/config') {
            return http.Response(
              '{"version":"3.1.0","registration_enabled":true}',
              200,
            );
          }
          return http.Response('{"tag_name":"v9.9.9","assets":[]}', 200);
        }),
      );

      await service.checkNow();

      expect(seen, [
        '/api/mobile/apps/duoyi/update',
        '/api/config',
        '/repos/dq52099/duoyi/releases/latest',
      ]);
      expect(service.error, isNull);
      expect(service.latestVersion, 'v9.9.9');
      expect(service.hasUpdate, isTrue);
    },
  );

  test(
    'server config with outdated contract still falls back to GitHub',
    () async {
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.9',
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.url.path == '/api/config') {
            return http.Response(
              '{"api_contract_version":"2024-01-01.1","version":"3.1.0"}',
              200,
            );
          }
          return http.Response('{"tag_name":"v9.9.9","assets":[]}', 200);
        }),
      );

      await service.checkNow();

      expect(service.error, isNull);
      expect(service.latestVersion, 'v9.9.9');
      expect(service.hasUpdate, isTrue);
    },
  );

  test(
    'server config with route hash mismatch still falls back to GitHub',
    () async {
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.9',
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.url.path == '/api/config') {
            return http.Response(
              json.encode({
                'api_contract_version': ApiClient.requiredApiContractVersion,
                'required_routes_hash': 'stale-routes',
                'version': '3.1.0',
              }),
              200,
            );
          }
          return http.Response('{"tag_name":"v9.9.9","assets":[]}', 200);
        }),
      );

      await service.checkNow();

      expect(service.error, isNull);
      expect(service.latestVersion, 'v9.9.9');
      expect(service.hasUpdate, isTrue);
    },
  );

  test('backend mobile update fills missing release notes from GitHub', () async {
    final seen = <String>[];
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.9',
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        seen.add(request.url.path);
        if (request.url.path == '/api/mobile/apps/duoyi/update') {
          return http.Response(json.encode(_mobileUpdatePayload()), 200);
        }
        if (request.url.path == '/repos/dq52099/duoyi/releases/latest') {
          return http.Response.bytes(
            utf8.encode(
              '{"tag_name":"v2.0.0","body":"## 更新内容\\n- 修复通知红点状态\\n- 更新弹框显示具体说明","assets":[]}',
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    await service.checkNow();

    expect(seen, [
      '/api/mobile/apps/duoyi/update',
      '/repos/dq52099/duoyi/releases/latest',
    ]);
    expect(service.error, isNull);
    expect(service.latestVersion, '2.0.0');
    expect(service.latestUrl, 'https://cdn.duoyi.test/duoyi-2.0.0.apk');
    expect(service.latestNotesForDisplay, contains('- 修复通知红点状态'));
    expect(service.latestNotesForDisplay, contains('- 更新弹框显示具体说明'));
  });

  test(
    'server policy startup check also fills missing release notes from GitHub',
    () async {
      final seen = <String>[];
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.9',
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add(request.url.path);
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(json.encode(_mobileUpdatePayload()), 200);
          }
          if (request.url.path == '/repos/dq52099/duoyi/releases/latest') {
            return http.Response.bytes(
              utf8.encode(
                '{"tag_name":"v2.0.0","body":"## 更新内容\\n- 强制更新页展示发布说明","assets":[]}',
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkServerPolicyNow();

      expect(seen, [
        '/api/mobile/apps/duoyi/update',
        '/repos/dq52099/duoyi/releases/latest',
      ]);
      expect(service.error, isNull);
      expect(service.mustUpdate, isTrue);
      expect(service.latestNotesForDisplay, contains('- 强制更新页展示发布说明'));
    },
  );

  test('backend mobile minimum supported version can force update', () async {
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.9',
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/mobile/apps/duoyi/update') {
          return http.Response(
            json.encode(
              _mobileUpdatePayload(
                available: false,
                latestVersion: '1.1.9',
                forceUpdate: false,
                forceUpdateRequired: true,
                minimumSupportedVersion: '2.1.0',
              ),
            ),
            200,
          );
        }
        return http.Response('{"tag_name":"v1.1.9","assets":[]}', 200);
      }),
    );

    await service.checkNow();

    expect(service.error, isNull);
    expect(service.minimumSupportedVersion, '2.1.0');
    expect(service.forceUpdateRequired, isTrue);
    expect(service.mustUpdate, isTrue);
  });

  test(
    'mobile update 200 with route hash mismatch still falls back to GitHub',
    () async {
      final seen = <String>[];
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.9',
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add(request.url.path);
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(
              json.encode(
                _mobileUpdatePayload(requiredRoutesHash: 'stale-routes'),
              ),
              200,
            );
          }
          if (request.url.path == '/api/config') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          return http.Response('{"tag_name":"v9.9.9","assets":[]}', 200);
        }),
      );

      await service.checkNow();

      expect(seen, [
        '/api/mobile/apps/duoyi/update',
        '/api/config',
        '/repos/dq52099/duoyi/releases/latest',
      ]);
      expect(service.error, isNull);
      expect(service.latestVersion, 'v9.9.9');
      expect(service.hasUpdate, isTrue);
    },
  );

  test(
    'backend force update switch also locks when backend reports blocked url',
    () {
      final source = File(
        'lib/services/app_update_service.dart',
      ).readAsStringSync();
      final mobileStart = source.indexOf(
        'Future<bool?> _checkBackendMobileUpdate',
      );
      final mobileEnd = source.indexOf('String _stringValue', mobileStart);
      expect(mobileStart, greaterThanOrEqualTo(0));
      expect(mobileEnd, greaterThan(mobileStart));
      final mobileUpdate = source.substring(mobileStart, mobileEnd);

      expect(mobileUpdate, contains("data['force_update'] == true ||"));
      expect(
        mobileUpdate,
        contains('policyEnabled && (available || belowMinimum)'),
        reason:
            '移动更新强更需要同时兼容新 force_update_required 和旧 force_app_update_enabled，并让最低支持版本参与判断。',
      );
    },
  );

  test('server config force update fallback blocks even without manual url', () {
    final source = File(
      'lib/services/app_update_service.dart',
    ).readAsStringSync();
    final configStart = source.indexOf('Future<bool?> _checkServerConfig');
    final configEnd = source.indexOf(
      'Future<bool?> _checkBackendMobileUpdate',
      configStart,
    );
    expect(configStart, greaterThanOrEqualTo(0));
    expect(configEnd, greaterThan(configStart));
    final config = source.substring(configStart, configEnd);

    expect(
      config,
      contains("_forceUpdateRequired = data['force_update_required'] == true"),
      reason:
          '/api/config fallback must honor the admin force-update switch; the gate itself explains when no install URL is configured.',
    );
  });

  test('backend update checks normalize trailing slash base urls', () {
    final source = File(
      'lib/services/app_update_service.dart',
    ).readAsStringSync();
    final helperStart = source.indexOf('Uri _backendUri(');
    final helperEnd = source.indexOf('int _versionToCode', helperStart);
    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helperEnd, greaterThan(helperStart));
    final helper = source.substring(helperStart, helperEnd);

    expect(helper, contains("replaceFirst(RegExp(r'/+\$'), '')"));
    expect(helper, contains("\$cleanPath"));
    expect(helper, contains('queryParameters: queryParameters'));
    expect(source, isNot(contains("Uri.parse('\$base/api/config')")));
    expect(
      source,
      isNot(contains("Uri.parse('\$base/api/mobile/apps/duoyi/update')")),
    );
  });

  test('backend update download urls are resolved and blocked reasons surface', () {
    final source = File(
      'lib/services/app_update_service.dart',
    ).readAsStringSync();
    final mineScreen = File('lib/screens/mine_screen.dart').readAsStringSync();

    expect(source, contains('String? _forceUpdateBlockedReason;'));
    expect(source, contains('String? get forceUpdateBlockedReason'));
    expect(
      source,
      contains('String _resolveBackendUrl(String base, String value)'),
    );
    expect(source, contains('baseUri.resolve(raw).toString()'));
    expect(source, contains("if (raw.startsWith('//')) return 'https:\$raw';"));
    expect(
      source,
      contains(
        "final blockedReason = _stringValue(data['force_update_blocked_reason'])",
      ),
    );
    expect(
      source,
      contains(
        '_forceUpdateBlockedReason = blockedReason.isEmpty ? null : blockedReason',
      ),
    );
    expect(
      source,
      contains('final downloadUrl = _resolveBackendUrl('),
      reason:
          'Both backend update endpoints should normalize relative APK URLs.',
    );
    expect(mineScreen, contains('updater.forceUpdateBlockedReason'));
    expect(mineScreen, contains('安装包不可用'));
  });
}

Map<String, Object?> _mobileUpdatePayload({
  String requiredRoutesHash = ApiClient.requiredApiContractRoutesHash,
  bool available = true,
  String latestVersion = '2.0.0',
  bool forceUpdate = true,
  bool forceUpdateRequired = true,
  String minimumSupportedVersion = '1.1.9',
}) {
  return {
    'api_contract_version': ApiClient.requiredApiContractVersion,
    'required_routes_hash': requiredRoutesHash,
    'available': available,
    'latest_version_name': latestVersion,
    'minimum_supported_version': minimumSupportedVersion,
    'download_url': 'https://cdn.duoyi.test/duoyi-2.0.0.apk',
    'release_notes': '',
    'force_update': forceUpdate,
    'force_update_required': forceUpdateRequired,
    'force_app_update_enabled': forceUpdateRequired,
  };
}
