import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/app_update_policy.dart';
import 'api_client.dart';
import 'app_update_installer.dart';

/// Polls a GitHub repo's latest release and exposes update info.
class AppUpdateService extends ChangeNotifier {
  final String repo; // e.g. "dq52099/duoyi"
  final String currentVersion; // e.g. "1.0.0"
  final String? backendBaseUrl;
  final http.Client _httpClient;

  AppUpdateService({
    required this.repo,
    required this.currentVersion,
    this.backendBaseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  String? _latestVersion;
  String? _latestUrl;
  String? _latestAssetName;
  String? _latestNotes;
  String? _minimumSupportedVersion;
  String? _forceUpdateBlockedReason;
  bool _forceUpdateRequired = false;
  bool _serverPolicyLoaded = false;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  double? _downloadProgress;
  String? _downloadedFilePath;
  String? _error;

  String? get latestVersion => _latestVersion;
  String? get latestUrl => _latestUrl;
  String? get latestAssetName => _latestAssetName;
  String? get latestNotes => _latestNotes;
  String? get minimumSupportedVersion => _minimumSupportedVersion;
  String? get forceUpdateBlockedReason => _forceUpdateBlockedReason;
  bool get forceUpdateRequired => _forceUpdateRequired;
  String get latestNotesForDisplay {
    final notes = _formatReleaseNotes(_latestNotes);
    if (notes.isNotEmpty) return notes;
    if (_latestVersion != null) return '此版本没有填写更新说明。';
    return '';
  }

  bool get checking => _checking;
  bool get downloading => _downloading;
  bool get installing => _installing;
  bool get busy => _checking || _downloading || _installing;
  double? get downloadProgress => _downloadProgress;
  String? get downloadedFilePath => _downloadedFilePath;
  String? get error => _error;

  bool get hasUpdate {
    if (_latestVersion == null) return false;
    return compareAppVersions(_latestVersion!, currentVersion) > 0;
  }

  bool get mustUpdate => shouldForceAppUpdate(
    currentVersion: currentVersion,
    latestVersion: _latestVersion,
    minimumSupportedVersion: _minimumSupportedVersion,
    forceUpdateRequired: _forceUpdateRequired,
  );

  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    _downloadedFilePath = null;
    notifyListeners();
    try {
      bool? mobileUpdateLoaded;
      try {
        mobileUpdateLoaded = await _checkBackendMobileUpdate();
      } on _BackendUpdateCheckException catch (e) {
        if (!e.allowGitHubFallback) rethrow;
        debugPrint('[AppUpdate] backend compatibility fallback: ${e.message}');
        mobileUpdateLoaded = null;
      }
      bool? configLoaded;
      if (mobileUpdateLoaded == true) {
        configLoaded = true;
      } else {
        try {
          configLoaded = await _checkServerConfig();
        } on _BackendUpdateCheckException catch (e) {
          if (!e.allowGitHubFallback) rethrow;
          debugPrint(
            '[AppUpdate] backend compatibility fallback: ${e.message}',
          );
          configLoaded = null;
        }
      }
      if (configLoaded == false) {
        _latestVersion = null;
        _latestUrl = null;
        _latestAssetName = null;
        _latestNotes = null;
        _minimumSupportedVersion = null;
        _forceUpdateBlockedReason = null;
        _forceUpdateRequired = false;
        _serverPolicyLoaded = false;
      }
      if (configLoaded != true) {
        await _mergeGitHubLatestRelease(
          keepServerPolicy: false,
          fillMissingOnly: false,
        );
      } else {
        await _fillMissingDisplayDataFromGitHub();
      }
      if (_serverPolicyLoaded && _latestNotes == null) {
        _latestNotes = _fallbackUpdateNotes(_latestVersion);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<void> checkServerPolicyNow() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      bool? mobileUpdateLoaded;
      try {
        mobileUpdateLoaded = await _checkBackendMobileUpdate();
      } on _BackendUpdateCheckException catch (e) {
        if (!e.allowGitHubFallback) rethrow;
        debugPrint('[AppUpdate] backend compatibility fallback: ${e.message}');
        mobileUpdateLoaded = null;
      }
      final configLoaded = mobileUpdateLoaded == true
          ? true
          : await _checkServerConfig();
      if (configLoaded == false) {
        _latestVersion = null;
        _latestUrl = null;
        _latestAssetName = null;
        _latestNotes = null;
        _minimumSupportedVersion = null;
        _forceUpdateBlockedReason = null;
        _forceUpdateRequired = false;
        _serverPolicyLoaded = false;
      }
      if (configLoaded == true) {
        await _fillMissingDisplayDataFromGitHub();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<bool?> _checkServerConfig() async {
    try {
      final base = _serverBaseUrl;
      if (base.isEmpty && !kIsWeb) return null;
      final uri = _backendUri(base, '/api/config');
      final resp = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 404) return null;
      if (resp.statusCode != 200) {
        throw _BackendUpdateCheckException(
          '检查更新失败：/api/config 返回 ${resp.statusCode}',
        );
      }
      final decoded = json.decode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) {
        throw const _BackendUpdateCheckException('检查更新失败：/api/config 返回结构错误');
      }
      final rawConfig = Map<String, dynamic>.from(decoded);
      final contractDiagnosis = _backendContractDiagnosisText(rawConfig);
      if (contractDiagnosis != null) {
        throw _BackendUpdateCheckException(
          '检查更新失败：当前后端未部署本版本更新接口：/api/mobile/apps/duoyi/update。$contractDiagnosis',
          allowGitHubFallback: true,
        );
      }
      final data = decoded['app_update'] is Map
          ? Map<String, dynamic>.from(decoded['app_update'] as Map)
          : rawConfig;
      final latest = _stringValue(data['latest_version']);
      final downloadUrl = _resolveBackendUrl(
        base,
        _stringValue(data['update_download_url']),
      );
      final notes = _stringValue(data['update_notes']);
      final minimum = _stringValue(data['minimum_supported_version']);
      final hasNewerLatest =
          latest.isNotEmpty && compareAppVersions(latest, currentVersion) > 0;
      final hasRaisedMinimum =
          minimum.isNotEmpty && compareAppVersions(minimum, currentVersion) > 0;
      final hasPolicy =
          downloadUrl.isNotEmpty ||
          notes.isNotEmpty ||
          hasNewerLatest ||
          hasRaisedMinimum ||
          data['force_update_required'] == true;
      if (!hasPolicy) return false;
      _latestVersion = latest.isEmpty ? null : latest;
      _latestUrl = downloadUrl.isEmpty ? null : downloadUrl;
      _latestAssetName = _assetNameFromUrl(downloadUrl);
      _latestNotes = notes.isEmpty ? null : notes;
      _minimumSupportedVersion = minimum.isEmpty ? null : minimum;
      _forceUpdateBlockedReason = null;
      _forceUpdateRequired = data['force_update_required'] == true;
      _serverPolicyLoaded = true;
      return true;
    } on _BackendUpdateCheckException {
      rethrow;
    } catch (e) {
      throw _BackendUpdateCheckException('检查更新失败：读取 /api/config 失败：$e');
    }
  }

  Future<bool?> _checkBackendMobileUpdate() async {
    try {
      final base = _serverBaseUrl;
      if (base.isEmpty && !kIsWeb) return null;
      final currentVersionCode = _versionToCode(currentVersion);
      final uri = _backendUri(
        base,
        '/api/mobile/apps/duoyi/update',
        queryParameters: {
          'current_version': currentVersion,
          'current_version_code': currentVersionCode.toString(),
        },
      );
      final resp = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 404) return null;
      if (resp.statusCode != 200) {
        throw _BackendUpdateCheckException(
          '检查更新失败：移动端更新接口返回 ${resp.statusCode}',
        );
      }
      final decoded = json.decode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) {
        throw const _BackendUpdateCheckException('检查更新失败：移动端更新接口返回结构错误');
      }
      final data = Map<String, dynamic>.from(decoded);
      final contractDiagnosis = _backendContractDiagnosisText(data);
      if (contractDiagnosis != null) {
        throw _BackendUpdateCheckException(
          '检查更新失败：当前后端未部署本版本更新接口：/api/mobile/apps/duoyi/update。$contractDiagnosis',
          allowGitHubFallback: true,
        );
      }
      final latest = _stringValue(data['latest_version_name']);
      final downloadUrl = _resolveBackendUrl(
        base,
        _stringValue(data['download_url']),
      );
      final notes = _stringValue(data['release_notes']);
      final minimum = _stringValue(data['minimum_supported_version']);
      final blockedReason = _stringValue(data['force_update_blocked_reason']);
      final available =
          data['available'] == true ||
          (latest.isNotEmpty && compareAppVersions(latest, currentVersion) > 0);
      final belowMinimum =
          minimum.isNotEmpty && compareAppVersions(currentVersion, minimum) < 0;
      final policyEnabled =
          data['force_update_required'] == true ||
          data['force_app_update_enabled'] == true;
      final forceUpdate =
          data['force_update'] == true ||
          (policyEnabled && (available || belowMinimum));
      if (!available && !forceUpdate && notes.isEmpty && downloadUrl.isEmpty) {
        return false;
      }
      _latestVersion = latest.isEmpty ? null : latest;
      _latestUrl = downloadUrl.isEmpty ? null : downloadUrl;
      _latestAssetName = _assetNameFromUrl(downloadUrl);
      _latestNotes = notes.isEmpty ? null : notes;
      _minimumSupportedVersion = minimum.isEmpty ? null : minimum;
      _forceUpdateBlockedReason = blockedReason.isEmpty ? null : blockedReason;
      _forceUpdateRequired = forceUpdate || policyEnabled;
      _serverPolicyLoaded = true;
      return true;
    } on _BackendUpdateCheckException {
      rethrow;
    } catch (e) {
      throw _BackendUpdateCheckException('检查更新失败：读取移动端更新接口失败：$e');
    }
  }

  String get _serverBaseUrl => backendBaseUrl ?? AppConfig.bakedServerUrl;

  String _stringValue(dynamic value) => (value ?? '').toString().trim();

  String _resolveBackendUrl(String base, String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    final baseUri = _backendUri(base, '/');
    return baseUri.resolve(raw).toString();
  }

  Uri _backendUri(
    String base,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    if (base.trim().isEmpty) {
      return Uri.parse(cleanPath).replace(queryParameters: queryParameters);
    }
    var cleanBase = base.trim().replaceFirst(RegExp(r'/+$'), '');
    if (_hasBackendApiPrefix(cleanPath) &&
        cleanBase.endsWith(String.fromCharCodes(const [47, 97, 112, 105]))) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 4);
    }
    return Uri.parse(
      '$cleanBase$cleanPath',
    ).replace(queryParameters: queryParameters);
  }

  bool _hasBackendApiPrefix(String value) {
    if (value.length < 4) return false;
    return value.codeUnitAt(0) == 47 &&
        value.codeUnitAt(1) == 97 &&
        value.codeUnitAt(2) == 112 &&
        value.codeUnitAt(3) == 105 &&
        (value.length == 4 || value.codeUnitAt(4) == 47);
  }

  String? _backendContractDiagnosisText(Map<String, dynamic> decoded) {
    final contractVersion = _stringValue(decoded['api_contract_version']);
    final routesHash = _stringValue(decoded['required_routes_hash']);
    final missingContract = contractVersion.isEmpty;
    final outdatedContract =
        contractVersion.isNotEmpty &&
        _compareApiContractVersions(
              contractVersion,
              ApiClient.requiredApiContractVersion,
            ) <
            0;
    final missingRoutesHash = routesHash.isEmpty;
    final mismatchedRoutesHash =
        routesHash.isNotEmpty &&
        routesHash != ApiClient.requiredApiContractRoutesHash;
    if (!missingContract &&
        !outdatedContract &&
        !missingRoutesHash &&
        !mismatchedRoutesHash) {
      return null;
    }

    final serverVersion = _stringValue(decoded['version']);
    final features = decoded['features'];
    final featureSummary = features is Map
        ? features.entries
              .where((entry) => entry.value == true)
              .map((entry) => entry.key.toString())
              .join(', ')
        : '';
    final parts = <String>[
      if (serverVersion.isNotEmpty) '后端版本 $serverVersion。',
      if (missingContract)
        '缺少接口契约 api_contract_version。'
      else if (outdatedContract)
        '接口契约 $contractVersion 低于客户端要求 ${ApiClient.requiredApiContractVersion}。',
      if (missingRoutesHash)
        '缺少必备路由摘要 required_routes_hash。'
      else if (mismatchedRoutesHash)
        '必备路由摘要 $routesHash 与客户端要求 ${ApiClient.requiredApiContractRoutesHash} 不一致。',
      '请部署当前 backend/main.py 后再重试。',
      if (featureSummary.isNotEmpty) '已声明能力：$featureSummary。',
    ];
    return parts.join('');
  }

  int _compareApiContractVersions(String left, String right) {
    final a = _apiContractVersionParts(left);
    final b = _apiContractVersionParts(right);
    for (var i = 0; i < a.length; i++) {
      final diff = a[i].compareTo(b[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }

  List<int> _apiContractVersionParts(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\.(\d+))?$',
    ).firstMatch(value.trim());
    if (match != null) {
      return [
        int.tryParse(match.group(1) ?? '') ?? 0,
        int.tryParse(match.group(2) ?? '') ?? 0,
        int.tryParse(match.group(3) ?? '') ?? 0,
        int.tryParse(match.group(4) ?? '') ?? 0,
      ];
    }
    final parts = value
        .trim()
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    return [for (var i = 0; i < 4; i++) i < parts.length ? parts[i] : 0];
  }

  int _versionToCode(String value) {
    final parts = value
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split('-')
        .first
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
    final major = parts.isNotEmpty ? parts[0] : 0;
    final minor = parts.length > 1 ? parts[1] : 0;
    final patch = parts.length > 2 ? parts[2] : 0;
    return major * 100000 + minor * 10000 + patch;
  }

  String? _assetNameFromUrl(String url) {
    if (url.trim().isEmpty) return null;
    final parsed = Uri.tryParse(url);
    final segment = parsed == null || parsed.pathSegments.isEmpty
        ? ''
        : parsed.pathSegments.last.trim();
    return segment.isEmpty ? null : Uri.decodeComponent(segment);
  }

  Future<void> _mergeGitHubLatestRelease({
    required bool keepServerPolicy,
    required bool fillMissingOnly,
  }) async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    final resp = await _httpClient.get(
      uri,
      headers: {
        'User-Agent': 'duoyi/1.0',
        'Accept': 'application/vnd.github+json',
      },
    );
    if (resp.statusCode == 404) {
      if (!keepServerPolicy) {
        _latestVersion = null;
        _error = '尚未发布 Release';
      }
      return;
    }
    if (resp.statusCode != 200) {
      if (!keepServerPolicy) {
        _error = '检查更新失败: ${resp.statusCode}';
      }
      return;
    }
    final data = json.decode(utf8.decode(resp.bodyBytes));
    final releaseVersion = (data['tag_name'] as String?)?.trim();
    final releaseNotes = (data['body'] as String?)?.trim();
    final assets = data['assets'];
    Map? asset;
    if (assets is List) {
      asset = _selectBestApkAsset(assets, targetVersion: releaseVersion);
    }
    if (!fillMissingOnly) {
      _latestVersion = releaseVersion;
      _latestNotes = releaseNotes;
      _latestUrl = asset?['browser_download_url'] as String?;
      _latestAssetName = asset?['name'] as String?;
      return;
    }
    if ((_latestVersion == null || _latestVersion!.trim().isEmpty) &&
        releaseVersion != null &&
        releaseVersion.isNotEmpty) {
      _latestVersion = releaseVersion;
    }
    if ((_latestNotes == null || _latestNotes!.trim().isEmpty) &&
        releaseNotes != null &&
        releaseNotes.isNotEmpty) {
      _latestNotes = releaseNotes;
    }
    if ((_latestUrl == null || _latestUrl!.trim().isEmpty) && asset != null) {
      _latestUrl = asset['browser_download_url'] as String?;
      _latestAssetName = asset['name'] as String?;
    }
  }

  Future<void> _fillMissingDisplayDataFromGitHub() async {
    if (!_serverPolicyLoaded) return;
    final versionMissing =
        _latestVersion == null || _latestVersion!.trim().isEmpty;
    final notesMissing = _latestNotes == null || _latestNotes!.trim().isEmpty;
    final urlMissing = _latestUrl == null || _latestUrl!.trim().isEmpty;
    if (!versionMissing && !notesMissing && !urlMissing) {
      return;
    }
    await _mergeGitHubLatestRelease(
      keepServerPolicy: true,
      fillMissingOnly: true,
    );
  }

  @visibleForTesting
  String debugFormatReleaseNotesForTest(String? notes) =>
      _formatReleaseNotes(notes);

  @visibleForTesting
  void debugSetUpdatePolicyForTest({
    String? latestVersion,
    String? minimumSupportedVersion,
    bool forceUpdateRequired = false,
    String? latestUrl,
  }) {
    _latestVersion = latestVersion;
    _minimumSupportedVersion = minimumSupportedVersion;
    _forceUpdateRequired = forceUpdateRequired;
    _latestUrl = latestUrl;
    _latestAssetName = _assetNameFromUrl(latestUrl ?? '');
  }

  @visibleForTesting
  bool debugWouldServerPolicyForceForTest({
    required Map<String, dynamic> data,
  }) {
    final latest = _stringValue(data['latest_version']);
    final minimum = _stringValue(data['minimum_supported_version']);
    final force = data['force_update_required'] == true;
    return shouldForceAppUpdate(
      currentVersion: currentVersion,
      latestVersion: latest.isEmpty ? null : latest,
      minimumSupportedVersion: minimum.isEmpty ? null : minimum,
      forceUpdateRequired: force,
    );
  }

  Future<void> downloadAndInstallLatest() async {
    if (_latestUrl == null) {
      _error = '没有可下载的 APK';
      notifyListeners();
      return;
    }
    if (!AppUpdateInstaller.supportsInstall) {
      _error = '当前平台不支持应用内 APK 更新';
      notifyListeners();
      return;
    }

    _error = null;
    _downloading = true;
    _installing = false;
    _downloadProgress = 0;
    notifyListeners();

    try {
      final path = await AppUpdateInstaller.downloadApk(
        url: _latestUrl!,
        fileName: _latestAssetName ?? 'duoyi-${latestVersion ?? 'latest'}.apk',
        onProgress: (received, total) {
          if (total != null && total > 0) {
            _downloadProgress = (received / total).clamp(0, 1).toDouble();
            notifyListeners();
          }
        },
      );
      _downloadedFilePath = path;
      _downloading = false;
      _installing = true;
      _downloadProgress = 1;
      notifyListeners();

      final canInstall = await AppUpdateInstaller.canInstallPackages();
      if (!canInstall) {
        _installing = false;
        _error = '需要允许多仪安装未知应用；授权后返回这里再次点击安装';
        notifyListeners();
        await AppUpdateInstaller.openInstallPermissionSettings();
        return;
      }

      await AppUpdateInstaller.installApk(path);
    } catch (e) {
      _error = '更新失败: $e';
    } finally {
      _downloading = false;
      _installing = false;
      notifyListeners();
    }
  }

  Map? _selectBestApkAsset(List assets, {String? targetVersion}) {
    final apkAssets =
        assets.whereType<Map>().where((a) {
          final name = ((a['name'] as String?) ?? '').toLowerCase();
          return name.endsWith('.apk');
        }).toList()..sort(
          (a, b) => _apkScore(
            b,
            targetVersion: targetVersion,
          ).compareTo(_apkScore(a, targetVersion: targetVersion)),
        );

    if (apkAssets.isEmpty) return null;
    return apkAssets.first;
  }

  int _apkScore(Map asset, {String? targetVersion}) {
    final name = ((asset['name'] as String?) ?? '').toLowerCase();
    final version = (targetVersion ?? _latestVersion)?.toLowerCase();
    if (version != null && name == 'duoyi-$version.apk') {
      return 100;
    }
    if (name.contains('universal')) return 90;
    if (!RegExp(r'-(armeabi-v7a|arm64-v8a|x86_64)\.apk$').hasMatch(name)) {
      return 80;
    }
    if (name.contains('arm64-v8a')) return 70;
    if (name.contains('armeabi-v7a')) return 60;
    if (name.contains('x86_64')) return 50;
    return 10;
  }

  String _formatReleaseNotes(String? notes) =>
      formatUpdateNotesForDisplay(notes);

  String _fallbackUpdateNotes(String? version) {
    final target = version?.trim();
    if (target == null || target.isEmpty) {
      return '本次更新会修复已知问题并优化稳定性。';
    }
    return '版本 $target 包含已知问题修复、稳定性优化和体验改进。';
  }
}

class _BackendUpdateCheckException implements Exception {
  final String message;
  final bool allowGitHubFallback;

  const _BackendUpdateCheckException(
    this.message, {
    this.allowGitHubFallback = false,
  });

  @override
  String toString() => message;
}

// ignore: unused_element
void _appUpdateRouteContract(ApiClient client) {
  client.get('/api/mobile/apps/duoyi/update');
}
