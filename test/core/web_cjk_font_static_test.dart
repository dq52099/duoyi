import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

int _u16(ByteData bytes, int offset) => bytes.getUint16(offset, Endian.big);

int _u32(ByteData bytes, int offset) => bytes.getUint32(offset, Endian.big);

int _printableAsciiCoverage(Uint8List fontBytes) {
  final bytes = ByteData.sublistView(fontBytes);
  final tableCount = _u16(bytes, 4);
  var cmapOffset = -1;

  for (var index = 0; index < tableCount; index++) {
    final recordOffset = 12 + index * 16;
    final tag = String.fromCharCodes(
      fontBytes.sublist(recordOffset, recordOffset + 4),
    );
    if (tag == 'cmap') {
      cmapOffset = _u32(bytes, recordOffset + 8);
      break;
    }
  }
  if (cmapOffset < 0) {
    throw const FormatException('Font has no cmap table');
  }

  final encodingCount = _u16(bytes, cmapOffset + 2);
  var format4Offset = -1;
  for (var index = 0; index < encodingCount; index++) {
    final recordOffset = cmapOffset + 4 + index * 8;
    final platformId = _u16(bytes, recordOffset);
    final encodingId = _u16(bytes, recordOffset + 2);
    final subtableOffset = cmapOffset + _u32(bytes, recordOffset + 4);
    final isUnicodeEncoding =
        platformId == 0 || (platformId == 3 && encodingId == 1);
    if (isUnicodeEncoding && _u16(bytes, subtableOffset) == 4) {
      format4Offset = subtableOffset;
      break;
    }
  }
  if (format4Offset < 0) {
    throw const FormatException('Font has no Unicode cmap format 4 table');
  }

  final segmentCount = _u16(bytes, format4Offset + 6) ~/ 2;
  final endCodeOffset = format4Offset + 14;
  final startCodeOffset = endCodeOffset + segmentCount * 2 + 2;
  final deltaOffset = startCodeOffset + segmentCount * 2;
  final rangeOffset = deltaOffset + segmentCount * 2;
  var covered = 0;

  for (var codePoint = 0x20; codePoint <= 0x7e; codePoint++) {
    var glyphId = 0;
    for (var segment = 0; segment < segmentCount; segment++) {
      final start = _u16(bytes, startCodeOffset + segment * 2);
      final end = _u16(bytes, endCodeOffset + segment * 2);
      if (codePoint < start || codePoint > end) continue;

      final delta = _u16(bytes, deltaOffset + segment * 2);
      final rangeWordOffset = rangeOffset + segment * 2;
      final glyphRangeOffset = _u16(bytes, rangeWordOffset);
      if (glyphRangeOffset == 0) {
        glyphId = (codePoint + delta) & 0xffff;
      } else {
        glyphId = _u16(
          bytes,
          rangeWordOffset + glyphRangeOffset + 2 * (codePoint - start),
        );
        if (glyphId != 0) glyphId = (glyphId + delta) & 0xffff;
      }
      break;
    }
    if (glyphId != 0) covered++;
  }

  return covered;
}

void main() {
  test('web CJK fallback font is registered and used by app themes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final brand = File('lib/core/app_brand.dart').readAsStringSync();

    expect(
      pubspec,
      contains(
        'family: DroidSansFallbackFull\n'
        '      fonts:\n'
        '        - asset: assets/fonts/DroidSansFallbackFull.ttf',
      ),
    );
    expect(brand, contains("const String _cnFontFamily = 'sans-serif';"));
    expect(brand, contains('fontFamilyFallback: _cnFontFallback'));
    expect(brand, contains("'DroidSansFallbackFull'"));
    expect(File('assets/fonts/DroidSansFallbackFull.ttf').existsSync(), isTrue);
  });

  test('web Latin fallback is bundled ahead of the CJK font', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final brand = File('lib/core/app_brand.dart').readAsStringSync();

    expect(
      pubspec,
      contains(
        'family: DejaVu Sans\n'
        '      fonts:\n'
        '        - asset: assets/fonts/DejaVuSans.ttf',
      ),
    );
    expect(brand, contains("const String _cnFontFamily = 'sans-serif';"));

    final latinFamilyIndex = brand.indexOf("'DejaVu Sans'");
    final cjkFamilyIndex = brand.indexOf("'DroidSansFallbackFull'");
    expect(latinFamilyIndex, greaterThanOrEqualTo(0));
    expect(cjkFamilyIndex, greaterThan(latinFamilyIndex));
    expect(
      RegExp(r'fontFamilyFallback:\s*_cnFontFallback').allMatches(brand).length,
      greaterThanOrEqualTo(6),
    );
  });

  test('bundled Latin font covers all printable ASCII glyphs', () {
    final font = File('assets/fonts/DejaVuSans.ttf').readAsBytesSync();
    expect(font.length, 757076);
    expect(
      sha256.convert(font).toString(),
      '690243adfefe0ce154b547db6205794bd30ac4277275179517a90994f4980648',
    );
    expect(_printableAsciiCoverage(Uint8List.fromList(font)), 95);
  });

  test(
    'bundled Latin font notice retains Debian and embedded license terms',
    () {
      final noticeFile = File('assets/fonts/DejaVuSans-LICENSE.txt');
      expect(noticeFile.existsSync(), isTrue);
      final noticeBytes = noticeFile.readAsBytesSync();
      final notice = noticeFile.readAsStringSync();

      expect(
        sha256.convert(noticeBytes).toString(),
        '9017a163db9ef1168811dca991bca1293cbdca2c6c78bfa4567750e6bcf2d733',
      );
      for (final phrase in [
        'Upstream-Name: DejaVu fonts',
        'License: bitstream-vera',
        'Files: debian/*',
        'License: GPL-2+',
        'Bitstream Vera Fonts Copyright',
        'Arev Fonts Copyright',
        'Fonts are (c) Bitstream (see below).',
        'Glyphs imported from Arev fonts are (c) Tavmjung Bah (see below)',
      ]) {
        expect(notice, contains(phrase));
      }
    },
  );
}
