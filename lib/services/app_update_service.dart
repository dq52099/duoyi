import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Polls a GitHub repo's latest release and exposes update info.
/// Mirrors RE0's lib/core/app_update_service.dart pattern, simplified.
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
    return _compareSemver(_normalize(_latestVersion!), _normalize(currentVersion)) > 0;
  }

  Future<void> checkNow() async {
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        req.headers.set('User-Agent', 'duoyi/1.0');
        req.headers.set('Accept', 'application/vnd.github+json');
        final resp = await req.close();
        final raw = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 404) {
          // No release yet
          _latestVersion = null;
          _error = '尚未发布 Release';
          return;
        }
        if (resp.statusCode != 200) {
          _error = '检查更新失败: ${resp.statusCode}';
          return;
        }
        final data = json.decode(raw);
        _latestVersion = (data['tag_name'] as String?)?.trim();
        _latestNotes = (data['body'] as String?)?.trim();
        // Find first APK asset
        final assets = data['assets'];
        if (assets is List) {
          for (final a in assets) {
            final name = (a['name'] as String?) ?? '';
            if (name.toLowerCase().endsWith('.apk')) {
              _latestUrl = a['browser_download_url'] as String?;
              break;
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  String _normalize(String v) => v.replaceFirst(RegExp(r'^v'), '').split('-').first;

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
}
