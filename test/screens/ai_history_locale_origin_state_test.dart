import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/screens/ai_history_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _boundaryKey = ValueKey('history_capture');
const _historyKey = 'ai_review_history';
const _platformHistoryKey = 'flutter.$_historyKey';
const _reviewId = 'locale-origin-review';
const _secondReviewId = 'locale-origin-second-review';
const _reviewBody = 'Literal AI body 原文 stays exactly as saved.';
const _secondReviewBody = 'Second literal review body 保留.';
const _legacySummary = 'this week数据：完成 2 / 3 项待办，专注 45 分钟，习惯连续打卡 4 天。';
const _localizedEnglishSummary =
    'this week summary: tasks done 2 / 3, focus 45 min, longest habit streak 4 days.';

Finder _reviewToggle(String id) =>
    find.byKey(ValueKey<String>('ai_history_toggle_$id'));

Finder _reviewMenu(String id) =>
    find.byKey(ValueKey<String>('ai_history_menu_$id'));

Finder _clearButton(String tooltip) => find.ancestor(
  of: find.byTooltip(tooltip),
  matching: find.byType(IconButton),
);

void main() {
  setUpAll(loadWeeklyReviewScreenshotFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final size in [const Size(320, 844), const Size(568, 320)]) {
        testWidgets(
          'clear dialog retains live brand $initialBrand ${locale.name} ${size.width}',
          (tester) async {
            I18n.setLocale(locale);
            final fixture = await _mountHistory(
              tester,
              [_review()],
              size: size,
              textScale: 2,
              initialBrand: initialBrand,
            );
            final history = find.byType(AiHistoryScreen);
            final historyState = tester.state(history);
            await tester.tap(_clearButton(I18n.tr('ai_history.clear.tooltip')));
            await tester.pumpAndSettle();
            final dialog = find.byType(AppDialog);
            final dialogElement = tester.element(dialog);
            final route = ModalRoute.of(dialogElement);
            expect(
              appSurfaceStyleOf(dialogElement),
              AppBrands.byId(initialBrand).theme.extension<AppSurfaceStyle>(),
            );
            final target = initialBrand == 'defaultBrand'
                ? 'liquidGlass'
                : 'defaultBrand';
            final changed = await tester.runAsync(
              () => fixture.theme.setBrand(target),
            );
            expect(changed, isTrue);
            await tester.pumpAndSettle();
            await _captureLiveClear(tester, initialBrand, locale, size);
            expect(tester.element(dialog), same(dialogElement));
            expect(ModalRoute.of(tester.element(dialog)), same(route));
            expect(tester.state(history), same(historyState));
            expect(fixture.ai.reviewHistory.single.id, _reviewId);
            expect(
              appSurfaceStyleOf(tester.element(dialog)),
              AppBrands.byId(target).theme.extension<AppSurfaceStyle>(),
            );
            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            expect(tester.element(dialog), same(dialogElement));
            await tester.tap(
              find.widgetWithText(TextButton, I18n.tr('action.cancel')),
            );
            await tester.pumpAndSettle();
            expect(fixture.ai.reviewHistory.single.id, _reviewId);
            expect(fixture.store.historyWriteAttempts, 0);
            await tester.tap(_clearButton(I18n.tr('ai_history.clear.tooltip')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(
                FilledButton,
                I18n.tr('ai_history.clear.action'),
              ),
            );
            await tester.pumpAndSettle();
            expect(fixture.ai.reviewHistory, isEmpty);
            expect(await fixture.storedReviews(), isEmpty);
            expect(fixture.store.historyWriteAttempts, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'legacy weekly summary and AI body refresh on the branded history route',
    (tester) async {
      final fixture = await _mountHistory(tester, [_review()]);
      final history = find.byType(AiHistoryScreen);
      final state = tester.state<State<AiHistoryScreen>>(history);
      final route = ModalRoute.of(tester.element(history));

      expect(find.byType(BrandRouteSurface), findsOneWidget);
      expect(
        find.text('本周数据：完成 2 / 3 项待办，专注 45 分钟，习惯连续打卡 4 天。'),
        findsOneWidget,
      );
      expect(find.text(_reviewBody), findsNothing);
      expect(find.byTooltip('展开回顾'), findsOneWidget);

      await tester.tap(_reviewToggle(_reviewId));
      await tester.pumpAndSettle();
      expect(find.text(_reviewBody), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state<State<AiHistoryScreen>>(history), same(state));
      expect(ModalRoute.of(tester.element(history)), same(route));
      expect(find.text(_localizedEnglishSummary), findsOneWidget);
      expect(find.text(_reviewBody), findsOneWidget);
      expect(find.byTooltip('Collapse review'), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(tester.state<State<AiHistoryScreen>>(history), same(state));
      expect(find.text(_reviewBody), findsOneWidget);
      expect(find.byTooltip('收起回顾'), findsOneWidget);
      expect(fixture.ai.reviewHistory.single.content, _reviewBody);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history menus, copy, delete, clear tooltip, and confirmation follow locale',
    (tester) async {
      final clipboardWrites = _installClipboardSpy(tester);
      final fixture = await _mountHistory(tester, [
        _review(),
        _review(
          id: _secondReviewId,
          content: _secondReviewBody,
          summary: 'last week数据：完成 1 / 2 项待办，专注 30 分钟，习惯连续打卡 3 天。',
        ),
      ]);
      final history = find.byType(AiHistoryScreen);
      final route = ModalRoute.of(tester.element(history));

      expect(find.byTooltip('清空历史'), findsOneWidget);
      final menuButton = _reviewMenu(_reviewId);
      final chineseMenuTooltip = MaterialLocalizations.of(
        tester.element(history),
      ).showMenuTooltip;
      expect(find.byTooltip(chineseMenuTooltip), findsNWidgets(2));

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final englishMenuTooltip = MaterialLocalizations.of(
        tester.element(history),
      ).showMenuTooltip;
      expect(englishMenuTooltip, isNot(chineseMenuTooltip));
      expect(find.byTooltip(englishMenuTooltip), findsNWidgets(2));
      expect(find.byTooltip('Clear history'), findsOneWidget);
      expect(ModalRoute.of(tester.element(history)), same(route));

      await tester.tap(menuButton);
      await tester.pumpAndSettle();
      final menuRoute = ModalRoute.of(tester.element(find.text('Copy')));
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(ModalRoute.of(tester.element(find.text('复制'))), same(menuRoute));
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(clipboardWrites, [_reviewBody]);
      expect(find.text('已复制'), findsOneWidget);

      await tester.tap(_reviewMenu(_reviewId));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(fixture.ai.reviewHistory.map((entry) => entry.id), [
        _secondReviewId,
      ]);
      expect(find.text(_reviewBody), findsNothing);
      expect(_reviewToggle(_secondReviewId), findsOneWidget);

      await tester.tap(_clearButton('清空历史'));
      await tester.pumpAndSettle();
      expect(find.text('清空全部回顾?'), findsOneWidget);
      expect(find.text('本地保留的 AI 回顾将被删除，无法恢复'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
      final dialogRoute = ModalRoute.of(tester.element(find.text('清空')));

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        ModalRoute.of(tester.element(find.text('Clear'))),
        same(dialogRoute),
      );
      expect(find.text('Clear all reviews?'), findsOneWidget);
      expect(
        find.text(
          'Locally saved AI reviews will be deleted and cannot be recovered',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(fixture.ai.reviewHistory, isEmpty);
      expect(find.text('还没有 AI 回顾\n在"我的"页生成一份吧'), findsOneWidget);
      expect(await fixture.storedReviews(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale menu and clear callbacks cannot act after same-owner history reset and reload',
    (tester) async {
      final fixture = await _mountHistory(tester, [_review()]);

      await tester.tap(_reviewMenu(_reviewId));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      fixture.ai.resetLocalState();
      await tester.runAsync(fixture.ai.loadFromStorage);
      await tester.pumpAndSettle();
      expect(fixture.ai.reviewHistory.single.id, _reviewId);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(fixture.ai.reviewHistory.single.id, _reviewId);

      final clear = tester.widget<IconButton>(_clearButton('清空历史'));
      final staleClear = clear.onPressed!;
      fixture.ai.resetLocalState();
      await tester.runAsync(fixture.ai.loadFromStorage);
      staleClear();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.ai.reviewHistory.single.id, _reviewId);

      await tester.tap(_clearButton('清空历史'));
      await tester.pumpAndSettle();
      expect(find.text('清空全部回顾?'), findsOneWidget);
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '清空'))
          .onPressed!;
      fixture.ai.resetLocalState();
      await tester.runAsync(fixture.ai.loadFromStorage);
      await tester.pumpAndSettle();
      expect(fixture.ai.reviewHistory.single.id, _reviewId);

      confirm();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.ai.reviewHistory.single.id, _reviewId);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.ai.reviewHistory.single.id, _reviewId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear write failure exposes a retry that asks for confirmation again',
    (tester) async {
      final fixture = await _mountHistory(tester, [_review()]);
      fixture.store.rejectNextHistoryWrite = true;

      await tester.tap(_clearButton('清空历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();

      expect(fixture.ai.reviewHistory, isEmpty);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('重试'), findsOneWidget);
      expect(fixture.store.historyWriteAttempts, 1);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('清空全部回顾?'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);

      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(fixture.ai.reviewHistory, isEmpty);
      expect(fixture.store.historyWriteAttempts, 2);
      expect(await fixture.storedReviews(), isEmpty);
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open history controls reject replacement auth and service owners',
    (tester) async {
      final fixture = await _mountHistory(tester, [_review()]);
      await tester.tap(_clearButton('清空历史'));
      await tester.pumpAndSettle();
      final confirm = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '清空'))
          .onPressed!;
      fixture.replaceAuth();
      await tester.pumpAndSettle();
      confirm();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.ai.reviewHistory, hasLength(1));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(_reviewMenu(_reviewId));
      await tester.pumpAndSettle();
      final replacement = AiService();
      await tester.runAsync(replacement.loadFromStorage);
      fixture.replaceAi(replacement);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(replacement.reviewHistory, hasLength(1));
      expect(fixture.store.historyWriteAttempts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('covered or locked history confirmation cannot mutate records', (
    tester,
  ) async {
    final fixture = await _mountHistory(tester, [_review()]);
    await tester.tap(_clearButton('清空历史'));
    await tester.pumpAndSettle();
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '清空'))
        .onPressed!;
    fixture.navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Covered route')),
      ),
    );
    await tester.pumpAndSettle();
    confirm();
    await tester.pumpAndSettle();
    expect(find.text('Covered route'), findsOneWidget);
    expect(fixture.ai.reviewHistory, hasLength(1));
    fixture.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    fixture.lock.setLocked(true);
    await tester.pump();
    confirm();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(fixture.store.historyWriteAttempts, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history locale switch preserves scroll offset and expanded entry',
    (tester) async {
      final fixture = await _mountHistory(tester, [
        for (var i = 0; i < 15; i++) _review(id: 'scroll-$i'),
      ]);
      await tester.tap(_reviewToggle('scroll-0'));
      await tester.pumpAndSettle();
      final historyState = tester.state(find.byType(AiHistoryScreen));
      final list = find
          .descendant(
            of: find.byType(AiHistoryScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      final offset = tester.state<ScrollableState>(list).position.pixels;
      expect(offset, greaterThan(0));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AiHistoryScreen)), same(historyState));
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        closeTo(offset, 0.1),
      );
      await tester.drag(list, const Offset(0, 1600));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(_reviewToggle('scroll-0')).tooltip,
        'Collapse review',
      );
      expect(fixture.ai.reviewHistory, hasLength(15));
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in [AppLocale.zh, AppLocale.en]) {
    for (final size in [const Size(320, 844), const Size(568, 320)]) {
      testWidgets('History layout ${locale.name} ${size.width.toInt()} 1.6x', (
        tester,
      ) async {
        if (Platform.environment['DUOYI_CAPTURE_WEEKLY_REVIEW'] == '1') {
          await loadWeeklyReviewScreenshotFonts();
        }
        I18n.setLocale(locale);
        await _mountHistory(tester, [_review()], size: size, textScale: 1.6);
        await tester.tap(_reviewToggle(_reviewId));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _captureHistory(tester, locale, size, 'body');
        await tester.tap(_reviewMenu(_reviewId));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _captureHistory(tester, locale, size, 'menu');
        Navigator.of(
          tester.element(find.text(I18n.tr('ai_history.copy'))),
        ).pop();
        await tester.pumpAndSettle();
        await tester.tap(_clearButton(I18n.tr('ai_history.clear.tooltip')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _captureHistory(tester, locale, size, 'clear');
      });
    }
  }
}

AiReviewEntry _review({
  String id = _reviewId,
  String content = _reviewBody,
  String summary = _legacySummary,
}) => AiReviewEntry(
  id: id,
  createdAt: DateTime(2026, 10, 14, 9),
  content: content,
  summary: summary,
);

List<String> _installClipboardSpy(WidgetTester tester) {
  final writes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        writes.add(arguments['text'] as String);
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
  return writes;
}

Future<_Fixture> _mountHistory(
  WidgetTester tester,
  List<AiReviewEntry> entries, {
  Size size = const Size(390, 844),
  double textScale = 1,
  String? initialBrand,
}) async {
  final previousStore = SharedPreferencesStorePlatform.instance;
  final store = _HistoryStore(entries, initialBrand: initialBrand);
  SharedPreferencesStorePlatform.instance = store;
  final ai = AiService();
  await tester.runAsync(ai.loadFromStorage);
  final theme = initialBrand == null
      ? ThemeProvider()
      : (await tester.runAsync(() async {
          final loaded = ThemeProvider();
          await loaded.loadFromStorage();
          return loaded;
        }))!;
  final fixture = _Fixture(
    ai: ai,
    theme: theme,
    store: store,
    navigatorKey: GlobalKey<NavigatorState>(),
    messengerKey: GlobalKey<ScaffoldMessengerState>(),
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
    theme.dispose();
    SharedPreferencesStorePlatform.instance = previousStore;
    tester.view.reset();
  });

  await tester.pumpWidget(
    AnimatedBuilder(
      animation: Listenable.merge([fixture, theme]),
      builder: (_, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AiService>.value(value: fixture.ai),
          ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
          ChangeNotifierProvider<AppLockProvider>.value(value: fixture.lock),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) => MaterialApp(
            navigatorKey: fixture.navigatorKey,
            scaffoldMessengerKey: fixture.messengerKey,
            locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(key: _boundaryKey, child: child!),
            ),
            home: const _HistoryLauncher(),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey<String>('open-ai-history')));
  await tester.pumpAndSettle();
  return fixture;
}

class _HistoryLauncher extends StatelessWidget {
  const _HistoryLauncher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const ValueKey<String>('open-ai-history'),
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: AiHistoryScreen()),
          ),
        ),
        child: const Text('Open history'),
      ),
    ),
  );
}

class _Fixture extends ChangeNotifier {
  _Fixture({
    required this.ai,
    required this.theme,
    required this.store,
    required this.navigatorKey,
    required this.messengerKey,
  });

  AiService ai;
  AuthProvider auth = AuthProvider();
  final _TestLock lock = _TestLock();
  final List<ChangeNotifier> retired = [];
  void replaceAuth() {
    retired.add(auth);
    auth = AuthProvider();
    notifyListeners();
  }

  void replaceAi(AiService replacement) {
    retired.add(ai);
    ai = replacement;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final item in retired) {
      item.dispose();
    }
    ai.dispose();
    auth.dispose();
    lock.dispose();
    super.dispose();
  }

  final ThemeProvider theme;
  final _HistoryStore store;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  Future<List<String>> storedReviews() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_historyKey) ?? const [];
  }
}

