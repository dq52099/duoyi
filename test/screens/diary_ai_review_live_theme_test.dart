import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _openDiaryKey = ValueKey<String>('open-diary-ai-review');
const _diaryBody = 'Authored diary 原文: finished the project and took a walk.';
const _reviewBody = 'AI result 原文: keep the daily walk and plan one small step.';
const _asyncTimeout = Duration(seconds: 5);

void main() {
  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    for (final initialLocale in [AppLocale.zh, AppLocale.en]) {
      for (final size in [const Size(320, 844), const Size(568, 320)]) {
        testWidgets(
          'real diary AI result retains live theme and locale '
          '$initialBrand ${initialLocale.name} ${size.width}',
          (tester) async {
            final fixture = await _mountDiary(
              tester,
              initialBrand: initialBrand,
              initialLocale: initialLocale,
              size: size,
            );
            final diary = find.byType(DiaryScreen);
            final diaryElement = tester.element(diary);
            final diaryRoute = ModalRoute.of(diaryElement);
            expect(diaryRoute, isNotNull);
            final diarySnapshot = jsonEncode(
              fixture.diaries.entries.single.toJson(),
            );

            // Invoke DiaryScreen's actual action, service and result route.
            // Only HTTP and preferences are substituted; no test dialog is built.
            await tester.tap(
              find.byTooltip(I18n.tr('diary.ai.deep_review.tooltip')),
            );
            await tester.pump();
            expect(fixture.requestCount, 1);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(find.byType(AppDialog), findsNothing);
            expect(fixture.ai.reviewHistory, isEmpty);

            await fixture.completeReview(tester);
            await tester.pumpAndSettle();

            final dialog = find.byType(AppDialog);
            expect(dialog, findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            final dialogElement = tester.element(dialog);
            final dialogRoute = ModalRoute.of(dialogElement);
            expect(dialogRoute, isNotNull);
            expect(dialogRoute, isNot(same(diaryRoute)));
            final resultFinder = find.descendant(
              of: dialog,
              matching: find.byType(SelectableText),
            );
            expect(resultFinder, findsOneWidget);
            final resultElement = tester.element(resultFinder);
            final resultState = tester.state<State<SelectableText>>(
              resultFinder,
            );
            final savedReview = jsonEncode(
              fixture.ai.reviewHistory.single.toJson(),
            );
            final storedReviews = await fixture.storedReviews(tester);
            expect(storedReviews, hasLength(1));
            expect(jsonDecode(storedReviews.single), jsonDecode(savedReview));

            void expectRetainedResult(String brand) {
              expect(tester.element(dialog), same(dialogElement));
              expect(ModalRoute.of(tester.element(dialog)), same(dialogRoute));
              expect(tester.element(diary), same(diaryElement));
              expect(ModalRoute.of(tester.element(diary)), same(diaryRoute));
              expect(tester.element(resultFinder), same(resultElement));
              expect(
                tester.state<State<SelectableText>>(resultFinder),
                same(resultState),
              );
              expect(
                tester.widget<SelectableText>(resultFinder).data,
                _reviewBody,
              );
              expect(
                appSurfaceStyleOf(tester.element(dialog)),
                AppBrands.byId(brand).theme.extension<AppSurfaceStyle>(),
                reason: 'The open production result must follow the live brand',
              );
              expect(
                find.descendant(
                  of: dialog,
                  matching: find.text(I18n.tr('diary.ai.deep_review.title')),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: dialog,
                  matching: find.widgetWithText(
                    TextButton,
                    I18n.tr('action.close'),
                  ),
                ),
                findsOneWidget,
              );
              expect(fixture.requestCount, 1);
              expect(
                jsonEncode(fixture.ai.reviewHistory.single.toJson()),
                savedReview,
              );
              expect(
                jsonEncode(fixture.diaries.entries.single.toJson()),
                diarySnapshot,
              );
            }

            expectRetainedResult(initialBrand);

            final targetBrand = initialBrand == 'defaultBrand'
                ? 'liquidGlass'
                : 'defaultBrand';
            expect(
              await tester.runAsync(() => fixture.theme.setBrand(targetBrand)),
              isTrue,
            );
            await tester.pumpAndSettle();
            expect(fixture.theme.brand.id, targetBrand);
            expect(
              appSurfaceStyleOf(tester.element(diary)),
              AppBrands.byId(targetBrand).theme.extension<AppSurfaceStyle>(),
              reason: 'The underlying page must really change theme',
            );
            expectRetainedResult(targetBrand);

            final targetLocale = initialLocale == AppLocale.zh
                ? AppLocale.en
                : AppLocale.zh;
            final previousTitle = I18n.tr('diary.ai.deep_review.title');
            final previousClose = I18n.tr('action.close');
            I18n.setLocale(targetLocale);
            await tester.pumpAndSettle();
            expectRetainedResult(targetBrand);
            expect(
              find.descendant(of: dialog, matching: find.text(previousTitle)),
              findsNothing,
            );
            expect(
              find.descendant(of: dialog, matching: find.text(previousClose)),
              findsNothing,
            );
            if (initialBrand == 'defaultBrand') {
              await fixture.captureResult(
                tester,
                'from-${initialLocale.name}-${size.width.toInt()}x'
                '${size.height.toInt()}-2x-locale-${targetLocale.name}-glass',
              );
            }

            I18n.setLocale(initialLocale);
            expect(
              await tester.runAsync(() => fixture.theme.setBrand(initialBrand)),
              isTrue,
            );
            await tester.pumpAndSettle();
            expectRetainedResult(initialBrand);
            if (initialBrand == 'defaultBrand') {
              await fixture.captureResult(
                tester,
                'from-${initialLocale.name}-${size.width.toInt()}x'
                '${size.height.toInt()}-2x-locale-${initialLocale.name}-default-return',
              );
            }

            final close = find.descendant(
              of: dialog,
              matching: find.widgetWithText(
                TextButton,
                I18n.tr('action.close'),
              ),
            );
            expect(close.hitTestable(), findsOneWidget);
            await tester.tap(close);
            await tester.pumpAndSettle();
            expect(dialog, findsNothing);
            expect(tester.element(diary), same(diaryElement));
            expect(ModalRoute.of(tester.element(diary)), same(diaryRoute));
            expect(diaryRoute!.isCurrent, isTrue);
            expect(fixture.requestCount, 1);
            expect(
              await fixture.storedReviews(tester),
              orderedEquals(storedReviews),
            );
            expect(
              jsonEncode(fixture.diaries.entries.single.toJson()),
              diarySnapshot,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

Future<_DiaryFixture> _mountDiary(
  WidgetTester tester, {
  required String initialBrand,
  required AppLocale initialLocale,
  required Size size,
}) async {
  final previousLocale = I18n.current;
  final previousStore = SharedPreferencesStorePlatform.instance;
  final entry = DiaryEntry(
    id: 'diary-ai-live-theme',
    date: DateTime.now(),
    content: _diaryBody,
  );
  SharedPreferences.setMockInitialValues({
    'duoyi_diary': [jsonEncode(entry.toJson())],
    'active_brand': initialBrand,
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'theme_shop_state': jsonEncode({
      'activeBrand': initialBrand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
  });
  I18n.setLocale(initialLocale);
  // Construct the real services in the real-async zone as well as loading them:
  // their initial serialization futures must not be stranded in fakeAsync.
  final fixture = (await tester.runAsync(() async => _DiaryFixture()))!;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    try {
      // Complete an outstanding transport even if an earlier assertion failed.
      if (!fixture.response.isCompleted) {
        await fixture.completeReview(tester);
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => fixture.ai.drainPendingHistoryWrites().timeout(_asyncTimeout),
      );
    } finally {
      fixture.ai.dispose();
      fixture.diaries.dispose();
      fixture.theme.dispose();
      fixture.transport.close();
      SharedPreferencesStorePlatform.instance = previousStore;
      I18n.setLocale(previousLocale);
      tester.view.reset();
    }
  });
  await tester.runAsync(() async {
    if (fixture.evidenceDirectory?.isNotEmpty ?? false) {
      await loadWeeklyReviewScreenshotFonts().timeout(_asyncTimeout);
    }
    await fixture.theme.loadFromStorage().timeout(_asyncTimeout);
    await fixture.diaries.loadFromStorage().timeout(_asyncTimeout);
    await fixture.ai.loadFromStorage().timeout(_asyncTimeout);
  });
  expect(fixture.theme.brand.id, initialBrand);
  expect(fixture.diaries.entries.single.content, _diaryBody);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: fixture.theme),
        ChangeNotifierProvider<DiaryProvider>.value(value: fixture.diaries),
        ChangeNotifierProvider<AiService>.value(value: fixture.ai),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, child) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, child) => MaterialApp(
            locale: locale.flutterLocale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
              ),
              child: RepaintBoundary(key: fixture.captureKey, child: child!),
            ),
            home: const _DiaryLauncher(),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_openDiaryKey));
  await tester.pumpAndSettle();
  return fixture;
}

class _DiaryLauncher extends StatelessWidget {
  const _DiaryLauncher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: _openDiaryKey,
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: DiaryScreen()),
          ),
        ),
        child: const Text('Open diary'),
      ),
    ),
  );
}

