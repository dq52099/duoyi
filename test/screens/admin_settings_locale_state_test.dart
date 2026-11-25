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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final index in [1, 2, 3]) {
    testWidgets(
      'admin settings module $index localizes without losing state or refetching',
      (tester) async {
        final requests = <String>[];
        final key = await _pump(tester, index, requests);
        final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
        final module = find.byKey(
          ValueKey(
            'admin-${['dashboard', 'settings', 'ai', 'backup'][index]}-0',
          ),
        );
        final moduleElement = tester.element(module);
        final scrollable = find
            .descendant(of: module, matching: find.byType(Scrollable))
            .first;
        final scrollState = tester.state<ScrollableState>(scrollable);
        final beforeRequests = List<String>.of(requests);
        final fields = find.descendant(
          of: module,
          matching: find.byType(TextField),
        );
        final field = fields.first;
        await tester.scrollUntilVisible(field, 160, scrollable: scrollable);
        final fieldWidget = tester.widget<TextField>(field);
        final draft =
            fieldWidget.keyboardType.index == TextInputType.number.index
            ? '2450'
            : 'literal / 保留草稿';
        await tester.enterText(field, draft);
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = TextSelection(
          baseOffset: 1,
          extentOffset: draft.length.clamp(1, 5),
        );
        final selection = controller.selection;
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(tester.element(module), same(moduleElement));
        expect(
          tester.widget<TabBar>(find.byType(TabBar)).controller,
          same(tabs),
        );
        expect(tabs.index, index);
        expect(tester.state<ScrollableState>(scrollable), same(scrollState));
        expect(controller.text, draft);
        expect(controller.selection, selection);
        expect(requests, beforeRequests);
        _expectEnglish(tester);
        await _capture(tester, key, 'module-$index-en-draft');
        // Every lazily built section must translate, including the bottom controls.
        final position = scrollState.position;
        position.jumpTo(0);
        await tester.pumpAndSettle();
        _expectEnglish(tester);
        await _capture(tester, key, 'module-$index-en-top');
        var steps = 0;
        while (position.pixels < position.maxScrollExtent && steps++ < 40) {
          position.jumpTo(
            (position.pixels + 420).clamp(0, position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
          _expectEnglish(tester);
          expect(tester.takeException(), isNull);
        }
        await _capture(tester, key, 'module-$index-en-bottom');
        expect(requests, beforeRequests);
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        expect(controller.text, draft);
        expect(requests, beforeRequests);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Future<GlobalKey> _pump(
  WidgetTester tester,
  int index,
  List<String> requests,
) async {
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final client = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-admin',
    httpClient: MockClient((request) async {
      requests.add(
        '${request.method} ${request.url.path}?${request.url.query}',
      );
      if (request.method != 'GET') {
        throw StateError('Unexpected rendering mutation');
      }
      final path = request.url.path;
      final scope = request.url.queryParameters['scope'];
      Object body;
      if (path == '/api/admin/settings') {
        body = switch (scope) {
          'ai' => {
            'ai_enabled': false,
            'ai_model': 'literal-model',
            'ai_api_key_set': false,
            'ai_daily_quota': 0,
          },
          'backup' => {
            'backup_enabled': false,
            'backup_max_size_kb': 2048,
            'backup_interval_minutes': 30,
            'backup_retain_days': 0,
            'server_backup_enabled': false,
            'local_backups': [],
            'reminder_email_enabled': false,
            'email_service_enabled': false,
          },
          _ => {
            'invite_code_required': false,
            'registration_enabled': true,
            'registration_email_required': false,
            'maintenance_mode': false,
            'force_update_required': false,
            'default_registration_coins': 100,
          },
        };
      } else if (path == '/api/admin/groups' || path == '/api/admin/roles') {
        body = [];
      } else if (path == '/api/admin/backups' ||
          path == '/api/admin/server-backups') {
        body = {'items': [], 'total': 0, 'limit': 50, 'offset': 0};
      } else {
        throw StateError('Unmocked request: $path');
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  final auth = _AdminAuth(client);
  final ai = AiService()..attachClient(client);
  final theme = ThemeProvider();
  addTearDown(auth.dispose);
  addTearDown(ai.dispose);
  addTearDown(theme.dispose);
  final fonts = widgetPolishScreenshotTheme();
  final key = GlobalKey();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: MaterialApp(
        theme: theme.brand.theme.copyWith(
          textTheme: fonts.textTheme,
          primaryTextTheme: fonts.primaryTextTheme,
        ),
        builder: (context, child) => RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
        ),
        home: AdminScreen(initialTabIndex: index),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(AdminUiCopy.reload), findsNothing);
  expect(tester.takeException(), isNull);
  return key;
}

void _expectEnglish(WidgetTester tester) {
  final chinese = RegExp(r'[\u3400-\u9fff]');
  final labels = <String>[
    for (final text in tester.widgetList<Text>(find.byType(Text)))
      text.data ?? text.textSpan?.toPlainText() ?? '',
    for (final tooltip in tester.widgetList<Tooltip>(find.byType(Tooltip)))
      tooltip.message ?? '',
    for (final field in tester.widgetList<TextField>(
      find.byType(TextField),
    )) ...[
      field.decoration?.labelText ?? '',
      field.decoration?.hintText ?? '',
      field.decoration?.helperText ?? '',
      field.decoration?.errorText ?? '',
    ],
  ];
  // Controller contents are user data and intentionally remain bilingual.
  expect(
    labels.where((text) => text != 'literal / 保留草稿' && chinese.hasMatch(text)),
    isEmpty,
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['DUOYI_CAPTURE_ADMIN_LOCALE_SCREENSHOTS'] != '1') {
    return;
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory =
        Platform.environment['DUOYI_ADMIN_SCREENSHOT_DIR'] ??
        'evidence/screenshots/admin-settings-locale-20261012';
    final file = File('$directory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _AdminAuth extends AuthProvider {
  final ApiClient fixture;
  _AdminAuth(this.fixture);
  @override
  ApiClient get client => fixture;
  @override
  AuthState get state => const AuthState(
    userId: 'synthetic-admin',
    token: 'synthetic-admin',
    isAdmin: true,
  );
}
