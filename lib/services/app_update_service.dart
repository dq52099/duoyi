import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Polls a GitHub repo's latest release and exposes update info.
class AppUpdateService extends ChangeNotifier {
  final String repo; // e.g. "dq52099/duoyi"
  final String currentVersion; // e.g. "1.0.0"

  AppUpdateService({required this.repo, required this.currentVersion});

  String? _latestVersion;
  String? _latestUrl;
  String? _latestNotes;
  bool _checking = false;
  String? _error;

  String? get latestVersion => _latestVersion;
  String? get latestUrl => _latestUrl;
  String? get latestNotes => _latestNotes;
  bool get checking => _checking;
  String? get error => _error;

  bool get hasUpdate {
    if (_latestVersion == null) return false;
    return _compareSemver(
          _normalize(_latestVersion!),
          _normalize(currentVersion),
        ) >
        0;
  }

  Future<void> checkNow() async {
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repo/releases/latest',
      );
      final resp = await http.get(uri, headers: {
        'User-Agent': 'duoyi/1.0',
        'Accept': 'application/vnd.github+json',
      });
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
        _latestUrl = _selectBestApkUrl(assets);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  String _normalize(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split('-').first;

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

  String? _selectBestApkUrl(List assets) {
    final apkAssets = assets
        .whereType<Map>()
        .where((a) {
          final name = ((a['name'] as String?) ?? '').toLowerCase();
          return name.endsWith('.apk');
        })
        .toList()
      ..sort((a, b) => _apkScore(b).compareTo(_apkScore(a)));

    if (apkAssets.isEmpty) return null;
    return apkAssets.first['browser_download_url'] as String?;
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
}
