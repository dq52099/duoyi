import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

typedef _PngHeader = ({int width, int height, int colorType});

_PngHeader _parsePngHeader(Uint8List bytes, String label) {
  expect(
    bytes.length,
    greaterThanOrEqualTo(33),
    reason: 'Truncated PNG: $label',
  );
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    expect(
      bytes[i],
      signature[i],
      reason: 'Invalid PNG signature: $label',
    );
  }
  expect(
    String.fromCharCodes(bytes.sublist(12, 16)),
    'IHDR',
    reason: 'Missing IHDR chunk: $label',
  );
  final data = ByteData.sublistView(bytes);
  return (
    width: data.getUint32(16, Endian.big),
    height: data.getUint32(20, Endian.big),
    colorType: bytes[25],
  );
}

_PngHeader _readPngHeader(File file) {
  expect(file.existsSync(), isTrue, reason: 'Missing PNG: ${file.path}');
  return _parsePngHeader(
    Uint8List.fromList(file.readAsBytesSync()),
    file.path,
  );
}

String _sha256Hex(File file) => sha256.convert(file.readAsBytesSync()).toString();

void main() {
  const legacyDisallowedHashes = <String>{
    // Legacy default Flutter web icons
    '7ab2525f4b86b65d3e4c70358a17e5a1aaf6f437f99cbcc046dad73d59bb9015',
    '3dce99077602f70421c1c6b2a240bc9b83d64d86681d45f2154143310c980be3',
    'baccb205ae45f0b421be1657259b4943ac40c95094ab877f3bcbe12cd544dcbe',
    'd2c842e22a9f4ec9d996b23373a905c88d9a203b220c5c151885ad621f974b5c',
    '6aee06cdcab6b2aef74b1734c4778f4421d2da100b0ff9e52b21b55240202929',
    // Legacy hourglass brand assets
    'f278d1e81def73ee3e96de28ad6df6bae633bb309b0446e99bdf22332d8a486b',
    '1e44f0804bea83bd7db0cfd0c4bb138eaf527d39a907d8a2c4b225870443fa8a',
    '1025771b9d7db18dfa60781cc6baa1e73916b365d3f259c09630b4f184c7370f',
    'e04a7a50d90469302852baef80bcea559b9bd1ce561621bda8fbc280157361b5',
  };

  test('canonical APK icon source and synced web/linux/logo assets match specs', () {
    final canonical = File('assets/logo/duoyi_logo_redesign_1024.png');
    final canonicalHeader = _readPngHeader(canonical);
    expect(canonicalHeader.width, 1024);
    expect(canonicalHeader.height, 1024);

    // colorType: 2 = RGB (opaque), 6 = RGBA (transparent outer corners)
    const expectedPngs = <String, ({int size, int colorType})>{
      'assets/logo/duoyi_logo_1024.png': (size: 1024, colorType: 6),
      'assets/logo/duoyi_logo_512.png': (size: 512, colorType: 6),
      'assets/logo/duoyi_logo_192.png': (size: 192, colorType: 6),
      'web/favicon.png': (size: 32, colorType: 6),
      'web/icons/Icon-192.png': (size: 192, colorType: 6),
      'web/icons/Icon-512.png': (size: 512, colorType: 6),
      'web/icons/Icon-maskable-192.png': (size: 192, colorType: 2),
      'web/icons/Icon-maskable-512.png': (size: 512, colorType: 2),
      'web/icons/apple-touch-icon.png': (size: 180, colorType: 2),
      'linux/duoyi.png': (size: 512, colorType: 6),
    };

    for (final entry in expectedPngs.entries) {
      final file = File(entry.key);
      final header = _readPngHeader(file);
      expect(header.width, entry.value.size, reason: entry.key);
      expect(header.height, entry.value.size, reason: entry.key);
      expect(header.colorType, entry.value.colorType, reason: entry.key);
      expect(
        legacyDisallowedHashes.contains(_sha256Hex(file)),
        isFalse,
        reason: '${entry.key} still uses legacy icon hash',
      );
    }

    expect(
      _sha256Hex(File('web/icons/Icon-192.png')),
      _sha256Hex(File('assets/logo/duoyi_logo_192.png')),
    );
    expect(
      _sha256Hex(File('web/icons/Icon-512.png')),
      _sha256Hex(File('assets/logo/duoyi_logo_512.png')),
    );
    expect(
      _sha256Hex(File('linux/duoyi.png')),
      _sha256Hex(File('assets/logo/duoyi_logo_512.png')),
    );

    final svgFile = File('assets/logo/duoyi_logo.svg');
    expect(svgFile.existsSync(), isTrue);
    expect(legacyDisallowedHashes.contains(_sha256Hex(svgFile)), isFalse);
    final svgText = svgFile.readAsStringSync();
    expect(svgText, isNot(contains('sandTop')));
    expect(svgText, isNot(contains('sandBot')));
    expect(svgText, contains('ribbonGrad'));

    final icoFile = File('web/favicon.ico');
    expect(icoFile.existsSync(), isTrue);
    expect(legacyDisallowedHashes.contains(_sha256Hex(icoFile)), isFalse);
    final icoBytes = Uint8List.fromList(icoFile.readAsBytesSync());
    expect(icoBytes.length, greaterThanOrEqualTo(6 + 16 * 3));
    final icoData = ByteData.sublistView(icoBytes);
    expect(icoData.getUint16(0, Endian.little), 0);
    expect(icoData.getUint16(2, Endian.little), 1);
    final icoCount = icoData.getUint16(4, Endian.little);
    expect(icoCount, 3);
    final icoSizes = <int>{};
    for (var i = 0; i < icoCount; i++) {
      final entryOffset = 6 + i * 16;
      final width = icoBytes[entryOffset] == 0 ? 256 : icoBytes[entryOffset];
      final height =
          icoBytes[entryOffset + 1] == 0 ? 256 : icoBytes[entryOffset + 1];
      final bitsPerPixel = icoData.getUint16(entryOffset + 6, Endian.little);
      final bytesInRes = icoData.getUint32(entryOffset + 8, Endian.little);
      final imageOffset = icoData.getUint32(entryOffset + 12, Endian.little);
      expect(width, height, reason: 'ICO entry $i must be square');
      expect(bitsPerPixel, 32, reason: 'ICO entry $i must be 32bpp RGBA');
      expect(imageOffset + bytesInRes, lessThanOrEqualTo(icoBytes.length));
      final pngHeader = _parsePngHeader(
        Uint8List.sublistView(icoBytes, imageOffset, imageOffset + bytesInRes),
        'web/favicon.ico[$width]',
      );
      expect(pngHeader.width, width);
      expect(pngHeader.height, height);
      expect(pngHeader.colorType, 6);
      icoSizes.add(width);
    }
    expect(icoSizes, equals(<int>{16, 32, 48}));
  });

  test('iOS AppIcon.appiconset entries match Contents.json sizes without alpha', () {
    const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final contentsFile = File('$dir/Contents.json');
    expect(contentsFile.existsSync(), isTrue);
    final decoded = jsonDecode(contentsFile.readAsStringSync()) as Map<String, dynamic>;
    final images = (decoded['images'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(images, isNotEmpty);

    for (final item in images) {
      final filename = item['filename'] as String;
      final sizePt = double.parse((item['size'] as String).split('x').first);
      final scale = int.parse((item['scale'] as String).replaceAll('x', ''));
      final expectedPx = (sizePt * scale).round();
      final header = _readPngHeader(File('$dir/$filename'));
      expect(header.width, expectedPx, reason: filename);
      expect(header.height, expectedPx, reason: filename);
      expect(
        header.colorType,
        2,
        reason: '$filename must be opaque RGB (no alpha channel for App Store)',
      );
    }
  });
}
