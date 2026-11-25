import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/screens/lock_settings_screen.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/priority_theme_fixture.dart' show priorityLayouts;
import '../support/secondary_route_render_probe.dart'
    show RouteProbeNonlinearScaler;
import '../support/weekly_review_screenshot_font.dart';

enum _Page {
  preferences,
  personalization,
  bottomNav,
  shareGuest,
  shareSignedIn,
  adminGuest,
  adminSignedIn,
  lock,
  more,
  profileLocal,
  profileAccount,
}

Widget _screen(_Page page) => switch (page) {
  _Page.preferences => const PreferencesScreen(),
  _Page.personalization => const PersonalizationSettingsScreen(),
  _Page.bottomNav => const BottomNavSettingsScreen(),
  _Page.shareGuest || _Page.shareSignedIn => const ShareScreen(),
  _Page.adminGuest ||
  _Page.adminSignedIn => const AdminScreen(initialTabIndex: 1),
  _Page.lock => const LockSettingsScreen(),
  _Page.more => const MoreApplicationsScreen(
    visibleBottomNavTabs: [0, 1, 2, 6],
  ),
  _Page.profileLocal || _Page.profileAccount => const ProfileScreen(),
};
bool _plain(_Page page) =>
    [_Page.personalization, _Page.bottomNav].contains(page);
