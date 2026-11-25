import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _groupId = 'group-literal-a';
const _groupName = 'Literal Group A';
const _groupDescription = 'Literal description A';
const _draftName = 'literal edit draft / 保留';
const _addedName = 'Literal Added Group';
const _addedDescription = 'Literal added description';
final _cjk = RegExp(r'[\u3400-\u9fff]');

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Groups zh-en-zh keeps the list, controllers, selection, focus, and dialog route',
    (tester) async {
      final fixture = await _mountGroups(tester, width: 320, textScale: 1.6);
      final module = find.byKey(const ValueKey('admin-groups-0'));
      expect(module, findsOneWidget);
      final moduleElement = tester.element(module);
      final group = find.descendant(
        of: module,
        matching: find.text(_groupName),
      );
      expect(group, findsOneWidget);
      final groupElement = tester.element(group);
      final scrollable = find
          .descendant(of: module, matching: find.byType(Scrollable))
          .first;
      final scrollState = tester.state<ScrollableState>(scrollable);

      await _openEditDialog(tester);
      final dialogRoute = fixture.routes.current;
      expect(dialogRoute, isNotNull);
      expect(find.byType(Dialog), findsOneWidget);
      final fields = _dialogFields(tester);
      expect(fields.length, greaterThanOrEqualTo(2));
      final nameField = fields.first;
      await tester.enterText(nameField, _draftName);
      final nameWidget = tester.widget<TextField>(nameField);
      final controller = nameWidget.controller!;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 9,
      );
      final selection = controller.selection;
      final focusNode = tester
          .widget<EditableText>(
            find.descendant(of: nameField, matching: find.byType(EditableText)),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(focusNode));
      final readsBefore = List<String>.of(fixture.requestLines);
      final routePushCount = fixture.routes.pushed.length;

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(module), same(moduleElement));
        expect(tester.element(group), same(groupElement));
        expect(tester.state<ScrollableState>(scrollable), same(scrollState));
        expect(fixture.routes.current, same(dialogRoute));
        expect(fixture.routes.pushed, hasLength(routePushCount));
        expect(controller.text, _draftName);
        expect(controller.selection, selection);
        expect(
          tester.widget<TextField>(_dialogFields(tester).first).controller,
          same(controller),
        );
        expect(FocusManager.instance.primaryFocus, same(focusNode));
        expect(fixture.requestLines, readsBefore);
        _expectDialogLocale(tester, locale);
        if (locale == AppLocale.en) {
          await _captureIfRequested(
            tester,
            fixture,
            'groups-320-1_6-en-edit-form',
          );
        }
        expect(tester.takeException(), isNull);
      }

      await _captureIfRequested(tester, fixture, 'groups-320-1_6-zh-edit-form');
      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.requestLines, readsBefore);
    },
  );

  for (final layout in const [
    (scale: 1.6, name: '1_6'),
    (scale: 2.0, name: '2_0'),
  ]) {
    testWidgets('Groups dialogs fit 320px at text scale ${layout.scale}', (
      tester,
    ) async {
      final fixture = await _mountGroups(
        tester,
        width: 320,
        textScale: layout.scale,
      );
      expect(find.byKey(const ValueKey('admin-groups-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _captureIfRequested(
        tester,
        fixture,
        'groups-320-${layout.name}-zh-populated',
      );

      await _openAddDialog(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);

      await _openEditDialog(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);

      await _openDeleteDialog(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      await _captureIfRequested(
        tester,
        fixture,
        'groups-320-${layout.name}-en-populated',
      );
      await _openAddDialog(tester);
      _expectDialogLocale(tester, AppLocale.en);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
      await _openEditDialog(tester);
      _expectDialogLocale(tester, AppLocale.en);
      await _captureIfRequested(
        tester,
        fixture,
        'groups-320-${layout.name}-en-form',
      );
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
      await _openDeleteDialog(tester);
      _expectDialogLocale(tester, AppLocale.en);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty Groups state localizes without another read', (
    tester,
  ) async {
    final fixture = await _mountGroups(
      tester,
      width: 320,
      textScale: 1.6,
      emptyGroups: true,
    );
    expect(find.text(AdminUiCopy.noGroups), findsOneWidget);
    final requests = List<String>.of(fixture.requestLines);
    await _captureIfRequested(tester, fixture, 'groups-320-1_6-zh-empty');

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text(AdminUiCopy.noGroups), findsOneWidget);
    expect(fixture.requestLines, requests);
    await _captureIfRequested(tester, fixture, 'groups-320-1_6-en-empty');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'add group success feedback follows the live locale and submits once',
    (tester) async {
      final fixture = await _mountGroups(tester);
      await _openAddDialog(tester);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(AdminUiCopy.addGroupTitle),
        ),
        findsOneWidget,
      );
      _expectDialogLocale(tester, AppLocale.zh);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectDialogLocale(tester, AppLocale.en);
      final fields = _dialogFields(tester);
      expect(fields.length, greaterThanOrEqualTo(2));
      await tester.enterText(fields[0], _addedName);
      await tester.enterText(fields[1], _addedDescription);

      final held = fixture.holdNextMutation();
      final submit = _primaryDialogCallback(tester);
      submit();
      submit(); // Reusing a retained callback must not dispatch a second write.
      await tester.pumpAndSettle();
      expect(fixture.groupMutations, hasLength(1));
      expect(fixture.mutationBodies.single['name'], _addedName);
      expect(fixture.mutationBodies.single['description'], _addedDescription);
      final readsWhilePending = List<String>.of(fixture.requestLines);

      expect(find.byType(Dialog), findsNothing);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(fixture.requestLines, readsWhilePending);
      held.complete(
        _jsonResponse({
          'id': 'group-added',
          'name': _addedName,
          'description': _addedDescription,
          'default_time_coins': 100,
          'is_active': true,
          'user_count': 0,
        }),
      );
      await tester.pumpAndSettle();

      expect(fixture.groupMutations, hasLength(1));
      expect(find.byType(Dialog), findsNothing);
      _expectSnackLocale(tester, AppLocale.zh);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.en);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit group error feedback follows locale and preserves submitted values',
    (tester) async {
      final fixture = await _mountGroups(tester);
      await _openEditDialog(tester);
      final fields = _dialogFields(tester);
      final nameField = fields.first;
      await tester.enterText(nameField, _draftName);
      final controller = tester.widget<TextField>(nameField).controller!;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 12,
      );
      final selection = controller.selection;

      final held = fixture.holdNextMutation();
      _primaryDialogCallback(tester)();
      await tester.pumpAndSettle();
      expect(fixture.groupMutations, hasLength(1));
      expect(find.byType(Dialog), findsNothing);
      expect(controller.text, _draftName);
      expect(controller.selection, selection);
      final readsWhilePending = List<String>.of(fixture.requestLines);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      held.complete(
        _jsonResponse({
          'detail': 'held synthetic group write failure',
        }, status: 500),
      );
      await tester.pumpAndSettle();

      expect(fixture.requestLines, readsWhilePending);
      expect(find.byType(Dialog), findsNothing);
      _expectSnackLocale(tester, AppLocale.en);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.zh);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'delete group dialog and success feedback follow locale changes',
    (tester) async {
      final fixture = await _mountGroups(tester, width: 320, textScale: 1.6);
      await _openDeleteDialog(tester);
      expect(find.byType(Dialog), findsOneWidget);
      _expectDialogLocale(tester, AppLocale.zh);
      await _captureIfRequested(
        tester,
        fixture,
        'groups-320-1_6-zh-delete-dialog',
      );
      final dialogRoute = fixture.routes.current;

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(dialogRoute));
      _expectDialogLocale(tester, AppLocale.en);
      await _captureIfRequested(
        tester,
        fixture,
        'groups-320-1_6-en-delete-dialog',
      );

      final held = fixture.holdNextMutation();
      _primaryDialogCallback(tester)();
      await tester.pumpAndSettle();
      expect(fixture.groupMutations, hasLength(1));
      expect(fixture.groupMutations.single.method, 'DELETE');
      expect(fixture.groupMutations.single.path, '/api/admin/groups/$_groupId');
      held.complete(_jsonResponse({}));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      _expectSnackLocale(tester, AppLocale.en);
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.zh);
      expect(tester.takeException(), isNull);
    },
  );

  for (final boundary in const [
    'auth replacement',
    'client replacement',
    'token change',
  ]) {
    testWidgets('retained Groups opener rejects $boundary', (tester) async {
      final fixture = await _mountGroups(tester);
      final staleOpen = _captureEditOpener(tester);

      switch (boundary) {
        case 'auth replacement':
          fixture.replaceAuth(
            AuthProvider(
              client: fixture.client,
              initialState: _adminState(userId: 'replacement-admin'),
            ),
          );
          await tester.pumpAndSettle();
          break;
        case 'client replacement':
          fixture.replaceClient(fixture.newClient(token: 'synthetic-admin'));
          await tester.pumpAndSettle();
          break;
        case 'token change':
          fixture.client.token = 'rotated-synthetic-token';
          break;
      }

      final requestsBeforeStaleCallback = List<String>.of(fixture.requestLines);
      staleOpen();
      await tester.pumpAndSettle();
      expect(fixture.requestLines, requestsBeforeStaleCallback);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'covered delete callback cannot pop the foreground route or write',
    (tester) async {
      final fixture = await _mountGroups(tester);
      await _openDeleteDialog(tester);
      final dialogRoute = fixture.routes.current;
      final confirmDelete = _primaryDialogCallback(tester);
      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('covering route'))),
      );
      unawaited(fixture.navigatorKey.currentState!.push<void>(coveringRoute));
      await tester.pumpAndSettle();
      final requestsBeforeCallback = List<String>.of(fixture.requestLines);

      confirmDelete();
      await tester.pumpAndSettle();
      expect(find.text('covering route'), findsOneWidget);
      expect(fixture.routes.current, same(coveringRoute));
      expect(fixture.groupMutations, isEmpty);
      expect(fixture.requestLines, requestsBeforeCallback);
      expect(dialogRoute, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired held Groups write has no reload or feedback and cannot duplicate',
    (tester) async {
      final fixture = await _mountGroups(tester);
      await _openEditDialog(tester);
      final fields = _dialogFields(tester);
      await tester.enterText(fields.first, _draftName);
      final held = fixture.holdNextMutation();
      final save = _primaryDialogCallback(tester);
      save();
      save();
      await tester.pumpAndSettle();
      expect(fixture.groupMutations, hasLength(1));
      expect(find.byType(Dialog), findsNothing);
      final readsBeforeInvalidation = List<String>.of(fixture.requestLines);
      fixture.client.token = 'rotated-while-request-is-pending';

      held.complete(
        _jsonResponse({
          'id': _groupId,
          'name': _draftName,
          'description': _groupDescription,
          'default_time_coins': 100,
          'is_active': true,
          'user_count': 2,
        }),
      );
      await tester.pumpAndSettle();

      expect(fixture.requestLines, readsBeforeInvalidation);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.groupMutations, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_GroupsFixture> _mountGroups(
  WidgetTester tester, {
  double width = 390,
  double height = 900,
  double textScale = 1,
  bool emptyGroups = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final fixture = _GroupsFixture(emptyGroups: emptyGroups);
  final fonts = widgetPolishScreenshotTheme();
  late StateSetter rebuildHost;
  await tester.pumpWidget(
    StatefulBuilder(
      builder: (context, setState) {
        rebuildHost = setState;
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
          ],
          child: MaterialApp(
            navigatorKey: fixture.navigatorKey,
            navigatorObservers: [fixture.routes],
            scaffoldMessengerKey: fixture.messengerKey,
            theme: fixture.theme.brand.theme.copyWith(
              textTheme: fonts.textTheme,
              primaryTextTheme: fonts.primaryTextTheme,
            ),
            builder: (context, child) => RepaintBoundary(
              key: fixture.screenshotKey,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
            ),
            home: const AdminScreen(initialTabIndex: 5),
          ),
        );
      },
    ),
  );
  fixture.rebuildHost = rebuildHost;
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('admin-groups-0')), findsOneWidget);
  expect(fixture.groupPageReads, hasLength(1));
  expect(tester.takeException(), isNull);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Future<void> _openAddDialog(WidgetTester tester) async {
  final add = find.text(AdminUiCopy.addGroupTitle).first;
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _openEditDialog(WidgetTester tester) async {
  final edit = _editButton();
  await tester.ensureVisible(edit);
  await tester.tap(edit);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _openDeleteDialog(WidgetTester tester) async {
  final delete = _deleteButton();
  await tester.ensureVisible(delete);
  await tester.tap(delete);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _closeDialog(WidgetTester tester, _GroupsFixture fixture) async {
  fixture.navigatorKey.currentState!.pop();
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsNothing);
}

Finder _editButton() => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton && widget.tooltip == AdminUiCopy.editGroupTooltip,
);

Finder _deleteButton() => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton && widget.tooltip == AdminUiCopy.deleteGroupTooltip,
);

VoidCallback _captureEditOpener(WidgetTester tester) {
  final finder = _editButton();
  expect(finder, findsOneWidget);
  return tester.widget<IconButton>(finder).onPressed!;
}

List<Finder> _dialogFields(WidgetTester tester) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  return find
      .descendant(of: dialog, matching: find.byType(TextField))
      .evaluate()
      .map((element) => find.byWidget(element.widget))
      .toList();
}

