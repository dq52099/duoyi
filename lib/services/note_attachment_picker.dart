import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../models/note.dart';
import '../core/i18n.dart';

class NoteAttachmentPicker {
  NoteAttachmentPicker._();

  static const int maxInlineWebImageBytes = 1572864;

  static const MethodChannel _channel = MethodChannel(
    'duoyi/note_attachment_picker',
  );

  static Future<NoteAttachment?> pickFile() async {
    if (kIsWeb) return _pickWebFile();
    if (!_isAndroid) return _pickPortableFile();
    return _pickAndroidFile();
  }

  static Future<NoteAttachment?> _pickAndroidFile() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickFile',
      );
      if (result == null) return null;
      final uri = result['uri']?.toString() ?? '';
      if (uri.isEmpty) return null;
      final name = result['name']?.toString();
      return NoteAttachment(
        name: name == null || name.trim().isEmpty
            ? I18n.tr('note.attachment.default_name')
            : name.trim(),
        uri: uri,
        mimeType: result['mimeType']?.toString() ?? '',
      );
    } catch (e, st) {
      debugPrint('[NoteAttachmentPicker] pickFile failed: $e\n$st');
      return null;
    }
  }

  static Future<NoteAttachment?> _pickPortableFile() async {
    if (kIsWeb) return null;
    try {
      final file = await openFile();
      if (file == null) return null;
      final uri = file.path.trim();
      if (uri.isEmpty) return null;
      final name = file.name.trim().isEmpty
          ? I18n.tr('note.attachment.default_name')
          : file.name.trim();
      return NoteAttachment(
        name: name,
        uri: uri,
        mimeType: file.mimeType ?? '',
      );
    } catch (e, st) {
      debugPrint('[NoteAttachmentPicker] portable pickFile failed: $e\n$st');
      return null;
    }
  }

  static Future<NoteAttachment?> _pickWebFile() async {
    try {
      final file = await openFile();
      if (file == null) return null;
      return fromWebXFile(file);
    } catch (e, st) {
      debugPrint('[NoteAttachmentPicker] web pickFile failed: $e\n$st');
      return null;
    }
  }

  @visibleForTesting
  static Future<NoteAttachment?> fromWebXFile(XFile file) async {
    final trimmedName = file.name.trim();
    final name = trimmedName.isEmpty
        ? I18n.tr('note.attachment.default_name')
        : trimmedName;
    final rawMime = (file.mimeType ?? '').trim();
    final inferredFromName = _inferMimeType(name);
    final mime = rawMime.isNotEmpty
        ? rawMime
        : inferredFromName.isNotEmpty
        ? inferredFromName
        : _inferMimeType(file.path);
    var uri = file.path.trim();
    if (_isImageMimeOrName(mime, name)) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty && bytes.length <= maxInlineWebImageBytes) {
          final safeMime = mime.startsWith('image/') ? mime : 'image/png';
          uri = 'data:$safeMime;base64,${base64Encode(bytes)}';
        }
      } catch (e, st) {
        debugPrint('[NoteAttachmentPicker] web readAsBytes failed: $e\n$st');
      }
    }
    if (uri.isEmpty) return null;
    return NoteAttachment(name: name, uri: uri, mimeType: mime);
  }

  static String _inferMimeType(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'text/markdown';
    }
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.ics')) return 'text/calendar';
    if (lower.endsWith('.txt')) return 'text/plain';
    return '';
  }

  static bool _isImageMimeOrName(String mime, String name) {
    if (mime.toLowerCase().startsWith('image/')) return true;
    final lower = name.trim().toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  static bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}
