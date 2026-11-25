import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugDesktopWebBuild = true;
  });
  tearDown(() {
    WebTarget.debugDesktopWebBuild = null;
    I18n.setLocale(AppLocale.zh);
  });

  for (final locale in AppLocale.values) {
    for (final size in [const Size(320, 844), const Size(1024, 900)]) {
      testWidgets('desktop web gallery fits ${locale.name} at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(loadWidgetPolishScreenshotFonts);
        final theme = ThemeProvider();
        await theme.loadFromStorage();
        addTearDown(theme.dispose);
        I18n.setLocale(locale);
        var nativeCalls = 0;
        const channel = MethodChannel('duoyi/widgets');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            nativeCalls++;
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        });
        final text = theme.brand.theme.textTheme.apply(
          fontFamily: 'DuoyiScreenshotLatin',
          fontFamilyFallback: const ['DuoyiScreenshot'],
        );
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme,
            child: MaterialApp(
              theme: theme.brand.theme.copyWith(textTheme: text),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(size.width < 600 ? 1.6 : 1),
                ),
                child: child!,
              ),
              home: const WidgetScreen(hostPlatform: WidgetHostPlatform.web),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byKey(const ValueKey('desktop_web_widget_fallback'));
        final rect = tester.getRect(list);
        expect(rect.width, closeTo(size.width < 720 ? size.width : 720, 0.01));
        expect(rect.center.dx, closeTo(size.width / 2, 0.01));
        expect(find.byType(WidgetPreviewCard), findsOneWidget);
        expect(find.text(WidgetUiCopy.desktopWebTitle), findsOneWidget);
        final action = find.widgetWithText(
          FilledButton,
          WidgetUiCopy.desktopWebOpenCalendar,
        );
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
        expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
        final label = find.descendant(
          of: action,
          matching: find.text(WidgetUiCopy.desktopWebOpenCalendar),
        );
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(tester.getRect(label).left, greaterThanOrEqualTo(rect.left));
        expect(tester.getRect(label).right, lessThanOrEqualTo(rect.right));
        expect(nativeCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
