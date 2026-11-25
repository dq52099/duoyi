// Synthetic route rendering only; the HTTP client cannot reach a real service.
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
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

import '../support/secondary_route_render_probe.dart';
import '../support/weekly_review_screenshot_font.dart';

void main() {
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in [
        (name: 'common', size: const Size(390, 844), scale: 1.0),
        (name: 'narrow', size: const Size(320, 844), scale: 1.6),
        (name: 'large', size: const Size(320, 844), scale: 2.0),
        (name: 'landscape', size: const Size(568, 320), scale: 2.0),
        (name: 'desktop', size: const Size(1000, 720), scale: 1.1),
        (name: 'nonlinear', size: const Size(332, 844), scale: -1.0),
      ]) {
        final name = 'share-$brand-${locale.name}-${layout.name}';
        testWidgets('shared space text and retained route $name', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          I18n.setLocale(locale);
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final requests = <http.Request>[];
          final client = ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'synthetic-token',
            httpClient: MockClient((request) async {
              requests.add(request);
              // Only reads are expected; forms are cancelled without submission.
              expect(request.method, 'GET');
              expect(request.url.host, 'duoyi.test');
              final Object response;
              if (request.url.path == '/api/workspaces') {
                response = [
                  {
                    'id': 'space',
                    'name': 'Synthetic Space',
                    'owner_user_id': 'A',
                    'members': [
                      {
                        'workspace_id': 'space',
                        'user_id': 'A',
                        'username': 'Synthetic member',
                        'role': 'owner',
                      },
                    ],
                  },
                ];
              } else {
                expect(
                  request.url.path,
                  isIn([
                    '/api/workspaces/mentions',
                    '/api/workspaces/space/comments',
                    '/api/workspaces/space/activities',
                    '/api/workspaces/space/leaderboard',
                  ]),
                );
                response = [];
              }
              return http.Response(
                jsonEncode(response),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          final auth = AuthProvider(
            client: client,
            initialState: const AuthState(
              userId: 'A',
              username: 'synthetic-A',
              token: 'synthetic-token',
            ),
          );
          final share = ShareProvider()
            ..apiClientGetter = (() => auth.client)
            ..userIdGetter = (() => auth.state.userId);
          final theme = ThemeProvider();
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            share.dispose();
            auth.dispose();
            theme.dispose();
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<ShareProvider>.value(value: share),
              ],
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, selected, _) => MaterialApp(
                  locale: Locale(selected == AppLocale.en ? 'en' : 'zh'),
                  supportedLocales: const [Locale('en'), Locale('zh')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  theme: theme.brand.theme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: layout.scale < 0
                          ? const RouteProbeNonlinearScaler()
                          : TextScaler.linear(layout.scale),
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          key: const ValueKey('probe_open_route'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const BrandRouteSurface(child: ShareScreen()),
                            ),
                          ),
                          child: const Text('Open synthetic route'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('probe_open_route')));
          await tester.pumpAndSettle();
          expect(theme.brand.id, brand);
          expect(share.workspaces.single.name, 'Synthetic Space');
          final state = tester.state(find.byType(ShareScreen));
          final probe = RouteRenderProbe(tester, boundary, name);
          await probe.capture('top');
          await probe.text(
            find.text(ShareUiCopy.heroDescription()),
            role: 'hero description',
          );
          await probe.text(
            find.text(ShareUiCopy.myWorkspacesTitle()),
            role: 'section title',
          );
          await probe.text(
            find.text(ShareUiCopy.myWorkspacesSubtitle()),
            role: 'section description',
          );
          await probe.text(
            find.text('Synthetic Space'),
            role: 'workspace name',
          );
          final nameParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text('Synthetic Space'),
              matching: find.byType(RichText),
            ),
          );
          final nameContext = tester.element(find.text('Synthetic Space'));
          final wordPainter = TextPainter(
            text: TextSpan(text: 'Synthetic', style: nameParagraph.text.style),
            textDirection: Directionality.of(nameContext),
            textScaler: MediaQuery.textScalerOf(nameContext),
          )..layout();
          final wordWidth = wordPainter.width;
          wordPainter.dispose();
          probe.rows.add({
            'role': 'workspace title word width',
            'wordWidth': wordWidth,
            'availableWidth': nameParagraph.size.width,
          });
          if (wordWidth > nameParagraph.size.width + 0.1) {
            probe.errors.add(
              'workspace title splits an ordinary word: $wordWidth > ${nameParagraph.size.width}',
            );
          }
          await probe.text(
            find.text(ShareUiCopy.membersCount(1, WorkspaceRole.owner.label)),
            role: 'member count and role',
          );
          for (final tooltip in [
            ShareUiCopy.collaborationTooltip(),
            ShareUiCopy.createInviteTooltip(),
          ]) {
            final control = find.byTooltip(tooltip);
            await probe.reveal(control);
            final rect = tester.getRect(control);
            probe.rows.add({
              'role': 'workspace action target',
              'tooltip': tooltip,
              'width': rect.width,
              'height': rect.height,
            });
            if (rect.width < 43.99 || rect.height < 43.99) {
              probe.errors.add('$tooltip target ${rect.size} below44');
            }
            expect(control.hitTestable(), findsOneWidget);
          }
          await probe.capture('card');
          final beforeActions = requests.length;
          final collaboration = find.byTooltip(
            ShareUiCopy.collaborationTooltip(),
          );
          await probe.reveal(collaboration);
          await tester.tap(collaboration);
          await tester.pumpAndSettle();
          expect(
            find.text(ShareUiCopy.collaborationSheetTitle('Synthetic Space')),
            findsOneWidget,
          );
          expect(requests.length, beforeActions + 3);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(ShareScreen)), same(state));
          final invite = find.byTooltip(ShareUiCopy.createInviteTooltip());
          await probe.reveal(invite);
          await tester.tap(invite);
          await tester.pumpAndSettle();
          expect(find.text(ShareUiCopy.createInviteTitle()), findsOneWidget);
          final cancelInvite = find.widgetWithText(
            TextButton,
            ShareUiCopy.actionCancel(),
          );
          await probe.reveal(cancelInvite);
          await tester.tap(cancelInvite);
          await tester.pumpAndSettle();
          expect(find.text(ShareUiCopy.createInviteTitle()), findsNothing);
          expect(requests.length, beforeActions + 3);
          final beforeRequests = requests.length;
          // The landscape ListView legitimately disposes its offscreen hero.
          // Restore the actual scroll position before locating its New button.
          final list = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          list.position.jumpTo(0);
          await tester.pumpAndSettle();
          final create = find.widgetWithText(
            FilledButton,
            ShareUiCopy.actionNew(),
          );
          await probe.reveal(create);
          expect(create.hitTestable(), findsOneWidget);
          await tester.tap(create);
          await tester.pumpAndSettle();
          final field = find.byType(TextField);
          await tester.enterText(field, '原始 synthetic draft');
          final controller = tester.widget<TextField>(field).controller!;
          controller.selection = const TextSelection(
            baseOffset: 2,
            extentOffset: 7,
          );
          final draft = controller.value;
          I18n.setLocale(locale == AppLocale.en ? AppLocale.zh : AppLocale.en);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(ShareScreen)), same(state));
          expect(tester.widget<TextField>(field).controller, same(controller));
          expect(controller.value, draft);
          expect(requests.length, beforeRequests);
          await probe.capture('live-form');
          final cancel = find.widgetWithText(
            TextButton,
            ShareUiCopy.actionCancel(),
          );
          await probe.reveal(cancel);
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsNothing);
          await probe.text(
            find.text(ShareUiCopy.heroDescription()),
            role: 'live hero description',
          );
          await probe.text(
            find.text(ShareUiCopy.myWorkspacesSubtitle()),
            role: 'live section description',
          );
          list.position.jumpTo(list.position.maxScrollExtent);
          await tester.pumpAndSettle();
          await probe.text(
            find.text(ShareUiCopy.membersCount(1, WorkspaceRole.owner.label)),
            role: 'live member count and role',
          );
          expect(share.workspaces.single.name, 'Synthetic Space');
          expect(requests.length, beforeRequests);
          await probe.capture('live-card');
          await probe.finish();
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(find.byType(ShareScreen), findsNothing);
          expect(
            find.byKey(const ValueKey('probe_open_route')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
