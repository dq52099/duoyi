import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import 'app_update_installer.dart';

/// Polls a GitHub repo's latest release and exposes update info.
class AppUpdateService extends ChangeNotifier {
  final String repo; // e.g. "dq52099/duoyi"
  final String currentVersion; // e.g. "1.0.0"

  AppUpdateService({required this.repo, required this.currentVersion});

  String? _latestVersion;
  String? _latestUrl;
  String? _latestAssetName;
  String? _latestNotes;
  String? _minimumSupportedVersion;
  bool _forceUpdateRequired = false;
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
    return _compareSemver(
          _normalize(_latestVersion!),
          _normalize(currentVersion),
        ) >
        0;
  }

  bool get mustUpdate {
    if (!_forceUpdateRequired) return false;
    if (hasUpdate) return true;
    final minimum = _minimumSupportedVersion;
    if (minimum == null || minimum.trim().isEmpty) return false;
    return _compareSemver(_normalize(currentVersion), _normalize(minimum)) < 0;
  }

  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    _latestUrl = null;
    _latestAssetName = null;
    _latestNotes = null;
    _minimumSupportedVersion = null;
    _forceUpdateRequired = false;
    _downloadedFilePath = null;
    notifyListeners();
    try {
      final configLoaded = await _checkServerConfig();
      if (configLoaded && _latestVersion != null) return;
      final uri = Uri.parse(
        'https://api.github.com/repos/$repo/releases/latest',
      );
      final resp = await http.get(
        uri,
        headers: {
          'User-Agent': 'duoyi/1.0',
          'Accept': 'application/vnd.github+json',
        },
      );
      if (resp.statusCode == 404) {
        _latestVersion = null;
        _error = '尚未发布 Release';
        return;
      }
      if (resp.statusCode != 200) {
        _error = '检查更新失败: ${resp.statusCode}';
        return;
      }
      final data = json.decode(utf8.decode(resp.bodyBytes));
      _latestVersion = (data['tag_name'] as String?)?.trim();
      _latestNotes = (data['body'] as String?)?.trim();
      final assets = data['assets'];
      if (assets is List) {
        final asset = _selectBestApkAsset(assets);
        _latestUrl = asset?['browser_download_url'] as String?;
        _latestAssetName = asset?['name'] as String?;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<bool> _checkServerConfig() async {
    try {
      final base = AppConfig.bakedServerUrl;
      if (base.isEmpty && !kIsWeb) return false;
      final uri = base.isEmpty
          ? Uri.parse('/api/config')
          : Uri.parse('$base/api/config');
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return false;
      final decoded = json.decode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) return false;
      final data = decoded['app_update'] is Map
          ? Map<String, dynamic>.from(decoded['app_update'] as Map)
          : Map<String, dynamic>.from(decoded);
      final latest = _stringValue(data['latest_version']);
      final downloadUrl = _stringValue(data['update_download_url']);
      final notes = _stringValue(data['update_notes']);
      final minimum = _stringValue(data['minimum_supported_version']);
      final hasPolicy =
          latest.isNotEmpty ||
          downloadUrl.isNotEmpty ||
          notes.isNotEmpty ||
          minimum.isNotEmpty ||
          data['force_update_required'] == true;
      if (!hasPolicy) return false;
      _latestVersion = latest.isEmpty ? null : latest;
      _latestUrl = downloadUrl.isEmpty ? null : downloadUrl;
      _latestAssetName = _assetNameFromUrl(downloadUrl);
      _latestNotes = notes.isEmpty ? null : notes;
      _minimumSupportedVersion = minimum.isEmpty ? null : minimum;
      _forceUpdateRequired = data['force_update_required'] == true;
      return true;
    } catch (_) {
      return false;
    }
  }

  String _stringValue(dynamic value) => (value ?? '').toString().trim();

  String? _assetNameFromUrl(String url) {
    if (url.trim().isEmpty) return null;
    final parsed = Uri.tryParse(url);
    final segment = parsed == null || parsed.pathSegments.isEmpty
        ? ''
        : parsed.pathSegments.last.trim();
    return segment.isEmpty ? null : Uri.decodeComponent(segment);
  }

  @visibleForTesting
  String debugFormatReleaseNotesForTest(String? notes) =>
      _formatReleaseNotes(notes);

  @visibleForTesting
  void debugSetUpdatePolicyForTest({
    String? latestVersion,
    String? minimumSupportedVersion,
    bool forceUpdateRequired = false,
  }) {
    _latestVersion = latestVersion;
    _minimumSupportedVersion = minimumSupportedVersion;
    _forceUpdateRequired = forceUpdateRequired;
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

  String _normalize(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split('-').first.split('+').first;

  int _compareSemver(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  Map? _selectBestApkAsset(List assets) {
    final apkAssets = assets.whereType<Map>().where((a) {
      final name = ((a['name'] as String?) ?? '').toLowerCase();
      return name.endsWith('.apk');
    }).toList()..sort((a, b) => _apkScore(b).compareTo(_apkScore(a)));

    if (apkAssets.isEmpty) return null;
    return apkAssets.first;
  }

  int _apkScore(Map asset) {
    final name = ((asset['name'] as String?) ?? '').toLowerCase();
    if (_latestVersion != null &&
        name == 'duoyi-${_latestVersion!.toLowerCase()}.apk') {
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

  String _formatReleaseNotes(String? notes) {
    final raw = notes?.trim();
    if (raw == null || raw.isEmpty) return '';
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]+\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .split('\n')
        .where((line) {
          final normalized = line
              .trim()
              .replaceFirst(RegExp(r'^[*_\\s]+'), '')
              .toLowerCase();
          return !normalized.startsWith('full changelog');
        })
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
