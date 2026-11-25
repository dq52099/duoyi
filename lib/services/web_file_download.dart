import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'web_file_download_stub.dart'
    if (dart.library.js_interop) 'web_file_download_web.dart'
    if (dart.library.html) 'web_file_download_web.dart'
    as impl;

@immutable
class WebFileDownloadRequest {
  const WebFileDownloadRequest({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.shareText,
    this.shareSubject,
    this.sharePositionOrigin,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String? shareText;
  final String? shareSubject;
  final Rect? sharePositionOrigin;
}

@immutable
class WebFileDownloadResult {
  const WebFileDownloadResult({
    required this.saved,
    required this.fileName,
    this.dismissed = false,
    this.filePath,
  });

  final bool saved;
  final bool dismissed;
  final String fileName;
  final String? filePath;
}

class WebFileDownload {
  WebFileDownload._();

  @visibleForTesting
  static Future<WebFileDownloadResult> Function(WebFileDownloadRequest request)?
  debugSaveHandler;

  static Future<WebFileDownloadResult> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    String? shareText,
    String? shareSubject,
    Rect? sharePositionOrigin,
    bool Function()? canProceed,
  }) async {
    final safeName = sanitizeFileName(fileName);
    final resolvedMime = (mimeType != null && mimeType.trim().isNotEmpty)
        ? mimeType.trim()
        : inferMimeType(safeName);
    if (canProceed != null && !canProceed()) {
      return WebFileDownloadResult(saved: false, fileName: safeName);
    }
    final handler = debugSaveHandler;
    if (handler != null) {
      return handler(
        WebFileDownloadRequest(
          bytes: bytes,
          fileName: safeName,
          mimeType: resolvedMime,
          shareText: shareText,
          shareSubject: shareSubject,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    }
    final result = await impl.saveFileImpl(
      bytes: bytes,
      fileName: safeName,
      mimeType: resolvedMime,
      shareText: shareText,
      shareSubject: shareSubject,
      sharePositionOrigin: sharePositionOrigin,
      canProceed: canProceed,
    );
    return WebFileDownloadResult(
      saved: result.saved,
      dismissed: result.dismissed,
      fileName: safeName,
      filePath: result.filePath,
    );
  }

  static Future<WebFileDownloadResult> saveText({
    required String content,
    required String fileName,
    String? mimeType,
    String? shareText,
    String? shareSubject,
    Rect? sharePositionOrigin,
    bool Function()? canProceed,
  }) {
    final safeName = sanitizeFileName(fileName);
    final bytes = Uint8List.fromList(utf8.encode(content));
    final resolvedMime = (mimeType != null && mimeType.trim().isNotEmpty)
        ? mimeType.trim()
        : inferMimeType(safeName);
    return saveBytes(
      bytes: bytes,
      fileName: safeName,
      mimeType: resolvedMime,
      shareText: shareText,
      shareSubject: shareSubject,
      sharePositionOrigin: sharePositionOrigin,
      canProceed: canProceed,
    );
  }

  static String inferMimeType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.json')) return 'application/json;charset=utf-8';
    if (lower.endsWith('.csv')) return 'text/csv;charset=utf-8';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown;charset=utf-8';
    }
    if (lower.endsWith('.ics')) return 'text/calendar;charset=utf-8';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain;charset=utf-8';
    return 'application/octet-stream';
  }

  static String sanitizeFileName(
    String raw, {
    String fallback = 'duoyi_export.txt',
  }) {
    var cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    if (cleaned.isEmpty) return fallback;
    if (cleaned.length > 120) {
      final dot = cleaned.lastIndexOf('.');
      if (dot > 0 && cleaned.length - dot <= 16) {
        final ext = cleaned.substring(dot);
        final stem = cleaned.substring(0, 120 - ext.length);
        cleaned = '$stem$ext';
      } else {
        cleaned = cleaned.substring(0, 120);
      }
    }
    return cleaned;
  }
}
