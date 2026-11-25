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
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final large in [false, true]) {
        final name =
            '$brand-${locale.name}-${large ? '320px200percent' : 'ordinary'}';
        testWidgets('module tab labels stay complete and stable $name', (
          tester,
        ) async {
          final fixture = await _mount(tester, brand, locale, large);
          final bar = _topTabs();
          final controller = tester.widget<TabBar>(bar).controller!;
          for (var index = 0; index < 10; index++) {
            final label = find.descendant(
              of: bar,
              matching: find.text(AdminUiCopy.tabTitleForIndex(index, locale)),
            );
            await Scrollable.ensureVisible(
              tester.element(label),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            _expectComplete(tester, label);
            final tab = find.ancestor(of: label, matching: find.byType(Tab));
            final width = tester.getSize(tab).width;
            final rect = tester.getRect(label);
            final viewport = tester.getRect(bar);
            expect(rect.left, greaterThanOrEqualTo(viewport.left - .5));
            expect(rect.right, lessThanOrEqualTo(viewport.right + .5));
            await tester.tap(label);
            await tester.pumpAndSettle();
            expect(controller.index, index);
            expect(
              tester.getSize(tab).width,
              width,
              reason: 'Selecting must not change the tab width',
            );
            _expectComplete(tester, label);
            await _capture(tester, fixture.key, 'admin-nav-$name-$index');
            expect(tester.takeException(), isNull);
          }
          expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
        });

        testWidgets('selected mail channel and menu stay complete $name', (
          tester,
        ) async {
          final fixture = await _mount(tester, brand, locale, large);
          await _channel(tester, locale, 'primary');
          await _capture(tester, fixture.key, 'admin-channel-$name-primary');
          await tester.tap(_channelField());
          await tester.pumpAndSettle();
          final menu = find.byWidgetPredicate(
            (w) => w is PopupMenuItem<String>,
          );
          expect(menu, findsNWidgets(2));
          for (final value in ['primary', 'backup']) {
            final label = find.descendant(
              of: menu,
              matching: find.text(_channelLabel(locale, value)),
            );
            await tester.ensureVisible(label);
            await tester.pumpAndSettle();
            _expectComplete(tester, label);
          }
          final backup = find.descendant(
            of: menu,
            matching: find.text(_channelLabel(locale, 'backup')),
          );
          await tester.tap(backup);
          await tester.pumpAndSettle();
          await _channel(tester, locale, 'backup');
          await _capture(tester, fixture.key, 'admin-channel-$name-backup');
          expect(menu, findsNothing);
          expect(
            fixture.requests.where((r) => r.method != 'GET'),
            isEmpty,
            reason: 'Changing the local selection must not save or send mail',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
      'retains active module and selected mail value across mounted changes $brand',
      (tester) async {
        final fixture = await _mount(tester, brand, AppLocale.en, true);
        final state = tester.state(find.byType(AdminScreen));
        final controller = tester.widget<TabBar>(_topTabs()).controller!;
        await _channel(tester, AppLocale.en, 'primary');
        await tester.tap(_channelField());
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byWidgetPredicate((w) => w is PopupMenuItem<String>),
            matching: find.text(_channelLabel(AppLocale.en, 'backup')),
          ),
        );
        await tester.pumpAndSettle();
        final fieldState = tester.state<FormFieldState<String>>(
          find.descendant(
            of: _channelField(),
            matching: find.byType(FormField<String>),
          ),
        );
        final reads = fixture.requests.length;
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => fixture.theme.setBrand(
            brand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
          ),
        );
        await tester.pumpAndSettle();
        await _channel(tester, AppLocale.zh, 'backup');
        expect(tester.state(find.byType(AdminScreen)), same(state));
        expect(tester.widget<TabBar>(_topTabs()).controller, same(controller));
        expect(controller.index, 3);
        expect(
          tester.state<FormFieldState<String>>(
            find.descendant(
              of: _channelField(),
              matching: find.byType(FormField<String>),
            ),
          ),
          same(fieldState),
        );
        expect(fieldState.value, 'backup');
        expect(
          fixture.requests.length,
          reads,
          reason: 'Mounted locale/theme changes must not reload settings',
        );
        final tabLabel = find.descendant(
          of: _topTabs(),
          matching: find.text(AdminUiCopy.tabTitleForIndex(3, AppLocale.zh)),
        );
        await Scrollable.ensureVisible(tester.element(tabLabel), alignment: .5);
        await tester.pumpAndSettle();
        _expectComplete(tester, tabLabel);
        await _capture(tester, fixture.key, 'admin-channel-mounted-$brand');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _topTabs() =>
    find.byWidgetPredicate((w) => w is TabBar && w.tabs.length == 10);
Finder _channelField() => find.byWidgetPredicate(
  (w) =>
      w is AppDropdownField<String> && w.items.any((i) => i.value == 'primary'),
);
String _channelLabel(AppLocale locale, String value) => value == 'primary'
    ? AdminUiCopy.primaryChannelItemFor(locale)
    : AdminUiCopy.backupChannelItemFor(locale);

Future<void> _channel(
  WidgetTester tester,
  AppLocale locale,
  String value,
) async {
  final field = _channelField();
  final scroll = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  await tester.scrollUntilVisible(
    field,
    300,
    scrollable: scroll,
    maxScrolls: 100,
  );
  await Scrollable.ensureVisible(tester.element(field), alignment: .5);
  await tester.pumpAndSettle();
  final label = find.descendant(
    of: field,
    matching: find.text(_channelLabel(locale, value)),
  );
  expect(label, findsOneWidget);
  _expectComplete(tester, label);
  expect(
    tester
        .state<FormFieldState<String>>(
          find.descendant(of: field, matching: find.byType(FormField<String>)),
        )
        .value,
    value,
  );
  expect(field.hitTestable(), findsOneWidget);
}

void _expectComplete(WidgetTester tester, Finder label) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: label, matching: find.byType(RichText)),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: paragraph.text.toPlainText(),
  );
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  expect(painter.height, lessThanOrEqualTo(paragraph.size.height + .5));
  expect(painter.width, lessThanOrEqualTo(paragraph.size.width + .5));
  painter.dispose();
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
  _Fixture(this.theme, this.key, this.requests);
  final ThemeProvider theme;
  final GlobalKey key;
  final List<http.Request> requests;
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String brand,
  AppLocale locale,
  bool large,
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: const BrandRouteSurface(
              remountOnLocaleChange: false,
              child: AdminScreen(initialTabIndex: 3),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(theme, key, requests);
}
