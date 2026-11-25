import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.en);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'retained AI callback cannot start a request in another account',
    (tester) async {
      final ai = _Ai();
      await _mount(tester, ai);
      await tester.ensureVisible(find.text('AI review'));
      final review = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'AI review'))
          .onPressed!;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      review();
      await tester.pump();
      expect(ai.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'share form checks lock at invocation and remains usable after unlock',
    (tester) async {
      var clipboardWrites = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardWrites++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final lock = _Lock();
      await _mount(tester, _Ai(), lock: lock);
      await tester.tap(find.byTooltip('Report share image'));
      await tester.pumpAndSettle();
      final copy = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Copy Text'))
          .onPressed!;
      lock.blocked = true;
      copy();
      await tester.pump();
      expect(clipboardWrites, 0);
      lock.blocked = false;
      copy();
      await tester.pumpAndSettle();
      expect(clipboardWrites, 1);
    },
  );

  testWidgets(
    'copy rejection provides retryable feedback that follows visible locale changes',
    (tester) async {
      var reject = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData' && reject) {
            throw StateError('rejected clipboard');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _mount(tester, _Ai());
      await tester.tap(find.byTooltip('Report share image'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy Text'));
      await tester.pumpAndSettle();
      expect(find.text('Export failed, please try again'), findsOneWidget);
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.text('导出失败，请重试'), findsOneWidget);
      reject = false;
      await tester.tap(find.text('复制文案'));
      await tester.pumpAndSettle();
      expect(find.text('报告文案已复制'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  if (Platform.environment['DUOYI_STATISTICS_SCREENSHOTS'] == '1') {
    testWidgets(
      'render Statistics share dialog in the default theme at multiple sizes',
      (tester) async {
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
        for (final sample in [
          (size: const Size(390, 844), scale: 1.0, locale: AppLocale.en),
          (size: const Size(320, 844), scale: 1.6, locale: AppLocale.zh),
          (size: const Size(900, 650), scale: 1.0, locale: AppLocale.en),
        ]) {
          I18n.setLocale(sample.locale);
          final capture = GlobalKey();
          await _mount(
            tester,
            _Ai(),
            capture: capture,
            size: sample.size,
            scale: sample.scale,
          );
          await tester.tap(
            find.byTooltip(
              sample.locale == AppLocale.en ? 'Report share image' : '报告分享图',
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'evidence/screenshots/statistics-report-20261012/share-${sample.size.width.toInt()}-${sample.locale.name}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  testWidgets(
    'delayed review for the same report is displayed and busy state clears',
    (tester) async {
      final ai = _Ai();
      await _mount(tester, ai);
      await _startReview(tester);
      expect(ai.requests.single.locale, AppLocale.en);
      expect(ai.requests.single.markdown, contains('# Weekly report'));
      ai.requests.single.result.complete('literal review / 原文');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('literal review / 原文'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'brand route retains month range and pending AI review across locales',
    (tester) async {
      final ai = _Ai();
      await _mount(tester, ai);
      await tester.ensureVisible(find.text('This month'));
      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      final screenState = tester.state(find.byType(StatisticsScreen));
      final rangeControl = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton,
      );
      final selected =
          (tester.widget(rangeControl) as SegmentedButton).selected;
      await _startReview(tester);
      expect(ai.requests, hasLength(1));
      final request = ai.requests.single;
      I18n.setLocale(AppLocale.zh);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(StatisticsScreen)), same(screenState));
      expect(
        (tester.widget(rangeControl) as SegmentedButton).selected,
        selected,
      );
      expect(ai.requests, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      request.result.complete('Retained monthly review / 原文');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Retained monthly review / 原文'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(StatisticsScreen)), same(screenState));
      expect(
        (tester.widget(rangeControl) as SegmentedButton).selected,
        selected,
      );
      expect(find.text('Retained monthly review / 原文'), findsOneWidget);
      expect(ai.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final transition in ['range', 'account']) {
    testWidgets(
      '$transition change rejects old review without clearing newer busy state',
      (tester) async {
        final ai = _Ai();
        await _mount(tester, ai);
        await _startReview(tester);
        if (transition == 'range') {
          await tester.ensureVisible(find.text('This month'));
          await tester.tap(find.text('This month'));
        } else {
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        }
        await tester.pump(const Duration(milliseconds: 300));
        await _startReview(tester);
        expect(ai.requests, hasLength(2));
        ai.requests.first.result.complete('old review');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('old review'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        ai.requests.last.result.complete('current review');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('current review'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  }

  testWidgets(
    'open share dialog follows locale while retaining selected PDF template',
    (tester) async {
      await _mount(tester, _Ai());
      await tester.tap(find.byTooltip('Report share image'));
      await tester.pumpAndSettle();
      final segmentFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SegmentedButton &&
            widget.segments.any(
              (segment) =>
                  segment.label is Text &&
                  (segment.label as Text).data == 'Archive',
            ),
      );
      final screenState = tester.state(find.byType(StatisticsScreen));
      final element = tester.element(segmentFinder);
      await tester.tap(find.text('Archive'));
      await tester.pump();
      final selected =
          (tester.widget(segmentFinder) as SegmentedButton).selected.single;
      I18n.setLocale(AppLocale.zh);
      await tester.pump();
      expect(find.text('报告分享图'), findsOneWidget);
      expect(find.text('归档版'), findsOneWidget);
      final translatedFinder = find.byWidgetPredicate(
        (widget) =>
            widget is SegmentedButton &&
            widget.segments.any(
              (segment) =>
                  segment.label is Text &&
                  (segment.label as Text).data == '归档版',
            ),
      );
      expect(tester.state(find.byType(StatisticsScreen)), same(screenState));
      expect(tester.element(translatedFinder), same(element));
      expect(
        (tester.widget(translatedFinder) as SegmentedButton).selected.single,
        selected,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open share dialog follows live theme while retaining selected PDF template',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      });
      await _mount(tester, _Ai());
      final theme = Provider.of<ThemeProvider>(
        tester.element(find.byType(StatisticsScreen)),
        listen: false,
      );
      await tester.runAsync(
        () => theme.applyShopStateFromServer({
          'activeBrand': 'defaultBrand',
          'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
        }, trusted: true),
      );
      await tester.tap(find.byTooltip('Report share image'));
      await tester.pumpAndSettle();
      final archive = find.byWidgetPredicate(
        (widget) =>
            widget is SegmentedButton &&
            widget.segments.any(
              (segment) =>
                  segment.label is Text &&
                  (segment.label as Text).data == 'Archive',
            ),
      );
      await tester.tap(
        find.descendant(of: archive, matching: find.text('Archive')),
      );
      await tester.pump();
      final selected = (tester.widget<SegmentedButton>(
        archive,
      )).selected.single;
      final dialogRoute = ModalRoute.of(tester.element(find.byType(Dialog)))!;

      await tester.runAsync(() => theme.setBrand('liquidGlass'));
      await tester.pumpAndSettle();

      expect(
        ModalRoute.of(tester.element(find.byType(Dialog))),
        same(dialogRoute),
      );
      expect(dialogRoute.isCurrent, isTrue);
      expect(theme.brand.id, 'liquidGlass');
      expect(find.byType(AppDialog), findsOneWidget);
      expect(tester.widget<SegmentedButton>(archive).selected.single, selected);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('share dialog from an old account cannot copy its old report', (
    tester,
  ) async {
    var clipboardWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardWrites++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _mount(tester, _Ai());
    await tester.tap(find.byTooltip('Report share image'));
    await tester.pumpAndSettle();
    final copy = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Copy Text'))
        .onPressed!;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    copy();
    await tester.pump();
    expect(clipboardWrites, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained share close cannot pop a newer route and is safe after disposal',
    (tester) async {
      await _mount(tester, _Ai());
      await tester.tap(find.byTooltip('Report share image'));
      await tester.pumpAndSettle();
      final close = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
          .onPressed!;
      final navigator = Navigator.of(tester.element(find.byType(Dialog)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('new route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      close();
      await tester.pumpAndSettle();
      expect(find.text('new route'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      close();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _startReview(WidgetTester tester) async {
  await tester.ensureVisible(find.text('AI review'));
  await tester.tap(find.text('AI review'));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _mount(
  WidgetTester tester,
  _Ai ai, {
  Size size = const Size(800, 600),
  double scale = 1,
  GlobalKey? capture,
  _Lock? lock,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TodoProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider<AiService>(create: (_) => ai),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          if (lock != null)
            ChangeNotifierProvider<AppLockProvider>(create: (_) => lock),
        ],
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
            home: const BrandRouteSurface(child: StatisticsScreen()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Review {
  _Review(this.locale, this.markdown);
  final AppLocale? locale;
  final String markdown;
  final result = Completer<String>();
}

class _Ai extends AiService {
  final requests = <_Review>[];
  @override
  bool get enabled => true;
  @override
  Future<String> personalizedReportReview({
    required String periodLabel,
    required String reportMarkdown,
    AppLocale? locale,
  }) {
    final request = _Review(locale, reportMarkdown);
    requests.add(request);
    return request.result.future;
  }
}

class _Lock extends AppLockProvider {
  bool blocked = false;
  @override
  bool get isLocked => blocked;
}
