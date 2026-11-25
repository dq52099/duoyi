import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _specs = <(int, int, String Function(AppLocale))>[
  (1, 0, AdminUiCopy.defaultCoinsLabelFor),
  (1, 1, AdminUiCopy.maintenanceMessageLabelFor),
  (2, 1, _apiKey),
  (2, 2, AdminUiCopy.aiModelLabelFor),
  (2, 3, AdminUiCopy.aiDailyQuotaLabelFor),
  (3, 0, AdminUiCopy.backupMaxSizeLabelFor),
  (3, 1, AdminUiCopy.backupIntervalLabelFor),
  (3, 2, AdminUiCopy.backupRetainLabelFor),
  (3, 3, AdminUiCopy.serverBackupIntervalLabelFor),
  (3, 4, AdminUiCopy.serverBackupRetainLabelFor),
  (3, 5, _webDav),
  (3, 6, AdminUiCopy.openlistPublicUrlLabelFor),
  (3, 7, AdminUiCopy.openlistUserLabelFor),
  (3, 8, AdminUiCopy.openlistPasswordLabelFor),
  (3, 9, AdminUiCopy.openlistPathLabelFor),
];
String _apiKey(AppLocale _) => 'API Key';
String _webDav(AppLocale _) => 'OpenList WebDAV URL';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final large in [false, true]) {
        final name =
            '$brand-${locale.name}-${large ? '320px200percent' : 'ordinary'}';
        testWidgets('all settings field labels readable and accessible $name', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            final fixture = await _mount(tester, brand, locale, large, 1);
            final issues = <String>[];
            final observations = <Map<String, Object?>>[];
            var active = 1;
            for (final spec in _specs) {
              if (active != spec.$1) {
                final tabs = tester.widget<TabBar>(_topTabs()).controller!;
                tabs.animateTo(spec.$1);
                await tester.pumpAndSettle();
                active = spec.$1;
              }
              final label = spec.$3(locale);
              await _reveal(tester, _fieldForLabel(spec.$1, label), spec.$1);
              final field = _fieldForLabel(spec.$1, label);
              observations.add(_probe(tester, field, spec.$1, label, issues));
              await _capture(
                tester,
                fixture.key,
                'admin-fields-$name-${spec.$1}-${spec.$2}',
              );
              expect(tester.takeException(), isNull);
            }
            await _measure(tester, name, observations);
            expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
            expect(
              issues,
              isEmpty,
              reason:
                  'All 15 labels, glyph bounds, semantics and input targets must remain usable',
            );
          } finally {
            semantics.dispose();
          }
        });
      }
    }
    for (final module in [1, 2, 3]) {
      testWidgets(
        'retains edited field through mounted layout locale theme changes $brand module$module',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final fixture = await _mount(
              tester,
              brand,
              AppLocale.en,
              false,
              module,
            );
            final spec = _specs.lastWhere(
              (s) => s.$1 == module && (module != 3 || s.$2 == 8),
            );
            await _reveal(
              tester,
              _fieldForLabel(module, spec.$3(AppLocale.en)),
              module,
            );
            final initialField = _fieldForLabel(module, spec.$3(AppLocale.en));
            final controller = tester
                .widget<TextField>(initialField)
                .controller!;
            final field = find.descendant(
              of: _module(module),
              matching: find.byWidgetPredicate(
                (w) => w is TextField && identical(w.controller, controller),
              ),
            );
            final state = tester.state(find.byType(AdminScreen));
            final fieldState = tester.state(
              find.descendant(of: field, matching: find.byType(EditableText)),
            );
            final draft = module == 2 ? '2310' : 'synthetic-draft';
            await tester.enterText(field, draft);
            controller.selection = const TextSelection(
              baseOffset: 1,
              extentOffset: 3,
            );
            await tester.pumpAndSettle();
            final reads = fixture.requests.length;
            final focus = tester
                .widget<EditableText>(
                  find.descendant(
                    of: field,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode;
            expect(focus.hasFocus, isTrue);
            for (final step in [0, 1, 2, 3]) {
              if (step == 0) {
                tester.view.physicalSize = const Size(320, 844);
                fixture.scale.value = 2;
              } else if (step == 1) {
                I18n.setLocale(AppLocale.zh);
              } else if (step == 2) {
                await tester.runAsync(
                  () => fixture.theme.setBrand(
                    brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
                  ),
                );
              } else {
                tester.view.physicalSize = const Size(390, 844);
                fixture.scale.value = 1;
                I18n.setLocale(AppLocale.en);
              }
              await tester.pumpAndSettle();
              await _reveal(tester, field, module);
              final issues = <String>[];
              _probe(tester, field, module, spec.$3(I18n.current), issues);
              expect(issues, isEmpty);
              expect(tester.state(find.byType(AdminScreen)), same(state));
              expect(
                tester.state(
                  find.descendant(
                    of: field,
                    matching: find.byType(EditableText),
                  ),
                ),
                same(fieldState),
              );
              expect(
                tester.widget<TextField>(field).controller,
                same(controller),
              );
              expect(controller.text, draft);
              expect(
                controller.selection,
                const TextSelection(baseOffset: 1, extentOffset: 3),
              );
              expect(focus.hasFocus, isTrue);
              expect(tester.widget<TextField>(field).obscureText, module == 3);
              expect(
                fixture.requests.length,
                reads,
                reason: 'Mounted changes must not refetch or save',
              );
              await _capture(
                tester,
                fixture.key,
                'admin-fields-mounted-$brand-module$module-step$step',
              );
              expect(tester.takeException(), isNull);
            }
            expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}

Finder _topTabs() =>
    find.byWidgetPredicate((w) => w is TabBar && w.tabs.length == 10);
Finder _module(int index) => find.byKey(
  ValueKey('admin-${['dashboard', 'settings', 'ai', 'backup'][index]}-0'),
);
Finder _fieldForLabel(int module, String label) => find.descendant(
  of: _module(module),
  matching: find.byElementPredicate((element) {
    final widget = element.widget;
    if (widget is! TextField) return false;
    if (widget.decoration?.labelText == label) return true;
    var labeled = false;
    element.visitAncestorElements((ancestor) {
      final parent = ancestor.widget;
      if (parent is Semantics && parent.properties.label == label) {
        labeled = true;
        return false;
      }
      return true;
    });
    return labeled;
  }),
);
Future<void> _reveal(WidgetTester tester, Finder field, int module) async {
  final scroll = find
      .descendant(
        of: _module(module),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final state = tester.state<ScrollableState>(scroll);
  state.position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    field.hitTestable(),
    240,
    scrollable: scroll,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(field), alignment: .5);
  await tester.pumpAndSettle();
}

Map<String, Object?> _probe(
  WidgetTester tester,
  Finder field,
  int module,
  String label,
  List<String> issues,
) {
  final text = find.descendant(of: _module(module), matching: find.text(label));
  expect(
    text,
    findsOneWidget,
    reason: 'Fixture must locate the real label $label',
  );
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  final labelLaidOut = paragraph.hasSize && !paragraph.debugNeedsLayout;
  bool? exceededMaxLines;
  if (!labelLaidOut) {
    issues.add('$label: label not laid out for visible input');
  } else {
    exceededMaxLines = paragraph.didExceedMaxLines;
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    if (paragraph.didExceedMaxLines) issues.add('$label: truncated');
    if (painter.height > paragraph.size.height + .5 ||
        painter.width > paragraph.size.width + .5) {
      issues.add('$label: natural layout exceeds painted label');
    }
    final boxes = [
      for (final glyph in RegExp(r'\S', unicode: true).allMatches(label))
        ...paragraph.getBoxesForSelection(
          TextSelection(baseOffset: glyph.start, extentOffset: glyph.end),
        ),
    ];
    if (boxes.isEmpty) issues.add('$label: no painted glyphs');
    for (final box in boxes) {
      if (box.left < -.5 || box.right > paragraph.size.width + .5) {
        issues.add('$label: visible glyph outside label');
      }
    }
    painter.dispose();
  }
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  final node = tester.getSemantics(editable);
  if (!node.flagsCollection.isTextField || !node.label.contains(label)) {
    issues.add('$label: missing accessible input label');
  }
  if (label.allMatches(node.label).length != 1) {
    issues.add('$label: repeated accessible label');
  }
  final duplicates = tester.semantics.simulatedAccessibilityTraversal().where(
    (n) => !n.flagsCollection.isTextField && n.label.trim() == label,
  );
  if (duplicates.isNotEmpty) issues.add('$label: duplicate static semantics');
  final rect = tester.getRect(field);
  if (rect.height < 43.9) issues.add('$label: input height ${rect.height} <44');
  if (field.hitTestable().evaluate().isEmpty) {
    issues.add('$label: input unreachable');
  }
  return {
    'label': label,
    'labelLaidOut': labelLaidOut,
    'exceededMaxLines': exceededMaxLines,
    'labelSize': paragraph.hasSize
        ? [paragraph.size.width, paragraph.size.height]
        : null,
    'fieldHeight': rect.height,
    'semanticsLabel': node.label,
    'obscure': tester.widget<TextField>(field).obscureText,
  };
}

Future<void> _measure(
  WidgetTester tester,
  String name,
  List<Map<String, Object?>> rows,
) async {
  final directory =
      Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final file = File('$directory/admin-fields-$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(rows));
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _Auth extends AuthProvider {
  _Auth(this.api);
  final ApiClient api;
  @override
  AuthState get state => const AuthState(
    userId: 'synthetic-admin',
    username: 'synthetic-admin',
    token: 'synthetic-admin',
    isAdmin: true,
    adminPermissions: ['settings', 'ai', 'backup'],
  );
  @override
  ApiClient get client => api;
}

class _Fixture {
  _Fixture(this.theme, this.key, this.requests, this.scale);
  final ValueNotifier<double> scale;
  final ThemeProvider theme;
  final GlobalKey key;
  final List<http.Request> requests;
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String brand,
  AppLocale locale,
  bool large,
  int initialIndex,
) async {
  SharedPreferences.setMockInitialValues({
    'theme_shop_state': jsonEncode({
      'activeBrand': brand,
      'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
  });
  tester.view.physicalSize = Size(large ? 320 : 390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  I18n.setLocale(locale);
  final theme = ThemeProvider();
  await theme.loadFromStorage();
  await tester.runAsync(loadWeeklyReviewScreenshotFonts);
  final scale = ValueNotifier<double>(large ? 2 : 1);
  final requests = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-admin',
    httpClient: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      final Object body;
      if (path == '/api/admin/settings') {
        body = {
          'email_service_enabled': true,
          'email_code_primary_provider': 'claw163',
          'email_code_backup_provider': 'resend',
          'email_code_active_slot': 'primary',
        };
      } else if (path == '/api/admin/stats') {
        body = {
          'users': {'total': 0, 'admin': 0, 'active_7d': 0},
          'feedback': {'open': 0},
          'registration_series': [],
        };
      } else if (path == '/api/admin/groups' || path == '/api/admin/roles') {
        body = [];
      } else {
        body = {
          'items': [],
          'total': 0,
          'offset': 0,
          'limit': 20,
          'has_more': false,
        };
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final auth = _Auth(api);
  final ai = AiService()..attachClient(api);
  final key = GlobalKey();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    ai.dispose();
    auth.dispose();
    theme.dispose();
    scale.dispose();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, locale, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.brand.theme,
            locale: Locale(locale == AppLocale.en ? 'en' : 'zh'),
            supportedLocales: const [Locale('en'), Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: scale,
              builder: (context, scale, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: key, child: child!),
              ),
            ),
            home: BrandRouteSurface(
              remountOnLocaleChange: false,
              child: AdminScreen(initialTabIndex: initialIndex),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(theme, key, requests, scale);
}
