import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/date_item_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  for (final surface in ['list', 'default-editor', 'custom-editor']) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'narrow', size: Size(320, 844), scale: 1.3),
        (name: 'landscape', size: Size(568, 320), scale: 1.6),
      ]) {
        testWidgets(
          'countdown category $surface ${locale.name} ${layout.name}',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            I18n.setLocale(locale);
            await tester.runAsync(_loadFonts);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            final provider = CountdownProvider();
            final theme = ThemeProvider();
            final boundary = GlobalKey();
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              provider.dispose();
              theme.dispose();
              tester.view.reset();
              I18n.setLocale(AppLocale.zh);
            });
            expect(theme.brand.id, AppBrands.defaultBrand.id);
            final isEn = locale == AppLocale.en;
            await provider.addItem(
              CountdownItem(
                id: 'generated',
                title: isEn
                    ? 'Family celebration with a long title'
                    : '与家人庆祝值得纪念的重要日子',
                targetDate: DateTime(2099, 7, 1),
              ),
            );
            await provider.addItem(
              CountdownItem(
                id: 'custom',
                title: isEn ? 'A category you named yourself' : '保留自己填写的分类名称',
                targetDate: DateTime(2099, 7, 2),
                category: '默认',
              ),
            );
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: provider),
                  ChangeNotifierProvider.value(value: theme),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme.copyWith(
                    platform: TargetPlatform.iOS,
                  ),
                  builder: (context, child) => RepaintBoundary(
                    key: boundary,
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                      child: child!,
                    ),
                  ),
                  home: BrandRouteSurface(
                    child: CountdownScreen(
                      initialCountdownId: surface == 'list'
                          ? null
                          : surface == 'default-editor'
                          ? 'generated'
                          : 'custom',
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (surface == 'list') {
              final card = find.byKey(const ValueKey('countdown_card_custom'));
              final scrollable = find.byType(Scrollable).first;
              await tester.scrollUntilVisible(
                card,
                100,
                scrollable: scrollable,
              );
              await tester.drag(scrollable, const Offset(0, -500));
              await tester.pumpAndSettle();
              expect(
                find.descendant(of: card, matching: find.text('默认')),
                findsOneWidget,
              );
              expect(
                tester
                    .getRect(card)
                    .overlaps(
                      tester.getRect(
                        find.byKey(const ValueKey('countdown_add_button')),
                      ),
                    ),
                isFalse,
              );
            } else {
              final field = find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText ==
                        I18n.tr('countdown.field.category'),
              );
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              final widget = tester.widget<TextField>(field);
              expect(
                widget.controller!.text,
                surface == 'default-editor' ? '' : '默认',
              );
              expect(
                widget.decoration!.hintText,
                I18n.tr('countdown.category.default'),
              );
              expect(
                widget.decoration!.floatingLabelBehavior,
                FloatingLabelBehavior.always,
              );
              if (surface == 'custom-editor') {
                expect(
                  find.byTooltip(DateItemUiCopy.resetCategory),
                  findsOneWidget,
                );
              }
              final modal = find.byType(AppModalSheet).last;
              expect(
                find.descendant(
                  of: modal,
                  matching: find.text(I18n.tr('action.save')),
                ),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
            await _capture(
              tester,
              boundary,
              '$surface-${locale.name}-${layout.name}',
            );
          },
        );
      }
    }
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_DATE_SETTINGS_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await render.toImage();
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    screenshot.dispose();
    final file = File(
      'evidence/screenshots/countdown-category-20261015/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
  await loadWidgetPolishScreenshotFonts();
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    await (FontLoader(family)..addFont(Future.value(chinese))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}
