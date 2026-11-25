import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/widget_quick_todo_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final sample in [
      (name: 'phone', size: const Size(390, 844), scale: 1.6, keyboard: 300.0),
      (name: 'narrow', size: const Size(320, 844), scale: 2.0, keyboard: 300.0),
      (
        name: 'landscape',
        size: const Size(568, 320),
        scale: 1.6,
        keyboard: 128.0,
      ),
    ]) {
      final name = '$brand-${sample.name}';
      testWidgets('quick widget task keyboard and locale $name', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({'active_brand': brand});
        I18n.setLocale(AppLocale.zh);
        tester.view.physicalSize = sample.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final theme = ThemeProvider();
        await tester.runAsync(() async {
          await theme.loadFromStorage();
          await loadWeeklyReviewScreenshotFonts();
        });
        final capture = GlobalKey();
        var saves = 0;
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme,
            child: MaterialApp(
              theme: theme.brand.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(sample.scale)),
                child: RepaintBoundary(key: capture, child: child!),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => WidgetQuickTodoDialog(
                        canSubmit: () => true,
                        onSubmit: (_) async {
                          saves++;
                          return false;
                        },
                      ),
                    ),
                    child: const Text('Open quick task'),
                  ),
                ),
              ),
            ),
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          theme.dispose();
        });
        expect(theme.brand.id, brand);
        await tester.tap(find.text('Open quick task'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '明天下午3点开会 / keep draft');
        tester.view.viewInsets = FakeViewPadding(bottom: sample.keyboard);
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(find.byType(TextField));
        final controller = field.controller!;
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 6,
        );
        final original = tester.element(find.byType(WidgetQuickTodoDialog));
        final observations = <Map<String, Object?>>[];
        final errors = <Object>[];
        for (final locale in [AppLocale.zh, AppLocale.en]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          final finder = find.widgetWithText(
            FilledButton,
            locale == AppLocale.zh ? '添加' : 'Add',
          );
          final button = tester.getRect(finder);
          final error = tester.takeException();
          if (error != null) errors.add(error);
          observations.add({
            'locale': locale.name,
            'keyboardTop': sample.size.height - sample.keyboard,
            'button': [button.left, button.top, button.right, button.bottom],
            'hitTestable': finder.hitTestable().evaluate().length == 1,
          });
          final folder =
              Platform.environment['DUOYI_QUICK_KEYBOARD_SCREENSHOTS'];
          if (folder != null) {
            await tester.runAsync(() async {
              final boundary =
                  capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              try {
                final png = (await image.toByteData(
                  format: ui.ImageByteFormat.png,
                ))!;
                final file = File('$folder/$name-${locale.name}.png');
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(png.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          // A short IME viewport may scroll the title or parsed date away.
          // Both must remain reachable while the actions stay above the IME.
          for (final target in [
            find.text(locale == AppLocale.zh ? '快速待办' : 'Quick task'),
            find.textContaining(locale == AppLocale.zh ? '识别到:' : 'Detected:'),
          ]) {
            expect(target, findsOneWidget);
            await Scrollable.ensureVisible(
              tester.element(target),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            final viewport = tester.getRect(
              find
                  .ancestor(
                    of: target,
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first,
            );
            final targetRect = tester.getRect(target);
            expect(targetRect.top, greaterThanOrEqualTo(viewport.top - .5));
            expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom + .5));
            expect(
              tester.getRect(finder).bottom,
              lessThanOrEqualTo(sample.size.height - sample.keyboard + .5),
            );
            expect(finder.hitTestable(), findsOneWidget);
          }
          expect(
            tester.element(find.byType(WidgetQuickTodoDialog)),
            same(original),
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller,
            same(controller),
          );
          expect(controller.text, '明天下午3点开会 / keep draft');
          expect(
            controller.selection,
            const TextSelection(baseOffset: 2, extentOffset: 6),
          );
        }
        final folder =
            Platform.environment['DUOYI_QUICK_KEYBOARD_MEASUREMENTS'];
        if (folder != null) {
          final file = File('$folder/$name.json');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(
            jsonEncode({
              'observations': observations,
              'renderErrors': errors.map((e) => '$e').toList(),
            }),
          );
        }
        expect(errors, isEmpty);
        for (final observation in observations) {
          final rect = observation['button']! as List<double>;
          expect(
            rect[1],
            greaterThanOrEqualTo(0),
            reason: '$name ${observation['locale']} Add top',
          );
          expect(
            rect[3],
            lessThanOrEqualTo(sample.size.height - sample.keyboard + .5),
            reason: '$name ${observation['locale']} Add must remain above IME',
          );
          expect(observation['hitTestable'], isTrue);
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(find.byType(WidgetQuickTodoDialog), findsOneWidget);
        expect(controller.text, '明天下午3点开会 / keep draft');
      });
    }
  }
}
