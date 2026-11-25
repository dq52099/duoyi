import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('Admin module 1 settings error follows locale while visible', (
    tester,
  ) async {
    final fixture = await _pumpAdmin(tester, 1);
    final draft = await _enterDraft(
      tester,
      1,
      AdminUiCopy.maintenanceMessageLabelFor(AppLocale.zh),
      'literal settings draft',
    );

    await _checkPendingWriteFeedback(
      tester,
      fixture,
      draft: draft,
      submit: () async {
        final title = find.text(
          AdminUiCopy.maintenanceModeTitleFor(AppLocale.zh),
        );
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        await tester.tap(title);
        await tester.pumpAndSettle();
      },
      expected: (locale) => userVisibleApiError(
        ApiException('500: held synthetic write failure'),
        locale: locale,
      ),
      successful: false,
    );
  });

  testWidgets('Admin module 2 AI save error follows locale while visible', (
    tester,
  ) async {
    final fixture = await _pumpAdmin(tester, 2);
    final draft = await _enterDraft(
      tester,
      2,
      AdminUiCopy.aiModelLabelFor(AppLocale.zh),
      'literal AI model draft',
    );

    await _checkPendingWriteFeedback(
      tester,
      fixture,
      draft: draft,
      submit: () async {
        final save = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveFor(AppLocale.zh),
        );
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
      },
      expected: (locale) => AdminUiCopy.formatActionError(
        ApiException('500: held synthetic write failure'),
        AdminUiCopy.actionSaveAiConfigFor(locale),
        locale: locale,
      ),
      successful: false,
    );
  });

  testWidgets('Admin module 3 backup save error follows locale while visible', (
    tester,
  ) async {
    final fixture = await _pumpAdmin(tester, 3);
    final draft = await _enterDraft(
      tester,
      3,
      AdminUiCopy.backupMaxSizeLabelFor(AppLocale.zh),
      '2345',
    );

    await _checkPendingWriteFeedback(
      tester,
      fixture,
      draft: draft,
      submit: () async {
        final save = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveConfigBtnFor(AppLocale.zh),
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(save);
        final onPressed = button.onPressed;
        expect(onPressed, isNotNull);
        onPressed!();
        await tester.pumpAndSettle();
      },
      expected: (locale) => AdminUiCopy.formatActionError(
        ApiException('500: held synthetic write failure'),
        AdminUiCopy.actionSaveBackupConfigFor(locale),
        locale: locale,
      ),
      successful: false,
    );
  });

  testWidgets('Admin module 1 settings success follows locale while visible', (
    tester,
  ) async {
    final fixture = await _pumpAdmin(tester, 1);
    final draft = await _enterDraft(
      tester,
      1,
      AdminUiCopy.maintenanceMessageLabelFor(AppLocale.zh),
      'literal success draft',
    );

    await _checkPendingWriteFeedback(
      tester,
      fixture,
      draft: draft,
      submit: () async {
        final title = find.text(
          AdminUiCopy.maintenanceModeTitleFor(AppLocale.zh),
        );
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        await tester.tap(title);
        await tester.pumpAndSettle();
      },
      expected: AdminUiCopy.settingsUpdatedFor,
      successful: true,
    );
  });

  testWidgets('Admin module 2 AI save success follows locale while visible', (
    tester,
  ) async {
    final fixture = await _pumpAdmin(tester, 2);
    const text = 'literal AI success draft';
    final draft = await _enterDraft(
      tester,
      2,
      AdminUiCopy.aiModelLabelFor(AppLocale.zh),
      text,
    );

    await _checkPendingWriteFeedback(
      tester,
      fixture,
      draft: draft,
      submit: () async {
        final save = find.widgetWithText(
          FilledButton,
          AdminUiCopy.saveFor(AppLocale.zh),
        );
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
      },
      expected: AdminUiCopy.aiConfigSavedFor,
      successful: true,
      reloadsAfterSuccess: true,
    );
  });

  testWidgets(
    'Admin module 3 backup save success follows locale while visible',
    (tester) async {
      final fixture = await _pumpAdmin(tester, 3);
      const text = '2345';
      final draft = await _enterDraft(
        tester,
        3,
        AdminUiCopy.backupMaxSizeLabelFor(AppLocale.zh),
        text,
      );

      await _checkPendingWriteFeedback(
        tester,
        fixture,
        draft: draft,
        submit: () async {
          final save = find.widgetWithText(
            FilledButton,
            AdminUiCopy.saveConfigBtnFor(AppLocale.zh),
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          await tester.tap(save);
          await tester.pumpAndSettle();
        },
        expected: AdminUiCopy.backupConfigSavedFor,
        successful: true,
        reloadsAfterSuccess: true,
      );
    },
  );
}