VoidCallback _primaryDialogCallback(WidgetTester tester) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  final buttons = find.descendant(
    of: dialog,
    matching: find.byType(FilledButton),
  );
  expect(buttons, findsWidgets);
  return tester.widget<FilledButton>(buttons.last).onPressed!;
}

void _expectDialogLocale(WidgetTester tester, AppLocale locale) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  final labels =
      <String>[
            for (final text in tester.widgetList<Text>(
              find.descendant(of: dialog, matching: find.byType(Text)),
            ))
              text.data ?? text.textSpan?.toPlainText() ?? '',
            for (final field in tester.widgetList<TextField>(
              find.descendant(of: dialog, matching: find.byType(TextField)),
            )) ...[
              field.decoration?.labelText ?? '',
              field.decoration?.hintText ?? '',
              field.decoration?.helperText ?? '',
              field.decoration?.errorText ?? '',
            ],
          ]
          .where(
            (text) =>
                text.isNotEmpty &&
                text != _groupName &&
                text != _groupDescription &&
                text != _draftName &&
                text != _addedName &&
                text != _addedDescription,
          )
          .toList();
  expect(labels, isNotEmpty);
  if (locale == AppLocale.en) {
    expect(labels.where(_cjk.hasMatch), isEmpty, reason: '$labels');
  } else {
    expect(labels.any(_cjk.hasMatch), isTrue, reason: '$labels');
  }
}

