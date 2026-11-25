import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/shared_text_import_sheet.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  if (Platform.environment['DUOYI_SHARE_SCREENSHOTS'] == '1') {
    testWidgets('render shared import visual evidence', (tester) async {
      await tester.runAsync(loadWidgetPolishScreenshotFonts);
      await tester.runAsync(() async {
        final latin = File('assets/fonts/DejaVuSans.ttf').readAsBytesSync();
        await (FontLoader(
          'sans-serif',
        )..addFont(Future.value(ByteData.sublistView(latin)))).load();
        final chinese = File(
          'assets/fonts/DroidSansFallbackFull.ttf',
        ).readAsBytesSync();
        await (FontLoader(
          'DroidSansFallbackFull',
        )..addFont(Future.value(ByteData.sublistView(chinese)))).load();
        await (FontLoader(
          'PingFang SC',
        )..addFont(Future.value(ByteData.sublistView(chinese)))).load();
      });
      for (final sample in [
        (size: const Size(390, 844), scale: 1.0, locale: AppLocale.en),
        (size: const Size(320, 844), scale: 1.6, locale: AppLocale.zh),
        (size: const Size(640, 300), scale: 1.6, locale: AppLocale.en),
      ]) {
        I18n.setLocale(sample.locale);
        final capture = GlobalKey();
        await _open(
          tester,
          size: sample.size,
          scale: sample.scale,
          capture: capture,
        );
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final screenshot = await boundary.toImage();
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File(
            'evidence/screenshots/shared-import-20261012/share-${sample.size.width.toInt()}-${sample.locale.name}.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          screenshot.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  for (final size in [
    const Size(320, 844),
    const Size(900, 600),
    const Size(640, 300),
  ]) {
    testWidgets(
      'shared import fits $size with large text and preserves locale state',
      (tester) async {
        final f = await _open(tester, size: size);
        final sheet = find.byType(SharedTextImportSheet);
        final state = tester.state(sheet);
        final editable = find.descendant(
          of: sheet,
          matching: find.byType(EditableText),
        );
        final controller = tester.widget<EditableText>(editable).controller;
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 8,
        );
        final scroll = find
            .descendant(of: sheet, matching: find.byType(SingleChildScrollView))
            .last;
        final scrollController = tester
            .widget<SingleChildScrollView>(scroll)
            .controller!;
        scrollController.jumpTo(40);
        await tester.pump();
        final offset = scrollController.offset;
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(tester.state(sheet), same(state));
          expect(
            tester.widget<EditableText>(editable).controller,
            same(controller),
          );
          expect(
            controller.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );
          expect(scrollController.offset, offset);
          expect(
            find.text(locale == AppLocale.en ? 'Import shared text' : '导入分享文本'),
            findsOneWidget,
          );
          expect(
            find.text(locale == AppLocale.en ? 'Create task' : '创建待办'),
            findsOneWidget,
          );
          expect(
            find.text(locale == AppLocale.en ? 'Save note' : '保存笔记'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('shared_text_import_todo_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('shared_text_import_todo_button')),
        );
        await tester.pumpAndSettle();
        expect(await f.result, SharedTextImportChoice.todo);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'retained actions cannot choose while locked or pop a covering route',
    (tester) async {
      final f = await _open(tester);
      final button = find.byKey(
        const ValueKey('shared_text_import_note_button'),
      );
      final callback = tester.widget<OutlinedButton>(button).onPressed!;
      f.allowed = false;
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(SharedTextImportSheet), findsOneWidget);
      f.allowed = true;
      f.navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering page')),
        ),
      );
      await tester.pumpAndSettle();
      callback();
      await tester.pumpAndSettle();
      expect(find.text('Covering page'), findsOneWidget);
      f.navigator.pop();
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(await f.result, SharedTextImportChoice.note);
      callback();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final delay in [Duration.zero, const Duration(milliseconds: 100)]) {
    testWidgets(
      'repeated import choice during dismissal preserves host $delay',
      (tester) async {
        final f = await _open(tester, secondaryHost: true);
        final callback = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('shared_text_import_todo_button')),
            )
            .onPressed!;
        callback();
        if (delay != Duration.zero) await tester.pump(delay);
        callback();
        await tester.pumpAndSettle();
        expect(await f.result, SharedTextImportChoice.todo);
        expect(find.text('Secondary host'), findsOneWidget);
        expect(tester.takeException(), isNull);
        f.navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
      },
    );
  }
}

class _Fixture {
  bool allowed = true;
  late NavigatorState navigator;
  late Future<SharedTextImportChoice?> result;
}

Future<_Fixture> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1.6,
  GlobalKey? capture,
  bool secondaryHost = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final f = _Fixture();
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: context.watch<ThemeProvider>().brand.theme,
            debugShowCheckedModeBanner: false,
            builder: (_, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(size: size, textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) {
                f.navigator = Navigator.of(context);
                return const Scaffold(body: Text('Home'));
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (secondaryHost) {
    f.navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Secondary host')),
      ),
    );
    await tester.pumpAndSettle();
  }
  f.result = showAppModalSheet<SharedTextImportChoice>(
    context: f.navigator.context,
    builder: (_) => SharedTextImportSheet(
      text: List.generate(50, (i) => 'Shared draft line $i 分享文本').join('\n'),
      canChoose: () => f.allowed,
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return f;
}