Future<void> _checkPendingWriteFeedback(
  WidgetTester tester,
  _AdminWriteFixture fixture, {
  required _FieldDraft draft,
  required Future<void> Function() submit,
  required String Function(AppLocale locale) expected,
  required bool successful,
  bool reloadsAfterSuccess = false,
}) async {
  final requestsBefore = fixture.requests.length;
  await submit();
  expect(fixture.writeRequests, hasLength(1));
  expect(fixture.requests, hasLength(requestsBefore + 1));
  final requestsWhilePending = List<String>.of(fixture.requests);
  _expectDraft(draft);

  I18n.setLocale(AppLocale.en);
  await tester.pumpAndSettle();
  _expectDraft(draft);
  expect(fixture.requests, requestsWhilePending);

  fixture.writeResponse.complete(
    successful
        ? http.Response('{}', 200, headers: _jsonHeaders)
        : http.Response(
            jsonEncode({'detail': 'held synthetic write failure'}),
            500,
            headers: _jsonHeaders,
          ),
  );
  await tester.pumpAndSettle();
  final requestsAfterCompletion = List<String>.of(fixture.requests);
  if (reloadsAfterSuccess) {
    expect(
      requestsAfterCompletion.skip(requestsWhilePending.length),
      isNotEmpty,
    );
    expect(
      requestsAfterCompletion.skip(requestsWhilePending.length),
      everyElement(startsWith('GET ')),
    );
  } else {
    expect(fixture.requests, requestsWhilePending);
  }
  _expectSnack(tester, expected(AppLocale.en));
  if (reloadsAfterSuccess) {
    expect(draft.controller.text, draft.text);
  } else {
    _expectDraft(draft);
  }
  final selectionAfterCompletion = draft.controller.selection;
  expect(fixture.writeRequests, hasLength(1));

  for (final locale in [AppLocale.zh, AppLocale.en]) {
    I18n.setLocale(locale);
    await tester.pumpAndSettle();
    _expectSnack(tester, expected(locale));
    _expectDraft(draft, selection: selectionAfterCompletion);
    expect(fixture.requests, requestsAfterCompletion);
    expect(fixture.writeRequests, hasLength(1));
  }
}

Future<_FieldDraft> _enterDraft(
  WidgetTester tester,
  int moduleIndex,
  String fieldLabel,
  String text,
) async {
  final module = find.byKey(ValueKey('admin-${_moduleName(moduleIndex)}-0'));
  final scrollable = find
      .descendant(of: module, matching: find.byType(Scrollable))
      .first;
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.labelText == fieldLabel,
  );
  await tester.scrollUntilVisible(field, 180, scrollable: scrollable);
  await tester.enterText(field, text);
  final controller = tester.widget<TextField>(field).controller!;
  final draftSelection = TextSelection(
    baseOffset: 1,
    extentOffset: text.length - 1,
  );
  controller.selection = draftSelection;
  return _FieldDraft(text, controller, draftSelection);
}

void _expectDraft(_FieldDraft draft, {TextSelection? selection}) {
  expect(draft.controller.text, draft.text);
  expect(draft.controller.selection, selection ?? draft.selection);
}

void _expectSnack(WidgetTester tester, String expected) {
  expect(
    find.descendant(
      of: find.byType(SnackBar).last,
      matching: find.text(expected),
    ),
    findsOneWidget,
  );
}

String _moduleName(int index) => switch (index) {
  1 => 'settings',
  2 => 'ai',
  3 => 'backup',
  _ => throw ArgumentError.value(index, 'index'),
};

const _jsonHeaders = {'content-type': 'application/json'};

Future<_AdminWriteFixture> _pumpAdmin(
  WidgetTester tester,
  int moduleIndex,
) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final fixture = _AdminWriteFixture();
  final auth = _AdminAuth(fixture.apiClient);
  final ai = AiService()..attachClient(fixture.apiClient);
  final theme = ThemeProvider();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    ai.dispose();
    theme.dispose();
    fixture.close();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: MaterialApp(
        theme: theme.brand.theme,
        home: AdminScreen(initialTabIndex: moduleIndex),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(ValueKey('admin-${_moduleName(moduleIndex)}-0')),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
  return fixture;
}

class _FieldDraft {
  const _FieldDraft(this.text, this.controller, this.selection);

  final String text;
  final TextEditingController controller;
  final TextSelection selection;
}

class _AdminWriteFixture {
  _AdminWriteFixture() {
    httpClient = MockClient(_respond);
    apiClient = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'synthetic-admin',
      httpClient: httpClient,
    );
  }

  final List<String> requests = [];
  final List<String> writeRequests = [];
  final Completer<http.Response> writeResponse = Completer<http.Response>();
  String _savedAiModel = 'server-model';
  int _savedBackupMaxSizeKb = 2048;
  late final http.Client httpClient;
  late final ApiClient apiClient;

  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    final scope = request.url.queryParameters['scope'];
    requests.add('${request.method} $path?${request.url.query}');
    if (request.method != 'GET') {
      writeRequests.add('${request.method} $path');
      final payload = jsonDecode(request.body);
      if (payload is Map<String, dynamic>) {
        final model = payload['ai_model'];
        if (model is String) _savedAiModel = model;
        final backupMaxSizeKb = payload['backup_max_size_kb'];
        if (backupMaxSizeKb is num) {
          _savedBackupMaxSizeKb = backupMaxSizeKb.toInt();
        }
      }
      return writeResponse.future;
    }

    Object body;
    if (path == '/api/admin/settings') {
      body = switch (scope) {
        'ai' => {
          'ai_enabled': false,
          'ai_base_url': 'https://api.synthetic.test',
          'ai_model': _savedAiModel,
          'ai_api_key_set': false,
          'ai_daily_quota': 0,
        },
        'backup' => {
          'backup_enabled': false,
          'backup_max_size_kb': _savedBackupMaxSizeKb,
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
          'maintenance_message': 'server maintenance text',
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
      throw StateError('Unmocked Admin fixture request: $path');
    }
    return http.Response(jsonEncode(body), 200, headers: _jsonHeaders);
  }

  void close() => httpClient.close();
}

class _AdminAuth extends AuthProvider {
  _AdminAuth(this.fixture) : super(client: fixture);

  final ApiClient fixture;

  @override
  ApiClient get client => fixture;

  @override
  AuthState get state => const AuthState(
    userId: 'synthetic-admin',
    token: 'synthetic-admin',
    isAdmin: true,
  );
}
