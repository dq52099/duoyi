import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final dir = await getTemporaryDirectory();
  if (canProceed != null && !canProceed()) {
    return (saved: false, dismissed: false, filePath: null);
  }
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  if (canProceed != null && !canProceed()) {
    return (saved: false, dismissed: false, filePath: null);
  }
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: fileName)],
      text: shareText,
      subject: shareSubject,
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
  if (result.status == ShareResultStatus.unavailable) {
    throw StateError('Share sheet unavailable on this platform');
  }
  final dismissed = result.status == ShareResultStatus.dismissed;
  return (saved: !dismissed, dismissed: dismissed, filePath: file.path);
}
