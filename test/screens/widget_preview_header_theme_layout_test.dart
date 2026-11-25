import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart';
import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

Widget _preview(
  WidgetPreviewKind kind,
  WidgetDisplayMode mode,
  TargetPlatform platform,
) {
  return switch (kind) {
    WidgetPreviewKind.todo => WidgetPreviewCard.todo(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.focus => WidgetPreviewCard.focus(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.habit => WidgetPreviewCard.habit(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.calendar => WidgetPreviewCard.calendar(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.schedule => WidgetPreviewCard.schedule(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.goal => WidgetPreviewCard.goal(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.course => WidgetPreviewCard.course(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.note => WidgetPreviewCard.note(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.anniversary => WidgetPreviewCard.anniversary(
      displayMode: mode,
      platformOverride: platform,
    ),
    WidgetPreviewKind.diary => WidgetPreviewCard.diary(
      displayMode: mode,
      platformOverride: platform,
    ),
  };
}

class _HeaderProbe extends RouteRenderProbe {
  _HeaderProbe(super.tester, super.boundary, super.name, this.scaler);
  final TextScaler scaler;

  Future<void> header(Finder finder, String role, double nominal) async {
    await text(
      finder,
      role: role,
      contrast: false,
      minimumGeometricScale: .999,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    Rect rect(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(render),
      Offset.zero & box.size,
    );
    final bounds = rect(paragraph);
    final surface = rect(
      tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('widget_preview_surface')),
      ),
    );
    expect(surface.inflate(.1).contains(bounds.topLeft), isTrue);
    expect(surface.inflate(.1).contains(bounds.bottomRight), isTrue);
    // Blank interior strip: beyond the rounded border, before header padding.
    final point = Offset(surface.left + 8, bounds.center.dy);
    expect((Offset.zero & render.size).contains(point), isTrue);
    final background = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      try {
        final raw = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = point.dx.floor(), y = point.dy.floor();
        expect(x, inInclusiveRange(0, image.width - 1));
        expect(y, inInclusiveRange(0, image.height - 1));
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          255,
          raw.getUint8(offset),
          raw.getUint8(offset + 1),
          raw.getUint8(offset + 2),
        );
      } finally {
        image.dispose();
      }
    });
    final style = paragraph.text.style!;
    expect(style.fontSize, nominal);
    expect(style.fontWeight ?? FontWeight.normal, FontWeight.normal);
    expect(
      paragraph.textScaler.scale(nominal),
      closeTo(scaler.scale(nominal), .001),
    );
    final foreground = style.foreground?.color ?? style.color!;
    final a = Color.alphaBlend(foreground, background!).computeLuminance();
    final b = background.computeLuminance();
    final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
    final required = scaler.scale(nominal) >= 24 ? 3.0 : 4.5;
    if (ratio < required) {
      errors.add('$role contrast $ratio below $required');
    }
    rows.last.addAll({
      'nominalFontSize': nominal,
      'actualFontSize': scaler.scale(nominal),
      'ratio': ratio,
      'required': required,
      'foregroundARGB': foreground.toARGB32(),
      'backgroundARGB': background.toARGB32(),
      'paragraphRect': [bounds.left, bounds.top, bounds.width, bounds.height],
      'sample': [point.dx.floor(), point.dy.floor()],
    });
  }
}

void main() {
  final original = I18n.current;
  tearDown(() => I18n.setLocale(original));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final mode in WidgetDisplayMode.values) {
        for (final layout in priorityLayouts) {
          final name =
              'preview-header-$brand-${platform.name}-${mode.name}-${layout.name}';
          testWidgets(name, (tester) async {
            final appBrand = brand == 'defaultBrand'
                ? 'liquidGlass'
                : 'defaultBrand';
            SharedPreferences.setMockInitialValues({
              'theme_shop_state': jsonEncode({
                'activeBrand': appBrand,
                'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
                'activeWidgetBackgroundId': brand,
              }),
            });
            final theme = ThemeProvider();
            final boundary = GlobalKey();
            final scaler = layout.scale < 0
                ? const RouteProbeNonlinearScaler()
                : TextScaler.linear(layout.scale);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.runAsync(() async {
              await theme.loadFromStorage();
              await loadWeeklyReviewScreenshotFonts();
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              theme.dispose();
            });
            expect(theme.brand.id, appBrand);
            expect(theme.activeWidgetBackgroundBrand.id, brand);
            final prefs = await SharedPreferences.getInstance();
            final before = {
              for (final key in prefs.getKeys()) key: prefs.get(key),
            };
            final probe = _HeaderProbe(tester, boundary, name, scaler);
            for (final kind in WidgetPreviewKind.values) {
              I18n.setLocale(AppLocale.en);
              await tester.pumpWidget(
                ChangeNotifierProvider<ThemeProvider>.value(
                  value: theme,
                  child: ValueListenableBuilder<AppLocale>(
                    valueListenable: I18n.localeListenable,
                    builder: (context, locale, _) => MaterialApp(
                      theme: theme.brand.theme,
                      locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
                      supportedLocales: const [Locale('en'), Locale('zh')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: scaler),
                        child: RepaintBoundary(key: boundary, child: child!),
                      ),
                      home: BrandRouteSurface(
                        // WidgetScreen itself retains locale state; this fixture
                        // mounts its public preview inside a synthetic scaffold.
                        remountOnLocaleChange: false,
                        child: Scaffold(
                          body: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: _preview(kind, mode, platform),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final element = tester.element(find.byType(WidgetPreviewCard));
              for (final locale in [AppLocale.en, AppLocale.zh]) {
                I18n.setLocale(locale);
                await tester.pumpAndSettle();
                expect(
                  tester.element(find.byType(WidgetPreviewCard)),
                  same(element),
                );
                final role = '${kind.name} ${locale.name}';
                final error = tester.takeException();
                if (error != null) {
                  probe.errors.add('$role framework: $error');
                }
                final title = WidgetUiCopy.previewSampleBadge(
                  WidgetUiCopy.previewTitle(kind),
                );
                final date = WidgetUiCopy.sampleHeaderDate(
                  platform == TargetPlatform.android
                      ? mode.previewCellLabel
                      : mode.label,
                );
                await probe.header(find.text(title), '$role title', 12);
                await probe.header(find.text(date), '$role date', 10);
                await probe.header(find.text('↻'), '$role refresh', 11);
                final frame = find.byWidgetPredicate(
                  (widget) =>
                      widget.runtimeType.toString() ==
                      '_WidgetPreviewContentFrame',
                );
                final bodyTexts = tester
                    .widgetList<Text>(
                      find.descendant(of: frame, matching: find.byType(Text)),
                    )
                    .map((text) => text.data)
                    .whereType<String>()
                    .toList();
                expect(
                  bodyTexts,
                  isNotEmpty,
                  reason: '$role keeps primary preview content',
                );
                expect(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is Semantics &&
                        widget.properties.label ==
                            '${WidgetUiCopy.previewTitle(kind)} ${platform == TargetPlatform.android ? mode.previewCellLabel : mode.label}',
                  ),
                  findsOneWidget,
                );
                probe.rows.add({
                  'role': '$role body',
                  'height': tester.getSize(frame).height,
                  'texts': bodyTexts,
                });
                if (mode == WidgetDisplayMode.detailed &&
                    [
                      WidgetPreviewKind.todo,
                      WidgetPreviewKind.anniversary,
                    ].contains(kind)) {
                  await probe.reveal(find.text(title));
                  await probe.capture('${kind.name}-${locale.name}');
                }
              }
            }
            expect({
              for (final key in prefs.getKeys()) key: prefs.get(key),
            }, before);
            await probe.finish();
          });
        }
      }
    }
  }
}