class _HistoryStore extends InMemorySharedPreferencesStore {
  _HistoryStore(List<AiReviewEntry> entries, {String? initialBrand})
    : super.withData({
        _platformHistoryKey: entries
            .map((entry) => jsonEncode(entry.toJson()))
            .toList(),
        if (initialBrand != null) ...{
          'flutter.active_brand': initialBrand,
          'flutter.theme_shop_state': jsonEncode({
            'activeBrand': initialBrand,
            'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
          }),
          'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        },
      });

  bool rejectNextHistoryWrite = false;
  int historyWriteAttempts = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key == _platformHistoryKey) {
      historyWriteAttempts++;
      if (rejectNextHistoryWrite) {
        rejectNextHistoryWrite = false;
        return Future<bool>.value(false);
      }
    }
    return super.setValue(valueType, key, value);
  }
}

Future<void> _captureLiveClear(
  WidgetTester tester,
  String initialBrand,
  AppLocale locale,
  Size size,
) async {
  final output = Platform.environment['DUOYI_LIVE_CLEAR_CAPTURE'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
    );
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '$output/$initialBrand-${locale.name}-${size.width.toInt()}x${size.height.toInt()}.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _captureHistory(
  WidgetTester tester,
  AppLocale locale,
  Size size,
  String state,
) async {
  if (Platform.environment['DUOYI_CAPTURE_WEEKLY_REVIEW'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'evidence/screenshots/weekly-review-20261015/history-${locale.name}-${size.width.toInt()}x${size.height.toInt()}-$state-1.6.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _TestLock extends AppLockProvider {
  bool locked = false;
  @override
  bool get isLocked => locked;
  void setLocked(bool value) {
    locked = value;
    notifyListeners();
  }
}
