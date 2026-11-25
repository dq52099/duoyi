// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart';
import '../support/weekly_review_screenshot_font.dart';

const _layouts = [
  (name: '200x844-scale2', size: Size(200, 844), scale: 2.0),
  (name: '320x844-scale1', size: Size(320, 844), scale: 1.0),
  (name: '320x844-scale1.6', size: Size(320, 844), scale: 1.6),
  (name: '568x320-scale2', size: Size(568, 320), scale: 2.0),
  (name: '900x900-scale2', size: Size(900, 900), scale: 2.0),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brandId in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in _layouts) {
        final name = '$brandId-${locale.name}-${layout.name}';
        testWidgets('paired More Apps labels and widget route: $name', (
          tester,
        ) async {
          final previousStore = SharedPreferencesStorePlatform.instance;
          final previousShadows = debugDisableShadows;
          final theme = ThemeProvider();
          final preferences = PreferencesProvider();
          final selection = const WidgetDisplayModeSelection(
            mode: 'standard',
            intentId: 'synthetic-more-apps-theme',
            pending: false,
          );
          final store = _TrackingStore({
            'flutter.active_brand': brandId,
            'flutter.${WidgetDisplayModeSelection.storageKey}': selection
                .encode(),
            'flutter.${WidgetDisplayModeSelection.legacyKey}': 'standard',
          });
          SharedPreferences.setMockInitialValues({});
          SharedPreferencesStorePlatform.instance = store;
          I18n.setLocale(locale);
          debugDisableShadows = false;
          final captureKey = GlobalKey();
          try {
            await theme.loadFromStorage();
            expect(theme.brand.id, brandId);
            // Use readable fixture fonts under production family names. Do not
            // substitute a different ThemeData or reduce production text sizes.
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: preferences,
                  ),
                ],
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: RepaintBoundary(key: captureKey, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BrandRouteSurface(
                                child: MoreApplicationsScreen(
                                  visibleBottomNavTabs: [6],
                                ),
                              ),
                            ),
                          ),
                          child: const Text('Open hidden features'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open hidden features'));
            await tester.pumpAndSettle();
            expect(find.byType(BackButton), findsOneWidget);
            await _expectIntroWords(tester);
            await _capture(tester, captureKey, '$name-top');
            await _showGrid(tester);
            expect(find.byType(MoreApplicationButton), findsNWidgets(5));
            _expectDensity(tester, layout.size.width, layout.scale);
            await _capture(tester, captureKey, '$name-bottom');
            _recordLabels(tester, name, brandId);
            await _expectCountContrast(tester, captureKey, name);
            await _showGrid(tester);
            for (final tab in [0, 1, 2, 3, 5]) {
              final button = _button(tab);
              await Scrollable.ensureVisible(
                tester.element(button),
                alignment: 0.5,
              );
              await tester.pumpAndSettle();
              expectReadableControl(tester, button);
            }

            final writesBeforeLocale = store.mutationCount;
            I18n.setLocale(
              locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
            );
            await tester.pumpAndSettle();
            expect(store.mutationCount, writesBeforeLocale);
            expect(find.text(I18n.tr('mine.tile.more_apps')), findsOneWidget);
            await _expectIntroWords(tester);
            await _showGrid(tester);
            expect(find.byType(MoreApplicationButton), findsNWidgets(5));
            _expectDensity(tester, layout.size.width, layout.scale);
            for (final tab in [0, 1, 2, 3, 5]) {
              final button = _button(tab);
              await Scrollable.ensureVisible(
                tester.element(button),
                alignment: 0.5,
              );
              await tester.pumpAndSettle();
              expectReadableControl(tester, button);
            }
            await _capture(tester, captureKey, '$name-switched');
            _recordLabels(tester, '$name-switched', brandId);
            await _expectCountContrast(tester, captureKey, '$name-switched');
            await _showGrid(tester);

            final widgetEntry = _button(5);
            await Scrollable.ensureVisible(
              tester.element(widgetEntry),
              alignment: 0.5,
            );
            await tester.pumpAndSettle();
            await tester.tap(widgetEntry);
            await tester.pumpAndSettle();
            expect(find.byType(WidgetScreen), findsOneWidget);
            expect(find.byType(BackButton), findsOneWidget);
            final widgetState = tester.state(find.byType(WidgetScreen));
            final writesBeforeWidgetLocale = store.mutationCount;
            I18n.setLocale(locale);
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(WidgetScreen)), same(widgetState));
            expect(store.mutationCount, writesBeforeWidgetLocale);
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            expect(find.byType(WidgetScreen), findsNothing);
            expect(find.byType(MoreApplicationsScreen), findsOneWidget);
            await _showGrid(tester);
            expect(find.byType(MoreApplicationButton), findsNWidgets(5));
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            expect(find.byType(MoreApplicationsScreen), findsNothing);
            expect(find.text('Open hidden features'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            theme.dispose();
            preferences.dispose();
            tester.view.reset();
            debugDisableShadows = previousShadows;
            I18n.setLocale(AppLocale.zh);
            SharedPreferences.resetStatic();
            SharedPreferencesStorePlatform.instance = previousStore;
          }
        });
      }
    }
  }
}

Finder _button(int tab) => find.byWidgetPredicate(
  (widget) => widget is MoreApplicationButton && widget.app.tab == tab,
);

