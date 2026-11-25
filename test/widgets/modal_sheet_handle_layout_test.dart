import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/widgets/app_date_picker.dart';
import 'package:duoyi/widgets/app_time_picker.dart';
import 'package:duoyi/widgets/settings_picker_tile.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'default brand keeps its theme handle while the helper leaves the owned handle',
    (tester) async {
      await _loadModalFonts(tester);
      final screenshotKey = GlobalKey();
      await _pumpHost(
        tester,
        screenshotKey: screenshotKey,
        home: _openButton('Open', (_) {}),
      );
      expect(AppBrands.defaultBrand.theme.useMaterial3, isTrue);
      expect(
        AppBrands.defaultBrand.theme.bottomSheetTheme.showDragHandle,
        isTrue,
      );

      final hostContext = tester.element(find.text('Open'));
      final frameworkSheet = showModalBottomSheet<void>(
        context: hostContext,
        builder: (_) => const SizedBox(
          height: 120,
          child: Center(child: Text('Framework sheet')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      await frameworkSheet;

      final appSheet = showAppModalSheet<void>(
        context: tester.element(find.text('Open')),
        builder: (_) => const AppModalSheet(
          title: 'Owned handle',
          child: Text('Modal body'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      expect(
        tester.widget<AppModalSheet>(find.byType(AppModalSheet)).showDragHandle,
        isTrue,
      );
      expect(_ownedHandle(), findsOneWidget);
      expect(
        tester.getTopLeft(_ownedHandle()).dy,
        greaterThan(tester.getBottomLeft(find.byType(AppBar)).dy),
      );
      await _captureModalHandleScreenshot(
        tester,
        screenshotKey,
        'app-modal-sheet',
      );
      Navigator.of(tester.element(find.byType(AppModalSheet))).pop();
      await tester.pumpAndSettle();
      await appSheet;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('surface card helper keeps its owned 40x5 handle only', (
    tester,
  ) async {
    await _loadModalFonts(tester);
    final screenshotKey = GlobalKey();
    await _pumpHost(
      tester,
      screenshotKey: screenshotKey,
      home: _openButton('Open', (context) {
        showAppModalSheet<void>(
          context: context,
          builder: (_) => AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const ValueKey('surface-card-owned-handle'),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Surface card body'),
              ],
            ),
          ),
        );
      }),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isFalse,
    );
    final ownedHandle = find.byKey(const ValueKey('surface-card-owned-handle'));
    expect(ownedHandle, findsOneWidget);
    expect(tester.getSize(ownedHandle), const Size(40, 5));
    await _captureModalHandleScreenshot(
      tester,
      screenshotKey,
      'surface-card-handle',
    );
    Navigator.of(tester.element(find.byType(AppSurfaceCard))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default helper retains barrier dismissal and drag enablement', (
    tester,
  ) async {
    await _loadModalFonts(tester);
    Future<String?>? result;
    await _pumpHost(
      tester,
      home: _openButton('Open', (context) {
        result = showAppModalSheet<String>(
          context: context,
          builder: (_) => const AppModalSheet(
            title: 'Dismissible sheet',
            scrollable: false,
            child: SizedBox(height: 100, child: Text('Dismiss from scrim')),
          ),
        );
      }),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isTrue,
    );
    expect(
      tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).dismissible,
      isTrue,
    );

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(await result, isNull);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_ownedHandle(), findsOneWidget);
    await tester.fling(_ownedHandle(), const Offset(0, 600), 1200);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(await result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabled drag and scrim dismissal still allow a returned result',
    (tester) async {
      await _loadModalFonts(tester);
      Future<String?>? result;
      await _pumpHost(
        tester,
        home: _openButton('Open', (context) {
          result = showAppModalSheet<String>(
            context: context,
            isDismissible: false,
            enableDrag: false,
            builder: (sheetContext) => AppModalSheet(
              title: 'Fixed sheet',
              scrollable: false,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop('returned'),
                  child: const Text('Return result'),
                ),
              ],
              child: const SizedBox(height: 80, child: Text('Fixed content')),
            ),
          );
        }),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
        isFalse,
      );
      expect(
        tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).dismissible,
        isFalse,
      );

      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
      await tester.drag(_ownedHandle(), const Offset(0, 280));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);

      await tester.ensureVisible(find.text('Return result'));
      await tester.tap(find.text('Return result'));
      await tester.pumpAndSettle();
      expect(await result, 'returned');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('helper uses the nearest navigator by default', (tester) async {
    await _verifyNavigatorResult(tester, useRootNavigator: false);
  });

  testWidgets('helper can return a result through the root navigator', (
    tester,
  ) async {
    await _verifyNavigatorResult(tester, useRootNavigator: true);
  });

  testWidgets('shiftForKeyboard retains or removes the simulated IME inset', (
    tester,
  ) async {
    await _loadModalFonts(tester);
    await _pumpHost(
      tester,
      viewInsetsBottom: 200,
      home: _openButton('Open', (_) {}),
    );
    final hostContext = tester.element(find.text('Open'));

    Future<String?> showWithInset(bool shiftForKeyboard) {
      return showAppModalSheet<String>(
        context: hostContext,
        shiftForKeyboard: shiftForKeyboard,
        builder: (sheetContext) => AppModalSheet(
          title: 'Keyboard layout',
          shiftForKeyboard: shiftForKeyboard,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop('closed'),
              child: const Text('Close sheet'),
            ),
          ],
          child: Builder(
            builder: (context) {
              _observedBottomInset = MediaQuery.viewInsetsOf(context).bottom;
              return const Text('Inset probe');
            },
          ),
        ),
      );
    }

    _observedBottomInset = null;
    final shiftedResult = showWithInset(true);
    await tester.pumpAndSettle();
    expect(_observedBottomInset, 200);
    await tester.tap(find.text('Close sheet'));
    await tester.pumpAndSettle();
    expect(await shiftedResult, 'closed');

    _observedBottomInset = null;
    final unshiftedResult = showWithInset(false);
    await tester.pumpAndSettle();
    expect(_observedBottomInset, 0);
    await tester.tap(find.text('Close sheet'));
    await tester.pumpAndSettle();
    expect(await unshiftedResult, 'closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings picker keeps its selected option across locales and returns a choice',
    (tester) async {
      await _loadModalFonts(tester);
      int? selected;
      final screenshotKey = GlobalKey();
      await _pumpHost(
        tester,
        screenshotKey: screenshotKey,
        size: const Size(320, 844),
        textScale: 1.3,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SettingsPickerTile<int>(
              icon: Icons.tune,
              color: Colors.blue,
              titleBuilder: () =>
                  I18n.current == AppLocale.zh ? '每周从星期几开始' : 'Week starts on',
              pickerTitleBuilder: () => I18n.current == AppLocale.zh
                  ? '选择每周起始日'
                  : 'Choose week start day',
              currentValue: 1,
              displayLabelBuilder: () =>
                  I18n.current == AppLocale.zh ? '星期一' : 'Monday',
              optionsBuilder: () => [
                SettingsPickerOption<int>(
                  value: 1,
                  title: I18n.current == AppLocale.zh ? '星期一' : 'Monday',
                ),
                SettingsPickerOption<int>(
                  value: 7,
                  title: I18n.current == AppLocale.zh ? '星期日' : 'Sunday',
                ),
              ],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SettingsPickerTile<int>));
      await tester.pumpAndSettle();
      expect(find.text('选择每周起始日'), findsOneWidget);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      expect(
        tester.widget<AppModalSheet>(find.byType(AppModalSheet)).showDragHandle,
        isTrue,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Choose week start day'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text('Monday'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await _captureModalHandleScreenshot(
        tester,
        screenshotKey,
        'settings-picker-en',
      );

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppModalSheet),
          matching: find.text('星期一'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await _captureModalHandleScreenshot(
        tester,
        screenshotKey,
        'settings-picker-zh',
      );

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final sunday = find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.text('Sunday'),
      );
      await tester.ensureVisible(sunday);
      await tester.tap(sunday);
      await tester.pumpAndSettle();
      expect(selected, 7);
      expect(find.byType(AppModalSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('date picker confirms a day at 320x844 and 1.3x text', (
    tester,
  ) async {
    await _verifyDatePickerLayout(
      tester,
      size: const Size(320, 844),
      viewInsetsBottom: 0,
    );
  });

  testWidgets('date picker confirms through a short IME layout', (
    tester,
  ) async {
    await _verifyDatePickerLayout(
      tester,
      size: const Size(568, 320),
      viewInsetsBottom: 96,
    );
  });

  testWidgets('time picker confirms at 320x844 and 1.3x text', (tester) async {
    await _verifyTimePickerLayout(
      tester,
      size: const Size(320, 844),
      viewInsetsBottom: 0,
    );
  });

  testWidgets('time picker confirms through a short IME layout', (
    tester,
  ) async {
    await _verifyTimePickerLayout(
      tester,
      size: const Size(568, 320),
      viewInsetsBottom: 96,
    );
  });
}

double? _observedBottomInset;

Future<void> _verifyNavigatorResult(
  WidgetTester tester, {
  required bool useRootNavigator,
}) async {
  await _loadModalFonts(tester);
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final nestedNavigatorKey = GlobalKey<NavigatorState>();
  Future<String?>? result;

  await _pumpHost(
    tester,
    navigatorKey: rootNavigatorKey,
    home: Navigator(
      key: nestedNavigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  result = showAppModalSheet<String>(
                    context: context,
                    useRootNavigator: useRootNavigator,
                    builder: (sheetContext) => AppModalSheet(
                      title: 'Navigator result',
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop('returned'),
                          child: const Text('Return result'),
                        ),
                      ],
                      child: const Text('Navigator scope'),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  final sheetContext = tester.element(find.byType(AppModalSheet));
  expect(
    Navigator.of(sheetContext),
    same(
      useRootNavigator
          ? rootNavigatorKey.currentState
          : nestedNavigatorKey.currentState,
    ),
  );
  await tester.tap(find.text('Return result'));
  await tester.pumpAndSettle();
  expect(await result, 'returned');
  expect(tester.takeException(), isNull);
}

Future<void> _verifyDatePickerLayout(
  WidgetTester tester, {
  required Size size,
  required double viewInsetsBottom,
}) async {
  await _loadModalFonts(tester);
  final screenshotKey = GlobalKey();
  Future<DateTime?>? result;
  await _pumpHost(
    tester,
    screenshotKey: screenshotKey,
    size: size,
    textScale: 1.3,
    viewInsetsBottom: viewInsetsBottom,
    home: _openButton('Open date picker', (context) {
      result = AppDatePicker.pickSolar(
        context,
        initialDate: DateTime(2026, 5, 17),
        firstDate: DateTime(2026, 1, 1),
        lastDate: DateTime(2026, 12, 31),
      );
    }),
  );

  await tester.tap(find.text('Open date picker'));
  await tester.pumpAndSettle();
  expect(find.byType(AppModalSheet), findsOneWidget);
  expect(
    tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
    isFalse,
  );
  await _captureModalHandleScreenshot(
    tester,
    screenshotKey,
    viewInsetsBottom > 0 ? 'date-picker-short-ime' : 'date-picker-portrait',
  );

  final day = find.byKey(const ValueKey('solar-day-2026-05-19'));
  await tester.ensureVisible(day);
  await tester.tap(day);
  await tester.pumpAndSettle();
  final confirm = find.text(I18n.tr('action.confirm'));
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();

  expect(await result, DateTime(2026, 5, 19));
  expect(find.byType(BottomSheet), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _verifyTimePickerLayout(
  WidgetTester tester, {
  required Size size,
  required double viewInsetsBottom,
}) async {
  await _loadModalFonts(tester);
  final screenshotKey = GlobalKey();
  Future<TimeOfDay?>? result;
  await _pumpHost(
    tester,
    screenshotKey: screenshotKey,
    size: size,
    textScale: 1.3,
    viewInsetsBottom: viewInsetsBottom,
    home: _openButton('Open time picker', (context) {
      result = AppTimePicker.show(
        context,
        initialTime: const TimeOfDay(hour: 9, minute: 13),
      );
    }),
  );

  await tester.tap(find.text('Open time picker'));
  await tester.pumpAndSettle();
  expect(find.byType(AppModalSheet), findsOneWidget);
  expect(
    tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
    isFalse,
  );
  await _captureModalHandleScreenshot(
    tester,
    screenshotKey,
    viewInsetsBottom > 0 ? 'time-picker-short-ime' : 'time-picker-portrait',
  );

  final later = find.text(I18n.tr('picker.time.later_30m'));
  await tester.ensureVisible(later);
  await tester.tap(later);
  await tester.pumpAndSettle();
  final confirm = find.text(I18n.tr('action.confirm'));
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();

  expect(await result, const TimeOfDay(hour: 9, minute: 45));
  expect(find.byType(AppModalSheet), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<GlobalKey<NavigatorState>> _pumpHost(
  WidgetTester tester, {
  required Widget home,
  GlobalKey? screenshotKey,
  Size size = const Size(390, 844),
  double textScale = 1,
  double viewInsetsBottom = 0,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (viewInsetsBottom > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: viewInsetsBottom);
  }
  addTearDown(tester.view.reset);

  final key = navigatorKey ?? GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      debugShowCheckedModeBanner: false,
      theme: AppBrands.defaultBrand.theme,
      builder: (context, child) => RepaintBoundary(
        key: screenshotKey ?? GlobalKey(),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
      home: home,
    ),
  );
  return key;
}

Future<void> _captureModalHandleScreenshot(
  WidgetTester tester,
  GlobalKey screenshotKey,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_MODAL_HANDLE_SCREENSHOTS'] != '1') {
    return;
  }

  await tester.runAsync(() async {
    final boundary =
        screenshotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = png!.buffer.asUint8List();
      final directory = Directory('evidence/screenshots/modal-handle-20261015');
      directory.createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes, flush: true);
    } finally {
      image.dispose();
    }
  });
}

Finder _ownedHandle() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.constraints == const BoxConstraints.tightFor(width: 40, height: 4),
);

Widget _openButton(String label, ValueChanged<BuildContext> onOpen) {
  return Scaffold(
    appBar: AppBar(title: const Text('Modal host')),
    body: Builder(
      builder: (context) => Center(
        child: TextButton(onPressed: () => onOpen(context), child: Text(label)),
      ),
    ),
  );
}

Future<void> _loadModalFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    await loadWidgetPolishScreenshotFonts();

    final latin = ByteData.sublistView(
      File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
    );
    for (final family in const ['sans-serif', 'Roboto', 'DejaVu Sans']) {
      await (FontLoader(family)..addFont(Future.value(latin))).load();
    }

    final cjk = ByteData.sublistView(
      File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
    );
    for (final family in const [
      'PingFang SC',
      'Hiragino Sans GB',
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'Microsoft YaHei',
      'WenQuanYi Micro Hei',
      'DroidSansFallbackFull',
    ]) {
      await (FontLoader(family)..addFont(Future.value(cjk))).load();
    }
    await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
      'type': 'fontsChange',
    });
  });
}
