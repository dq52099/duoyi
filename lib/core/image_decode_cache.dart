import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Bounded LRU cache for decoded base64 image payloads so scrolling lists
/// do not repeatedly invoke synchronous `base64Decode` inside `build()`.
class ImageDecodeCache {
  ImageDecodeCache._();

  static const int maxEntries = 32;
  static const int maxTotalBytes = 8 * 1024 * 1024;

  static final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();
  static int _totalBytes = 0;

  @visibleForTesting
  static int get entryCount => _cache.length;

  @visibleForTesting
  static int get totalBytes => _totalBytes;

  @visibleForTesting
  static void clear() {
    _cache.clear();
    _totalBytes = 0;
  }

  /// Decodes a `data:image/...;base64,...` URI or raw base64 image string,
  /// returning cached bytes when previously decoded within LRU bounds.
  static Uint8List? decodeBase64Image(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final existing = _cache.remove(trimmed);
    if (existing != null) {
      _cache[trimmed] = existing;
      return existing;
    }

    String payload = trimmed;
    if (trimmed.startsWith('data:')) {
      final comma = trimmed.indexOf(',');
      if (comma <= 0 || comma >= trimmed.length - 1) return null;
      final header = trimmed.substring(0, comma).toLowerCase();
      if (!header.contains(';base64')) return null;
      payload = trimmed.substring(comma + 1).trim();
      if (payload.isEmpty) return null;
    }

    final Uint8List bytes;
    try {
      bytes = base64Decode(payload);
    } catch (_) {
      return null;
    }

    final size = bytes.lengthInBytes;
    if (size <= maxTotalBytes) {
      _cache[trimmed] = bytes;
      _totalBytes += size;
      while (_cache.length > maxEntries || _totalBytes > maxTotalBytes) {
        final oldestKey = _cache.keys.first;
        final removed = _cache.remove(oldestKey);
        if (removed != null) {
          _totalBytes -= removed.lengthInBytes;
        }
      }
    }
    return bytes;
  }

  /// Computes a DPR-bounded decode pixel dimension for `Image.memory` /
  /// `Image.file` / `Image.asset` to avoid decoding full-resolution bitmaps
  /// for compact avatars and thumbnails.
  static int? boundedCachePixels(
    double logicalSize,
    double devicePixelRatio, {
    int maxPixels = 2048,
  }) {
    if (!logicalSize.isFinite ||
        logicalSize <= 0 ||
        !devicePixelRatio.isFinite ||
        devicePixelRatio <= 0) {
      return null;
    }
    final pixels = (logicalSize * devicePixelRatio).ceil();
    return pixels.clamp(1, maxPixels).toInt();
  }
}

Uint8List? decodeBase64Image(String raw) =>
    ImageDecodeCache.decodeBase64Image(raw);