Future<void> _expectIntroWords(WidgetTester tester) async {
  if (I18n.current != AppLocale.en) return;
  await _revealFromTop(tester, find.text('Hidden features'));
  for (final copy in [
    'Hidden features',
    'Features hidden from the bottom navigation are still available here.',
  ]) {
    final label = find.text(copy);
    expect(label, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.size.width, greaterThan(0));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(
      paragraph.textScaler.scale(10),
      MediaQuery.textScalerOf(tester.element(label)).scale(10),
    );
    for (final word in RegExp(r'[A-Za-z]+').allMatches(copy)) {
      expect(
        paragraph.getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        ),
        hasLength(1),
        reason: 'Intro words must remain whole: ${word.group(0)}',
      );
    }
  }
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _revealFromTop(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
  await tester.pumpAndSettle();
}

Future<void> _showGrid(WidgetTester tester) async {
  await _revealFromTop(tester, find.byType(GridView));
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
  scroll.position.jumpTo(scroll.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void _expectDensity(WidgetTester tester, double width, double scale) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  if (width == 200) {
    expect(delegate.crossAxisCount, 1);
  } else if (width == 900) {
    expect(delegate.crossAxisCount, 3);
  } else if (width == 320 && scale == 1 && I18n.current == AppLocale.zh) {
    expect(delegate.crossAxisCount, 2);
  }
}

void _recordLabels(WidgetTester tester, String name, String brandId) {
  final directory = Platform.environment['DUOYI_MORE_APPS_EVIDENCE_DIR'];
  if (directory == null) return;
  final labels = <Map<String, Object>>[];
  for (final tab in [0, 1, 2, 3, 5]) {
    final button = _button(tab);
    final text = find.descendant(of: button, matching: find.byType(Text));
    final label = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    labels.add({
      'tab': tab,
      'text': tester.widget<Text>(text).data!,
      'didExceedMaxLines': label.didExceedMaxLines,
      'labelWidth': label.size.width,
      'buttonWidth': tester.getSize(button).width,
      'buttonHeight': tester.getSize(button).height,
      'textDirection': label.textDirection.name,
    });
  }
  final file = File('$directory/$name.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${jsonEncode({'name': name, 'brandId': brandId, 'locale': I18n.current.name, 'labels': labels})}\n',
  );
}

Future<void> _expectCountContrast(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final counter = find.text(
    I18n.current == AppLocale.en ? '5 features' : '5 个',
  );
  await _revealFromTop(tester, counter);
  await Scrollable.ensureVisible(tester.element(counter), alignment: 0.5);
  await tester.pumpAndSettle();
  final container = find
      .ancestor(of: counter, matching: find.byType(Container))
      .first;
  final rect = tester.getRect(container);
  final labelRect = tester.getRect(counter);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: counter, matching: find.byType(RichText)),
  );
  final foreground = paragraph.text.style!.color!;
  final pixels = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      return (
        data: (await picture.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        width: picture.width,
        height: picture.height,
      );
    } finally {
      picture.dispose();
    }
  });
  final samples = <Map<String, Object>>[];
  for (final fraction in [0.25, 0.5, 0.75]) {
    final point = Offset(
      rect.left + rect.width * fraction,
      (rect.top + labelRect.top) / 2,
    );
    expect(rect.contains(point), isTrue);
    expect(labelRect.contains(point), isFalse);
    final x = point.dx.floor();
    final y = point.dy.floor();
    expect(x, inInclusiveRange(0, pixels!.width - 1));
    expect(y, inInclusiveRange(0, pixels.height - 1));
    final offset = (y * pixels.width + x) * 4;
    expect(pixels.data.getUint8(offset + 3), 255);
    final background = Color.fromARGB(
      255,
      pixels.data.getUint8(offset),
      pixels.data.getUint8(offset + 1),
      pixels.data.getUint8(offset + 2),
    );
    samples.add({
      'foreground': foreground.toARGB32().toRadixString(16),
      'rasterBackground': background.toARGB32().toRadixString(16),
      'contrastRatio': appContrastRatio(
        Color.alphaBlend(foreground, background),
        background,
      ),
    });
  }
  final directory = Platform.environment['DUOYI_MORE_APPS_EVIDENCE_DIR'];
  if (directory != null) {
    final file = File('$directory/$name-count.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode({'name': name, 'samples': samples})}\n',
    );
  }
  for (final sample in samples) {
    expect(
      sample['contrastRatio'],
      greaterThanOrEqualTo(4.5),
      reason: '$name count pill on actual painted padding: $sample',
    );
  }
  if (I18n.current == AppLocale.en) {
    final heading = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('Features'),
        matching: find.byType(RichText),
      ),
    );
    expect(
      heading.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 8),
      ),
      hasLength(1),
      reason: 'The Features heading must have room for one complete word.',
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final batch = Platform.environment['DUOYI_MORE_APPS_SCREENSHOT_BATCH'];
  if (batch == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'evidence/screenshots/more-apps-theme-20261020/$batch/$name.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

class _TrackingStore extends InMemorySharedPreferencesStore {
  _TrackingStore(super.data) : super.withData();

  int mutationCount = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutationCount++;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutationCount++;
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutationCount++;
    return super.clear();
  }
}
