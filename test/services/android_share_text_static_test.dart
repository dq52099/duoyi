import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android 系统分享文本可导入为待办或笔记', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final deepLinkService = File(
      'lib/services/deep_link_service.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(manifest, contains('android.intent.action.SEND'));
    expect(manifest, contains('android.intent.category.DEFAULT'));
    expect(manifest, contains('android:mimeType="text/plain"'));

    expect(mainActivity, contains('pendingInitialSharedText'));
    expect(
      mainActivity,
      contains('pendingInitialSharedText = sharedTextFrom(intent)'),
    );
    expect(mainActivity, contains('sharedTextFrom(intent)'));
    expect(mainActivity, contains('Intent.ACTION_SEND'));
    expect(mainActivity, contains('Intent.EXTRA_TEXT'));
    expect(mainActivity, contains('"takeInitialSharedText"'));
    expect(
      mainActivity,
      contains('channel.invokeMethod("onSharedText", sharedText)'),
    );
    expect(mainActivity, contains('!type.startsWith("text/")'));

    expect(
      deepLinkService,
      contains('static void Function(String text)? onSharedText'),
    );
    expect(deepLinkService, contains("call.method != 'onSharedText'"));
    expect(deepLinkService, contains("call.method == 'onSharedText'"));
    expect(deepLinkService, contains("onSharedText?.call(text)"));
    expect(deepLinkService, contains('takeInitialSharedText'));
    expect(deepLinkService, contains("'takeInitialSharedText'"));

    expect(main, contains('DeepLinkService.onSharedText = handleSharedText'));
    expect(main, contains('DeepLinkService.takeInitialSharedText()'));
    expect(main, contains('_showSharedTextImportSheet'));
    expect(main, contains('导入分享文本'));
    expect(main, contains('创建待办'));
    expect(main, contains('保存笔记'));
    expect(main, contains('SmartTodoDraftBuilder.fromText(text)'));
    expect(main, contains('latestContext.read<TodoProvider>().addTodo'));
    expect(main, contains('NoteItem('));
    expect(
      main,
      contains('latestContext.read<NoteProvider>().addOrUpdateNote'),
    );
    expect(
      main,
      contains(
        'MaterialPageRoute(\n        builder: (_) => const BrandRouteSurface(child: NoteScreen()),',
      ),
    );
    expect(
      main,
      contains('mainShellKey.currentState?.navigateTo(1, allowHidden: true)'),
      reason: '分享创建待办后，即使待办底部入口被隐藏也要打开待办页。',
    );
  });
}
