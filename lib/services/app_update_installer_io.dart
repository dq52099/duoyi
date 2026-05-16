import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef AppUpdateProgress = void Function(int receivedBytes, int? totalBytes);

class AppUpdateInstaller {
  static const _channel = MethodChannel('duoyi/update');

  static bool get supportsInstall {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static Future<String> downloadApk({
    required String url,
    required String fileName,
    required AppUpdateProgress onProgress,
  }) async {
    final dir = Directory('${Directory.systemTemp.path}/duoyi_updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safeName');
    final client = http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'duoyi/update'
        ..headers['Accept'] = 'application/vnd.android.package-archive,*/*';
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '下载失败: HTTP ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return file.path;
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  static Future<bool> canInstallPackages() async {
    if (!supportsInstall) return false;
    return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
  }

  static Future<void> openInstallPermissionSettings() async {
    if (!supportsInstall) return;
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<void> installApk(String path) async {
    if (!supportsInstall) {
      throw UnsupportedError('当前平台不支持应用内安装 APK');
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }
}
