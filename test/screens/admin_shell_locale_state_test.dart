import 'package:shared_preferences/shared_preferences.dart';
import '../support/widget_polish_screenshot_font.dart';
import '../support/rendered_control_contrast.dart';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      testWidgets(
        'priority admin ordinary actions are readable $brand ${locale.name}',
        (tester) => withControlEvidenceShadows(() async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          final theme = ThemeProvider();
          await theme.loadFromStorage();
          I18n.setLocale(locale);
          await tester.runAsync(loadWidgetPolishScreenshotFonts);
          final auth = _AdminAuth(
            ApiClient(
              baseUrl: 'https://duoyi.test',
              token: 'synthetic-admin',
              httpClient: MockClient(
                (request) async => http.Response('{}', 200),
              ),
            ),
            unrestricted: true,
          );
          final key = GlobalKey();
          await _pump(
            tester,
            auth,
            initialTabIndex: 1,
            themeOverride: theme,
            captureKey: key,
          );
          for (final label in [
            AdminUiCopy.addGroupBtnFor(locale),
            AdminUiCopy.addRoleBtnFor(locale),
          ]) {
            final labelFinder = find.descendant(
              of: find.byWidgetPredicate((widget) => widget is TextButton),
              matching: find.text(label),
            );
            final scrollable = find
                .byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                )
                .first;
            await tester.scrollUntilVisible(
              labelFinder,
              400,
              scrollable: scrollable,
              maxScrolls: 60,
            );
            await Scrollable.ensureVisible(
              tester.element(labelFinder),
              alignment: 0.4,
            );
            await tester.pumpAndSettle();
            final control = find.ancestor(
              of: labelFinder,
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton,
              ),
            );
            expect(control, findsOneWidget);
            expect(tester.widget<TextButton>(control).onPressed, isNotNull);
            expectReadableControl(tester, control);
            final material = tester.widget<Material>(
              find
                  .descendant(of: control, matching: find.byType(Material))
                  .first,
            );
            expect(material.shape, isA<RoundedRectangleBorder>());
            expect(
              (material.shape! as RoundedRectangleBorder).borderRadius.resolve(
                TextDirection.ltr,
              ),
              BorderRadius.circular(12),
            );
          }
          await captureControlPage(tester, key, 'admin-$brand-${locale.name}');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }),
      );
    }
  }

  testWidgets('admin locale preserves dashboard, tabs, scroll and requests', (
    tester,
  ) async {
    final requests = <String>[];
    final auth = _AdminAuth(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'synthetic-admin',
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'users': {'total': 24, 'admin': 2, 'active_7d': 11},
              'feedback': {'open': 3},
              'registration_series': [
                {'date': 'literal-date / 日期保留', 'count': 4},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    await _pump(tester, auth);
    expect(requests, ['/api/admin/stats']);
    final screenState = tester.state(find.byType(AdminScreen));
    final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    final dashboard = find.descendant(
      of: find.byType(TabBarView),
      matching: find.byType(ListView),
    );
    final scrollable = find
        .descendant(of: dashboard, matching: find.byType(Scrollable))
        .first;
    final scrollState = tester.state<ScrollableState>(scrollable);
    final position = scrollState.position;
    position.jumpTo(140);
    await tester.pumpAndSettle();
    final offset = position.pixels;
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AdminScreen)), same(screenState));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller, same(tabs));
    expect(tabs.index, 0);
    expect(tester.state<ScrollableState>(scrollable), same(scrollState));
    expect(scrollState.position.pixels, offset);
    expect(requests, ['/api/admin/stats']);
    _expectEnglish(tester, literal: 'literal-date / 日期保留');
    await tester.scrollUntilVisible(
      find.text('literal-date / 日期保留'),
      250,
      scrollable: scrollable,
    );
    expect(find.text('literal-date / 日期保留'), findsOneWidget);
    _expectEnglish(tester, literal: 'literal-date / 日期保留');
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AdminScreen)), same(screenState));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller, same(tabs));
    expect(requests, ['/api/admin/stats']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('admin switcher and denied module update while open', (
    tester,
  ) async {
    final requests = <String>[];
    final auth = _AdminAuth(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'synthetic-admin',
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response('{}', 200);
        }),
      ),
    );
    await _pump(tester, auth, initialTabIndex: 1);
    final screenState = tester.state(find.byType(AdminScreen));
    final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(tabs.index, 1);
    expect(requests, isEmpty);
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    final menuItem = tester.element(find.byType(PopupMenuItem<int>).first);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(menuItem.mounted, isTrue);
    _expectEnglish(tester);
    expect(tester.state(find.byType(AdminScreen)), same(screenState));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller, same(tabs));
    expect(tabs.index, 1);
    expect(requests, isEmpty);
    await tester.tap(find.byType(PopupMenuItem<int>).at(1));
    await tester.pumpAndSettle();
    expect(tabs.index, 1);
    _expectEnglish(tester);
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pump(
  WidgetTester tester,
  _AdminAuth auth, {
  int initialTabIndex = 0,
  ThemeProvider? themeOverride,
  GlobalKey? captureKey,
}) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(auth.dispose);
  final theme = themeOverride ?? ThemeProvider();
  addTearDown(theme.dispose);
  final base = theme.brand.theme;
  final fonts = base.textTheme.apply(
    fontFamily: captureKey == null ? null : 'DuoyiScreenshotLatin',
    fontFamilyFallback: captureKey == null ? null : const ['DuoyiScreenshot'],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        theme: captureKey == null
            ? base
            : base.copyWith(textTheme: fonts, primaryTextTheme: fonts),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: RepaintBoundary(
            key: captureKey,
            child: BrandRouteSurface(
              child: AdminScreen(initialTabIndex: initialTabIndex),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectEnglish(WidgetTester tester, {String? literal}) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final labels = <String>[
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      text.data ?? text.textSpan?.toPlainText() ?? '',
    for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
      tooltip.message ?? '',
  ];
  expect(
    labels.where((value) => value != literal && chinese.hasMatch(value)),
    isEmpty,
  );
}

class _AdminAuth extends AuthProvider {
  final ApiClient _fixtureClient;
  final bool unrestricted;
  _AdminAuth(this._fixtureClient, {this.unrestricted = false});
  @override
  ApiClient get client => _fixtureClient;
  @override
  AuthState get state => AuthState(
    userId: 'synthetic-admin',
    token: 'synthetic-admin',
    isAdmin: true,
    adminPermissions: unrestricted ? null : const ['fixture-denied'],
  );
}