bool _profile(_Page page) =>
    [_Page.profileLocal, _Page.profileAccount].contains(page);

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass', 're0', 'starRail']) {
    for (final page in _Page.values) {
      for (final pushed in [false, true]) {
        for (final layout
            in brand == 're0' || brand == 'starRail'
                ? [priorityLayouts[1]]
                : priorityLayouts) {
          final name =
              '$brand-${page.name}-${pushed ? "pushed" : "standalone"}-${layout.name}';
          testWidgets('settings backdrop $name', (tester) async {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(AppLocale.zh);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final theme = ThemeProvider();
            final transport = MockClient((request) async {
              expect(request.method, 'GET');
              expect(request.url.host, 'synthetic.example.test');
              expect(
                request.url.path,
                isIn(['/api/workspaces', '/api/workspaces/mentions']),
              );
              return http.Response(
                '[]',
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            });
            final signedIn = [
              _Page.shareSignedIn,
              _Page.adminSignedIn,
              _Page.profileAccount,
            ].contains(page);
            final auth = AuthProvider(
              client: ApiClient(
                baseUrl: 'https://synthetic.example.test',
                token: signedIn ? 'synthetic-token' : null,
                httpClient: transport,
              ),
              initialState: AuthState(
                userId: signedIn ? 'synthetic-user' : null,
                username: 'Synthetic',
                token: signedIn ? 'synthetic-token' : null,
                isAdmin: page == _Page.adminSignedIn,
                adminPermissions: const ['fixture-denied'],
              ),
            );
            final ai = AiService();
            final prefs = PreferencesProvider();
            final lock = AppLockProvider();
            final user = UserProvider();
            final share = ShareProvider()
              ..apiClientGetter = (() => auth.client)
              ..userIdGetter = (() => auth.state.userId);
            final updater = AppUpdateService(
              repo: 'synthetic/unused',
              currentVersion: '0.0.0',
            );
            await tester.runAsync(() async {
              await theme.loadFromStorage();
              await loadWeeklyReviewScreenshotFonts();
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpAndSettle();
              for (final provider in <ChangeNotifier>[
                theme,
                auth,
                ai,
                prefs,
                lock,
                user,
                share,
                updater,
              ]) {
                provider.dispose();
              }
              transport.close();
            });
            final capture = GlobalKey();
            final screen = _screen(page);
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                  ChangeNotifierProvider<AuthProvider>.value(value: auth),
                  ChangeNotifierProvider<AiService>.value(value: ai),
                  ChangeNotifierProvider<PreferencesProvider>.value(
                    value: prefs,
                  ),
                  ChangeNotifierProvider<AppLockProvider>.value(value: lock),
                  ChangeNotifierProvider<UserProvider>.value(value: user),
                  ChangeNotifierProvider<ShareProvider>.value(value: share),
                  ChangeNotifierProvider<AppUpdateService>.value(
                    value: updater,
                  ),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme,
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: capture, child: child!),
                  ),
                  home: pushed
                      ? Builder(
                          builder: (context) => Scaffold(
                            body: TextButton(
                              key: const ValueKey('open_secondary_backdrop'),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  // Feedback submission is a plain route in production.
                                  builder: (_) => _plain(page)
                                      ? screen
                                      : BrandRouteSurface(
                                          remountOnLocaleChange: _profile(page)
                                              ? false
                                              : true,
                                          child: screen,
                                        ),
                                ),
                              ),
                              child: const Text('Open synthetic route'),
                            ),
                          ),
                        )
                      : screen,
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (pushed) {
              await tester.tap(
                find.byKey(const ValueKey('open_secondary_backdrop')),
              );
              await tester.pumpAndSettle();
            }
            expect(theme.brand.id, brand);
            final finder = find.byWidget(screen);
            final element = tester.element(finder);
            final retainedElements = <String, bool>{};
            TextEditingController? draft;
            if (_profile(page)) {
              final field = find.byType(TextField).first;
              draft = tester.widget<TextField>(field).controller!;
              draft.value = const TextEditingValue(
                text: 'Synthetic draft',
                selection: TextSelection.collapsed(offset: 5),
              );
              await tester.pumpAndSettle();
            }
            final points = [
              for (final f in [.35, .65, .9]) Offset(2, layout.size.height * f),
            ];
            final actual = <String, List<int>>{};
            final backgroundLayers = <String, int>{};
            final errors = <Object>[];
            for (final selected in [AppLocale.zh, AppLocale.en]) {
              I18n.setLocale(selected);
              await tester.pumpAndSettle();
              retainedElements[selected.name] = identical(
                tester.element(finder),
                element,
              );
              if (!(page == _Page.more && pushed)) {
                expect(tester.element(finder), same(element));
              }
              if (draft != null) {
                expect(
                  tester
                      .widget<TextField>(find.byType(TextField).first)
                      .controller,
                  same(draft),
                );
                expect(draft.text, 'Synthetic draft');
                expect(draft.selection.baseOffset, 5);
              }
              actual[selected.name] = await _pixels(tester, capture, points);
              backgroundLayers[selected.name] = find
                  .byType(BrandBackground)
                  .evaluate()
                  .length;
              await _screenshot(tester, capture, '$name-${selected.name}');
              final error = tester.takeException();
              if (error != null) errors.add(error);
            }
            if (pushed) {
              Navigator.of(tester.element(finder)).pop();
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('open_secondary_backdrop')),
                findsOneWidget,
              );
            }
            final reference = GlobalKey();
            final t = theme.brand.theme;
            final routeBackground = _profile(page) && !pushed
                ? Colors.transparent
                : t.brightness == Brightness.dark
                ? t.colorScheme.surface
                : t.colorScheme.surfaceContainerLowest;
            final referenceBrand =
                brand == 'liquidGlass' || (_profile(page) && pushed);
            // Independent reference is rendered only AFTER removing the page.
            await tester.pumpWidget(
              ChangeNotifierProvider<ThemeProvider>.value(
                value: theme,
                child: MaterialApp(
                  theme: t,
                  home: RepaintBoundary(
                    key: reference,
                    child: Material(
                      color: routeBackground,
                      child: referenceBrand
                          ? const BrandBackground(child: SizedBox.expand())
                          : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected = await _pixels(tester, reference, points);
            final output =
                Platform.environment['DUOYI_ROUTE_BACKDROP_EVIDENCE'];
            if (output != null) {
              await tester.runAsync(() async {
                final file = File('$output/$name.json');
                file.parent.createSync(recursive: true);
                file.writeAsStringSync(
                  jsonEncode({
                    'name': name,
                    'brand': brand,
                    'page': page.name,
                    'actual': actual,
                    'backgroundLayers': backgroundLayers,
                    'reference': expected,
                    'renderErrors': [for (final error in errors) '$error'],
                    'retainedElements': retainedElements,
                    'profileDraftRetained': draft != null,
                    'pushed': pushed,
                  }),
                );
              });
            }
            for (final entry in actual.entries) {
              expect(
                entry.value,
                expected,
                reason: '$name ${entry.key}: preserve route background policy',
              );
            }
            expect(errors, isEmpty, reason: '$name: no rendering errors');
            final expectedLayers =
                brand == 'liquidGlass' || (pushed && !_plain(page)) ? 1 : 0;
            for (final count in backgroundLayers.values) {
              expect(
                count,
                expectedLayers,
                reason: '$name: background is owned once',
              );
            }
          });
        }
      }
    }
  }
}

Future<List<int>> _pixels(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async => (await tester.runAsync(() async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return [
      for (final point in points)
        data.getUint32((point.dy.floor() * image.width + point.dx.floor()) * 4),
    ];
  } finally {
    image.dispose();
  }
}))!;

Future<void> _screenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final output = Platform.environment['DUOYI_ROUTE_BACKDROP_SCREENSHOTS'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$output/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
