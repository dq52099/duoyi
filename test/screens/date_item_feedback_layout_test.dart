// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/date_item_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  for (final anniversary in [false, true]) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'narrow', size: Size(320, 844), scale: 1.3),
        (name: 'landscape', size: Size(568, 320), scale: 1.6),
      ]) {
        testWidgets('date feedback $anniversary ${locale.name} ${layout.name}', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          final store = _Store();
          SharedPreferencesStorePlatform.instance = store;
          I18n.setLocale(locale);
          await tester.runAsync(_loadFonts);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          final countdown = CountdownProvider();
          final memorial = AnniversaryProvider();
          final boundary = GlobalKey();
          final isEn = locale == AppLocale.en;
          final title = isEn
              ? 'Family celebration with a long title'
              : '与家人一起庆祝值得纪念的重要日子';
          final countdownItem = CountdownItem(
            id: 'layout',
            title: title,
            targetDate: DateTime(2099, 7, 1),
          );
          final anniversaryItem = Anniversary(
            id: 'layout',
            title: title,
            originDate: DateTime(2099, 7, 1),
            type: AnniversaryType.memorial,
          );
          if (anniversary) {
            await memorial.add(anniversaryItem);
          } else {
            await countdown.addItem(countdownItem);
          }
          addTearDown(() async {
            store.release();
            await tester.pumpAndSettle();
            await AccountPreferenceWrites.drain();
            await tester.pumpWidget(const SizedBox.shrink());
            countdown.dispose();
            memorial.dispose();
            tester.view.reset();
            I18n.setLocale(AppLocale.zh);
            SharedPreferences.setMockInitialValues({});
          });
          final theme = AppBrands.defaultBrand.theme.copyWith(
            platform: TargetPlatform.iOS,
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: countdown),
                ChangeNotifierProvider.value(value: memorial),
              ],
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => RepaintBoundary(
                  key: boundary,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                    child: child!,
                  ),
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () {
                          if (anniversary) {
                            showAnniversaryEditor(
                              context,
                              item: anniversaryItem,
                            );
                          } else {
                            showCountdownEditor(context, item: countdownItem);
                          }
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
          store.reject = true;
          final save = find.byKey(
            ValueKey(
              '${anniversary ? 'anniversary' : 'countdown'}_editor_save_button',
            ),
          );
          await _reveal(tester, save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          final retry = find.text(I18n.tr('action.retry'));
          await _reveal(tester, retry);
          expect(find.text(DateItemUiCopy.saveFailed), findsOneWidget);
          expect(
            tester.getRect(retry).right,
            lessThanOrEqualTo(layout.size.width),
          );
          expect(tester.takeException(), isNull);
          final prefix =
              '${anniversary ? 'anniversary' : 'countdown'}-${locale.name}-${layout.name}';
          await _capture(tester, boundary, '$prefix-failure');
          store.hold = Completer<void>();
          await tester.tap(retry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
          if (layout.name == 'narrow') {
            expect(
              tester.widget<TextField>(find.byType(TextField).first).enabled,
              isFalse,
            );
          }
          expect(tester.takeException(), isNull);
          if (layout.name == 'narrow') {
            await _capture(tester, boundary, '$prefix-pending');
          }
          store.release();
          await tester.pumpAndSettle();
          expect(save, findsNothing);
        });
      }
    }
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(
        of: find.byType(AppModalSheet),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    target,
    100,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_DATE_SETTINGS_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      'evidence/screenshots/date-item-confirmed-20261015/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
  await loadWidgetPolishScreenshotFonts();
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    await (FontLoader(family)..addFont(Future.value(chinese))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool reject = false;
  Completer<void>? hold;
  Completer<void>? _pending;
  void release() {
    for (final pending in [hold, _pending]) {
      if (pending != null && !pending.isCompleted) pending.complete();
    }
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if ((key == 'flutter.duoyi_countdowns' ||
            key == 'flutter.duoyi_anniversaries_v2') &&
        hold != null) {
      final waiting = hold!;
      _pending = waiting;
      hold = null;
      await waiting.future;
      _pending = null;
    }
    final saved = await super.setValue(type, key, value);
    if (reject) {
      reject = false;
      return false;
    }
    return saved;
  }
}
