import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/widget_quick_todo_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.en));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('quick add fits phone and short windows in the default theme', (
    tester,
  ) async {
    final screenshots =
        Platform.environment['DUOYI_WIDGET_ACTION_SCREENSHOTS'] == '1';
    if (screenshots) {
      await tester.runAsync(() async {
        await loadWidgetPolishScreenshotFonts();
        final latin = ByteData.sublistView(
          File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
        );
        await (FontLoader('sans-serif')..addFont(Future.value(latin))).load();
        final cjk = ByteData.sublistView(
          File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
        );
        for (final family in ['DroidSansFallbackFull', 'PingFang SC']) {
          await (FontLoader(family)..addFont(Future.value(cjk))).load();
        }
      });
    }
    for (final sample in [
      (size: const Size(390, 844), scale: 1.0, locale: AppLocale.en),
      (size: const Size(320, 844), scale: 1.6, locale: AppLocale.zh),
      (size: const Size(640, 250), scale: 1.6, locale: AppLocale.en),
    ]) {
      I18n.setLocale(sample.locale);
      final capture = GlobalKey();
      await _mount(
        tester,
        onSubmit: (_) async => false,
        size: sample.size,
        scale: sample.scale,
        capture: capture,
      );
      await tester.enterText(
        find.byType(TextField),
        '明天下午3点开会 / design review',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find
            .widgetWithText(
              FilledButton,
              sample.locale == AppLocale.en ? 'Add' : '添加',
            )
            .hitTestable(),
        findsOneWidget,
      );
      if (screenshots) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'evidence/screenshots/widget-actions-20261012/quick-${sample.size.width.toInt()}-${sample.locale.name}.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'denied save retains input, selection and retry across locale changes',
    (tester) async {
      var calls = 0;
      await _mount(tester, onSubmit: (_) async => ++calls > 1);
      await tester.enterText(find.byType(TextField), '明天下午3点开会 / keep literal');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      final route = ModalRoute.of(tester.element(find.byType(TextField)));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(WidgetQuickTodoDialog), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      final translated = tester.widget<TextField>(find.byType(TextField));
      expect(translated.controller, same(field.controller));
      expect(translated.focusNode, same(field.focusNode));
      expect(translated.controller!.text, '明天下午3点开会 / keep literal');
      expect(
        translated.controller!.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(
        ModalRoute.of(tester.element(find.byType(TextField))),
        same(route),
      );
      expect(find.text('快速待办'), findsOneWidget);
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(WidgetQuickTodoDialog), findsNothing);
    },
  );

  testWidgets('busy save ignores a retained duplicate callback', (
    tester,
  ) async {
    final gate = Completer<bool>();
    var calls = 0;
    await _mount(
      tester,
      onSubmit: (_) {
        calls++;
        return gate.future;
      },
    );
    await tester.enterText(find.byType(TextField), 'draft');
    final submit = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
        .onPressed!;
    submit();
    await tester.pump();
    submit();
    expect(calls, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    gate.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets(
    'blocked access suppresses retained submit and allows retry after unlock',
    (tester) async {
      var allowed = true;
      var calls = 0;
      await _mount(
        tester,
        canSubmit: () => allowed,
        onSubmit: (_) async {
          calls++;
          return false;
        },
      );
      await tester.enterText(find.byType(TextField), 'draft');
      final submit = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .onPressed!;
      allowed = false;
      submit();
      await tester.pump();
      expect(calls, 0);
      allowed = true;
      submit();
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets(
    'late accepted save removes only its own form under a newer route',
    (tester) async {
      final gate = Completer<bool>();
      final navigator = GlobalKey<NavigatorState>();
      await _mount(tester, navigator: navigator, onSubmit: (_) => gate.future);
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.tap(find.text('Add'));
      await tester.pump();
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('new route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      gate.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('new route'), findsOneWidget);
      expect(
        find.byType(WidgetQuickTodoDialog, skipOffstage: false),
        findsNothing,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('launch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(
  WidgetTester tester, {
  required Future<bool> Function(String) onSubmit,
  bool Function()? canSubmit,
  GlobalKey<NavigatorState>? navigator,
  Size size = const Size(800, 600),
  double scale = 1,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: context.watch<ThemeProvider>().brand.theme,
            debugShowCheckedModeBanner: false,
            builder: (appContext, child) => MediaQuery(
              data: MediaQuery.of(
                appContext,
              ).copyWith(size: size, textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            navigatorKey: navigator,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => WidgetQuickTodoDialog(
                      canSubmit: canSubmit ?? () => true,
                      onSubmit: onSubmit,
                    ),
                  ),
                  child: const Text('launch'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('launch'));
  await tester.pumpAndSettle();
}