class _DiaryFixture {
  _DiaryFixture() {
    transport = MockClient((request) {
      requestCount++;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/ai/chat');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['user'], contains(_diaryBody));
      return response.future;
    });
    ai.attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'isolated-diary-review-token',
        httpClient: transport,
      ),
    );
    ai.updateFromServerConfig({
      'ai_enabled': true,
      'ai_model': 'diary-review-test',
    });
    ai.addListener(() {
      if (ai.reviewHistory.isNotEmpty && !persisted.isCompleted) {
        persisted.complete();
      }
    });
  }

  final theme = ThemeProvider();
  final diaries = DiaryProvider();
  final ai = AiService();
  final captureKey = GlobalKey();
  final String? evidenceDirectory =
      Platform.environment['DUOYI_THEME_DIALOG_EVIDENCE_DIR'];
  final response = Completer<http.Response>();
  final persisted = Completer<void>();
  late final MockClient transport;
  int requestCount = 0;

  Future<void> captureResult(WidgetTester tester, String phase) async {
    final directory = evidenceDirectory;
    if (directory == null || directory.isEmpty) return;
    // MaterialApp.builder surrounds the Navigator, including its dialog overlay.
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        final png = bytes!;
        final output = File('$directory/diary-ai-result-$phase.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    });
  }

  Future<void> completeReview(WidgetTester tester) async {
    if (!response.isCompleted) {
      response.complete(
        http.Response(
          jsonEncode({'content': _reviewBody}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
    }
    if (requestCount == 0) return;
    // The screen action starts in testWidgets' fake-async zone. Pump its
    // continuations while yielding to the preferences platform work; awaiting
    // this listener inside runAsync alone would strand those continuations.
    for (var frame = 0; frame < 50 && !persisted.isCompleted; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(
      persisted.isCompleted,
      isTrue,
      reason: 'The real AiService must persist its generated diary review',
    );
    await tester.pump();
  }

  Future<List<String>> storedReviews(WidgetTester tester) async {
    final stored = await tester.runAsync(() async {
      await ai.drainPendingHistoryWrites().timeout(_asyncTimeout);
      final preferences = await SharedPreferences.getInstance();
      return preferences.getStringList('ai_review_history') ?? <String>[];
    });
    return stored!;
  }
}
