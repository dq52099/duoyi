import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/share_ui_copy.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'active_brand': 'defaultBrand',
      'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    });
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('generated invite result follows live brand and locale', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' && request.url.path == '/api/workspaces') {
          return _json([
            {
              'id': 'space',
              'name': 'Synthetic Space',
              'owner_user_id': 'user-A',
              'members': [
                {
                  'workspace_id': 'space',
                  'user_id': 'user-A',
                  'username': 'Synthetic owner',
                  'role': 'owner',
                },
              ],
            },
          ]);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/workspaces/space/invites') {
          return _json({
            'id': 'invite-1',
            'workspace_id': 'space',
            'code': 'SYNTHETIC-INVITE-CODE',
            'role': 'viewer',
          });
        }
        return _json([]);
      }),
    );
    final auth = AuthProvider(
      client: client,
      initialState: const AuthState(
        userId: 'user-A',
        username: 'synthetic-user',
        token: 'synthetic-token',
      ),
    );
    final share = ShareProvider()
      ..apiClientGetter = (() => auth.client)
      ..userIdGetter = (() => auth.state.userId);
    final theme = ThemeProvider();
    await tester.runAsync(theme.loadFromStorage);
    addTearDown(() {
      share.dispose();
      auth.dispose();
      theme.dispose();
    });

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ShareProvider>.value(value: share),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, current, _) => MaterialApp(
            navigatorKey: navigatorKey,
            theme: current.brand.theme,
            home: const BrandRouteSurface(child: ShareScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(ShareUiCopy.createInviteTooltip()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, ShareUiCopy.actionGenerate()),
    );
    await tester.pumpAndSettle();

    final resultDialog = find.byType(AppDialog);
    expect(resultDialog, findsOneWidget);
    final resultElement = tester.element(resultDialog);
    final resultRoute = ModalRoute.of(resultElement);
    final createRequests = requests.where(
      (request) => request.method == 'POST',
    );
    expect(createRequests, hasLength(1));
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'SYNTHETIC-INVITE-CODE\n\n${ShareUiCopy.roleLabelPrefix(WorkspaceRole.viewer.labelFor(AppLocale.zh), AppLocale.zh)}',
    );
    expect(
      appSurfaceStyleOf(resultElement),
      isNot(AppSurfaceStyle.liquidGlass),
    );

    for (final brand in ['liquidGlass', 'defaultBrand']) {
      await tester.runAsync(() async {
        expect(await theme.setBrand(brand), isTrue);
      });
      await tester.pumpAndSettle();
      expect(tester.element(resultDialog), same(resultElement));
      expect(ModalRoute.of(tester.element(resultDialog)), same(resultRoute));
      expect(
        Theme.of(tester.element(resultDialog)).colorScheme.primary,
        brand == 'liquidGlass'
            ? AppBrands.liquidGlass.theme.colorScheme.primary
            : AppBrands.defaultBrand.theme.colorScheme.primary,
      );
      expect(
        appSurfaceStyleOf(tester.element(resultDialog)),
        brand == 'liquidGlass'
            ? AppSurfaceStyle.liquidGlass
            : isNot(AppSurfaceStyle.liquidGlass),
      );
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        'SYNTHETIC-INVITE-CODE\n\n${ShareUiCopy.roleLabelPrefix(WorkspaceRole.viewer.labelFor(AppLocale.zh), AppLocale.zh)}',
      );
      expect(tester.takeException(), isNull);
    }

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('Invite Code Copied'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'SYNTHETIC-INVITE-CODE\n\n${ShareUiCopy.roleLabelPrefix(WorkspaceRole.viewer.labelFor(AppLocale.en), AppLocale.en)}',
    );
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsNothing);
    expect(navigatorKey.currentState?.canPop(), isFalse);
    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
