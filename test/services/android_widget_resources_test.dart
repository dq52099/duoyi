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
      expect(preview.existsSync(), isTrue);
      expect(preview.lengthSync(), greaterThan(1024));
      expect(_pngSize(preview), const _PngSize(720, 480));
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
      expect(preview.existsSync(), isTrue);
      expect(preview.lengthSync(), greaterThan(1024));
      expect(_pngSize(preview), const _PngSize(720, 480));
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
