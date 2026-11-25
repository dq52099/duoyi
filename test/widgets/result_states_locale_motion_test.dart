import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/widgets/result_states.dart' show ErrorState, LoadingState;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_polish_screenshot_font.dart';

const _captureEnvKey = 'DUOYI_CAPTURE_RESULT_STATES_SCREENSHOTS';
const _screenshotDirectory = 'evidence/screenshots/result-states-20261015';

bool get _captureScreenshots => Platform.environment[_captureEnvKey] == '1';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('default error title and Retry update with the current locale', (
    tester,
  ) async {
    var retries = 0;
    final capture = await _mount(
      tester,
      ErrorState(error: 'Connection lost', onRetry: () => retries++),
    );

    expect(find.text('出错了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await _capture(tester, capture, 'error-default-zh');

    I18n.setLocale(AppLocale.en);
    await tester.pump();

    expect(find.text('出错了'), findsNothing);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Connection lost'), findsOneWidget);
    await _capture(tester, capture, 'error-default-en');
    expect(tester.takeException(), isNull);

    // The button remains actionable after its localized label changes.
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('custom title and error stay literal while Retry translates', (
    tester,
  ) async {
    var retries = 0;
    await _mount(
      tester,
      ErrorState(
        title: 'Sync failed / 自定义标题',
        error: 'Raw response / 原始错误',
        onRetry: () => retries++,
      ),
    );

    expect(find.text('Sync failed / 自定义标题'), findsOneWidget);
    expect(find.text('Raw response / 原始错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    I18n.setLocale(AppLocale.en);
    await tester.pump();

    expect(find.text('Sync failed / 自定义标题'), findsOneWidget);
    expect(find.text('Raw response / 原始错误'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pump();
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state omits Retry when no callback is supplied', (
    tester,
  ) async {
    await _mount(tester, const ErrorState(error: 'No retry action'));

    expect(find.text('出错了'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'LoadingState pauses for disableAnimations and resumes when motion is enabled',
    (tester) async {
      final viewport = const Size(390, 844);
      final media = ValueNotifier<MediaQueryData>(
        MediaQueryData(size: viewport, disableAnimations: true),
      );
      final capture = await _mount(
        tester,
        const LoadingState(message: 'Loading goals', lines: 3),
        viewport: viewport,
        mediaQuery: media,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(_loadingController(tester).isAnimating, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(_loadingController(tester).isAnimating, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await _capture(tester, capture, 'loading-reduced-motion');

      media.value = media.value.copyWith(disableAnimations: false);
      await tester.pump();
      expect(_loadingController(tester).isAnimating, isTrue);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 40));
      expect(_loadingController(tester).isAnimating, isTrue);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(tester.takeException(), isNull);
      media.dispose();
    },
  );

  testWidgets('LoadingState pauses for accessibleNavigation', (tester) async {
    final media = ValueNotifier<MediaQueryData>(
      const MediaQueryData(size: Size(390, 844), accessibleNavigation: true),
    );
    await _mount(
      tester,
      const LoadingState(message: 'Loading goals'),
      mediaQuery: media,
    );

    await tester.pump(const Duration(seconds: 3));
    expect(_loadingController(tester).isAnimating, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(_loadingController(tester).isAnimating, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    media.dispose();
  });

  testWidgets('LoadingState accepts zero or negative line counts', (
    tester,
  ) async {
    await _mount(
      tester,
      const LoadingState(message: 'Still loading', lines: 0),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Still loading'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(
      tester,
      const LoadingState(message: 'Still loading', lines: -2),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Still loading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ErrorState scrolls and keeps Retry tappable in short windows', (
    tester,
  ) async {
    var retries = 0;
    for (final viewport in [const Size(200, 100), const Size(320, 180)]) {
      await _mount(
        tester,
        ErrorState(
          title:
              'The result could not be refreshed because the connection failed',
          error:
              'A long server response / 原始错误信息 that should stay readable in a short window.',
          onRetry: () => retries++,
        ),
        viewport: viewport,
        textScale: 1.3,
      );

      final retryButton = find.widgetWithText(FilledButton, '重试');
      final scrollable = find.byType(Scrollable).first;
      final scrollState = tester.state<ScrollableState>(scrollable);
      await tester.scrollUntilVisible(retryButton, 32, scrollable: scrollable);

      expect(scrollState.position.pixels, greaterThan(0));
      expect(retryButton.hitTestable(), findsOneWidget);
      await tester.tap(retryButton);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(retries, 2);
  });

  testWidgets(
    'LoadingState scrolls without overflow in short text-scaled windows',
    (tester) async {
      for (final viewport in [const Size(200, 100), const Size(320, 180)]) {
        await _mount(
          tester,
          const LoadingState(
            message: 'Loading a long result description / 正在载入较长的结果说明文字',
            lines: 10,
          ),
          viewport: viewport,
          textScale: 1.3,
        );

        final scrollable = find.byType(Scrollable).first;
        final scrollState = tester.state<ScrollableState>(scrollable);
        await tester.drag(scrollable, const Offset(0, -80));
        await tester.pump(const Duration(milliseconds: 32));

        expect(scrollState.position.pixels, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}

AnimationController _loadingController(WidgetTester tester) {
  final shimmer = find.descendant(
    of: find.byType(LoadingState),
    matching: find.byType(AnimatedBuilder),
  );
  return tester
          .widgetList<AnimatedBuilder>(shimmer)
          .firstWhere((widget) => widget.animation is AnimationController)
          .animation
      as AnimationController;
}

Future<GlobalKey> _mount(
  WidgetTester tester,
  Widget child, {
  Size viewport = const Size(390, 844),
  double textScale = 1,
  ValueListenable<MediaQueryData>? mediaQuery,
}) async {
  if (_captureScreenshots) {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
  }

  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final boundary = GlobalKey();
  final baseTheme = widgetPolishScreenshotTheme();
  final theme = _captureScreenshots
      ? baseTheme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              textStyle: baseTheme.textTheme.labelLarge,
            ),
          ),
        )
      : ThemeData();

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final screen = RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SizedBox.expand(child: child),
              ),
            );
            if (mediaQuery != null) {
              return ValueListenableBuilder<MediaQueryData>(
                valueListenable: mediaQuery,
                child: screen,
                builder: (context, data, child) => MediaQuery(
                  data: data.copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
              );
            }
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: screen,
            );
          },
        ),
      ),
    ),
  );
  return boundary;
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  if (!_captureScreenshots) return;
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_screenshotDirectory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
