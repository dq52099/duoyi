import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/app_update_policy.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

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
      expect(
        shouldForceAppUpdate(
          currentVersion: '1.1.13',
          latestVersion: '1.1.13',
          minimumSupportedVersion: '1.1.13',
          forceUpdateRequired: true,
          currentVersionCode: 110012,
          latestVersionCode: 120013,
        ),
        isTrue,
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
    expect(source, contains('final int? currentVersionCode;'));
    expect(source, contains('this.currentVersionCode,'));
    expect(
      source,
      contains('currentVersionCode ?? _versionToCode(currentVersion)'),
    );
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

  test('backend update request sends real build code when provided', () async {
    Uri? mobileUri;
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.13',
      currentVersionCode: 120013,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/mobile/apps/duoyi/update') {
          mobileUri = request.url;
          return http.Response(
            json.encode({
              'api_contract_version': ApiClient.requiredApiContractVersion,
              'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
              'available': false,
              'latest_version_name': '1.1.13',
              'latest_version_code': 120013,
              'minimum_supported_version': '1.1.13',
              'minimum_supported_version_code': 120013,
              'download_url': '',
              'release_notes': '',
              'force_update': false,
              'force_update_required': false,
              'force_app_update_enabled': false,
            }),
            200,
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    await service.checkNow();

    expect(mobileUri, isNotNull);
    expect(mobileUri!.queryParameters['current_version'], '1.1.13');
    expect(mobileUri!.queryParameters['current_version_code'], '120013');
  });

  test('same version with newer build code still surfaces update', () async {
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.13',
      currentVersionCode: 110012,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/mobile/apps/duoyi/update') {
          return http.Response(
            json.encode(
              _mobileUpdatePayload(
                latestVersion: '1.1.13',
                latestVersionCode: 120013,
                minimumSupportedVersion: '1.1.13',
                minimumSupportedVersionCode: 120013,
                available: true,
                forceUpdate: true,
                forceUpdateRequired: true,
              ),
            ),
            200,
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    await service.checkNow();

    expect(service.error, isNull);
    expect(service.latestVersion, '1.1.13');
    expect(service.latestVersionCode, 120013);
    expect(service.hasUpdate, isTrue);
    expect(service.mustUpdate, isTrue);
  });

  test(
    'server policy startup check avoids GitHub and uses fallback notes',
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

      expect(seen, ['/api/mobile/apps/duoyi/update']);
      expect(service.error, isNull);
      expect(service.mustUpdate, isTrue);
      expect(service.latestNotesForDisplay, contains('版本 2.0.0'));
    },
  );

  test(
    'startup policy check hides stale backend compatibility prompt',
    () async {
      final seen = <String>[];
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.10',
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

      await service.checkServerPolicyNow();

      expect(seen, ['/api/mobile/apps/duoyi/update', '/api/config']);
      expect(service.error, isNull);
      expect(service.mustUpdate, isFalse);
      expect(service.latestVersion, isNull);
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
    'stale backend update versions are displayed as current version',
    () async {
      final service = AppUpdateService(
        repo: 'dq52099/duoyi',
        currentVersion: '1.1.34',
        currentVersionCode: 140000,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response.bytes(
              utf8.encode(
                json.encode(
                  _mobileUpdatePayload(
                    available: false,
                    latestVersion: '1.1.20',
                    latestVersionCode: 110020,
                    forceUpdate: false,
                    forceUpdateRequired: true,
                    minimumSupportedVersion: '1.1.20',
                    minimumSupportedVersionCode: 110020,
                    releaseNotes: '旧强更配置应按当前版本展示',
                    downloadUrl: 'https://cdn.duoyi.test/duoyi-1.1.20.apk',
                  ),
                ),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkNow();

      expect(service.error, isNull);
      expect(service.latestVersion, '1.1.34');
      expect(service.latestVersionCode, 140000);
      expect(service.minimumSupportedVersion, '1.1.34');
      expect(service.minimumSupportedVersionCode, 140000);
      expect(service.hasUpdate, isFalse);
      expect(service.mustUpdate, isFalse);
      expect(service.forceUpdateRequired, isFalse);
      expect(service.latestNotesForDisplay, contains('旧强更配置应按当前版本展示'));
    },
  );

  test('backend stale apk url is replaced by release channel apk', () async {
    final seen = <String>[];
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.34',
      currentVersionCode: 140000,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        seen.add(request.url.path);
        if (request.url.path == '/api/mobile/apps/duoyi/update') {
          return http.Response.bytes(
            utf8.encode(
              json.encode(
                _mobileUpdatePayload(
                  latestVersion: '1.1.36',
                  latestVersionCode: 140002,
                  minimumSupportedVersion: '1.1.34',
                  minimumSupportedVersionCode: 140000,
                  downloadUrl: 'https://cdn.duoyi.test/duoyi-v1.1.20.apk',
                ),
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/repos/dq52099/duoyi/releases/latest') {
          return http.Response.bytes(
            utf8.encode(
              json.encode({
                'tag_name': 'v1.1.36',
                'body': '## 更新内容\n- 修复强制更新安装包地址',
                'assets': [
                  {
                    'name': 'duoyi-v1.1.36.apk',
                    'browser_download_url':
                        'https://github.com/dq52099/duoyi/releases/download/v1.1.36/duoyi-v1.1.36.apk',
                  },
                ],
              }),
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
    expect(service.latestVersion, '1.1.36');
    expect(service.latestUrl, contains('duoyi-v1.1.36.apk'));
    expect(service.latestUrl, isNot(contains('1.1.20')));
    expect(service.mustUpdate, isTrue);
  });

  test('mobile force_update response is honored directly', () async {
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.34',
      currentVersionCode: 140000,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/mobile/apps/duoyi/update') {
          return http.Response.bytes(
            utf8.encode(
              json.encode(
                _mobileUpdatePayload(
                  available: true,
                  latestVersion: '1.1.34',
                  latestVersionCode: 140002,
                  forceUpdate: true,
                  forceUpdateRequired: true,
                  minimumSupportedVersion: '1.1.34',
                  minimumSupportedVersionCode: 140000,
                ),
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    await service.checkNow();

    expect(service.forceUpdateRequired, isTrue);
    expect(service.hasUpdate, isTrue);
    expect(service.mustUpdate, isTrue);
  });

  test('check update restores downloaded installer without network', () async {
    final tmp = await Directory.systemTemp.createTemp('duoyi_update_test_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final apk = File('${tmp.path}/duoyi-v1.1.34.apk');
    await apk.writeAsBytes(const [1, 2, 3]);
    SharedPreferences.setMockInitialValues({
      'duoyi_update_downloaded_apk_path': apk.path,
      'duoyi_update_downloaded_apk_version': '1.1.34',
      'duoyi_update_downloaded_apk_version_code': 140002,
      'duoyi_update_downloaded_apk_url':
          'https://cdn.duoyi.test/duoyi-v1.1.34.apk',
      'duoyi_update_downloaded_apk_asset_name': 'duoyi-v1.1.34.apk',
    });
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.34',
      currentVersionCode: 140000,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        throw const SocketException('offline');
      }),
    );

    await service.checkNow();

    expect(service.hasDownloadedInstaller, isTrue);
    expect(service.downloadedFilePath, apk.path);
    expect(service.latestVersion, '1.1.34');
    expect(service.latestVersionCode, 140002);
    expect(service.latestUrl, 'https://cdn.duoyi.test/duoyi-v1.1.34.apk');
    expect(service.hasUpdate, isTrue);
  });

  test('stale downloaded installer url is not reused offline', () async {
    final tmp = await Directory.systemTemp.createTemp('duoyi_update_test_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final apk = File('${tmp.path}/duoyi-v1.1.20.apk');
    await apk.writeAsBytes(const [1, 2, 3]);
    SharedPreferences.setMockInitialValues({
      'duoyi_update_downloaded_apk_path': apk.path,
      'duoyi_update_downloaded_apk_version': '1.1.36',
      'duoyi_update_downloaded_apk_version_code': 140002,
      'duoyi_update_downloaded_apk_url':
          'https://cdn.duoyi.test/duoyi-v1.1.20.apk',
      'duoyi_update_downloaded_apk_asset_name': 'duoyi-v1.1.20.apk',
    });
    final service = AppUpdateService(
      repo: 'dq52099/duoyi',
      currentVersion: '1.1.34',
      currentVersionCode: 140000,
      backendBaseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        throw const SocketException('offline');
      }),
    );

    await service.checkNow();

    expect(service.hasDownloadedInstaller, isFalse);
    expect(service.downloadedFilePath, isNull);
    expect(service.latestUrl, isNull);
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
      expect(mobileUpdate, contains('final forceUpdate ='));
      expect(
        mobileUpdate,
        contains('policyEnabled && (available || belowMinimum)'),
      );
      expect(mobileUpdate, contains('_forceUpdateRequired = forceUpdate;'));
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
      contains('final policyEnabled ='),
      reason:
          '/api/config fallback must honor the admin force-update switch; the gate itself explains when no install URL is configured.',
    );
    expect(config, contains('_forceUpdateRequired = policyEnabled;'));
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
      contains('final rawDownloadUrl = _resolveBackendUrl('),
      reason:
          'Both backend update endpoints should normalize relative APK URLs.',
    );
    expect(source, contains('_sanitizeDownloadUrlForVersion('));
    expect(source, contains('_downloadUrlLooksStaleForVersion'));
    expect(mineScreen, contains('updater.forceUpdateBlockedReason'));
    expect(mineScreen, contains('安装包不可用'));
    expect(source, contains('hasDownloadedInstaller'));
    expect(source, contains('_restoreDownloadedInstaller'));
    expect(source, contains('_rememberDownloadedInstaller'));
    expect(source, contains('downloadedFileExists'));
  });
}

Map<String, Object?> _mobileUpdatePayload({
  String requiredRoutesHash = ApiClient.requiredApiContractRoutesHash,
  bool available = true,
  String latestVersion = '2.0.0',
  int? latestVersionCode,
  bool forceUpdate = true,
  bool forceUpdateRequired = true,
  String minimumSupportedVersion = '1.1.9',
  int? minimumSupportedVersionCode,
  String releaseNotes = '',
  String downloadUrl = 'https://cdn.duoyi.test/duoyi-2.0.0.apk',
}) {
  final payload = <String, Object?>{
    'api_contract_version': ApiClient.requiredApiContractVersion,
    'required_routes_hash': requiredRoutesHash,
    'available': available,
    'latest_version_name': latestVersion,
    'minimum_supported_version': minimumSupportedVersion,
    'download_url': downloadUrl,
    'release_notes': releaseNotes,
    'force_update': forceUpdate,
    'force_update_required': forceUpdateRequired,
    'force_app_update_enabled': forceUpdateRequired,
  };
  if (latestVersionCode != null) {
    payload['latest_version_code'] = latestVersionCode;
  }
  if (minimumSupportedVersionCode != null) {
    payload['minimum_supported_version_code'] = minimumSupportedVersionCode;
  }
  return payload;
}
