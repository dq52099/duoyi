// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/rendered_control_contrast.dart';
import '../support/widget_polish_screenshot_font.dart';

const _widgetChannel = MethodChannel('duoyi/widgets');
const _narrow = Size(320, 844);
const _landscape = Size(568, 320);
const _tablet = Size(1024, 900);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = true;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = null;
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
        'gallery remains readable: ${locale.name} / ${dark ? 'dark' : 'light'}',
        (tester) async {
          I18n.setLocale(locale);
          final fixture = await _GalleryFixture.mount(
            tester,
            viewport: _narrow,
            textScale: 1.6,
            dark: dark,
          );
          final screen = find.byType(WidgetScreen);
          final screenState = tester.state(screen);

          expect(find.text(WidgetUiCopy.previewHeaderTitle), findsNothing);
          await _expectViewportAndControls(
            tester,
            fixture,
            viewport: _narrow,
            locale: locale,
            textScale: 1.6,
          );
          if (locale == AppLocale.zh && !dark) {
            await _scrollGalleryToTop(tester);
            await _captureIfRequested(
              tester,
              fixture.captureKey,
              'gallery-zh-light-top-controls.png',
            );
          }
          if (locale == AppLocale.en && !dark) {
            await _scrollGalleryToTop(tester);
            await _captureIfRequested(
              tester,
              fixture.captureKey,
              'gallery-en-light-top-controls.png',
            );
          }

          await _expectFirstGalleryCard(tester, viewport: _narrow);
          await _captureIfRequested(
            tester,
            fixture.captureKey,
            'gallery-${locale.name}-${dark ? 'dark' : 'light'}-first-add.png',
          );

          await fixture.resize(tester, viewport: _landscape, textScale: 1.6);
          await _expectViewportAndControls(
            tester,
            fixture,
            viewport: _landscape,
            locale: locale,
            textScale: 1.6,
          );
          await _expectFirstGalleryCard(tester, viewport: _landscape);

          await fixture.resize(tester, viewport: _tablet, textScale: 1);
          await _expectViewportAndControls(
            tester,
            fixture,
            viewport: _tablet,
            locale: locale,
            textScale: 1,
          );
          await _expectFirstGalleryCard(tester, viewport: _tablet);
          expect(tester.state(screen), same(screenState));
          if (locale == AppLocale.zh && !dark) {
            await _scrollGalleryToTop(tester);
            await _captureIfRequested(
              tester,
              fixture.captureKey,
              'gallery-tablet-zh-light-top-controls.png',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final locale in AppLocale.values) {
    testWidgets('glass gallery remains readable: ${locale.name}', (
      tester,
    ) async {
      I18n.setLocale(locale);
      final fixture = await _GalleryFixture.mount(
        tester,
        viewport: _narrow,
        textScale: 1.6,
        brandId: 'liquidGlass',
      );
      expect(fixture.theme.activeWidgetBackgroundBrand.id, 'liquidGlass');
      final state = tester.state(find.byType(WidgetScreen));
      await _expectViewportAndControls(
        tester,
        fixture,
        viewport: _narrow,
        locale: locale,
        textScale: 1.6,
      );
      await _scrollGalleryToTop(tester);
      await _captureIfRequested(
        tester,
        fixture.captureKey,
        'gallery-${locale.name}-glass-top-controls.png',
      );
      await _expectFirstGalleryCard(tester, viewport: _narrow);
      await _captureIfRequested(
        tester,
        fixture.captureKey,
        'gallery-${locale.name}-glass-first-add.png',
      );
      await fixture.resize(tester, viewport: _landscape, textScale: 1.6);
      await _expectViewportAndControls(
        tester,
        fixture,
        viewport: _landscape,
        locale: locale,
        textScale: 1.6,
      );
      await _expectFirstGalleryCard(tester, viewport: _landscape);
      await fixture.resize(tester, viewport: _tablet, textScale: 1);
      await _expectViewportAndControls(
        tester,
        fixture,
        viewport: _tablet,
        locale: locale,
        textScale: 1,
      );
      await _scrollGalleryToTop(tester);
      await _captureIfRequested(
        tester,
        fixture.captureKey,
        'gallery-tablet-${locale.name}-glass-top-controls.png',
      );
      expect(tester.state(find.byType(WidgetScreen)), same(state));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('catalog cards keep their kind keys and full add labels', (
    tester,
  ) async {
    I18n.setLocale(AppLocale.en);
    final fixture = await _GalleryFixture.mount(
      tester,
      viewport: _tablet,
      textScale: 1,
    );

    for (final kind in DuoyiWidgetKind.values) {
      final group = _galleryGroup(kind);
      await _scrollGalleryUntilVisible(tester, group);
      await tester.pumpAndSettle();
      expect(group, findsOneWidget, reason: kind.name);
      expect(tester.widget(group), isA<AppSurfaceCard>(), reason: kind.name);
      final groupElement = group.evaluate().single;
      expect(
        groupElement.findAncestorWidgetOfExactType<RepaintBoundary>(),
        isNotNull,
        reason:
            '${kind.name} preview card should have an isolated repaint boundary.',
      );
      expect(
        find.descendant(
          of: group,
          matching: find.text(WidgetUiCopy.catalogTitle(kind)),
        ),
        findsOneWidget,
        reason: kind.name,
      );
      expect(
        find.descendant(of: group, matching: find.byType(WidgetPreviewCard)),
        findsOneWidget,
        reason: kind.name,
      );

      final addState = find.descendant(
        of: group,
        matching: find.byKey(ValueKey(kind)),
      );
      expect(addState, findsOneWidget, reason: kind.name);
      final addButton = find.descendant(
        of: addState,
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(addButton);
      await tester.pumpAndSettle();
      _expectAddButton(tester, addButton, kind);
      expect(
        tester.getSize(addButton).height,
        greaterThanOrEqualTo(44),
        reason: '${kind.name} Add button must meet the touch target minimum.',
      );
      final label = find.descendant(
        of: addButton,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data ==
                  WidgetUiCopy.addWidgetButtonLabel(
                    modeLabel: WidgetDisplayMode.standard.label,
                    launcherRequestLabel:
                        WidgetDisplayMode.standard.launcherRequestLabel,
                  ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(_paragraphLineCount(paragraph), 1);
    }
    expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category, display style and locale changes preserve state without extra writes',
    (tester) async {
      final fixture = await _GalleryFixture.mount(
        tester,
        viewport: _narrow,
        textScale: 1.6,
      );
      final screen = find.byType(WidgetScreen);
      final screenState = tester.state(screen);

      await _selectCategory(tester, WidgetCategory.life);
      expect(_selectedCategory(tester), {WidgetCategory.life});
      expect(_galleryGroup(DuoyiWidgetKind.todo), findsNothing);
      await _scrollGalleryUntilVisible(
        tester,
        _galleryGroup(DuoyiWidgetKind.diary),
      );
      expect(_galleryGroup(DuoyiWidgetKind.diary), findsOneWidget);
      expect(fixture.preferenceStore.widgetPreferenceWrites, isEmpty);

      await _selectDisplayMode(tester, WidgetDisplayMode.detailed);
      await AccountPreferenceWrites.drain();
      await tester.pumpAndSettle();
      expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
      final writesAfterStyleSelection = List<String>.of(
        fixture.preferenceStore.widgetPreferenceWrites,
      );
      expect(writesAfterStyleSelection, isNotEmpty);
      expect(
        writesAfterStyleSelection.toSet(),
        everyElement(
          isIn({
            'flutter.${WidgetDisplayModeSelection.storageKey}',
            'flutter.${WidgetDisplayModeSelection.legacyKey}',
          }),
        ),
      );

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        await _scrollGalleryToTop(tester);
        expect(tester.state(screen), same(screenState));
        expect(_selectedCategory(tester), {WidgetCategory.life});
        expect(_selectedDisplayMode(tester), {WidgetDisplayMode.detailed});
        expect(_galleryGroup(DuoyiWidgetKind.todo), findsNothing);
        await _scrollGalleryUntilVisible(
          tester,
          _galleryGroup(DuoyiWidgetKind.diary),
        );
        expect(_galleryGroup(DuoyiWidgetKind.diary), findsOneWidget);
        expect(
          fixture.preferenceStore.widgetPreferenceWrites,
          writesAfterStyleSelection,
        );
      }

      await _scrollGalleryToTop(tester);
      final previousSupportChecks = fixture.channels.supportChecks;
      final settingsButton = _bannerAction(
        tester,
        WidgetUiCopy.actionAppSettings,
      );
      final recheckButton = _bannerAction(tester, WidgetUiCopy.actionRecheck);
      await _scrollGalleryUntilVisible(tester, settingsButton);
      expect(tester.getSize(settingsButton).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(recheckButton).height, greaterThanOrEqualTo(44));
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();
      expect(fixture.channels.openSettings, 1);
      await _scrollGalleryUntilVisible(tester, recheckButton);
      await tester.tap(recheckButton);
      await tester.pumpAndSettle();
      expect(fixture.channels.supportChecks, previousSupportChecks + 1);
      expect(
        fixture.preferenceStore.widgetPreferenceWrites,
        writesAfterStyleSelection,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow English add action may wrap without losing its full label',
    (tester) async {
      I18n.setLocale(AppLocale.en);
      await _GalleryFixture.mount(
        tester,
        viewport: const Size(280, 844),
        textScale: 2,
        boldText: true,
      );
      await _expectSegmentLabels(tester, _categorySelector(tester), [
        for (final value in WidgetCategory.values)
          WidgetUiCopy.categoryLabel(value),
      ]);
      await _scrollGalleryUntilVisible(tester, _styleSelector(tester));
      await _expectSegmentLabels(tester, _styleSelector(tester), [
        for (final mode in WidgetDisplayMode.values)
          '${mode.label} ${mode.launcherRequestLabel}',
      ]);
      final addButton = await _firstAddButton(tester);
      final labelText = _addLabel(tester, addButton);
      final paragraph = tester.renderObject<RenderParagraph>(labelText);
      expect(
        paragraph.text.toPlainText(),
        WidgetUiCopy.addWidgetButtonLabel(
          modeLabel: WidgetDisplayMode.standard.label,
          launcherRequestLabel: WidgetDisplayMode.standard.launcherRequestLabel,
        ),
      );
      expect(tester.widget<Text>(labelText).maxLines, isNull);
      expect(tester.widget<Text>(labelText).overflow, isNull);
      expect(tester.widget<Text>(labelText).softWrap, isNot(false));
      expect(_paragraphLineCount(paragraph), greaterThan(1));
      expect(tester.getSize(addButton).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    },
  );

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final width in [390.0, 412.0]) {
        testWidgets('phone banner $brand ${locale.name} $width at200percent', (
          tester,
        ) async {
          I18n.setLocale(locale);
          final fixture = await _GalleryFixture.mount(
            tester,
            viewport: Size(width, 844),
            textScale: 2.0,
            brandId: brand,
          );
          for (final label in [
            WidgetUiCopy.actionAppSettings,
            WidgetUiCopy.actionRecheck,
          ]) {
            final action = _bannerAction(tester, label);
            await _scrollGalleryUntilVisible(tester, action);
            expect(action.hitTestable(), findsOneWidget);
            expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: action, matching: find.byType(RichText)).last,
            );
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.textSize.width,
              lessThanOrEqualTo(paragraph.size.width + .1),
            );
          }
          expect(fixture.channels.openSettings, 0);
          final settings = _bannerAction(
            tester,
            WidgetUiCopy.actionAppSettings,
          );
          await _scrollGalleryUntilVisible(tester, settings);
          await tester.tap(settings);
          await tester.pumpAndSettle();
          expect(fixture.channels.openSettings, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

Future<void> _expectViewportAndControls(
  WidgetTester tester,
  _GalleryFixture fixture, {
  required Size viewport,
  required AppLocale locale,
  required double textScale,
}) async {
  expect(find.text(WidgetUiCopy.previewHeaderTitle), findsNothing);
  final category = _categorySelector(tester);
  await _scrollGalleryUntilVisible(tester, category, delta: -240);
  final expectedCategoryDirection =
      viewport == _narrow && locale == AppLocale.en
      ? Axis.vertical
      : Axis.horizontal;
  await _expectSegmentLabels(tester, category, [
    for (final value in WidgetCategory.values)
      WidgetUiCopy.categoryLabel(value),
  ], expectedDirection: expectedCategoryDirection);

  final style = _styleSelector(tester);
  await _scrollGalleryUntilVisible(tester, style);
  final expectedStyleDirection =
      viewport.width >= 900 || (viewport == _narrow && locale == AppLocale.en)
      ? (viewport == _narrow && locale == AppLocale.en
            ? Axis.vertical
            : Axis.horizontal)
      : null;
  await _expectSegmentLabels(tester, style, [
    for (final mode in WidgetDisplayMode.values)
      '${mode.label} ${mode.launcherRequestLabel}',
  ], expectedDirection: expectedStyleDirection);

  if (viewport == _narrow) {
    for (final label in [
      WidgetUiCopy.actionAppSettings,
      WidgetUiCopy.actionRecheck,
    ]) {
      final button = _bannerAction(tester, label);
      await _scrollGalleryUntilVisible(tester, button);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      expect(button.hitTestable(), findsOneWidget);
      expect(
        tester
            .getSemantics(button)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      if (textScale == 1.6 &&
          (fixture.theme.brand.id == 'defaultBrand' ||
              fixture.theme.brand.id == 'liquidGlass')) {
        expectReadableControl(tester, button);
      }
    }
  }
  expect(tester.takeException(), isNull);
  expect(fixture.viewport, viewport);
  expect(fixture.textScale, textScale);
}

Future<void> _expectSegmentLabels(
  WidgetTester tester,
  Finder segmented,
  List<String> labels, {
  Axis? expectedDirection,
}) async {
  await _scrollGalleryUntilVisible(tester, segmented);
  final control = tester.widget(segmented) as SegmentedButton<dynamic>;
  if (expectedDirection != null) {
    expect(control.direction, expectedDirection);
  }
  for (final value in labels) {
    final label = find.descendant(of: segmented, matching: find.text(value));
    expect(label, findsOneWidget, reason: value);
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    final segmentButton = find
        .ancestor(of: label, matching: find.byType(TextButton))
        .first;
    expect(segmentButton.hitTestable(), findsOneWidget, reason: value);
    expect(
      tester.getSize(segmentButton).height,
      greaterThanOrEqualTo(44),
      reason: '$value needs a 44 logical pixel touch target.',
    );
    // SegmentedButton merges its TextButton into an outer selected node.
    final mergedSegment = find
        .ancestor(of: segmentButton, matching: find.byType(MergeSemantics))
        .first;
    final semantics = tester.getSemantics(mergedSegment).getSemanticsData();
    expect(semantics.label, contains(value), reason: value);
    expect(
      semantics.hasAction(SemanticsAction.tap),
      isTrue,
      reason: '$value must expose a semantic tap action.',
    );
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.text.toPlainText(), value, reason: value);
    expect(paragraph.didExceedMaxLines, isFalse, reason: value);
    final labelRect = tester.getRect(label);
    final buttonRect = tester.getRect(segmentButton);
    expect(
      labelRect.left,
      greaterThanOrEqualTo(buttonRect.left - 0.5),
      reason: '$value must fit inside its segment horizontally.',
    );
    expect(
      labelRect.right,
      lessThanOrEqualTo(buttonRect.right + 0.5),
      reason: '$value must fit inside its segment horizontally.',
    );
  }
}

Future<Rect> _expectFirstGalleryCard(
  WidgetTester tester, {
  required Size viewport,
}) async {
  final group = _galleryGroup(DuoyiWidgetKind.todo);
  await _scrollGalleryUntilVisible(tester, group);
  await tester.pumpAndSettle();
  expect(group, findsOneWidget);
  expect(tester.widget(group), isA<AppSurfaceCard>());
  final rect = tester.getRect(group);
  expect(rect.width, lessThanOrEqualTo(720));
  expect(rect.center.dx, closeTo(viewport.width / 2, 1));
  expect(rect.left, greaterThanOrEqualTo(11));
  expect(rect.right, lessThanOrEqualTo(viewport.width - 11));

  final addButton = await _firstAddButton(tester);
  _expectAddButton(tester, addButton, DuoyiWidgetKind.todo);
  final buttonRect = tester.getRect(addButton);
  expect(buttonRect.height, greaterThanOrEqualTo(44));
  expect(buttonRect.top, greaterThanOrEqualTo(kToolbarHeight - 1));
  expect(buttonRect.bottom, lessThanOrEqualTo(viewport.height + 1));
  return rect;
}

void _expectAddButton(
  WidgetTester tester,
  Finder addButton,
  DuoyiWidgetKind kind,
) {
  final label = _addLabel(tester, addButton);
  final expected = WidgetUiCopy.addWidgetButtonLabel(
    modeLabel: WidgetDisplayMode.standard.label,
    launcherRequestLabel: WidgetDisplayMode.standard.launcherRequestLabel,
  );
  final text = tester.widget<Text>(label);
  final paragraph = tester.renderObject<RenderParagraph>(label);
  expect(text.data, expected, reason: kind.name);
  expect(text.maxLines, isNull, reason: kind.name);
  expect(text.overflow, isNull, reason: kind.name);
  expect(text.softWrap, isNot(false), reason: kind.name);
  expect(paragraph.text.toPlainText(), expected, reason: kind.name);
  expect(paragraph.didExceedMaxLines, isFalse, reason: kind.name);
  expect(addButton.hitTestable(), findsOneWidget, reason: kind.name);
  final semantics = tester.getSemantics(addButton);
  expect(semantics.label, contains(expected), reason: kind.name);
  expect(
    semantics.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: kind.name,
  );
}

Future<Finder> _firstAddButton(WidgetTester tester) async {
  final group = _galleryGroup(DuoyiWidgetKind.todo);
  await _scrollGalleryUntilVisible(tester, group);
  final addState = find.descendant(
    of: group,
    matching: find.byKey(const ValueKey(DuoyiWidgetKind.todo)),
  );
  final button = find.descendant(
    of: addState,
    matching: find.byType(FilledButton),
  );
  // Keep the action at the viewport bottom so its preview remains visible.
  await Scrollable.ensureVisible(tester.element(button), alignment: 1);
  await tester.pumpAndSettle();
  return button;
}

Finder _addLabel(WidgetTester tester, Finder addButton) => find
    .descendant(
      of: addButton,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.data != null,
      ),
    )
    .first;

Future<void> _selectCategory(
  WidgetTester tester,
  WidgetCategory category,
) async {
  final control = _categorySelector(tester);
  await _scrollGalleryUntilVisible(tester, control, delta: -240);
  final label = find.descendant(
    of: control,
    matching: find.text(WidgetUiCopy.categoryLabel(category)),
  );
  await tester.ensureVisible(label);
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Future<void> _selectDisplayMode(
  WidgetTester tester,
  WidgetDisplayMode mode,
) async {
  final control = _styleSelector(tester);
  await _scrollGalleryUntilVisible(tester, control, delta: -240);
  final label = find.descendant(
    of: control,
    matching: find.text('${mode.label} ${mode.launcherRequestLabel}'),
  );
  await tester.ensureVisible(label);
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Set<WidgetCategory> _selectedCategory(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetCategory>>(_categorySelector(tester))
    .selected;

Set<WidgetDisplayMode> _selectedDisplayMode(WidgetTester tester) => tester
    .widget<SegmentedButton<WidgetDisplayMode>>(_styleSelector(tester))
    .selected;

Finder _categorySelector(WidgetTester tester) => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetCategory>,
);

Finder _styleSelector(WidgetTester tester) => find.byWidgetPredicate(
  (widget) => widget is SegmentedButton<WidgetDisplayMode>,
);

Finder _galleryGroup(DuoyiWidgetKind kind) =>
    find.byKey(ValueKey('widget_gallery_${kind.name}'));

Finder _galleryScrollable(WidgetTester tester) => find
    .descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollGalleryUntilVisible(
  WidgetTester tester,
  Finder target, {
  double delta = 240,
}) async {
  // ListView builds lazily. Start from a known position so an unmounted
  // control above the current card is not searched for by scrolling down.
  await _scrollGalleryToTop(tester);
  await tester.scrollUntilVisible(
    target,
    delta.abs(),
    scrollable: _galleryScrollable(tester),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollGalleryToTop(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(_galleryScrollable(tester));
  if (scrollable.position.pixels != 0) scrollable.position.jumpTo(0);
  await tester.pumpAndSettle();
}

int _paragraphLineCount(RenderParagraph paragraph) {
  final plainText = paragraph.text.toPlainText();
  if (plainText.isEmpty) return 0;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plainText.length),
  );
  final lineTops = <double>[];
  for (final box in boxes) {
    if (lineTops.every((top) => (top - box.top).abs() > 0.5)) {
      lineTops.add(box.top);
    }
  }
  return lineTops.length;
}

Finder _bannerAction(WidgetTester tester, String label) => find
    .ancestor(of: find.text(label), matching: find.byType(TextButton))
    .first;

Future<void> _captureIfRequested(
  WidgetTester tester,
  GlobalKey key,
  String filename,
) async {
  final directory = Platform.environment['DUOYI_WIDGET_SCREENSHOT_DIR'];
  if (directory == null || directory.isEmpty) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$filename');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _GalleryFixture {
  _GalleryFixture._({
    required this.theme,
    required this.channels,
    required this.preferenceStore,
    required this.captureKey,
    required this.viewport,
    required this.textScale,
    required this.boldText,
  });

  final ThemeProvider theme;
  final _WidgetChannels channels;
  final _GalleryPreferenceStore preferenceStore;
  final GlobalKey captureKey;
  Size viewport;
  double textScale;
  bool boldText;

  static Future<_GalleryFixture> mount(
    WidgetTester tester, {
    required Size viewport,
    double textScale = 1.6,
    bool dark = false,
    bool boldText = false,
    String? brandId,
  }) async {
    await tester.runAsync(loadWidgetPolishScreenshotFonts);
    final preferenceStore = _GalleryPreferenceStore({
      'flutter.active_brand': brandId ?? (dark ? 'starRail' : 'defaultBrand'),
    });
    SharedPreferencesStorePlatform.instance = preferenceStore;
    final theme = ThemeProvider();
    await theme.loadFromStorage();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    final channels = _WidgetChannels();
    final fixture = _GalleryFixture._(
      theme: theme,
      channels: channels,
      preferenceStore: preferenceStore,
      captureKey: GlobalKey(),
      viewport: viewport,
      textScale: textScale,
      boldText: boldText,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_widgetChannel, channels.handle);
    addTearDown(() async {
      await AccountPreferenceWrites.drain();
      await tester.pumpWidget(const SizedBox.shrink());
      messenger.setMockMethodCallHandler(_widgetChannel, null);
      AndroidWidgetManager.debugIsAndroidOverride = null;
      tester.view.reset();
      theme.dispose();
    });
    await tester.pumpWidget(fixture._app());
    await tester.pumpAndSettle();
    return fixture;
  }

  Widget _app() {
    final baseTheme = theme.brand.theme;
    TextTheme withScreenshotFonts(TextTheme text) => text.apply(
      fontFamily: 'DuoyiScreenshotLatin',
      fontFamilyFallback: const ['DuoyiScreenshot'],
    );
    return ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          textTheme: withScreenshotFonts(baseTheme.textTheme),
          primaryTextTheme: withScreenshotFonts(baseTheme.primaryTextTheme),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: viewport,
            textScaler: TextScaler.linear(textScale),
            boldText: boldText,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
        ),
      ),
    );
  }

  Future<void> resize(
    WidgetTester tester, {
    required Size viewport,
    required double textScale,
    bool? boldText,
  }) async {
    this.viewport = viewport;
    this.textScale = textScale;
    if (boldText != null) this.boldText = boldText;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
  }
}

class _GalleryPreferenceStore extends InMemorySharedPreferencesStore {
  _GalleryPreferenceStore(super.data) : super.withData();

  final widgetPreferenceWrites = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.startsWith('flutter.duoyi_widget_')) {
      widgetPreferenceWrites.add(key);
    }
    return super.setValue(valueType, key, value);
  }
}

class _WidgetChannels {
  int supportChecks = 0;
  int openSettings = 0;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'canRequestPinWidget':
        supportChecks++;
        return true;
      case 'canOpenWidgetSettings':
        return true;
      case 'openWidgetSettings':
        openSettings++;
        return true;
      case 'applyWidgetDisplayMode':
      case 'refreshAllWidgets':
        return 0;
      default:
        return null;
    }
  }
}
