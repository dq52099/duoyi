import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/quick_capture_ui_copy.dart';
import 'package:duoyi/models/quick_capture_template.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final locale in AppLocale.values) {
    testWidgets(
      'quick capture $locale default iOS dialogs and templates fit narrow scaled phone',
      (tester) async {
        final boundary = await _mount(tester, locale: locale);
        await _open(tester, Icons.edit_note);
        await tester.enterText(find.byType(TextField), '项目原文 / Literal draft');
        await _capture(tester, boundary, '${locale.name}-note');
        await _cancel(tester);

        await _open(tester, Icons.check_circle_outline);
        await tester.enterText(find.byType(TextField), '明天下午3点 读书 / literal');
        await _capture(tester, boundary, '${locale.name}-todo');
        await _cancel(tester);

        await _templates(tester);
        await _capture(tester, boundary, '${locale.name}-templates');
        await tester.tap(
          find.widgetWithText(OutlinedButton, I18n.tr('quick.template.save')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(4));
        await tester.enterText(
          find.byType(TextField).first,
          '自定义 / Literal template',
        );
        await _capture(tester, boundary, '${locale.name}-template-save');
        await _cancel(tester);

        await _templates(tester);
        await tester.tap(
          find.text(
            QuickCaptureUiCopy.templateName(
              QuickCaptureTemplate.builtIns().first,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '项目讨论 / Literal');
        await _capture(tester, boundary, '${locale.name}-template-apply');
        await _cancel(tester);

        await _open(tester, Icons.assistant_outlined);
        await tester.enterText(find.byType(TextField), '记笔记 项目原文；开始专注');
        await _capture(tester, boundary, '${locale.name}-ai');
        await _cancel(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(800, 1000), const Size(320, 568)]) {
    testWidgets(
      'quick capture note and save template fit $size with keyboard',
      (tester) async {
        final boundary = await _mount(
          tester,
          locale: AppLocale.en,
          size: size,
          keyboard: 180,
        );
        await _open(tester, Icons.edit_note);
        await tester.enterText(find.byType(TextField), 'Literal draft');
        await _capture(
          tester,
          boundary,
          'en-${size.width.toInt()}-keyboard-note',
        );
        await _cancel(tester);
        await _templates(tester);
        await tester.tap(
          find.widgetWithText(OutlinedButton, I18n.tr('quick.template.save')),
        );
        await tester.pumpAndSettle();
        await _capture(
          tester,
          boundary,
          'en-${size.width.toInt()}-keyboard-template-save',
        );
        await _cancel(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<GlobalKey> _mount(
  WidgetTester tester, {
  required AppLocale locale,
  Size size = const Size(320, 720),
  double keyboard = 0,
}) async {
  I18n.setLocale(locale);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final themeProvider = ThemeProvider();
  final templates = QuickCaptureTemplateProvider();
  final notes = NoteProvider();
  final ai = _Ai();
  final gate = AppAccessRouteGate();
  final boundary = GlobalKey();
  final theme = themeProvider.brand.theme;
  final fonts = theme.textTheme.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: ['DuoyiScreenshot'],
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<QuickCaptureTemplateProvider>.value(
          value: templates,
        ),
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
        navigatorObservers: [gate],
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.3),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
        ),
        home: const Scaffold(floatingActionButton: QuickCaptureFab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    templates.dispose();
    notes.dispose();
    ai.dispose();
    themeProvider.dispose();
    gate.dispose();
  });
  return boundary;
}

Future<void> _open(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byType(FloatingActionButton).last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithIcon(FloatingActionButton, icon));
  await tester.pumpAndSettle();
}

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, I18n.tr('action.cancel')));
  await tester.pumpAndSettle();
  expect(find.byType(AppDialog), findsNothing);
}

Future<void> _templates(WidgetTester tester) async {
  await tester.longPress(find.byType(FloatingActionButton).last);
  await tester.pumpAndSettle();
  expect(find.text(I18n.tr('quick.template.title')), findsOneWidget);
  expect(
    tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
    isFalse,
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  if (Platform.environment['DUOYI_CAPTURE_QUICK_CAPTURE_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('evidence/screenshots/quick-capture-20261015/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _Ai extends AiService {
  @override
  bool get enabled => true;
}
