import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final narrow in [false, true]) {
      for (final configured in [false, true]) {
        final name = '$brand-${narrow ? 'narrow' : 'ordinary'}-$configured';
        testWidgets('CalDAV rendered text contrast $name', (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          final sync = _Sync(configured);
          final theme = ThemeProvider();
          final locale = LocaleProvider();
          final locations = LocationReminderProvider();
          final notifications = NotificationService();
          final boundary = GlobalKey();
          final originalShadows = debugDisableShadows;
          final rows = <Map<String, Object?>>[];
          try {
            I18n.setLocale(AppLocale.zh);
            await theme.loadFromStorage();
            expect(theme.brand.id, brand);
            await tester.runAsync(loadWeeklyReviewScreenshotFonts);
            debugDisableShadows = false;
            tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<CalendarSyncProvider>.value(
                    value: sync,
                  ),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<LocaleProvider>.value(value: locale),
                  ChangeNotifierProvider<LocationReminderProvider>.value(
                    value: locations,
                  ),
                  ChangeNotifierProvider<NotificationService>.value(
                    value: notifications,
                  ),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const BrandRouteSurface(
                              child: IntegrationsScreen(),
                            ),
                          ),
                        ),
                        child: const Text('Open synthetic integrations'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open synthetic integrations'));
            await tester.pumpAndSettle();
            final route = tester.element(find.byType(IntegrationsScreen));
            final prefs = await SharedPreferences.getInstance();
            final before = {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            for (final language in [AppLocale.zh, AppLocale.en]) {
              I18n.setLocale(language);
              await tester.pumpAndSettle();
              final messages = configured
                  ? {
                      'summary':
                          '${NotificationUiCopy.calDavVerified} · ${NotificationUiCopy.isEn ? 'Keep remote changes' : '远端变更不覆盖'} · ${sync.writeTarget!.collectionUrl}',
                      'conflicts': NotificationUiCopy.calDavConflictsSkipped(
                        sync.lastCalDavConflicts.length,
                      ),
                      'tested': NotificationUiCopy.lastTestedAt(
                        I18nDateFormat.fullDateTime(
                          sync.writeTarget!.lastTestedAt!,
                        ),
                      ),
                      'error': NotificationUiCopy.formatCalDavError(
                        sync.lastCalDavError!,
                      ),
                    }
                  : {'guidance': NotificationUiCopy.calDavConfigPrompt};
              for (final entry in messages.entries) {
                final text = find.text(entry.value);
                final scroll = find
                    .byWidgetPredicate(
                      (w) =>
                          w is Scrollable &&
                          w.axisDirection == AxisDirection.down,
                    )
                    .first;
                tester.state<ScrollableState>(scroll).position.jumpTo(0);
                await tester.pumpAndSettle();
                if (entry.key == 'error') {
                  final expectedError = language == AppLocale.en
                      ? 'Calendar access denied. Check your authorization and permissions.'
                      : '日历访问被拒绝，请检查授权信息和权限';
                  expect(
                    entry.value,
                    expectedError,
                    reason: 'The CalDAV error fixture must supply complete safe copy.',
                  );
                }
                await tester.scrollUntilVisible(
                  text,
                  100,
                  maxScrolls: 40,
                  scrollable: scroll,
                );
                await tester.ensureVisible(text);
                await tester.pumpAndSettle();
                if (entry.key == 'error') {
                  expect(
                    text,
                    findsOneWidget,
                    reason:
                        'The dedicated CalDAV error must be mounted exactly once after revealing.',
                  );
                }
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(of: text, matching: find.byType(RichText)),
                );
                final render =
                    boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final rect = MatrixUtils.transformRect(
                  paragraph.getTransformTo(render),
                  Offset.zero & paragraph.size,
                );
                final card = find
                    .ancestor(of: text, matching: find.byType(AppSurfaceCard))
                    .first;
                final cardBox = tester.renderObject<RenderBox>(card);
                final cardRect = MatrixUtils.transformRect(
                  cardBox.getTransformTo(render),
                  Offset.zero & cardBox.size,
                );
                final color =
                    paragraph.text.style?.foreground?.color ??
                    paragraph.text.style!.color!;
                final captured = (await tester.runAsync(() async {
                  final picture = await render.toImage(pixelRatio: 1);
                  try {
                    if (Platform.environment['DUOYI_CAPTURE_CALDAV_CONTRAST'] ==
                        '1') {
                      final png = await picture.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      final run =
                          Platform.environment['DUOYI_CALDAV_CONTRAST_RUN'] ??
                          'current';
                      final file = File(
                        'evidence/screenshots/caldav-contrast-20261020/$run/$name-${language.name}-${entry.key}.png',
                      );
                      await file.parent.create(recursive: true);
                      await file.writeAsBytes(png!.buffer.asUint8List());
                    }
                    return (
                      data: (await picture.toByteData(
                        format: ui.ImageByteFormat.rawRgba,
                      ))!,
                      width: picture.width,
                      height: picture.height,
                    );
                  } finally {
                    picture.dispose();
                  }
                }))!;
                final samples = <Map<String, Object>>[];
                // Both side gutters are inside the card's 12px padding and
                // outside the paragraph. They include actual glass/backdrop
                // compositing at each text row, rather than a theme proxy.
                for (final x in [rect.left - 4, rect.right + 4]) {
                  for (final fraction in [.1, .5, .9]) {
                    final point = Offset(x, rect.top + rect.height * fraction);
                    expect(cardRect.contains(point), isTrue);
                    expect(rect.contains(point), isFalse);
                    final px = point.dx.floor();
                    final py = point.dy.floor();
                    expect(px, inInclusiveRange(0, captured.width - 1));
                    expect(py, inInclusiveRange(0, captured.height - 1));
                    final index = (py * captured.width + px) * 4;
                    expect(captured.data.getUint8(index + 3), 255);
                    final background = Color.fromARGB(
                      255,
                      captured.data.getUint8(index),
                      captured.data.getUint8(index + 1),
                      captured.data.getUint8(index + 2),
                    );
                    samples.add({
                      'x': px,
                      'y': py,
                      'background': background.toARGB32(),
                      'contrast': appContrastRatio(
                        Color.alphaBlend(color, background),
                        background,
                      ),
                    });
                  }
                }
                rows.add({
                  'locale': language.name,
                  'role': entry.key,
                  'foreground': color.toARGB32(),
                  'fontSize': paragraph.text.style!.fontSize,
                  'scaledFontSize': paragraph.textScaler.scale(
                    paragraph.text.style!.fontSize!,
                  ),
                  'samples': samples,
                  'readable': samples.every(
                    (s) => (s['contrast']! as double) >= 4.5,
                  ),
                });
              }
              expect(
                tester.element(find.byType(IntegrationsScreen)),
                same(route),
              );
              expect(sync.calls, 0);
              expect({
                for (final key in prefs.getKeys()) key: prefs.get(key),
              }, before);
              expect(tester.takeException(), isNull);
            }
            expect(
              rows.every((r) => r['readable'] == true),
              isTrue,
              reason: jsonEncode(rows),
            );
          } finally {
            final run = Platform.environment['DUOYI_CALDAV_CONTRAST_RUN'];
            if (run != null) {
              await tester.runAsync(() async {
                final file = File(
                  'evidence/caldav-contrast-20261020/$run/$name.json',
                );
                await file.parent.create(recursive: true);
                await file.writeAsString(jsonEncode(rows));
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            sync.dispose();
            theme.dispose();
            locale.dispose();
            locations.dispose();
            notifications.dispose();
            tester.view.reset();
            debugDisableShadows = originalShadows;
            I18n.setLocale(AppLocale.zh);
          }
        });
      }
    }
  }
}

class _Sync extends CalendarSyncProvider {
  _Sync(this.configured);
  final bool configured;
  int calls = 0;
  @override
  CalDavWriteTarget? get writeTarget => configured
      ? CalDavWriteTarget(
          collectionUrl:
              'https://synthetic.example.test/calendars/a-long-public-collection-identifier/',
          authorizationHeader: 'Basic synthetic-not-real',
          enabled: true,
          lastTestedAt: DateTime(2026, 10, 20, 9, 30),
        )
      : null;
  @override
  String? get lastCalDavError =>
      configured ? '401 synthetic-private diagnostic' : null;
  @override
  List<CalDavWriteConflict> get lastCalDavConflicts => configured
      ? const [
          CalDavWriteConflict(
            uid: 'synthetic-id',
            title: 'Synthetic 用户标题',
            reason: 'synthetic conflict',
          ),
        ]
      : const [];
  @override
  Future<void> saveWriteTarget(CalDavWriteTarget target) async {
    calls++;
  }

  @override
  Future<void> clearWriteTarget() async {
    calls++;
  }

  @override
  Future<void> testWriteTarget({bool Function()? isCurrent}) async {
    calls++;
  }
}
