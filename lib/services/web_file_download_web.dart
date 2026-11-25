import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';

import 'package:web/web.dart' as web;

Future<({bool saved, bool dismissed, String? filePath})> saveFileImpl({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? shareText,
  String? shareSubject,
  Rect? sharePositionOrigin,
  bool Function()? canProceed,
}) async {
  if (canProceed != null && !canProceed()) {
    return (saved: false, dismissed: false, filePath: null);
  }
  final parts = <web.BlobPart>[bytes.toJS].toJS;
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  final parent = web.document.body ?? web.document.documentElement;
  parent?.appendChild(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    unawaited(
      Future<void>.delayed(const Duration(seconds: 2), () {
        web.URL.revokeObjectURL(url);
      }),
    );
  }
  return (saved: true, dismissed: false, filePath: null);
}
