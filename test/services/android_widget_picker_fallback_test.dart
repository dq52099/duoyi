import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _resources = {
  'widget_preview',
  'widget_todo_preview',
  'widget_focus_habit_preview',
  'widget_habit_preview',
  'widget_calendar_preview',
  'widget_schedule_preview',
  'widget_goal_preview',
  'widget_course_preview',
  'widget_note_preview',
  'widget_anniversary_preview',
  'widget_diary_preview',
};

void main() {
  final manifest =
      jsonDecode(
            File(
              'scripts/widget_picker_preview_manifest.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final assets = (manifest['assets'] as List).cast<Map<String, dynamic>>();

  test(
    'fallback previews cover every module with a localized resource pair',
    () {
      expect(manifest['size'], [720, 480]);
      expect(manifest['kind'], 'example-data illustration');
      expect(manifest['palette'], 'defaultBrand|plain_card');
      expect(assets, hasLength(_resources.length * 2));
      for (final locale in ['zh', 'en']) {
        final localized = assets.where((asset) => asset['locale'] == locale);
        expect(localized.map((asset) => asset['resource']).toSet(), _resources);
        expect(localized, hasLength(_resources.length));
        final folder = locale == 'zh' ? 'drawable-nodpi' : 'drawable-en-nodpi';
        for (final asset in localized) {
          expect(
            asset['path'],
            'android/app/src/main/res/$folder/${asset['resource']}.png',
          );
          expect(asset['title'], isNotEmpty);
          if (locale == 'en') {
            expect(
              RegExp(
                r'[\u3400-\u9fff]',
              ).hasMatch('${asset['title']} ${asset['rows']}'),
              isFalse,
              reason: '${asset['resource']} English example copy',
            );
          }
          final partner = assets.singleWhere(
            (other) =>
                other['resource'] == asset['resource'] &&
                other['locale'] != locale,
          );
          expect(asset['sha256'], isNot(partner['sha256']));
        }
      }
    },
  );

  test('generation inputs and all output bytes match the manifest', () {
    final sources = {
      'generator_sha256': File('scripts/generate_widget_picker_previews.py'),
      'palette_sha256': File(
        'android/app/src/main/res/raw/widget_surface_palettes.json',
      ),
    };
    for (final entry in sources.entries) {
      expect(
        sha256.convert(entry.value.readAsBytesSync()).toString(),
        manifest[entry.key],
        reason: entry.value.path,
      );
    }
    final fonts = manifest['fonts'] as Map<String, dynamic>;
    expect(
      sha256
          .convert(File('assets/fonts/DejaVuSans.ttf').readAsBytesSync())
          .toString(),
      fonts['latin'],
    );
    expect(
      sha256
          .convert(
            File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
          )
          .toString(),
      fonts['cjk'],
    );
    for (final asset in assets) {
      final bytes = File(asset['path'] as String).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), asset['sha256']);
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(bytes);
      expect(header.getUint32(16), 720);
      expect(header.getUint32(20), 480);
    }
  });

  testWidgets(
    'decoded previews have transparent corners and shallow surfaces',
    (tester) async {
      await tester.runAsync(() async {
        for (final asset in assets) {
          final codec = await ui.instantiateImageCodec(
            File(asset['path'] as String).readAsBytesSync(),
          );
          final frame = await codec.getNextFrame();
          final pixels = await frame.image.toByteData();
          frame.image.dispose();
          codec.dispose();
          expect(pixels, isNotNull, reason: asset['path'] as String);
          final rgba = pixels!.buffer.asUint8List();
          expect(rgba[3], 0, reason: 'Transparent outer corner');
          final surfacePixel = (115 * 720 + 400) * 4;
          expect(
            rgba.sublist(surfacePixel, surfacePixel + 4),
            [246, 247, 249, 255],
            reason: '${asset['path']} follows the default shallow surface',
          );
          var darkPixels = 0;
          for (var i = 0; i < rgba.length; i += 4) {
            if (rgba[i + 3] == 255 &&
                rgba[i] < 80 &&
                rgba[i + 1] < 80 &&
                rgba[i + 2] < 80) {
              darkPixels++;
            }
          }
          expect(darkPixels, greaterThan(500), reason: asset['path'] as String);
        }
      });
    },
  );
}