void _expectSnackLocale(WidgetTester tester, AppLocale locale) {
  final snack = find.byType(SnackBar);
  expect(snack, findsOneWidget);
  final message = tester
      .widgetList<Text>(find.descendant(of: snack, matching: find.byType(Text)))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .join(' ');
  expect(message, isNotEmpty);
  if (locale == AppLocale.en) {
    expect(_cjk.hasMatch(message), isFalse, reason: message);
  } else {
    expect(_cjk.hasMatch(message), isTrue, reason: message);
  }
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  _GroupsFixture fixture,
  String name,
) async {
  final directoryPath =
      Platform.environment['DUOYI_ADMIN_GROUPS_SCREENSHOT_DIR'];
  if (directoryPath == null || directoryPath.trim().isEmpty) return;
  final screenshotsRoot = Directory('evidence/screenshots').absolute.path;
  final outputDirectory = Directory(directoryPath).absolute.path;
  if (outputDirectory != screenshotsRoot &&
      !outputDirectory.startsWith(
        '$screenshotsRoot${Platform.pathSeparator}',
      )) {
    throw StateError(
      'DUOYI_ADMIN_GROUPS_SCREENSHOT_DIR must stay under evidence/screenshots/.',
    );
  }
  await tester.runAsync(() async {
    final boundary =
        fixture.screenshotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$outputDirectory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

AuthState _adminState({String userId = 'admin'}) => AuthState(
  userId: userId,
  username: 'admin',
  token: 'synthetic-admin',
  isAdmin: true,
  adminPermissions: const ['groups'],
);

http.Response _jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

class _GroupsFixture {
  _GroupsFixture({this.emptyGroups = false}) {
    auth = _SwitchableClientAuth(
      client: newClient(token: 'synthetic-admin'),
      state: _adminState(),
    );
    authProviders.add(auth);
  }

  final bool emptyGroups;
  final List<_CapturedRequest> requests = [];
  final List<Map<String, dynamic>> mutationBodies = [];
  final List<AuthProvider> authProviders = [];
  final List<http.Client> transports = [];
  final ThemeProvider theme = ThemeProvider();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey screenshotKey = GlobalKey();
  final _RecordingNavigatorObserver routes = _RecordingNavigatorObserver();
  late AuthProvider auth;
  late StateSetter rebuildHost;
  Completer<http.Response>? _nextMutation;

  ApiClient get client => auth.client;

  ApiClient newClient({required String token}) {
    final transport = MockClient(_handle);
    transports.add(transport);
    return ApiClient(
      baseUrl: 'https://duoyi.test',
      token: token,
      httpClient: transport,
    );
  }

  Completer<http.Response> holdNextMutation() {
    final completer = Completer<http.Response>();
    _nextMutation = completer;
    return completer;
  }

  List<_CapturedRequest> get groupReads => requests
      .where(
        (request) =>
            request.method == 'GET' && request.path == '/api/admin/groups',
      )
      .toList();

  List<_CapturedRequest> get groupPageReads => groupReads
      .where((request) => request.queryParameters['limit'] == '20')
      .toList();

  List<_CapturedRequest> get groupMutations => requests
      .where(
        (request) =>
            request.path.startsWith('/api/admin/groups') &&
            request.method != 'GET',
      )
      .toList();

  List<String> get requestLines =>
      requests.map((request) => request.line).toList();

  void replaceAuth(AuthProvider replacement) {
    auth = replacement;
    authProviders.add(replacement);
    rebuildHost(() {});
  }

  void replaceClient(ApiClient replacement) {
    final current = auth;
    if (current is! _SwitchableClientAuth) {
      throw StateError('The fixture AuthProvider cannot swap clients.');
    }
    current.replaceClient(replacement);
  }

  Future<http.Response> _handle(http.Request request) async {
    final captured = _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.query,
      body: request.body,
      queryParameters: Map<String, String>.of(request.url.queryParameters),
    );
    requests.add(captured);

    if (request.method == 'GET' && request.url.path == '/api/admin/groups') {
      final items = emptyGroups
          ? <Map<String, dynamic>>[]
          : <Map<String, dynamic>>[
              {
                'id': _groupId,
                'name': _groupName,
                'description': _groupDescription,
                'default_time_coins': 100,
                'is_active': true,
                'user_count': 2,
                'created_at': '2026-10-01 08:00:00',
                'updated_at': '2026-10-01 08:00:00',
              },
            ];
      return _jsonResponse({
        'items': items,
        'total': items.length,
        'limit': int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20,
        'offset':
            int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0,
        'has_more': false,
      });
    }

    if (request.method == 'GET') {
      final query = request.url.queryParameters;
      final limit = int.tryParse(query['limit'] ?? '') ?? 20;
      final offset = int.tryParse(query['offset'] ?? '') ?? 0;
      final emptyPage = _jsonResponse({
        'items': <Object>[],
        'total': 0,
        'limit': limit,
        'offset': offset,
        'has_more': false,
      });
      switch (request.url.path) {
        case '/api/admin/roles':
          return _jsonResponse(<Object>[]);
        case '/api/admin/stats':
          return _jsonResponse({
            'users': <String, Object>{'total': 0, 'disabled': 0},
            'feedback': <String, Object>{'total': 0, 'open': 0},
            'announcements': <String, Object>{'total': 0, 'published': 0},
            'invites': <String, Object>{'total': 0, 'used': 0},
            'registration_series': <Object>[],
          });
        case '/api/admin/settings':
          return _jsonResponse(switch (query['scope']) {
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
              'local_backups': <Object>[],
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
          });
        case '/api/admin/users':
        case '/api/admin/backups':
        case '/api/admin/server-backups':
        case '/api/admin/announcements':
        case '/api/admin/feedback':
        case '/api/admin/invite-codes':
        case '/api/admin/audit-log':
          return emptyPage;
      }
    }

    if (request.url.path.startsWith('/api/admin/groups') &&
        request.method != 'GET') {
      if (request.body.isNotEmpty) {
        mutationBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      final held = _nextMutation;
      _nextMutation = null;
      if (held != null) return held.future;
      if (request.method == 'DELETE') return _jsonResponse({});
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _jsonResponse({
        'id': request.method == 'POST' ? 'group-added' : _groupId,
        ...body,
        'user_count': request.method == 'POST' ? 0 : 2,
      });
    }

    throw StateError('Unexpected Groups fixture request: ${captured.line}');
  }

  void dispose() {
    for (final provider in authProviders) {
      provider.dispose();
    }
    for (final transport in transports) {
      transport.close();
    }
    theme.dispose();
  }
}

class _SwitchableClientAuth extends AuthProvider {
  _SwitchableClientAuth({required ApiClient client, required AuthState state})
    : _currentClient = client,
      super(client: client, initialState: state);

  ApiClient _currentClient;

  @override
  ApiClient get client => _currentClient;

  void replaceClient(ApiClient client) {
    _currentClient = client;
    notifyListeners();
  }
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.queryParameters,
  });

  final String method;
  final String path;
  final String query;
  final String body;
  final Map<String, String> queryParameters;

  String get line => '$method $path${query.isEmpty ? '' : '?$query'}';
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> _stack = [];

  Route<dynamic>? get current => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    _stack.remove(route);
    _stack.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    if (previousRoute != null && !_stack.contains(previousRoute)) {
      _stack.add(previousRoute);
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final index = _stack.indexOf(oldRoute);
      if (index >= 0) _stack.removeAt(index);
      if (newRoute != null) {
        _stack.insert(index < 0 ? _stack.length : index, newRoute);
      }
      if (newRoute != null) pushed.add(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
