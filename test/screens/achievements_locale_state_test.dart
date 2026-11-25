import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/achievement_ui_copy.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/screens/achievements_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _captureKey = ValueKey('achievements-capture');
const _context = AchievementContext(
  totalTodos: 10,
  completedTodos: 10,
  longestHabitStreak: 0,
  habitCount: 1,
  focusMinutes: 60,
  focusSessions: 1,
  diaryStreak: 0,
  diaryCount: 1,
  goalsTotal: 1,
  goalsAchieved: 0,
  anniversaries: 0,
  courses: 0,
  notes: 0,
  todayCompletedTodos: 3,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('locale retains route, scroll and full catalog', (tester) async {
    final f = await _Fixture.open(tester);
    final page = tester.element(find.byType(AchievementsScreen));
    final scroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    scroll.jumpTo(370);
    await tester.pump();
    final offset = scroll.pixels;
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(AchievementsScreen)), same(page));
    final retainedScroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(retainedScroll.pixels, offset);
    expect(find.text('Daily and weekly challenges'), findsOneWidget);
    await _reachLastBadge(tester);
    expect(
      find
          .text(AchievementUiCopy.badgeTitle(Achievements.all.last))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await f.close(tester);
  });

  testWidgets(
    'open share follows locale and clipboard uses live catalog copy',
    (tester) async {
      final f = await _Fixture.open(tester);
      final writes = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              writes.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await f.share(tester);
      final dialog = tester.element(find.byType(AlertDialog));
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AlertDialog)), same(dialog));
      expect(find.text('Created with Duoyi'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Copy text'));
      await tester.pumpAndSettle();
      expect(writes.single, contains('# Duoyi achievements'));
      expect(writes.single, contains('First step: Complete your first task'));
      expect(writes.single, isNot(contains('启程')));
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(find.text('成就文案已复制'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '复制文案'));
      await tester.pumpAndSettle();
      expect(writes.last, contains('启程'));
      await f.close(tester);
    },
  );

  testWidgets('copy failure retries and duplicate pending action is blocked', (
    tester,
  ) async {
    final f = await _Fixture.open(tester);
    var calls = 0;
    final pending = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            calls++;
            if (calls == 1) throw PlatformException(code: 'synthetic');
            await pending.future;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await f.share(tester);
    final button = find.widgetWithText(TextButton, '复制文案');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('复制失败，请重试'), findsOneWidget);
    final callback = tester.widget<TextButton>(button).onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(calls, 2);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('成就文案已复制'), findsOneWidget);
    await f.close(tester);
  });

  for (final invalidate in [false, true]) {
    testWidgets(
      'PNG capture ${invalidate ? 'stops after locale changes' : 'shares current image and text'}',
      (tester) async {
        final f = await _Fixture.open(tester);
        final temp = await tester.runAsync(
          () => Directory.systemTemp.createTemp('duoyi-achievement-test-'),
        );
        final pending = Completer<String>();
        var directoryRequests = 0;
        final shares = <Map<Object?, Object?>>[];
        const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
        const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(pathChannel, (call) async {
          directoryRequests++;
          return pending.future;
        });
        messenger.setMockMethodCallHandler(shareChannel, (call) async {
          shares.add(Map<Object?, Object?>.from(call.arguments as Map));
          return 'synthetic-target';
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(pathChannel, null);
          messenger.setMockMethodCallHandler(shareChannel, null);
          await temp!.delete(recursive: true);
        });
        await f.share(tester);
        await tester.tap(find.widgetWithText(FilledButton, '分享 PNG'));
        await tester.pump();
        await tester.runAsync(() async {
          for (var i = 0; i < 100 && directoryRequests == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        expect(directoryRequests, 1);
        if (invalidate) {
          I18n.setLocale(AppLocale.en);
          await tester.pump();
        }
        pending.complete(temp!.path);
        await tester.runAsync(() async {
          for (var i = 0; i < 50 && shares.isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (invalidate) break;
          }
        });
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
        if (invalidate) {
          expect(shares, isEmpty);
          expect(await tester.runAsync(() => temp.list().toList()), isEmpty);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Share PNG'),
                )
                .onPressed,
            isNotNull,
          );
        } else {
          expect(shares, hasLength(1));
          expect(shares.single['text'], contains('# 多仪成就海报'));
          expect(shares.single['originWidth'], greaterThan(0));
          expect(shares.single['originHeight'], greaterThan(0));
          final file = File((shares.single['paths'] as List).single as String);
          final bytes = await tester.runAsync(file.readAsBytes);
          expect(bytes!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
        }
        expect(tester.takeException(), isNull);
        await f.close(tester);
      },
    );
  }

  for (final invalidation in ['reset', 'account', 'replacement', 'covered']) {
    testWidgets('stale share entry cannot open after $invalidation', (
      tester,
    ) async {
      final f = await _Fixture.open(tester);
      final open = tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('成就分享图'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed!;
      if (invalidation == 'reset') f.provider.resetLocalState();
      if (invalidation == 'account') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      }
      if (invalidation == 'replacement') {
        f.current.value = AchievementProvider();
      }
      if (invalidation == 'covered') {
        unawaited(
          f.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered route')),
            ),
          ),
        );
      }
      await tester.pumpAndSettle();
      open();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      if (invalidation == 'covered') {
        expect(find.text('Covered route'), findsOneWidget);
      }
      await f.close(tester);
    });
  }

  for (final invalidation in [
    'account',
    'reset',
    'lock',
    'covered',
    'replacement',
  ]) {
    testWidgets('stale share callbacks cannot act after $invalidation', (
      tester,
    ) async {
      final f = await _Fixture.open(tester);
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') writes++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await f.share(tester);
      final copy = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '复制文案'))
          .onPressed!;
      final close = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '关闭'))
          .onPressed!;
      final png = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '分享 PNG'))
          .onPressed!;
      if (invalidation == 'account') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      }
      if (invalidation == 'reset') f.provider.resetLocalState();
      if (invalidation == 'lock') f.lock.lock();
      if (invalidation == 'covered') {
        unawaited(
          f.navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('New route')),
            ),
          ),
        );
      }
      if (invalidation == 'replacement') {
        f.current.value = AchievementProvider();
      }
      await tester.pumpAndSettle();
      copy();
      png();
      close();
      await tester.pumpAndSettle();
      expect(writes, 0);
      if (invalidation == 'covered') {
        expect(find.text('New route'), findsOneWidget);
      } else {
        expect(find.byType(AlertDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  for (final size in [const Size(320, 844), const Size(568, 320)]) {
    for (final locale in AppLocale.values) {
      testWidgets(
        'full content and share layout ${size.width} ${locale.name} at 1.6x',
        (tester) async {
          final capture =
              Platform.environment['DUOYI_CAPTURE_ACHIEVEMENTS'] == '1';
          if (capture) await loadWeeklyReviewScreenshotFonts();
          I18n.setLocale(locale);
          final f = await _Fixture.open(tester, size: size, textScale: 1.6);
          final stem = '${size.width.toInt()}-${locale.name}';
          if (capture) await _capture(tester, '$stem-top');
          await _reachLastBadge(tester);
          expect(
            find
                .text(AchievementUiCopy.badgeTitle(Achievements.all.last))
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (capture) await _capture(tester, '$stem-tail');
          await f.share(tester);
          expect(tester.takeException(), isNull);
          if (capture) await _capture(tester, '$stem-share');
          await f.close(tester);
        },
      );
    }
  }
}

Future<void> _reachLastBadge(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text(AchievementUiCopy.badgeTitle(Achievements.all.last)),
    500,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 50,
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/achievements-locale-20261015/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _Fixture {
  final provider = AchievementProvider();
  final lock = AppLockProvider();
  final navigator = GlobalKey<NavigatorState>();
  late final current = ValueNotifier<AchievementProvider>(provider);

  static Future<_Fixture> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    final f = _Fixture();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await f.lock.setPin('1234');
    await f.provider.loadFromStorage();
    await f.provider.updateContext(_context);
    await tester.pumpWidget(
      ValueListenableBuilder<AchievementProvider>(
        valueListenable: f.current,
        builder: (context, provider, _) => MultiProvider(
          providers: [
            ChangeNotifierProvider<AchievementProvider>.value(value: provider),
            ChangeNotifierProvider<AppLockProvider>.value(value: f.lock),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            navigatorKey: f.navigator,
            theme: AppBrands.defaultBrand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(key: _captureKey, child: child!),
            ),
            home: const BrandRouteSurface(child: AchievementsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return f;
  }

  Future<void> share(WidgetTester tester) async {
    await tester.tap(
      find.byTooltip(AchievementUiCopy.text('成就分享图', 'Share achievements')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (!identical(current.value, provider)) current.value.dispose();
    current.dispose();
    provider.dispose();
    lock.dispose();
  }
}
