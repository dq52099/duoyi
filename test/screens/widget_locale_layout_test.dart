import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

final _previews = <String, Widget Function(WidgetDisplayMode)>{
  'todo': (mode) => WidgetPreviewCard.todo(displayMode: mode),
  'focus': (mode) => WidgetPreviewCard.focus(displayMode: mode),
  'habit': (mode) => WidgetPreviewCard.habit(displayMode: mode),
  'calendar': (mode) => WidgetPreviewCard.calendar(displayMode: mode),
  'schedule': (mode) => WidgetPreviewCard.schedule(displayMode: mode),
  'goal': (mode) => WidgetPreviewCard.goal(displayMode: mode),
  'course': (mode) => WidgetPreviewCard.course(displayMode: mode),
  'note': (mode) => WidgetPreviewCard.note(displayMode: mode),
  'anniversary': (mode) => WidgetPreviewCard.anniversary(displayMode: mode),
  'diary': (mode) => WidgetPreviewCard.diary(displayMode: mode),
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('preview follows independent widget background and skin', (
    tester,
  ) async {
    final theme = await _prepare(tester, dark: true);
    await theme.unlockCardSkin('mint_card');
    await theme.setWidgetBackgroundBrand('defaultBrand');
    await theme.setWidgetCardSkin('mint_card');
    final screenshotKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        theme,
        RepaintBoundary(
          key: screenshotKey,
          child: const WidgetPreviewCard.focus(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byType(WidgetPreviewCard);
    final previewTheme = find.descendant(
      of: preview,
      matching: find.byType(Theme),
    );
    final payload = HomeWidgetThemePayload.fromThemeProvider(theme);
    expect(payload.cardSkinId, 'mint_card');
    expect(theme.activeCardSkin.id, 'plain_card');
    expect(
      tester.widget<Theme>(previewTheme).data.colorScheme.primary,
      payload.primary,
    );
    expect(
      tester.widget<Theme>(previewTheme).data.colorScheme.onSurface,
      payload.text,
    );
    expect(
      tester.widget<Theme>(previewTheme).data.brightness,
      Brightness.light,
    );
    final appTheme = Theme.of(tester.element(find.byKey(screenshotKey)));
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.colorScheme.onSurface, isNot(payload.text));
    final sampleTitle = find.text(
      WidgetUiCopy.previewSampleBadge(
        WidgetUiCopy.previewTitle(WidgetPreviewKind.focus),
      ),
    );
    expect(sampleTitle, findsOneWidget);
    final titleRichText = tester.widget<RichText>(
      find.descendant(of: sampleTitle, matching: find.byType(RichText)),
    );
    expect(titleRichText.text.style?.color, payload.text);
    final root = tester.widget<Container>(
      find.ancestor(of: previewTheme, matching: find.byType(Container)).first,
    );
    final decoration = root.decoration! as BoxDecoration;
    expect(decoration.color, payload.background);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(payload.cornerRadiusDp.toDouble()),
    );
    await theme.setWidgetCardSkin('plain_card');
    await tester.pumpAndSettle();
    final updated =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: previewTheme,
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(updated.border, isNull);
    expect(updated.borderRadius, BorderRadius.circular(16));
    expect(tester.takeException(), isNull);
    await _capture(
      tester,
      screenshotKey,
      'independent-light-widget-on-dark-app',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final mode in WidgetDisplayMode.values) {
        final name = '${locale.name}-${dark ? 'dark' : 'light'}-${mode.id}';
        testWidgets('all ten widget previews fit 320 / 1.6: $name', (
          tester,
        ) async {
          I18n.setLocale(locale);
          final theme = await _prepare(tester, dark: dark);
          final keys = {for (final kind in _previews.keys) kind: GlobalKey()};
          await tester.pumpWidget(
            _app(
              theme,
              SingleChildScrollView(
                child: Column(
                  children: [
                    for (final entry in _previews.entries)
                      RepaintBoundary(
                        key: keys[entry.key],
                        child: ColoredBox(
                          color: theme.brand.theme.colorScheme.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: entry.value(mode),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(WidgetPreviewCard), findsNWidgets(10));
          if (locale == AppLocale.en) _expectEnglishCopy(tester);

          for (final entry in keys.entries) {
            final finder = find.byKey(entry.value);
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: entry.key);
            expect(tester.getSize(finder).width, 320);
            if (mode != WidgetDisplayMode.compact) {
              final navigation = find.descendant(
                of: finder,
                matching: find.byKey(
                  const ValueKey('widget_preview_navigation'),
                ),
              );
              expect(navigation, findsOneWidget);
              for (final label in WidgetUiCopy.previewNavLabels) {
                final text = find.descendant(
                  of: navigation,
                  matching: find.text(label),
                );
                final paragraph = tester.renderObject<RenderParagraph>(text);
                expect(tester.widget<Text>(text).softWrap, isFalse);
                expect(
                  paragraph.size.width + 0.5,
                  greaterThanOrEqualTo(
                    paragraph.getMaxIntrinsicWidth(double.infinity),
                  ),
                  reason:
                      '${entry.key}: navigation label $label must fit intact',
                );
              }
            }
            if (mode == WidgetDisplayMode.standard) {
              await _capture(tester, entry.value, '${entry.key}-$name');
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('standalone previews react to language changes', (tester) async {
    final theme = await _prepare(tester);
    await tester.pumpWidget(_app(theme, const WidgetPreviewCard.habit()));
    await tester.pumpAndSettle();
    expect(find.text('今日习惯'), findsWidgets);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    _expectEnglishCopy(tester);
    expect(find.text('80%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.text('今日习惯'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('catalog changes language without resetting style or category', (
    tester,
  ) async {
    final theme = await _prepare(tester);
    final catalogKey = GlobalKey();
    await tester.pumpWidget(
      _app(
        theme,
        RepaintBoundary(key: catalogKey, child: const WidgetScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('生活'));
    await tester.tap(find.text('生活'));
    await tester.pumpAndSettle();
    final categoryFinder = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetCategory>,
    );
    expect(
      tester.widget<SegmentedButton<WidgetCategory>>(categoryFinder).selected,
      {WidgetCategory.life},
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    final modeFinder = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetDisplayMode>,
    );
    await tester.ensureVisible(modeFinder);
    final detailedModeLabel = find
        .descendant(of: modeFinder, matching: find.textContaining('详细'))
        .first;
    await tester.tap(detailedModeLabel);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SegmentedButton<WidgetDisplayMode>>(modeFinder).selected,
      {WidgetDisplayMode.detailed},
    );
    final visibleKinds = tester
        .widgetList<WidgetPreviewCard>(find.byType(WidgetPreviewCard))
        .length;
    expect(visibleKinds, lessThan(10));
    expect(visibleKinds, greaterThan(0));

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    _expectEnglishCopy(tester);
    expect(
      tester.widget<SegmentedButton<WidgetCategory>>(categoryFinder).selected,
      {WidgetCategory.life},
    );
    expect(
      tester.widget<SegmentedButton<WidgetDisplayMode>>(modeFinder).selected,
      {WidgetDisplayMode.detailed},
    );
    expect(find.byType(WidgetPreviewCard), findsNWidgets(visibleKinds));
    expect(find.text(WidgetDisplayMode.detailed.description), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, catalogKey, 'catalog-life-detailed-en');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'account cleanup keeps a pending saved style read from restoring old data',
    (tester) async {
      final store = _GatedReadPreferencesStore({
        'flutter.duoyi_widget_display_mode': 'detailed',
      });
      SharedPreferencesStorePlatform.instance = store;
      final theme = ThemeProvider();
      addTearDown(theme.dispose);

      await tester.pumpWidget(_app(theme, const WidgetScreen()));
      await store.readStarted.future;

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

      final cleanup = AccountLocalDataCleaner.clearSharedPreferences();
      await tester.pump();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

      store.releaseRead.complete();
      await tester.pump();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});

      await cleanup;
      await tester.pumpAndSettle();

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});
      expect(
        (await SharedPreferences.getInstance()).getString(
          'duoyi_widget_display_mode',
        ),
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await AccountPreferenceWrites.waitForBoundary();
    },
  );

  testWidgets('stale style retry cannot overwrite a newer selected style', (
    tester,
  ) async {
    final store = _RejectingWidgetModePreferencesStore()
      ..rejectNextModeWrite = true;
    SharedPreferencesStorePlatform.instance = store;
    final theme = ThemeProvider();
    addTearDown(theme.dispose);

    await tester.pumpWidget(_app(theme, const WidgetScreen()));
    await tester.pumpAndSettle();

    final modeSelector = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<WidgetDisplayMode>,
    );
    await tester.tap(
      find.descendant(
        of: modeSelector,
        matching: find.textContaining(WidgetDisplayMode.detailed.label),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBarAction), findsOneWidget);
    final staleRetry = tester
        .widget<SnackBarAction>(find.byType(SnackBarAction))
        .onPressed;

    await tester.tap(
      find.descendant(
        of: modeSelector,
        matching: find.textContaining(WidgetDisplayMode.compact.label),
      ),
    );
    await tester.pumpAndSettle();
    expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});
    expect(
      (await SharedPreferences.getInstance()).getString(
        'duoyi_widget_display_mode',
      ),
      WidgetDisplayMode.compact.id,
    );

    staleRetry();
    await tester.pumpAndSettle();

    expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});
    expect(
      (await SharedPreferences.getInstance()).getString(
        'duoyi_widget_display_mode',
      ),
      WidgetDisplayMode.compact.id,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed style save restores the saved mode after a delayed initial load',
    (tester) async {
      final store = _GatedReadPreferencesStore({
        'flutter.duoyi_widget_display_mode': 'detailed',
      })..rejectNextModeWrite = true;
      SharedPreferencesStorePlatform.instance = store;
      final theme = ThemeProvider();
      addTearDown(theme.dispose);

      await tester.pumpWidget(_app(theme, const WidgetScreen()));
      await store.readStarted.future;

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.standard});
      final modeSelector = find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      );
      await tester.tap(
        find.descendant(
          of: modeSelector,
          matching: find.textContaining(WidgetDisplayMode.compact.label),
        ),
      );
      await tester.pump();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.compact});

      store.releaseRead.complete();
      await tester.pumpAndSettle();

      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
      expect(
        (await SharedPreferences.getInstance()).getString(
          'duoyi_widget_display_mode',
        ),
        WidgetDisplayMode.detailed.id,
      );
      expect(find.byType(SnackBarAction), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Set<WidgetDisplayMode> _selectedDisplayMode(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetDisplayMode>>(
      find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      ),
    )
    .selected;

class _GatedReadPreferencesStore extends InMemorySharedPreferencesStore {
  _GatedReadPreferencesStore(super.data) : super.withData();

  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool rejectNextModeWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_widget_display_mode' && rejectNextModeWrite) {
      rejectNextModeWrite = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (!readStarted.isCompleted) {
      readStarted.complete();
      await releaseRead.future;
    }
    return super.getAll();
  }
}

class _RejectingWidgetModePreferencesStore
    extends InMemorySharedPreferencesStore {
  _RejectingWidgetModePreferencesStore() : super.withData({});

  bool rejectNextModeWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_widget_display_mode' && rejectNextModeWrite) {
      rejectNextModeWrite = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

Future<ThemeProvider> _prepare(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  SharedPreferences.setMockInitialValues({
    'active_brand': dark ? 'starRail' : 'defaultBrand',
  });
  final theme = ThemeProvider();
  await theme.loadFromStorage();
  addTearDown(theme.dispose);
  return theme;
}

Widget _app(ThemeProvider provider, Widget child) {
  final theme = provider.brand.theme;
  final fonts = theme.textTheme.apply(
    fontFamily: 'DuoyiScreenshotLatin',
    fontFamilyFallback: const ['DuoyiScreenshot'],
  );
  return ChangeNotifierProvider<ThemeProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: theme.copyWith(textTheme: fonts, primaryTextTheme: fonts),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 844),
          textScaler: TextScaler.linear(1.6),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void _expectEnglishCopy(WidgetTester tester) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final labels = <String>[
    for (final widget in tester.widgetList<Text>(find.byType(Text)))
      widget.data ?? widget.textSpan?.toPlainText() ?? '',
    for (final widget in tester.widgetList<Tooltip>(find.byType(Tooltip)))
      widget.message ?? widget.richMessage?.toPlainText() ?? '',
  ];
  expect(labels.where(chinese.hasMatch), isEmpty);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_WIDGET_LOCALE_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '${Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR'] ?? 'evidence/screenshots/widget-locale-20261006'}/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}
