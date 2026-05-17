import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android 小组件资源', () {
    test('主小组件声明底部导航和 PNG 预览', () {
      final provider = File(
        'android/app/src/main/res/xml/duoyi_widget_info.xml',
      ).readAsStringSync();
      final layout = File(
        'android/app/src/main/res/layout/duoyi_widget.xml',
      ).readAsStringSync();
      final preview = File(
        'android/app/src/main/res/drawable-nodpi/widget_preview.png',
      );

      expect(
        provider,
        contains('android:previewImage="@drawable/widget_preview"'),
      );
      expect(
        provider,
        contains('android:previewLayout="@layout/duoyi_widget"'),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:resource="@drawable/widget_preview"'),
      );
      expect(preview.existsSync(), isTrue);
      expect(preview.lengthSync(), greaterThan(1024));
      expect(_pngSize(preview), const _PngSize(720, 480));
      expect(_pngContainsTextLikeContent(preview), isTrue);
      expect(layout, contains('@+id/widget_bottom_nav'));
      expect(layout, contains('@+id/widget_nav_todo'));
      expect(layout, contains('@+id/widget_nav_habit'));
      expect(layout, contains('@+id/widget_nav_calendar'));
      expect(layout, contains('@+id/widget_nav_focus'));
      expect(
        File(
          'android/app/src/main/res/drawable/widget_preview.xml',
        ).existsSync(),
        isFalse,
      );
    });

    test('今日待办小组件声明底部导航和 PNG 预览', () {
      final provider = File(
        'android/app/src/main/res/xml/duoyi_todo_widget_info.xml',
      ).readAsStringSync();
      final layout = File(
        'android/app/src/main/res/layout/duoyi_todo_widget.xml',
      ).readAsStringSync();
      final preview = File(
        'android/app/src/main/res/drawable-nodpi/widget_todo_preview.png',
      );

      expect(
        provider,
        contains('android:previewImage="@drawable/widget_todo_preview"'),
      );
      expect(
        provider,
        contains('android:previewLayout="@layout/duoyi_todo_widget"'),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:resource="@drawable/widget_todo_preview"'),
      );
      expect(preview.existsSync(), isTrue);
      expect(preview.lengthSync(), greaterThan(1024));
      expect(_pngSize(preview), const _PngSize(720, 480));
      expect(_pngContainsTextLikeContent(preview), isTrue);
      expect(layout, contains('@+id/widget_todo_bottom_nav'));
      expect(layout, contains('@+id/widget_todo_nav_todo'));
      expect(layout, contains('@+id/widget_todo_nav_habit'));
      expect(layout, contains('@+id/widget_todo_nav_calendar'));
      expect(layout, contains('@+id/widget_todo_nav_focus'));
      expect(
        File(
          'android/app/src/main/res/drawable/widget_todo_preview.xml',
        ).existsSync(),
        isFalse,
      );
    });

    test('底部导航每个入口都绑定到对应深链', () {
      final mainProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetProvider.kt',
      ).readAsStringSync();
      final todoProvider = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiTodoWidgetProvider.kt',
      ).readAsStringSync();

      for (final source in [mainProvider, todoProvider]) {
        expect(source, contains('Uri.parse("duoyi://tab/todo")'));
        expect(source, contains('Uri.parse("duoyi://tab/habit")'));
        expect(source, contains('Uri.parse("duoyi://tab/calendar")'));
        expect(source, contains('Uri.parse("duoyi://tab/focus")'));
      }
      expect(mainProvider, contains('R.id.widget_nav_todo'));
      expect(mainProvider, contains('R.id.widget_nav_habit'));
      expect(mainProvider, contains('R.id.widget_nav_calendar'));
      expect(mainProvider, contains('R.id.widget_nav_focus'));
      expect(todoProvider, contains('R.id.widget_todo_nav_todo'));
      expect(todoProvider, contains('R.id.widget_todo_nav_habit'));
      expect(todoProvider, contains('R.id.widget_todo_nav_calendar'));
      expect(todoProvider, contains('R.id.widget_todo_nav_focus'));
    });
  });
}

bool _pngContainsTextLikeContent(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  // The real preview is a rendered screenshot-style PNG with many colors and
  // dark text pixels. A blank/abstract placeholder typically lacks this range.
  final unique = <int>{};
  var darkPixels = 0;
  for (var i = 0; i < bytes.length - 2; i += 97) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    unique.add((r << 16) | (g << 8) | b);
    if (r < 80 && g < 80 && b < 80) darkPixels++;
  }
  return width == 720 && height == 480 && unique.length > 24 && darkPixels > 5;
}

_PngSize _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  expect(bytes.take(signature.length).toList(), signature);
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return _PngSize(data.getUint32(16), data.getUint32(20));
}

class _PngSize {
  final int width;
  final int height;

  const _PngSize(this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is _PngSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}
